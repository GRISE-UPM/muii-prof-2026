#!/bin/bash

# Lista los recursos AWS del laboratorio en docs/resources.json.
# Parte de lab-state.json (red.sh, aurora.sh, alb.sh, nginx.sh, cognito.sh,
# ecs.sh y back.sh) y completa los datos con describe.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/../aws-scripts/jq-functions.sh"

OUT_DIR="$PROJECT_ROOT/docs"
OUT_FILE="$OUT_DIR/resources.json"
VERSION="5.0.0"

mkdir -p "$OUT_DIR"

if [ ! -f "$LAB_STATE_FILE" ]; then
    echo "Error: no existe $LAB_STATE_FILE. Ejecuta antes: make deploy"
    exit 1
fi

VPC_ID=$(state_require VpcId)
SUBNET_IDS=$(state_require SubnetIds)
GROUP_ID=$(state_require GroupId)
ALB_GROUP_ID=$(state_require AlbGroupId)

ALB_ARN=$(state_require LoadBalancerArn)
TG_ARN=$(state_require TargetGroupArn)
LISTENER_ARN=$(state_require ListenerArn)

BUCKET_NAME=$(state_require BucketName)
INSTANCE_ID=$(state_require InstanceId)
ALLOCATION_ID=$(state_require AllocationId)

REPOSITORY_URI=$(state_require EcrRepositoryUri)
CLUSTER_NAME=$(state_require EcsCluster)
LOG_GROUP=$(state_require LogGroup)
SERVICE_NAME=$(state_require EcsService)
TASK_DEF_ARN=$(state_require TaskDefinitionArn)

USER_POOL_ID=$(state_require UserPoolId)
CLIENT_ID=$(state_require ClientId)
COGNITO_DOMAIN=$(state_require Domain)
CALLBACK_URL=$(state_require CallbackUrl)
ISSUER_URI=$(state_require IssuerUri)
COGNITO_DOMAIN_URL=$(state_require CognitoDomainUrl)

DB_SUBNET_GROUP=$(state_require DBSubnetGroupName)
DB_CLUSTER_ID=$(state_require DBClusterIdentifier)
DB_SECRET_ARN=$(state_require SecretArn)

REGION=$(state_get Region)
if [ -z "$REGION" ]; then
    REGION=$(aws configure get region 2>/dev/null || true)
fi
if [ -z "$REGION" ]; then
    REGION="${AWS_DEFAULT_REGION:-}"
fi
if [ -z "$REGION" ]; then
    echo "Error: No hay región en lab-state.json ni en la CLI (aws configure / AWS_DEFAULT_REGION)."
    exit 1
fi

ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Consultando recursos V${VERSION} en $REGION..."

VPC_JSON=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --output json)
# shellcheck disable=SC2086
SUBNETS_JSON=$(aws ec2 describe-subnets --subnet-ids $SUBNET_IDS --output json)
SG_JSON=$(aws ec2 describe-security-groups --group-ids "$ALB_GROUP_ID" "$GROUP_ID" --output json)

ALB_JSON=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --output json)
TG_JSON=$(aws elbv2 describe-target-groups --target-group-arns "$TG_ARN" --output json)
# Una entrada por tarea registrada, con su IP y su estado de salud.
TG_HEALTH_JSON=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --output json)
LISTENER_JSON=$(aws elbv2 describe-listeners --listener-arns "$LISTENER_ARN" --output json)

INSTANCE_JSON=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --output json)
ADDRESS_JSON=$(aws ec2 describe-addresses --allocation-ids "$ALLOCATION_ID" --output json)
BUCKET_POLICY_JSON=$(aws s3api get-bucket-policy --bucket "$BUCKET_NAME" --query Policy --output text)
BUCKET_REGION=$(aws s3api get-bucket-location --bucket "$BUCKET_NAME" \
    --query LocationConstraint --output text)
