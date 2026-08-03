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

# --- Iconos: UTF-8 o ASCII según soporte de la terminal ---
# Forzar modo ASCII con: export UNAH_ASCII_ICONS=1
# Auto-detección: si LANG o LC_ALL contienen "UTF-8" se usan glifos Unicode.
_usar_utf8=false
if [[ "${UNAH_ASCII_ICONS:-0}" != "1" ]]; then
    _locale_actual="${LC_ALL:-${LANG:-}}"
    if [[ "$_locale_actual" == *"UTF-8"* || "$_locale_actual" == *"utf8"* ]]; then
        _usar_utf8=true
    fi
fi

if $_usar_utf8; then
    _ICONO_PASO="\u279C"  # ➜
    _ICONO_OK="\u2713"   # ✓
    _ICONO_WARN="\u26A0" # ⚠
    _ICONO_ERR="\u2717"  # ✗
    _ICONO_INFO="\u2139" # ℹ
else
    _ICONO_PASO="->"
    _ICONO_OK="[OK]"
    _ICONO_WARN="[!]"
    _ICONO_ERR="[X]"
    _ICONO_INFO="[i]"
fi

# --- Secuencia principal de despliegue (fuente única de verdad) ---
# Estos son exactamente los 11 scripts numerados en el orden de deploy-all.sh.
# PASOS se usa en paso() para mostrar el contador [n/11].
# Tanto deploy-all.sh como paso() deben derivar su lista de este array.
MAIN_SEQUENCE_SCRIPTS=(
    "01-update.sh"
    "02-apache.sh"
    "03-mariadb.sh"
    "04-php.sh"
    "05-wordpress.sh"
    "06-moodle.sh"
    "07-vhosts.sh"
    "08-security.sh"
    "09-backup.sh"
    "10-webmin.sh"
    "11-monitor.sh"
)
PASOS=${#MAIN_SEQUENCE_SCRIPTS[@]}

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
# NOTA: todos los echo redirigen a stderr (>&2) para que las sustituciones de
# comando $(...) nunca capturen mensajes de diagnóstico como parte del valor
# retornado por una función. Solo el stdout explícito de una función (echo sin >&2)
# debe ser capturado por el llamador.
paso() {
    # Determinar si el script actual pertenece a la secuencia principal comprobando
    # membresía en MAIN_SEQUENCE_SCRIPTS (en vez de regex), para que 07b-ssl.sh
    # y cualquier nombre con letra en el prefijo también muestren el contador.
    local _script_basename
    _script_basename=$(basename "$0")
    local _es_principal=false
    for _s in "${MAIN_SEQUENCE_SCRIPTS[@]}"; do
        if [[ "$_s" == "$_script_basename" ]]; then
            _es_principal=true
            break
        fi
    done

    if $_es_principal; then
        echo -e "${CYAN}${_ICONO_PASO} [${1}/${PASOS}]${ND} ${BOLD}$2...${ND}" >&2
        _write_log "PASO" "[$1/$PASOS] $2..."
    else
        echo -e "${CYAN}${_ICONO_PASO}${ND} ${BOLD}$2...${ND}" >&2
        _write_log "PASO" "$2..."
    fi
}

ok() {
    echo -e "    ${VERDE}${_ICONO_OK}${ND} $1" >&2
    _write_log "OK" "$1"
}

error() {
    echo -e "" >&2
    echo -e "    ${ROJO}${_ICONO_ERR}${ND} ${BOLD}$1${ND}" >&2
    _write_log "ERROR" "$1"
    exit 1
}

advertencia() {
    echo -e "    ${AMARILLO}${_ICONO_WARN}${ND} ${BOLD}$1${ND}" >&2
    _write_log "ADVERTENCIA" "$1"
}

info() {
    echo -e "    ${AZUL}${_ICONO_INFO}${ND} $1" >&2
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