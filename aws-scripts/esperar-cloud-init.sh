#!/bin/bash

# Espera a que la instancia acepte SSH y a que cloud-init termine de ejecutar el user data
# (la instalación de Nginx). CloudFormation da la instancia por creada en cuanto arranca, sin
# esperar a ese script, así que back.sh y front.sh no deben lanzarse antes.
# No tiene delete.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Funciones para leer las salidas de la pila de CloudFormation
source "$SCRIPT_DIR/stack-functions.sh"
KEY_PATH="$PROJECT_ROOT/ssh-key/labsuser.pem"

# PublicIp es una salida de la pila de CDK (EventHubStack).
PUBLIC_IP=$(salida_requerida EventHubStack PublicIp)

if [ ! -f "$KEY_PATH" ]; then
    echo "Error: No se encontró la clave SSH en: $KEY_PATH"
    exit 1
fi

echo "Esperando a que $PUBLIC_IP acepte conexiones SSH..."

# La instancia está running antes de que arranque sshd: se reintenta durante unos 5 minutos
for _ in $(seq 1 60); do
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" true 2>/dev/null; then
        break
    fi
    sleep 5
done

echo "Esperando a que cloud-init termine de instalar Nginx..."

# --wait bloquea hasta que cloud-init acaba. Devuelve un código distinto de cero si el user data
# falló; su registro está en /var/log/cloud-init-output.log
ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" "cloud-init status --wait"

echo "Nginx está listo en http://$PUBLIC_IP/"
