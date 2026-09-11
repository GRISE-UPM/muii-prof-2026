#!/usr/bin/env python3
"""Arquitectura Event Hub en la rama secrets (H2 con credenciales en Secrets Manager)."""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2ElasticIpAddress, EC2Instance
from diagrams.aws.general import Users, GenericFirewall
from diagrams.aws.security import Cognito, SecretsManager
from diagrams.generic.database import SQL
from diagrams.onprem.network import Nginx
from diagrams.programming.framework import React, Spring

graph_attr = {
    "fontsize": "13",
    "bgcolor": "white",
    "pad": "0.4",
    "splines": "ortho",
}
cluster_vpc = {"bgcolor": "#D6EAF8", "pencolor": "#2E86C1"}
cluster_ec2 = {"bgcolor": "#D5F5E3", "pencolor": "#1E8449"}

edge_label = {"fontsize": "10", "fontname": "Helvetica"}

with Diagram(
    "Event Hub · rama secrets",
    filename="/Users/odieste/Library/CloudStorage/Dropbox/trabajo/muii-prof-2026/docs/arquitectura-eventhub-secrets-v300",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    user = Users("Usuario\nNavegador")
    cognito = Cognito("Amazon Cognito\nUser Pool + Hosted UI")
    secrets = SecretsManager("AWS Secrets Manager\nprod/h2/admin")

    with Cluster("Amazon VPC (us-east-1)", graph_attr=cluster_vpc):
        eip = EC2ElasticIpAddress("Elastic IP")
        sg = GenericFirewall("Security Group\nTCP 22, 80, 443")

        with Cluster("Amazon EC2 · Ubuntu t2.micro", graph_attr=cluster_ec2):
            inst = EC2Instance("Instancia")
            nginx = Nginx("Nginx TLS :443")
            react = React("SPA React\n/var/www/html")
            spring = Spring("Spring Boot\n127.0.0.1:8080")
            h2 = SQL("H2 en memoria\njdbc:h2:mem:eventhub")

            inst >> Edge(color="#1E8449") >> nginx
            nginx >> Edge(label="/", **edge_label) >> react
            nginx >> Edge(label="/api/", **edge_label) >> spring
            spring >> Edge(color="#1E8449", **edge_label) >> h2

        eip >> Edge(color="#2E86C1") >> sg >> Edge(color="#2E86C1") >> inst

    user >> Edge(label="login OIDC", **edge_label) >> cognito
    user >> Edge(label="HTTPS", **edge_label) >> eip
    spring >> Edge(
        label="GetSecretValue\nusername, password,\ndbname",
        color="#B7950B",
        **edge_label,
    ) >> secrets
