#!/bin/bash

# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"
KEY_PATH="$PROJECT_ROOT/ssh-key/labsuser.pem"
APP_PATH="$PROJECT_ROOT/eventhub-front-react"
# Ruta absoluta: el lote SFTP se encuentra aunque el comando no se lance desde la raíz.
# No tiene delete: el build en /var/www/html desaparece con la instancia.
SFTP_BATCH_FILE="$SCRIPT_DIR/sftp-batch-file.txt"

# PublicIp lo dejó ec2.sh en lab-state.json.
PUBLIC_IP=$(state_require PublicIp)

if [ ! -f "$KEY_PATH" ]; then
    echo "Error: No se encontró la clave SSH en: $KEY_PATH"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: No se encontró el directorio del código fuente en: $APP_PATH"
    exit 1
fi

# Vite solo carga este fichero con npm run build, no con npm run dev.
cat > "$APP_PATH/.env.production.local" <<EOF
# Generado por aws-scripts/front.sh. No editar a mano.
# VITE_API_BASE_URL: origen HTTP de la API en EC2
VITE_API_BASE_URL=http://$PUBLIC_IP
EOF

echo "Compilando la aplicación React..."
cd "$APP_PATH"
npm install
npm run build
cd - > /dev/null

BUILD_DIR="$APP_PATH/build"
if [ ! -d "$BUILD_DIR" ]; then
    BUILD_DIR="$APP_PATH/dist"
fi

if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: No se encontró el directorio de compilación (build/dist)."
    exit 1
fi

echo "Subiendo el frontend a $PUBLIC_IP..."
cat << EOF > "$SFTP_BATCH_FILE"
mkdir /tmp/app_dist
cd /tmp/app_dist
lcd $BUILD_DIR
put -r .
quit
EOF

# -b: ejecuta el lote SFTP. -i: clave SSH de AWS Academy.
sftp -o StrictHostKeyChecking=no -b "$SFTP_BATCH_FILE" -i "$KEY_PATH" ubuntu@"$PUBLIC_IP"

echo "Publicando los ficheros en /var/www/html..."
# -T: sin pseudo-terminal, para que no avise al leer el script por stdin
ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" << 'ENDSSH'
set -e
# Sustituye la página de carga de nginx.sh por el frontend compilado.
sudo rm -rf /var/www/html/*
sudo mv /tmp/app_dist/* /var/www/html/
sudo rm -rf /tmp/app_dist
sudo chown -R www-data:www-data /var/www/html
ENDSSH

rm -f "$SFTP_BATCH_FILE"

echo "El build queda en la instancia, servido por Nginx. No va en el repositorio:"
echo "  http://$PUBLIC_IP/"
echo "Despliegue del frontend finalizado."
