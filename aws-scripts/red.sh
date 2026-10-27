#!/bin/bash

# Crea o borra la red de eventhub: subnets de la VPC por defecto y los dos grupos de seguridad.
# Si ya existe el clúster Aurora de los alumnos (versión 4.0.0), las tareas reutilizan su grupo
# de seguridad en lugar de crear otro, y delete no lo borra.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. VpcId, SubnetIds, GroupId y AlbGroupId se escriben en lab-state.json al hacer create.
# eventhub-sg: tareas de ECS y clúster Aurora. eventhub-alb-sg: balanceador de carga.
SG_NAME="eventhub-sg"
ALB_SG_NAME="eventhub-alb-sg"
BACK_PORT=8080
DB_CLUSTER_ID="eventhub-cluster-aurora"

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create # Obtiene la VPC y dos subnets, y crea los grupos de seguridad"
    echo "  $0 delete # Borra los grupos de seguridad"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

case "$ACTION" in
    create)
        echo "Obteniendo la VPC por defecto..."

        # AWS Academy ya tiene una VPC default. Este script no la crea.
        VPC_ID=$(aws ec2 describe-vpcs \
            --filters Name=isDefault,Values=true \
            --query 'Vpcs[0].VpcId' \
            --output text)
        if [ -z "$VPC_ID" ] || [ "$VPC_ID" = "None" ]; then
            echo "Error: No se encontró una VPC por defecto."
            exit 1
        fi
        state_set VpcId "$VPC_ID"
        echo "VPC por defecto: $VPC_ID"

        echo "Obteniendo subnets de la VPC..."

        # Se guardan dos, en zonas distintas: el balanceador, las tareas y Aurora
        # exigen al menos dos zonas.
        ALL_SUBNET_IDS=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=$VPC_ID" \
            --query 'Subnets[].SubnetId' \
            --output text)
        SUBNET_1=$(echo "$ALL_SUBNET_IDS" | awk '{print $1}')
        SUBNET_2=$(echo "$ALL_SUBNET_IDS" | awk '{print $2}')
        if [ -z "$SUBNET_1" ] || [ -z "$SUBNET_2" ]; then
            echo "Error: Hacen falta al menos 2 subnets en la VPC $VPC_ID; encontradas: ${ALL_SUBNET_IDS:-ninguna}"
            exit 1
        fi
        state_set_array SubnetIds "$SUBNET_1" "$SUBNET_2"
        echo "Subnets: $SUBNET_1 $SUBNET_2"

        echo "Creando el grupo de seguridad del balanceador '$ALB_SG_NAME'..."

        # --vpc-id: el grupo vive en la VPC por defecto
        ALB_SG_ID=$(aws ec2 create-security-group \
            --group-name "$ALB_SG_NAME" \
            --description "Balanceador de eventhub: HTTP y HTTPS desde Internet" \
            --vpc-id "$VPC_ID" \
            --query "GroupId" \
            --output text)
        state_set AlbGroupId "$ALB_SG_ID"

        # El balanceador es el único punto de entrada: sin CloudFront, acepta HTTP (80)
        # y HTTPS (443) desde cualquier origen. El 80 solo redirige al 443.
        for PORT in 80 443; do
            aws ec2 authorize-security-group-ingress \
                --group-id "$ALB_SG_ID" \
                --protocol tcp \
                --port "$PORT" \
                --cidr 0.0.0.0/0 \
                --output text >/dev/null
        done
        echo "Grupo del balanceador creado (ID: $ALB_SG_ID): puertos 80 y 443 abiertos a Internet."

        # Si el clúster Aurora ya existe, su grupo de seguridad es el de las tareas: así llegan al
        # puerto 5432 sin tocar nada del clúster. previo.sh ya comprobó que no tiene reglas
        # abiertas a Internet.
        SG_ID=$(aws rds describe-db-clusters --db-cluster-identifier "$DB_CLUSTER_ID" \
            --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
            --output text 2>/dev/null || true)
        if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
            echo "El clúster '$DB_CLUSTER_ID' ya existe: las tareas reutilizan su grupo de seguridad ($SG_ID)."
            state_set GroupId "$SG_ID"
            state_set GroupExistente true
        else
            echo "Creando el grupo de seguridad de las tareas '$SG_NAME'..."

            # El mismo grupo alojará después el clúster Aurora (aurora.sh)
            SG_ID=$(aws ec2 create-security-group \
                --group-name "$SG_NAME" \
                --description "Tareas de ECS y cluster Aurora de eventhub" \
                --vpc-id "$VPC_ID" \
                --query "GroupId" \
                --output text)
            state_set GroupId "$SG_ID"
        fi

        # --source-group: al puerto de Spring Boot solo llega el balanceador.
        # aurora.sh abre después el 5432 dentro de este mismo grupo.
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port "$BACK_PORT" \
            --source-group "$ALB_SG_ID" \
            --output text >/dev/null
        echo "Grupo de las tareas listo (ID: $SG_ID): puerto $BACK_PORT abierto al balanceador."

        echo "La VPC, las subnets y los grupos de seguridad quedan en lab-state.json:"
        echo "  $LAB_STATE_FILE"
        echo "Creación de la red finalizada."
        ;;

    delete)

        # Primero el grupo de las tareas, que tiene una regla que apunta al del balanceador.
        # Las interfaces de red de las tareas y del balanceador tardan en liberarse
        # después de borrarlos: si el grupo sigue en uso, se reintenta.
        # La VPC por defecto no es de este script: no se borra.
        # Si el grupo de las tareas es el del clúster Aurora que ya existía, no se borra (lo usa
        # la base de datos): solo se quita la regla del 8080, para poder borrar el del balanceador.
        SG_ID=$(state_require GroupId)
        ALB_SG_ID=$(state_require AlbGroupId)

        if [ "$(state_get GroupExistente)" = "true" ]; then
            echo "El grupo '$SG_ID' lo usa la base de datos: se conserva y se retira su regla del puerto $BACK_PORT."
            aws ec2 revoke-security-group-ingress \
                --group-id "$SG_ID" \
                --protocol tcp \
                --port "$BACK_PORT" \
                --source-group "$ALB_SG_ID" \
                --output text >/dev/null
            GROUPS_TO_DELETE="$ALB_SG_ID"
        else
            GROUPS_TO_DELETE="$SG_ID $ALB_SG_ID"
        fi

        for GROUP in $GROUPS_TO_DELETE; do
            echo "Eliminando grupo de seguridad '$GROUP'..."
            for intento in $(seq 1 20); do
                if aws ec2 delete-security-group --group-id "$GROUP" 2>/dev/null; then
                    break
                fi
                if [ "$intento" -eq 20 ]; then
                    echo "Error: No se pudo borrar el grupo '$GROUP': sigue en uso."
                    exit 1
                fi
                echo "  El grupo sigue en uso; se reintenta en 15 segundos..."
                sleep 15
            done
        done

        tmp=$(mktemp)
        jq 'del(.VpcId, .SubnetIds, .GroupId, .AlbGroupId, .GroupExistente)' "$LAB_STATE_FILE" > "$tmp"
        mv "$tmp" "$LAB_STATE_FILE"
        echo "Red eliminada."
        ;;

    *)
        usage
        ;;
esac
