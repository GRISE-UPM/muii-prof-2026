#!/bin/bash
# Lista los recursos AWS de EventHub V1.0.0 en docs/resources.json.
# Parte de lab-state.json (escrito por ec2.sh) y enriquece con describe-*.
#
# Uso: docs/list-resources.sh

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
# Funciones para leer/escribir el fichero lab-state.json
source "$SCRIPT_DIR/../aws-scripts/jq-functions.sh"

OUT_DIR="$PROJECT_ROOT/docs"
OUT_FILE="$OUT_DIR/resources.json"
VERSION="1.0.0"

mkdir -p "$OUT_DIR"

if [ ! -f "$LAB_STATE_FILE" ]; then
    echo "Error: no existe $LAB_STATE_FILE. Ejecuta antes: aws-scripts/ec2.sh create"
    exit 1
fi

VPC_ID=$(state_require VpcId)
GROUP_ID=$(state_require GroupId)
INSTANCE_ID=$(state_require InstanceId)
ALLOCATION_ID=$(state_require AllocationId)
ASSOCIATION_ID=$(state_get AssociationId)
PUBLIC_IP=$(state_require PublicIp)
SUBNET_IDS=$(state_require SubnetIds)

REGION=$(aws configure get region 2>/dev/null || true)
if [ -z "$REGION" ]; then
    REGION="${AWS_DEFAULT_REGION:-us-east-1}"
fi
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Consultando recursos V${VERSION} en $REGION..."

VPC_JSON=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --output json)
SG_JSON=$(aws ec2 describe-security-groups --group-ids "$GROUP_ID" --output json)
INSTANCE_JSON=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --output json)
EIP_JSON=$(aws ec2 describe-addresses --allocation-ids "$ALLOCATION_ID" --output json)

# shellcheck disable=SC2086
SUBNETS_JSON=$(aws ec2 describe-subnets --subnet-ids $SUBNET_IDS --output json)

SG_NAME=$(echo "$SG_JSON" | jq -r '.SecurityGroups[0].GroupName')
INSTANCE_TYPE=$(echo "$INSTANCE_JSON" | jq -r '.Reservations[0].Instances[0].InstanceType')
INSTANCE_STATE=$(echo "$INSTANCE_JSON" | jq -r '.Reservations[0].Instances[0].State.Name')
AMI_ID=$(echo "$INSTANCE_JSON" | jq -r '.Reservations[0].Instances[0].ImageId')
PRIVATE_IP=$(echo "$INSTANCE_JSON" | jq -r '.Reservations[0].Instances[0].PrivateIpAddress')
KEY_NAME=$(echo "$INSTANCE_JSON" | jq -r '.Reservations[0].Instances[0].KeyName // empty')
AZ=$(echo "$INSTANCE_JSON" | jq -r '.Reservations[0].Instances[0].Placement.AvailabilityZone')
INSTANCE_SUBNET=$(echo "$INSTANCE_JSON" | jq -r '.Reservations[0].Instances[0].SubnetId')
EIP_PUBLIC=$(echo "$EIP_JSON" | jq -r '.Addresses[0].PublicIp')
EIP_ASSOC=$(echo "$EIP_JSON" | jq -r '.Addresses[0].AssociationId // empty')

jq -n \
    --arg version "$VERSION" \
    --arg region "$REGION" \
    --arg account "$ACCOUNT" \
    --arg generatedAt "$GENERATED_AT" \
    --arg labStateFile "$LAB_STATE_FILE" \
    --arg vpcId "$VPC_ID" \
    --argjson vpc "$VPC_JSON" \
    --arg groupId "$GROUP_ID" \
    --arg groupName "$SG_NAME" \
    --argjson securityGroup "$SG_JSON" \
    --arg instanceId "$INSTANCE_ID" \
    --arg instanceType "$INSTANCE_TYPE" \
    --arg instanceState "$INSTANCE_STATE" \
    --arg amiId "$AMI_ID" \
    --arg privateIp "$PRIVATE_IP" \
    --arg keyName "$KEY_NAME" \
    --arg availabilityZone "$AZ" \
    --arg instanceSubnetId "$INSTANCE_SUBNET" \
    --argjson instance "$INSTANCE_JSON" \
    --arg allocationId "$ALLOCATION_ID" \
    --arg associationId "${ASSOCIATION_ID:-$EIP_ASSOC}" \
    --arg publicIp "${PUBLIC_IP:-$EIP_PUBLIC}" \
    --argjson elasticIp "$EIP_JSON" \
    --argjson subnets "$SUBNETS_JSON" \
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
        + [
          {
            type: "AWS::EC2::SecurityGroup",
            service: "Amazon EC2",
            id: $groupId,
            name: $groupName,
            vpcId: $vpcId,
            ingressPorts: (
              $securityGroup.SecurityGroups[0].IpPermissions
              | map({protocol: .IpProtocol, fromPort: .FromPort, toPort: .ToPort})
            )
          },
          {
            type: "AWS::EC2::Instance",
            service: "Amazon EC2",
            id: $instanceId,
            instanceType: $instanceType,
            state: $instanceState,
            imageId: $amiId,
            privateIp: $privateIp,
            keyName: $keyName,
            availabilityZone: $availabilityZone,
            subnetId: $instanceSubnetId,
            securityGroupIds: [$groupId]
          },
          {
            type: "AWS::EC2::EIP",
            service: "Amazon EC2",
            id: $allocationId,
            associationId: $associationId,
            publicIp: $publicIp,
            instanceId: $instanceId
          }
        ]
      )
    }' > "$OUT_FILE"

echo "Escrito $OUT_FILE"
jq '{version, region, account, resourceCount: (.resources|length), types: [.resources[].type]}' "$OUT_FILE"
