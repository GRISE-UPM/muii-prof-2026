package es.upm.grise.profundizacion.eventhub.service;

import es.upm.grise.profundizacion.eventhub.model.Compra;
import es.upm.grise.profundizacion.eventhub.model.EstadoCobro;

public interface CompraService {

    Compra registrarCompra(Long eventoId, String usuarioEmail, EstadoCobro estadoCobro, String referenciaPago);
}
