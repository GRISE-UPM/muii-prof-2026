# Event Hub

Aplicación para gestionar eventos, compuesta por:

- `eventhub-back-springboot`: API REST Spring Boot con JPA, Aurora PostgreSQL (usando las credenciales que Aurora almacena en AWS Secrets Manager), seguridad OAuth2/JWT y OpenAPI. Se empaqueta como imagen Docker y se ejecuta en Amazon ECS con Fargate.
- `eventhub-front-react`: aplicación React/Vite para la interfaz web, con login Cognito y visualización de JWT. Se empaqueta como imagen Docker con Nginx y se ejecuta en Amazon ECS con Fargate.
- `aws-scripts`: scripts para crear la red, el clúster Aurora, el balanceador con su certificado, Cognito y el clúster de ECS, y para publicar el backend y el frontend.

## Arquitectura

```
Navegador ──HTTPS──> ALB (certificado autofirmado)
                      ├── /*      ──> tareas ECS Fargate del frontend (Nginx, 2 zonas)
                      └── /api/*  ──> tareas ECS Fargate del backend (2 zonas) ──> Aurora PostgreSQL
```

- Esta versión (5.2.0) es una alternativa a la 5.0.0 para los laboratorios que no permiten CloudFront (AWS Academy Learner Lab). En la 5.0.0, CloudFront pone el HTTPS y sirve el frontend desde S3.
- A diferencia de la 5.1.0, que crea siempre la base de datos, esta versión **reutiliza el clúster Aurora que ya existe** (el de la versión 4.0.0) y solo lo crea si no existe. `make delete` no borra una base de datos que ya existía.
- El HTTPS lo pone un certificado autofirmado que `alb.sh` importa en ACM. El navegador avisa de que no puede verificarlo, y hay que aceptarlo. El puerto 80 redirige al 443.
- El frontend y la API comparten origen (el balanceador reparte por ruta), así que no hace falta CORS.
- El balanceador acepta tráfico de Internet, y las tareas solo del balanceador. Aurora solo acepta conexiones de las tareas.
- El balanceador comprueba la salud de cada tarea en `/actuator/health/liveness` y deja de enviar peticiones a las que no responden.

## Requisitos

### Instala y configura:

- Java 21 o superior
- Maven 3.9 o superior
- Node.js y npm
- Docker (con el daemon arrancado: `back.sh` construye la imagen)
- Python 3
- AWS CLI, jq y openssl

### Configura las credenciales de AWS:

- Descarga las credenciales desde AWS Academy y almacénalas en ~/.aws/credentials

## Configuración inicial

- Asigna permiso de ejecución a los ficheros .sh en aws-scripts/

## Despliegue con Make

- Ejecuta

```bash
make deploy
```

desde la raíz. Antes de crear nada, `previo.sh` comprueba que no quedan restos de eventhub de versiones anteriores (una EC2 de la versión 4.0.0, su IP elástica, reglas abiertas a Internet en `eventhub-sg`, un User Pool de Cognito, un balanceador o un clúster de ECS). Si los encuentra, **se detiene sin crear ni modificar nada** y lista lo que hay que eliminar. Hay que borrar todo lo que se refiera a eventhub, excepto las bases de datos. Después, los scripts se ejecutan en este orden, y cada uno lee de `lab-state.json` lo que dejaron los anteriores:

| Script | Crea |
|---|---|
| `previo.sh` | Nada: solo comprueba que no quedan restos de eventhub, y se detiene si los hay |
| `red.sh` | Subnets de la VPC por defecto y el grupo de seguridad del balanceador (`eventhub-alb-sg`). Para las tareas reutiliza el grupo de seguridad del clúster Aurora si ya existe, y si no, crea `eventhub-sg` |
| `aurora.sh` | Si el clúster Aurora existe, lo reutiliza y escribe `aurora.properties`. Si no, crea el clúster con una instancia en cada zona |
| `alb.sh` | Application Load Balancer, un grupo de destino para el backend y otro para el frontend, el certificado autofirmado (importado en ACM), el listener HTTPS:443 con la regla `/api/*` y el listener HTTP:80 que redirige al 443 |
| `cognito.sh` | User Pool, cliente y dominio de Cognito, con el nombre DNS del balanceador como callback |
| `ecs.sh` | Repositorios ECR y grupos de logs de CloudWatch del backend y del frontend, y clúster de ECS |
| `back.sh` | Compila el backend, sube la imagen a ECR y crea (o actualiza) el servicio con dos tareas |
| `front.sh` | Compila el frontend, construye la imagen con Nginx, la sube a ECR y crea (o actualiza) el servicio con dos tareas |

