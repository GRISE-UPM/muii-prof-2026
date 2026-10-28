# Event Hub. Ejercicio de Amazon Aurora

Este repositorio contiene el código de partida de un ejercicio guiado sobre bases de datos gestionadas con **Amazon Aurora**. Está basado en la versión 2.0.0 de *eventhub*, una aplicación para gestionar eventos formada por un back Spring Boot (`eventhub-back-springboot`), un front React/Vite (`eventhub-front-react`) y los scripts de despliegue en AWS (`aws-scripts`).

En la versión 2.0.0 el back guarda los datos en una base de datos H2 en memoria (usuario `sa` y contraseña vacía), que desaparece cada vez que se reinicia la aplicación y que no se puede compartir entre varias instancias. En el ejercicio se sustituye por un clúster Aurora PostgreSQL, un servicio de base de datos gestionada que replica los datos en varias zonas de disponibilidad y conmuta a otra instancia si falla la principal. Las credenciales del clúster las genera y guarda Aurora en Secrets Manager, y el back las lee de allí al arrancar. El front no cambia.

El tutorial explica el ejercicio paso a paso, y es lo que hay que seguir para realizarlo:

https://www.overleaf.com/read/mhnjvhhfmddb#e29576
