#!/bin/bash

# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

# Configuración del despliegue del backend Spring Boot
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"
KEY_PATH="$PROJECT_ROOT/ssh-key/labsuser.pem"
BACKEND_PATH="$PROJECT_ROOT/eventhub-eventos-springboot"

usage() {
    echo "Uso: $0 {deploy|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 deploy # Compila y despliega el backend"
    echo "  $0 delete # Elimina el JAR y el servicio systemd"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

case "$ACTION" in
    deploy)
        # PublicIp lo dejó ec2.sh en lab-state.json.
        PUBLIC_IP=$(state_require PublicIp)

        if [ ! -f "$KEY_PATH" ]; then
            echo "Error: No se encontró la clave SSH en: $KEY_PATH"
            exit 1
        fi

        if [ ! -d "$BACKEND_PATH" ]; then
            echo "Error: No se encontró el proyecto backend en: $BACKEND_PATH"
            exit 1
        fi

        echo "Compilando el backend Spring Boot..."
        cd "$BACKEND_PATH"
        mvn clean package -DskipTests
        BACKEND_JAR_NAME=$(find target -maxdepth 1 -type f -name '*.jar' ! -name '*.original' -print -quit)
        cd - > /dev/null
        BACKEND_JAR="$BACKEND_PATH/$BACKEND_JAR_NAME"

        if [ -z "$BACKEND_JAR_NAME" ] || [ ! -f "$BACKEND_JAR" ]; then
            echo "Error: No se encontró el JAR ejecutable del backend."
            exit 1
        fi

        echo "Subiendo el backend a $PUBLIC_IP..."
        # -i: clave SSH de AWS Academy (labsuser.pem)
        # -o StrictHostKeyChecking=no: el laboratorio no pide confirmar known_hosts
        scp -o StrictHostKeyChecking=no -i "$KEY_PATH" "$BACKEND_JAR" ubuntu@"$PUBLIC_IP":/tmp/eventhub.jar

        echo "Configurando Spring Boot en la instancia EC2..."
        # -T: sin pseudo-terminal, para que no avise al leer el script por stdin
        ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" << 'END_BACKEND'
set -e
sudo apt-get update -y
sudo apt-get install -y openjdk-21-jre-headless
# En el primer despliegue el servicio aún no existe.
sudo systemctl stop eventhub 2>/dev/null || true
sudo systemctl disable eventhub 2>/dev/null || true
sudo rm -f /etc/systemd/system/eventhub.service
sudo rm -rf /opt/eventhub
sudo mkdir -p /opt/eventhub
sudo mv /tmp/eventhub.jar /opt/eventhub/eventhub.jar
sudo chown -R ubuntu:ubuntu /opt/eventhub
sudo tee /etc/systemd/system/eventhub.service > /dev/null << 'SERVICE'
[Unit]
Description=Event Hub Spring Boot backend
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/opt/eventhub
ExecStart=/usr/bin/java -jar /opt/eventhub/eventhub.jar
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable eventhub
sudo systemctl restart eventhub
END_BACKEND

        echo "El JAR queda en la instancia, como servicio systemd. No va en el repositorio:"
        echo "  https://$PUBLIC_IP/api/eventos"
        echo "Despliegue del backend finalizado."
        ;;

    delete)
        PUBLIC_IP=$(state_require PublicIp)

        if [ ! -f "$KEY_PATH" ]; then
            echo "Error: No se encontró la clave SSH en: $KEY_PATH"
            exit 1
        fi

        echo "Eliminando el backend de $PUBLIC_IP..."
        ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" << 'END_DELETE'
set -e
sudo systemctl stop eventhub 2>/dev/null || true
sudo systemctl disable eventhub 2>/dev/null || true
sudo rm -f /etc/systemd/system/eventhub.service
sudo systemctl daemon-reload
sudo rm -f /opt/eventhub/eventhub.jar /tmp/eventhub.jar
sudo rm -rf /opt/eventhub
END_DELETE

        echo "Backend eliminado."
        ;;

    *)
        usage
        ;;
esac
