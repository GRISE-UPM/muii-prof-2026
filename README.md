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

- Credenciales de una cuenta de AWS con permisos para crear stacks, roles IAM, instancias EC2 e IPs elásticas
- Un par de claves EC2 llamado `vockey` en la región `us-east-1`, cuya clave privada debe estar en `ssh-key/labsuser.pem`

## Configuración inicial

- Asigna permiso de ejecución a los ficheros .sh en aws-scripts/
- Ejecuta `make bootstrap` una vez por cuenta y región (CDK crea un bucket y unos roles que usa al desplegar).
- Esta versión no se puede desplegar en AWS Academy Learner Lab, ya que crea roles IAM. Para el laboratorio existe la versión `V1.0.0-CDK-learner-lab`.

## Despliegue con GitHub Actions

Nadie despliega desde su máquina. Un pull request que cambia `cdk/` ejecuta `infra-pr.yml` (`cdk synth` y un comentario con `cdk diff`), y el merge a `main` ejecuta `infra-deploy.yml`, con un trabajo por fase (`infra`, y después `back` y `front` a la vez). Cada trabajo llama al mismo script que `make deploy` usa en local, así que la lógica vive en `aws-scripts/` y se puede depurar sin GitHub. Los workflows se autentican en AWS con OIDC, sin claves guardadas. Hace falta configurar una vez en AWS y en GitHub:

- Un proveedor de identidad OIDC para `token.actions.githubusercontent.com` y dos roles. `github-cdk-diff` (cuyo `sub` es `repo:<org>/<repo>:pull_request`) solo puede leer CloudFormation y asumir el rol de lookup del bootstrap. `github-cdk-deploy` (cuyo `sub` es `repo:<org>/<repo>:environment:produccion`) puede desplegar.
- Un entorno `produccion` en GitHub (con aprobación manual si se quiere).
- Un secreto `SSH_PRIVATE_KEY` con la clave privada del par `vockey`, para que los scripts publiquen el backend y el frontend.
- Las variables `AWS_ACCOUNT_ID` del repositorio, con el identificador de la cuenta.
- Proteger la rama `main` para exigir el PR, una aprobación y que pase `Infraestructura (PR) / diff`.

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