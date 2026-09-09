package es.upm.grise.profundizacion.correos;

import es.upm.grise.profundizacion.correos.controller.CorreoController;
import es.upm.grise.profundizacion.correos.service.CorreoService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mail.MailSender;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest
class CorreosApplicationSmokeTest {

    @Autowired
    private CorreoController correoController;

    @Autowired
    private CorreoService correoService;

    // Lo crea la autoconfiguración de Spring Cloud AWS sobre SES: si falta, el servicio no podría enviar nada.
    @Autowired
    private MailSender mailSender;

    @Test
    @DisplayName("Smoke Test - Verificación de inyección de beans del microservicio de correos")
    void contextLoadsAndBeansAreInitialized() {
        assertThat(correoController).isNotNull();
        assertThat(correoService).isNotNull();
        assertThat(mailSender).isNotNull();
    }
}
