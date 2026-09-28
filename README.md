# Event Hub

Aplicación para gestionar eventos, compuesta por:

- `eventhub-back-springboot`: API REST Spring Boot con JPA, Aurora PostgreSQL (usando las credenciales que Aurora almacena en AWS Secrets Manager), seguridad OAuth2/JWT y OpenAPI.
- `eventhub-front-react`: aplicación React/Vite para la interfaz web, con login Cognito y visualización de JWT.
- `aws-scripts`: scripts para desplegar una instancia EC2, crear el clúster Aurora, configurar Nginx, crear Cognito y publicar el backend y el frontend.

## Requisitos

### Instala y configura:

- Java 21 o superior
- Maven 3.9 o superior
- Node.js y npm
- Python 3
- AWS CLI

### Configura las credenciales de AWS:

- Descarga las credenciales desde AWS Academy y almacénalas en ~/.aws/credentials
- Descarga la SSH key y almacénala en ssh-key/

## Configuración inicial

- Asigna permiso de ejecución a los ficheros .sh en aws-scripts/

## Despliegue con Make

- Ejecuta

```bash
make deploy
```

desde la raíz para crear EC2, crear el clúster Aurora, configurar Nginx, crear Cognito y publicar backend y frontend. Si una fase falla, el despliegue se detiene. La creación de Aurora tarda varios minutos. Cognito en AWS no se borra: si el User Pool o el dominio ya existen, se reutilizan. `make delete` sí elimina los ficheros locales generados (`.env.local`, `cognito.properties`, etc.); el siguiente `create` los regenera. Para eliminar frontend, backend, configuración local de Cognito, Aurora, EC2 y los ficheros de la instancia:

```bash
make delete
```

## Los scripts generan o actualizan estos ficheros:

- `aws-scripts/lab-state.json`: IDs de infraestructura del laboratorio (GroupId, VpcId, SubnetIds, InstanceId, AllocationId, PublicIp, Region, UserPoolId, ClientId, Domain, CallbackUrl, …). Lo escriben los scripts de create; no versionar.
- `eventhub-front-react/.env.local`: variables de Cognito utilizadas por Vite (dev y build).
- `eventhub-front-react/.env.production.local`: URL de la API utilizada por Vite en el build de producción.
- `eventhub-back-springboot/src/main/resources/cognito.properties`: emisor JWT utilizado por Spring Boot.
- `eventhub-back-springboot/src/main/resources/aurora.properties`: nombre del secreto de Aurora que importa Spring Boot.

Las carpetas necesarias deben existir previamente. `aws-scripts/cognito.sh` falla si no encuentra `eventhub-front-react/` o `eventhub-back-springboot/src/main/resources/`.

## Credenciales de la base de datos

El backend usa Aurora PostgreSQL, y su usuario y su contraseña no están en el repositorio: los crea el propio clúster al desplegarse y quedan en AWS Secrets Manager.

- `aws rds create-db-cluster --manage-master-user-password` hace que Aurora genere la contraseña y el secreto: no se escribe a mano ni viaja por la CLI.
- El nombre del secreto lo asigna RDS (`rds!cluster-...`), por lo que `aurora.sh` lo consulta y lo escribe en `aurora.properties`.
- El JSON del secreto contiene `username`, `password`, `host`, `port` y `dbname`, con los que Spring Boot construye `jdbc:postgresql://${host}:${port}/${dbname}`.
- Aurora es accesible solo desde la VPC: `aurora.sh` abre el puerto 5432 en el grupo de seguridad de EC2 y únicamente para el tráfico de ese mismo grupo.
- Los tests no necesitan AWS: `src/test/resources/application.properties` arranca H2 en memoria con credenciales fijas.

`make delete` elimina la instancia, el clúster y su subnet group; RDS se encarga de retirar el secreto.

## La aplicación estará disponible en

### Front

https://<PublicIp de lab-state.json>/

### Documentación OpenAPI (solo desarrollo)

Swagger no se publica en EC2. En local, arranca el backend con el perfil `dev`:

```bash
cd eventhub-back-springboot
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

El UI queda en `http://localhost:8080/swagger-ui.html`.

En `dev` la base de datos es H2 en memoria, así que no hace falta Aurora ni `aurora.properties`. La consola H2 queda en `http://localhost:8080/h2-console` (JDBC URL `jdbc:h2:mem:eventhubdb`, usuario `sa`, sin contraseña).

## Ejecutar el frontend localmente

```bash
cd eventhub-front-react
npm install
npm run dev
```

La aplicación estará disponible normalmente en `http://localhost:3000`. En desarrollo las peticiones van a `http://localhost:8080` (`VITE_API_BASE_URL` en `.env.development`). El `build` de producción usa `.env.production.local` (generado por `front.sh`). Las variables de Cognito salen de `.env.local` (generado por `cognito.sh`).
