package es.upm.grise.profundizacion.eventhub.config;

import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

/**
 * Configuración principal de seguridad para la aplicación Spring Boot.
 * Define la autenticación OAuth2 y las reglas de autorización por HTTP y rol.
 */
@Configuration // Indica a Spring que esta clase es una fuente de configuración global
@EnableMethodSecurity // Habilita la seguridad basada en anotaciones en métodos (ej. @PreAuthorize, @Secured)
public class SecurityConfig {

    /**
     * Define la cadena de filtros de seguridad (SecurityFilterChain) que procesa las peticiones HTTP entrantes.
     */
    @Bean // Objeto creado automaticamente y gestionado por Spring Boot
    public SecurityFilterChain securityFilterChain(HttpSecurity http, Environment env) throws Exception {
        http
            // Deshabilita la protección CSRF (común en APIs REST sin estado que usan tokens JWT)
            // TODO: Tendremos que cambiar esta opción en una versión posterior cuando introduzcamos las 
            // Lambdas como Token Handlers
            .csrf(csrf -> csrf.disable())
            // Nginx sirve front y API en el mismo origen: CORS no se usa en produccion.
            // Solo el perfil 'dev' lo activa, para el Vite en http://localhost:3000.
            .cors(cors -> {
                if (env.matchesProfiles("dev")) {
                    cors.configurationSource(corsConfigurationSource());
                } else {
                    cors.disable();
                }
            })

            // Deshabilita la restricción de Frames (necesario para desplegar correctamente la consola H2 en iframe)
            // TODO: Se podrá activar cuando migremos a una base de datos convencional
            .headers(headers -> headers.frameOptions(frame -> frame.disable()))

            // Configuración de autorización basada en endpoints HTTP
            .authorizeHttpRequests(auth -> auth
                // Permite acceso público sin autenticación a la documentación Swagger/OpenAPI y la consola H2
                .requestMatchers("/swagger-ui/**", "/swagger-ui.html", "/v3/api-docs/**", "/h2-console/**").permitAll()
                
                // Creación de eventos: Exclusivo para usuarios con rol ADMIN
                .requestMatchers(HttpMethod.POST, "/api/eventos").hasRole("ADMIN")
                
                // Consulta de eventos: Permitida para usuarios con rol USER o ADMIN
                .requestMatchers(HttpMethod.GET, "/api/eventos/**").hasAnyRole("USER", "ADMIN")
                
                // Compra de entradas: Exclusiva para usuarios con rol USER
                .requestMatchers(HttpMethod.POST, "/api/eventos/*/comprar").hasRole("USER")
                
                // Cualquier otro endpoint no especificado requiere al menos estar autenticado
                // TODO: Parece mala idea, pero será útil cuando migremos la seguridad al API Gateway, ya que
                //       cederemos al API Gateway el control de las rutas
                .anyRequest().authenticated()
            )

            // Configura la aplicación como un servidor de recursos OAuth2 que valida tokens JWT.
            // Los 401/403 hay que definirlos aquí: si no, el resource server deja el cuerpo vacío
            // o Spring envía la página HTML de error.
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter()))
                .authenticationEntryPoint((request, response, authException) ->
                    escribirErrorJson(response, HttpStatus.UNAUTHORIZED, "Unauthorized",
                        "No hay sesión o el token no es válido"))
                .accessDeniedHandler((request, response, accessDeniedException) ->
                    escribirErrorJson(response, HttpStatus.FORBIDDEN, "Forbidden",
                        "El rol no permite esta operación"))
            );

        return http.build();
    }

    private CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(List.of("http://localhost:3000"));
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }

    private void escribirErrorJson(HttpServletResponse response, HttpStatus status, String error, String mensaje)
            throws IOException {
        response.setStatus(status.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write("{\"error\":\"" + error + "\",\"mensaje\":\"" + mensaje + "\"}");
    }

    /**
     * Convertidor personalizado para extraer los grupos de AWS Cognito desde el token JWT.
     * Si el usuario no tiene ningún grupo asignado, se le otorga el rol 'ROLE_USER' por defecto.
     */
    private JwtAuthenticationConverter jwtAuthenticationConverter() {
        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            Collection<GrantedAuthority> authorities = new ArrayList<>();
            
            // Extrae el claim personalizado 'cognito:groups' enviado por AWS Cognito
            List<String> groups = jwt.getClaimAsStringList("cognito:groups");
            
            if (groups != null && !groups.isEmpty()) {
                // Mapea los grupos existentes (ej. "admin" -> "ROLE_ADMIN")
                // Se concatena el prefijo "ROLE_" porque el método .hasRole("ADMIN") de Spring 
                // busca internamente una autoridad llamada exactamente "ROLE_ADMIN". 
                // Si se usara solo "ADMIN", habría que evaluarlo con .hasAuthority("ADMIN").
                groups.forEach(group -> 
                    authorities.add(new SimpleGrantedAuthority("ROLE_" + group.toUpperCase()))
                );
            } else {
                // Asignación por defecto: Si no tiene grupos en Cognito, se le asigna ROLE_USER
                // TODO: Esto habrá que cambiarlo cuando migremos la seguridad al API Gateway
                // La razón es que ahora consideramos a todo usuario autenticado como ROLE_USER,
                // pero al migrar al API Gateway la seguridad, necesitaremos crear una Lambda
                // que asigne el rol automaticamente, por lo que NO TODO USUARIO AUTENTICADO
                // será necesariamente un ROLE_USER
                authorities.add(new SimpleGrantedAuthority("ROLE_USER"));
            }
            
            return authorities;
        });
        
        return converter;
    }
}