#!/bin/bash

# Crea o borra el Application Load Balancer, que es el único punto de entrada: sirve el frontend
# y reparte /api/* entre las tareas del backend. El HTTPS lo pone un certificado autofirmado
# que se importa en ACM, porque el laboratorio no permite CloudFront ni tiene dominio propio.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. LoadBalancerArn, LoadBalancerDns, TargetGroupArn, FrontTargetGroupArn,
# CertificateArn, ListenerArn y HttpListenerArn se escriben en lab-state.json al hacer create.
ALB_NAME="eventhub-alb"
BACK_TARGET_GROUP_NAME="eventhub-back-tg"
FRONT_TARGET_GROUP_NAME="eventhub-front-tg"
APP_PORT=8080

# Ruta de salud de Spring Boot Actuator. liveness no consulta la base de datos:
# durante un failover de Aurora, las tareas no se retiran del balanceador.
BACK_HEALTH_PATH="/actuator/health/liveness"

# Nginx responde 200 en la raíz mientras esté vivo.
FRONT_HEALTH_PATH="/"

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create # Crea el balanceador, dos grupos de destino, el certificado y los listeners"
    echo "  $0 delete # Borra los listeners, el balanceador, los grupos de destino y el certificado"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

case "$ACTION" in
    create)
        if ! command -v openssl >/dev/null 2>&1; then
            echo "Error: Falta openssl, que genera el certificado autofirmado."
            exit 1
        fi

        # VpcId, SubnetIds y AlbGroupId los escribió red.sh en lab-state.json.
        VPC_ID=$(state_require VpcId)
        SUBNET_IDS=$(state_require SubnetIds)
        ALB_SG_ID=$(state_require AlbGroupId)

        echo "Creando el balanceador '$ALB_NAME'..."

        # --type application: balanceador de capa 7 (HTTP)
        # --scheme internet-facing: el navegador llega a él por Internet
        # --subnets: dos zonas; $SUBNET_IDS va sin comillas a propósito (dos argumentos)
        # --security-groups: eventhub-alb-sg, que admite HTTP y HTTPS desde Internet
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

        echo "Creando el grupo de destino del backend '$BACK_TARGET_GROUP_NAME'..."

        # --port: puerto de Spring Boot en cada tarea
        # --target-type ip: Fargate registra cada tarea por su IP privada
        # --health-check-*: una consulta cada 15 s; 2 aciertos seguidos dan la tarea
        #   por sana, y 3 fallos, por enferma: deja de recibir peticiones
        BACK_TG_ARN=$(aws elbv2 create-target-group \
            --name "$BACK_TARGET_GROUP_NAME" \
            --protocol HTTP \
            --port "$APP_PORT" \
            --vpc-id "$VPC_ID" \
            --target-type ip \
            --health-check-path "$BACK_HEALTH_PATH" \
            --health-check-interval-seconds 15 \
            --healthy-threshold-count 2 \
            --unhealthy-threshold-count 3 \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text)
        state_set TargetGroupArn "$BACK_TG_ARN"

        echo "Creando el grupo de destino del frontend '$FRONT_TARGET_GROUP_NAME'..."

        # Igual que el del backend, con la comprobación de salud sobre la raíz de Nginx
        FRONT_TG_ARN=$(aws elbv2 create-target-group \
            --name "$FRONT_TARGET_GROUP_NAME" \
            --protocol HTTP \
            --port "$APP_PORT" \
            --vpc-id "$VPC_ID" \
            --target-type ip \
            --health-check-path "$FRONT_HEALTH_PATH" \
            --health-check-interval-seconds 15 \
            --healthy-threshold-count 2 \
            --unhealthy-threshold-count 3 \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text)
        state_set FrontTargetGroupArn "$FRONT_TG_ARN"

        echo "Generando e importando el certificado autofirmado..."

        # Sin dominio propio no hay certificado válido: ACM solo emite certificados públicos
        # para dominios cuya propiedad se demuestra, y el nombre del ALB no es nuestro.
        # Un certificado autofirmado cifra igual, pero el navegador avisa de que no puede
        # verificarlo y hay que aceptarlo. Cognito solo exige que la URL sea HTTPS.
        # -subj y subjectAltName: el nombre DNS del balanceador, que es el que ve el navegador
        CERT_DIR=$(mktemp -d)
        openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
            -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
            -subj "/CN=$ALB_DNS" -addext "subjectAltName=DNS:$ALB_DNS" 2>/dev/null
        CERT_ARN=$(aws acm import-certificate \
            --certificate "fileb://$CERT_DIR/cert.pem" \
            --private-key "fileb://$CERT_DIR/key.pem" \
            --query 'CertificateArn' \
            --output text)
        rm -rf "$CERT_DIR"
        state_set CertificateArn "$CERT_ARN"

        echo "Creando el listener HTTPS:443..."

        # El tráfico llega al balanceador por HTTPS y se reenvía a las tareas por HTTP.
        # --certificates: el certificado importado
        # --default-actions forward: todo lo que no es /api/* va al frontend
        LISTENER_ARN=$(aws elbv2 create-listener \
            --load-balancer-arn "$ALB_ARN" \
            --protocol HTTPS \
            --port 443 \
            --certificates "CertificateArn=$CERT_ARN" \
            --default-actions "Type=forward,TargetGroupArn=$FRONT_TG_ARN" \
            --query 'Listeners[0].ListenerArn' \
            --output text)
        state_set ListenerArn "$LISTENER_ARN"

        echo "Creando la regla /api/* del listener..."

        # Las reglas se evalúan por prioridad antes de la acción por defecto.
        # path-pattern /api/*: las peticiones a la API van al grupo del backend
        aws elbv2 create-rule \
            --listener-arn "$LISTENER_ARN" \
            --priority 10 \
            --conditions "Field=path-pattern,Values=/api/*" \
            --actions "Type=forward,TargetGroupArn=$BACK_TG_ARN" \
            --output text >/dev/null

        echo "Creando el listener HTTP:80..."

        # El 80 no sirve nada: redirige al 443 con un 301, conservando la ruta y los parámetros
        HTTP_LISTENER_ARN=$(aws elbv2 create-listener \
            --load-balancer-arn "$ALB_ARN" \
            --protocol HTTP \
            --port 80 \
            --default-actions 'Type=redirect,RedirectConfig={Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' \
            --query 'Listeners[0].ListenerArn' \
            --output text)
        state_set HttpListenerArn "$HTTP_LISTENER_ARN"

        echo "Esperando a que el balanceador esté activo..."
        aws elbv2 wait load-balancer-available --load-balancer-arns "$ALB_ARN"

        echo "El balanceador, sus grupos de destino y el certificado quedan en lab-state.json. back.sh y front.sh registran ahí las tareas:"
        echo "  $LAB_STATE_FILE"
        echo "  https://$ALB_DNS"
        echo "Creación del balanceador finalizada."
        ;;

    delete)

        # Los listeners se borran antes que el balanceador (la regla /api/* se va con el
        # listener HTTPS). Los grupos de destino y el certificado, cuando ya no los usa
        # ningún listener.
        HTTP_LISTENER_ARN=$(state_require HttpListenerArn)
        LISTENER_ARN=$(state_require ListenerArn)
        ALB_ARN=$(state_require LoadBalancerArn)
        BACK_TG_ARN=$(state_require TargetGroupArn)
        FRONT_TG_ARN=$(state_require FrontTargetGroupArn)
        CERT_ARN=$(state_require CertificateArn)

        echo "Eliminando los listeners..."
        aws elbv2 delete-listener --listener-arn "$HTTP_LISTENER_ARN"
        aws elbv2 delete-listener --listener-arn "$LISTENER_ARN"

        echo "Eliminando el balanceador..."
        aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
        aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"

        echo "Eliminando los grupos de destino..."
        aws elbv2 delete-target-group --target-group-arn "$BACK_TG_ARN"
        aws elbv2 delete-target-group --target-group-arn "$FRONT_TG_ARN"

        # El certificado sigue en uso unos instantes después de borrar el balanceador
        echo "Eliminando el certificado..."
        for intento in $(seq 1 10); do
            if aws acm delete-certificate --certificate-arn "$CERT_ARN" 2>/dev/null; then
                break
            fi
            if [ "$intento" -eq 10 ]; then
                echo "Error: No se pudo borrar el certificado '$CERT_ARN': sigue en uso."
                exit 1
            fi
            echo "  El certificado sigue en uso; se reintenta en 10 segundos..."
            sleep 10
        done

        tmp=$(mktemp)
        jq 'del(.LoadBalancerArn, .LoadBalancerDns, .TargetGroupArn, .FrontTargetGroupArn, .CertificateArn, .ListenerArn, .HttpListenerArn)' \
            "$LAB_STATE_FILE" > "$tmp"
        mv "$tmp" "$LAB_STATE_FILE"
        echo "Balanceador eliminado."
        ;;

    *)
        usage
        ;;
esac
