#!/bin/bash
###############################################################################
# 07-vhosts.sh
# Proyecto: UNAH-CONECTA
# Función: Generación dinámica y configuración de Virtual Hosts para Apache2 
#          con conexión a PHP-FPM vía proxy_fcgi.
# Ejecución: sudo ./07-vhosts.sh (o mediante menu.sh)
#
# VARIABLES REQUERIDAS DE config.env:
#   DOMAIN_WP, PATH_WP, DOMAIN_MOODLE, PATH_MOODLE
#
# VARIABLES NUEVAS A AGREGAR A config.env:
#   PHP_VERSION (Debe coincidir con la instalada en 04-php.sh, ej: 8.3)
#   SERVER_ADMIN_EMAIL (Email del administrador del servidor web)
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

SOCKET_PATH="/run/php/php${PHP_VERSION}-fpm.sock"
if [ ! -S "$SOCKET_PATH" ]; then
    error "El socket de PHP-FPM (${SOCKET_PATH}) no existe. Verifique que el script 04-php.sh se haya ejecutado correctamente."
fi
ok "Dependencias validadas. Socket de PHP-FPM encontrado."

# --- Paso 2: Función generadora de Virtual Hosts ---
# Parámetros: 1: domain, 2: path, 3: conf_filename, 4: allow_override_type
generar_vhost() {
    local domain="$1"
    local path="$2"
    local conf_filename="$3"
    local allow_override_type="$4"
    local log_prefix="${conf_filename%.conf}"
    local dest_file="${BASE_DIR}/config/vhosts/${conf_filename}"

    mkdir -p "${BASE_DIR}/config/vhosts"

    cat > "$dest_file" <<EOF
<VirtualHost *:80>
    ServerName ${domain}
    ServerAdmin ${SERVER_ADMIN_EMAIL}
    DocumentRoot ${path}

    <Directory ${path}>
        Options FollowSymLinks
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
    info "Archivo generado dinámicamente en: ${dest_file}"
}

# --- Paso 3: Generación de archivos de configuración ---
paso "07" "Generando configuraciones de Virtual Hosts (WordPress y Moodle)"

# Generar VHost de WordPress (Requiere AllowOverride All para los permalinks)
generar_vhost "${DOMAIN_WP}" "${PATH_WP}" "unahconecta.conf" "All"

# Generar VHost de Moodle (No usa .htaccess, requiere AllowOverride None por seguridad/rendimiento)
generar_vhost "${DOMAIN_MOODLE}" "${PATH_MOODLE}" "moodle.unahconecta.conf" "None"

ok "Archivos de configuración generados."

# --- Paso 4: Despliegue hacia Apache ---
paso "07" "Desplegando Virtual Hosts en Apache"

desplegar_y_habilitar() {
    local conf_filename="$1"
    local src_file="${BASE_DIR}/config/vhosts/${conf_filename}"
    local dest_file="/etc/apache2/sites-available/${conf_filename}"

    # Respaldo si el archivo ya existe en sites-available
    if [ -f "$dest_file" ]; then
        local timestamp
        timestamp=$(date +%Y%m%d%H%M%S)
        cp "$dest_file" "${dest_file}.bak.${timestamp}" || error "Error al respaldar ${dest_file}."
        info "Respaldo creado: ${dest_file}.bak.${timestamp}"
    fi

    cp "$src_file" "$dest_file" || error "Error al copiar ${conf_filename} a sites-available."

    # Habilitar el sitio
    if [ -L "/etc/apache2/sites-enabled/${conf_filename}" ]; then
        advertencia "El sitio ${conf_filename} ya estaba habilitado en Apache."
    else
        a2ensite "${conf_filename}" >/dev/null 2>&1 || error "Error al habilitar el sitio ${conf_filename}."
        info "Sitio ${conf_filename} habilitado."
    fi
}

desplegar_y_habilitar "unahconecta.conf"
desplegar_y_habilitar "moodle.unahconecta.conf"
ok "Despliegue y activación de Virtual Hosts completado."

# --- Paso 5: Desactivación del sitio por defecto ---
paso "07" "Desactivando sitio por defecto de Apache"

if [ -L "/etc/apache2/sites-enabled/000-default.conf" ]; then
    a2dissite 000-default.conf >/dev/null 2>&1 || error "Error al deshabilitar el sitio por defecto."
    ok "Sitio por defecto (000-default.conf) deshabilitado."
else
    info "El sitio por defecto ya se encontraba deshabilitado."
fi

# --- Paso 6: Validación de sintaxis ---
paso "07" "Validando la sintaxis global de Apache"

if apache2ctl configtest >/dev/null 2>&1; then
    ok "Sintaxis de configuración de Apache válida."
else
    error "Fallo en la prueba de sintaxis de Apache (configtest). Se detiene el proceso para evitar una caída del servidor web."
fi

# --- Paso 7: Recarga y verificación del resultado real ---
paso "07" "Recargando Apache y verificando accesibilidad local"

systemctl reload apache2 >/dev/null 2>&1 || error "Error al recargar la configuración de Apache2."

if systemctl is-active --quiet apache2; then
    ok "Servicio Apache2 activo tras la recarga."
else
    error "Apache2 dejó de estar activo tras recargar la configuración."
fi

verificar_http() {
    local dominio="$1"
    local http_status
    http_status=$(curl -I -s -o /dev/null -w "%{http_code}" -H "Host: ${dominio}" http://127.0.0.1/ || echo "000")
    
    # 200 OK o 30x Redirect son respuestas válidas de una plataforma activa
    if [[ "$http_status" == "200" || "$http_status" == 30* ]]; then
        ok "El Virtual Host para ${dominio} responde correctamente (HTTP ${http_status})."
    else
        advertencia "La petición HTTP a ${dominio} devolvió código ${http_status}. El VHost está creado, pero la plataforma podría requerir revisión."
    fi
}

verificar_http "${DOMAIN_WP}"
verificar_http "${DOMAIN_MOODLE}"

echo "Script 07-vhosts.sh finalizado con éxito."
