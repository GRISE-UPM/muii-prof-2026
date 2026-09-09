package es.upm.grise.profundizacion.pagos.controller;

import es.upm.grise.profundizacion.pagos.dto.PagoRequestDTO;
import es.upm.grise.profundizacion.pagos.dto.PagoResponseDTO;
import es.upm.grise.profundizacion.pagos.service.PagoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/pagos")
@Tag(name = "Pagos", description = "Endpoint interno para solicitar el cobro de una compra")
public class PagoController {

    private final PagoService pagoService;

    public PagoController(PagoService pagoService) {
        this.pagoService = pagoService;
    }

    @PostMapping
    @Operation(summary = "Solicitar un cobro",
               description = "Devuelve 200 tanto si el cobro se aprueba como si se deniega: la denegación es una " +
                             "respuesta de negocio, no un error. El resultado viaja en el campo 'estado'.")
    public ResponseEntity<PagoResponseDTO> cobrar(@Valid @RequestBody PagoRequestDTO dto) {
        return ResponseEntity.ok(pagoService.cobrar(dto));
    }
}