Si una fase falla, el despliegue se detiene. La creación de Aurora tarda varios minutos. Cognito en AWS no se borra: si el User Pool o el dominio ya existen, se reutilizan.

Para publicar una nueva versión del código basta con volver a ejecutar `back.sh` o `front.sh`. ECS sustituye las tareas poco a poco, sin cortar el servicio.

Para eliminar todo, en orden inverso:

```bash
make delete
```

`make delete` también elimina los ficheros locales generados (`.env.local`, `cognito.properties`, etc.); el siguiente `create` los regenera. Si la base de datos Aurora ya existía cuando se desplegó, `make delete` la conserva, junto con su grupo de seguridad, y solo retira lo que creó este despliegue.

## Los scripts generan o actualizan estos ficheros:

- `aws-scripts/lab-state.json`: IDs de infraestructura del laboratorio (VpcId, SubnetIds, GroupId, AlbGroupId, LoadBalancerArn, TargetGroupArn, FrontTargetGroupArn, CertificateArn, EcsCluster, EcsService, FrontEcsService, UserPoolId, ClientId, CallbackUrl, …). Lo escriben los scripts de create; no versionar.
- `eventhub-front-react/.env.local`: variables de Cognito utilizadas por Vite (dev y build).
- `eventhub-front-react/.env.production.local`: URL de la API utilizada por Vite en el build de producción. Queda vacía: la API está en el mismo origen que el frontend.
- `eventhub-back-springboot/src/main/resources/cognito.properties`: emisor JWT utilizado por Spring Boot.
- `eventhub-back-springboot/src/main/resources/aurora.properties`: nombre del secreto de Aurora que importa Spring Boot y datos de conexión (`aurora.host`, `aurora.port`, `aurora.dbname`).

`cognito.properties` y `aurora.properties` viajan dentro del JAR, y por tanto dentro de la imagen Docker: `back.sh` falla si no existen.

Las carpetas necesarias deben existir previamente. `aws-scripts/cognito.sh` falla si no encuentra `eventhub-front-react/` o `eventhub-back-springboot/src/main/resources/`.

## Imagen Docker

`eventhub-back-springboot/Dockerfile` copia el JAR que genera `mvn package` sobre `amazoncorretto:21-alpine`. `back.sh` construye la imagen para la arquitectura del equipo que despliega (ARM64 o X86_64) y ejecuta las tareas de Fargate con esa misma arquitectura.

Las tareas usan el rol `LabRole` de AWS Academy, tanto para descargar la imagen y escribir los logs como para leer el secreto de Aurora. La salida de Spring Boot queda en el grupo de logs `/ecs/eventhub-back` de CloudWatch.

## Credenciales de la base de datos

El backend usa Aurora PostgreSQL, y su usuario y su contraseña no están en el repositorio: los crea el propio clúster al desplegarse y quedan en AWS Secrets Manager.

- `aws rds create-db-cluster --manage-master-user-password` hace que Aurora genere la contraseña y el secreto: no se escribe a mano ni viaja por la CLI.
- El nombre del secreto lo asigna RDS (`rds!cluster-...`), por lo que `aurora.sh` lo consulta y lo escribe en `aurora.properties`.
- El JSON del secreto gestionado por RDS solo contiene `username` y `password`. El endpoint del clúster lo devuelve `create-db-cluster` y `aurora.sh` lo escribe en `aurora.properties`; Spring Boot construye `jdbc:aws-wrapper:postgresql://${aurora.host}:${aurora.port}/${aurora.dbname}` con el driver JDBC de AWS, que envía las transacciones de solo lectura a la réplica.
- Aurora es accesible solo desde la VPC: `aurora.sh` abre el puerto 5432 en el grupo de seguridad de las tareas y únicamente para el tráfico de ese mismo grupo.
- Los tests no necesitan AWS: `src/test/resources/application.properties` arranca H2 en memoria con credenciales fijas.

`make delete` elimina las dos instancias, el clúster y su subnet group, si los creó este despliegue; RDS se encarga de retirar el secreto. Si ya existían, los conserva.

## La aplicación estará disponible en

### Front

https://<LoadBalancerDns de lab-state.json>/

La API queda en la misma dirección, bajo `/api/`.

### Documentación OpenAPI (solo desarrollo)

Swagger no se publica en AWS. En local, arranca el backend con el perfil `dev`:

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
