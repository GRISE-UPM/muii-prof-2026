package es.upm.grise.profundizacion.pagos.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import org.springframework.context.annotation.Configuration;

/**
 * Documentación OpenAPI del microservicio de pagos.
 *
 * No declara ningún esquema de seguridad: el servicio escucha solo en 127.0.0.1 y no está
 * publicado por Nginx, así que el único cliente posible es el servicio de eventos de la misma máquina.
 */
@Configuration
@OpenAPIDefinition(
    info = @Info(
        title = "Event Hub - API de pagos",
        version = "0.1",
        description = "Microservicio interno que resuelve las solicitudes de cobro del servicio de eventos"
    )
)
public class OpenApiConfig {
}
