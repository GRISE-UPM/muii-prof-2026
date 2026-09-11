#!/bin/bash

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes del laboratorio (nombres fijos; no van en lab-state.json).
# GroupId y SubnetIds se leen de lab-state.json (escritos por ec2.sh create).
# La contraseña master la genera Aurora en Secrets Manager (--manage-master-user-password).
DB_CLUSTER_ID="eventhub-cluster-aurora"
DB_INSTANCE_ID="eventhub-aurora-instance"
DB_SUBNET_GROUP="eventhub-aurora-subnets"
SPRING_CONFIG_FILE="$PROJECT_ROOT/eventhub-eventos-springboot/src/main/resources/aurora.properties"
DB_USER="master"
DB_NAME="eventhub"
DB_ENGINE="aurora-postgresql"
DB_PORT=5432

if [ -z "$1" ] || [ -n "$2" ]; then
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create"
    echo "  $0 delete"
    exit 1
fi

ACTION="$1"

case "$ACTION" in
    create)
        SPRING_CONFIG_PARENT_DIR="$(dirname "$SPRING_CONFIG_FILE")"
        if [ ! -d "$SPRING_CONFIG_PARENT_DIR" ]; then
            echo "Error: No existe la carpeta de recursos de Spring Boot: $SPRING_CONFIG_PARENT_DIR"
            exit 1
        fi

        echo "Clúster Aurora previsto: $DB_CLUSTER_ID"
        echo "Usuario master: $DB_USER (password gestionada por Aurora en Secrets Manager)"

        if aws rds describe-db-clusters --db-cluster-identifier "$DB_CLUSTER_ID" >/dev/null 2>&1; then
            echo "El clúster '$DB_CLUSTER_ID' ya existe; se reutiliza."
        else
            # SubnetIds: las dos primeras de la VPC, guardadas por ec2.sh.
            # El DB subnet group es la forma de AWS de asignarlas al cluster
            # (create-db-cluster no admite --subnet-ids).
            SUBNET_IDS=$(state_require SubnetIds)
            echo "SubnetIds desde lab-state.json: $SUBNET_IDS"

            if aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP" >/dev/null 2>&1; then
                echo "El subnet group '$DB_SUBNET_GROUP' ya existe; se reutiliza."
            else
                echo "Creando el subnet group '$DB_SUBNET_GROUP'..."
                # Parámetros:
                # --db-subnet-group-name: Nombre del grupo (Aurora exige >= 2 AZ)
                # --subnet-ids: Las dos SubnetIds de lab-state.json
                aws rds create-db-subnet-group \
                    --db-subnet-group-name "$DB_SUBNET_GROUP" \
                    --db-subnet-group-description "Subnets Aurora EventHub (2 primeras de la VPC)" \
                    --subnet-ids $SUBNET_IDS
                if [ $? -ne 0 ]; then
                    echo "Error al crear el subnet group '$DB_SUBNET_GROUP'."
                    exit 1
                fi
            fi

            # Un solo security group por ahora (EC2 + Aurora). GroupId en lab-state.json.
            echo "Usando el security group de EC2 (GroupId en lab-state.json)..."
            SG_ID=$(state_require GroupId)

            PG_RULE=$(aws ec2 describe-security-groups \
                --group-ids "$SG_ID" \
                --query "SecurityGroups[0].IpPermissions[?FromPort==\`5432\` && ToPort==\`5432\`]" \
                --output text)
            if [ -z "$PG_RULE" ]; then
                echo "Abriendo el puerto PostgreSQL 5432 en $SG_ID (tráfico desde el propio SG)..."
                # Parámetros:
                # --group-id: SG compartido con EC2
                # --source-group: La instancia EC2 del mismo SG puede conectar a Aurora
                aws ec2 authorize-security-group-ingress \
                    --group-id "$SG_ID" \
                    --protocol tcp \
                    --port "$DB_PORT" \
                    --source-group "$SG_ID"
                if [ $? -ne 0 ]; then
                    echo "Error al abrir el puerto PostgreSQL en $SG_ID."
                    exit 1
                fi
            else
                echo "El puerto 5432 ya está abierto en $SG_ID."
            fi

            echo "Creando el clúster Aurora '$DB_CLUSTER_ID' (password en Secrets Manager)..."
            # Parámetros:
            # --db-cluster-identifier: Nombre fijo del laboratorio (constante DB_CLUSTER_ID)
            # --engine: aurora-postgresql
            # --master-username: Usuario master (no puede ser 'admin' en PostgreSQL)
            # --manage-master-user-password: Aurora crea el secreto y la password; no viaja por la CLI
            # --database-name: Base inicial (coincide con dbname del secreto cuando RDS lo rellena)
            # --vpc-security-group-ids: Mismo SG que la instancia EC2
            # --db-subnet-group-name: Subnets en al menos 2 AZ
            aws rds create-db-cluster \
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
                --query 'DBCluster.DBClusterIdentifier' \
                --output text >/dev/null
            if [ $? -ne 0 ]; then
                echo "Error al crear el clúster Aurora '$DB_CLUSTER_ID'."
                exit 1
            fi

            echo "Esperando a que el clúster esté available (puede tardar varios minutos)..."
            aws rds wait db-cluster-available --db-cluster-identifier "$DB_CLUSTER_ID"
            if [ $? -ne 0 ]; then
                echo "Error: el clúster '$DB_CLUSTER_ID' no llegó a available."
                exit 1
            fi

            echo "Creando la instancia Aurora '$DB_INSTANCE_ID'..."
            # Parámetros:
            # --db-instance-identifier: Instancia de cómputo del clúster
            # --db-cluster-identifier: Clúster recién creado
            # --db-instance-class: Clase mínima habitual de Aurora PostgreSQL
            # --no-publicly-accessible: Solo accesible desde la VPC (EC2)
            aws rds create-db-instance \
                --db-instance-identifier "$DB_INSTANCE_ID" \
                --db-cluster-identifier "$DB_CLUSTER_ID" \
                --engine "$DB_ENGINE" \
                --db-instance-class db.t3.medium \
                --no-publicly-accessible \
                --query 'DBInstance.DBInstanceIdentifier' \
                --output text >/dev/null
            if [ $? -ne 0 ]; then
                echo "Error al crear la instancia Aurora '$DB_INSTANCE_ID'."
                exit 1
            fi

            echo "Esperando a que la instancia esté available (puede tardar varios minutos)..."
            aws rds wait db-instance-available --db-instance-identifier "$DB_INSTANCE_ID"
            if [ $? -ne 0 ]; then
                echo "Error: la instancia '$DB_INSTANCE_ID' no llegó a available."
                exit 1
            fi
        fi

        # El secreto lo crea Aurora. El nombre lo asigna RDS (rds!cluster-...) y el host
        # solo existe cuando el clúster ya tiene endpoint. describe-secret no devuelve la password.
        # Parámetros:
        # --query: ARN del secreto gestionado (MasterUserSecret)
        SECRET_ARN=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$DB_CLUSTER_ID" \
            --query 'DBClusters[0].MasterUserSecret.SecretArn' \
            --output text)
        if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
            echo "Error: El clúster '$DB_CLUSTER_ID' no tiene secreto de usuario master."
            exit 1
        fi

        # Parámetros:
        # --secret-id: ARN del secreto que creó Aurora
        # --query: Nombre para que Spring Boot lo importe (username, password, host, port, dbname)
        SECRET_NAME=$(aws secretsmanager describe-secret \
            --secret-id "$SECRET_ARN" \
            --query Name \
            --output text)
        if [ -z "$SECRET_NAME" ] || [ "$SECRET_NAME" = "None" ]; then
            echo "Error: No se pudo obtener el nombre del secreto '$SECRET_ARN'."
            exit 1
        fi

        echo "Secreto de Aurora: $SECRET_NAME"
        cat > "$SPRING_CONFIG_FILE" << EOF
