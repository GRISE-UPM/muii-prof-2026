package es.upm.grise.profundizacion.eventhub;

import es.upm.grise.profundizacion.eventhub.controller.EventoController;
import es.upm.grise.profundizacion.eventhub.repository.CompraRepository;
import es.upm.grise.profundizacion.eventhub.repository.EventoRepository;
import es.upm.grise.profundizacion.eventhub.service.EventoService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
class EventHubApplicationSmokeTest {

    @Autowired
    private EventoController eventoController;

    @Autowired
    private EventoService eventoService;

    @Autowired
    private EventoRepository eventoRepository;

    @Autowired
    private CompraRepository compraRepository;

    @Test
    @DisplayName("Smoke Test - Verificación de inyección de beans y repositorios")
    void contextLoadsAndBeansAreInitialized() {
        assertThat(eventoController).isNotNull();
        assertThat(eventoService).isNotNull();
        assertThat(eventoRepository).isNotNull();
        assertThat(compraRepository).isNotNull();
    }
}
