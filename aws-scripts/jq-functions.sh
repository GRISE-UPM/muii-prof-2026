#!/bin/bash
# Acceso a aws-scripts/lab-state.json (estado del laboratorio).
# Uso: source "$SCRIPT_DIR/jq-functions.sh"
#
# El JSON se va poblando a medida que cada script hace create (no hace falta
# un esquema completo desde el principio). Claves alineadas con la API de AWS
# (GroupId, InstanceId, AllocationId, ...). PublicIp se guarda por comodidad;
# tambien se obtiene con describe-addresses --allocation-ids.

LAB_STATE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LAB_STATE_FILE="${LAB_STATE_FILE:-$LAB_STATE_DIR/lab-state.json}"

state_init() {
    if [ ! -f "$LAB_STATE_FILE" ]; then
        echo '{}' > "$LAB_STATE_FILE"
    fi
}

# state_get <Clave>  -> imprime el valor o cadena vacia
state_get() {
    local key="$1"
    state_init
    jq -r --arg k "$key" 'if has($k) and .[$k] != null then .[$k] else empty end' "$LAB_STATE_FILE"
}

# state_set <Clave> <valor>
state_set() {
    local key="$1"
    local value="$2"
    local tmp
    state_init
    tmp=$(mktemp)
    jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$LAB_STATE_FILE" > "$tmp"
    if [ $? -ne 0 ]; then
        rm -f "$tmp"
        echo "Error: no se pudo escribir '$key' en $LAB_STATE_FILE"
        exit 1
    fi
    mv "$tmp" "$LAB_STATE_FILE"
}

# state_require <Clave>  -> imprime el valor o sale con error
state_require() {
    local key="$1"
    local value
    value=$(state_get "$key")
    if [ -z "$value" ]; then
        echo "Error: falta '$key' en $LAB_STATE_FILE. Ejecuta antes el create correspondiente."
        exit 1
    fi
    printf '%s' "$value"
}

# state_clear  -> borra el fichero de estado
state_clear() {
    rm -f "$LAB_STATE_FILE"
}
