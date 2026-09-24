#!/bin/bash

# Crea o borra el clúster Aurora PostgreSQL y escribe aurora.properties.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. GroupId y SubnetIds los escribió ec2.sh en lab-state.json.
# La contraseña master la genera Aurora en Secrets Manager.
DB_CLUSTER_ID="eventhub-cluster-aurora"
DB_INSTANCE_ID="eventhub-aurora-instance"
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
    echo "  $0 create # Crea el clúster Aurora y escribe aurora.properties"
    echo "  $0 delete # Borra el clúster, el subnet group y la regla del puerto 5432"
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

        echo "Creando subnet group '$DB_SUBNET_GROUP'..."

        # --subnet-ids: las dos subnets de lab-state.json, en zonas distintas.
        # Sin comillas a propósito: cada subnet llega a la CLI como un argumento.
        aws rds create-db-subnet-group \
            --db-subnet-group-name "$DB_SUBNET_GROUP" \
            --db-subnet-group-description "Subnets Aurora EventHub (2 primeras de la VPC)" \
            --subnet-ids $SUBNET_IDS \
            --output text >/dev/null
        echo "Subnet group creado."

        echo "Abriendo el puerto PostgreSQL $DB_PORT en '$SG_ID'..."

        # --source-group: solo la instancia del mismo grupo puede conectar a Aurora
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
            --output text >/dev/null
        echo "Esperando a que el clúster esté available..."
        aws rds wait db-cluster-available --db-cluster-identifier "$DB_CLUSTER_ID"

        echo "Creando la instancia Aurora '$DB_INSTANCE_ID'..."

        # --db-instance-class: clase mínima habitual de Aurora PostgreSQL
        # --no-publicly-accessible: solo se alcanza desde la VPC
        aws rds create-db-instance \
            --db-instance-identifier "$DB_INSTANCE_ID" \
            --db-cluster-identifier "$DB_CLUSTER_ID" \
            --engine "$DB_ENGINE" \
            --db-instance-class db.t3.medium \
            --no-publicly-accessible \
            --output text >/dev/null
        echo "Esperando a que la instancia esté available..."
        aws rds wait db-instance-available --db-instance-identifier "$DB_INSTANCE_ID"

        # El nombre del secreto lo asigna RDS (rds!cluster-...). describe-secret no devuelve la password.
        SECRET_ARN=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$DB_CLUSTER_ID" \
            --query 'DBClusters[0].MasterUserSecret.SecretArn' \
            --output text)
        if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
            echo "Error: El clúster '$DB_CLUSTER_ID' no tiene secreto de usuario master."
            exit 1
        fi

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
# El secreto lo crea Aurora. Spring lo importa al arrancar.
spring.config.import=aws-secretsmanager:${SECRET_NAME}
EOF

        echo "El clúster y el secreto quedan en este fichero. Spring lo lee al arrancar; no van en el código:"
        echo "  Backend (secreto de Aurora): $SPRING_CONFIG_FILE"
        echo "Creación de Aurora finalizada."
        ;;

    delete)

        # Nombres fijos del script. Nada se conserva: ni snapshot ni la regla del 5432.
        # La instancia se borra antes que el clúster, y el subnet group cuando ya no lo usa.
        # El secreto gestionado desaparece con el clúster.
        echo "Eliminando la instancia '$DB_INSTANCE_ID'..."

        # --skip-final-snapshot: no se guarda copia de la base
        aws rds delete-db-instance \
            --db-instance-identifier "$DB_INSTANCE_ID" \
            --skip-final-snapshot \
            --output text >/dev/null
        echo "Esperando a que la instancia se elimine..."
        aws rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE_ID"

        echo "Eliminando el clúster '$DB_CLUSTER_ID' (el secreto se borra con él)..."
        aws rds delete-db-cluster \
            --db-cluster-identifier "$DB_CLUSTER_ID" \
            --skip-final-snapshot \
            --output text >/dev/null
        echo "Esperando a que el clúster se elimine..."
        aws rds wait db-cluster-deleted --db-cluster-identifier "$DB_CLUSTER_ID"

        echo "Eliminando el subnet group '$DB_SUBNET_GROUP'..."
        aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP"

        SG_ID=$(state_require GroupId)
        echo "Cerrando el puerto PostgreSQL $DB_PORT en '$SG_ID'..."

        # --source-group: la misma regla que abrió create
        aws ec2 revoke-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port "$DB_PORT" \
            --source-group "$SG_ID" \
            --output text >/dev/null

        rm -f "$SPRING_CONFIG_FILE"
        echo "Aurora eliminada."
        ;;

    *)
        usage
        ;;
esac
