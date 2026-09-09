package es.upm.grise.profundizacion.eventhub.service;

import es.upm.grise.profundizacion.eventhub.dto.CompraResponseDTO;
import es.upm.grise.profundizacion.eventhub.dto.EventoRequestDTO;
import es.upm.grise.profundizacion.eventhub.dto.EventoResponseDTO;
import es.upm.grise.profundizacion.eventhub.model.Compra;
import es.upm.grise.profundizacion.eventhub.model.Evento;
import es.upm.grise.profundizacion.eventhub.repository.CompraRepository;
import es.upm.grise.profundizacion.eventhub.repository.EventoRepository;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.stream.Collectors;

@Service
public class EventoService {
    private final EventoRepository eventoRepository;
    private final CompraRepository compraRepository;

    public EventoService(EventoRepository eventoRepository, CompraRepository compraRepository) {
        this.eventoRepository = eventoRepository;
        this.compraRepository = compraRepository;
    }

    @Transactional
    public EventoResponseDTO crearEvento(EventoRequestDTO dto) {
        Evento evento = new Evento(dto.getNombre(), dto.getDescripcion(), dto.getPrecio(), dto.getAforoDisponible());
        Evento guardado = eventoRepository.save(evento);
        return mapToResponseDTO(guardado);
    }

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

    @Transactional
    public CompraResponseDTO comprarEvento(Long id, Jwt jwt) {
        Evento evento = eventoRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Evento no encontrado con id: " + id));

        if (evento.getAforoDisponible() <= 0) {
            return new CompraResponseDTO("Aforo agotado para este evento", id, null);
        }

        // Reduce el aforo
        evento.setAforoDisponible(evento.getAforoDisponible() - 1);
        eventoRepository.save(evento);

        // Extrae email o identificador del usuario desde el JWT
        String userEmail = jwt.getClaimAsString("email");
        if (userEmail == null) {
            userEmail = jwt.getSubject();
        }

        // Registra y persiste la entidad Compra
        Compra compra = new Compra(evento, userEmail, LocalDateTime.now());
        compraRepository.save(compra);

        return new CompraResponseDTO("Entrada comprada con éxito", id, userEmail);
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
