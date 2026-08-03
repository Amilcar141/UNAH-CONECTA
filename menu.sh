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
    advertencia "No se encontró config.env, algunas opciones podrían no funcionar."
fi

# --- Ejecuta un script del proyecto si existe, o avisa si aún no está listo ---
run_script() {
    local script_name="$1"
    shift
    local script_path="${SCRIPTS_DIR}/${script_name}"
    if [[ -f "$script_path" ]]; then
        bash "$script_path" "$@"
    else
        advertencia "El script ${script_name} aún no ha sido creado en ${SCRIPTS_DIR}/"
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
            advertencia "$svc NO está activo o no está instalado"
        fi
    done

    # PHP-FPM: verificar directamente con PHP_VERSION (cargada desde config.env).
    # Fallback: buscar cualquier servicio php*-fpm activo si PHP_VERSION no está definida.
    local _fpm_svc
    if [[ -n "${PHP_VERSION:-}" ]]; then
        _fpm_svc="php${PHP_VERSION}-fpm"
        if systemctl is-active --quiet "$_fpm_svc" 2>/dev/null; then
            ok "${_fpm_svc} está activo"
        else
            advertencia "${_fpm_svc} NO está activo o no está instalado"
        fi
    else
        # Fallback: buscar cualquier servicio php[version]-fpm mediante lista
        local _fpm_found=false
        while IFS= read -r _unit; do
            _fpm_found=true
            if systemctl is-active --quiet "$_unit" 2>/dev/null; then
                ok "${_unit} está activo"
            else
                advertencia "${_unit} NO está activo"
            fi
        done < <(systemctl list-units --all --type=service --no-legend --plain 2>/dev/null \
            | awk '{print $1}' | grep -E '^php[0-9.]+-fpm\.service$' | sort -u)
        if ! $_fpm_found; then
            advertencia "No se detectó ningún servicio php-fpm (PHP_VERSION no definida en config.env)"
        fi
    fi
}

# --- Diagnóstico: acceso a las plataformas configuradas ---
check_domains() {
    echo ""
    info "Verificando acceso a las plataformas (por IP):"
    # Extraer host y puerto de las variables de config.env
    local url_wp="http://${DOMAIN_WP:-<IP_PUBLICA>}"
    local host_moodle="${DOMAIN_MOODLE:-<IP_PUBLICA>:8080}"
    local url_moodle="http://${host_moodle%%:*}:${host_moodle##*:}"
    [[ "$host_moodle" != *:* ]] && url_moodle="http://${host_moodle}"

    for entry in "WordPress|${url_wp}" "Moodle|${url_moodle}"; do
        local label="${entry%%|*}"
        local url="${entry##*|}"
        local code="000"
        code=$(curl -s -o /dev/null --connect-timeout 3 -m 5 -w "%{http_code}" \
            "${url}" 2>/dev/null || echo "000")

        if [[ "$code" == "000" ]]; then
            advertencia "${label} no responde en ${url}"
        elif [[ "$code" =~ ^(200|301|302|303|307|308)$ ]]; then
            ok "${label} responde correctamente (HTTP ${code}) → ${url}"
        else
            advertencia "${label} respondió con HTTP ${code} → ${url}"
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
    local log_dir="${LOG_DIR:-/var/log/unahconecta}"
    
    # Obtener lista de logs generados por los scripts en el directorio
    local log_files=()
    if [[ -d "$log_dir" ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && log_files+=("$file")
        done < <(find "$log_dir" -maxdepth 1 -name "*.log" -type f | sort)
    fi

    if [[ ${#log_files[@]} -eq 0 ]]; then
        advertencia "No hay logs de scripts disponibles aún en $log_dir."
        return
    fi

    # Imprimir submenú dinámico
    echo "  Logs disponibles:"
    local i=1
    for log_file in "${log_files[@]}"; do
        echo "  $i) $(basename "$log_file")"
        ((i++))
    done
    
    # Logs adicionales estáticos que existían
    local apache_err="/var/log/apache2/error.log"
    local apache_acc="/var/log/apache2/access.log"
    
    local idx_err=$i
    echo "  ${idx_err}) Log de errores de Apache"
    ((i++))
    
    local idx_acc=$i
    echo "  ${idx_acc}) Log de acceso de Apache"
    
    echo "  0) Volver"
    
    read -rp "  Selecciona un log: " log_opt
    
    # Manejar opciones
    if [[ "$log_opt" == "0" ]]; then
        return
    elif [[ "$log_opt" =~ ^[0-9]+$ ]] && (( log_opt >= 1 && log_opt <= ${#log_files[@]} )); then
        local selected_log="${log_files[$((log_opt-1))]}"
        if command -v less >/dev/null 2>&1; then
            less "$selected_log"
        else
            cat "$selected_log"
        fi
    elif [[ "$log_opt" == "$idx_err" ]]; then
        [[ -f "$apache_err" ]] && sudo tail -n 40 "$apache_err" || advertencia "No existe ese log todavía."
    elif [[ "$log_opt" == "$idx_acc" ]]; then
        [[ -f "$apache_acc" ]] && sudo tail -n 40 "$apache_acc" || advertencia "No existe ese log todavía."
    else
        advertencia "Opción inválida"
    fi
}

show_menu() {
    clear
    echo -e "${AZUL}╔════════════════════════════════════════╗${ND}"
    echo -e "${AZUL}║     UNAH-CONECTA · Panel de Control    ║${ND}"
    echo -e "${AZUL}╚════════════════════════════════════════╝${ND}"
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
    echo "   9) Verificar acceso a las plataformas (por IP)"
    echo "  10) Información general del servidor"
    echo ""
    echo "  PERSONALIZACIÓN MOODLE"
    echo "  11) Guardar diseño (Moove)"
    echo "  12) Aplicar diseño (Moove)"
    echo ""
    echo "  RECUPERACIÓN"
    echo "  13) Restaurar backup en servidor nuevo"
    echo ""
    echo "  CONFIGURACIÓN ADICIONAL"
    echo "  14) Configurar Virtual Hosts (07-vhosts)"
    echo "  15) Configurar Webmin (10-webmin)"
    echo "  16) Forzar sincronización manual de IP administrativa (DDNS)"
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
        11) run_script "save-desing.sh" ;;
        12) run_script "load-desing.sh" ;;
        13)
            read -rp "  Introduce el TIMESTAMP del backup a restaurar (ej. 20260730_143210): " timestamp
            if [[ -n "$timestamp" ]]; then
                run_script "12-restore.sh" "$timestamp"
            else
                advertencia "TIMESTAMP no proporcionado. Operación cancelada."
            fi
            ;;
        14) run_script "07-vhosts.sh" ;;
        15) run_script "10-webmin.sh" ;;
        16)
            info "Forzando sincronización de IP administrativa..."
            run_script "sync-admin-ip.sh"
            ;;
        0) echo "Saliendo..."; exit 0 ;;
        *) advertencia "Opción inválida" ;;
    esac
    echo ""
    read -rp "Presiona Enter para continuar..." _
done