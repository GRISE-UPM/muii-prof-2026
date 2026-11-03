# Event Hub

Aplicación para gestionar eventos, compuesta por:

- `eventhub-back-springboot`: API REST Spring Boot con JPA, H2 y OpenAPI.
- `eventhub-front-react`: aplicación React/Vite para la interfaz web.
- `cdk`: aplicación AWS CDK (Python) que define la instancia EC2 con Nginx, su IP elástica y su grupo de seguridad.
- `aws-scripts`: scripts para esperar a que Nginx esté instalado y publicar el backend y el frontend.

## Requisitos

### Instala y configura:

- Java 21 o superior
- Maven 3.9 o superior
- Node.js y npm
- Python 3
- AWS CLI
- AWS CDK CLI (`npm install -g aws-cdk`)

### Configura las credenciales de AWS:

- Descarga las credenciales desde AWS Academy y almacénalas en ~/aws/credentials
- Descarga la SSH key y almacénala en ssh-key/

## Configuración inicial

- Asigna permiso de ejecución a los ficheros .sh en aws-scripts/
- No hace falta `cdk bootstrap`: la aplicación usa `LegacyStackSynthesizer`, ya que el bootstrap crea roles IAM y el Learner Lab no lo permite.

## Despliegue con Make

- Ejecuta

```bash
make deploy
```

desde la raíz para crear EC2 con CDK y publicar backend y frontend. Si una fase falla, el despliegue se detiene. Para eliminar frontend, backend, EC2 y los ficheros de configuración generados:

```bash
make delete
```

Otras órdenes útiles:

```bash
make synth  # genera la plantilla de CloudFormation sin desplegar
make diff   # qué cambiaría un despliegue respecto a lo que hay en AWS
```

## Los scripts generan o actualizan estos ficheros:

- `cdk/cdk.context.json`: resultado de la búsqueda de la VPC por defecto. CDK lo escribe en la primera síntesis y conviene versionarlo.
- `eventhub-front-react/.env.production.local`: variables utilizadas por Vite en el build de producción.

## La aplicación estará disponible en

### Front

http://<PublicIp, salida de la pila EventHubStack>/

### Documentación OpenAPI (solo desarrollo)

Swagger no se publica en EC2. En local, arranca el backend con el perfil `dev`:

```bash
cd eventhub-back-springboot
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

El UI queda en `http://localhost:8080/swagger-ui.html`.

## Ejecutar el frontend localmente

```bash
cd eventhub-front-react
npm install
npm run dev
```

La aplicación estará disponible normalmente en `http://localhost:3000`. En desarrollo las peticiones van a `http://localhost:8080` (`VITE_API_BASE_URL` en `.env.development`). El `build` de producción usa `.env.production.local` (generado por `front.sh`).