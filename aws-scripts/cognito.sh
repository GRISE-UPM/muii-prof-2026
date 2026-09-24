#!/bin/bash

# Crea o borra el User Pool, el dominio y el App Client de Cognito.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

# Rutas absolutas del script y del repositorio. Así jq-functions.sh, .env.local y
# cognito.properties se encuentran aunque el comando no se lance desde la raíz.
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. Region, UserPoolId, ClientId, Domain, CallbackUrl, IssuerUri y
# CognitoDomainUrl se escriben en lab-state.json al hacer create.
POOL_NAME="eventhub-pool"
CLIENT_NAME="eventhub-front-react"
CONFIG_FILE="$PROJECT_ROOT/eventhub-front-react/.env.local"
SPRING_CONFIG_FILE="$PROJECT_ROOT/eventhub-back-springboot/src/main/resources/cognito.properties"

# Cognito rechaza el scope offline_access. El refresh token sale igual del
# flujo authorization code si RefreshTokenValidity es mayor que 0.
OAUTH_SCOPES="openid email profile"
REFRESH_TOKEN_VALIDITY_DAYS=30

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create # Crea el User Pool, el dominio y el App Client"
    echo "  $0 delete # Borra el dominio y el User Pool; el App Client cae con él"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

# Región de la CLI (Academy suele ser us-east-1). Hace falta para las URLs.
AWS_REGION=$(aws configure get region 2>/dev/null || true)
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [ -z "$AWS_REGION" ]; then
    echo "Error: No hay región AWS configurada (aws configure get region / AWS_DEFAULT_REGION)."
    exit 1
fi

# El prefijo del Hosted UI es único en toda la región. El ID de cuenta evita
# que choque entre alumnos o laboratorios.
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$AWS_ACCOUNT_ID" ] || [ "$AWS_ACCOUNT_ID" = "None" ]; then
    echo "Error: No se pudo obtener el ID de la cuenta de AWS."
    exit 1
fi
COGNITO_DOMAIN="muii-prof-2026-${AWS_ACCOUNT_ID}"

case "$ACTION" in
    create)
        for dir in "$(dirname "$CONFIG_FILE")" "$(dirname "$SPRING_CONFIG_FILE")"; do
            if [ ! -d "$dir" ]; then
                echo "Error: No existe la carpeta: $dir"
                exit 1
            fi
        done

        # Callback HTTPS de la SPA. PublicIp lo dejó ec2.sh en lab-state.json.
        PUBLIC_IP=$(state_require PublicIp)
        CALLBACK_URL="https://${PUBLIC_IP}"
        echo "Callback de Cognito: $CALLBACK_URL"
        echo "Dominio de Cognito: $COGNITO_DOMAIN"

        echo "Creando User Pool '$POOL_NAME'..."

        # --pool-name: Directorio de usuarios
        # --auto-verified-attributes: Código de confirmación al email
        # --username-attributes: El correo es el nombre de usuario
        # --admin-create-user-config: Permite el autorregistro
        # --policies: Longitud y complejidad de la contraseña
        USER_POOL_ID=$(aws cognito-idp create-user-pool \
            --pool-name "$POOL_NAME" \
            --auto-verified-attributes email \
            --username-attributes email \
            --admin-create-user-config AllowAdminCreateUserOnly=false \
            --policies '{"PasswordPolicy":{"MinimumLength":8,"RequireUppercase":true,"RequireLowercase":true,"RequireNumbers":true,"RequireSymbols":false}}' \
            --query "UserPool.Id" \
            --output text)
        echo "User Pool creado (ID: $USER_POOL_ID)."

        echo "Creando dominio de Cognito '$COGNITO_DOMAIN'..."

        # --domain: Prefijo del Hosted UI, donde el navegador inicia el login.
        # La respuesta JSON (ManagedLoginVersion) no aporta nada: se descarta.
        aws cognito-idp create-user-pool-domain \
            --domain "$COGNITO_DOMAIN" \
            --user-pool-id "$USER_POOL_ID" \
            --output text >/dev/null
        echo "Dominio de Cognito creado."

        echo "Creando App Client para la SPA..."

        # --no-generate-secret: Cliente público; el secreto quedaría en el navegador
        # --allowed-o-auth-flows: Authorization code (con PKCE)
        # --callback-urls / --logout-urls: Únicas URLs a las que Cognito puede redirigir
        # --refresh-token-validity: Días de validez del refresh token
        CLIENT_ID=$(aws cognito-idp create-user-pool-client \
            --user-pool-id "$USER_POOL_ID" \
            --client-name "$CLIENT_NAME" \
            --no-generate-secret \
            --allowed-o-auth-flows code \
            --allowed-o-auth-scopes $OAUTH_SCOPES \
            --allowed-o-auth-flows-user-pool-client \
            --callback-urls "$CALLBACK_URL" \
            --logout-urls "$CALLBACK_URL" \
            --supported-identity-providers COGNITO \
            --refresh-token-validity "$REFRESH_TOKEN_VALIDITY_DAYS" \
            --query "UserPoolClient.ClientId" \
            --output text)
        echo "App Client creada (ID: $CLIENT_ID)."

        # El Hosted UI inicia el login. issuer-uri es quien firma los JWT.
        COGNITO_DOMAIN_URL="https://$COGNITO_DOMAIN.auth.$AWS_REGION.amazoncognito.com"
        ISSUER_URI="https://cognito-idp.$AWS_REGION.amazonaws.com/$USER_POOL_ID"

        state_set Region "$AWS_REGION"
        state_set UserPoolId "$USER_POOL_ID"
        state_set ClientId "$CLIENT_ID"
        state_set Domain "$COGNITO_DOMAIN"
        state_set CallbackUrl "$CALLBACK_URL"
        state_set IssuerUri "$ISSUER_URI"
        state_set CognitoDomainUrl "$COGNITO_DOMAIN_URL"

        cat > "$CONFIG_FILE" <<EOF
