# Event Hub

Aplicación para gestionar eventos, compuesta por:

- `eventhub-back-springboot`: API REST Spring Boot con JPA, Aurora PostgreSQL (usando las credenciales que Aurora almacena en AWS Secrets Manager), seguridad OAuth2/JWT y OpenAPI. Se empaqueta como imagen Docker y se ejecuta en Amazon ECS con Fargate.
- `eventhub-front-react`: aplicación React/Vite para la interfaz web, con login Cognito y visualización de JWT. Se sirve como sitio estático desde Amazon S3 a través de Amazon CloudFront.
- `aws-scripts`: scripts para crear la red, el clúster Aurora, el balanceador, la distribución de CloudFront, Cognito y el clúster de ECS, y para publicar el backend y el frontend.

## Arquitectura

```
Navegador ──HTTPS──> CloudFront (*.cloudfront.net)
                      ├── /*      ──> S3 (SPA, bucket privado)
                      └── /api/*  ──HTTP──> ALB ──> tareas ECS Fargate (2 zonas) ──> Aurora PostgreSQL
```

- CloudFront pone el HTTPS con su certificado `*.cloudfront.net`. La SPA y la API comparten origen, así que no hace falta CORS.
- El balanceador solo acepta tráfico de CloudFront, y las tareas solo del balanceador. Aurora solo acepta conexiones de las tareas.
- El balanceador comprueba la salud de cada tarea en `/actuator/health/liveness` y deja de enviar peticiones a las que no responden.

## Requisitos

### Instala y configura:

- Java 21 o superior
- Maven 3.9 o superior
- Node.js y npm
- Docker (con el daemon arrancado: `back.sh` construye la imagen)
- Python 3
- AWS CLI y jq

### Configura las credenciales de AWS:

- Descarga las credenciales desde AWS Academy y almacénalas en ~/.aws/credentials

## Configuración inicial

- Asigna permiso de ejecución a los ficheros .sh en aws-scripts/

## Despliegue con Make

- Ejecuta

```bash
make deploy
```

desde la raíz. Los scripts se ejecutan en este orden, y cada uno lee de `lab-state.json` lo que dejaron los anteriores:

| Script | Crea |
|---|---|
| `red.sh` | Subnets de la VPC por defecto y los grupos de seguridad del balanceador (`eventhub-alb-sg`) y de las tareas (`eventhub-sg`) |
| `aurora.sh` | Clúster Aurora PostgreSQL con una instancia en cada zona, y `aurora.properties` |
| `alb.sh` | Application Load Balancer, grupo de destino y listener HTTP:80 |
| `cloudfront.sh` | Bucket S3 privado y distribución de CloudFront con dos orígenes (S3 y el balanceador) |
| `cognito.sh` | User Pool, cliente y dominio de Cognito, con el dominio de CloudFront como callback |
| `ecs.sh` | Repositorio ECR, grupo de logs de CloudWatch y clúster de ECS |
| `back.sh` | Compila el backend, sube la imagen a ECR y crea (o actualiza) el servicio con dos tareas |
| `front.sh` | Compila el frontend, lo sube al bucket e invalida la caché de CloudFront |

Si una fase falla, el despliegue se detiene. La creación de Aurora y la de CloudFront tardan varios minutos. Cognito en AWS no se borra: si el User Pool o el dominio ya existen, se reutilizan.

Para publicar una nueva versión del código basta con volver a ejecutar `back.sh` o `front.sh`. ECS sustituye las tareas poco a poco, sin cortar el servicio.

Para eliminar todo, en orden inverso:

```bash
make delete
```

`make delete` también elimina los ficheros locales generados (`.env.local`, `cognito.properties`, etc.); el siguiente `create` los regenera. Desactivar y borrar la distribución de CloudFront tarda varios minutos.

## Los scripts generan o actualizan estos ficheros:

- `aws-scripts/lab-state.json`: IDs de infraestructura del laboratorio (VpcId, SubnetIds, GroupId, AlbGroupId, LoadBalancerArn, TargetGroupArn, BucketName, DistributionId, DistributionDomain, EcsCluster, EcsService, UserPoolId, ClientId, CallbackUrl, …). Lo escriben los scripts de create; no versionar.
- `eventhub-front-react/.env.local`: variables de Cognito utilizadas por Vite (dev y build).
- `eventhub-front-react/.env.production.local`: URL de la API utilizada por Vite en el build de producción. Queda vacía: la API está en el mismo origen que la SPA.
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

`make delete` elimina las dos instancias, el clúster y su subnet group; RDS se encarga de retirar el secreto.

## La aplicación estará disponible en

### Front

https://<DistributionDomain de lab-state.json>/

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
