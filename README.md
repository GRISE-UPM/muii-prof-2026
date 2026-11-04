# Event Hub

Aplicación para gestionar eventos, compuesta por:

- `eventhub-back-springboot`: API REST Spring Boot con JPA, H2 y OpenAPI.
- `eventhub-front-react`: aplicación React/Vite para la interfaz web.
- `cdk`: aplicación AWS CDK (Python) que define la instancia EC2 con Nginx, su IP elástica y su grupo de seguridad.
- `.github/workflows`: despliegue a través de pull requests con GitHub Actions (`infra-pr.yml` e `infra-deploy.yml`).
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

## Despliegue con GitHub Actions

Un pull request ejecuta `infra-pr.yml`, con tres trabajos. `diff` comenta el `cdk diff` respecto a la pila de producción. `preview` despliega la aplicación completa en una pila aparte, `EventHubStack-pr-<número>`, y comenta su dirección. `limpieza` borra esa pila al cerrar el PR. El merge a `main` ejecuta `infra-deploy.yml`, con un trabajo por fase (`infra`, y después `back` y `front` a la vez). Cada trabajo llama al mismo script que `make deploy` usa en local. Como el laboratorio no permite OIDC, los workflows usan las credenciales de la sesión, que caducan con ella. Hace falta configurar en el repositorio (*Settings > Secrets and variables > Actions*):

- Los secretos `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y `AWS_SESSION_TOKEN`, con los valores de *AWS Details > AWS CLI*. Hay que actualizarlos cada vez que se pulsa *Start Lab*.
- El secreto `SSH_PRIVATE_KEY`, con el contenido de la clave privada `vockey` (`labsuser.pem`).
- Proteger la rama `main` para exigir el PR y que pasen `diff` y `preview`.

Si un merge se hizo con la sesión caducada, el despliegue falla. Tras actualizar los secretos, se relanza desde la pestaña *Actions* (*Run workflow*).

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