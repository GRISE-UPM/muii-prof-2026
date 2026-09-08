package es.upm.grise.profundizacion.eventhub.model;

import jakarta.persistence.*;
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

    public Compra() {}

    public Compra(Evento evento, String usuarioEmail, LocalDateTime fechaCompra) {
        this.evento = evento;
        this.usuarioEmail = usuarioEmail;
        this.fechaCompra = fechaCompra;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Evento getEvento() { return evento; }
    public void setEvento(Evento evento) { this.evento = evento; }

    public String getUsuarioEmail() { return usuarioEmail; }
    public void setUsuarioEmail(String usuarioEmail) { this.usuarioEmail = usuarioEmail; }

    public LocalDateTime getFechaCompra() { return fechaCompra; }
    public void setFechaCompra(LocalDateTime fechaCompra) { this.fechaCompra = fechaCompra; }
}
