package es.upm.grise.profundizacion.pagos;

import es.upm.grise.profundizacion.pagos.controller.PagoController;
import es.upm.grise.profundizacion.pagos.service.PagoService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
class PagosApplicationSmokeTest {

    @Autowired
    private PagoController pagoController;

    @Autowired
    private PagoService pagoService;

    @Test
    @DisplayName("Smoke Test - Verificación de inyección de beans del microservicio de pagos")
    void contextLoadsAndBeansAreInitialized() {
        assertThat(pagoController).isNotNull();
        assertThat(pagoService).isNotNull();
    }
}
