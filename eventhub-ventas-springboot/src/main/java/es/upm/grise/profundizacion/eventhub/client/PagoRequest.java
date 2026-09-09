package es.upm.grise.profundizacion.eventhub.client;

import java.math.BigDecimal;

/**
 * Cuerpo que espera POST /api/pagos del microservicio de pagos.
 */
public class PagoRequest {

    private Long eventoId;
    private String usuarioEmail;
    private BigDecimal importe;

    public PagoRequest() {}

    public PagoRequest(Long eventoId, String usuarioEmail, BigDecimal importe) {
        this.eventoId = eventoId;
        this.usuarioEmail = usuarioEmail;
        this.importe = importe;
    }

    public Long getEventoId() { return eventoId; }
    public void setEventoId(Long eventoId) { this.eventoId = eventoId; }

    public String getUsuarioEmail() { return usuarioEmail; }
    public void setUsuarioEmail(String usuarioEmail) { this.usuarioEmail = usuarioEmail; }

    public BigDecimal getImporte() { return importe; }
    public void setImporte(BigDecimal importe) { this.importe = importe; }
}
