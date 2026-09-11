SHELL := /bin/bash

AWS_SCRIPTS := aws-scripts

.PHONY: deploy delete

deploy:
	bash $(AWS_SCRIPTS)/ec2.sh create
	bash $(AWS_SCRIPTS)/nginx.sh deploy
	bash $(AWS_SCRIPTS)/cognito.sh create
	bash $(AWS_SCRIPTS)/back.sh deploy
	bash $(AWS_SCRIPTS)/front.sh deploy
	@echo "Despliegue completo finalizado correctamente."

delete:
	bash $(AWS_SCRIPTS)/front.sh delete
	bash $(AWS_SCRIPTS)/back.sh delete
	bash $(AWS_SCRIPTS)/cognito.sh delete
	bash $(AWS_SCRIPTS)/ec2.sh delete
	rm -f $(AWS_SCRIPTS)/lab-state.json \
		eventhub-front-react/.env.production.local
	@echo "Eliminación completa finalizada correctamente."
