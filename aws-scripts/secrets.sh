#!/bin/bash

# Crea o borra el secreto de H2 en Secrets Manager.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

# Credenciales de H2 para Spring Boot. H2 es embebida: no hay host ni puerto.
SECRET_NAME="prod/h2/admin"

# En H2 el usuario puede ser cualquiera. En Aurora PostgreSQL no puede llamarse admin.
DB_USER="admin"
DB_NAME="eventhub"

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create"
    echo "  $0 delete"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

case "$ACTION" in
    create)
        echo "Generando la password con Secrets Manager..."

        # ExcludeCharacters: /, ", @, ' y \ suelen romper JSON, JDBC, SQL o el shell.
        DB_PASS=$(aws secretsmanager get-random-password \
            --password-length 32 \
            --exclude-characters "/\"@'\\" \
            --query RandomPassword \
            --output text)
        if [ -z "$DB_PASS" ] || [ "$DB_PASS" = "None" ]; then
            echo "Error: No se pudo generar la password."
            exit 1
        fi

        SECRET_JSON=$(jq -c -n \
            --arg user "$DB_USER" \
            --arg pass "$DB_PASS" \
            --arg dbname "$DB_NAME" \
            '{username: $user, password: $pass, dbname: $dbname}')
        unset DB_PASS

        echo "Creando el secreto '$SECRET_NAME'..."

        # --secret-string: JSON con username, password y dbname. No se imprime.
        SECRET_ARN=$(aws secretsmanager create-secret \
            --name "$SECRET_NAME" \
            --description "Credenciales de administración ($DB_USER) para la base de datos '$DB_NAME'." \
            --secret-string "$SECRET_JSON" \
            --query ARN \
            --output text)
        unset SECRET_JSON

        echo "El secreto queda en Secrets Manager. Spring lo importa por el nombre; la password no va en el código:"
        echo "  $SECRET_NAME"
        echo "  $SECRET_ARN"
        echo "Creación del secreto finalizada."
        ;;

    delete)
        echo "Eliminando el secreto '$SECRET_NAME'..."

        # --force-delete-without-recovery: borrado inmediato, sin ventana de recuperación
        aws secretsmanager delete-secret \
            --secret-id "$SECRET_NAME" \
            --force-delete-without-recovery \
            --output text >/dev/null
        echo "Secreto eliminado."
        ;;

    *)
        usage
        ;;
esac
