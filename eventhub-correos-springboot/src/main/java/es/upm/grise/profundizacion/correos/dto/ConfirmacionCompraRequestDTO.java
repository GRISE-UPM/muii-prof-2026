package es.upm.grise.profundizacion.correos.dto;

import es.upm.grise.profundizacion.correos.model.ResultadoCobro;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.math.BigDecimal;

public class ConfirmacionCompraRequestDTO {

    @NotBlank(message = "El destinatario es obligatorio")
    @Email(message = "El destinatario no es un email válido")
    private String destinatario;

    @NotBlank(message = "El nombre del evento es obligatorio")
    private String evento;

    @NotNull(message = "El importe es obligatorio")
    private BigDecimal importe;

    @NotNull(message = "El resultado del cobro es obligatorio")
    private ResultadoCobro resultadoCobro;

    private String referenciaPago;

    public ConfirmacionCompraRequestDTO() {}

    public ConfirmacionCompraRequestDTO(String destinatario, String evento, BigDecimal importe,
                                        ResultadoCobro resultadoCobro, String referenciaPago) {
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

    public ResultadoCobro getResultadoCobro() { return resultadoCobro; }
    public void setResultadoCobro(ResultadoCobro resultadoCobro) { this.resultadoCobro = resultadoCobro; }

    public String getReferenciaPago() { return referenciaPago; }
    public void setReferenciaPago(String referenciaPago) { this.referenciaPago = referenciaPago; }
}
