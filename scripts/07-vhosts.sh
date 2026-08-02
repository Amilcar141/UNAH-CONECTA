#!/bin/bash
###############################################################################
# 07-vhosts.sh
# Proyecto: UNAH-CONECTA
# Función: Generación dinámica y configuración de Virtual Hosts para Apache2
#          con conexión a PHP-FPM vía proxy_fcgi.
#          Soporta configuración temporal por IP (WP en :80, Moodle en :8080)
#          y configuración definitiva por dominio (ambos en :80 con ServerName).
# Ejecución: sudo ./07-vhosts.sh (o mediante menu.sh)
#
# VARIABLES REQUERIDAS DE config.env:
#   DOMAIN_WP, PATH_WP, DOMAIN_MOODLE, PATH_MOODLE
#   PHP_VERSION, SERVER_ADMIN_EMAIL
###############################################################################

set -euo pipefail

# Resolver directorios base usando BASH_SOURCE
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Cambiar de directorio a BASE_DIR para que helpers.sh resuelva el conteo de PASOS
cd "$BASE_DIR"

# Cargar funciones de salida compartidas y variables de configuración
source "./helpers.sh"
source "./config.env"

# Verificar privilegios de root/sudo al inicio
require_root

# Configurar frontend no interactivo
export DEBIAN_FRONTEND=noninteractive

# --- Paso 1: Verificación de variables y dependencias ---
paso "07" "Validando dependencias para la configuración de Virtual Hosts"

if [[ -z "${PHP_VERSION:-}" || -z "${SERVER_ADMIN_EMAIL:-}" ]]; then
    error "Faltan variables requeridas en config.env (PHP_VERSION o SERVER_ADMIN_EMAIL)."
fi

if [[ -z "${DOMAIN_WP:-}" || -z "${PATH_WP:-}" || -z "${DOMAIN_MOODLE:-}" || -z "${PATH_MOODLE:-}" ]]; then
    error "Faltan variables requeridas de dominios o rutas en config.env (DOMAIN_WP, PATH_WP, DOMAIN_MOODLE, PATH_MOODLE)."
fi

SOCKET_PATH="/run/php/php${PHP_VERSION}-fpm.sock"
if [ ! -S "$SOCKET_PATH" ]; then
    error "El socket de PHP-FPM (${SOCKET_PATH}) no existe. Verifique que 04-php.sh se ejecutó."
fi
ok "Dependencias validadas. Socket de PHP-FPM encontrado."

# --- Paso 2: Detectar modo de operación (IP con puertos o dominios reales) ---
# Extrae host y puerto de una cadena que puede ser "ip:puerto" o solo "dominio"
extraer_host() { echo "${1%%:*}"; }
extraer_puerto() {
    if [[ "$1" == *:* ]]; then echo "${1##*:}"; else echo "80"; fi
}

HOST_WP=$(extraer_host "$DOMAIN_WP")
PUERTO_WP=$(extraer_puerto "$DOMAIN_WP")
HOST_MOODLE=$(extraer_host "$DOMAIN_MOODLE")
PUERTO_MOODLE=$(extraer_puerto "$DOMAIN_MOODLE")

info "WordPress  → http://${HOST_WP}:${PUERTO_WP}"
info "Moodle     → http://${HOST_MOODLE}:${PUERTO_MOODLE}"

# --- Paso 3: Habilitar puerto extra en Apache si Moodle usa puerto ≠ 80 ---
PORTS_CONF="/etc/apache2/ports.conf"
PUERTO_NUEVO_AGREGADO=false
if [[ "$PUERTO_MOODLE" != "80" ]]; then
    paso "07" "Habilitando puerto ${PUERTO_MOODLE} en Apache (Moodle)"
    if grep -q "Listen ${PUERTO_MOODLE}" "$PORTS_CONF"; then
        info "El puerto ${PUERTO_MOODLE} ya estaba declarado en ports.conf."
    else
        echo "Listen ${PUERTO_MOODLE}" >> "$PORTS_CONF" || error "Error al agregar Listen ${PUERTO_MOODLE} en ports.conf."
        ok "Puerto ${PUERTO_MOODLE} agregado a ports.conf."
        # Un puerto Listen nuevo requiere un restart completo para que Apache
        # abra el socket de escucha; un simple reload no siempre lo hace.
        PUERTO_NUEVO_AGREGADO=true
    fi
fi

