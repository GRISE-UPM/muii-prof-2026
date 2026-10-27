#!/bin/bash

# Crea o borra el bucket S3 del frontend y la distribución de CloudFront que sirve
# el frontend desde S3 y reenvía /api/* al balanceador.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. BucketName, OriginAccessControlId, DistributionId, DistributionArn y
# DistributionDomain se escriben en lab-state.json al hacer create.
S3_ORIGIN_ID="s3-front"
ALB_ORIGIN_ID="alb-api"

# Políticas gestionadas de CloudFront (sus IDs son fijos en todas las cuentas):
#   CachingOptimized: cachea los ficheros del frontend
#   CachingDisabled: no cachea nada de la API
#   AllViewerExceptHostHeader: reenvía a la API cabeceras, cookies y query string
CACHE_POLICY_OPTIMIZED="658327ea-f89d-4fab-a63d-7e88639e58f6"
CACHE_POLICY_DISABLED="4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
ORIGIN_REQUEST_ALL_EXCEPT_HOST="b689b0a8-53d0-40ab-baf2-68738e2966ac"

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create # Crea el bucket del frontend y la distribución de CloudFront"
    echo "  $0 delete # Desactiva y borra la distribución, y vacía y borra el bucket"
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
        if ! command -v envsubst >/dev/null 2>&1; then
            echo "Error: Falta envsubst (paquete gettext). Instálalo, por ejemplo, con: brew install gettext"
            exit 1
        fi

        # LoadBalancerDns lo escribió alb.sh en lab-state.json.
        ALB_DNS=$(state_require LoadBalancerDns)

        # El nombre de un bucket es único en todo S3: el ID de cuenta evita choques.
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        BUCKET_NAME="eventhub-front-${AWS_ACCOUNT_ID}-${AWS_REGION}"

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

        echo "Creando el Origin Access Control..."

        # OAC: CloudFront firma sus peticiones al bucket; nadie más puede leerlo.
        # SigningBehavior=always: firma todas las peticiones, sin excepción
        OAC_ID=$(aws cloudfront create-origin-access-control \
            --origin-access-control-config "Name=eventhub-oac-${AWS_ACCOUNT_ID},SigningProtocol=sigv4,SigningBehavior=always,OriginAccessControlOriginType=s3" \
            --query 'OriginAccessControl.Id' \
            --output text)
        state_set OriginAccessControlId "$OAC_ID"

        echo "Creando la distribución de CloudFront..."

        # La configuración de la distribución está en distribution.json. Sus marcadores
        # ${...} los sustituye envsubst por las variables que se exportan aquí:
        #   CALLER_REFERENCE: valor único; si la petición se repite, no crea otra distribución.
        # Dos orígenes:
        #   s3-front: el frontend (comportamiento por defecto), cacheado en el edge
        #   alb-api: /api/*, sin caché y con todos los métodos HTTP
        # http-only: el balanceador no tiene certificado; el HTTPS lo pone CloudFront.
        # redirect-to-https: una petición HTTP al frontend se redirige a HTTPS.
        # https-only: la API rechaza HTTP (un POST redirigido perdería su cuerpo).
        # PriceClass_100: solo ubicaciones de Norteamérica y Europa, las más baratas.
        export CALLER_REFERENCE="eventhub-$(date +%s)"
        export BUCKET_DOMAIN="${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com"
        export OAC_ID ALB_DNS S3_ORIGIN_ID ALB_ORIGIN_ID
        export CACHE_POLICY_OPTIMIZED CACHE_POLICY_DISABLED ORIGIN_REQUEST_ALL_EXCEPT_HOST
        DIST_CONFIG=$(mktemp)
        envsubst '${CALLER_REFERENCE} ${BUCKET_DOMAIN} ${OAC_ID} ${ALB_DNS} ${S3_ORIGIN_ID} ${ALB_ORIGIN_ID} ${CACHE_POLICY_OPTIMIZED} ${CACHE_POLICY_DISABLED} ${ORIGIN_REQUEST_ALL_EXCEPT_HOST}' \
            < "$SCRIPT_DIR/distribution.json" > "$DIST_CONFIG"

        DIST_INFO=$(aws cloudfront create-distribution \
            --distribution-config "file://$DIST_CONFIG" \
            --query 'Distribution.[Id,ARN,DomainName]' \
            --output text)
        rm -f "$DIST_CONFIG"

        # --output text separa los tres valores con tabuladores
        read -r DIST_ID DIST_ARN DIST_DOMAIN <<< "$DIST_INFO"
        state_set DistributionId "$DIST_ID"
        state_set DistributionArn "$DIST_ARN"
        state_set DistributionDomain "$DIST_DOMAIN"
        echo "Distribución creada: https://$DIST_DOMAIN"

        echo "Permitiendo que la distribución lea el bucket..."

        # Solo esta distribución (AWS:SourceArn) puede leer los objetos del bucket.
        BUCKET_POLICY=$(jq -n \
            --arg bucket "$BUCKET_NAME" \
            --arg dist "$DIST_ARN" \
            '{
              Version: "2012-10-17",
              Statement: [{
                Sid: "LecturaDesdeCloudFront",
                Effect: "Allow",
                Principal: {Service: "cloudfront.amazonaws.com"},
                Action: "s3:GetObject",
                Resource: ("arn:aws:s3:::" + $bucket + "/*"),
                Condition: {StringEquals: {"AWS:SourceArn": $dist}}
              }]
            }')
        aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy "$BUCKET_POLICY"

        echo "Esperando a que la distribución se despliegue en el edge (puede tardar varios minutos)..."
        aws cloudfront wait distribution-deployed --id "$DIST_ID"

        echo "El bucket y la distribución quedan en lab-state.json. cognito.sh usa el dominio como callback:"
        echo "  $LAB_STATE_FILE"
        echo "  https://$DIST_DOMAIN"
        echo "Creación de CloudFront finalizada."
        ;;

    delete)

        # Una distribución solo se puede borrar desactivada, y cada cambio exige el
        # ETag de su última versión (--if-match).
        DIST_ID=$(state_require DistributionId)
        OAC_ID=$(state_require OriginAccessControlId)
        BUCKET_NAME=$(state_require BucketName)

        echo "Desactivando la distribución '$DIST_ID'..."
        ETAG=$(aws cloudfront get-distribution-config --id "$DIST_ID" --query ETag --output text)
        DIST_CONFIG=$(mktemp)
        aws cloudfront get-distribution-config --id "$DIST_ID" --query DistributionConfig --output json \
            | jq '.Enabled = false' > "$DIST_CONFIG"
        aws cloudfront update-distribution \
            --id "$DIST_ID" \
            --if-match "$ETAG" \
            --distribution-config "file://$DIST_CONFIG" \
            --output text >/dev/null
        rm -f "$DIST_CONFIG"

        echo "Esperando a que la desactivación llegue al edge (puede tardar varios minutos)..."
        aws cloudfront wait distribution-deployed --id "$DIST_ID"

        echo "Eliminando la distribución..."
        ETAG=$(aws cloudfront get-distribution --id "$DIST_ID" --query ETag --output text)
        aws cloudfront delete-distribution --id "$DIST_ID" --if-match "$ETAG"

        echo "Eliminando el Origin Access Control..."
        ETAG=$(aws cloudfront get-origin-access-control --id "$OAC_ID" --query ETag --output text)
        aws cloudfront delete-origin-access-control --id "$OAC_ID" --if-match "$ETAG"

        echo "Vaciando y eliminando el bucket '$BUCKET_NAME'..."
        aws s3 rm "s3://$BUCKET_NAME" --recursive
        aws s3api delete-bucket --bucket "$BUCKET_NAME"

        tmp=$(mktemp)
        jq 'del(.BucketName, .OriginAccessControlId, .DistributionId, .DistributionArn, .DistributionDomain)' \
            "$LAB_STATE_FILE" > "$tmp"
        mv "$tmp" "$LAB_STATE_FILE"
        echo "CloudFront y el bucket eliminados."
        ;;

    *)
        usage
        ;;
esac
