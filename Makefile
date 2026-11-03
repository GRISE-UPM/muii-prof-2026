SHELL := /bin/bash

AWS_SCRIPTS := aws-scripts
CDK_DIR := cdk

# Sin esto, jsii avisa en cada ejecución si tu versión de Node ya no tiene soporte
export JSII_SILENCE_WARNING_UNTESTED_NODE_VERSION := 1

.PHONY: venv synth diff deploy delete

# Entorno virtual de Python con las librerías de CDK. Se crea una vez.
venv: $(CDK_DIR)/.venv
$(CDK_DIR)/.venv: $(CDK_DIR)/requirements.txt
	python3 -m venv $(CDK_DIR)/.venv
	$(CDK_DIR)/.venv/bin/pip install -q -r $(CDK_DIR)/requirements.txt
	touch $(CDK_DIR)/.venv

# Genera la plantilla de CloudFormation en cdk/cdk.out y no despliega nada
synth: venv
	cd $(CDK_DIR) && cdk synth --quiet

# Qué cambiaría un despliegue respecto a lo que hay en AWS
diff: venv
	cd $(CDK_DIR) && cdk diff

# El orden importa:
#  1. cdk deploy crea el grupo de seguridad, la instancia y la IP elástica.
#  2. esperar-cloud-init.sh espera a que la instancia termine de instalar Nginx (user data), ya
#     que CloudFormation da la instancia por creada en cuanto arranca.
#  3. back.sh compila y arranca el backend en la instancia.
#  4. front.sh compila y sube el frontend.
# Los scripts leen la IP pública de las salidas de la pila: no hay fichero de estado.
deploy: venv
	cd $(CDK_DIR) && cdk deploy --require-approval never
	bash $(AWS_SCRIPTS)/esperar-cloud-init.sh
	bash $(AWS_SCRIPTS)/back.sh
	bash $(AWS_SCRIPTS)/front.sh
	@echo "Despliegue completo finalizado correctamente."

# Nginx, el JAR y el frontend están en el disco de la instancia: destruir la pila se los lleva.
# .env.production.local es local; no vive en EC2.
delete: venv
	cd $(CDK_DIR) && cdk destroy --force
	rm -f eventhub-front-react/.env.production.local
	@echo "Eliminación completa finalizada correctamente."
