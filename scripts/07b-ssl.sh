#!/bin/bash
###############################################################################
# 07b-ssl.sh
# Proyecto: UNAH-CONECTA
# Función: Emisión e instalación de certificados Let's Encrypt para todos los
#          dominios configurados utilizando Certbot.
# Ejecución: sudo ./07b-ssl.sh (o mediante menu.sh)
#
# REQUISITOS: Se debe haber configurado los Virtual Hosts en 07-vhosts.sh y,
#             si aplica, 10-webmin.sh.
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

export DEBIAN_FRONTEND=noninteractive

paso "07b" "Verificando dependencias de Certbot"

if ! command -v certbot >/dev/null 2>&1; then
    info "Instalando certbot y python3-certbot-apache..."
    _retry=0
    while ! apt-get update -y > /tmp/apt_update_ssl.log 2>&1; do
        if grep -qEi "Could not get lock|Unable to lock" /tmp/apt_update_ssl.log; then
            if [ $_retry -ge 12 ]; then
                error "Tiempo agotado esperando el bloqueo de APT. Detalle:\n$(cat /tmp/apt_update_ssl.log)"
            fi
            advertencia "APT está bloqueado por otro proceso. Esperando 10s... ($((_retry+1))/12)"
            sleep 10
            _retry=$((_retry + 1))
        else
            error "Error actualizando APT. Detalle:\n$(cat /tmp/apt_update_ssl.log)"
        fi
    done
    
    _retry=0
    while ! apt-get install -y certbot python3-certbot-apache > /tmp/apt_install_certbot.log 2>&1; do
        if grep -qEi "Could not get lock|Unable to lock" /tmp/apt_install_certbot.log; then
            if [ $_retry -ge 12 ]; then
                error "Tiempo agotado esperando el bloqueo de APT. Detalle:\n$(cat /tmp/apt_install_certbot.log)"
            fi
            advertencia "APT está bloqueado por otro proceso. Esperando 10s... ($((_retry+1))/12)"
            sleep 10
            _retry=$((_retry + 1))
        else
            error "Error instalando certbot. Detalle:\n$(cat /tmp/apt_install_certbot.log)"
        fi
    done
    ok "Certbot instalado correctamente."
else
    ok "Certbot ya está instalado."
fi

# Lista de dominios a procesar
DOMINIOS_A_PROCESAR=()

# Extraer el host real, omitiendo posibles puertos (ej. si DOMAIN_WP tiene puerto)
extraer_host() { echo "${1%%:*}"; }

if [[ -n "${DOMAIN_WP:-}" ]]; then
    DOMINIOS_A_PROCESAR+=("$(extraer_host "$DOMAIN_WP")")
fi
if [[ -n "${DOMAIN_WP_ALIAS:-}" ]]; then
    DOMINIOS_A_PROCESAR+=("$(extraer_host "$DOMAIN_WP_ALIAS")")
fi
if [[ -n "${DOMAIN_MOODLE:-}" ]]; then
    DOMINIOS_A_PROCESAR+=("$(extraer_host "$DOMAIN_MOODLE")")
fi
if [[ -n "${DOMAIN_WEBMIN:-}" ]]; then
    DOMINIOS_A_PROCESAR+=("$(extraer_host "$DOMAIN_WEBMIN")")
fi

