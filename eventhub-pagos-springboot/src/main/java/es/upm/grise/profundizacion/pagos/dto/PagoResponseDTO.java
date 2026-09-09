package es.upm.grise.profundizacion.pagos.dto;

import es.upm.grise.profundizacion.pagos.model.EstadoPago;

public class PagoResponseDTO {

    private String referencia;
    private EstadoPago estado;
    private String motivo;

    public PagoResponseDTO() {}

    public PagoResponseDTO(String referencia, EstadoPago estado, String motivo) {
        this.referencia = referencia;
        this.estado = estado;
        this.motivo = motivo;
    }

    public String getReferencia() { return referencia; }
    public void setReferencia(String referencia) { this.referencia = referencia; }

    public EstadoPago getEstado() { return estado; }
    public void setEstado(EstadoPago estado) { this.estado = estado; }

    public String getMotivo() { return motivo; }
    public void setMotivo(String motivo) { this.motivo = motivo; }
}
