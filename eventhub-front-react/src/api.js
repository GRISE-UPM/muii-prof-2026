// Base URL de la API: en `npm run dev` sale de .env.development; en `npm run build` de .env.production.local.
export const API_BASE_URL = import.meta.env.VITE_API_BASE_URL ?? "";

const HTTP_DESCRIPCIONES = {
  200: "OK — la petición se procesó correctamente",
  201: "Created — el recurso se creó correctamente",
  204: "No Content — operación correcta, sin cuerpo de respuesta",
  400: "Bad Request — datos no válidos o regla de negocio (p. ej. aforo agotado)",
  401: "Unauthorized — no autorizado",
  403: "Forbidden — no hay permiso para esta operación",
  404: "Not Found — no existe el recurso solicitado",
  405: "Method Not Allowed — el método HTTP no está permitido en esta ruta",
  409: "Conflict — el estado actual no permite la operación",
  415: "Unsupported Media Type — el formato del cuerpo no es el esperado",
  500: "Internal Server Error — error interno del servidor",
  502: "Bad Gateway — el proxy no obtuvo una respuesta válida",
  503: "Service Unavailable — el servidor no está disponible",
};

export function describirHttp(status) {
  return HTTP_DESCRIPCIONES[status] ?? `Código HTTP ${status}`;
}

function cuerpoComoJson(text, status, descripcion) {
  if (text) {
    try {
      return JSON.parse(text);
    } catch {
      // HTML u otro texto: no lo pintamos; el JSON de abajo resume el fallo
    }
  }
  return {
    error: status ? `HTTP ${status}` : "Sin respuesta",
    mensaje: descripcion,
  };
}

export async function apiFetch(path, { method = "GET", body } = {}) {
  try {
    const response = await fetch(`${API_BASE_URL}${path}`, {
      method,
      headers: {
        Accept: "application/json",
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });

    const descripcion = describirHttp(response.status);
    return {
      ok: response.ok,
      status: response.status,
      descripcion,
      data: cuerpoComoJson(await response.text(), response.status, descripcion),
    };
  } catch {
    const descripcion = "Sin respuesta HTTP — no se pudo conectar con la API";
    return {
      ok: false,
      status: 0,
      descripcion,
      data: { error: "Sin respuesta", mensaje: descripcion },
    };
  }
}
