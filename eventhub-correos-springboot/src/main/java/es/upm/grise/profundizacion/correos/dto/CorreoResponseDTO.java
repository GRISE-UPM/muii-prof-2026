package es.upm.grise.profundizacion.correos.dto;

public class CorreoResponseDTO {

    private String destinatario;
    private String asunto;

    public CorreoResponseDTO() {}

    public CorreoResponseDTO(String destinatario, String asunto) {
        this.destinatario = destinatario;
        this.asunto = asunto;
    }

    public String getDestinatario() { return destinatario; }
    public void setDestinatario(String destinatario) { this.destinatario = destinatario; }

    public String getAsunto() { return asunto; }
    public void setAsunto(String asunto) { this.asunto = asunto; }
}
