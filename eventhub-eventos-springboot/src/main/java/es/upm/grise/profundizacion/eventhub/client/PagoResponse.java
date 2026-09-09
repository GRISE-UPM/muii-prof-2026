package es.upm.grise.profundizacion.eventhub.client;

/**
 * Respuesta de POST /api/pagos.
 *
 * El estado viaja como texto y no como enum para que un valor nuevo en el microservicio de pagos
 * no rompa la deserialización aquí: lo que no sea APROBADO se trata como cobro no realizado.
 */
public class PagoResponse {

    private String referencia;
    private String estado;
    private String motivo;

    public PagoResponse() {}

    public PagoResponse(String referencia, String estado, String motivo) {
        this.referencia = referencia;
        this.estado = estado;
        this.motivo = motivo;
    }

    public boolean estaAprobado() {
        return "APROBADO".equals(estado);
    }

    public String getReferencia() { return referencia; }
    public void setReferencia(String referencia) { this.referencia = referencia; }

    public String getEstado() { return estado; }
    public void setEstado(String estado) { this.estado = estado; }

    public String getMotivo() { return motivo; }
    public void setMotivo(String motivo) { this.motivo = motivo; }
}
