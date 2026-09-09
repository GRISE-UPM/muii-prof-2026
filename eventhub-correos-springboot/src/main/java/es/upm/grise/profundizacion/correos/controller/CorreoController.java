package es.upm.grise.profundizacion.correos.controller;

import es.upm.grise.profundizacion.correos.dto.ConfirmacionCompraRequestDTO;
import es.upm.grise.profundizacion.correos.dto.CorreoResponseDTO;
import es.upm.grise.profundizacion.correos.service.CorreoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/correos")
@Tag(name = "Correos", description = "Endpoint interno para avisar al comprador del resultado de su compra")
public class CorreoController {

    private final CorreoService correoService;

    public CorreoController(CorreoService correoService) {
        this.correoService = correoService;
    }

    @PostMapping("/confirmacion-compra")
    @Operation(summary = "Enviar el correo de una compra",
               description = "Envía por Amazon SES la confirmación o el rechazo de la compra. El texto del " +
                             "correo lo redacta este microservicio a partir del resultado del cobro.")
    public ResponseEntity<CorreoResponseDTO> enviarConfirmacionCompra(@Valid @RequestBody ConfirmacionCompraRequestDTO dto) {
        return ResponseEntity.ok(correoService.enviarConfirmacionCompra(dto));
    }
}
