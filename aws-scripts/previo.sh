#!/bin/bash

# Comprobación previa al despliegue. Es lo primero que ejecuta make deploy.
#
# Esta versión (5.1.0) reutiliza la base de datos Aurora que los alumnos ya crearon en la
# versión 4.0.0, si existe, y despliega todo lo demás. Si no existe, la crea. Para que no haya
# conflictos, no debe quedar en la cuenta nada más de eventhub de las versiones anteriores,
# salvo las bases de datos.
#
# Decisión de diseño: si el script encuentra restos de eventhub, se detiene antes de crear
# nada y pide al alumno que los elimine él, en lugar de borrarlos por su cuenta. Son recursos
# de otras versiones que el alumno puede estar usando, y borrarlos no se puede deshacer.
# Las bases de datos nunca se consideran restos: se reutilizan.
#
# No crea, modifica ni borra nada. Termina con error si encuentra restos.
set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Nombres que usan los scripts de las versiones 4.0.0, 5.0.0 y 5.1.0
SG_NAME="eventhub-sg"
ALB_SG_NAME="eventhub-alb-sg"
NGINX_SG_NAME="eventhub-nginx-sg"
ALB_NAME="eventhub-alb"
CLUSTER_NAME="eventhub"
POOL_NAME="eventhub-pool"
REPOSITORIES="eventhub-back"
LOG_GROUPS="/ecs/eventhub-back"
DB_CLUSTER_ID="eventhub-cluster-aurora"

PROBLEMAS=()
ACCIONES=()

# problema "descripción" "qué hacer"
problema() {
    PROBLEMAS+=("$1")
    ACCIONES+=("$2")
}

echo "Comprobando que no quedan restos de eventhub de versiones anteriores..."

AWS_REGION=$(aws configure get region 2>/dev/null || true)
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
if [ -z "$AWS_REGION" ]; then
    echo "Error: No hay región AWS configurada (aws configure get region / AWS_DEFAULT_REGION)."
    exit 1
fi
if ! AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null); then
    echo "Error: No se pudieron obtener las credenciales de AWS. Descárgalas desde AWS Academy a ~/.aws/credentials."
    exit 1
fi

# --- Grupo de seguridad de eventhub: instancias EC2 y reglas abiertas a Internet (versión 4.0.0)
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    INSTANCIAS=$(aws ec2 describe-instances \
        --filters "Name=instance.group-id,Values=$SG_ID" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)
    for INSTANCIA in $INSTANCIAS; do
        problema "Instancia EC2 $INSTANCIA, con el grupo de seguridad '$SG_NAME'" \
                 "Termínala: aws ec2 terminate-instances --instance-ids $INSTANCIA"
        IPS=$(aws ec2 describe-addresses \
            --filters "Name=instance-id,Values=$INSTANCIA" \
            --query 'Addresses[].AllocationId' --output text 2>/dev/null || true)
        for IP in $IPS; do
            problema "Dirección IP elástica $IP, asociada a esa instancia" \
                     "Libérala: aws ec2 release-address --allocation-id $IP (después de terminar la instancia)"
        done
    done

    # Reglas de entrada con origen 0.0.0.0/0: las tareas de Fargate usarían este mismo grupo
    REGLAS=$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
        --query 'SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]].[IpProtocol,FromPort,ToPort]' \
        --output text 2>/dev/null || true)
    while read -r PROTO DESDE HASTA; do
        [ -z "${PROTO:-}" ] && continue
        problema "El grupo '$SG_NAME' admite el puerto $DESDE desde cualquier dirección de Internet" \
                 "Quita la regla: aws ec2 revoke-security-group-ingress --group-id $SG_ID --protocol $PROTO --port $DESDE --cidr 0.0.0.0/0"
    done <<< "$REGLAS"
fi

# --- Grupo de seguridad del balanceador (versiones 5.x)
ALB_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$ALB_SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
if [ -n "$ALB_SG_ID" ] && [ "$ALB_SG_ID" != "None" ]; then
    problema "Grupo de seguridad '$ALB_SG_NAME' ($ALB_SG_ID)" \
             "Elimínalo, después de borrar el balanceador y de quitar su regla del grupo '$SG_NAME'"
fi

# --- Grupo de seguridad de Nginx, su instancia y el bucket del frontend (versiones 5.x)
NGINX_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$NGINX_SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)
if [ -n "$NGINX_SG_ID" ] && [ "$NGINX_SG_ID" != "None" ]; then
    NGINX_INSTANCIAS=$(aws ec2 describe-instances \
        --filters "Name=instance.group-id,Values=$NGINX_SG_ID" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || true)
    for INSTANCIA in $NGINX_INSTANCIAS; do
        problema "Instancia EC2 $INSTANCIA, con el grupo de seguridad '$NGINX_SG_NAME'" \
                 "Termínala: aws ec2 terminate-instances --instance-ids $INSTANCIA"
        IPS=$(aws ec2 describe-addresses \
            --filters "Name=instance-id,Values=$INSTANCIA" \
            --query 'Addresses[].AllocationId' --output text 2>/dev/null || true)
        for IP in $IPS; do
            problema "Dirección IP elástica $IP, asociada a esa instancia" \
                     "Libérala: aws ec2 release-address --allocation-id $IP (después de terminar la instancia)"
        done
    done
    problema "Grupo de seguridad '$NGINX_SG_NAME' ($NGINX_SG_ID)" \
             "Elimínalo, después de terminar la instancia"
