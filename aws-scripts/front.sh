#!/bin/bash

# Compila el frontend y lo sube al bucket S3, desde donde lo sirve Nginx.
# No tiene delete: el bucket se vacía y se borra con nginx.sh delete.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"
APP_PATH="$PROJECT_ROOT/eventhub-front-react"

# BucketName y PublicIp los escribió nginx.sh en lab-state.json.
BUCKET_NAME=$(state_require BucketName)
PUBLIC_IP=$(state_require PublicIp)

if [ ! -d "$APP_PATH" ]; then
    echo "Error: No se encontró el directorio del código fuente en: $APP_PATH"
    exit 1
fi

# Vite solo carga este fichero con npm run build, no con npm run dev.
# El frontend y la API comparten origen (Nginx reenvía /api/* al balanceador),
# así que el frontend llama a rutas relativas: VITE_API_BASE_URL queda vacía.
cat > "$APP_PATH/.env.production.local" <<EOF
# Generado por aws-scripts/front.sh. No editar a mano.
# VITE_API_BASE_URL: vacía; la API está en el mismo origen que el frontend (Nginx)
VITE_API_BASE_URL=
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

echo "Subiendo el frontend al bucket '$BUCKET_NAME'..."

# --delete: borra del bucket los ficheros que ya no están en el build
aws s3 sync "$BUILD_DIR" "s3://$BUCKET_NAME" --delete

echo "El build queda en el bucket, servido por Nginx. No va en el repositorio:"
echo "  https://$PUBLIC_IP/"
echo "El certificado es autofirmado: el navegador avisará, y hay que aceptarlo."
echo "Despliegue del frontend finalizado."