# --- Paso 4: Función generadora de Virtual Hosts ---
# Parámetros: 1:host 2:puerto 3:path 4:conf_filename 5:allow_override 6:alias(opcional)
generar_vhost() {
    local host="$1"
    local puerto="$2"
    local path="$3"
    local conf_filename="$4"
    local allow_override_type="$5"
    local alias="${6:-}"
    local log_prefix="${conf_filename%.conf}"
    local dest_file="${BASE_DIR}/config/vhosts/${conf_filename}"

    mkdir -p "${BASE_DIR}/config/vhosts"
    
    local alias_directive=""
    if [[ -n "$alias" ]]; then
        alias_directive="ServerAlias ${alias}"
    fi

    cat > "$dest_file" <<EOF
<VirtualHost *:${puerto}>
    ServerName ${host}
    ${alias_directive}
    ServerAdmin ${SERVER_ADMIN_EMAIL}
    DocumentRoot ${path}

    <Directory ${path}>
        Options -Indexes +FollowSymLinks
        AllowOverride ${allow_override_type}
        Require all granted
    </Directory>

    <FilesMatch \.php$>
        SetHandler "proxy:unix:${SOCKET_PATH}|fcgi://localhost"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/${log_prefix}_error.log
    CustomLog \${APACHE_LOG_DIR}/${log_prefix}_access.log combined
</VirtualHost>
EOF
    info "Configuración generada: ${dest_file}"
}

# --- Paso 5: Generación de archivos de configuración ---
paso "07" "Generando configuraciones de Virtual Hosts (WordPress y Moodle)"

# WordPress: AllowOverride All para que funcionen los permalinks con .htaccess
generar_vhost "$HOST_WP" "$PUERTO_WP" "$PATH_WP" "unahconecta.conf" "All" "${DOMAIN_WP_ALIAS:-}"

# Moodle: AllowOverride None (no usa .htaccess; mejora rendimiento y seguridad)
generar_vhost "$HOST_MOODLE" "$PUERTO_MOODLE" "$PATH_MOODLE" "moodle.unahconecta.conf" "None" ""

ok "Archivos de configuración generados."

# --- Paso 6: Despliegue hacia Apache ---
paso "07" "Desplegando Virtual Hosts en Apache"

# (La función desplegar_y_habilitar ahora se encuentra en helpers.sh)

desplegar_y_habilitar "unahconecta.conf"
desplegar_y_habilitar "moodle.unahconecta.conf"
ok "Despliegue y activación de Virtual Hosts completado."

# --- Paso 7: Desactivación del sitio por defecto ---
paso "07" "Desactivando sitio por defecto de Apache"

if [ -L "/etc/apache2/sites-enabled/000-default.conf" ]; then
    a2dissite 000-default.conf >/dev/null 2>&1 || error "Error al deshabilitar el sitio por defecto."
    ok "Sitio por defecto (000-default.conf) deshabilitado."
else
    info "El sitio por defecto ya se encontraba deshabilitado."
fi

# --- Paso 8: Validación de sintaxis ---
paso "07" "Validando la sintaxis global de Apache"

if apache2ctl configtest > /tmp/apache_configtest_vhosts.log 2>&1; then
    ok "Sintaxis de configuración de Apache válida."
else
    error "Fallo en apache2ctl configtest. Se detiene el proceso para no dañar el servidor web. Detalle:\n$(cat /tmp/apache_configtest_vhosts.log)"
fi

# --- Paso 9: Recarga (o restart) y verificación del resultado real ---
if [[ "$PUERTO_NUEVO_AGREGADO" == "true" ]]; then
    paso "07" "Reiniciando Apache (puerto nuevo requiere restart, no solo reload)"
    systemctl restart apache2 >/dev/null 2>&1 || error "Error al reiniciar Apache2."
else
    paso "07" "Recargando Apache y verificando accesibilidad local"
    systemctl reload apache2 >/dev/null 2>&1 || error "Error al recargar la configuración de Apache2."
fi

if systemctl is-active --quiet apache2; then
    ok "Servicio Apache2 activo."
else
    error "Apache2 dejó de estar activo tras aplicar la configuración."
fi

# Verificación extra: si se agregó un puerto nuevo, confirmar que Apache
# realmente quedó escuchando en él (evita el caso "todo OK pero el puerto
# nunca abrió", que es silencioso y confuso de diagnosticar después)
if [[ "$PUERTO_NUEVO_AGREGADO" == "true" ]]; then
    if ss -tln | grep -q ":${PUERTO_MOODLE} "; then
        ok "Apache confirmado escuchando en el puerto ${PUERTO_MOODLE}."
    else
        error "Apache no quedó escuchando en el puerto ${PUERTO_MOODLE} tras el restart. Revisa ports.conf manualmente."
    fi
fi

verificar_http() {
    local host="$1"
    local puerto="$2"
    local label="$3"
    local http_status
    http_status=$(curl --max-time 5 --connect-timeout 3 -s -o /dev/null -w "%{http_code}" "http://${host}:${puerto}/" 2>/dev/null || echo "000")

    if [[ "$http_status" == "200" || "$http_status" == 30* ]]; then
        ok "${label} responde correctamente (HTTP ${http_status}) → http://${host}:${puerto}"
    else
        advertencia "${label} devolvió HTTP ${http_status} → http://${host}:${puerto} (esperable si la plataforma aún no está inicializada)."
    fi
}

verificar_http "$HOST_WP"     "$PUERTO_WP"     "WordPress"
verificar_http "$HOST_MOODLE" "$PUERTO_MOODLE" "Moodle"

echo "Script 07-vhosts.sh finalizado con éxito."