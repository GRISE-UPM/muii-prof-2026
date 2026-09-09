package es.upm.grise.profundizacion.eventhub.dto;

import es.upm.grise.profundizacion.eventhub.model.EstadoCobro;

public class CompraResponseDTO {

    private String mensaje;
    private Long eventoId;
    private String usuarioEmail;
    private EstadoCobro estadoCobro;
    private String referenciaPago;

    public CompraResponseDTO() {}

    public CompraResponseDTO(String mensaje, Long eventoId, String usuarioEmail,
                             EstadoCobro estadoCobro, String referenciaPago) {
        this.mensaje = mensaje;
        this.eventoId = eventoId;
        this.usuarioEmail = usuarioEmail;
        this.estadoCobro = estadoCobro;
        this.referenciaPago = referenciaPago;
    }

    public String getMensaje() { return mensaje; }
    public void setMensaje(String mensaje) { this.mensaje = mensaje; }

    public Long getEventoId() { return eventoId; }
    public void setEventoId(Long eventoId) { this.eventoId = eventoId; }

    public String getUsuarioEmail() { return usuarioEmail; }
    public void setUsuarioEmail(String usuarioEmail) { this.usuarioEmail = usuarioEmail; }

    public EstadoCobro getEstadoCobro() { return estadoCobro; }
    public void setEstadoCobro(EstadoCobro estadoCobro) { this.estadoCobro = estadoCobro; }

    public String getReferenciaPago() { return referenciaPago; }
    public void setReferenciaPago(String referenciaPago) { this.referenciaPago = referenciaPago; }
}
