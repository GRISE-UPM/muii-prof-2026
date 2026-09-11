#!/bin/bash

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=jq-functions.sh
source "$SCRIPT_DIR/jq-functions.sh"

# Configuración por defecto (constantes; no van en lab-state.json)
POOL_NAME="eventhub-pool"
CLIENT_NAME="eventhub-front-react"
CONFIG_FILE="$PROJECT_ROOT/eventhub-front-react/.env.local"
SPRING_CONFIG_FILE="$PROJECT_ROOT/eventhub-back-springboot/src/main/resources/cognito.properties"
AWS_REGION="us-east-1"
# Cognito no admite el scope OIDC 'offline_access'; el refresh token se emite
# con el flujo authorization code si el client tiene RefreshTokenValidity > 0.
OAUTH_SCOPES="openid email profile"
REFRESH_TOKEN_VALIDITY_DAYS=30

# Validar que se reciba exactamente un parametro
if [ -z "$1" ] || [ -n "$2" ]; then
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create"
    echo "  $0 delete"
    exit 1
fi

ACTION="$1"

# El prefijo del Hosted UI es único en toda la región, no solo en esta cuenta.
# Se añade el ID de cuenta para que no choque entre alumnos o laboratorios.
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$AWS_ACCOUNT_ID" ] || [ "$AWS_ACCOUNT_ID" = "None" ]; then
    echo "Error: No se pudo obtener el ID de la cuenta de AWS."
    exit 1
fi
COGNITO_DOMAIN="muii-prof-2026-${AWS_ACCOUNT_ID}"

