import React from "react";
import ReactDOM from "react-dom/client";

// Hook que gestiona la autenticación
import { AuthProvider } from "react-oidc-context";

// Sirve para almacenar los tokens de autenticación en el 
// localStorage. Esto permitirá que la autenticación persista
// entre cierres del navegador. En teoría habría esta dependencia
// en package.json. Sin embargo, oidc-client-ts es una dependencia
// de react-oidc-context, por lo que se descarga transitivamente. 
// Esto hace que no nos tengamos que preocupar por la versión.
import { WebStorageStateStore } from "oidc-client-ts";
import App from "./App.jsx";
import "./styles.css";

// Configuración de la autenticación con OIDC y Cognito. El objeto
// puede tomar cualquier nombre, pero no las propiedades.
const oidcConfig = {
  // Mismo emisor de JWT que spring.security.oauth2.resourceserver.jwt.issuer-uri
  authority: import.meta.env.VITE_COGNITO_ISSUER_URI,
  
  // Identificador de la aplicación cliente (App Client ID) en Cognito
  client_id: import.meta.env.VITE_COGNITO_CLIENT_ID,
  
  // URL a la que Cognito redirigirá al usuario tras autenticarse con éxito
  redirect_uri: window.location.origin,
  
  // Uso del flujo recomendado OAuth 2.0 Authorization Code Grant
  response_type: "code",
  
  // Cognito no admite el scope OIDC 'offline_access' (lo rechaza el hosted UI).
  // El refresh_token se obtiene igual: authorization code + PKCE + scope openid.
  // oidc-client-ts usa ese refresh_token en automaticSilentRenew y signinSilent.
  scope: "openid email profile",
  
  // App.jsx llama a handleRefreshToken en el evento accessTokenExpiring.
  // Este margen (60 s) es el tiempo antes de caducar en el que se dispara ese evento.
  accessTokenExpiringNotificationTimeInSeconds: 60,
  automaticSilentRenew: false,
  
  // Persiste la sesión y los tokens en el localStorage para mantener la sesión tras recargar la página
  // TODO: Esto exige un almacenamiento local del token, que podría ser inseguro
  // Hay que mejorar esta parte usando Lambdas
  userStore: new WebStorageStateStore({ store: window.localStorage })
};

ReactDOM.createRoot(document.getElementById("root")).render(

  // Renderiza el componente App en root, como es normal en React
  // App está encapsulado dentro del provider de autenticación, para
  // que se pueda usar la autenticación en toda la aplicación.
  <React.StrictMode>
    <AuthProvider {...oidcConfig}>
      <App />
    </AuthProvider>
  </React.StrictMode>
);