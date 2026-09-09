package es.upm.grise.profundizacion.correos.config;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.mail.MailException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

@RestControllerAdvice
public class ApiExceptionHandler {

    /**
     * Un fallo de SES no es un error de la petición: se responde 502 para que quien llama
     * distinga entre "el correo iba mal formado" y "el proveedor no ha podido enviarlo".
     */
    @ExceptionHandler(MailException.class)
    public ResponseEntity<Map<String, String>> manejarFalloDeEnvio(MailException ex) {
        String mensaje = ex.getMessage() != null ? ex.getMessage() : "No se pudo enviar el correo";
        return ResponseEntity.status(HttpStatus.BAD_GATEWAY).body(Map.of(
                "error", HttpStatus.BAD_GATEWAY.getReasonPhrase(),
                "mensaje", mensaje
        ));
    }
}
