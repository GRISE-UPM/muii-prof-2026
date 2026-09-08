import React, { useCallback, useEffect, useState } from "react";
// Hook principal de react-oidc-context para gestionar sesión y métodos OIDC
import { useAuth } from "react-oidc-context";
import CrearEvento from "./components/CrearEvento.jsx";
import BuscarEventos from "./components/BuscarEventos.jsx";
import ComprarEvento from "./components/ComprarEvento.jsx";

function App() {
  const auth = useAuth();
  const [pestana, setPestana] = useState("buscar");

  // Renueva access/id token con el refresh_token de Cognito (flujo code + openid).
  // Cognito no usa el scope OIDC offline_access; signinSilent llama a /oauth2/token
  // con grant_type=refresh_token si auth.user.refresh_token está presente.
  const handleRefreshToken = useCallback(async () => {
    try {
      // Petición silenciosa a Cognito sin redirigir al usuario
      await auth.signinSilent();
      console.log("Tokens renovados con éxito mediante Refresh Token");
    } catch (error) {
      console.error("Error al renovar el token:", error);
    }
  }, [auth]);

  // oidc-client-ts dispara accessTokenExpiring antes de la caducidad del access token.
  useEffect(() => {
    return auth.events.addAccessTokenExpiring(() => {
      void handleRefreshToken();
    });
  }, [auth.events, handleRefreshToken]);

  // Cierre de sesión federado completo (en la aplicación y en Cognito)
  const handleSignOut = async () => {
    const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID;
    const cognitoDomain = import.meta.env.VITE_COGNITO_DOMAIN;
    const logoutUri = window.location.origin; // URL base de la app tras el logout

    // Destruye la sesión local en el cliente
    await auth.removeUser();

    // Redirige a Cognito para cerrar sesión en el servidor
    window.location.href = `${cognitoDomain}/logout?client_id=${clientId}&logout_uri=${encodeURIComponent(logoutUri)}`;
  };

  if (auth.isLoading) {
    return <div>Cargando estado de autenticación...</div>;
  }

  if (auth.error) {
    return <div>Error de autenticación: {auth.error.message}</div>;
  }

  if (auth.isAuthenticated) {
    const token = auth.user?.access_token;
    const pestanas = {
      crear: <CrearEvento token={token} />,
      buscar: <BuscarEventos token={token} />,
      comprar: <ComprarEvento token={token} />,
    };

    return (
      <div>
        {/* Información de identidad obtenida del ID Token */}
        <h2>Bienvenido, {auth.user?.profile.email}</h2>

        <details>
          <summary>Ver Tokens</summary>
          {/* ID Token: Datos del perfil de usuario */}
          <pre>ID Token: {auth.user?.id_token}</pre>
          {/* Access Token: Se envía en la cabecera Authorization: Bearer a la API */}
          <pre>Access Token: {auth.user?.access_token}</pre>
          {/* Refresh Token: Credencial opaca para pedir nuevos tokens */}
          <pre>Refresh Token: {auth.user?.refresh_token}</pre>
        </details>

        <br />
        <button onClick={handleRefreshToken}>Refresh Token</button>
        {" "}
        <button onClick={handleSignOut}>Sign out</button>

        <hr />
        <nav className="nav-api">
          <button type="button" className={`btn ${pestana === "crear" ? "btn-activo" : ""}`} onClick={() => setPestana("crear")}>Crear evento</button>
          <button type="button" className={`btn ${pestana === "buscar" ? "btn-activo" : ""}`} onClick={() => setPestana("buscar")}>Buscar eventos</button>
          <button type="button" className={`btn ${pestana === "comprar" ? "btn-activo" : ""}`} onClick={() => setPestana("comprar")}>Comprar entrada</button>
        </nav>
        {pestanas[pestana]}
      </div>
    );
  }

  return (
    <div>
      {/* Redirige a la pantalla de login en Cognito (Hosted UI) */}
      <button onClick={() => auth.signinRedirect()}>Sign in</button>
    </div>
  );
}

export default App;