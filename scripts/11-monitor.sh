#!/bin/bash
###############################################################################
# 11-monitor.sh
# Proyecto: UNAH-CONECTA
# Función: Generar registros (logs) del estado del servidor y de los
#          servicios críticos (Apache2, MariaDB, SSH, PHP), pensado para
#          ejecutarse manualmente o mediante una tarea programada (cron).
# Ejecución: sudo ./11-monitor.sh (o mediante menu.sh / crontab)
#
# VARIABLES OPCIONALES DE config.env:
#   MONITOR_LOG_DIR         (ruta de logs. Por defecto: /var/log/unah-conecta)
#   MONITOR_DISK_THRESHOLD  (umbral % de disco para advertencia. Por defecto: 85)
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BASE_DIR"

source "./helpers.sh"
source "./config.env"

require_root

MONITOR_LOG_DIR="${MONITOR_LOG_DIR:-/var/log/unah-conecta}"
MONITOR_DISK_THRESHOLD="${MONITOR_DISK_THRESHOLD:-85}"
LOG_FILE="${MONITOR_LOG_DIR}/monitor-$(date +%Y%m%d).log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

# --- Paso 1: Preparar directorio de logs ---
paso "11" "Preparando el directorio de logs de monitoreo"

mkdir -p "$MONITOR_LOG_DIR" || error "No se pudo crear el directorio de logs ${MONITOR_LOG_DIR}."
ok "Directorio de logs listo en ${MONITOR_LOG_DIR}."

# --- Paso 2: Recolección del estado del servidor ---
paso "11" "Recolectando el estado actual del servidor"

{
    echo "==================================================================="
    echo "REGISTRO DE ESTADO DEL SERVIDOR - ${TIMESTAMP}"
    echo "==================================================================="

    echo "--- CARGA DEL SISTEMA (uptime) ---"
    uptime

    echo ""
    echo "--- USO DE CPU (snapshot) ---"
    top -bn1 | head -n 12

    echo ""
    echo "--- USO DE MEMORIA RAM ---"
    free -h

    echo ""
    echo "--- USO DE DISCO ---"
    df -h --output=target,pcent,used,size

    echo ""
    echo "--- ESTADO DE SERVICIOS CRÍTICOS ---"
    for servicio in apache2 mariadb ssh; do
        if systemctl is-active --quiet "$servicio"; then
            echo "[OK]    ${servicio}: activo"
        else
            echo "[ERROR] ${servicio}: inactivo o con fallas"
        fi
    done

    # PHP-FPM es opcional; con PHP nativo vía mod_php este chequeo se omite si no existe
    PHP_FPM_SERVICE=$(systemctl list-units --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -m1 "php.*fpm" || true)
    if [[ -n "$PHP_FPM_SERVICE" ]]; then
        if systemctl is-active --quiet "$PHP_FPM_SERVICE"; then
            echo "[OK]    ${PHP_FPM_SERVICE}: activo"
        else
            echo "[ERROR] ${PHP_FPM_SERVICE}: inactivo o con fallas"
        fi
    fi

    echo ""
    echo "--- TOP 5 PROCESOS POR USO DE CPU ---"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 6

    echo ""
    echo "--- PUERTOS CLAVE EN ESCUCHA (80, 443, 3306, 22, 10000) ---"
    ss -tuln | grep -E ':80 |:443 |:3306 |:22 |:10000 ' || echo "Sin escucha activa en los puertos monitoreados."

} >> "$LOG_FILE" 2>&1

ok "Registro de estado agregado a ${LOG_FILE}."

# --- Paso 3: Alerta simple por uso elevado de disco ---
paso "11" "Verificando umbral de uso de disco (${MONITOR_DISK_THRESHOLD}%)"

DISK_USAGE=$(df / --output=pcent | tail -n1 | tr -dc '0-9')

if [ "$DISK_USAGE" -ge "$MONITOR_DISK_THRESHOLD" ]; then
    advertencia "El uso del disco principal es de ${DISK_USAGE}%, superando el umbral configurado (${MONITOR_DISK_THRESHOLD}%)."
    echo "[ALERTA] Uso de disco crítico: ${DISK_USAGE}% - ${TIMESTAMP}" >> "$LOG_FILE"
else
    ok "Uso de disco dentro de parámetros normales (${DISK_USAGE}%)."
fi

echo "Script 11-monitor.sh finalizado con éxito. Log disponible en: ${LOG_FILE}"
