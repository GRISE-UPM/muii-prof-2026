package es.upm.grise.profundizacion.eventhub.dto;

import java.math.BigDecimal;

public class EventoResponseDTO {

    private Long id;
    private String nombre;
    private String descripcion;
    private BigDecimal precio;
    private Integer aforoDisponible;

    public EventoResponseDTO() {}

    public EventoResponseDTO(Long id, String nombre, String descripcion, BigDecimal precio, Integer aforoDisponible) {
        this.id = id;
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
