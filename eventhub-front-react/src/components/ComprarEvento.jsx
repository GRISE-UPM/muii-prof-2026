import React, { useState } from "react";
import { apiFetch } from "../api.js";
import ResultadoHttp from "./ResultadoHttp.jsx";

// POST /api/eventos/{id}/comprar — equivalente a "Comprar entrada" en Swagger
function ComprarEvento() {
  const [id, setId] = useState("1");
  const [email, setEmail] = useState("");
  const [resultado, setResultado] = useState(null);

  const handleSubmit = async (event) => {
    event.preventDefault();
    const query = `?email=${encodeURIComponent(email)}`;
    setResultado(await apiFetch(`/api/eventos/${id}/comprar${query}`, {
      method: "POST",
    }));
  };

  return (
    <div className="api-panel">
      <h3>Comprar entrada</h3>
      <p className="ruta">POST /api/eventos/{"{id}"}/comprar</p>
      <form onSubmit={handleSubmit}>
        <label>
          ID del evento
          <input type="number" min="1" value={id} onChange={(e) => setId(e.target.value)} required />
        </label>
        <label>
          Email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <button className="btn btn-principal" type="submit">Comprar</button>
      </form>
      <ResultadoHttp resultado={resultado} />
    </div>
  );
}

export default ComprarEvento;
