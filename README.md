# Event Hub. Ejercicio de infraestructura como código con AWS CDK

Este repositorio contiene el código de partida de un ejercicio guiado sobre **AWS CDK**. Está basado en la versión 1.0.0 de *eventhub*, una aplicación para gestionar eventos formada por un back Spring Boot (`eventhub-back-springboot`), un front React/Vite (`eventhub-front-react`) y los scripts de despliegue en AWS (`aws-scripts`).

En la versión 1.0.0 la infraestructura (grupo de seguridad, instancia EC2 e IP elástica) se crea con scripts del CLI de AWS, y Nginx se instala entrando por SSH. En el ejercicio se describe esa infraestructura con un programa en Python que CDK convierte en una plantilla de CloudFormation. Nginx pasa a instalarse con el *user data* de la instancia, y el estado lo guarda CloudFormation. El resultado es la versión `V1.0.0-CDK-learner-lab`, que se puede desplegar en AWS Academy Learner Lab.

La carpeta `cdk/` contiene la aplicación CDK y el script de *user data*. El fichero `cdk/eventhub_cdk/ec2_stack.py` está vacío, y se completa a lo largo del tutorial.

El tutorial explica el ejercicio paso a paso, y es lo que hay que seguir para realizarlo.
