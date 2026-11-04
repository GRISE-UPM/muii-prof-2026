#!/usr/bin/env python3
"""Aplicación CDK de eventhub (versión 1.0.0): la instancia EC2 de la 1.0.0 como código."""

import os

import aws_cdk as cdk

from eventhub_cdk.ec2_stack import EventHubStack

app = cdk.App()

# La VPC por defecto se busca en la cuenta al sintetizar (lookup), así que hace falta una cuenta y
# una región concretas. El CLI de CDK las toma de las credenciales de AWS.
env = cdk.Environment(
    account=os.environ.get("CDK_DEFAULT_ACCOUNT", "123456789012"),
    region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
)

# Contexto: pares clave-valor que el programa CDK lee mientras se ejecuta. Salen de cdk.json,
# de cdk.context.json (donde CDK guarda los lookups, como la VPC) y de la línea de comandos,
# con `-c clave=valor`. try_get_context devuelve el valor, o None si nadie lo ha pasado.
#
# Aquí el contexto `entorno` decide el nombre de la pila. Sin `-c`, como en un `cdk deploy`
# local o en el despliegue al hacer merge, la pila es la de producción, EventHubStack. Con
# `-c entorno=pr-7` se despliega una copia aparte, EventHubStack-pr-7, que es la vista previa
# de un pull request.
#
# `entorno` es un nombre elegido por nosotros, no algo que definan CDK o GitHub. Lo pasa el
# workflow infra-pr.yml como `-c entorno=$ENTORNO`, siendo $ENTORNO = pr-${{ github.event.number }}
# El nombre de la pila se repite en la variable STACK_NAME de ese workflow, que es
# la que leen back.sh, front.sh y esperar-cloud-init.sh, así que ambos deben coincidir.

entorno = app.node.try_get_context("entorno")
nombre = f"EventHubStack-{entorno}" if entorno else "EventHubStack"

# Sin bootstrap: el stack no tiene assets, y el bootstrap crea roles IAM, que el Learner Lab
# no permite.
EventHubStack(app, nombre, env=env, synthesizer=cdk.LegacyStackSynthesizer())

app.synth()
