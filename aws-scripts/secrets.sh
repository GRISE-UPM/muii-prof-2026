#!/bin/bash

# Credenciales de la base de datos para Spring Boot (username, password, dbname).
# H2 es embebida: no hay host ni puerto que guardar en el secreto.
SECRET_NAME="prod/h2/admin"

DB_USER="admin"
DB_NAME="eventhub"



if [ -z "$1" ] || [ -n "$2" ]; then
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create"
    echo "  $0 delete"
    exit 1
fi

ACTION="$1"

case "$ACTION" in
    create)
        if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
            echo "El secreto '$SECRET_NAME' ya existe; se reutiliza."
            exit 0
        fi

        # La contraseña la genera Secrets Manager (no sale del portátil).
        # SecretStringTemplate es el JSON sin password; GenerateStringKey indica
        # en qué clave inserta AWS la password.
        GENERATE_SPEC=$(jq -c -n \
          --arg user "$DB_USER" \
          --arg dbname "$DB_NAME" \
          '{
            SecretStringTemplate: ({
              username: $user,
              dbname: $dbname
            } | tostring),
            GenerateStringKey: "password",
            PasswordLength: 32,
            ExcludeCharacters: "/\"@'\''\\"
          }')

        echo "Creando el secreto '$SECRET_NAME' (password generada por Secrets Manager)..."
        # Parámetros:
        # --name: Nombre del secreto que importará Spring Boot
        # --generate-secret-string: AWS genera la password y la mete en el JSON
        # --query: Solo el ARN, para no imprimir el SecretString
        # ARN (Amazon Resource Name): identificador único del recurso en AWS
        # (servicio, región, cuenta y nombre; p. ej. arn:aws:secretsmanager:us-east-1:123:secret:prod/h2/admin-AbCdEf)
        SECRET_ARN=$(aws secretsmanager create-secret \
            --name "$SECRET_NAME" \
            --description "Credenciales de administración ($DB_USER) para la base de datos '$DB_NAME'." \
            --generate-secret-string "$GENERATE_SPEC" \
            --query ARN \
            --output text)
        if [ -z "$SECRET_ARN" ] || [ "$SECRET_ARN" = "None" ]; then
            echo "Error al crear el secreto '$SECRET_NAME'."
            exit 1
        fi

        echo "Secreto creado: $SECRET_ARN"
        ;;

    delete)
        if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" >/dev/null 2>&1; then
            echo "Eliminando el secreto '$SECRET_NAME'..."
            # Parámetros:
            # --secret-id: Nombre o ARN del secreto
            # --force-delete-without-recovery: Borrado inmediato (laboratorio)
            aws secretsmanager delete-secret \
                --secret-id "$SECRET_NAME" \
                --force-delete-without-recovery
            echo "Secreto eliminado."
        else
            echo "El secreto '$SECRET_NAME' no existe."
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
