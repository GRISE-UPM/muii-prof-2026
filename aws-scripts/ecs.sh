#!/bin/bash

# Crea o borra el repositorio de imágenes (ECR), el grupo de logs y el clúster de ECS.
# El servicio y las tareas los crea back.sh; aquí se borran con el clúster.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. EcrRepositoryUri, EcsCluster y LogGroup se escriben en lab-state.json
# al hacer create; EcsService y TaskDefinitionArn los escribe back.sh.
REPOSITORY_NAME="eventhub-back"
CLUSTER_NAME="eventhub"
LOG_GROUP="/ecs/eventhub-back"
TASK_FAMILY="eventhub-back"
LOG_RETENTION_DAYS=7

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create # Crea el repositorio ECR, el grupo de logs y el clúster"
    echo "  $0 delete # Borra el servicio, las definiciones de tarea, el clúster, los logs y el repositorio"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

case "$ACTION" in
    create)
        echo "Creando el repositorio de imágenes '$REPOSITORY_NAME'..."

        # ECR: registro privado de imágenes Docker de la cuenta. ECS descarga de aquí la imagen.
        REPOSITORY_URI=$(aws ecr create-repository \
            --repository-name "$REPOSITORY_NAME" \
            --query 'repository.repositoryUri' \
            --output text)
        state_set EcrRepositoryUri "$REPOSITORY_URI"
        echo "Repositorio creado: $REPOSITORY_URI"

        echo "Creando el grupo de logs '$LOG_GROUP'..."

        # Las tareas envían aquí la salida de Spring Boot (driver awslogs).
        # --retention-in-days: los logs se borran solos pasada una semana
        aws logs create-log-group --log-group-name "$LOG_GROUP"
        aws logs put-retention-policy \
            --log-group-name "$LOG_GROUP" \
            --retention-in-days "$LOG_RETENTION_DAYS"
        state_set LogGroup "$LOG_GROUP"

        echo "Creando el clúster de ECS '$CLUSTER_NAME'..."

        # Con Fargate, el clúster no contiene máquinas: solo agrupa los servicios.
        aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --output text >/dev/null
        state_set EcsCluster "$CLUSTER_NAME"

        echo "El repositorio, el grupo de logs y el clúster quedan en lab-state.json. back.sh los usa al desplegar:"
        echo "  $LAB_STATE_FILE"
        echo "Creación de ECS finalizada."
        ;;

    delete)

        # El servicio se para y se borra antes que el clúster. Las definiciones de
        # tarea se dan de baja: ECS no deja borrarlas mientras estén activas.
        CLUSTER_NAME=$(state_require EcsCluster)
        LOG_GROUP=$(state_require LogGroup)
        SERVICE_NAME=$(state_get EcsService)

        if [ -n "$SERVICE_NAME" ]; then
            echo "Eliminando el servicio '$SERVICE_NAME' y sus tareas..."

            # --force: borra el servicio aunque aún tenga tareas en marcha
            aws ecs delete-service \
                --cluster "$CLUSTER_NAME" \
                --service "$SERVICE_NAME" \
                --force \
                --output text >/dev/null
            aws ecs wait services-inactive --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"
        fi

        echo "Dando de baja las definiciones de tarea '$TASK_FAMILY'..."
        for TASK_DEF in $(aws ecs list-task-definitions \
                --family-prefix "$TASK_FAMILY" \
                --query 'taskDefinitionArns[]' \
                --output text); do
            aws ecs deregister-task-definition --task-definition "$TASK_DEF" --output text >/dev/null
        done

        echo "Eliminando el clúster '$CLUSTER_NAME'..."
        aws ecs delete-cluster --cluster "$CLUSTER_NAME" --output text >/dev/null

        echo "Eliminando el grupo de logs '$LOG_GROUP'..."
        aws logs delete-log-group --log-group-name "$LOG_GROUP"

        echo "Eliminando el repositorio '$REPOSITORY_NAME' y sus imágenes..."

        # --force: borra el repositorio aunque contenga imágenes
        aws ecr delete-repository \
            --repository-name "$REPOSITORY_NAME" \
            --force \
            --output text >/dev/null

        tmp=$(mktemp)
        jq 'del(.EcrRepositoryUri, .EcsCluster, .LogGroup, .EcsService, .TaskDefinitionArn)' \
            "$LAB_STATE_FILE" > "$tmp"
        mv "$tmp" "$LAB_STATE_FILE"
        echo "ECS eliminado."
        ;;

    *)
        usage
        ;;
esac
