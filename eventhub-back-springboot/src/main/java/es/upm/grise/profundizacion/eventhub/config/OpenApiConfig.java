package es.upm.grise.profundizacion.eventhub.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.info.Info;
import org.springframework.context.annotation.Configuration;

/**
 * Configuración de OpenAPI / Swagger 3 para la documentación interactiva de la API.
 */
@Configuration
@OpenAPIDefinition(
    info = @Info(
        title = "Event Hub API",
        version = "0.1",
        description = "Documentación de la API Event Hub"
    )
)
public class OpenApiConfig {
}
