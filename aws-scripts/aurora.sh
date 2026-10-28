#!/bin/bash

# Crea o borra el clúster Aurora PostgreSQL y escribe aurora.properties.
# Si el clúster ya existe (los alumnos lo crearon en la versión 4.0.0), no crea otro: lo
# reutiliza, deja en lab-state.json lo que describe y escribe aurora.properties. En ese caso,
# delete no borra la base de datos, porque no es de este despliegue.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. GroupId y SubnetIds los escribió red.sh en lab-state.json.
# DBSubnetGroupName, DBClusterIdentifier, DBInstanceIdentifiers, SecretArn y
# Endpoint se escriben en lab-state.json al hacer create.
# La contraseña master la genera Aurora en Secrets Manager.
# Los nombres writer y reader indican el papel inicial de cada instancia. Tras
# un failover se intercambian los papeles, pero los nombres no cambian.
DB_CLUSTER_ID="eventhub-cluster-aurora"
DB_WRITER_ID="eventhub-aurora-writer"
DB_READER_ID="eventhub-aurora-reader"
DB_SUBNET_GROUP="eventhub-aurora-subnets"
SPRING_CONFIG_FILE="$PROJECT_ROOT/eventhub-back-springboot/src/main/resources/aurora.properties"
DB_USER="master"
DB_NAME="eventhub"
DB_ENGINE="aurora-postgresql"
DB_PORT=5432

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create # Crea el clúster Aurora con una instancia en cada zona (o reutiliza el existente) y escribe aurora.properties"
    echo "  $0 delete # Borra las instancias, el clúster, el subnet group y la regla del puerto 5432 (si lo creó create)"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

case "$ACTION" in
    create)
        if [ ! -d "$(dirname "$SPRING_CONFIG_FILE")" ]; then
            echo "Error: No existe la carpeta: $(dirname "$SPRING_CONFIG_FILE")"
            exit 1
        fi

        # El DB subnet group es la forma de AWS de pasar subnets al clúster.
        SUBNET_IDS=$(state_require SubnetIds)
        SG_ID=$(state_require GroupId)
        echo "Clúster Aurora: $DB_CLUSTER_ID"
        echo "Subnets: $SUBNET_IDS"
        echo "Grupo de seguridad: $SG_ID"

        # Si el clúster ya existe, se reutiliza. Lo habitual es que lo creara el alumno en la
        # versión 4.0.0. Se lee de él todo lo que el resto del despliegue necesita.
        EXISTING=$(aws rds describe-db-clusters --db-cluster-identifier "$DB_CLUSTER_ID" \
            --query 'DBClusters[0].[Endpoint,MasterUserSecret.SecretArn,Port,DatabaseName,DBSubnetGroup]' \
            --output text 2>/dev/null || true)
        if [ -n "$EXISTING" ] && [ "$EXISTING" != "None" ]; then
            echo "El clúster '$DB_CLUSTER_ID' ya existe: se reutiliza y no se crea otro."

            # Un clúster que no está available (por ejemplo, creándose) no sirve todavía
            aws rds wait db-cluster-available --db-cluster-identifier "$DB_CLUSTER_ID"

            read -r DB_HOST SECRET_ARN DB_PORT DB_NAME DB_SUBNET_GROUP <<< "$EXISTING"
            if [ -z "$DB_HOST" ] || [ "$DB_HOST" = "None" ]; then
                echo "Error: El clúster '$DB_CLUSTER_ID' no tiene endpoint de escritura."
                exit 1
            fi
            if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
                echo "Error: El clúster '$DB_CLUSTER_ID' no tiene secreto de usuario master gestionado por Aurora."
                exit 1
            fi
            DB_INSTANCE_IDS=$(aws rds describe-db-clusters --db-cluster-identifier "$DB_CLUSTER_ID" \
                --query 'DBClusters[0].DBClusterMembers[].DBInstanceIdentifier' --output text)

            # Las tareas se conectan desde el mismo grupo de seguridad que usa el clúster
            # (red.sh lo reutiliza). Casi siempre la regla del 5432 ya está; si falta, se añade.
            if ! RESULT=$(aws ec2 authorize-security-group-ingress \
                    --group-id "$SG_ID" \
                    --protocol tcp \
                    --port "$DB_PORT" \
                    --source-group "$SG_ID" \
                    --output text 2>&1); then
                case "$RESULT" in
                    *InvalidPermission.Duplicate*) ;;
                    *) echo "$RESULT"; exit 1 ;;
                esac
            fi

            SECRET_NAME=$(aws secretsmanager describe-secret \
                --secret-id "$SECRET_ARN" \
                --query Name \
                --output text)

            state_set DBClusterIdentifier "$DB_CLUSTER_ID"
            state_set DBSubnetGroupName "$DB_SUBNET_GROUP"
            # shellcheck disable=SC2086
            state_set_array DBInstanceIdentifiers $DB_INSTANCE_IDS
            state_set Endpoint "$DB_HOST"
            state_set SecretArn "$SECRET_ARN"
            # Marca que el clúster no lo creó este despliegue: delete conserva el clúster por defecto
            state_set AuroraExistente true

            cat > "$SPRING_CONFIG_FILE" << EOF
