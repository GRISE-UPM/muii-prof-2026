package es.upm.grise.profundizacion.correos.service;

import es.upm.grise.profundizacion.correos.dto.ConfirmacionCompraRequestDTO;
import es.upm.grise.profundizacion.correos.dto.CorreoResponseDTO;

public interface CorreoService {

    CorreoResponseDTO enviarConfirmacionCompra(ConfirmacionCompraRequestDTO dto);
}
