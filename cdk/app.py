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

# Sintetizador por defecto: la cuenta debe estar preparada una vez con `cdk bootstrap`
EventHubStack(app, "EventHubStack", env=env)

app.synth()
