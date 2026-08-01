#!/bin/bash
###############################################################################
# sync-admin-ip.sh
# Proyecto: UNAH-CONECTA
# Función: Sincroniza la IP administrativa (DDNS) con las reglas de acceso
#          de Webmin (miniserv.conf), el Virtual Host de Apache y UFW.
#          Solo actúa si ADMIN_IP_MODE=dynamic.
#
# Ejecución: Invocado automáticamente por sync-admin-ip.timer (systemd).
#            También puede ejecutarse manualmente: sudo bash sync-admin-ip.sh
#
# PREREQUISITOS:
#   - config.env cargado con ADMIN_DDNS_HOSTNAME y DOMAIN_WEBMIN definidos.
#   - Webmin y Apache2 instalados y activos.
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BASE_DIR"

source "./helpers.sh"
source "./config.env"

require_root

# --- Leer variables con valores por defecto ---
ADMIN_IP_MODE="${ADMIN_IP_MODE:-static}"
ADMIN_DDNS_HOSTNAME="${ADMIN_DDNS_HOSTNAME:-}"
WEBMIN_PORT="${WEBMIN_PORT:-10000}"
DOMAIN_WEBMIN="${DOMAIN_WEBMIN:-}"

# Solo actúa en modo dynamic
if [[ "$ADMIN_IP_MODE" != "dynamic" ]]; then
    info "ADMIN_IP_MODE=${ADMIN_IP_MODE}. Este script solo actúa en modo 'dynamic'. Saliendo."
    exit 0
fi

if [[ -z "$ADMIN_DDNS_HOSTNAME" ]]; then
    advertencia "ADMIN_DDNS_HOSTNAME está vacío. No hay nada que resolver. Saliendo."
    exit 0
fi

# --- Directorio y archivo de caché ---
CACHE_DIR="/var/lib/unah-conecta"
CACHE_FILE="${CACHE_DIR}/admin_ip.cache"

mkdir -p "$CACHE_DIR"

# Leer IP anterior desde caché.
# CASO DE PRIMERA EJECUCIÓN: si el archivo de caché no existe, se trata
# explícitamente como "IP anterior vacía" — esto garantiza que las reglas
# se apliquen igualmente en el primer arranque y no se omitan por "sin cambios".
if [[ -f "$CACHE_FILE" ]]; then
    IP_ANTERIOR="$(cat "$CACHE_FILE" | tr -d '[:space:]')"
else
    IP_ANTERIOR=""
    info "Primera ejecución: archivo de caché no existe. Se aplicarán las reglas aunque no haya cambio previo."
fi

# --- Resolver IP actual del DDNS ---
IP_ACTUAL="$(host -t A "$ADMIN_DDNS_HOSTNAME" 2>/dev/null \
    | awk '/has address/ {print $NF; exit}')"

if [[ -z "$IP_ACTUAL" ]]; then
    advertencia "No se pudo resolver '${ADMIN_DDNS_HOSTNAME}'. Se mantienen las reglas actuales."
    exit 0
fi

# --- Comparar con IP anterior ---
if [[ "$IP_ACTUAL" == "$IP_ANTERIOR" && -n "$IP_ANTERIOR" ]]; then
    info "IP administrativa sin cambios (${IP_ACTUAL}). No se requiere actualización."
    exit 0
fi

info "IP administrativa actualizada: '${IP_ANTERIOR:-<ninguna>}' → '${IP_ACTUAL}'"

# =============================================================================
# APLICAR CAMBIOS
# =============================================================================

ERRORES=0

# --- 1. Actualizar miniserv.conf de Webmin ---
if [[ -f /etc/webmin/miniserv.conf ]]; then
    if grep -q "^allow=" /etc/webmin/miniserv.conf; then
        sed -i "s|^allow=.*|allow=127.0.0.1 ${IP_ACTUAL}|" /etc/webmin/miniserv.conf \
            && info "miniserv.conf actualizado con allow=127.0.0.1 ${IP_ACTUAL}" \
            || { advertencia "Fallo al actualizar allow= en miniserv.conf."; ERRORES=$((ERRORES+1)); }
    else
        echo "allow=127.0.0.1 ${IP_ACTUAL}" >> /etc/webmin/miniserv.conf \
            && info "allow= agregado en miniserv.conf: 127.0.0.1 ${IP_ACTUAL}" \
            || { advertencia "Fallo al agregar allow= en miniserv.conf."; ERRORES=$((ERRORES+1)); }
    fi

    systemctl restart webmin >/dev/null 2>&1 \
        && info "Webmin reiniciado correctamente." \
        || { advertencia "Fallo al reiniciar Webmin."; ERRORES=$((ERRORES+1)); }
