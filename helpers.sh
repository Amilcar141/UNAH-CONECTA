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

# --- Despliegue de Virtual Hosts ---
# Parámetros: 1:conf_filename
# Asume que BASE_DIR está definido en el script que la invoca.
desplegar_y_habilitar() {
    local conf_filename="$1"
    local src_file="${BASE_DIR}/config/vhosts/${conf_filename}"
    local dest_file="/etc/apache2/sites-available/${conf_filename}"

    # Respaldar si ya existe en sites-available
    if [ -f "$dest_file" ]; then
        local timestamp
        timestamp=$(date +%Y%m%d%H%M%S)
        cp "$dest_file" "${dest_file}.bak.${timestamp}" || error "Error al respaldar ${dest_file}."
        info "Respaldo creado: ${dest_file}.bak.${timestamp}"
    fi

    cp "$src_file" "$dest_file" || error "Error al copiar ${conf_filename} a sites-available."

    # Habilitar el sitio (a2ensite es idempotente, pero informamos si ya estaba activo)
    if [ -L "/etc/apache2/sites-enabled/${conf_filename}" ]; then
        advertencia "El sitio ${conf_filename} ya estaba habilitado en Apache."
    else
        a2ensite "${conf_filename}" >/dev/null 2>&1 || error "Error al habilitar el sitio ${conf_filename}."
        info "Sitio ${conf_filename} habilitado."
    fi
}