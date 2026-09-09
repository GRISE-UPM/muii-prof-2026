package es.upm.grise.profundizacion.eventhub.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.ClientHttpRequestFactory;
import org.springframework.http.client.SimpleClientHttpRequestFactory;

import java.time.Duration;

/**
 * Transporte HTTP compartido por los clientes de pagos y de correos.
 *
 * Los tiempos de espera son obligatorios: sin ellos, un microservicio que no responde dejaría
 * colgada la compra del usuario en lugar de fallar rápido.
 */
@Configuration
public class ServiciosInternosConfig {

    @Bean
    public ClientHttpRequestFactory clientHttpRequestFactory(
            @Value("${servicios.espera-conexion}") Duration esperaConexion,
            @Value("${servicios.espera-lectura}") Duration esperaLectura) {

        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(esperaConexion);
        factory.setReadTimeout(esperaLectura);
        return factory;
    }
}
