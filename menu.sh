#!/bin/bash
###############################################################################
# menu.sh
# Proyecto: UNAH-CONECTA
# Función: Panel de control interactivo para instalación, mantenimiento
#          y diagnóstico del servidor.
# Ejecución: sudo bash menu.sh
###############################################################################

set -uo pipefail

# --- Rutas base ---
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${BASE_DIR}/scripts"
CONFIG_FILE="${BASE_DIR}/config.env"

if [[ ! -f "${BASE_DIR}/helpers.sh" ]]; then
    echo "ERROR: no se encontró helpers.sh en ${BASE_DIR}/"
    echo "menu.sh debe ejecutarse desde la carpeta raíz del proyecto (junto a helpers.sh y config.env)."
    echo "Ejemplo correcto: /opt/unah-conecta/menu.sh, /opt/unah-conecta/helpers.sh"
    exit 1
fi

source "${BASE_DIR}/helpers.sh"

# Carga variables compartidas si existen
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    warn "No se encontró config.env, algunas opciones podrían no funcionar."
fi

# --- Ejecuta un script del proyecto si existe, o avisa si aún no está listo ---
run_script() {
    local script_name="$1"
    local script_path="${SCRIPTS_DIR}/${script_name}"
    if [[ -f "$script_path" ]]; then
        bash "$script_path"
    else
        warn "El script ${script_name} aún no ha sido creado en ${SCRIPTS_DIR}/"
    fi
}

# --- Diagnóstico: estado de servicios clave ---
check_services() {
    echo ""
    info "Estado de servicios:"
    for svc in apache2 mariadb ssh; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ok "$svc está activo"
        else
            warn "$svc NO está activo o no está instalado"
        fi
    done
    # PHP-FPM puede tener nombre distinto según la versión instalada
    if systemctl list-units --type=service 2>/dev/null | grep -q "php.*fpm"; then
        for svc in $(systemctl list-units --type=service 2>/dev/null | grep -oP 'php\S*fpm\S*\.service' | sort -u); do
            if systemctl is-active --quiet "$svc"; then
                ok "$svc está activo"
            else
                warn "$svc NO está activo"
            fi
        done
    else
        warn "No se detectó ningún servicio php-fpm"
    fi
}

# --- Diagnóstico: acceso a los dominios configurados ---
check_domains() {
    echo ""
    info "Verificando acceso a los dominios:"
    local domains=("${DOMAIN_WP:-www.unahconecta.com}" "${DOMAIN_MOODLE:-moodle.unahconecta.com}")
    for url in "${domains[@]}"; do
        code=$(curl -s -o /dev/null -m 5 -w "%{http_code}" "http://${url}" 2>/dev/null || echo "000")
        if [[ "$code" == "200" ]]; then
            ok "http://${url} responde correctamente (HTTP ${code})"
        elif [[ "$code" == "000" ]]; then
            warn "http://${url} no responde (sin conexión o DNS no resuelto)"
        else
            warn "http://${url} respondió con HTTP ${code}"
        fi
    done
}

# --- Diagnóstico: información general del servidor ---
system_info() {
    echo ""
    info "Información del sistema:"
    echo "  Hostname:     $(hostname)"
    echo "  IP interna:   $(hostname -I 2>/dev/null | awk '{print $1}')"
    echo "  Uptime:       $(uptime -p 2>/dev/null)"
    echo "  Disco (/):    $(df -h / 2>/dev/null | awk 'NR==2 {print $3" usado de "$2" ("$5")"}')"
    echo "  Memoria RAM:  $(free -h 2>/dev/null | awk '/^Mem:/ {print $3" usada de "$2}')"
}

# --- Submenú de logs ---
logs_menu() {
    echo ""
    echo "  1) Log de instalación (${INSTALL_LOG:-/var/log/unahconecta/install.log})"
    echo "  2) Log de errores de Apache"
    echo "  3) Log de acceso de Apache"
    echo "  0) Volver"
    read -rp "  Selecciona un log: " log_opt
    case "$log_opt" in
        1) [[ -f "${INSTALL_LOG:-/var/log/unahconecta/install.log}" ]] && tail -n 40 "${INSTALL_LOG:-/var/log/unahconecta/install.log}" || warn "No existe ese log todavía." ;;
        2) [[ -f /var/log/apache2/error.log ]] && sudo tail -n 40 /var/log/apache2/error.log || warn "No existe ese log todavía." ;;
        3) [[ -f /var/log/apache2/access.log ]] && sudo tail -n 40 /var/log/apache2/access.log || warn "No existe ese log todavía." ;;
        0) return ;;
        *) warn "Opción inválida" ;;
    esac
}

show_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     UNAH-CONECTA · Panel de Control      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "  INSTALACIÓN"
    echo "   1) Instalación completa (01 → 11 en orden)"
    echo "   2) Solo módulo WordPress"
    echo "   3) Solo módulo Moodle"
    echo ""
    echo "  MANTENIMIENTO"
    echo "   4) Actualizar sistema manualmente"
    echo "   5) Ejecutar backup manual"
    echo "   6) Ver/editar config.env"
    echo ""
    echo "  DIAGNÓSTICO"
    echo "   7) Ver estado de servicios"
    echo "   8) Ver logs"
    echo "   9) Verificar acceso a los dominios"
    echo "  10) Información general del servidor"
    echo ""
    echo "   0) Salir"
    echo ""
}

# --- Loop principal ---
while true; do
    show_menu
    read -rp "Selecciona una opción: " opt
    case "$opt" in
        1) run_script "deploy-all.sh" ;;
        2) run_script "05-wordpress.sh" ;;
        3) run_script "06-moodle.sh" ;;
        4) run_script "01-update.sh" ;;
        5) run_script "09-backup.sh" ;;
        6) ${EDITOR:-nano} "$CONFIG_FILE" ;;
        7) check_services ;;
        8) logs_menu ;;
        9) check_domains ;;
        10) system_info ;;
        0) echo "Saliendo..."; exit 0 ;;
        *) warn "Opción inválida" ;;
    esac
    echo ""
    read -rp "Presiona Enter para continuar..." _
done