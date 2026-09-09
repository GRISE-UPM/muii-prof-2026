package es.upm.grise.profundizacion.eventhub.service;

import es.upm.grise.profundizacion.eventhub.model.Compra;
import es.upm.grise.profundizacion.eventhub.model.EstadoCobro;
import es.upm.grise.profundizacion.eventhub.model.Evento;
import es.upm.grise.profundizacion.eventhub.repository.CompraRepository;
import es.upm.grise.profundizacion.eventhub.repository.EventoRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

/**
 * Escritura en base de datos de una compra ya resuelta.
 *
 * Vive en su propia clase para que la transacción empiece cuando el cobro ya ha respondido:
 * si envolviera también las llamadas a los microservicios, la conexión a Aurora quedaría
 * retenida durante toda la espera de la red.
 */
@Service
public class CompraService {

    private final EventoRepository eventoRepository;
    private final CompraRepository compraRepository;

    public CompraService(EventoRepository eventoRepository, CompraRepository compraRepository) {
        this.eventoRepository = eventoRepository;
        this.compraRepository = compraRepository;
    }

    @Transactional
    public Compra registrarCompra(Long eventoId, String usuarioEmail, EstadoCobro estadoCobro, String referenciaPago) {
        Evento evento = eventoRepository.findById(eventoId)
                .orElseThrow(() -> new RuntimeException("Evento no encontrado con id: " + eventoId));

        // El aforo solo baja si el cobro salió bien: una compra NOK se registra como intento fallido.
        if (estadoCobro == EstadoCobro.COBRO_OK) {
            evento.setAforoDisponible(evento.getAforoDisponible() - 1);
            eventoRepository.save(evento);
        }

        Compra compra = new Compra(evento, usuarioEmail, LocalDateTime.now(), evento.getPrecio(),
                estadoCobro, referenciaPago);
        return compraRepository.save(compra);
    }
}
