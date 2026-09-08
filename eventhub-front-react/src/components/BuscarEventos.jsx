import React, { useState } from "react";
import { apiFetch } from "../api.js";
import ResultadoHttp from "./ResultadoHttp.jsx";

// GET /api/eventos/buscar — equivalente a "Buscar eventos" en Swagger (rol USER o ADMIN)
function BuscarEventos({ token }) {
  const [nombre, setNombre] = useState("");
  const [resultado, setResultado] = useState(null);

  const handleSubmit = async (event) => {
    event.preventDefault();
    const query = nombre ? `?nombre=${encodeURIComponent(nombre)}` : "";
    setResultado(await apiFetch(`/api/eventos/buscar${query}`, { token }));
  };

  return (
    <div className="api-panel">
      <h3>Buscar eventos</h3>
      <p className="ruta">GET /api/eventos/buscar (requiere rol USER o ADMIN)</p>
      <form onSubmit={handleSubmit}>
        <label>
          Nombre (vacío = todos)
          <input value={nombre} onChange={(e) => setNombre(e.target.value)} />
        </label>
        <button className="btn btn-principal" type="submit">Buscar</button>
      </form>
      <ResultadoHttp resultado={resultado} />
    </div>
  );
}

export default BuscarEventos;
