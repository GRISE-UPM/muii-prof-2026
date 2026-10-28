#!/bin/bash

# Compila el backend, construye su imagen Docker, la sube a ECR y la despliega en ECS
# con Fargate: dos tareas detrás del balanceador.
# No tiene delete: el servicio y las tareas se borran con ecs.sh delete.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"
BACKEND_PATH="$PROJECT_ROOT/eventhub-back-springboot"
RESOURCES_PATH="$BACKEND_PATH/src/main/resources"

# Constantes. EcsService y TaskDefinitionArn se escriben en lab-state.json.
SERVICE_NAME="eventhub-back"
TASK_FAMILY="eventhub-back"
CONTAINER_NAME="eventhub-back"
BACK_PORT=8080
DESIRED_COUNT=2

# CPU y memoria de cada tarea: 0,5 vCPU y 1 GiB
TASK_CPU="512"
TASK_MEMORY="1024"

# Segundos que el balanceador espera antes de dar por muerta una tarea que arranca:
# Spring Boot tarda en levantar el contexto.
HEALTH_GRACE_SECONDS=120

# EcrRepositoryUri, EcsCluster y LogGroup los escribió ecs.sh; TargetGroupArn, alb.sh;
# SubnetIds y GroupId, red.sh.
REPOSITORY_URI=$(state_require EcrRepositoryUri)
CLUSTER_NAME=$(state_require EcsCluster)
LOG_GROUP=$(state_require LogGroup)
TG_ARN=$(state_require TargetGroupArn)
SUBNET_IDS=$(state_require SubnetIds)
SG_ID=$(state_require GroupId)

AWS_REGION=$(aws configure get region 2>/dev/null || true)
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [ -z "$AWS_REGION" ]; then
    echo "Error: No hay región AWS configurada (aws configure get region / AWS_DEFAULT_REGION)."
    exit 1
fi
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# LabRole de AWS Academy: con él la tarea descarga la imagen, escribe los logs
# (rol de ejecución) y lee el secreto de Aurora (rol de la tarea).
LAB_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/LabRole"

# La configuración generada viaja dentro del JAR: sin ella el backend no arranca.
for FILE in cognito.properties aurora.properties; do
    if [ ! -f "$RESOURCES_PATH/$FILE" ]; then
        echo "Error: Falta $RESOURCES_PATH/$FILE. Ejecuta antes cognito.sh create y aurora.sh create."
        exit 1
    fi
done

# La imagen se construye para la arquitectura de este equipo, y la tarea se
# ejecuta en Fargate con la misma: así no hace falta emular otra CPU.
case "$(uname -m)" in
    arm64|aarch64)
        DOCKER_PLATFORM="linux/arm64"
        CPU_ARCHITECTURE="ARM64"
        ;;
    *)
        DOCKER_PLATFORM="linux/amd64"
        CPU_ARCHITECTURE="X86_64"
        ;;
esac

echo "Compilando el backend Spring Boot..."
cd "$BACKEND_PATH"
mvn clean package -DskipTests

# Etiqueta fija: cada despliegue sustituye la imagen anterior en ECR (la antigua queda
# sin etiqueta). Como la definición de tarea no cambia, update-service usa
# --force-new-deployment para que ECS arranque tareas nuevas y descargue la imagen.
IMAGE_TAG="latest"
IMAGE_URI="$REPOSITORY_URI:$IMAGE_TAG"

echo "Construyendo la imagen $IMAGE_URI ($DOCKER_PLATFORM)..."
docker build --platform "$DOCKER_PLATFORM" -t "$IMAGE_URI" .
cd - > /dev/null

echo "Subiendo la imagen a ECR..."

# El registro es la parte del URI anterior a la primera barra.
# get-login-password: contraseña temporal de ECR; docker login la lee de la entrada estándar.
REGISTRY="${REPOSITORY_URI%%/*}"
aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"
docker push "$IMAGE_URI"

echo "Registrando la definición de tarea '$TASK_FAMILY'..."

# awsvpc: cada tarea tiene su propia interfaz de red en una subnet de la VPC.
# executionRoleArn: rol de ECS para descargar la imagen y escribir los logs.
# taskRoleArn: rol de la aplicación para leer el secreto de Aurora.
# runtimePlatform: la arquitectura con la que se construyó la imagen.
# awslogs: la salida de Spring Boot va al grupo de logs de CloudWatch.
TASK_DEF=$(mktemp)
jq -n \
    --arg family "$TASK_FAMILY" \
    --arg cpu "$TASK_CPU" \
    --arg memory "$TASK_MEMORY" \
    --arg role "$LAB_ROLE_ARN" \
    --arg arch "$CPU_ARCHITECTURE" \
    --arg name "$CONTAINER_NAME" \
    --arg image "$IMAGE_URI" \
    --argjson port "$BACK_PORT" \
    --arg logGroup "$LOG_GROUP" \
    --arg region "$AWS_REGION" \
    '{
      family: $family,
      networkMode: "awsvpc",
      requiresCompatibilities: ["FARGATE"],
      cpu: $cpu,
      memory: $memory,
      executionRoleArn: $role,
      taskRoleArn: $role,
      runtimePlatform: {operatingSystemFamily: "LINUX", cpuArchitecture: $arch},
      containerDefinitions: [{
        name: $name,
        image: $image,
        essential: true,
        portMappings: [{containerPort: $port, protocol: "tcp"}],
        logConfiguration: {
          logDriver: "awslogs",
          options: {"awslogs-group": $logGroup, "awslogs-region": $region, "awslogs-stream-prefix": "back"}
        }
      }]
    }' > "$TASK_DEF"

TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json "file://$TASK_DEF" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)
rm -f "$TASK_DEF"
state_set TaskDefinitionArn "$TASK_DEF_ARN"

# Las dos subnets, en zonas distintas, separadas por comas para la CLI.
SUBNETS_CSV=$(echo "$SUBNET_IDS" | tr ' ' ',')

if [ -z "$(state_get EcsService)" ]; then
    echo "Creando el servicio '$SERVICE_NAME' con $DESIRED_COUNT tareas..."

    # --network-configuration: las tareas van en las dos subnets, con el grupo
    #   de las tareas. assignPublicIp: la VPC por defecto no tiene NAT, y las
    #   tareas necesitan salir a Internet (ECR, Secrets Manager, Cognito).
    # --load-balancers: ECS registra cada tarea en el grupo de destino del balanceador.
    # --health-check-grace-period-seconds: margen para que arranque Spring Boot.
    aws ecs create-service \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --desired-count "$DESIRED_COUNT" \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS_CSV],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
        --load-balancers "targetGroupArn=$TG_ARN,containerName=$CONTAINER_NAME,containerPort=$BACK_PORT" \
        --health-check-grace-period-seconds "$HEALTH_GRACE_SECONDS" \
        --output text >/dev/null
    state_set EcsService "$SERVICE_NAME"
else
    echo "Actualizando el servicio '$SERVICE_NAME' con la nueva imagen..."

    # ECS sustituye las tareas poco a poco: las nuevas entran en el balanceador
    # antes de que se paren las antiguas.
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --force-new-deployment \
        --output text >/dev/null
fi

echo "Esperando a que el servicio esté estable (puede tardar varios minutos)..."
aws ecs wait services-stable --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"

ALB_DNS=$(state_get LoadBalancerDns)
echo "La imagen queda en ECR y las tareas en ECS, detrás del balanceador. No van en el repositorio:"
echo "  $IMAGE_URI"
if [ -n "$ALB_DNS" ]; then
    echo "  https://$ALB_DNS/api/eventos"
fi
echo "Despliegue del backend finalizado."