fi

BUCKET_NAME="eventhub-front-${AWS_ACCOUNT_ID}-${AWS_REGION}"
if aws s3api head-bucket --bucket "$BUCKET_NAME" >/dev/null 2>&1; then
    problema "Bucket de S3 '$BUCKET_NAME'" \
             "Vacíalo y elimínalo: aws s3 rb s3://$BUCKET_NAME --force"
fi

# --- Balanceador, clúster de ECS, repositorios y logs (versiones 5.x)
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
    problema "Balanceador '$ALB_NAME'" \
             "Elimínalo con sus listeners y grupos de destino (consola de EC2, Balanceadores de carga)"
fi

CLUSTER_ESTADO=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" \
    --query 'clusters[0].status' --output text 2>/dev/null || true)
if [ "$CLUSTER_ESTADO" = "ACTIVE" ]; then
    problema "Clúster de ECS '$CLUSTER_NAME'" \
             "Elimina sus servicios y el clúster (consola de ECS)"
fi

for REPOSITORIO in $REPOSITORIES; do
    if aws ecr describe-repositories --repository-names "$REPOSITORIO" >/dev/null 2>&1; then
        problema "Repositorio de ECR '$REPOSITORIO'" \
                 "Elimínalo: aws ecr delete-repository --repository-name $REPOSITORIO --force"
    fi
done

for GRUPO in $LOG_GROUPS; do
    EXISTE=$(aws logs describe-log-groups --log-group-name-prefix "$GRUPO" \
        --query "logGroups[?logGroupName=='$GRUPO'].logGroupName" --output text 2>/dev/null || true)
    if [ -n "$EXISTE" ]; then
        problema "Grupo de logs '$GRUPO'" \
                 "Elimínalo: aws logs delete-log-group --log-group-name $GRUPO"
    fi
done

# --- Cognito (versiones 2.0.0 en adelante)
POOL_IDS=$(aws cognito-idp list-user-pools --max-results 60 \
    --query "UserPools[?Name=='$POOL_NAME'].Id" --output text 2>/dev/null || true)
for POOL_ID in $POOL_IDS; do
    problema "User Pool de Cognito '$POOL_NAME' ($POOL_ID)" \
             "Bórralo: aws cognito-idp delete-user-pool --user-pool-id $POOL_ID (antes, su dominio: aws cognito-idp delete-user-pool-domain)"
done
DOMINIO="muii-prof-2026-${AWS_ACCOUNT_ID}"
DOMINIO_POOL=$(aws cognito-idp describe-user-pool-domain --domain "$DOMINIO" \
    --query 'DomainDescription.UserPoolId' --output text 2>/dev/null || true)
if [ -n "$DOMINIO_POOL" ] && [ "$DOMINIO_POOL" != "None" ]; then
    problema "Dominio de Cognito '$DOMINIO'" \
             "Bórralo: aws cognito-idp delete-user-pool-domain --domain $DOMINIO --user-pool-id $DOMINIO_POOL"
fi

# --- Resultado
if [ ${#PROBLEMAS[@]} -gt 0 ]; then
    echo ""
    echo "Se han encontrado restos de eventhub que pueden entrar en conflicto con este despliegue:"
    for i in "${!PROBLEMAS[@]}"; do
        echo ""
        echo "  - ${PROBLEMAS[$i]}"
        echo "      ${ACCIONES[$i]}"
    done
    echo ""
    echo "Elimina todo lo que se refiera a eventhub, excepto las bases de datos, y vuelve a ejecutar make deploy."
    echo "No se ha creado ni modificado nada. Las bases de datos, y el grupo de seguridad '$SG_NAME' que"
    echo "usan, no se borran: se reutilizan."
    exit 1
fi

# Aurora: si ya existe, se reutiliza. Se avisa y se pide confirmación, porque make delete
# (aurora.sh delete) preguntará después si se conserva o se borra, y borrarla no se puede deshacer.
# Sin terminal (por ejemplo, en un script) no se pregunta y se continúa.
CLUSTER_DB=$(aws rds describe-db-clusters --db-cluster-identifier "$DB_CLUSTER_ID" \
    --query 'DBClusters[0].Status' --output text 2>/dev/null || true)
if [ -n "$CLUSTER_DB" ] && [ "$CLUSTER_DB" != "None" ]; then
    echo "Aurora: el clúster '$DB_CLUSTER_ID' ya existe (estado: $CLUSTER_DB). Se reutilizará y no se creará otro."
    echo "Con make delete se te preguntará si lo conservas o lo borras."
    if [ -t 0 ]; then
        read -r -p "¿Quieres continuar el despliegue con esa base de datos? [S/n] " RESPUESTA
        case "$RESPUESTA" in
            [nN]|[nN][oO])
                echo "Despliegue cancelado. No se ha creado ni modificado nada."
                exit 1
                ;;
        esac
    fi
else
    echo "Aurora: el clúster '$DB_CLUSTER_ID' no existe. Se creará."
fi
echo "Comprobación previa finalizada: no hay restos de eventhub."
