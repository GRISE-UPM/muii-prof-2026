package es.upm.grise.profundizacion.eventhub.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

public class EventoRequestDTO {

    @NotBlank(message = "El nombre es obligatorio")
    private String nombre;

    private String descripcion;

    @NotNull(message = "El precio es obligatorio")
    @Min(value = 0, message = "El precio debe ser mayor o igual a 0")
    private BigDecimal precio;

    @NotNull(message = "El aforo es obligatorio")
    @Min(value = 1, message = "El aforo debe ser al menos 1")
    private Integer aforoDisponible;

    public EventoRequestDTO() {}

    public String getNombre() { return nombre; }
    public void setNombre(String nombre) { this.nombre = nombre; }

    public String getDescripcion() { return descripcion; }
    public void setDescripcion(String descripcion) { this.descripcion = descripcion; }

    public BigDecimal getPrecio() { return precio; }
    public void setPrecio(BigDecimal precio) { this.precio = precio; }

    public Integer getAforoDisponible() { return aforoDisponible; }
    public void setAforoDisponible(Integer aforoDisponible) { this.aforoDisponible = aforoDisponible; }
}
