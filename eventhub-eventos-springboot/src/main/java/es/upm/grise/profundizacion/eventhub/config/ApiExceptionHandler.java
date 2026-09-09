package es.upm.grise.profundizacion.eventhub.config;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.Map;

@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler(RuntimeException.class)
    public ResponseEntity<Map<String, String>> manejarRuntime(RuntimeException ex) {
        String mensaje = ex.getMessage() != null ? ex.getMessage() : "Error interno";
        HttpStatus status = mensaje.toLowerCase().contains("no encontrado")
                ? HttpStatus.NOT_FOUND
                : HttpStatus.INTERNAL_SERVER_ERROR;
        return ResponseEntity.status(status).body(Map.of(
                "error", status.getReasonPhrase(),
                "mensaje", mensaje
        ));
    }
}
