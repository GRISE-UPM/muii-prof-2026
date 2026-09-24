#!/bin/bash

# Crea o borra la instancia EC2, su IP elástica y el grupo de seguridad.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. VpcId, SubnetIds, GroupId, InstanceId, AllocationId,
# AssociationId y PublicIp se escriben en lab-state.json al hacer create.
SG_NAME="eventhub-sg"
KEY_NAME="vockey"
INSTANCE_TYPE="t2.micro"

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create # Crea la instancia, la IP elástica y el grupo de seguridad"
    echo "  $0 delete # Borra la IP, la instancia y el grupo de seguridad"
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

        # Se guardan dos: Aurora, más adelante, exige subnets en al menos dos zonas.
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

        echo "Creando grupo de seguridad '$SG_NAME'..."

        # --vpc-id: el grupo vive en la VPC por defecto
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "Permite trafico HTTP, HTTPS y SSH al servidor EC2" \
            --vpc-id "$VPC_ID" \
            --query "GroupId" \
            --output text)
        state_set GroupId "$SG_ID"
        echo "Grupo de seguridad creado (ID: $SG_ID)."

        echo "Abriendo los puertos 80 (HTTP), 443 (HTTPS) y 22 (SSH)..."

        # --cidr 0.0.0.0/0: cualquier origen. La respuesta repite la regla; se descarta.
        for port in 80 443 22; do
            aws ec2 authorize-security-group-ingress \
                --group-id "$SG_ID" \
                --protocol tcp \
                --port "$port" \
                --cidr 0.0.0.0/0 \
                --output text >/dev/null
        done

        echo "Buscando la AMI de Ubuntu 22.04..."

        # --owners: Canonical. Se queda la Jammy amd64 más reciente.
        AMI_ID=$(aws ec2 describe-images \
            --owners 099720109477 \
            --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
            --output text)
        echo "AMI: $AMI_ID"

        echo "Creando la instancia EC2..."

        # --key-name: par vockey de AWS Academy, para el SSH de los despliegues
        # --instance-type: t2.micro, el tamaño del laboratorio
        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --count 1 \
            --instance-type "$INSTANCE_TYPE" \
            --key-name "$KEY_NAME" \
            --security-group-ids "$SG_ID" \
            --query "Instances[0].InstanceId" \
            --output text)
        state_set InstanceId "$INSTANCE_ID"
        echo "Instancia creada (ID: $INSTANCE_ID)."

        echo "Reservando Elastic IP..."

        # --domain vpc: la reserva es de VPC, no de EC2-Classic
        ALLOCATION_ID=$(aws ec2 allocate-address \
            --domain vpc \
            --query "AllocationId" \
            --output text)
        state_set AllocationId "$ALLOCATION_ID"
        echo "Elastic IP reservada (AllocationId: $ALLOCATION_ID)."

        echo "Esperando a que la instancia esté running..."
        aws ec2 wait instance-running --instance-id "$INSTANCE_ID"

        echo "Asociando la Elastic IP a la instancia..."
        ASSOCIATION_ID=$(aws ec2 associate-address \
            --instance-id "$INSTANCE_ID" \
            --allocation-id "$ALLOCATION_ID" \
            --query "AssociationId" \
            --output text)
        state_set AssociationId "$ASSOCIATION_ID"

        PUBLIC_IP=$(aws ec2 describe-addresses \
            --allocation-ids "$ALLOCATION_ID" \
            --query "Addresses[0].PublicIp" \
            --output text)
        state_set PublicIp "$PUBLIC_IP"

        echo "La instancia, la IP y el grupo de seguridad quedan en lab-state.json. Nginx, el backend y el frontend los leen al desplegar; no van en el código:"
        echo "  $LAB_STATE_FILE"
        echo "  IP pública: $PUBLIC_IP"
        echo "Esperando 45 segundos para que la instancia termine de arrancar..."
        sleep 45
        echo "Creación de la instancia EC2 finalizada."
        ;;

    delete)

        # IDs de lab-state.json. La IP se suelta antes de terminar la instancia.
        # El grupo de seguridad se borra cuando la instancia ya no lo usa.
        # La VPC por defecto no es de este script: no se borra.
        ASSOCIATION_ID=$(state_require AssociationId)
        ALLOCATION_ID=$(state_require AllocationId)
        INSTANCE_ID=$(state_require InstanceId)
        SG_ID=$(state_require GroupId)

        echo "Desasociando Elastic IP '$ASSOCIATION_ID'..."
        aws ec2 disassociate-address --association-id "$ASSOCIATION_ID"

        echo "Liberando Elastic IP '$ALLOCATION_ID'..."
        aws ec2 release-address --allocation-id "$ALLOCATION_ID"

        echo "Terminando instancia '$INSTANCE_ID'..."
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --output text >/dev/null

        echo "Esperando a que la instancia termine..."
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"

        echo "Eliminando grupo de seguridad '$SG_ID'..."
        aws ec2 delete-security-group --group-id "$SG_ID"

        state_clear
        echo "Infraestructura EC2 eliminada."
        ;;

    *)
        usage
        ;;
esac