if [[ ${#DOMINIOS_A_PROCESAR[@]} -eq 0 ]]; then
    advertencia "No hay dominios configurados en config.env para procesar SSL."
    exit 0
fi

DOMINIOS_VALIDADOS=()

paso "07b" "Verificando resolución DNS de dominios antes de solicitar SSL"

if ! command -v host >/dev/null 2>&1; then
    apt-get install -y bind9-host >/dev/null 2>&1 || true
fi

for dom in "${DOMINIOS_A_PROCESAR[@]}"; do
    if host "$dom" >/dev/null 2>&1; then
        ok "Dominio resuelve en DNS: $dom"
        DOMINIOS_VALIDADOS+=("-d" "$dom")
    else
        advertencia "El dominio $dom NO resuelve vía DNS. Se ignorará para SSL."
    fi
done

if [[ ${#DOMINIOS_VALIDADOS[@]} -eq 0 ]]; then
    advertencia "Ningún dominio configurado resuelve vía DNS. SSL requiere que el dominio apunte a la IP pública del servidor."
    advertencia "Saltando configuración SSL de forma segura."
    exit 0
fi

paso "07b" "Solicitando certificados Let's Encrypt"

if certbot --apache --redirect --non-interactive --agree-tos -m "${SERVER_ADMIN_EMAIL:-admin@localhost}" "${DOMINIOS_VALIDADOS[@]}"; then
    ok "Certificados emitidos e instalados correctamente."
else
    error "Ocurrió un problema al solicitar el certificado con Certbot."
fi

# Extraer solo los hostnames de los argumentos -d del array DOMINIOS_VALIDADOS
# (que tiene la forma: -d dom1 -d dom2 ...)
DOMINIOS_SSL=()
for _arg in "${DOMINIOS_VALIDADOS[@]}"; do
    [[ "$_arg" != "-d" ]] && DOMINIOS_SSL+=("$_arg")
done

# --- CORRECCIÓN DE MIXED CONTENT ---
# Explicación: Moodle y WordPress se instalan usando HTTP antes de emitir los
# certificados SSL. Al forzar HTTPS en Apache, ambas plataformas intentan cargar
# assets (CSS/JS) internos vía HTTP dentro de una conexión HTTPS, provocando bloqueo
# de "mixed content" en los navegadores y rompiendo el diseño visual. Aquí 
# actualizamos sus URLs base directamente en la configuración a HTTPS para evitarlo.

if [[ -n "${DOMAIN_MOODLE:-}" && -n "${PATH_MOODLE:-}" ]]; then
    _host_moodle="$(extraer_host "$DOMAIN_MOODLE")"
    _encontrado_moodle=false
    for _dom in "${DOMINIOS_SSL[@]}"; do
        if [[ "$_dom" == "$_host_moodle" ]]; then
            _encontrado_moodle=true
            break
        fi
    done

    if $_encontrado_moodle; then
        paso "07b" "Actualizando URL base de Moodle a HTTPS (Mixed Content Fix)"
        if [[ -f "${PATH_MOODLE}/config.php" ]]; then
            sed -i "s|^\([[:space:]]*\$CFG->wwwroot[[:space:]]*=[[:space:]]*'\)http://${_host_moodle}|\1https://${_host_moodle}|" "${PATH_MOODLE}/config.php"
            sudo -u www-data php "${PATH_MOODLE}/admin/cli/purge_caches.php" >/dev/null 2>&1 || advertencia "No se pudo limpiar la caché de Moodle automáticamente."
            
            if grep -q "^[[:space:]]*\$CFG->wwwroot[[:space:]]*=[[:space:]]*'http://${_host_moodle}" "${PATH_MOODLE}/config.php"; then
                advertencia "No se pudo actualizar completamente config.php de Moodle a HTTPS."
            else
                ok "URL base de Moodle actualizada a HTTPS."
            fi
        else
            advertencia "No se encontró ${PATH_MOODLE}/config.php para actualizar la URL."
        fi
    fi
fi

if [[ -n "${DOMAIN_WP:-}" && -n "${PATH_WP:-}" ]]; then
    _host_wp="$(extraer_host "$DOMAIN_WP")"
    _encontrado_wp=false
    for _dom in "${DOMINIOS_SSL[@]}"; do
        if [[ "$_dom" == "$_host_wp" ]]; then
            _encontrado_wp=true
            break
        fi
    done

    if $_encontrado_wp; then
        paso "07b" "Actualizando URL base de WordPress a HTTPS (Mixed Content Fix)"
        if ! command -v wp >/dev/null 2>&1; then
            info "WP-CLI no encontrado. Descargando wp-cli.phar portable..."
            wget -q -O /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || advertencia "Fallo al descargar WP-CLI."
            mv /tmp/wp-cli.phar /usr/local/bin/wp || advertencia "No se pudo mover WP-CLI a /usr/local/bin/wp."
            chmod +x /usr/local/bin/wp
        fi
        
        if command -v wp >/dev/null 2>&1; then
            sudo -u www-data wp option update siteurl "https://${_host_wp}" --path="${PATH_WP}" >/dev/null 2>&1 || true
            sudo -u www-data wp option update home "https://${_host_wp}" --path="${PATH_WP}" >/dev/null 2>&1 || true
            
            _siteurl_actual=$(sudo -u www-data wp option get siteurl --path="${PATH_WP}" 2>/dev/null || echo "")
            if [[ "$_siteurl_actual" == https://* ]]; then
                ok "URL base de WordPress actualizada a HTTPS."
            else
                advertencia "No se pudo verificar la actualización de la URL en WordPress."
            fi
        else
            advertencia "WP-CLI no está disponible para actualizar la URL."
        fi
    fi
fi

paso "07b" "Validando renovación automática"
if certbot renew --dry-run >/dev/null 2>&1; then
    ok "Prueba de renovación (dry-run) completada con éxito."
else
    advertencia "La prueba de renovación falló, es posible que haya problemas en el futuro."
fi

paso "07b" "Verificando bloques VirtualHost *:443 por dominio en sites-enabled"

SITES_ENABLED_DIR="/etc/apache2/sites-enabled"
VHOST_443_ERRORS=0

for dominio in "${DOMINIOS_SSL[@]}"; do
    # Busca en cada archivo de sites-enabled si existe un bloque <VirtualHost *:443>
    # que contenga "ServerName <dominio>" dentro de ese mismo bloque (no en cualquier parte).
    # Estrategia: extraer 10 líneas tras cada VirtualHost *:443 y verificar si
    # alguna de ellas contiene el ServerName exacto del dominio.
    _encontrado=false
    for _conf_file in "${SITES_ENABLED_DIR}"/*.conf "${SITES_ENABLED_DIR}"/*; do
        [[ -f "$_conf_file" ]] || continue
        # Buscar bloques <VirtualHost *:443> y las líneas siguientes en ese archivo
        while IFS= read -r _bloque; do
            if echo "$_bloque" | grep -q "ServerName[[:space:]]\+${dominio}$"; then
                _encontrado=true
                break 2
            fi
        done < <(grep -A 10 "VirtualHost \*:443" "$_conf_file" 2>/dev/null)
    done

    if $_encontrado; then
        ok "Bloque VirtualHost *:443 con ServerName ${dominio} confirmado en sites-enabled."
    else
        advertencia "ATENCIÓN: No se encontró un bloque <VirtualHost *:443> con ServerName ${dominio} en ${SITES_ENABLED_DIR}/."
        advertencia "  El certificado puede haberse emitido pero el vhost HTTPS no está activo para ese dominio."
        advertencia "  Diagnóstico: sudo apache2ctl -S | grep ${dominio}"
        VHOST_443_ERRORS=$((VHOST_443_ERRORS + 1))
    fi
done

if [[ $VHOST_443_ERRORS -gt 0 ]]; then
    advertencia "${VHOST_443_ERRORS} dominio(s) sin bloque VirtualHost *:443 activo. Revisa manualmente con: apache2ctl -S"
else
    ok "Todos los dominios SSL tienen su VirtualHost *:443 correctamente configurado."
fi

echo "Script 07b-ssl.sh finalizado con éxito."
