package es.upm.grise.profundizacion.eventhub.config;

import es.upm.grise.profundizacion.eventhub.model.Evento;
import es.upm.grise.profundizacion.eventhub.repository.EventoRepository;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.math.BigDecimal;

@Configuration
public class DataInitializer {

    @Bean
    public CommandLineRunner initData(EventoRepository eventoRepository) {
        return args -> {
            if (eventoRepository.count() == 0) {
                eventoRepository.save(new Evento("Concierto Rock", "Concierto en vivo de Rock", new BigDecimal("45.00"), 100));
                eventoRepository.save(new Evento("Obra de Teatro", "Comedia clásica", new BigDecimal("25.50"), 50));
                eventoRepository.save(new Evento("Festival Jazz", "Festival al aire libre", new BigDecimal("30.00"), 0));
            }
        };
    }
}
