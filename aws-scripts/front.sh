#!/bin/bash

# Compila la SPA, la sube al bucket S3 y renueva la caché de CloudFront.
# No tiene delete: el bucket se vacía y se borra con cloudfront.sh delete.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"
APP_PATH="$PROJECT_ROOT/eventhub-front-react"

# BucketName, DistributionId y DistributionDomain los escribió cloudfront.sh en lab-state.json.
BUCKET_NAME=$(state_require BucketName)
DIST_ID=$(state_require DistributionId)
DIST_DOMAIN=$(state_require DistributionDomain)

if [ ! -d "$APP_PATH" ]; then
    echo "Error: No se encontró el directorio del código fuente en: $APP_PATH"
    exit 1
fi

# Vite solo carga este fichero con npm run build, no con npm run dev.
# La SPA y la API comparten origen (CloudFront reenvía /api/* al balanceador),
# así que la SPA llama a rutas relativas: VITE_API_BASE_URL queda vacía.
cat > "$APP_PATH/.env.production.local" <<EOF
# Generado por aws-scripts/front.sh. No editar a mano.
# VITE_API_BASE_URL: vacía; la API está en el mismo origen que la SPA (CloudFront)
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

echo "Renovando la caché de CloudFront..."

# CloudFront guarda copias de los ficheros en el edge. La invalidación obliga a
# pedirlos de nuevo al bucket, para que se vea la versión recién subida.
INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id "$DIST_ID" \
    --paths "/*" \
    --query 'Invalidation.Id' \
    --output text)
aws cloudfront wait invalidation-completed --distribution-id "$DIST_ID" --id "$INVALIDATION_ID"

echo "El build queda en el bucket, servido por CloudFront. No va en el repositorio:"
echo "  https://$DIST_DOMAIN/"
echo "Despliegue del frontend finalizado."
