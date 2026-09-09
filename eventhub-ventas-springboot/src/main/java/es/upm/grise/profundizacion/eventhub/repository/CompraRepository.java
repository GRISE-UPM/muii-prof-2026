package es.upm.grise.profundizacion.eventhub.repository;

import es.upm.grise.profundizacion.eventhub.model.Compra;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface CompraRepository extends JpaRepository<Compra, Long> {
    List<Compra> findByUsuarioEmail(String usuarioEmail);
}