# Fuera de us-east-1 get-bucket-location devuelve la región; en us-east-1, None.
if [ "$BUCKET_REGION" = "None" ]; then
    BUCKET_REGION="us-east-1"
fi
BUCKET_OBJECTS=$(aws s3api list-objects-v2 --bucket "$BUCKET_NAME" \
    --query 'KeyCount' --output text)

REPOSITORY_NAME="${REPOSITORY_URI#*/}"
ECR_JSON=$(aws ecr describe-repositories --repository-names "$REPOSITORY_NAME" --output json)
ECR_IMAGES_JSON=$(aws ecr describe-images --repository-name "$REPOSITORY_NAME" --output json)
LOG_GROUP_JSON=$(aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --output json)

ECS_CLUSTER_JSON=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --output json)
ECS_SERVICE_JSON=$(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$SERVICE_NAME" --output json)
TASK_DEF_JSON=$(aws ecs describe-task-definition --task-definition "$TASK_DEF_ARN" --output json)
TASK_ARNS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --service-name "$SERVICE_NAME" \
    --query 'taskArns[]' --output text)
if [ -n "$TASK_ARNS" ]; then
    # shellcheck disable=SC2086
    TASKS_JSON=$(aws ecs describe-tasks --cluster "$CLUSTER_NAME" --tasks $TASK_ARNS --output json)
else
    TASKS_JSON='{"tasks": []}'
fi

# Rol que usan las tareas (rol de ejecución y rol de la tarea): LabRole en AWS Academy.
TASK_ROLE_ARN=$(echo "$TASK_DEF_JSON" | jq -r '.taskDefinition.taskRoleArn // empty')
if [ -n "$TASK_ROLE_ARN" ]; then
    ROLE_JSON=$(aws iam get-role --role-name "${TASK_ROLE_ARN##*/}" --output json 2>/dev/null \
        || echo '{"Role": null}')
else
    ROLE_JSON='{"Role": null}'
fi

