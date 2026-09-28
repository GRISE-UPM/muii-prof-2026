import React, { useState } from "react";
import CrearEvento from "./components/CrearEvento.jsx";
import BuscarEventos from "./components/BuscarEventos.jsx";
import ComprarEvento from "./components/ComprarEvento.jsx";

function App() {
  const [pestana, setPestana] = useState("buscar");

  const pestanas = {
    crear: <CrearEvento />,
    buscar: <BuscarEventos />,
    comprar: <ComprarEvento />,
  };

  return (
    <div>
      <h2>Event Hub</h2>
      <nav className="nav-api">
        <button type="button" className={`btn ${pestana === "crear" ? "btn-activo" : ""}`} onClick={() => setPestana("crear")}>Crear evento</button>
        <button type="button" className={`btn ${pestana === "buscar" ? "btn-activo" : ""}`} onClick={() => setPestana("buscar")}>Buscar eventos</button>
        <button type="button" className={`btn ${pestana === "comprar" ? "btn-activo" : ""}`} onClick={() => setPestana("comprar")}>Comprar entrada</button>
      </nav>
      {pestanas[pestana]}
    </div>
  );
}

export default App;
