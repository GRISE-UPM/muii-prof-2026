#!/bin/bash

# Crea o borra el bucket S3 del frontend y la instancia EC2 con Nginx que ocupa el lugar de
# CloudFront: pone el HTTPS (con un certificado autofirmado), sirve el frontend desde S3 y
# reenvía /api/* al balanceador. Es la misma idea que el Nginx de la versión 1.0.0.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. BucketName, NginxGroupId, InstanceId, AllocationId, AssociationId y PublicIp
# se escriben en lab-state.json al hacer create.
NGINX_SG_NAME="eventhub-nginx-sg"
INSTANCE_TYPE="t2.micro"

# Servidor DNS de la VPC. Nginx lo usa para resolver el nombre del balanceador y el de S3 en
# cada petición: las direcciones IP de ambos cambian sin avisar, y sus nombres no.
VPC_RESOLVER="169.254.169.253"

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create # Crea el bucket del frontend y la instancia con Nginx y su IP elástica"
    echo "  $0 delete # Borra la instancia, la IP y su grupo de seguridad, y vacía y borra el bucket"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

AWS_REGION=$(aws configure get region 2>/dev/null || true)
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [ -z "$AWS_REGION" ]; then
    echo "Error: No hay región AWS configurada (aws configure get region / AWS_DEFAULT_REGION)."
    exit 1
fi

case "$ACTION" in
    create)
        # VpcId y SubnetIds los escribió red.sh en lab-state.json; AlbGroupId, también;
        # LoadBalancerDns lo escribió alb.sh.
        VPC_ID=$(state_require VpcId)
        SUBNET_IDS=$(state_require SubnetIds)
        ALB_SG_ID=$(state_require AlbGroupId)
        ALB_DNS=$(state_require LoadBalancerDns)
        SUBNET_ID=$(echo "$SUBNET_IDS" | awk '{print $1}')

        # El nombre de un bucket es único en todo S3: el ID de cuenta evita choques.
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        BUCKET_NAME="eventhub-front-${AWS_ACCOUNT_ID}-${AWS_REGION}"
        S3_HOST="${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com"

        echo "Creando el bucket '$BUCKET_NAME'..."

        # Fuera de us-east-1, S3 exige indicar la región en LocationConstraint.
        # El bucket es privado: los buckets nuevos bloquean el acceso público.
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$BUCKET_NAME" --output text >/dev/null
        else
            aws s3api create-bucket --bucket "$BUCKET_NAME" \
                --create-bucket-configuration "LocationConstraint=$AWS_REGION" \
                --output text >/dev/null
        fi
        state_set BucketName "$BUCKET_NAME"

        echo "Reservando la IP elástica..."

        # Se reserva antes de crear la instancia, porque la IP entra en el certificado, en la
        # política del bucket y en la regla del balanceador. --domain vpc: la reserva es de VPC
        ALLOCATION_ID=$(aws ec2 allocate-address \
            --domain vpc \
            --query "AllocationId" \
            --output text)
        state_set AllocationId "$ALLOCATION_ID"
        PUBLIC_IP=$(aws ec2 describe-addresses \
            --allocation-ids "$ALLOCATION_ID" \
            --query "Addresses[0].PublicIp" \
            --output text)
        state_set PublicIp "$PUBLIC_IP"
        echo "IP elástica: $PUBLIC_IP"

        echo "Permitiendo que Nginx lea el bucket..."

        # Nginx no firma sus peticiones a S3, así que el bucket no puede reconocerlo por una
        # identidad de AWS, como hacía con CloudFront (Origin Access Control). Lo reconoce por
        # su IP: solo las peticiones que llegan desde la IP elástica (aws:SourceIp, /32 es una
        # sola dirección) pueden leer los objetos. Para el resto de Internet, el bucket es privado.
        BUCKET_POLICY=$(jq -n \
            --arg bucket "$BUCKET_NAME" \
            --arg ip "$PUBLIC_IP/32" \
            '{
              Version: "2012-10-17",
              Statement: [{
                Sid: "LecturaDesdeNginx",
                Effect: "Allow",
                Principal: "*",
                Action: "s3:GetObject",
                Resource: ("arn:aws:s3:::" + $bucket + "/*"),
                Condition: {IpAddress: {"aws:SourceIp": $ip}}
              }]
            }')
        aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "$BUCKET_POLICY"

        echo "Permitiendo que Nginx llegue al balanceador..."

        # Misma idea con el balanceador: solo acepta HTTP (80) desde la IP elástica
        aws ec2 authorize-security-group-ingress \
            --group-id "$ALB_SG_ID" \
            --protocol tcp \
            --port 80 \
            --cidr "$PUBLIC_IP/32" \
            --output text >/dev/null

        echo "Creando el grupo de seguridad '$NGINX_SG_NAME'..."

        # --vpc-id: el grupo vive en la VPC por defecto
        NGINX_SG_ID=$(aws ec2 create-security-group \
            --group-name "$NGINX_SG_NAME" \
            --description "Nginx de eventhub: HTTP y HTTPS desde Internet" \
            --vpc-id "$VPC_ID" \
            --query "GroupId" \
            --output text)
        state_set NginxGroupId "$NGINX_SG_ID"

        # --cidr 0.0.0.0/0: cualquier origen. El 80 solo redirige al 443.
        for PORT in 80 443; do
            aws ec2 authorize-security-group-ingress \
                --group-id "$NGINX_SG_ID" \
                --protocol tcp \
                --port "$PORT" \
                --cidr 0.0.0.0/0 \
                --output text >/dev/null
        done

        # Script que la instancia ejecuta al arrancar (user data). No hace falta SSH. Instala
        # Nginx, genera el certificado autofirmado y escribe la configuración. Los marcadores
        # __...__ se sustituyen aquí por los valores de este despliegue.
        #   server 80: redirige al 443 con un 301
        #   /api/*: va al balanceador por HTTP (el HTTPS termina en Nginx)
        #   /*: se pide al bucket por HTTPS. Si el objeto no existe, S3 responde 403, y Nginx
        #   sirve index.html: es el equivalente de las páginas de error de CloudFront, y deja
        #   que React resuelva las rutas.
        # resolver y set: sin ellos, Nginx resolvería los nombres una sola vez, al arrancar.
        USER_DATA=$(mktemp)
        cat > "$USER_DATA" <<'USER_DATA_EOF'
