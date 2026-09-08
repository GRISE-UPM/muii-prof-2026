package es.upm.grise.profundizacion.eventhub.repository;

import es.upm.grise.profundizacion.eventhub.model.Evento;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface EventoRepository extends JpaRepository<Evento, Long> {
    List<Evento> findByNombreContainingIgnoreCase(String nombre);
}