# Generado por aws-scripts/aurora.sh. No editar a mano.
# El secreto lo crea Aurora y aporta username y password. Spring lo importa al arrancar.
# aurora.host, aurora.port y aurora.dbname no son secretos: construyen la URL JDBC.
spring.config.import=aws-secretsmanager:${SECRET_NAME}
aurora.host=${DB_HOST}
aurora.port=${DB_PORT}
aurora.dbname=${DB_NAME}
EOF

            echo "Clúster reutilizado. Sus datos quedan en estos ficheros. Spring lee aurora.properties al arrancar; no van en el código:"
            echo "  $LAB_STATE_FILE"
            echo "  Backend (secreto y endpoint de Aurora): $SPRING_CONFIG_FILE"
            echo "Configuración de Aurora finalizada."
            exit 0
        fi

        # create-db-instance coloca cada instancia en una zona, no en una subnet.
        # Sin --availability-zone, RDS elige la zona y las dos instancias podrían
        # quedar en la misma: si cae esa zona, no habría a dónde hacer failover.
        # Por eso se consulta la zona de cada subnet de lab-state.json.
        # sort_by: el writer va siempre a la primera zona por orden alfabético.
        AZS=$(aws ec2 describe-subnets \
            --subnet-ids $SUBNET_IDS \
            --query 'sort_by(Subnets, &AvailabilityZone)[].AvailabilityZone' \
            --output text)
        read -r AZ_WRITER AZ_READER <<< "$AZS"
        if [ -z "$AZ_WRITER" ] || [ -z "$AZ_READER" ] || [ "$AZ_WRITER" = "$AZ_READER" ]; then
            echo "Error: Las subnets $SUBNET_IDS no están en dos zonas distintas: ${AZS:-ninguna}"
            exit 1
        fi
        echo "Zonas: writer en $AZ_WRITER, reader en $AZ_READER"

        echo "Creando subnet group '$DB_SUBNET_GROUP'..."

        # --subnet-ids: las dos subnets de lab-state.json, en zonas distintas.
        # $SUBNET_IDS no va entrecomillado a propósito: la CLI espera varios
        # argumentos subnet-xxxx, no una sola cadena con espacios.
        aws rds create-db-subnet-group \
            --db-subnet-group-name "$DB_SUBNET_GROUP" \
            --db-subnet-group-description "Subnets Aurora EventHub (2 primeras de la VPC)" \
            --subnet-ids $SUBNET_IDS \
            --output text >/dev/null
        state_set DBSubnetGroupName "$DB_SUBNET_GROUP"
        echo "Subnet group creado."

        echo "Abriendo el puerto PostgreSQL $DB_PORT en '$SG_ID'..."

        # --source-group: solo los miembros del grupo (las tareas del backend) pueden conectar a Aurora
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port "$DB_PORT" \
            --source-group "$SG_ID" \
            --output text >/dev/null

        echo "Creando el clúster Aurora '$DB_CLUSTER_ID'..."

        # --master-username: en Aurora PostgreSQL no puede ser admin
        # --manage-master-user-password: Aurora crea el secreto; la password no pasa por la CLI
        # --no-deletion-protection: el laboratorio puede borrar el clúster
        # --query: la respuesta ya trae el endpoint y el ARN del secreto, aunque
        # el clúster siga en creating. El DNS del endpoint no cambia después.
        CLUSTER_INFO=$(aws rds create-db-cluster \
            --db-cluster-identifier "$DB_CLUSTER_ID" \
            --engine "$DB_ENGINE" \
            --master-username "$DB_USER" \
            --manage-master-user-password \
            --database-name "$DB_NAME" \
            --port "$DB_PORT" \
            --vpc-security-group-ids "$SG_ID" \
            --db-subnet-group-name "$DB_SUBNET_GROUP" \
            --backup-retention-period 1 \
            --no-deletion-protection \
            --query '[DBCluster.Endpoint, DBCluster.MasterUserSecret.SecretArn]' \
            --output text)
        state_set DBClusterIdentifier "$DB_CLUSTER_ID"

        # --output text separa los dos valores con un tabulador
        read -r DB_HOST SECRET_ARN <<< "$CLUSTER_INFO"
        if [ -z "$DB_HOST" ] || [ "$DB_HOST" = "None" ]; then
            echo "Error: El clúster '$DB_CLUSTER_ID' no tiene endpoint de escritura."
            exit 1
        fi
        if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
            echo "Error: El clúster '$DB_CLUSTER_ID' no tiene secreto de usuario master."
            exit 1
        fi
        state_set Endpoint "$DB_HOST"
        state_set SecretArn "$SECRET_ARN"

        echo "Esperando a que el clúster esté available..."
        aws rds wait db-cluster-available --db-cluster-identifier "$DB_CLUSTER_ID"

        echo "Creando la instancia de escritura '$DB_WRITER_ID' en $AZ_WRITER..."

        # La primera instancia del clúster es la de escritura. Se espera a que
        # esté available antes de crear la réplica, para que el writer quede en
        # la zona prevista.
        # --availability-zone: zona de la primera subnet
        # --db-instance-class: clase mínima habitual de Aurora PostgreSQL
        # --no-publicly-accessible: solo se alcanza desde la VPC
        aws rds create-db-instance \
            --db-instance-identifier "$DB_WRITER_ID" \
            --db-cluster-identifier "$DB_CLUSTER_ID" \
            --engine "$DB_ENGINE" \
            --db-instance-class db.t3.medium \
            --availability-zone "$AZ_WRITER" \
            --no-publicly-accessible \
            --output text >/dev/null
        state_set_array DBInstanceIdentifiers "$DB_WRITER_ID"
        echo "Esperando a que la instancia de escritura esté available..."
        aws rds wait db-instance-available --db-instance-identifier "$DB_WRITER_ID"

        echo "Creando la réplica de lectura '$DB_READER_ID' en $AZ_READER..."

        # --availability-zone: zona de la segunda subnet, distinta de la del writer
        # --promotion-tier 0: prioridad máxima para sustituir al writer si falla
        aws rds create-db-instance \
            --db-instance-identifier "$DB_READER_ID" \
            --db-cluster-identifier "$DB_CLUSTER_ID" \
            --engine "$DB_ENGINE" \
            --db-instance-class db.t3.medium \
            --availability-zone "$AZ_READER" \
            --promotion-tier 0 \
            --no-publicly-accessible \
            --output text >/dev/null
        state_set_array DBInstanceIdentifiers "$DB_WRITER_ID" "$DB_READER_ID"
        echo "Esperando a que la réplica esté available..."
        aws rds wait db-instance-available --db-instance-identifier "$DB_READER_ID"

        # El nombre del secreto lo asigna RDS (rds!cluster-...). describe-secret no devuelve la password.
        SECRET_NAME=$(aws secretsmanager describe-secret \
            --secret-id "$SECRET_ARN" \
            --query Name \
            --output text)
        if [ -z "$SECRET_NAME" ] || [ "$SECRET_NAME" = "None" ]; then
            echo "Error: No se pudo obtener el nombre del secreto '$SECRET_ARN'."
            exit 1
        fi

        cat > "$SPRING_CONFIG_FILE" << EOF
