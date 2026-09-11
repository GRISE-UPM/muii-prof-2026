#!/usr/bin/env python3
"""Genera docs/architecture.png a partir de docs/resources.json (EventHub V2.0.0).

Usa la librería `diagrams`, que empaqueta los iconos oficiales de AWS Architecture Icons.
Requisitos: pip install diagrams && graphviz (dot) instalado en el sistema.

Uso:
  docs/list-resources.sh
  python3 docs/draw-architecture.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2, EC2ElasticIpAddress
from diagrams.aws.general import GenericFirewall, InternetAlt1, Users
from diagrams.aws.network import InternetGateway, PublicSubnet
from diagrams.aws.security import Cognito

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DOCS_DIR = PROJECT_ROOT / "docs"
RESOURCES_FILE = DOCS_DIR / "resources.json"
OUTPUT_STEM = DOCS_DIR / "architecture"


def _first(resources: list[dict], rtype: str) -> dict | None:
    for item in resources:
        if item.get("type") == rtype:
            return item
    return None


def _all(resources: list[dict], rtype: str) -> list[dict]:
    return [item for item in resources if item.get("type") == rtype]


def main() -> int:
    if not RESOURCES_FILE.is_file():
        print(
            f"Error: no existe {RESOURCES_FILE}. Ejecuta antes docs/list-resources.sh",
            file=sys.stderr,
        )
        return 1

    data = json.loads(RESOURCES_FILE.read_text(encoding="utf-8"))
    resources = data.get("resources", [])
    version = data.get("version", "2.0.0")
    region = data.get("region", "")
    account = data.get("account", "")

    vpc = _first(resources, "AWS::EC2::VPC")
    subnets = _all(resources, "AWS::EC2::Subnet")
    sg = _first(resources, "AWS::EC2::SecurityGroup")
    instance = _first(resources, "AWS::EC2::Instance")
    eip = _first(resources, "AWS::EC2::EIP")
    user_pool = _first(resources, "AWS::Cognito::UserPool")
    app_client = _first(resources, "AWS::Cognito::UserPoolClient")
    pool_domain = _first(resources, "AWS::Cognito::UserPoolDomain")

    if not all([vpc, sg, instance, eip, user_pool, app_client, pool_domain]):
        print(
            "Error: resources.json incompleto "
            "(faltan VPC, SecurityGroup, Instance, EIP o Cognito).",
            file=sys.stderr,
        )
        return 1

    vpc_label = f"VPC\n{vpc['id']}"
    if vpc.get("isDefault"):
        vpc_label += "\n(default)"
    if vpc.get("cidrBlock"):
        vpc_label += f"\n{vpc['cidrBlock']}"

    sg_ports = sg.get("ingressPorts") or []
    port_txt = ", ".join(
        str(p.get("fromPort"))
        for p in sg_ports
        if p.get("fromPort") is not None
    )
    sg_label = f"Security Group\n{sg.get('name', '')}\n{sg['id']}"
    if port_txt:
        sg_label += f"\nin: {port_txt}"

    inst_label = (
        f"EC2 Instance\n{instance['id']}\n"
        f"{instance.get('instanceType', '')} · {instance.get('state', '')}"
    )
    if instance.get("privateIp"):
        inst_label += f"\n{instance['privateIp']}"

    eip_label = f"Elastic IP\n{eip.get('publicIp', '')}\n{eip['id']}"

    pool_label = (
        f"User Pool\n{user_pool.get('name', '')}\n{user_pool['id']}"
    )
    client_label = (
        f"App Client\n{app_client.get('name', '')}\n{app_client['id']}"
    )
    if app_client.get("callbackUrl"):
        client_label += f"\n{app_client['callbackUrl']}"

    domain_label = (
        f"Hosted UI Domain\n{pool_domain['id']}\n"
        f"{pool_domain.get('cognitoDomainUrl', '')}"
    )

    DOCS_DIR.mkdir(parents=True, exist_ok=True)
    graph_attr = {
        "fontsize": "12",
        "bgcolor": "white",
        "pad": "0.4",
        "splines": "ortho",
    }
    title = f"EventHub V{version} · {region} · account {account}"

    with Diagram(
        title,
        filename=str(OUTPUT_STEM),
        outformat="png",
        show=False,
        direction="LR",
        graph_attr=graph_attr,
    ):
        users = Users("Clientes\nHTTP/HTTPS/SSH + OAuth")
        internet = InternetAlt1("Internet")

        with Cluster(f"AWS Cloud · {region}"):
            igw = InternetGateway("Internet Gateway\n(VPC default)")
            eip_node = EC2ElasticIpAddress(eip_label)

            with Cluster("Amazon Cognito"):
                cognito_pool = Cognito(pool_label)
                cognito_client = Cognito(client_label)
                cognito_domain = Cognito(domain_label)
                cognito_pool >> cognito_client
                cognito_pool >> cognito_domain

            with Cluster(vpc_label):
                subnet_nodes = []
                for sn in subnets:
                    sn_label = (
                        f"Subnet\n{sn['id']}\n"
                        f"{sn.get('availabilityZone', '')}\n"
                        f"{sn.get('cidrBlock', '')}"
                    )
                    subnet_nodes.append(PublicSubnet(sn_label))

                sg_node = GenericFirewall(sg_label)
                ec2_node = EC2(inst_label)

                if subnet_nodes:
                    inst_subnet = instance.get("subnetId")
                    linked = False
                    for sn, node in zip(subnets, subnet_nodes):
                        if sn["id"] == inst_subnet:
                            node >> sg_node >> ec2_node
                            linked = True
                        else:
                            _ = node
                    if not linked:
                        subnet_nodes[0] >> sg_node >> ec2_node
                else:
                    sg_node >> ec2_node

            igw >> Edge(label="EIP") >> eip_node
            eip_node >> Edge(label="asocia") >> ec2_node
            cognito_domain >> Edge(label="callback\nOAuth") >> eip_node
            cognito_pool >> Edge(label="JWT issuer") >> ec2_node

        users >> internet >> igw
        users >> Edge(label="login") >> cognito_domain

    out_png = Path(str(OUTPUT_STEM) + ".png")
    print(f"Escrito {out_png}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
