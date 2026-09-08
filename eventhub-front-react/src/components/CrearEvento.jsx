import React, { useState } from "react";
import { apiFetch } from "../api.js";
import ResultadoHttp from "./ResultadoHttp.jsx";

// POST /api/eventos — equivalente a "Introducir evento" en Swagger
function CrearEvento() {
  const [nombre, setNombre] = useState("");
  const [descripcion, setDescripcion] = useState("");
  const [precio, setPrecio] = useState("10");
  const [aforoDisponible, setAforoDisponible] = useState("100");
  const [resultado, setResultado] = useState(null);

  const handleSubmit = async (event) => {
    event.preventDefault();
    setResultado(await apiFetch("/api/eventos", {
      method: "POST",
      body: {
        nombre,
        descripcion,
        precio: Number(precio),
        aforoDisponible: Number(aforoDisponible),
      },
    }));
  };

  return (
    <div className="api-panel">
      <h3>Crear evento</h3>
      <p className="ruta">POST /api/eventos</p>
      <form onSubmit={handleSubmit}>
        <label>
          Nombre
          <input value={nombre} onChange={(e) => setNombre(e.target.value)} required />
        </label>
        <label>
          Descripción
          <input value={descripcion} onChange={(e) => setDescripcion(e.target.value)} />
        </label>
        <label>
          Precio
          <input type="number" min="0" step="0.01" value={precio} onChange={(e) => setPrecio(e.target.value)} required />
        </label>
        <label>
          Aforo
          <input type="number" min="1" value={aforoDisponible} onChange={(e) => setAforoDisponible(e.target.value)} required />
        </label>
        <button className="btn btn-principal" type="submit">Crear</button>
      </form>
      <ResultadoHttp resultado={resultado} />
    </div>
  );
}

export default CrearEvento;
