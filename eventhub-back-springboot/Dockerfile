# Imagen del backend: el JAR que genera mvn package sobre un JRE 21.
# La construye y la sube a ECR aws-scripts/back.sh.
FROM amazoncorretto:21-alpine
WORKDIR /app
COPY target/eventhub-*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
