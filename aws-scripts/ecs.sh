#!/bin/bash

# Crea o borra los repositorios de imágenes (ECR), los grupos de logs y el clúster de ECS.
# Hay un repositorio y un grupo de logs para el backend y otros para el frontend.
# Los servicios y las tareas los crean back.sh y front.sh; aquí se borran con el clúster.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"

# Constantes. EcrRepositoryUri, FrontEcrRepositoryUri, EcsCluster, LogGroup y FrontLogGroup
# se escriben en lab-state.json al hacer create; EcsService, FrontEcsService y
# TaskDefinitionArn los escriben back.sh y front.sh.
BACK_REPOSITORY_NAME="eventhub-back"
FRONT_REPOSITORY_NAME="eventhub-front"
CLUSTER_NAME="eventhub"
BACK_LOG_GROUP="/ecs/eventhub-back"
FRONT_LOG_GROUP="/ecs/eventhub-front"
BACK_TASK_FAMILY="eventhub-back"
FRONT_TASK_FAMILY="eventhub-front"
LOG_RETENTION_DAYS=7

usage() {
    echo "Uso: $0 {create|delete}"
    echo ""
    echo "Ejemplos:"
    echo "  $0 create # Crea los repositorios ECR, los grupos de logs y el clúster"
    echo "  $0 delete # Borra los servicios, las definiciones de tarea, el clúster, los logs y los repositorios"
    exit 1
}

if [ -z "$1" ] || [ -n "$2" ]; then
    usage
fi

ACTION="$1"

case "$ACTION" in
    create)
        echo "Creando el repositorio de imágenes del backend '$BACK_REPOSITORY_NAME'..."

        # ECR: registro privado de imágenes Docker de la cuenta. ECS descarga de aquí la imagen.
        BACK_REPOSITORY_URI=$(aws ecr create-repository \
            --repository-name "$BACK_REPOSITORY_NAME" \
            --query 'repository.repositoryUri' \
            --output text)
        state_set EcrRepositoryUri "$BACK_REPOSITORY_URI"
        echo "Repositorio creado: $BACK_REPOSITORY_URI"

        echo "Creando el repositorio de imágenes del frontend '$FRONT_REPOSITORY_NAME'..."
        FRONT_REPOSITORY_URI=$(aws ecr create-repository \
            --repository-name "$FRONT_REPOSITORY_NAME" \
            --query 'repository.repositoryUri' \
            --output text)
        state_set FrontEcrRepositoryUri "$FRONT_REPOSITORY_URI"
        echo "Repositorio creado: $FRONT_REPOSITORY_URI"

        echo "Creando los grupos de logs..."

        # Las tareas envían aquí su salida (driver awslogs).
        # --retention-in-days: los logs se borran solos pasada una semana
        for LOG_GROUP in "$BACK_LOG_GROUP" "$FRONT_LOG_GROUP"; do
            aws logs create-log-group --log-group-name "$LOG_GROUP"
            aws logs put-retention-policy \
                --log-group-name "$LOG_GROUP" \
                --retention-in-days "$LOG_RETENTION_DAYS"
        done
        state_set LogGroup "$BACK_LOG_GROUP"
        state_set FrontLogGroup "$FRONT_LOG_GROUP"

        echo "Creando el clúster de ECS '$CLUSTER_NAME'..."

        # Con Fargate, el clúster no contiene máquinas: solo agrupa los servicios.
        aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --output text >/dev/null
        state_set EcsCluster "$CLUSTER_NAME"

        echo "Los repositorios, los grupos de logs y el clúster quedan en lab-state.json. back.sh y front.sh los usan al desplegar:"
        echo "  $LAB_STATE_FILE"
        echo "Creación de ECS finalizada."
        ;;

    delete)

        # Los servicios se paran y se borran antes que el clúster. Las definiciones de
        # tarea se dan de baja: ECS no deja borrarlas mientras estén activas.
        CLUSTER_NAME=$(state_require EcsCluster)
        BACK_LOG_GROUP=$(state_require LogGroup)
        FRONT_LOG_GROUP=$(state_require FrontLogGroup)

        for SERVICE_KEY in EcsService FrontEcsService; do
            SERVICE_NAME=$(state_get "$SERVICE_KEY")
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
        done

        for TASK_FAMILY in "$BACK_TASK_FAMILY" "$FRONT_TASK_FAMILY"; do
            echo "Dando de baja las definiciones de tarea '$TASK_FAMILY'..."
            for TASK_DEF in $(aws ecs list-task-definitions \
                    --family-prefix "$TASK_FAMILY" \
                    --query 'taskDefinitionArns[]' \
                    --output text); do
                aws ecs deregister-task-definition --task-definition "$TASK_DEF" --output text >/dev/null
            done
        done

        echo "Eliminando el clúster '$CLUSTER_NAME'..."
        aws ecs delete-cluster --cluster "$CLUSTER_NAME" --output text >/dev/null

        for LOG_GROUP in "$BACK_LOG_GROUP" "$FRONT_LOG_GROUP"; do
            echo "Eliminando el grupo de logs '$LOG_GROUP'..."
            aws logs delete-log-group --log-group-name "$LOG_GROUP"
        done

        for REPOSITORY_NAME in "$BACK_REPOSITORY_NAME" "$FRONT_REPOSITORY_NAME"; do
            echo "Eliminando el repositorio '$REPOSITORY_NAME' y sus imágenes..."

            # --force: borra el repositorio aunque contenga imágenes
            aws ecr delete-repository \
                --repository-name "$REPOSITORY_NAME" \
                --force \
                --output text >/dev/null
        done

        tmp=$(mktemp)
        jq 'del(.EcrRepositoryUri, .FrontEcrRepositoryUri, .EcsCluster, .LogGroup, .FrontLogGroup, .EcsService, .FrontEcsService, .TaskDefinitionArn, .FrontTaskDefinitionArn)' \
            "$LAB_STATE_FILE" > "$tmp"
        mv "$tmp" "$LAB_STATE_FILE"
        echo "ECS eliminado."
        ;;

    *)
        usage
        ;;
esac
