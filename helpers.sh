#!/bin/bash
###############################################################################
# helpers.sh
# Proyecto: UNAH-CONECTA
# Función: Funciones de salida reutilizables para todos los scripts del proyecto
# Uso: source ./helpers.sh   (o  source ../helpers.sh  desde scripts/)
###############################################################################

# --- Colores ---
VERDE='\033[0;32m'
ROJO='\033[0;31m'
AMARILLO='\033[1;33m'
AZUL='\033[0;34m'
ND='\033[0m' # Sin color

# Busca la cantidad de archivos en la carpeta scripts para determinar el total de pasos
PASOS=$(find ./scripts -type f | wc -l)

# --- Funciones de salida ---
paso() {
    echo -e "${AZUL}[$1/${PASOS}]${ND} $2..."
}

ok() {
    echo -e "  ${VERDE}✓${ND} $1"
}

error() {
    echo -e "  ${ROJO}✗${ND} $1"
    exit 1
}

advertencia() {
    echo -e "  ${AMARILLO}⚠${ND} $1"
}

info() {
    echo -e "  ${AZUL}ℹ${ND} $1"
}

# Verifica que el script corra como root/sudo
require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script debe ejecutarse con sudo o como root."
    fi
}