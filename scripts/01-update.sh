#!/bin/bash
###############################################################################
# 01-update.sh
# Proyecto: UNAH-CONECTA
# Función: Actualización del sistema operativo e instalación de paquetes básicos
# Ejecución: sudo ./01-update.sh
# Nota: Este script es parte de la secuencia de DESPLIEGUE INICIAL.
#       No debe programarse para ejecutarse en cada arranque del sistema.
###############################################################################

set -euo pipefail

# --- Colores ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # Sin color

TOTAL_STEPS=11
STEP_NUM=1

# --- Funciones de salida ---
step() {
    echo -e "${BLUE}[${STEP_NUM}/${TOTAL_STEPS}]${NC} $1..."
}

ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
    exit 1
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

# --- Validación: debe correr como root/sudo ---
if [[ $EUID -ne 0 ]]; then
    fail "Este script debe ejecutarse con sudo o como root."
fi

# --- Inicio ---
step "Actualizando sistema"

apt update -y > /tmp/01-update.log 2>&1 \
    && ok "Índices de paquetes actualizados (apt update)" \
    || fail "Error al ejecutar apt update. Revisa /tmp/01-update.log"

apt upgrade -y >> /tmp/01-update.log 2>&1 \
    && ok "Paquetes del sistema actualizados (apt upgrade)" \
    || fail "Error al ejecutar apt upgrade. Revisa /tmp/01-update.log"

echo -e "${BLUE}[${STEP_NUM}/${TOTAL_STEPS}]${NC} Instalando utilidades básicas..."

apt install -y curl wget unzip software-properties-common \
    ca-certificates gnupg lsb-release ufw >> /tmp/01-update.log 2>&1 \
    && ok "Utilidades básicas instaladas (curl, wget, unzip, ufw, etc.)" \
    || fail "Error instalando utilidades básicas. Revisa /tmp/01-update.log"

# --- Verificación de reinicio pendiente ---
if [ -f /var/run/reboot-required ]; then
    warn "El sistema requiere reinicio (probablemente por actualización de kernel)."
fi

echo -e "${GREEN}Script 01-update.sh finalizado correctamente.${NC}"