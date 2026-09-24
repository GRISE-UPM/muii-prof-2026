#!/bin/bash

# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

# Configura Nginx: página estática y reverse proxy /api/ hacia Spring Boot.
# No tiene delete: Nginx y /var/www/html desaparecen al terminar la instancia.
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"
KEY_PATH="$PROJECT_ROOT/ssh-key/labsuser.pem"
LOADING_HTML="$SCRIPT_DIR/loading.html"
REMOTE_LOADING="/tmp/$(basename "$LOADING_HTML")"
REMOTE_INDEX="/var/www/html/index.html"

usage() {
    echo "Uso: $0 deploy"
    echo ""
    echo "Ejemplos:"
    echo "  $0 deploy # Instala Nginx, el proxy /api/ y una página de carga"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

require_ssh() {
    # PublicIp lo dejó ec2.sh en lab-state.json.
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
        # -i: clave SSH de AWS Academy
        scp -o StrictHostKeyChecking=no -i "$KEY_PATH" "$LOADING_HTML" ubuntu@"$PUBLIC_IP":"$REMOTE_LOADING"

        # -T: sin pseudo-terminal, para que no avise al leer el script por stdin
        ssh -T -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@"$PUBLIC_IP" \
            "REMOTE_LOADING='$REMOTE_LOADING' REMOTE_INDEX='$REMOTE_INDEX' bash -s" << 'END_NGINX'
set -e
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

        echo "Nginx queda en la instancia. El navegador entra por HTTP y /api/ se reenvía a Spring Boot en el puerto 8080:"
        echo "  http://$PUBLIC_IP/"
        echo "Configuración de Nginx finalizada."
        ;;

    *)
        usage
        ;;
esac
