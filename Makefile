SHELL := /bin/bash

AWS_SCRIPTS := aws-scripts

.PHONY: deploy delete

deploy:
	bash $(AWS_SCRIPTS)/ec2.sh create
	bash $(AWS_SCRIPTS)/aurora.sh create
	bash $(AWS_SCRIPTS)/nginx.sh
	bash $(AWS_SCRIPTS)/cognito.sh create
	bash $(AWS_SCRIPTS)/back.sh
	bash $(AWS_SCRIPTS)/front.sh
	@echo "Despliegue completo finalizado correctamente."

# Nginx, el JAR y el frontend están en el disco de la instancia: ec2.sh delete se los lleva.
# .env.production.local es local; no vive en EC2.
delete:
	bash $(AWS_SCRIPTS)/cognito.sh delete
	bash $(AWS_SCRIPTS)/aurora.sh delete
	bash $(AWS_SCRIPTS)/ec2.sh delete
	rm -f $(AWS_SCRIPTS)/lab-state.json \
		eventhub-front-react/.env.production.local
	@echo "Eliminación completa finalizada correctamente."
