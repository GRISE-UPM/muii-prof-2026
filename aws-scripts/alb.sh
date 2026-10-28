#!/bin/bash

# Crea o borra el Application Load Balancer que reparte las peticiones entre las tareas del backend.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. LoadBalancerArn, LoadBalancerDns, TargetGroupArn y ListenerArn se
# escriben en lab-state.json al hacer create.
ALB_NAME="eventhub-alb"
TARGET_GROUP_NAME="eventhub-back-tg"
BACK_PORT=8080

# Ruta de salud de Spring Boot Actuator. liveness no consulta la base de datos:
# durante un failover de Aurora, las tareas no se retiran del balanceador.
HEALTH_PATH="/actuator/health/liveness"

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create # Crea el balanceador, su grupo de destino y el listener HTTP"
    echo "  $0 delete # Borra el listener, el balanceador y el grupo de destino"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

case "$ACTION" in
    create)
        # VpcId, SubnetIds y AlbGroupId los escribió red.sh en lab-state.json.
        VPC_ID=$(state_require VpcId)
        SUBNET_IDS=$(state_require SubnetIds)
        ALB_SG_ID=$(state_require AlbGroupId)

        echo "Creando el balanceador '$ALB_NAME'..."

        # --type application: balanceador de capa 7 (HTTP)
        # --scheme internet-facing: Nginx llega a él por su dirección pública (el nombre DNS del balanceador)
        # --subnets: dos zonas; $SUBNET_IDS va sin comillas a propósito (dos argumentos)
        # --security-groups: eventhub-alb-sg, que solo admitirá a la instancia con Nginx (nginx.sh)
        ALB_INFO=$(aws elbv2 create-load-balancer \
            --name "$ALB_NAME" \
            --type application \
            --scheme internet-facing \
            --subnets $SUBNET_IDS \
            --security-groups "$ALB_SG_ID" \
            --query 'LoadBalancers[0].[LoadBalancerArn,DNSName]' \
            --output text)

        # --output text separa los dos valores con un tabulador
        read -r ALB_ARN ALB_DNS <<< "$ALB_INFO"
        state_set LoadBalancerArn "$ALB_ARN"
        state_set LoadBalancerDns "$ALB_DNS"
        echo "Balanceador creado: $ALB_DNS"

        echo "Creando el grupo de destino '$TARGET_GROUP_NAME'..."

        # --port: puerto de Spring Boot en cada tarea
        # --target-type ip: Fargate registra cada tarea por su IP privada
        # --health-check-*: una consulta cada 15 s; 2 aciertos seguidos dan la tarea
        #   por sana, y 3 fallos, por enferma: deja de recibir peticiones
        TG_ARN=$(aws elbv2 create-target-group \
            --name "$TARGET_GROUP_NAME" \
            --protocol HTTP \
            --port "$BACK_PORT" \
            --vpc-id "$VPC_ID" \
            --target-type ip \
            --health-check-path "$HEALTH_PATH" \
            --health-check-interval-seconds 15 \
            --healthy-threshold-count 2 \
            --unhealthy-threshold-count 3 \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text)
        state_set TargetGroupArn "$TG_ARN"

        echo "Creando el listener HTTP:80..."

        # HTTP y no HTTPS: el certificado lo pone Nginx (ver nginx.sh)
        # --default-actions forward: todo lo que llega al puerto 80 va al grupo de destino
        LISTENER_ARN=$(aws elbv2 create-listener \
            --load-balancer-arn "$ALB_ARN" \
            --protocol HTTP \
            --port 80 \
            --default-actions "Type=forward,TargetGroupArn=$TG_ARN" \
            --query 'Listeners[0].ListenerArn' \
            --output text)
        state_set ListenerArn "$LISTENER_ARN"

        echo "Esperando a que el balanceador esté activo..."
        aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"

        echo "El balanceador y su grupo de destino quedan en lab-state.json. back.sh registra ahí las tareas:"
        echo "  $LAB_STATE_FILE"
        echo "Creación del balanceador finalizada."
        ;;

    delete)

        # El listener se borra antes que el balanceador, y el grupo de destino cuando
        # ya no lo usa ningún listener.
        LISTENER_ARN=$(state_require ListenerArn)
        ALB_ARN=$(state_require LoadBalancerArn)
        TG_ARN=$(state_require TargetGroupArn)

        echo "Eliminando el listener..."
        aws elbv2 delete-listener --listener-arn "$LISTENER_ARN"

        echo "Eliminando el balanceador..."
        aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
        aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"

        echo "Eliminando el grupo de destino..."
        aws elbv2 delete-target-group --target-group-arn "$TG_ARN"

        tmp=$(mktemp)
        jq 'del(.LoadBalancerArn, .LoadBalancerDns, .TargetGroupArn, .ListenerArn)' "$LAB_STATE_FILE" > "$tmp"
        mv "$tmp" "$LAB_STATE_FILE"
        echo "Balanceador eliminado."
        ;;

    *)
        usage
        ;;
esac