USER_POOL_JSON=$(aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" --output json)
CLIENT_JSON=$(aws cognito-idp describe-user-pool-client \
    --user-pool-id "$USER_POOL_ID" \
    --client-id "$CLIENT_ID" \
    --output json)
DOMAIN_JSON=$(aws cognito-idp describe-user-pool-domain --domain "$COGNITO_DOMAIN" --output json)

DB_SUBNET_GROUP_JSON=$(aws rds describe-db-subnet-groups \
    --db-subnet-group-name "$DB_SUBNET_GROUP" --output json)
DB_CLUSTER_JSON=$(aws rds describe-db-clusters \
    --db-cluster-identifier "$DB_CLUSTER_ID" --output json)
# Todas las instancias del clúster, también las creadas a mano o por autoescalado.
DB_INSTANCES_JSON=$(aws rds describe-db-instances \
    --filters "Name=db-cluster-id,Values=$DB_CLUSTER_ID" --output json)
# describe-secret devuelve los metadatos del secreto, no la password.
SECRET_JSON=$(aws secretsmanager describe-secret --secret-id "$DB_SECRET_ARN" --output json)

jq -n \
    --arg version "$VERSION" \
    --arg region "$REGION" \
    --arg account "$ACCOUNT" \
    --arg generatedAt "$GENERATED_AT" \
    --arg labStateFile "$LAB_STATE_FILE" \
    --arg vpcId "$VPC_ID" \
    --argjson vpc "$VPC_JSON" \
    --argjson subnets "$SUBNETS_JSON" \
    --argjson securityGroups "$SG_JSON" \
    --argjson alb "$ALB_JSON" \
    --argjson targetGroup "$TG_JSON" \
    --argjson targetHealth "$TG_HEALTH_JSON" \
    --argjson listener "$LISTENER_JSON" \
    --arg bucketName "$BUCKET_NAME" \
    --arg bucketRegion "$BUCKET_REGION" \
    --arg bucketObjects "$BUCKET_OBJECTS" \
    --argjson instance "$INSTANCE_JSON" \
    --argjson address "$ADDRESS_JSON" \
    --argjson bucketPolicy "$BUCKET_POLICY_JSON" \
    --argjson ecr "$ECR_JSON" \
    --argjson ecrImages "$ECR_IMAGES_JSON" \
    --argjson logGroups "$LOG_GROUP_JSON" \
    --argjson ecsCluster "$ECS_CLUSTER_JSON" \
    --argjson ecsService "$ECS_SERVICE_JSON" \
    --argjson taskDefinition "$TASK_DEF_JSON" \
    --argjson tasks "$TASKS_JSON" \
    --argjson role "$ROLE_JSON" \
    --arg userPoolId "$USER_POOL_ID" \
    --arg issuerUri "$ISSUER_URI" \
    --argjson userPool "$USER_POOL_JSON" \
    --arg clientId "$CLIENT_ID" \
    --arg callbackUrl "$CALLBACK_URL" \
    --argjson userPoolClient "$CLIENT_JSON" \
    --arg domain "$COGNITO_DOMAIN" \
    --arg cognitoDomainUrl "$COGNITO_DOMAIN_URL" \
    --argjson userPoolDomain "$DOMAIN_JSON" \
    --argjson secret "$SECRET_JSON" \
    --argjson dbSubnetGroup "$DB_SUBNET_GROUP_JSON" \
    --argjson dbCluster "$DB_CLUSTER_JSON" \
    --argjson dbInstances "$DB_INSTANCES_JSON" \
    '{
      version: $version,
      region: $region,
      account: $account,
      generatedAt: $generatedAt,
      source: {labStateFile: $labStateFile},
      resources: (
        [
          {
            type: "AWS::EC2::VPC",
            service: "Amazon VPC",
            id: $vpcId,
            isDefault: ($vpc.Vpcs[0].IsDefault // false),
            cidrBlock: ($vpc.Vpcs[0].CidrBlock // null)
          }
        ]
        + (
          $subnets.Subnets
          | map({
              type: "AWS::EC2::Subnet",
              service: "Amazon VPC",
              id: .SubnetId,
              availabilityZone: .AvailabilityZone,
              cidrBlock: .CidrBlock,
              mapPublicIpOnLaunch: .MapPublicIpOnLaunch
            })
        )
        # Origen de cada regla: rangos IP u otro grupo.
        + (
          $securityGroups.SecurityGroups
          | map({
              type: "AWS::EC2::SecurityGroup",
              service: "Amazon EC2",
              id: .GroupId,
              name: .GroupName,
              vpcId: .VpcId,
              ingress: (
                .IpPermissions
                | map({
                    protocol: .IpProtocol,
                    fromPort: .FromPort,
                    toPort: .ToPort,
                    cidrs: (.IpRanges | map(.CidrIp)),
                    prefixListIds: (.PrefixListIds | map(.PrefixListId)),
                    sourceGroupIds: (.UserIdGroupPairs | map(.GroupId))
                  })
              )
            })
        )
        + [
          ($alb.LoadBalancers[0] | {
            type: "AWS::ElasticLoadBalancingV2::LoadBalancer",
            service: "Elastic Load Balancing",
            id: .LoadBalancerArn,
            name: .LoadBalancerName,
            dnsName: .DNSName,
            scheme: .Scheme,
            state: .State.Code,
            availabilityZones: (.AvailabilityZones | map(.ZoneName)),
            securityGroupIds: .SecurityGroups
          }),
          ($targetGroup.TargetGroups[0] | {
            type: "AWS::ElasticLoadBalancingV2::TargetGroup",
            service: "Elastic Load Balancing",
            id: .TargetGroupArn,
            name: .TargetGroupName,
            protocol: .Protocol,
            port: .Port,
            targetType: .TargetType,
            healthCheckPath: .HealthCheckPath,
            targets: ($targetHealth.TargetHealthDescriptions
              | map({ip: .Target.Id, port: .Target.Port, availabilityZone: .Target.AvailabilityZone, health: .TargetHealth.State}))
          }),
          ($listener.Listeners[0] | {
            type: "AWS::ElasticLoadBalancingV2::Listener",
            service: "Elastic Load Balancing",
            id: .ListenerArn,
            protocol: .Protocol,
            port: .Port,
            targetGroupArn: (.DefaultActions[0].TargetGroupArn // null)
          }),
          {
            type: "AWS::S3::Bucket",
            service: "Amazon S3",
            id: $bucketName,
            region: $bucketRegion,
            objectCount: ($bucketObjects | tonumber? // 0)
          },
          ($bucketPolicy.Statement[0] | {
            type: "AWS::S3::BucketPolicy",
            service: "Amazon S3",
            id: .Sid,
            effect: .Effect,
            action: .Action,
            allowedSourceIp: .Condition.IpAddress."aws:SourceIp"
          }),
          ($instance.Reservations[0].Instances[0] | {
            type: "AWS::EC2::Instance",
            service: "Amazon EC2",
            id: .InstanceId,
            instanceType: .InstanceType,
            state: .State.Name,
            availabilityZone: .Placement.AvailabilityZone,
            publicIp: .PublicIpAddress
          }),
          ($address.Addresses[0] | {
            type: "AWS::EC2::EIP",
            service: "Amazon EC2",
            id: .AllocationId,
            publicIp: .PublicIp,
            instanceId: .InstanceId
          }),
          ($ecr.repositories[0] | {
            type: "AWS::ECR::Repository",
            service: "Amazon ECR",
            id: .repositoryName,
            uri: .repositoryUri,
            imageTags: ($ecrImages.imageDetails | map(.imageTags // []) | add // [])
          }),
          ($logGroups.logGroups[0] | {
            type: "AWS::Logs::LogGroup",
            service: "Amazon CloudWatch Logs",
            id: .logGroupName,
            retentionInDays: (.retentionInDays // null)
          }),
          ($ecsCluster.clusters[0] | {
            type: "AWS::ECS::Cluster",
            service: "Amazon ECS",
            id: .clusterName,
            arn: .clusterArn,
            status: .status,
            runningTasksCount: .runningTasksCount
          }),
          ($taskDefinition.taskDefinition | {
            type: "AWS::ECS::TaskDefinition",
            service: "Amazon ECS",
            id: .taskDefinitionArn,
            family: .family,
            revision: .revision,
            cpu: .cpu,
            memory: .memory,
            cpuArchitecture: (.runtimePlatform.cpuArchitecture // null),
            executionRoleArn: .executionRoleArn,
            taskRoleArn: .taskRoleArn,
            image: .containerDefinitions[0].image
          }),
          ($ecsService.services[0] | {
            type: "AWS::ECS::Service",
            service: "Amazon ECS",
            id: .serviceName,
            arn: .serviceArn,
            status: .status,
            launchType: .launchType,
            desiredCount: .desiredCount,
            runningCount: .runningCount,
            taskDefinition: .taskDefinition,
            subnetIds: .networkConfiguration.awsvpcConfiguration.subnets,
            securityGroupIds: .networkConfiguration.awsvpcConfiguration.securityGroups,
            assignPublicIp: .networkConfiguration.awsvpcConfiguration.assignPublicIp,
            targetGroupArns: (.loadBalancers | map(.targetGroupArn))
          })
        ]
        # Tareas en marcha: cambian con cada despliegue, cada fallo y cada escalado.
        + (
          $tasks.tasks
          | map({
              type: "AWS::ECS::Task",
              service: "Amazon ECS",
              id: .taskArn,
              lastStatus: .lastStatus,
              healthStatus: .healthStatus,
              availabilityZone: .availabilityZone,
              taskDefinitionArn: .taskDefinitionArn,
              privateIp: ([.attachments[]?.details[]? | select(.name == "privateIPv4Address") | .value][0] // null)
            })
        )
        + [
          ($role.Role // {} | {
            type: "AWS::IAM::Role",
            service: "AWS IAM",
            id: (.Arn // null),
            name: (.RoleName // null)
          }),
          {
            type: "AWS::Cognito::UserPool",
            service: "Amazon Cognito",
            id: $userPoolId,
            name: $userPool.UserPool.Name,
            issuerUri: $issuerUri
          },
          {
            type: "AWS::Cognito::UserPoolClient",
            service: "Amazon Cognito",
            id: $clientId,
            name: $userPoolClient.UserPoolClient.ClientName,
            userPoolId: $userPoolId,
            callbackUrl: $callbackUrl,
            callbackUrls: ($userPoolClient.UserPoolClient.CallbackURLs // []),
            logoutUrls: ($userPoolClient.UserPoolClient.LogoutURLs // [])
          },
          {
            type: "AWS::Cognito::UserPoolDomain",
            service: "Amazon Cognito",
            id: $domain,
            userPoolId: $userPoolId,
            status: ($userPoolDomain.DomainDescription.Status // null),
            cognitoDomainUrl: $cognitoDomainUrl
          },
          {
            type: "AWS::SecretsManager::Secret",
            service: "AWS Secrets Manager",
            id: $secret.ARN,
            name: $secret.Name,
            owningService: ($secret.OwningService // null)
          },
          {
            type: "AWS::RDS::DBSubnetGroup",
            service: "Amazon RDS",
            id: $dbSubnetGroup.DBSubnetGroups[0].DBSubnetGroupName,
            vpcId: $dbSubnetGroup.DBSubnetGroups[0].VpcId,
            subnetIds: ($dbSubnetGroup.DBSubnetGroups[0].Subnets | map(.SubnetIdentifier))
          },
          ($dbCluster.DBClusters[0] | {
            type: "AWS::RDS::DBCluster",
            service: "Amazon Aurora",
            id: .DBClusterIdentifier,
            engine: .Engine,
            engineVersion: .EngineVersion,
            status: .Status,
            endpoint: .Endpoint,
            readerEndpoint: .ReaderEndpoint,
            port: .Port,
            databaseName: .DatabaseName,
            masterUsername: .MasterUsername,
            masterUserSecretArn: (.MasterUserSecret.SecretArn // null),
            dbSubnetGroup: .DBSubnetGroup,
            securityGroupIds: (.VpcSecurityGroups | map(.VpcSecurityGroupId)),
            storageEncrypted: .StorageEncrypted,
            backupRetentionPeriod: .BackupRetentionPeriod,
            members: (.DBClusterMembers | map({instanceId: .DBInstanceIdentifier, isWriter: .IsClusterWriter, promotionTier: .PromotionTier}))
          })
        ]
        + (
          ($dbCluster.DBClusters[0].DBClusterMembers
            | map({key: .DBInstanceIdentifier, value: .IsClusterWriter}) | from_entries) as $writers
          | $dbInstances.DBInstances
          | map({
              type: "AWS::RDS::DBInstance",
              service: "Amazon Aurora",
              id: .DBInstanceIdentifier,
              role: (if $writers[.DBInstanceIdentifier] then "writer" else "reader" end),
              instanceClass: .DBInstanceClass,
              status: .DBInstanceStatus,
              availabilityZone: .AvailabilityZone,
              promotionTier: .PromotionTier,
              publiclyAccessible: .PubliclyAccessible,
              endpoint: (.Endpoint.Address // null),
              dbClusterIdentifier: .DBClusterIdentifier
            })
        )
      )
    }' > "$OUT_FILE"

echo "Escrito $OUT_FILE"
jq '{version, region, account, resourceCount: (.resources|length), types: [.resources[].type]}' "$OUT_FILE"
