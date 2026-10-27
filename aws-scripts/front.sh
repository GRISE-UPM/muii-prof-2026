#!/bin/bash

# Compila el frontend, construye su imagen Docker con Nginx, la sube a ECR y la despliega
# en ECS con Fargate: dos tareas detrás del balanceador.
# No tiene delete: el servicio y las tareas se borran con ecs.sh delete.
# Termina en el primer comando que falle y muestra el error de ese comando.
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/jq-functions.sh"
APP_PATH="$PROJECT_ROOT/eventhub-front-react"

# Constantes. FrontEcsService y FrontTaskDefinitionArn se escriben en lab-state.json.
SERVICE_NAME="eventhub-front"
TASK_FAMILY="eventhub-front"
CONTAINER_NAME="eventhub-front"
APP_PORT=8080
DESIRED_COUNT=2

# CPU y memoria de cada tarea: 0,25 vCPU y 0,5 GiB, suficiente para servir ficheros estáticos
TASK_CPU="256"
TASK_MEMORY="512"

# Segundos que el balanceador espera antes de dar por muerta una tarea que arranca
HEALTH_GRACE_SECONDS=30

# FrontEcrRepositoryUri, EcsCluster y FrontLogGroup los escribió ecs.sh; FrontTargetGroupArn y
# LoadBalancerDns, alb.sh; SubnetIds y GroupId, red.sh.
REPOSITORY_URI=$(state_require FrontEcrRepositoryUri)
CLUSTER_NAME=$(state_require EcsCluster)
LOG_GROUP=$(state_require FrontLogGroup)
TG_ARN=$(state_require FrontTargetGroupArn)
ALB_DNS=$(state_require LoadBalancerDns)
SUBNET_IDS=$(state_require SubnetIds)
SG_ID=$(state_require GroupId)

if [ ! -d "$APP_PATH" ]; then
    echo "Error: No se encontró el directorio del código fuente en: $APP_PATH"
    exit 1
fi

AWS_REGION=$(aws configure get region 2>/dev/null || true)
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [ -z "$AWS_REGION" ]; then
    echo "Error: No hay región AWS configurada (aws configure get region / AWS_DEFAULT_REGION)."
    exit 1
fi
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# LabRole de AWS Academy: con él la tarea descarga la imagen y escribe los logs
LAB_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/LabRole"

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

# Vite solo carga este fichero con npm run build, no con npm run dev.
# El frontend y la API comparten origen (el balanceador reparte /api/* al backend),
# así que el frontend llama a rutas relativas: VITE_API_BASE_URL queda vacía.
cat > "$APP_PATH/.env.production.local" <<EOF
# Generado por aws-scripts/front.sh. No editar a mano.
# VITE_API_BASE_URL: vacía; la API está en el mismo origen que el frontend (el balanceador)
VITE_API_BASE_URL=
EOF

echo "Compilando la aplicación React..."
cd "$APP_PATH"
npm install
npm run build

# La etiqueta con la fecha distingue cada despliegue; ECS arranca tareas nuevas
# porque la definición de tarea cambia de imagen.
IMAGE_TAG=$(date +%Y%m%d%H%M%S)
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
# runtimePlatform: la arquitectura con la que se construyó la imagen.
# awslogs: la salida de Nginx va al grupo de logs de CloudWatch.
TASK_DEF=$(mktemp)
jq -n \
    --arg family "$TASK_FAMILY" \
    --arg cpu "$TASK_CPU" \
    --arg memory "$TASK_MEMORY" \
    --arg role "$LAB_ROLE_ARN" \
    --arg arch "$CPU_ARCHITECTURE" \
    --arg name "$CONTAINER_NAME" \
    --arg image "$IMAGE_URI" \
    --argjson port "$APP_PORT" \
    --arg logGroup "$LOG_GROUP" \
    --arg region "$AWS_REGION" \
    '{
      family: $family,
      networkMode: "awsvpc",
      requiresCompatibilities: ["FARGATE"],
      cpu: $cpu,
      memory: $memory,
      executionRoleArn: $role,
      runtimePlatform: {operatingSystemFamily: "LINUX", cpuArchitecture: $arch},
      containerDefinitions: [{
        name: $name,
        image: $image,
        essential: true,
        portMappings: [{containerPort: $port, protocol: "tcp"}],
        logConfiguration: {
          logDriver: "awslogs",
          options: {"awslogs-group": $logGroup, "awslogs-region": $region, "awslogs-stream-prefix": "front"}
        }
      }]
    }' > "$TASK_DEF"

TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json "file://$TASK_DEF" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)
rm -f "$TASK_DEF"
state_set FrontTaskDefinitionArn "$TASK_DEF_ARN"

# Las dos subnets, en zonas distintas, separadas por comas para la CLI.
SUBNETS_CSV=$(echo "$SUBNET_IDS" | tr ' ' ',')

if [ -z "$(state_get FrontEcsService)" ]; then
    echo "Creando el servicio '$SERVICE_NAME' con $DESIRED_COUNT tareas..."

    # --network-configuration: las tareas van en las dos subnets, con el grupo
    #   de las tareas. assignPublicIp: la VPC por defecto no tiene NAT, y las
    #   tareas necesitan salir a Internet para descargar su imagen de ECR.
    # --load-balancers: ECS registra cada tarea en el grupo de destino del frontend.
    # --health-check-grace-period-seconds: margen para que arranque Nginx.
    aws ecs create-service \
        --cluster "$CLUSTER_NAME" \
        --service-name "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --desired-count "$DESIRED_COUNT" \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS_CSV],securityGroups=[$SG_ID],assignPublicIp=ENABLED}" \
        --load-balancers "targetGroupArn=$TG_ARN,containerName=$CONTAINER_NAME,containerPort=$APP_PORT" \
        --health-check-grace-period-seconds "$HEALTH_GRACE_SECONDS" \
        --output text >/dev/null
    state_set FrontEcsService "$SERVICE_NAME"
else
    echo "Actualizando el servicio '$SERVICE_NAME' con la nueva imagen..."

    # ECS sustituye las tareas poco a poco: las nuevas entran en el balanceador
    # antes de que se paren las antiguas.
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --output text >/dev/null
fi

echo "Esperando a que el servicio esté estable (puede tardar varios minutos)..."
aws ecs wait services-stable --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME"

echo "La imagen queda en ECR y las tareas en ECS, detrás del balanceador. No van en el repositorio:"
echo "  $IMAGE_URI"
echo "  https://$ALB_DNS/"
echo "El certificado es autofirmado: el navegador avisará, y hay que aceptarlo."
echo "Despliegue del frontend finalizado."
