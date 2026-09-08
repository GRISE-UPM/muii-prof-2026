#!/bin/bash

# Configuración por defecto con rutas relativas
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
KEY_PATH="$PROJECT_ROOT/ssh-key/labsuser.pem"
APP_PATH="$PROJECT_ROOT/eventhub-front-react"
PUBLIC_IP_FILE="$SCRIPT_DIR/public-ip.txt"
SFTP_BATCH_FILE="sftp-batch-file.txt"

# Funcion para mostrar la ayuda
usage() {
    echo "Uso: $0 {deploy|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 deploy # Compila y despliega el frontend"
    echo "  $0 delete # Elimina los ficheros estáticos del frontend en EC2"
    exit 1
}

# Validar que se reciba al menos un parámetro
if [ -z "$1" ]; then
    usage
fi

ACTION="$1"

case "$ACTION" in
    deploy)
        if [ ! -f "$PUBLIC_IP_FILE" ]; then
            echo "Error: No se encontró el archivo de la IP en: $PUBLIC_IP_FILE"
            exit 1
        fi

        PUBLIC_IP=$(< "$PUBLIC_IP_FILE")
        PUBLIC_IP="${PUBLIC_IP%%$'\n'}"

        if [ ! -f "$KEY_PATH" ]; then
            echo "Error: No se encontró la clave SSH en: $KEY_PATH"
            exit 1
        fi

        if [ ! -d "$APP_PATH" ]; then
            echo "Error: No se encontró el directorio del código fuente en: $APP_PATH"
            exit 1
        fi

        # Solo se carga con `npm run build`. El dev usa .env.development (localhost:8080).
        cat > "$APP_PATH/.env.production.local" <<EOF
# .env.production.local (sufijo .local): git lo ignora. Lo genera aws-scripts/front.sh en cada
# deploy; no editar a mano. Vite solo lo carga con \`npm run build\`, no con \`npm run dev\`.
# Así el front local no apunta a EC2 aunque falte .env.development.
# VITE_API_BASE_URL: origen HTTPS de la API en EC2
VITE_API_BASE_URL=https://$PUBLIC_IP
EOF

        # Compilación de la aplicación React
        echo "Compilando la aplicación React..."
        cd "$APP_PATH" || exit 1
        npm install
        npm run build
        cd - > /dev/null

        # Detección de carpeta de salida (build o dist)
        BUILD_DIR="$APP_PATH/build"
        if [ ! -d "$BUILD_DIR" ]; then
            BUILD_DIR="$APP_PATH/dist"
        fi

        if [ ! -d "$BUILD_DIR" ]; then
            echo "Error: No se encontró el directorio de compilación (build/dist)."
            exit 1
        fi

        echo "Desplegando la aplicación en la instancia EC2..."

        # Creación del lote SFTP subiendo a una subcarpeta temporal
        cat << EOF > "$SFTP_BATCH_FILE"
mkdir /tmp/app_dist
cd /tmp/app_dist
lcd $BUILD_DIR
put -r .
quit
EOF

        echo "Subiendo archivos compilados mediante SFTP..."
        # Parámetros:
        # -o StrictHostKeyChecking=no: Evita el prompt interactivo de known_hosts en el laboratorio
        # -b: Ejecuta el lote de comandos SFTP generado en el fichero temporal
        # -i: Ruta a la clave SSH de AWS Academy (labsuser.cer)
        sftp -o StrictHostKeyChecking=no -b "$SFTP_BATCH_FILE" -i "$KEY_PATH" ubuntu@"$PUBLIC_IP"

        echo "Moviendo archivos a /var/www/html en el servidor..."
        # Parámetros:
        # -T: Deshabilita la asignacion de pseudo-terminal para evitar la advertencia
        # -o StrictHostKeyChecking=no: Evita el prompt interactivo de known_hosts en el laboratorio
        # -i: Ruta a la clave SSH de AWS Academy (labsuser.cer)
        ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" << 'ENDSSH'
# Sustituye la página de carga de nginx.sh por el frontend compilado
sudo rm -rf /var/www/html/*
sudo mv /tmp/app_dist/* /var/www/html/ 2>/dev/null
sudo rm -rf /tmp/app_dist
sudo chown -R www-data:www-data /var/www/html
ENDSSH

        # Limpieza de temporales locales
        rm -f "$SFTP_BATCH_FILE"

        echo "Frontend desplegado en: https://$PUBLIC_IP/"
        ;;

    delete)
        if [ ! -f "$PUBLIC_IP_FILE" ]; then
            echo "Error: No se encontró el archivo de la IP en: $PUBLIC_IP_FILE"
            exit 1
        fi

        PUBLIC_IP=$(< "$PUBLIC_IP_FILE")
        PUBLIC_IP="${PUBLIC_IP%%$'\n'}"

        if [ ! -f "$KEY_PATH" ]; then
            echo "Error: No se encontró la clave SSH en: $KEY_PATH"
            exit 1
        fi

        echo "Eliminando el frontend de $PUBLIC_IP..."
        # Parámetros:
        # -T: Deshabilita la asignacion de pseudo-terminal para evitar la advertencia
        # -o StrictHostKeyChecking=no: Evita el prompt interactivo de known_hosts en el laboratorio
        # -i: Ruta a la clave SSH de AWS Academy (labsuser.cer)
        ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" << 'END_DELETE'
# Vacía el document root de Nginx sin tocar el proxy /api/ del backend
sudo rm -rf /var/www/html/*
sudo rm -rf /tmp/app_dist
sudo mkdir -p /var/www/html
sudo chown -R www-data:www-data /var/www/html
END_DELETE

        # Limpieza de temporales locales generados por el deploy
        rm -f "$SFTP_BATCH_FILE"
        rm -f "$APP_PATH/.env.production.local"

        echo "Frontend eliminado de /var/www/html."
        ;;

    *)
        usage
        ;;
esac