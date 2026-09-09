package es.upm.grise.profundizacion.eventhub.model;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
@Table(name = "evento")
public class Evento {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String nombre;

    private String descripcion;

    @Column(nullable = false)
    private BigDecimal precio;

    @Column(name = "aforo_disponible", nullable = false)
    private Integer aforoDisponible;

    public Evento() {}

    public Evento(String nombre, String descripcion, BigDecimal precio, Integer aforoDisponible) {
        this.nombre = nombre;
        this.descripcion = descripcion;
        this.precio = precio;
        this.aforoDisponible = aforoDisponible;
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getNombre() { return nombre; }
    public void setNombre(String nombre) { this.nombre = nombre; }

    public String getDescripcion() { return descripcion; }
    public void setDescripcion(String descripcion) { this.descripcion = descripcion; }

    public BigDecimal getPrecio() { return precio; }
    public void setPrecio(BigDecimal precio) { this.precio = precio; }

    public Integer getAforoDisponible() { return aforoDisponible; }
    public void setAforoDisponible(Integer aforoDisponible) { this.aforoDisponible = aforoDisponible; }
}
