package es.upm.grise.profundizacion.eventhub.service;

import es.upm.grise.profundizacion.eventhub.dto.CompraResponseDTO;
import es.upm.grise.profundizacion.eventhub.dto.EventoRequestDTO;
import es.upm.grise.profundizacion.eventhub.dto.EventoResponseDTO;

import java.util.List;

public interface EventoService {
    EventoResponseDTO crearEvento(EventoRequestDTO dto);
    List<EventoResponseDTO> buscarEventos(String nombre);
    CompraResponseDTO comprarEvento(Long id, String email);
}
