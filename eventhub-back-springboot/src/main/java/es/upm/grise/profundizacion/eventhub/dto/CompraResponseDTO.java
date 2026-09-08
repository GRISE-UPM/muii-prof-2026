package es.upm.grise.profundizacion.eventhub.dto;

public class CompraResponseDTO {

    private String mensaje;
    private Long eventoId;
    private String usuarioEmail;

    public CompraResponseDTO() {}

    public CompraResponseDTO(String mensaje, Long eventoId, String usuarioEmail) {
        this.mensaje = mensaje;
        this.eventoId = eventoId;
        this.usuarioEmail = usuarioEmail;
    }

    public String getMensaje() { return mensaje; }
    public void setMensaje(String mensaje) { this.mensaje = mensaje; }

    public Long getEventoId() { return eventoId; }
    public void setEventoId(Long eventoId) { this.eventoId = eventoId; }

    public String getUsuarioEmail() { return usuarioEmail; }
    public void setUsuarioEmail(String usuarioEmail) { this.usuarioEmail = usuarioEmail; }
}
