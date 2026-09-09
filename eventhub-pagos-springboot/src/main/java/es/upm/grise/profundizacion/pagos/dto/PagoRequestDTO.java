package es.upm.grise.profundizacion.pagos.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

import java.math.BigDecimal;

public class PagoRequestDTO {

    @NotNull(message = "El identificador del evento es obligatorio")
    private Long eventoId;

    @NotBlank(message = "El email del usuario es obligatorio")
    @Email(message = "El email del usuario no es válido")
    private String usuarioEmail;

    @NotNull(message = "El importe es obligatorio")
    @Positive(message = "El importe debe ser mayor que cero")
    private BigDecimal importe;

    public PagoRequestDTO() {}

    public Long getEventoId() { return eventoId; }
    public void setEventoId(Long eventoId) { this.eventoId = eventoId; }

    public String getUsuarioEmail() { return usuarioEmail; }
    public void setUsuarioEmail(String usuarioEmail) { this.usuarioEmail = usuarioEmail; }

    public BigDecimal getImporte() { return importe; }
    public void setImporte(BigDecimal importe) { this.importe = importe; }
}
