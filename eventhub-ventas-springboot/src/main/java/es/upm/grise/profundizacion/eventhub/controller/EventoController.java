package es.upm.grise.profundizacion.eventhub.controller;

import es.upm.grise.profundizacion.eventhub.dto.CompraResponseDTO;
import es.upm.grise.profundizacion.eventhub.dto.EventoRequestDTO;
import es.upm.grise.profundizacion.eventhub.dto.EventoResponseDTO;
import es.upm.grise.profundizacion.eventhub.service.EventoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/eventos")
@Tag(name = "Eventos", description = "Endpoints para la gestión, búsqueda y compra de entradas a eventos")
@CrossOrigin(origins = "*")
public class EventoController {

    private final EventoService eventoService;

    public EventoController(EventoService eventoService) {
        this.eventoService = eventoService;
    }

    @PostMapping
    @Operation(summary = "Introducir evento", description = "Permite crear un nuevo evento. Requiere el rol ADMIN.")
    public ResponseEntity<EventoResponseDTO> crearEvento(@Valid @RequestBody EventoRequestDTO dto) {
        EventoResponseDTO respuesta = eventoService.crearEvento(dto);
        return ResponseEntity.status(HttpStatus.CREATED).body(respuesta);
    }

    @GetMapping("/buscar")
    @Operation(summary = "Buscar eventos", description = "Permite buscar eventos por nombre o listar todos. Requiere rol USER o ADMIN.")
    public ResponseEntity<List<EventoResponseDTO>> buscarEventos(@RequestParam(required = false, defaultValue = "") String nombre) {
        List<EventoResponseDTO> respuesta = eventoService.buscarEventos(nombre);
        return ResponseEntity.ok(respuesta);
    }

    @PostMapping("/{id}/comprar")
    @Operation(summary = "Comprar entrada para evento", description = "Reduce el aforo y registra una compra en BD. Requiere el rol USER.")
    public ResponseEntity<CompraResponseDTO> comprarEvento(@PathVariable Long id, @AuthenticationPrincipal Jwt jwt) {
        CompraResponseDTO respuesta = eventoService.comprarEvento(id, jwt);
        if ("Aforo agotado para este evento".equals(respuesta.getMensaje())) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(respuesta);
        }
        return ResponseEntity.ok(respuesta);
    }
}
