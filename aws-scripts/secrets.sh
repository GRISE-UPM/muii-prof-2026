#!/bin/bash

# Credenciales de la base de datos para Spring Boot (username, password, dbname).
# H2 es embebida: no hay host ni puerto que guardar en el secreto.
SECRET_NAME="prod/h2/admin"

# El nombre del administrador depende de la base de datos.
# En H2 el nombre puede ser cualquiera (aqui, admin).
# En PostgreSQL/Aurora (V4.0.0) el usuario master es obligatorio (no puede llamarse admin).
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

        # Password con get-random-password (compatible con AWS CLI que no
        # admite --generate-secret-string en create-secret).
        # ExcludeCharacters: /, ", @, ' y \ — suelen romper JSON, JDBC, SQL o el shell.
        echo "Generando password con Secrets Manager..."
        DB_PASS=$(aws secretsmanager get-random-password \
            --password-length 32 \
            --exclude-characters "/\"@'\\" \
            --query RandomPassword \
            --output text)
        if [ -z "$DB_PASS" ] || [ "$DB_PASS" = "None" ]; then
            echo "Error al generar la password con get-random-password."
            exit 1
        fi

        SECRET_JSON=$(jq -c -n \
            --arg user "$DB_USER" \
            --arg pass "$DB_PASS" \
            --arg dbname "$DB_NAME" \
            '{
              username: $user,
              password: $pass,
              dbname: $dbname
            }')
        unset DB_PASS

        echo "Creando el secreto '$SECRET_NAME'..."
        # Parámetros:
        # --name: Nombre del secreto que importará Spring Boot
        # --secret-string: JSON con username, password y dbname
        # --query: Solo el ARN, para no imprimir el SecretString
        # ARN (Amazon Resource Name): identificador único del recurso en AWS
        # (servicio, región, cuenta y nombre; p. ej. arn:aws:secretsmanager:us-east-1:123:secret:prod/h2/admin-AbCdEf)
        SECRET_ARN=$(aws secretsmanager create-secret \
            --name "$SECRET_NAME" \
            --description "Credenciales de administración ($DB_USER) para la base de datos '$DB_NAME'." \
            --secret-string "$SECRET_JSON" \
            --query ARN \
            --output text)
        unset SECRET_JSON
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
