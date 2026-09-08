package es.upm.grise.profundizacion.eventhub;

import tools.jackson.databind.ObjectMapper;
import es.upm.grise.profundizacion.eventhub.dto.CompraResponseDTO;
import es.upm.grise.profundizacion.eventhub.dto.EventoRequestDTO;
import es.upm.grise.profundizacion.eventhub.dto.EventoResponseDTO;
import es.upm.grise.profundizacion.eventhub.service.EventoService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.math.BigDecimal;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class EventoControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

        @MockitoBean
    private EventoService eventoService;

    @Test
    @DisplayName("POST /api/eventos - Crear Evento con rol ADMIN responde 201 Created")
    void testCrearEvento_ConRolAdmin() throws Exception {
        EventoRequestDTO requestDTO = new EventoRequestDTO("Festival de Cine", "Muestra de cine independiente", new BigDecimal("15.00"), 200);
        EventoResponseDTO responseDTO = new EventoResponseDTO(1L, "Festival de Cine", "Muestra de cine independiente", new BigDecimal("15.00"), 200);

        when(eventoService.crearEvento(any(EventoRequestDTO.class))).thenReturn(responseDTO);

        SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor jwtAdmin = jwt()
                .jwt(builder -> builder.claim("cognito:groups", List.of("ADMIN")))
                .authorities(new SimpleGrantedAuthority("ROLE_ADMIN"));

        mockMvc.perform(post("/api/eventos")
                        .with(jwtAdmin)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(requestDTO)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(1L))
                .andExpect(jsonPath("$.nombre").value("Festival de Cine"))
                .andExpect(jsonPath("$.aforoDisponible").value(200));
    }

    @Test
    @DisplayName("GET /api/eventos/buscar - Buscar Eventos con rol USER responde 200 OK")
    void testBuscarEventos_ConRolUser() throws Exception {
        EventoResponseDTO evento1 = new EventoResponseDTO(1L, "Concierto Rock", "Rock en vivo", new BigDecimal("45.00"), 100);
        when(eventoService.buscarEventos("Rock")).thenReturn(List.of(evento1));

        SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor jwtUser = jwt()
                .jwt(builder -> builder.claim("cognito:groups", List.of("USER")))
                .authorities(new SimpleGrantedAuthority("ROLE_USER"));

        mockMvc.perform(get("/api/eventos/buscar")
                        .param("nombre", "Rock")
                        .with(jwtUser))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(1L))
                .andExpect(jsonPath("$[0].nombre").value("Concierto Rock"));
    }

    @Test
    @DisplayName("POST /api/eventos/{id}/comprar - Comprar entrada con rol USER guarda compra y responde 200 OK")
    void testComprarEvento_Exitoso() throws Exception {
        CompraResponseDTO compraResponse = new CompraResponseDTO("Entrada comprada con éxito", 1L, "usuario@upm.es");

        when(eventoService.comprarEvento(eq(1L), any())).thenReturn(compraResponse);

        SecurityMockMvcRequestPostProcessors.JwtRequestPostProcessor jwtUser = jwt()
                .jwt(builder -> builder.claim("cognito:groups", List.of("USER"))
                        .claim("email", "usuario@upm.es"))
                .authorities(new SimpleGrantedAuthority("ROLE_USER"));

        mockMvc.perform(post("/api/eventos/1/comprar")
                        .with(jwtUser))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.mensaje").value("Entrada comprada con éxito"))
                .andExpect(jsonPath("$.eventoId").value(1L))
                .andExpect(jsonPath("$.usuarioEmail").value("usuario@upm.es"));
    }
}
