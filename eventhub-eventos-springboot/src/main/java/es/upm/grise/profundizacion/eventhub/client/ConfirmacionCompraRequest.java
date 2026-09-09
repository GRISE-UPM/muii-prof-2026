package es.upm.grise.profundizacion.eventhub.client;

import es.upm.grise.profundizacion.eventhub.model.EstadoCobro;

import java.math.BigDecimal;

/**
 * Cuerpo que espera POST /api/correos/confirmacion-compra del microservicio de correos.
 */
public class ConfirmacionCompraRequest {

    private String destinatario;
    private String evento;
    private BigDecimal importe;
    private EstadoCobro resultadoCobro;
    private String referenciaPago;

    public ConfirmacionCompraRequest() {}

    public ConfirmacionCompraRequest(String destinatario, String evento, BigDecimal importe,
                                     EstadoCobro resultadoCobro, String referenciaPago) {
        this.destinatario = destinatario;
        this.evento = evento;
        this.importe = importe;
        this.resultadoCobro = resultadoCobro;
        this.referenciaPago = referenciaPago;
    }

    public String getDestinatario() { return destinatario; }
    public void setDestinatario(String destinatario) { this.destinatario = destinatario; }

    public String getEvento() { return evento; }
    public void setEvento(String evento) { this.evento = evento; }

    public BigDecimal getImporte() { return importe; }
    public void setImporte(BigDecimal importe) { this.importe = importe; }

    public EstadoCobro getResultadoCobro() { return resultadoCobro; }
    public void setResultadoCobro(EstadoCobro resultadoCobro) { this.resultadoCobro = resultadoCobro; }

    public String getReferenciaPago() { return referenciaPago; }
    public void setReferenciaPago(String referenciaPago) { this.referenciaPago = referenciaPago; }
}
