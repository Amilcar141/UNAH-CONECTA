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
    apt-get update -y >/dev/null 2>&1 || error "Error actualizando APT"
    apt-get install -y certbot python3-certbot-apache >/dev/null 2>&1 || error "Error instalando certbot"
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

paso "07b" "Validando renovación automática"
if certbot renew --dry-run >/dev/null 2>&1; then
    ok "Prueba de renovación (dry-run) completada con éxito."
else
    advertencia "La prueba de renovación falló, es posible que haya problemas en el futuro."
fi

echo "Script 07b-ssl.sh finalizado con éxito."