# Generado por aws-scripts/cognito.sh. No editar a mano.
# VITE_COGNITO_ISSUER_URI: emisor de los JWT, el mismo valor que usa Spring
# VITE_COGNITO_CLIENT_ID: App Client de la SPA
# VITE_COGNITO_DOMAIN: Hosted UI para login y logout
VITE_COGNITO_ISSUER_URI=$ISSUER_URI
VITE_COGNITO_CLIENT_ID=$CLIENT_ID
VITE_COGNITO_DOMAIN=$COGNITO_DOMAIN_URL
EOF

        cat > "$SPRING_CONFIG_FILE" <<EOF
# Generado por aws-scripts/cognito.sh. No editar a mano.
# Emisor de los JWT (User Pool)
spring.security.oauth2.resourceserver.jwt.issuer-uri=$ISSUER_URI
EOF

        echo "El User Pool, el App Client y el dominio quedan en estos ficheros. La SPA y Spring los leen al arrancar; no van en el código:"
        echo "  Frontend (variables de la SPA): $CONFIG_FILE"
        echo "  Backend (emisor del JWT): $SPRING_CONFIG_FILE"
        echo "Configuración de Cognito finalizada."
        ;;

    delete)

        # IDs de lab-state.json. El dominio se borra antes que el pool.
        # El App Client desaparece al borrar el pool.
        USER_POOL_ID=$(state_require UserPoolId)
        DOMAIN=$(state_require Domain)

        echo "Eliminando dominio de Cognito '$DOMAIN'..."
        aws cognito-idp delete-user-pool-domain \
            --domain "$DOMAIN" \
            --user-pool-id "$USER_POOL_ID"

        echo "Eliminando User Pool '$USER_POOL_ID' (el App Client se borra con él)..."
        aws cognito-idp delete-user-pool --user-pool-id "$USER_POOL_ID"

        rm -f "$CONFIG_FILE" "$SPRING_CONFIG_FILE"

        tmp=$(mktemp)
        jq 'del(.Region, .UserPoolId, .ClientId, .Domain, .CallbackUrl, .IssuerUri, .CognitoDomainUrl)' \
            "$LAB_STATE_FILE" > "$tmp"
        mv "$tmp" "$LAB_STATE_FILE"
        echo "Cognito eliminado."
        ;;

    *)
        usage
        ;;
esac