#!/bin/bash
set -e
apt-get update -y
apt-get install -y nginx openssl
mkdir -p /etc/nginx/ssl

# Certificado autofirmado. Cifra el tráfico del navegador; Cognito exige https en el callback.
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/nginx.key \
    -out /etc/nginx/ssl/nginx.crt \
    -subj "/CN=__PUBLIC_IP__" -addext "subjectAltName=IP:__PUBLIC_IP__"

cat > /etc/nginx/sites-available/default <<'NGINX_CONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_certificate /etc/nginx/ssl/nginx.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx.key;

    resolver __VPC_RESOLVER__ valid=30s;
    set $alb_host "__ALB_DNS__";
    set $s3_host "__S3_HOST__";

    location /api/ {
        proxy_pass http://$alb_host;
        proxy_http_version 1.1;
        proxy_set_header Host $alb_host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        set $objeto $uri;
        if ($uri = /) {
            set $objeto /index.html;
        }
        proxy_pass https://$s3_host$objeto;
        proxy_http_version 1.1;
        proxy_set_header Host $s3_host;
        proxy_ssl_server_name on;
        proxy_intercept_errors on;
        error_page 403 404 = @spa;
    }

    location @spa {
        proxy_pass https://$s3_host/index.html;
        proxy_http_version 1.1;
        proxy_set_header Host $s3_host;
        proxy_ssl_server_name on;
    }
}
NGINX_CONF

