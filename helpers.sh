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
CYAN='\033[0;36m'
BOLD='\033[1m'
ND='\033[0m' # Sin color

# Cuenta solo los scripts de la secuencia principal (00-11): excluye auxiliares
# como 12-restore.sh, save-desing.sh, load-desing.sh, deploy-all.sh, etc.
PASOS=$(find ./scripts -maxdepth 1 -type f -name '*.sh' | grep -cE '/([0-9]|10|11)-[^/]+\.sh$')

# --- Variables de Logging ---
_LOG_INITIALIZED=0
SCRIPT_LOG=""

_init_log() {
    if [[ $_LOG_INITIALIZED -eq 0 ]]; then
        _LOG_INITIALIZED=1 # Evita llamadas circulares si hay error
        local current_log_dir="${LOG_DIR:-/var/log/unahconecta}"
        
        # Crear directorio si no existe
        if [[ ! -d "$current_log_dir" ]]; then
            if ! mkdir -p "$current_log_dir" 2>/dev/null; then
                SCRIPT_LOG="/dev/null"
                error "No se pudo crear el directorio de logs: $current_log_dir"
            fi
        fi
        
        # Generar ruta del log basada en el nombre del script actual
        local script_name
        script_name=$(basename "$0" .sh)
        SCRIPT_LOG="${current_log_dir}/${script_name}.log"
        
        # Truncar log para sobreescribir con cada nueva corrida
        if touch "$SCRIPT_LOG" 2>/dev/null; then
            > "$SCRIPT_LOG"
        else
            SCRIPT_LOG="/dev/null"
            error "No se pudo inicializar/truncar el archivo de log: $SCRIPT_LOG"
        fi
    fi
}

_write_log() {
    local level="$1"
    local message="$2"
    _init_log
    if [[ -n "$SCRIPT_LOG" && "$SCRIPT_LOG" != "/dev/null" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [${level}] ${message}" >> "$SCRIPT_LOG" 2>/dev/null
    fi
}

# --- Funciones de salida ---
paso() {
    # Detectar si el script actual pertenece a la secuencia principal (prefijo 00-11)
    local _script_base
    _script_base=$(basename "$0" .sh)
    if [[ "$_script_base" =~ ^(0[0-9]|1[01])- ]]; then
        # Script de la secuencia principal: mostrar contador [n/PASOS]
        echo -e "${CYAN}➜ [${1}/${PASOS}]${ND} ${BOLD}$2...${ND}"
        _write_log "PASO" "[$1/$PASOS] $2..."
    else
        # Script auxiliar: mostrar solo el ícono y el mensaje, sin contador
        echo -e "${CYAN}➜${ND} ${BOLD}$2...${ND}"
        _write_log "PASO" "$2..."
    fi
}

ok() {
    echo -e "    ${VERDE}✓${ND} $1"
    _write_log "OK" "$1"
}

error() {
    echo -e ""
    echo -e "    ${ROJO}✗${ND} ${BOLD}$1${ND}"
    _write_log "ERROR" "$1"
    exit 1
}

advertencia() {
    echo -e "    ${AMARILLO}⚠${ND} ${BOLD}$1${ND}"
    _write_log "ADVERTENCIA" "$1"
}

info() {
    echo -e "    ${AZUL}ℹ${ND} $1"
    _write_log "INFO" "$1"
}

# Verifica que el script corra como root/sudo
require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script debe ejecutarse con sudo o como root."
    fi
}