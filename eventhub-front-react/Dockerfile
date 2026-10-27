# Imagen del frontend: el build de Vite (npm run build) servido por Nginx sin privilegios.
# La construye y la sube a ECR aws-scripts/front.sh.
# nginx-unprivileged escucha en el 8080, el mismo puerto que el backend, así que el grupo
# de seguridad de las tareas no necesita otra regla.
FROM nginxinc/nginx-unprivileged:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/ /usr/share/nginx/html/
EXPOSE 8080
