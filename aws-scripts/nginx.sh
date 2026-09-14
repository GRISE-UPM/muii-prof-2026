#!/bin/bash

# Configura Nginx: página estática y reverse proxy /api/ hacia Spring Boot.
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"
KEY_PATH="$PROJECT_ROOT/ssh-key/labsuser.pem"
LOADING_HTML="$SCRIPT_DIR/loading.html"
REMOTE_LOADING="/tmp/$(basename "$LOADING_HTML")"
REMOTE_INDEX="/var/www/html/index.html"

usage() {
    echo "Uso: $0 {deploy|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 deploy # Instala Nginx, el proxy /api/ y una página de carga"
    echo "  $0 delete # Detiene Nginx y vacía /var/www/html"
    exit 1
}

if [ -z "$1" ]; then
    usage
fi

ACTION="$1"

require_ssh() {
    # PublicIp: está almacenado en lab-state.json; tambien se obtiene desde AllocationId.
    PUBLIC_IP=$(state_require PublicIp)

    if [ ! -f "$KEY_PATH" ]; then
        echo "Error: No se encontró la clave SSH en: $KEY_PATH"
        exit 1
    fi
}

case "$ACTION" in
    deploy)
        require_ssh

        if [ ! -f "$LOADING_HTML" ]; then
            echo "Error: No se encontró la página de carga en: $LOADING_HTML"
            exit 1
        fi

        echo "Configurando Nginx en $PUBLIC_IP..."
        # Parámetros:
        # -o StrictHostKeyChecking=no: Evita el prompt interactivo de known_hosts en el laboratorio
        # -i: Ruta a la clave SSH de AWS Academy
        scp -o StrictHostKeyChecking=no -i "$KEY_PATH" "$LOADING_HTML" ubuntu@"$PUBLIC_IP":"$REMOTE_LOADING"

        # Parámetros:
        # -T: Deshabilita la asignacion de pseudo-terminal para evitar la advertencia
        # -o StrictHostKeyChecking=no: Evita el prompt interactivo de known_hosts en el laboratorio
        # -i: Ruta a la clave SSH de AWS Academy
        ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" \
            "REMOTE_LOADING='$REMOTE_LOADING' REMOTE_INDEX='$REMOTE_INDEX' bash -s" << 'END_NGINX'
sudo apt-get update -y
sudo apt-get install -y nginx

sudo tee /etc/nginx/sites-available/default > /dev/null << 'NGINX_CONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;

    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX_CONF

sudo rm -rf /var/www/html/*
sudo mv "$REMOTE_LOADING" "$REMOTE_INDEX"
sudo chown -R www-data:www-data /var/www/html

sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx
END_NGINX

        echo "Nginx configurado en: http://$PUBLIC_IP/"
        ;;

    delete)
        require_ssh

        echo "Eliminando Nginx de $PUBLIC_IP..."
        ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" << 'END_DELETE'
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl disable nginx 2>/dev/null || true
sudo rm -rf /var/www/html/*
sudo mkdir -p /var/www/html
sudo chown -R www-data:www-data /var/www/html
END_DELETE

        echo "Nginx detenido y /var/www/html vacío."
        ;;

    *)
        usage
        ;;
esac
