#!/bin/bash
set -e
apt-get update -y
apt-get install -y nginx

cat > /etc/nginx/sites-available/default <<'NGINX_CONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html;

    # La API va a Spring Boot, que escucha en el puerto 8080 de la propia instancia
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # El resto es el frontend. Las rutas de React no son ficheros: index.html y que React las resuelva
    location / {
        try_files $uri $uri/ /index.html;
    }
}
NGINX_CONF

# Página de carga, hasta que se publique el frontend (la sustituye front.sh)
cat > /var/www/html/index.html <<'LOADING_HTML'
<!DOCTYPE html>
<html lang="es">
  <head>
    <meta charset="UTF-8" />
    <meta http-equiv="refresh" content="10" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Cargando</title>
    <style>
      html, body { height: 100%; margin: 0; }
      body {
        display: flex;
        align-items: center;
        justify-content: center;
        font-family: system-ui, sans-serif;
        color: #1f2328;
        background: #f6f8fa;
      }
    </style>
  </head>
  <body>
    <p>Cargando....espere por favor</p>
  </body>
</html>
LOADING_HTML

nginx -t
systemctl enable nginx
systemctl restart nginx
