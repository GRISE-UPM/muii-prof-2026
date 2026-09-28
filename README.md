# Event Hub

Aplicación para gestionar eventos, compuesta por:

- `eventhub-back-springboot`: API REST Spring Boot con JPA, H2, seguridad OAuth2/JWT y OpenAPI.
- `eventhub-front-react`: aplicación React/Vite para la interfaz web, con login Cognito y visualización de JWT.
- `aws-scripts`: scripts para desplegar una instancia EC2, configurar Nginx, crear Cognito y publicar el backend y el frontend.

## Requisitos

### Instala y configura:

- Java 21 o superior
- Maven 3.9 o superior
- Node.js y npm
- Python 3
- AWS CLI

### Configura las credenciales de AWS:

- Descarga las credenciales desde AWS Academy y almacénalas en ~/aws/credentials
- Descarga la SSH key y almacénala en ssh-key/

## Configuración inicial

- Asigna permiso de ejecución a los ficheros .sh en aws-scripts/

## Despliegue con Make

- Ejecuta

```bash
make deploy
```

desde la raíz para crear EC2, crear el secreto de la base de datos, configurar Nginx, crear Cognito y publicar backend y frontend. Si una fase falla, el despliegue se detiene. Cada `make deploy` crea un secreto, un User Pool, un dominio y un App Client nuevos, y regenera `.env.local` y `cognito.properties`. El nombre del secreto (`prod/h2/admin`) y el prefijo del dominio son fijos para cada cuenta de AWS, así que si ya existen (porque no se ejecutó `make delete`), `secrets.sh` o `cognito.sh` fallan al crearlos. Para eliminar Cognito (dominio y User Pool, con su App Client), el secreto, la instancia EC2 con el backend y el frontend, y los ficheros generados (`lab-state.json`, `.env.local`, `.env.production.local` y `cognito.properties`):

```bash
make delete
```

## Los scripts generan o actualizan estos ficheros:

- `aws-scripts/lab-state.json`: IDs de infraestructura del laboratorio (GroupId, VpcId, SubnetIds, InstanceId, AllocationId, PublicIp, Region, UserPoolId, ClientId, Domain, CallbackUrl, …). Lo escriben los scripts de create; no versionar.
- `eventhub-front-react/.env.local`: variables de Cognito utilizadas por Vite (dev y build).
- `eventhub-front-react/.env.production.local`: URL de la API utilizada por Vite en el build de producción.
- `eventhub-back-springboot/src/main/resources/cognito.properties`: emisor JWT utilizado por Spring Boot.

Las carpetas necesarias deben existir previamente. `aws-scripts/cognito.sh` falla si no encuentra `eventhub-front-react/` o `eventhub-back-springboot/src/main/resources/`.

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

El perfil `dev` activa también la consola H2 en `http://localhost:8080/h2-console`. La JDBC URL es `jdbc:h2:mem:<dbname>`; `dbname`, el usuario y la contraseña son los del secreto `prod/h2/admin`.

## Ejecutar el frontend localmente

```bash
cd eventhub-front-react
npm install
npm run dev
```

La aplicación estará disponible normalmente en `http://localhost:3000`. En desarrollo las peticiones van a `http://localhost:8080` (`VITE_API_BASE_URL` en `.env.development`). El `build` de producción usa `.env.production.local` (generado por `front.sh`). Las variables de Cognito salen de `.env.local` (generado por `cognito.sh`).