case "$ACTION" in
    create)
        CONFIG_PARENT_DIR="$(dirname "$CONFIG_FILE")"
        SPRING_CONFIG_PARENT_DIR="$(dirname "$SPRING_CONFIG_FILE")"

        if [ ! -d "$CONFIG_PARENT_DIR" ]; then
            echo "Error: No existe la carpeta de configuración del frontend: $CONFIG_PARENT_DIR"
            exit 1
        fi

        if [ ! -d "$SPRING_CONFIG_PARENT_DIR" ]; then
            echo "Error: No existe la carpeta de recursos de Spring Boot: $SPRING_CONFIG_PARENT_DIR"
            exit 1
        fi

        # Callback HTTPS de la SPA: se deriva de PublicIp (lab-state.json / EC2).
        # Tambien se podria reconstruir con describe-addresses --allocation-ids.
        PUBLIC_IP=$(state_require PublicIp)
        CALLBACK_URL="https://${PUBLIC_IP}"

        echo "Callback de Cognito: $CALLBACK_URL"
        echo "Dominio de Cognito: $COGNITO_DOMAIN"

        # Si el dominio ya existe en esta cuenta, se reutiliza su User Pool.
        # describe-user-pool-domain solo ve dominios de esta cuenta; si está en otra,
        # devuelve vacío y create-user-pool-domain falla.
        # Parámetros:
        # --domain: Prefijo del Hosted UI
        # --query: Extrae el User Pool ligado a ese prefijo
        # --output: Devuelve el resultado en texto plano
        DOMAIN_POOL=$(aws cognito-idp describe-user-pool-domain \
            --region "$AWS_REGION" \
            --domain "$COGNITO_DOMAIN" \
            --query "DomainDescription.UserPoolId" \
            --output text 2>/dev/null || true)

        if [ -n "$DOMAIN_POOL" ] && [ "$DOMAIN_POOL" != "None" ]; then
            USER_POOL_ID="$DOMAIN_POOL"
            echo "El dominio '$COGNITO_DOMAIN' ya pertenece al User Pool '$USER_POOL_ID'. Se reutiliza."
        else
            # Consultar el ID del User Pool por nombre:
            # Parámetros:
            # --max-results: Limita el escaneo a los primeros 60 User Pools registrados en la cuenta
            # --query: Filtra la lista buscando el elemento con el nombre especificado y obtiene su ID
            # --output: Devuelve el resultado filtrado como texto plano
            USER_POOL_ID=$(aws cognito-idp list-user-pools \
                --region "$AWS_REGION" \
                --max-results 60 \
                --query "UserPools[?Name=='$POOL_NAME'].Id | [0]" \
                --output text)

            if [ -n "$USER_POOL_ID" ] && [ "$USER_POOL_ID" != "None" ]; then
                echo "User Pool '$POOL_NAME' ya existe (ID: $USER_POOL_ID). Se reutiliza y se regeneran los ficheros de configuración."
            else
                # Crear el User Pool en AWS
                echo "Creando User Pool con nombre: '$POOL_NAME'..."
                # Parámetros:
                # --pool-name: Nombre del directorio de usuarios que se creara en AWS
                # --auto-verified-attributes: Envia automaticamente un codigo de confirmacion al email
                # --username-attributes: Permite iniciar sesion usando la direccion de correo como usuario
                # --admin-create-user-config: Permite el autorregistro publico de usuarios (Self-service sign up)
                # --policies: Define la complejidad y longitud minima exigida para las contraseñas
                # --query: Extrae unicamente el valor del campo "Id" de la respuesta JSON
                # --output: Devuelve el resultado en texto plano sin comillas para asignarlo a la variable
                USER_POOL_ID=$(aws cognito-idp create-user-pool \
                    --region "$AWS_REGION" \
                    --pool-name "$POOL_NAME" \
                    --auto-verified-attributes email \
                    --username-attributes email \
                    --admin-create-user-config AllowAdminCreateUserOnly=false \
                    --policies '{"PasswordPolicy":{"MinimumLength":8,"RequireUppercase":true,"RequireLowercase":true,"RequireNumbers":true,"RequireSymbols":false}}' \
                    --query "UserPool.Id" \
                    --output text)

                if [ -z "$USER_POOL_ID" ] || [ "$USER_POOL_ID" = "None" ]; then
                    echo "Error al crear el User Pool."
                    exit 1
                fi

                echo "User Pool '$POOL_NAME' creado (ID: $USER_POOL_ID)."
            fi

            echo "Creando dominio de Cognito"
            # Parámetros:
            # --domain: Prefijo del dominio. Sirve para iniciar la autorización OAuth 2.0 redirigiendo a la
            #           página web de login adecuada
            # --user-pool-id: ID del User Pool al que se asocia el dominio
            aws cognito-idp create-user-pool-domain \
                --region "$AWS_REGION" \
                --domain "$COGNITO_DOMAIN" \
                --user-pool-id "$USER_POOL_ID"
            if [ $? -ne 0 ]; then
                echo "Error al crear el dominio de Cognito '$COGNITO_DOMAIN'."
                exit 1
            fi
        fi

        # Localiza el App Client de la SPA dentro del User Pool
        # Parámetros:
        # --user-pool-id: ID del User Pool donde buscar el cliente
        # --max-results: Limita el escaneo a los primeros 60 clientes del pool
        # --query: Extrae el ClientId del cliente cuyo nombre coincide con CLIENT_NAME
        # --output: Devuelve el resultado filtrado como texto plano
        CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
            --region "$AWS_REGION" \
            --user-pool-id "$USER_POOL_ID" \
            --max-results 60 \
            --query "UserPoolClients[?ClientName=='$CLIENT_NAME'].ClientId | [0]" \
            --output text)

        if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "None" ]; then
            echo "Creando App Client para SPA..."
            # Parámetros:
            # --user-pool-id: ID del User Pool al que quedara asociado este cliente
            # --client-name: Nombre descriptivo para la aplicacion cliente (SPA)
            # --no-generate-secret: Evita crear clave secreta; obligatorio para clientes publicos como SPAs
            # --allowed-o-auth-flows: Habilita el flujo seguro Authorization Code Grant (OAuth 2.0 con PKCE)
            # --allowed-o-auth-scopes: Define los permisos solicitados en el token durante el login
            # --allowed-o-auth-flows-user-pool-client: Activa la configuracion OAuth definida en este cliente
            # --callback-urls: Lista blanca de URLs a donde Cognito puede redirigir tras un login exitoso
            # --logout-urls: Lista blanca de URLs a donde Cognito puede redirigir tras cerrar sesion
            # --supported-identity-providers: Permite autenticacion con el directorio propio de Cognito
            # --refresh-token-validity: Dias de validez del refresh token (Cognito no usa el scope offline_access)
            # --query: Extrae unicamente la propiedad "ClientId" de la respuesta JSON
            # --output: Devuelve la salida como texto plano
            CLIENT_ID=$(aws cognito-idp create-user-pool-client \
                --region "$AWS_REGION" \
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
        else
            echo "App Client '$CLIENT_NAME' ya existe (ID: $CLIENT_ID). Se actualizan callback y refresh token."
            # Parámetros:
            # --user-pool-id: ID del User Pool al que pertenece el cliente
            # --client-id: Identificador del App Client que se va a modificar
            # --client-name: Nombre descriptivo para la aplicacion cliente (SPA)
            # --allowed-o-auth-flows: Habilita el flujo seguro Authorization Code Grant (OAuth 2.0 con PKCE)
            # --allowed-o-auth-scopes: Define los permisos solicitados en el token durante el login
            # --allowed-o-auth-flows-user-pool-client: Activa la configuracion OAuth definida en este cliente
            # --callback-urls: Lista blanca de URLs a donde Cognito puede redirigir tras un login exitoso
            # --logout-urls: Lista blanca de URLs a donde Cognito puede redirigir tras cerrar sesion
            # --supported-identity-providers: Permite autenticacion con el directorio propio de Cognito
            # --refresh-token-validity: Dias de validez del refresh token (Cognito no usa el scope offline_access)
            aws cognito-idp update-user-pool-client \
                --region "$AWS_REGION" \
                --user-pool-id "$USER_POOL_ID" \
                --client-id "$CLIENT_ID" \
                --client-name "$CLIENT_NAME" \
                --allowed-o-auth-flows code \
                --allowed-o-auth-scopes $OAUTH_SCOPES \
                --allowed-o-auth-flows-user-pool-client \
                --callback-urls "$CALLBACK_URL" \
                --logout-urls "$CALLBACK_URL" \
                --supported-identity-providers COGNITO \
                --refresh-token-validity "$REFRESH_TOKEN_VALIDITY_DAYS" \
                --query "UserPoolClient.ClientId" \
                --output text >/dev/null
            if [ $? -ne 0 ]; then
                echo "Error al actualizar el App Client '$CLIENT_NAME'."
                exit 1
            fi
        fi

        if [ -z "$CLIENT_ID" ] || [ "$CLIENT_ID" = "None" ]; then
            echo "Error: No se obtuvo el Client ID de Cognito."
            exit 1
        fi

        # El dominio OAuth del frontend y el issuer del backend son endpoints distintos:
        # el primero inicia la autorización y el segundo identifica al emisor de los JWT.
        COGNITO_DOMAIN_URL="https://$COGNITO_DOMAIN.auth.$AWS_REGION.amazoncognito.com"
        ISSUER_URI="https://cognito-idp.$AWS_REGION.amazonaws.com/$USER_POOL_ID"

        cat > "$CONFIG_FILE" <<EOF
# .env.local (sufijo .local): git lo ignora. Lo genera aws-scripts/cognito.sh en cada create;
# no editar a mano. Se carga en todos los modos (dev y build) porque Cognito hace falta en ambos.
# VITE_COGNITO_ISSUER_URI: emisor de los JWT (User Pool), mismo valor que usa el API
# VITE_COGNITO_CLIENT_ID: identificador del App Client de la SPA
# VITE_COGNITO_DOMAIN: URL del Hosted UI para login y logout OAuth
VITE_COGNITO_ISSUER_URI=$ISSUER_URI
VITE_COGNITO_CLIENT_ID=$CLIENT_ID
VITE_COGNITO_DOMAIN=$COGNITO_DOMAIN_URL
EOF
        if [ $? -ne 0 ]; then
            echo "Error al escribir la configuración del frontend: $CONFIG_FILE"
            exit 1
        fi

        cat > "$SPRING_CONFIG_FILE" <<EOF
# Generado por aws-scripts/cognito.sh. No editar a mano: se sobrescribe en cada create.
# spring.security.oauth2.resourceserver.jwt.issuer-uri: emisor de los JWT (User Pool)
spring.security.oauth2.resourceserver.jwt.issuer-uri=$ISSUER_URI
EOF
        if [ $? -ne 0 ]; then
            echo "Error al escribir la configuración de Spring Boot: $SPRING_CONFIG_FILE"
            exit 1
        fi

        echo "Archivo $CONFIG_FILE actualizado."
        echo "Archivo $SPRING_CONFIG_FILE actualizado."
        echo "Configuración de Cognito finalizada."
        ;;

    delete)
        # No se borra el User Pool ni el dominio si existen: el pool contiene los
        # usuarios registrados y perderlos no es recuperable. El prefijo del Hosted UI
        # es único en toda la región; si se elimina, puede quedar reservado un tiempo
        # o seguir ocupado en otra cuenta del Learner Lab y no se puede volver a crear.
        echo "Comprobando el dominio de Cognito '$COGNITO_DOMAIN'..."
        # Parámetros:
        # --domain: Prefijo del dominio Hosted UI
        # --query: Extrae el User Pool ligado a ese dominio
        # --output: Devuelve el resultado en texto plano
        DOMAIN_POOL=$(aws cognito-idp describe-user-pool-domain \
            --region "$AWS_REGION" \
            --domain "$COGNITO_DOMAIN" \
            --query "DomainDescription.UserPoolId" \
            --output text 2>/dev/null || true)

        if [ -n "$DOMAIN_POOL" ] && [ "$DOMAIN_POOL" != "None" ]; then
            echo "Advertencia: el dominio '$COGNITO_DOMAIN' existe (User Pool '$DOMAIN_POOL'). No se elimina."
        fi

        echo "Comprobando el User Pool '$POOL_NAME'..."
        # Parámetros:
        # --max-results: Limita el escaneo a los primeros 60 User Pools registrados en la cuenta
        # --query: Filtra la lista buscando el elemento con el nombre especificado y obtiene su ID
        # --output: Devuelve el resultado filtrado como texto plano
        USER_POOL_ID=$(aws cognito-idp list-user-pools \
            --region "$AWS_REGION" \
            --max-results 60 \
            --query "UserPools[?Name=='$POOL_NAME'].Id | [0]" \
            --output text)

        if [ -n "$USER_POOL_ID" ] && [ "$USER_POOL_ID" != "None" ]; then
            echo "Advertencia: el User Pool '$POOL_NAME' existe (ID: $USER_POOL_ID). No se elimina."
        fi

        if { [ -z "$DOMAIN_POOL" ] || [ "$DOMAIN_POOL" = "None" ]; } && \
           { [ -z "$USER_POOL_ID" ] || [ "$USER_POOL_ID" = "None" ]; }; then
            echo "No hay dominio ni User Pool que eliminar."
        fi
        ;;

    *)
        echo "Uso: $0 {create|delete}"
        echo ""
        echo "Ejemplos:"
        echo "  $0 create"
        echo "  $0 delete"
        exit 1
        ;;
esac
