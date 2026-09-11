# Event Hub

Aplicación para gestionar eventos, compuesta por:

- `eventhub-eventos-springboot`: servicio de eventos. API REST Spring Boot con JPA, Aurora PostgreSQL (usando las credenciales que Aurora almacena en AWS Secrets Manager), seguridad OAuth2/JWT y OpenAPI. Además coordina la compra llamando a los otros dos servicios.
- `eventhub-pagos-springboot`: microservicio de cobros. Resuelve cada solicitud de cargo simulando una pasarela de pago.
- `eventhub-correos-springboot`: microservicio de correos. Avisa al comprador por Amazon SES del resultado de su compra.
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

desde la raíz para crear EC2, crear el clúster Aurora, configurar Nginx, crear Cognito y publicar backend y frontend. Si una fase falla, el despliegue se detiene. La creación de Aurora tarda varios minutos. Cognito no se borra: si el User Pool o el dominio ya existen, se reutilizan. Para eliminar frontend, backend, Aurora, EC2 y los ficheros de la instancia:

```bash
make delete
```

## Los scripts generan o actualizan estos ficheros:

- `aws-scripts/lab-state.json`: IDs de infraestructura del laboratorio (GroupId, VpcId, SubnetIds, InstanceId, AllocationId, PublicIp, UserPoolId, ClientId, Domain, CallbackUrl, …). Lo escriben los scripts de create; no versionar.
- `eventhub-front-react/.env.local`: variables de Cognito utilizadas por Vite (dev y build).
- `eventhub-front-react/.env.production.local`: URL de la API utilizada por Vite en el build de producción.
- `eventhub-eventos-springboot/src/main/resources/cognito.properties`: emisor JWT utilizado por Spring Boot.
- `eventhub-eventos-springboot/src/main/resources/aurora.properties`: nombre del secreto de Aurora que importa Spring Boot.

Las carpetas necesarias deben existir previamente. `aws-scripts/cognito.sh` falla si no encuentra `eventhub-front-react/` o `eventhub-eventos-springboot/src/main/resources/`.

## Credenciales de la base de datos

El backend usa Aurora PostgreSQL, y su usuario y su contraseña no están en el repositorio: los crea el propio clúster al desplegarse y quedan en AWS Secrets Manager.

- `aws rds create-db-cluster --manage-master-user-password` hace que Aurora genere la contraseña y el secreto: no se escribe a mano ni viaja por la CLI.
- El nombre del secreto lo asigna RDS (`rds!cluster-...`), por lo que `aurora.sh` lo consulta y lo escribe en `aurora.properties`.
- El JSON del secreto contiene `username`, `password`, `host`, `port` y `dbname`, con los que Spring Boot construye `jdbc:postgresql://${host}:${port}/${dbname}`.
- Aurora es accesible solo desde la VPC: `aurora.sh` abre el puerto 5432 en el grupo de seguridad de EC2 y únicamente para el tráfico de ese mismo grupo.
- Los tests no necesitan AWS: `src/test/resources/application.properties` arranca H2 en memoria con credenciales fijas.

`make delete` elimina la instancia, el clúster y su subnet group; RDS se encarga de retirar el secreto.

## Compra de una entrada

La compra la coordina el servicio de eventos, que es el único publicado por Nginx. Los otros dos escuchan solo en `127.0.0.1`, así que únicamente se les puede llamar desde la propia máquina:

1. Eventos comprueba el aforo del evento y, si queda, pide el cargo a pagos (`POST http://127.0.0.1:8081/api/pagos`).
2. Pagos responde `APROBADO` o `DENEGADO` con una referencia. La denegación llega con un 200: es un resultado de negocio, no un error.
3. Eventos guarda la compra marcada como `COBRO_OK` o `COBRO_NOK`. El aforo solo baja cuando el cobro se aprueba.
4. Eventos encarga el aviso a correos (`POST http://127.0.0.1:8082/api/correos/confirmacion-compra`), que redacta el texto y lo envía por Amazon SES.

Los dos microservicios pueden fallar sin tumbar la compra:

- Si pagos no responde, eventos registra la compra como `COBRO_NOK` sin referencia de pago.
- Si correos no responde, la compra ya está guardada y el fallo se ignora.

El comportamiento se ajusta desde las propiedades de cada servicio:

- `pagos.probabilidad-fallo` (por defecto `0.2`): con qué frecuencia se deniega el cargo. Con `0.0` se aprueban todos.
- `correos.remitente`: identidad verificada en SES desde la que sale el correo. Mientras la cuenta esté en el sandbox de SES, el destinatario también tiene que estar verificado.
- `servicios.pagos.url` y `servicios.correos.url` en eventos: dónde buscar cada microservicio.

## Ejecutar los microservicios localmente

Cada servicio es un proyecto Maven independiente y se arranca por separado:

```bash
cd eventhub-pagos-springboot
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

```bash
cd eventhub-correos-springboot
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

Con el perfil `dev` cada uno publica su Swagger en `http://localhost:8081/swagger-ui.html` y `http://localhost:8082/swagger-ui.html`. El de correos necesita credenciales de AWS válidas para que SES acepte el envío.

## La aplicación estará disponible en

### Front

https://<PublicIp de lab-state.json>/

### Documentación OpenAPI (solo desarrollo)

Swagger no se publica en EC2. En local, arranca el backend con el perfil `dev`:

```bash
cd eventhub-eventos-springboot
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

El UI queda en `http://localhost:8080/swagger-ui.html`.

## Ejecutar el frontend localmente

```bash
cd eventhub-front-react
npm install
npm run dev
```

La aplicación estará disponible normalmente en `http://localhost:3000`. En desarrollo las peticiones van a `http://localhost:8080` (`VITE_API_BASE_URL` en `.env.development`). El `build` de producción usa `.env.production.local` (generado por `front.sh`). Las variables de Cognito salen de `.env.local` (generado por `cognito.sh`).
