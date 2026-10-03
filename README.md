# Event Hub. Ejercicio de seguridad con Amazon Cognito

Este repositorio contiene el código de partida de un ejercicio guiado sobre autenticación y autorización con **Amazon Cognito**. Está basado en la versión 1.0.0 de *eventhub*, una aplicación para gestionar eventos formada por un back Spring Boot (`eventhub-back-springboot`), un front React/Vite (`eventhub-front-react`) y los scripts de despliegue en AWS (`aws-scripts`).

En la versión 1.0.0 la API no distingue usuarios. Cualquiera puede crear eventos, consultarlos y comprar entradas, y para comprar basta con escribir un email cualquiera en la petición. En el ejercicio se protege la aplicación con Cognito. La autenticación (saber quién es el usuario) se resuelve con OpenID Connect y recae en el front, que delega el login en Cognito y recibe a cambio los tokens. La autorización (decidir qué puede hacer) se resuelve con OAuth 2.0 y recae en el back, que actúa como servidor de recursos, comprueba el token de cada petición y decide según el rol del usuario. Los roles salen de los grupos de Cognito.

El tutorial explica el ejercicio paso a paso, y es lo que hay que seguir para realizarlo:

https://www.overleaf.com/read/dftvxsvhdywq#4e72c7