# Generado por aws-scripts/aurora.sh. No editar a mano: se sobrescribe en cada create.
# El secreto lo crea Aurora; el host solo es válido cuando el clúster ya existe.
spring.config.import=aws-secretsmanager:${SECRET_NAME}
EOF
        echo "Escrito $SPRING_CONFIG_FILE"
        echo "Creación de Aurora finalizada."
        ;;

    delete)
        # Nombres de clúster/instancia: constantes del script (no lab-state.json).
        if aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" >/dev/null 2>&1; then
            echo "Eliminando la instancia '$DB_INSTANCE_ID'..."
            # Parámetros:
            # --skip-final-snapshot: Obligatorio en laboratorio; no se conserva snapshot
            aws rds delete-db-instance \
                --db-instance-identifier "$DB_INSTANCE_ID" \
                --skip-final-snapshot
            echo "Esperando a que la instancia se elimine..."
            aws rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE_ID"
        else
            echo "La instancia '$DB_INSTANCE_ID' no existe."
        fi

        if aws rds describe-db-clusters --db-cluster-identifier "$DB_CLUSTER_ID" >/dev/null 2>&1; then
            echo "Eliminando el clúster '$DB_CLUSTER_ID'..."
            aws rds delete-db-cluster \
                --db-cluster-identifier "$DB_CLUSTER_ID" \
                --skip-final-snapshot
            echo "Esperando a que el clúster se elimine..."
            aws rds wait db-cluster-deleted --db-cluster-identifier "$DB_CLUSTER_ID"
        else
            echo "El clúster '$DB_CLUSTER_ID' no existe."
        fi

        if aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP" >/dev/null 2>&1; then
            echo "Eliminando el subnet group '$DB_SUBNET_GROUP'..."
            aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP"
        fi

        rm -f "$SPRING_CONFIG_FILE"
        echo "Eliminación de Aurora finalizada."
        ;;

    *)
        echo "Uso: $0 {create|delete}"
        echo ""
        echo "Ejemplos:"
        echo "  $0 create"
        echo "  $0 delete"
        exit 1
        ;;
esac
