# Event Hub. Ejercicio de AWS Secrets Manager

Este repositorio contiene el código de partida de un ejercicio guiado sobre la gestión de secretos con **AWS Secrets Manager**. Está basado en la versión 2.0.0 de *eventhub*, una aplicación para gestionar eventos formada por un back Spring Boot (`eventhub-back-springboot`), un front React/Vite (`eventhub-front-react`) y los scripts de despliegue en AWS (`aws-scripts`).

En la versión 2.0.0, las credenciales de la base de datos están escritas en texto claro en `application.properties` (usuario `sa` y contraseña vacía). Viajan en el repositorio y dentro del JAR. En el ejercicio se sacan del código y se guardan en Secrets Manager, un servicio que almacena secretos cifrados y solo los entrega a quien tiene permiso para leerlos. Al terminar, el back no contiene ninguna credencial. Al arrancar en EC2, pide el secreto a Secrets Manager (con las credenciales temporales del rol asociado a la instancia) y configura con él la conexión a la base de datos. El front no cambia.

El tutorial explica el ejercicio paso a paso, y es lo que hay que seguir para realizarlo:

https://www.overleaf.com/read/qqrpqhryqnkd#fc7dc6
