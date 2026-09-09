package es.upm.grise.profundizacion.correos.service;

import es.upm.grise.profundizacion.correos.dto.ConfirmacionCompraRequestDTO;
import es.upm.grise.profundizacion.correos.dto.CorreoResponseDTO;
import es.upm.grise.profundizacion.correos.model.ResultadoCobro;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.MailSender;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.stereotype.Service;

/**
 * Redacta y envía el correo de la compra.
 *
 * El MailSender lo crea la autoconfiguración de Spring Cloud AWS sobre Amazon SES, de modo que
 * el texto del correo se escribe aquí y el transporte queda fuera de esta clase.
 */
@Service
public class CorreoService {

    private static final Logger log = LoggerFactory.getLogger(CorreoService.class);

    private final MailSender mailSender;
    private final String remitente;

    public CorreoService(MailSender mailSender, @Value("${correos.remitente}") String remitente) {
        this.mailSender = mailSender;
        this.remitente = remitente;
    }

    public CorreoResponseDTO enviarConfirmacionCompra(ConfirmacionCompraRequestDTO dto) {
        boolean cobrado = dto.getResultadoCobro() == ResultadoCobro.COBRO_OK;
        String asunto = (cobrado ? "Compra confirmada: " : "Compra rechazada: ") + dto.getEvento();

        SimpleMailMessage mensaje = new SimpleMailMessage();
        mensaje.setFrom(remitente);
        mensaje.setTo(dto.getDestinatario());
        mensaje.setSubject(asunto);
        mensaje.setText(redactarCuerpo(dto, cobrado));

        mailSender.send(mensaje);
        log.info("Correo enviado a {} con asunto '{}'", dto.getDestinatario(), asunto);

        return new CorreoResponseDTO(dto.getDestinatario(), asunto);
    }

    private String redactarCuerpo(ConfirmacionCompraRequestDTO dto, boolean cobrado) {
        StringBuilder cuerpo = new StringBuilder();

        if (cobrado) {
            cuerpo.append("Hemos cobrado tu entrada para ").append(dto.getEvento()).append(".\n\n");
        } else {
            cuerpo.append("No hemos podido cobrar tu entrada para ").append(dto.getEvento())
                  .append(", por lo que la compra no se ha completado.\n\n");
        }

        cuerpo.append("Importe: ").append(dto.getImporte()).append(" euros\n");
        if (dto.getReferenciaPago() != null && !dto.getReferenciaPago().isBlank()) {
            cuerpo.append("Referencia del cobro: ").append(dto.getReferenciaPago()).append("\n");
        }
        cuerpo.append("\nEvent Hub");

        return cuerpo.toString();
    }
}
