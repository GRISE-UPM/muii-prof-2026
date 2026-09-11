#!/usr/bin/env python3
"""Arquitectura Event Hub en la rama aurora (password gestionada por RDS)."""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2ElasticIpAddress, EC2Instance
from diagrams.aws.database import Aurora
from diagrams.aws.general import Users, GenericFirewall
from diagrams.aws.security import Cognito, SecretsManager
from diagrams.onprem.network import Nginx
from diagrams.programming.framework import React, Spring

graph_attr = {
    "fontsize": "13",
    "bgcolor": "white",
    "pad": "0.4",
    "splines": "spline",
}
cluster_vpc = {"bgcolor": "#D6EAF8", "pencolor": "#2E86C1"}
cluster_ec2 = {"bgcolor": "#D5F5E3", "pencolor": "#1E8449"}
cluster_db = {"bgcolor": "#FDEBD0", "pencolor": "#B9770E"}

edge_label = {"fontsize": "10", "fontname": "Helvetica"}

with Diagram(
    "Event Hub · rama aurora",
    filename="/Users/odieste/Library/CloudStorage/Dropbox/trabajo/muii-prof-2026/docs/arquitectura-eventhub-aurora",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    user = Users("Usuario\nNavegador")
    cognito = Cognito("Amazon Cognito\nUser Pool + Hosted UI")
    secrets = SecretsManager("AWS Secrets Manager\nrds!cluster-...")

    with Cluster("Amazon VPC (us-east-1)", graph_attr=cluster_vpc):
        eip = EC2ElasticIpAddress("Elastic IP")
        sg = GenericFirewall("eventhub-sg\n22, 80, 443 + 5432 interno")

        with Cluster("Amazon EC2 · Ubuntu t2.micro", graph_attr=cluster_ec2):
            inst = EC2Instance("Instancia")
            nginx = Nginx("Nginx TLS :443")
            react = React("SPA React\n/var/www/html")
            spring = Spring("Spring Boot\n127.0.0.1:8080")

            inst >> Edge(color="#1E8449") >> nginx
            nginx >> Edge(label="/", **edge_label) >> react
            nginx >> Edge(label="/api/", **edge_label) >> spring

        with Cluster("Amazon Aurora PostgreSQL", graph_attr=cluster_db):
            aurora = Aurora("eventhub-cluster-aurora\nno-publicly-accessible")

        eip >> Edge(color="#2E86C1") >> sg >> Edge(color="#2E86C1") >> inst

    user >> Edge(label="login OIDC", **edge_label) >> cognito
    user >> Edge(label="HTTPS", **edge_label) >> eip

    # Password: Aurora la crea en Secrets Manager (no viaja por la CLI).
    aurora >> Edge(
        label="--manage-master-user-password\ncrea username + password + host",
        color="#B9770E",
        style="bold",
        **edge_label,
    ) >> secrets

    # Spring lee el secreto (GetSecretValue), no la CLI.
    spring >> Edge(
        label="GetSecretValue\n(AWSCURRENT)",
        color="#B7950B",
        **edge_label,
    ) >> secrets

    # Conexión JDBC con esas credenciales, puerto 5432 en el mismo SG.
    spring >> Edge(
        label="JDBC :5432\n(credenciales del secreto)",
        color="#1E8449",
        **edge_label,
    ) >> aurora