nginx -t
systemctl enable nginx
systemctl restart nginx
USER_DATA_EOF
        sed -i.bak \
            -e "s|__PUBLIC_IP__|$PUBLIC_IP|g" \
            -e "s|__VPC_RESOLVER__|$VPC_RESOLVER|g" \
            -e "s|__ALB_DNS__|$ALB_DNS|g" \
            -e "s|__S3_HOST__|$S3_HOST|g" \
            "$USER_DATA"

        echo "Buscando la AMI de Ubuntu 22.04..."

        # --owners: Canonical. Se queda la Jammy amd64 más reciente.
        AMI_ID=$(aws ec2 describe-images \
            --owners 099720109477 \
            --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
            --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
            --output text)
        echo "AMI: $AMI_ID"

        echo "Creando la instancia EC2..."

        # --subnet-id: una de las subnets de la VPC por defecto, que asignan IP pública al
        #   arrancar (la instancia necesita salir a Internet para instalar Nginx)
        # --user-data: el script anterior, que se ejecuta una vez, al primer arranque
        INSTANCE_ID=$(aws ec2 run-instances \
            --image-id "$AMI_ID" \
            --count 1 \
            --instance-type "$INSTANCE_TYPE" \
            --subnet-id "$SUBNET_ID" \
            --security-group-ids "$NGINX_SG_ID" \
            --user-data "file://$USER_DATA" \
            --query "Instances[0].InstanceId" \
            --output text)
        rm -f "$USER_DATA" "$USER_DATA.bak"
        state_set InstanceId "$INSTANCE_ID"
        echo "Instancia creada (ID: $INSTANCE_ID)."

        echo "Esperando a que la instancia esté running..."
        aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

        echo "Asociando la IP elástica a la instancia..."
        ASSOCIATION_ID=$(aws ec2 associate-address \
            --instance-id "$INSTANCE_ID" \
            --allocation-id "$ALLOCATION_ID" \
            --query "AssociationId" \
            --output text)
        state_set AssociationId "$ASSOCIATION_ID"

        echo "Esperando a que Nginx responda (puede tardar un par de minutos)..."

        # Cualquier respuesta HTTP sirve, aunque sea un error: el bucket aún está vacío.
        # -k: el certificado es autofirmado
        for intento in $(seq 1 40); do
            CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "https://$PUBLIC_IP/" || true)
            if [ "$CODE" != "000" ] && [ -n "$CODE" ]; then
                break
            fi
            if [ "$intento" -eq 40 ]; then
                echo "Error: Nginx no responde en https://$PUBLIC_IP/"
                exit 1
            fi
            sleep 10
        done

        echo "El bucket y la instancia quedan en lab-state.json. cognito.sh usa la IP como callback:"
        echo "  $LAB_STATE_FILE"
        echo "  https://$PUBLIC_IP"
        echo "Creación de Nginx finalizada."
        ;;

    delete)

        # IDs de lab-state.json. La IP se suelta antes de terminar la instancia, y el grupo de
        # seguridad se borra cuando la instancia ya no lo usa. La regla del puerto 80 del
        # balanceador desaparece con el grupo del balanceador (red.sh delete).
        ASSOCIATION_ID=$(state_require AssociationId)
        ALLOCATION_ID=$(state_require AllocationId)
        INSTANCE_ID=$(state_require InstanceId)
        NGINX_SG_ID=$(state_require NginxGroupId)
        BUCKET_NAME=$(state_require BucketName)

        echo "Desasociando la IP elástica '$ASSOCIATION_ID'..."
        aws ec2 disassociate-address --association-id "$ASSOCIATION_ID"

        echo "Liberando la IP elástica '$ALLOCATION_ID'..."
        aws ec2 release-address --allocation-id "$ALLOCATION_ID"

        echo "Terminando la instancia '$INSTANCE_ID'..."
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --output text >/dev/null
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"

        echo "Eliminando el grupo de seguridad '$NGINX_SG_ID'..."
        aws ec2 delete-security-group --group-id "$NGINX_SG_ID"

        echo "Vaciando y eliminando el bucket '$BUCKET_NAME'..."
        aws s3 rm "s3://$BUCKET_NAME" --recursive
        aws s3api delete-bucket --bucket "$BUCKET_NAME"

        tmp=$(mktemp)
        jq 'del(.BucketName, .NginxGroupId, .InstanceId, .AllocationId, .AssociationId, .PublicIp)' \
            "$LAB_STATE_FILE" > "$tmp"
        mv "$tmp" "$LAB_STATE_FILE"
        echo "Nginx y el bucket eliminados."
        ;;

    *)
        usage
        ;;
esac
