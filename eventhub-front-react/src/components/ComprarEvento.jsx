import React, { useState } from "react";
import { apiFetch } from "../api.js";
import ResultadoHttp from "./ResultadoHttp.jsx";

// POST /api/eventos/{id}/comprar — equivalente a "Comprar entrada" en Swagger (rol USER)
function ComprarEvento({ token }) {
  const [id, setId] = useState("1");
  const [resultado, setResultado] = useState(null);

  const handleSubmit = async (event) => {
    event.preventDefault();
    setResultado(await apiFetch(`/api/eventos/${id}/comprar`, {
      token,
      method: "POST",
    }));
  };

  return (
    <div className="api-panel">
      <h3>Comprar entrada</h3>
      <p className="ruta">POST /api/eventos/{"{id}"}/comprar (requiere rol USER)</p>
      <form onSubmit={handleSubmit}>
        <label>
          ID del evento
          <input type="number" min="1" value={id} onChange={(e) => setId(e.target.value)} required />
        </label>
        <button className="btn btn-principal" type="submit">Comprar</button>
      </form>
      <ResultadoHttp resultado={resultado} />
    </div>
  );
}

export default ComprarEvento;
