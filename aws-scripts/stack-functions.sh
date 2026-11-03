#!/bin/bash

# Funciones para leer las salidas de una pila de CloudFormation. Los scripts las usan en lugar
# de un fichero de estado: la pila ya guarda lo que creó, y no hay nada que sincronizar.
#
#   salida <pila> <clave>             imprime el valor; no imprime nada si la pila o la clave no existen
#   salida_requerida <pila> <clave>   igual, pero termina con error si no existe

salida() {
    aws cloudformation describe-stacks --stack-name "$1" \
        --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text 2>/dev/null \
        | grep -v '^None$' || true
}

salida_requerida() {
    local valor
    valor=$(salida "$1" "$2")
    if [ -z "$valor" ]; then
        echo "Error: No se encontró la salida '$2' de la pila '$1'. ¿Has desplegado la pila?" >&2
        exit 1
    fi
    echo "$valor"
}
