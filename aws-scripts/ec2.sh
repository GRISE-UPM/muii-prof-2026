#!/bin/bash

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=jq-functions.sh
source "$SCRIPT_DIR/jq-functions.sh"

# Configuración por defecto (constantes del laboratorio; no van en lab-state.json)
SG_NAME="eventhub-sg"
KEY_NAME="vockey"
INSTANCE_TYPE="t2.micro"

# Funcion para mostrar la ayuda
usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create"
    echo "  $0 delete"
    exit 1
}

# Validar que se reciba exactamente un parametro
if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

case "$ACTION" in
    create)
        echo "Creando la infraestructura EC2."

        # Creación del grupo de seguridad
        echo "Creando Grupo de Seguridad."
        # Parámetros:
        # --group-name: Nombre del security group que se creara en AWS
        # --description: Texto descriptivo visible en la consola de EC2
        # --query: Extrae unicamente el valor del campo "GroupId" de la respuesta JSON
        # --output: Devuelve el resultado en texto plano sin comillas para asignarlo a la variable
        SG_ID=$(aws ec2 create-security-group \
            --group-name "$SG_NAME" \
            --description "Permite trafico HTTP, HTTPS y SSH al servidor EC2" \
            --query "GroupId" \
            --output text)

        if [ -z "$SG_ID" ]; then
            echo "Error al crear el Grupo de Seguridad."
            exit 1
        fi
        state_set GroupId "$SG_ID"

        # Regla HTTP (Puerto 80)
        # Parámetros:
        # --group-id: Identificador del security group al que se anade la regla
        # --protocol: Protocolo de red permitido (tcp)
        # --port: Puerto de entrada que se abre
        # --cidr: Rango de direcciones IP autorizadas (0.0.0.0/0 = cualquier origen)
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0

        # Regla HTTPS (Puerto 443)
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 443 \
            --cidr 0.0.0.0/0

        # Regla SSH (Puerto 22)
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0

        # Obtener la AMI de Ubuntu 22.04 LTS mas reciente
        # Parámetros:
        # --owners: Identificador de Canonical, publicador oficial de las AMI de Ubuntu
        # --filters: Restringe el listado a Ubuntu 22.04 LTS amd64 con virtualizacion HVM
        # --query: Ordena por fecha y extrae el ImageId de la AMI mas reciente
        # --output: Devuelve el resultado en texto plano
        AMI_ID=$(aws ec2 describe-images \
            --owners 099720109477 \
            --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
            --output text)

        # Creación de la instancia EC2
        echo "Creación de la instancia EC2"
        # Parámetros:
        # --image-id: AMI de Ubuntu que se utilizara como disco de arranque
        # --count: Numero de instancias a lanzar
        # --instance-type: Tamano de la maquina virtual (t2.micro en AWS Academy)
        # --key-name: Par de claves SSH (vockey) para acceder a la instancia
        # --security-group-ids: Security group que abre HTTP, HTTPS y SSH
        # --query: Extrae el InstanceId de la primera instancia creada
        # --output: Devuelve el resultado en texto plano
        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --count 1 \
            --instance-type "$INSTANCE_TYPE" \
            --key-name "$KEY_NAME" \
            --security-group-ids "$SG_ID" \
            --query "Instances[0].InstanceId" \
            --output text)
        state_set InstanceId "$INSTANCE_ID"

        # Reserva de una IP estática (Elastic IP)
        echo "Reservando Elastic IP..."
        # Parámetros:
        # --domain: Reserva la IP en una VPC (obligatorio en cuentas actuales)
        # --query: Extrae el AllocationId necesario para asociar la IP despues
        # --output: Devuelve el resultado en texto plano
        ALLOCATION_ID=$(aws ec2 allocate-address \
            --domain vpc \
            --query "AllocationId" \
            --output text)
        state_set AllocationId "$ALLOCATION_ID"

        echo "Esperando que la instancia cambie a estado running..."
        # Parámetros:
        # --instance-id: Identificador de la instancia cuyo estado se espera
        aws ec2 wait instance-running \
            --instance-id "$INSTANCE_ID"

        echo "Asociando Elastic IP a la instancia..."
        # Parámetros:
        # --instance-id: Instancia a la que se liga la Elastic IP
        # --allocation-id: Reserva de IP publica obtenida en el paso anterior
        # --query: AssociationId para poder desasociar en delete sin consultar AWS
        ASSOCIATION_ID=$(aws ec2 associate-address \
            --instance-id "$INSTANCE_ID" \
            --allocation-id "$ALLOCATION_ID" \
            --query "AssociationId" \
            --output text)
        state_set AssociationId "$ASSOCIATION_ID"

        # Parámetros:
        # --allocation-ids: Identificador de la Elastic IP cuya direccion se consulta
        # --query: Extrae la direccion IPv4 publica
        # --output: Devuelve el resultado en texto plano
        # PublicIp: comodidad para nginx/back/front; tambien se obtiene con
        # describe-addresses --allocation-ids (AllocationId).
        PUBLIC_IP=$(aws ec2 describe-addresses \
            --allocation-ids "$ALLOCATION_ID" \
            --query "Addresses[0].PublicIp" \
            --output text)
        state_set PublicIp "$PUBLIC_IP"

        echo "Instancia activa en la IP fija: $PUBLIC_IP"
        echo "Estado del laboratorio: $LAB_STATE_FILE"
        echo "Esperando 45 segundos para completar la inicializacion"
        sleep 45

        echo "Creación de instancia EC2 finalizada."
        ;;

    delete)
        echo "Eliminando infraestructura EC2 segun $LAB_STATE_FILE..."

        INSTANCE_ID=$(state_get InstanceId)
        ALLOCATION_ID=$(state_get AllocationId)
        ASSOCIATION_ID=$(state_get AssociationId)
        SG_ID=$(state_get GroupId)

        if [ -n "$ASSOCIATION_ID" ]; then
            echo "Desasociando Elastic IP (AssociationId=$ASSOCIATION_ID)..."
            aws ec2 disassociate-address --association-id "$ASSOCIATION_ID" 2>/dev/null || true
        fi

        if [ -n "$ALLOCATION_ID" ]; then
            echo "Liberando Elastic IP (AllocationId=$ALLOCATION_ID)..."
            aws ec2 release-address --allocation-id "$ALLOCATION_ID" 2>/dev/null || true
        fi

        if [ -n "$INSTANCE_ID" ]; then
            echo "Terminando instancia $INSTANCE_ID..."
            aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
            echo "Esperando a que la instancia finalice completamente..."
            aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
        else
            echo "No hay InstanceId en lab-state.json."
        fi

        if [ -n "$SG_ID" ]; then
            echo "Eliminando Grupo de Seguridad '$SG_NAME' ($SG_ID)..."
            aws ec2 delete-security-group --group-id "$SG_ID"
            if [ $? -eq 0 ]; then
                echo "Infraestructura liberada correctamente de AWS."
            else
                echo "Ocurrio un error al eliminar el Grupo de Seguridad."
            fi
        else
            echo "No hay GroupId en lab-state.json."
        fi

        state_clear
        echo "Eliminado $LAB_STATE_FILE"
        ;;

    *)
        usage
        ;;
esac