# Generado por aws-scripts/aurora.sh. No editar a mano.
# El secreto lo crea Aurora y aporta username y password. Spring lo importa al arrancar.
# aurora.host, aurora.port y aurora.dbname no son secretos: construyen la URL JDBC.
spring.config.import=aws-secretsmanager:${SECRET_NAME}
aurora.host=${DB_HOST}
aurora.port=${DB_PORT}
aurora.dbname=${DB_NAME}
EOF

        echo "El clúster y el secreto quedan en estos ficheros. Spring lee aurora.properties al arrancar; no van en el código:"
        echo "  $LAB_STATE_FILE"
        echo "  Backend (secreto y endpoint de Aurora): $SPRING_CONFIG_FILE"
        echo "Creación de Aurora finalizada."
        ;;

    delete)

        # Borrar la base de datos no se puede deshacer: se pregunta. Por defecto se conserva el
        # clúster que ya existía antes del despliegue (lo normal, el de la versión 4.0.0) y se
        # borra el que creó este despliegue. BORRAR_AURORA=si|no responde sin preguntar, y sin
        # terminal (por ejemplo, en un script) se aplica el valor por defecto.
        if [ "$(state_get AuroraExistente)" = "true" ]; then
            ORIGEN="existía antes de este despliegue"
            POR_DEFECTO="no"
            PROMPT="¿Borrar la base de datos? [s/N] "
        else
            ORIGEN="lo creó este despliegue"
            POR_DEFECTO="si"
            PROMPT="¿Borrar la base de datos? [S/n] "
        fi
        RESPUESTA="${BORRAR_AURORA:-}"
        if [ -z "$RESPUESTA" ] && [ -t 0 ]; then
            echo "El clúster Aurora '$(state_get DBClusterIdentifier)' $ORIGEN."
            echo "Si lo borras, se pierden sus datos (no se guarda ninguna copia)."
            read -r -p "$PROMPT" RESPUESTA
        fi
        case "$RESPUESTA" in
            [sS]|[sS][iI]|[yY]|[yY][eE][sS]) BORRAR="si" ;;
            [nN]|[nN][oO]) BORRAR="no" ;;
            *) BORRAR="$POR_DEFECTO" ;;
        esac

        # La decisión la lee red.sh: el grupo de seguridad de las tareas es el de la base de datos
        if [ "$BORRAR" = "no" ]; then
            echo "El clúster '$(state_get DBClusterIdentifier)' se conserva."
            rm -f "$SPRING_CONFIG_FILE"
            tmp=$(mktemp)
            jq 'del(.DBSubnetGroupName, .DBClusterIdentifier, .DBInstanceIdentifiers, .SecretArn, .Endpoint, .AuroraExistente) | .AuroraConservada = "true"' \
                "$LAB_STATE_FILE" > "$tmp"
            mv "$tmp" "$LAB_STATE_FILE"
            echo "Aurora conservada."
            exit 0
        fi

        # IDs de lab-state.json. Nada se conserva: ni snapshot ni la regla del 5432.
        # Las instancias se borran antes que el clúster, y el subnet group cuando ya no lo usa.
        # El secreto gestionado desaparece con el clúster.
        DB_INSTANCE_IDS=$(state_require DBInstanceIdentifiers)
        DB_CLUSTER_ID=$(state_require DBClusterIdentifier)
        DB_SUBNET_GROUP=$(state_require DBSubnetGroupName)
        SG_ID=$(state_require GroupId)

        # Se piden todos los borrados y después se espera a cada uno: así se
        # borran a la vez.
        for DB_INSTANCE_ID in $DB_INSTANCE_IDS; do
            echo "Eliminando la instancia '$DB_INSTANCE_ID'..."

            # --skip-final-snapshot: no se guarda copia de la base
            aws rds delete-db-instance \
                --db-instance-identifier "$DB_INSTANCE_ID" \
                --skip-final-snapshot \
                --output text >/dev/null
        done
        for DB_INSTANCE_ID in $DB_INSTANCE_IDS; do
            echo "Esperando a que la instancia '$DB_INSTANCE_ID' se elimine..."
            aws rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE_ID"
        done

        echo "Eliminando el clúster '$DB_CLUSTER_ID' (el secreto se borra con él)..."
        aws rds delete-db-cluster \
            --db-cluster-identifier "$DB_CLUSTER_ID" \
            --skip-final-snapshot \
            --output text >/dev/null
        echo "Esperando a que el clúster se elimine..."
        aws rds wait db-cluster-deleted --db-cluster-identifier "$DB_CLUSTER_ID"

        echo "Eliminando el subnet group '$DB_SUBNET_GROUP'..."
        aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP"

        echo "Cerrando el puerto PostgreSQL $DB_PORT en '$SG_ID'..."

        # --source-group: la misma regla que abrió create
        aws ec2 revoke-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port "$DB_PORT" \
            --source-group "$SG_ID" \
            --output text >/dev/null

        rm -f "$SPRING_CONFIG_FILE"

        tmp=$(mktemp)
        jq 'del(.DBSubnetGroupName, .DBClusterIdentifier, .DBInstanceIdentifiers, .SecretArn, .Endpoint, .AuroraExistente)' \
            "$LAB_STATE_FILE" > "$tmp"
        mv "$tmp" "$LAB_STATE_FILE"
        echo "Aurora eliminada."
        ;;

    *)
        usage
        ;;
esac
