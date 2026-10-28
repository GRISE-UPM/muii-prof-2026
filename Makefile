SHELL := /bin/bash

AWS_SCRIPTS := aws-scripts

.PHONY: deploy delete

# previo.sh va primero: se detiene, sin crear nada, si quedan restos de eventhub de versiones
# anteriores (salvo las bases de datos, que se reutilizan).
# El orden importa: cada script lee de lab-state.json lo que dejaron los anteriores.
# cognito.sh necesita la IP elástica de Nginx (callback), y back.sh empaqueta
# cognito.properties y aurora.properties en la imagen.
deploy:
	bash $(AWS_SCRIPTS)/previo.sh
	bash $(AWS_SCRIPTS)/red.sh create
	bash $(AWS_SCRIPTS)/aurora.sh create
	bash $(AWS_SCRIPTS)/alb.sh create
	bash $(AWS_SCRIPTS)/nginx.sh create
	bash $(AWS_SCRIPTS)/cognito.sh create
	bash $(AWS_SCRIPTS)/ecs.sh create
	bash $(AWS_SCRIPTS)/back.sh
	bash $(AWS_SCRIPTS)/front.sh
	@echo "Despliegue completo finalizado correctamente."

# Los servicios y las tareas se van con ecs.sh delete; el build del frontend y Nginx, con
# nginx.sh delete. .env.production.local es local.
# aurora.sh delete pregunta si se conserva o se borra la base de datos Aurora.
delete:
	bash $(AWS_SCRIPTS)/ecs.sh delete
	bash $(AWS_SCRIPTS)/nginx.sh delete
	bash $(AWS_SCRIPTS)/alb.sh delete
	bash $(AWS_SCRIPTS)/cognito.sh delete
	bash $(AWS_SCRIPTS)/aurora.sh delete
	bash $(AWS_SCRIPTS)/red.sh delete
	rm -f $(AWS_SCRIPTS)/lab-state.json \
		eventhub-front-react/.env.production.local
	@echo "Eliminación completa finalizada correctamente."
