import React from "react";

function ResultadoHttp({ resultado }) {
  if (!resultado) {
    return null;
  }

  const clase = resultado.ok ? "http-ok" : "http-err";
  const codigo = resultado.status ? `HTTP ${resultado.status}` : "Sin HTTP";

  return (
    <div className={`http-resultado ${clase}`}>
      <p>
        <strong>{codigo}</strong>
        {" — "}
        {resultado.descripcion}
      </p>
      <pre>{JSON.stringify(resultado.data, null, 2)}</pre>
    </div>
  );
}

export default ResultadoHttp;
