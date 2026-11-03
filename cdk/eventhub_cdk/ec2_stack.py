"""Pila de eventhub: la instancia EC2 con Nginx, su IP elástica y su grupo de seguridad."""

from pathlib import Path

import aws_cdk as cdk
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_iam as iam
from constructs import Construct

# Imagen de Ubuntu 22.04 que Canonical mantiene actualizada en un parámetro público de SSM
UBUNTU_SSM = "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id"


class EventHubStack(cdk.Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Paso 2: la VPC y el grupo de seguridad

        # Paso 3: la instancia

        # Paso 4: la IP elástica y las salidas
