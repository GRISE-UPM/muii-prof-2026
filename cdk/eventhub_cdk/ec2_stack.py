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

        # AWS Academy ya tiene una VPC por defecto; la pila no la crea
        vpc = ec2.Vpc.from_lookup(self, "Vpc", is_default=True)

        # No se fija security_group_name (ec2.sh sí lo hacía, con eventhub-sg): CloudFormation
        # genera un nombre único, y así el grupo se puede reemplazar y la pila desplegar dos veces.
        sg = ec2.SecurityGroup(
            self, "EventHubSg", vpc=vpc,
            description="Permite trafico HTTP y SSH al servidor EC2",
        )
        for puerto in (80, 22):
            sg.add_ingress_rule(ec2.Peer.any_ipv4(), ec2.Port.tcp(puerto))

        # Nginx se instala con el user data, que cloud-init ejecuta en el primer arranque
        user_data = ec2.UserData.custom(Path(__file__).with_name("nginx_user_data.sh").read_text())

        instance = ec2.Instance(
            self, "EventHubInstance", vpc=vpc,
            instance_name="eventhub",
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            instance_type=ec2.InstanceType("t2.micro"),
            machine_image=ec2.MachineImage.from_ssm_parameter(UBUNTU_SSM),
            security_group=sg,
            # Par de claves de AWS Academy, para el SSH de los despliegues
            key_pair=ec2.KeyPair.from_key_pair_name(self, "VocKey", "vockey"),
            # El L2 Instance crea por defecto un rol IAM y su perfil, que el laboratorio no permite.
            # Se reutiliza el perfil que ya existe. Hay que importarlo con su rol: si solo se da el
            # nombre del perfil, el L2 sigue creando un rol propio.
            instance_profile=iam.InstanceProfile.from_instance_profile_attributes(
                self, "LabInstanceProfile",
                instance_profile_arn=f"arn:aws:iam::{self.account}:instance-profile/LabInstanceProfile",
                role=iam.Role.from_role_arn(self, "LabRole", f"arn:aws:iam::{self.account}:role/LabRole"),
            ),
            user_data=user_data,
        )

        # No hay L2 para la IP elástica: se usa directamente el L1
        eip = ec2.CfnEIP(
            self, "EventHubEip", domain="vpc", instance_id=instance.instance_id,
            tags=[cdk.CfnTag(key="Name", value="eventhub-eip")],
        )

        cdk.CfnOutput(self, "PublicIp", value=eip.attr_public_ip)
        cdk.CfnOutput(self, "Url", value=f"http://{eip.attr_public_ip}/")
