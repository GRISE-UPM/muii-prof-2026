package es.upm.grise.profundizacion.pagos.service;

import es.upm.grise.profundizacion.pagos.dto.PagoRequestDTO;
import es.upm.grise.profundizacion.pagos.dto.PagoResponseDTO;
import es.upm.grise.profundizacion.pagos.model.EstadoPago;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.UUID;
import java.util.random.RandomGenerator;

/**
 * Simula la pasarela de cobro: no hay banco detrás, la decisión se toma al azar
 * con la probabilidad de fallo que indique 'pagos.probabilidad-fallo'.
 */
@Service
public class PagoService {

    private static final Logger log = LoggerFactory.getLogger(PagoService.class);

    private final double probabilidadFallo;
    private final RandomGenerator aleatorio;

    public PagoService(@Value("${pagos.probabilidad-fallo}") double probabilidadFallo,
                       RandomGenerator aleatorio) {
        this.probabilidadFallo = probabilidadFallo;
        this.aleatorio = aleatorio;
    }

    public PagoResponseDTO cobrar(PagoRequestDTO dto) {
        String referencia = "PAG-" + UUID.randomUUID();
        boolean denegado = aleatorio.nextDouble() < probabilidadFallo;

        if (denegado) {
            log.info("Cobro {} DENEGADO: evento {}, usuario {}, importe {}",
                    referencia, dto.getEventoId(), dto.getUsuarioEmail(), dto.getImporte());
            return new PagoResponseDTO(referencia, EstadoPago.DENEGADO, "La entidad emisora ha rechazado el cargo");
        }

        log.info("Cobro {} APROBADO: evento {}, usuario {}, importe {}",
                referencia, dto.getEventoId(), dto.getUsuarioEmail(), dto.getImporte());
        return new PagoResponseDTO(referencia, EstadoPago.APROBADO, "Cargo autorizado");
    }
}
