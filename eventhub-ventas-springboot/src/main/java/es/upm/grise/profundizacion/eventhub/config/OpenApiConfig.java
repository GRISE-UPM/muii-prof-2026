package es.upm.grise.profundizacion.eventhub.config;

import io.swagger.v3.oas.annotations.OpenAPIDefinition;
import io.swagger.v3.oas.annotations.enums.SecuritySchemeType;
import io.swagger.v3.oas.annotations.info.Info;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.security.SecurityScheme;
import org.springframework.context.annotation.Configuration;

/**
 * Configuración de OpenAPI / Swagger 3 para la documentación interactiva de la API.
 * 
 * NOTA DE SEGURIDAD Y INTEGRACIÓN:
 * Esta interfaz es accesible públicamente gracias a la regla .requestMatchers("/swagger-ui/**", "/v3/api-docs/**").permitAll() 
 * corresponda utilizando el botón 'Authorize'
 * configurada en SecurityConfig. Permite a los usuarios probar endpoints autenticados inyectando el token JWT que
 */
@Configuration // Registra la clase como un componente de configuración dentro del contenedor de Spring
@OpenAPIDefinition(
    // Define la información general que se mostrará en la cabecera de Swagger UI
    info = @Info(
        title = "Event Hub API", 
        version = "0.1", 
        description = "Documentación de la API Event Hub"
    ),
    // Aplica de forma global el requisito de seguridad 'bearerAuth' a todos los endpoints documentados.
    // Esto añade el icono del candado en la UI de Swagger para indicar que las peticiones requieren el token JWT.
    security = @SecurityRequirement(name = "bearerAuth")
)
@SecurityScheme(
    // Nombre del esquema de seguridad de referencia utilizado en @SecurityRequirement
    name = "bearerAuth",
    
    // Tipo de esquema HTTP estándar
    type = SecuritySchemeType.HTTP,
    
    // Especifica que el token transportado en la cabecera es un JWT (emitido en este entorno por AWS Cognito)
    bearerFormat = "JWT",
    
    // Define el esquema 'bearer' para que Swagger UI adjunte automáticamente la cabecera:
    // 'Authorization: Bearer <token_jwt>' en las peticiones de prueba hacia los endpoints protegidos en SecurityConfig
    scheme = "bearer"
)
public class OpenApiConfig {
}