else
    advertencia "No se encontró /etc/webmin/miniserv.conf. Saltando actualización de Webmin."
    ERRORES=$((ERRORES+1))
fi

# --- 2. Actualizar Require ip en el Virtual Host de Apache ---
if [[ -n "$DOMAIN_WEBMIN" ]]; then
    VHOST_FILE="/etc/apache2/sites-available/webmin.unahconecta.conf"

    if [[ -f "$VHOST_FILE" ]]; then
        # Reemplazar la línea "Require ip <IP>" dentro del bloque <Location />
        # Cubre tanto "Require ip X.X.X.X" como "Require all granted"
        sed -i "s|^\(\s*\)Require ip .*|\1Require ip ${IP_ACTUAL}|" "$VHOST_FILE" \
            && info "Require ip actualizado a ${IP_ACTUAL} en ${VHOST_FILE}" \
            || { advertencia "Fallo al actualizar Require ip en ${VHOST_FILE}."; ERRORES=$((ERRORES+1)); }

        # Validar sintaxis antes de recargar — aborta con mensaje claro si es inválida
        if ! apache2ctl configtest >/dev/null 2>&1; then
            echo "ERROR: La sintaxis de Apache quedó inválida tras la actualización de ${VHOST_FILE}." >&2
            echo "Se reversa el cambio para no dejar el sistema en estado roto." >&2
            # Revertir: restaurar la IP anterior (o "Require all granted" si no había)
            if [[ -n "$IP_ANTERIOR" ]]; then
                sed -i "s|^\(\s*\)Require ip .*|\1Require ip ${IP_ANTERIOR}|" "$VHOST_FILE"
            else
                sed -i "s|^\(\s*\)Require ip .*|\1Require all granted|" "$VHOST_FILE"
            fi
            echo "Se restauró la configuración anterior. Revisa ${VHOST_FILE} manualmente." >&2
            ERRORES=$((ERRORES+1))
        else
            systemctl reload apache2 >/dev/null 2>&1 \
                && info "Apache recargado correctamente." \
                || { advertencia "Fallo al recargar Apache."; ERRORES=$((ERRORES+1)); }
        fi
    else
        advertencia "No se encontró ${VHOST_FILE}. Saltando actualización del vhost."
        ERRORES=$((ERRORES+1))
    fi
fi

# --- 3. Actualizar regla de UFW (solo si NO hay DOMAIN_WEBMIN, es decir, acceso directo) ---
if [[ -z "$DOMAIN_WEBMIN" ]] && command -v ufw >/dev/null 2>&1; then
    # Solo intenta borrar la regla de la IP anterior si esa IP no está vacía.
    # Esto evita un comando `ufw delete` con IP vacía en la primera ejecución.
    if [[ -n "$IP_ANTERIOR" ]]; then
        ufw delete allow from "$IP_ANTERIOR" to any port "$WEBMIN_PORT" proto tcp \
            >/dev/null 2>&1 || true
        info "Regla UFW anterior eliminada (${IP_ANTERIOR}:${WEBMIN_PORT})."
    fi

    ufw allow from "$IP_ACTUAL" to any port "$WEBMIN_PORT" proto tcp \
        >/dev/null 2>&1 \
        && info "Nueva regla UFW agregada: ${IP_ACTUAL} → puerto ${WEBMIN_PORT}/tcp." \
        || { advertencia "Fallo al agregar regla UFW para ${IP_ACTUAL}."; ERRORES=$((ERRORES+1)); }
fi

# --- 4. Actualizar caché solo si todos los cambios fueron exitosos ---
if [[ $ERRORES -eq 0 ]]; then
    echo "$IP_ACTUAL" > "$CACHE_FILE" \
        && info "Caché actualizado: ${CACHE_FILE} → ${IP_ACTUAL}" \
        || advertencia "Fallo al actualizar el archivo de caché."
    ok "Sincronización de IP administrativa completada exitosamente (${IP_ACTUAL})."
else
    advertencia "Sincronización completada con ${ERRORES} error(es). El caché NO fue actualizado para forzar reintento en la próxima ejecución."
    exit 1
fi
