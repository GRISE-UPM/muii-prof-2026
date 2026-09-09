package es.upm.grise.profundizacion.eventhub.service;

import es.upm.grise.profundizacion.eventhub.client.ConfirmacionCompraRequest;
import es.upm.grise.profundizacion.eventhub.client.CorreoClient;
import es.upm.grise.profundizacion.eventhub.client.PagoClient;
import es.upm.grise.profundizacion.eventhub.client.PagoRequest;
import es.upm.grise.profundizacion.eventhub.client.PagoResponse;
import es.upm.grise.profundizacion.eventhub.dto.CompraResponseDTO;
import es.upm.grise.profundizacion.eventhub.dto.EventoRequestDTO;
import es.upm.grise.profundizacion.eventhub.dto.EventoResponseDTO;
import es.upm.grise.profundizacion.eventhub.model.EstadoCobro;
import es.upm.grise.profundizacion.eventhub.model.Evento;
import es.upm.grise.profundizacion.eventhub.repository.EventoRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestClientException;

import java.math.BigDecimal;
import java.util.List;
import java.util.stream.Collectors;

/**
 * Además de gestionar los eventos, este servicio coordina la compra: pide el cobro al
 * microservicio de pagos, guarda el resultado y encarga el aviso al microservicio de correos.
 */
@Service
public class EventoServiceImpl implements EventoService {

    private static final Logger log = LoggerFactory.getLogger(EventoServiceImpl.class);

    private final EventoRepository eventoRepository;
    private final CompraService compraService;
    private final PagoClient pagoClient;
    private final CorreoClient correoClient;

    public EventoServiceImpl(EventoRepository eventoRepository, CompraService compraService,
                             PagoClient pagoClient, CorreoClient correoClient) {
        this.eventoRepository = eventoRepository;
        this.compraService = compraService;
        this.pagoClient = pagoClient;
        this.correoClient = correoClient;
    }

    @Override
    @Transactional
    public EventoResponseDTO crearEvento(EventoRequestDTO dto) {
        Evento evento = new Evento(dto.getNombre(), dto.getDescripcion(), dto.getPrecio(), dto.getAforoDisponible());
        Evento guardado = eventoRepository.save(evento);
        return mapToResponseDTO(guardado);
    }

    @Override
    @Transactional(readOnly = true)
    public List<EventoResponseDTO> buscarEventos(String nombre) {
        List<Evento> eventos;
        if (nombre == null || nombre.isBlank()) {
            eventos = eventoRepository.findAll();
        } else {
            eventos = eventoRepository.findByNombreContainingIgnoreCase(nombre);
        }
        return eventos.stream()
                .map(this::mapToResponseDTO)
                .collect(Collectors.toList());
    }

    /**
     * El método no es transaccional a propósito: la escritura en base de datos se delega en
     * CompraService para no mantener abierta una transacción mientras se espera a otros servicios.
     */
    @Override
    public CompraResponseDTO comprarEvento(Long id, Jwt jwt) {
        Evento evento = eventoRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Evento no encontrado con id: " + id));

        if (evento.getAforoDisponible() <= 0) {
            return new CompraResponseDTO("Aforo agotado para este evento", id, null, null, null);
        }

        // Extrae email o identificador del usuario desde el JWT
        String usuarioEmail = jwt.getClaimAsString("email");
        if (usuarioEmail == null) {
            usuarioEmail = jwt.getSubject();
        }

        // 1. El microservicio de pagos decide si el cargo se autoriza
        PagoResponse pago = solicitarCobro(id, usuarioEmail, evento.getPrecio());
        EstadoCobro estadoCobro = pago.estaAprobado() ? EstadoCobro.COBRO_OK : EstadoCobro.COBRO_NOK;

        // 2. La compra queda registrada con el resultado del cobro, haya salido bien o mal
        compraService.registrarCompra(id, usuarioEmail, estadoCobro, pago.getReferencia());

        // 3. El microservicio de correos avisa al comprador
        avisarAlComprador(new ConfirmacionCompraRequest(usuarioEmail, evento.getNombre(), evento.getPrecio(),
                estadoCobro, pago.getReferencia()));

        String mensaje = estadoCobro == EstadoCobro.COBRO_OK
                ? "Entrada comprada con éxito"
                : "Compra rechazada: " + pago.getMotivo();

        return new CompraResponseDTO(mensaje, id, usuarioEmail, estadoCobro, pago.getReferencia());
    }

    /**
     * Un microservicio de pagos caído no puede autorizar nada, así que se trata como una
     * denegación: la compra se registra igualmente como NOK y el usuario recibe su aviso.
     */
    private PagoResponse solicitarCobro(Long eventoId, String usuarioEmail, BigDecimal importe) {
        try {
            return pagoClient.cobrar(new PagoRequest(eventoId, usuarioEmail, importe));
        } catch (RestClientException ex) {
            log.error("El microservicio de pagos no respondió para el evento {}: {}", eventoId, ex.getMessage());
            return new PagoResponse(null, "DENEGADO", "El servicio de pagos no está disponible");
        }
    }

    /**
     * El correo es el último paso y no puede tumbar la compra: si falla, se registra en el log
     * y la respuesta al usuario sigue reflejando lo que se guardó en base de datos.
     */
    private void avisarAlComprador(ConfirmacionCompraRequest peticion) {
        try {
            correoClient.enviarConfirmacionCompra(peticion);
        } catch (RestClientException ex) {
            log.error("No se pudo enviar el correo a {}: {}", peticion.getDestinatario(), ex.getMessage());
        }
    }

    private EventoResponseDTO mapToResponseDTO(Evento evento) {
        return new EventoResponseDTO(
                evento.getId(),
                evento.getNombre(),
                evento.getDescripcion(),
                evento.getPrecio(),
                evento.getAforoDisponible()
        );
    }
}
