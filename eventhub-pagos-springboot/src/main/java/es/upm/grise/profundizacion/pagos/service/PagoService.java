package es.upm.grise.profundizacion.pagos.service;

import es.upm.grise.profundizacion.pagos.dto.PagoRequestDTO;
import es.upm.grise.profundizacion.pagos.dto.PagoResponseDTO;

public interface PagoService {

    PagoResponseDTO cobrar(PagoRequestDTO dto);
}
