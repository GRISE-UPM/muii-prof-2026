package es.upm.grise.profundizacion.pagos.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.random.RandomGenerator;

/**
 * La fuente de azar se declara como bean para que los tests puedan sustituirla
 * por una secuencia conocida y el resultado del cobro sea reproducible.
 */
@Configuration
public class AleatorioConfig {

    @Bean
    public RandomGenerator aleatorio() {
        return RandomGenerator.getDefault();
    }
}
