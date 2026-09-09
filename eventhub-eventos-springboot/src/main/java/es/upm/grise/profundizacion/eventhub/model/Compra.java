package es.upm.grise.profundizacion.eventhub.model;

import jakarta.persistence.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "compra")
public class Compra {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "evento_id", nullable = false)
    private Evento evento;

    @Column(name = "usuario_email", nullable = false)
    private String usuarioEmail;

    @Column(name = "fecha_compra", nullable = false)
    private LocalDateTime fechaCompra;

    @Column(nullable = false)
    private BigDecimal importe;

    // Se guarda el nombre del enum, no su posición: así el valor sigue siendo legible en la
    // base de datos y añadir estados nuevos no cambia el significado de las filas antiguas.
    @Enumerated(EnumType.STRING)
    @Column(name = "estado_cobro", nullable = false)
    private EstadoCobro estadoCobro;

    // Referencia que devuelve el microservicio de pagos. Es nula si no llegó a responder.
    @Column(name = "referencia_pago")
    private String referenciaPago;

    public Compra() {}

    public Compra(Evento evento, String usuarioEmail, LocalDateTime fechaCompra, BigDecimal importe,
                  EstadoCobro estadoCobro, String referenciaPago) {
        this.evento = evento;
        this.usuarioEmail = usuarioEmail;
        this.fechaCompra = fechaCompra;
        this.importe = importe;
        this.estadoCobro = estadoCobro;
        this.referenciaPago = referenciaPago;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Evento getEvento() { return evento; }
    public void setEvento(Evento evento) { this.evento = evento; }

    public String getUsuarioEmail() { return usuarioEmail; }
    public void setUsuarioEmail(String usuarioEmail) { this.usuarioEmail = usuarioEmail; }

    public LocalDateTime getFechaCompra() { return fechaCompra; }
    public void setFechaCompra(LocalDateTime fechaCompra) { this.fechaCompra = fechaCompra; }

    public BigDecimal getImporte() { return importe; }
    public void setImporte(BigDecimal importe) { this.importe = importe; }

    public EstadoCobro getEstadoCobro() { return estadoCobro; }
    public void setEstadoCobro(EstadoCobro estadoCobro) { this.estadoCobro = estadoCobro; }

    public String getReferenciaPago() { return referenciaPago; }
    public void setReferenciaPago(String referenciaPago) { this.referenciaPago = referenciaPago; }
}
