#!/bin/bash
###############################################################################
# 10-webmin.sh
# Proyecto: UNAH-CONECTA
# Función: Instalación y configuración automática de Webmin como plataforma
#          de administración remota del servidor Ubuntu.
# Ejecución: sudo ./10-webmin.sh (o mediante menu.sh)
#
# REQUISITO: Debe ejecutarse DESPUÉS de 08-security.sh (UFW debe estar activo).
#
# VARIABLES DE config.env utilizadas:
#   WEBMIN_PORT             Puerto de escucha de Webmin. Por defecto: 10000
#   DOMAIN_WEBMIN           Subdominio del reverse proxy Apache (ej. webmin.unahconecta.com)
#   SERVER_ADMIN_EMAIL      Email del administrador para el Virtual Host de Apache
#   ADMIN_IP_MODE           "static" (default) o "dynamic"
#   ADMIN_ALLOWED_IP        IP/CIDR fijo, usado si ADMIN_IP_MODE=static (puede estar vacío)
#   ADMIN_DDNS_HOSTNAME     Hostname DDNS, usado si ADMIN_IP_MODE=dynamic (puede estar vacío)
#   ADMIN_IP_SYNC_INTERVAL_MIN  Minutos entre resincronizaciones (default: 5, solo modo dynamic)
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BASE_DIR"

source "./helpers.sh"
source "./config.env"

require_root
export DEBIAN_FRONTEND=noninteractive

WEBMIN_PORT="${WEBMIN_PORT:-10000}"
ADMIN_IP_MODE="${ADMIN_IP_MODE:-static}"
ADMIN_ALLOWED_IP="${ADMIN_ALLOWED_IP:-}"
ADMIN_DDNS_HOSTNAME="${ADMIN_DDNS_HOSTNAME:-}"
ADMIN_IP_SYNC_INTERVAL_MIN="${ADMIN_IP_SYNC_INTERVAL_MIN:-5}"

###############################################################################
# resolver_ip_admin()
# Devuelve (vía stdout) la IP que debe recibir acceso administrativo a Webmin.
# Según ADMIN_IP_MODE:
#   static  → devuelve ADMIN_ALLOWED_IP (si no está vacía)
#   dynamic → resuelve ADMIN_DDNS_HOSTNAME con `host` y devuelve la primera IP
# Si la resolución falla o las variables están vacías, imprime advertencia y
# devuelve cadena vacía (sin abortar el script). Con IP vacía, Webmin queda
# accesible sin restricción de IP adicional, protegido únicamente por login.
###############################################################################
resolver_ip_admin() {
    if [[ "$ADMIN_IP_MODE" == "static" ]]; then
        if [[ -n "$ADMIN_ALLOWED_IP" ]]; then
            echo "$ADMIN_ALLOWED_IP"
        else
            advertencia "ADMIN_IP_MODE=static pero ADMIN_ALLOWED_IP está vacía. Webmin sin restricción de IP."
            echo ""
        fi
    elif [[ "$ADMIN_IP_MODE" == "dynamic" ]]; then
        if [[ -z "$ADMIN_DDNS_HOSTNAME" ]]; then
            advertencia "ADMIN_IP_MODE=dynamic pero ADMIN_DDNS_HOSTNAME está vacío. Webmin sin restricción de IP."
            echo ""
            return
        fi
        local ip_resuelta
        ip_resuelta=$(host -t A "$ADMIN_DDNS_HOSTNAME" 2>/dev/null \
            | awk '/has address/ {print $NF; exit}')
        if [[ -z "$ip_resuelta" ]]; then
            advertencia "No se pudo resolver '$ADMIN_DDNS_HOSTNAME'. Webmin sin restricción de IP."
            echo ""
        else
            echo "$ip_resuelta"
        fi
    else
        advertencia "ADMIN_IP_MODE='${ADMIN_IP_MODE}' no reconocido. Use 'static' o 'dynamic'. Webmin sin restricción de IP."
        echo ""
    fi
}

# --- Paso 1: Verificación de idempotencia ---
paso "10" "Comprobando si Webmin ya está instalado"

if dpkg -s webmin >/dev/null 2>&1; then
    advertencia "Webmin ya se encuentra instalado. Se omite la instalación del paquete, pero se revalidará su configuración."
    WEBMIN_YA_INSTALADO=true
else
    WEBMIN_YA_INSTALADO=false
fi

if [ "$WEBMIN_YA_INSTALADO" = false ]; then

    # --- Paso 2: Dependencias necesarias ---
    # NOTA: se instala vía paquete .deb directo (no por repositorio APT), ya que
    # el repositorio oficial de Webmin firma sus paquetes con una llave DSA de
    # 1024 bits, algoritmo que versiones recientes de APT/GPG rechazan por
    # política de seguridad ("untrusted public key algorithm: dsa1024"). Este
    # es un problema conocido y aún no resuelto por el proyecto Webmin.
    paso "10" "Instalando dependencias necesarias para Webmin"
    if ! apt-get update -y > /tmp/apt_update_webmin.log 2>&1; then
        error "Fallo al actualizar los repositorios APT. Detalle:\n$(cat /tmp/apt_update_webmin.log)"
    fi
    if ! apt-get install -y perl libnet-ssleay-perl openssl libauthen-pam-perl \
        libpam-runtime libio-pty-perl apt-show-versions python3 unzip curl \
        > /tmp/apt_install_webmin_deps.log 2>&1; then
        error "Error al instalar las dependencias de Webmin. Detalle:\n$(cat /tmp/apt_install_webmin_deps.log)"
    fi
    ok "Dependencias instaladas correctamente."

    # --- Paso 3: Descargar el paquete .deb oficial de Webmin ---
    paso "10" "Descargando el paquete .deb más reciente de Webmin"

    curl -fsSL https://www.webmin.com/download/deb/webmin-current.deb -o /tmp/webmin-current.deb \
        || error "No se pudo descargar el paquete .deb de Webmin."

    if [ ! -s /tmp/webmin-current.deb ]; then
        error "El paquete .deb descargado de Webmin está vacío o es corrupto."
    fi
    ok "Paquete de Webmin descargado correctamente."

    # --- Paso 4: Instalación del paquete ---
    paso "10" "Instalando el paquete Webmin"

    dpkg -i /tmp/webmin-current.deb >/dev/null 2>&1 || true
    # dpkg puede fallar por dependencias faltantes; apt-get -f las resuelve.
    if ! apt-get install -f -y > /tmp/apt_install_webmin_f.log 2>&1; then
        error "Error al resolver dependencias del paquete Webmin. Detalle:\n$(cat /tmp/apt_install_webmin_f.log)"
    fi

    dpkg -s webmin >/dev/null 2>&1 || error "El paquete Webmin no quedó instalado correctamente."
    rm -f /tmp/webmin-current.deb
    ok "Webmin instalado correctamente desde el paquete .deb oficial."
fi

# --- Paso 5: Configurar Webmin ---
paso "10" "Configurando Webmin (puerto ${WEBMIN_PORT})"

if [ -f /etc/webmin/miniserv.conf ]; then
    sed -i "s/^port=.*/port=${WEBMIN_PORT}/" /etc/webmin/miniserv.conf \
        || error "No se pudo modificar el puerto de Webmin en miniserv.conf."

    if [[ -n "${DOMAIN_WEBMIN:-}" ]]; then
        sed -i "s/^ssl=.*/ssl=0/" /etc/webmin/miniserv.conf \
            || advertencia "No se pudo modificar ssl=0 en miniserv.conf."
        info "SSL interno de Webmin deshabilitado (será manejado por el proxy Apache)."
        PROTOCOLO_INTERNO="http"
    else
        PROTOCOLO_INTERNO="https"
    fi

    # Resolver IP administrativa y aplicar en miniserv.conf (allow=)
    IP_ADMIN="$(resolver_ip_admin)"
    if [[ -n "$IP_ADMIN" ]]; then
        # allow= en miniserv.conf acepta IPs separadas por espacio; 127.0.0.1 siempre permitido
        if grep -q "^allow=" /etc/webmin/miniserv.conf; then
            sed -i "s|^allow=.*|allow=127.0.0.1 ${IP_ADMIN}|" /etc/webmin/miniserv.conf \
                || advertencia "No se pudo actualizar allow= en miniserv.conf."
        else
            echo "allow=127.0.0.1 ${IP_ADMIN}" >> /etc/webmin/miniserv.conf
        fi
        info "Restricción de acceso a Webmin activada para la IP: ${IP_ADMIN}"
    else
        info "Sin restricción de IP en miniserv.conf (Webmin protegido solo por login)."
    fi

    ok "Webmin configurado correctamente."
else
    error "No se encontró el archivo de configuración /etc/webmin/miniserv.conf. La instalación pudo haber fallado."
fi

# --- Paso 6: Habilitar e iniciar el servicio ---
paso "10" "Habilitando e iniciando el servicio Webmin"

systemctl enable webmin >/dev/null 2>&1 || error "No se pudo habilitar el servicio Webmin en el arranque."
systemctl restart webmin || error "No se pudo iniciar/reiniciar el servicio Webmin."
ok "Servicio Webmin habilitado e iniciado."

# --- Paso 7: Configuración del Reverse Proxy y UFW ---
if [[ -n "${DOMAIN_WEBMIN:-}" ]]; then
    paso "10" "Configurando Reverse Proxy para Webmin en Apache (${DOMAIN_WEBMIN})"

    # Habilitar módulos
    a2enmod proxy proxy_http >/dev/null 2>&1 || error "No se pudo habilitar proxy y proxy_http"

    # Preparar restricción por IP para el bloque <Location /> del vhost
    # Bug fix (c): usar 127.0.0.1 en lugar de localhost en ProxyPass
    # Bug fix (a): usar ${SERVER_ADMIN_EMAIL} directamente (variable ya cargada de config.env)
    if [[ -n "$IP_ADMIN" ]]; then
        ip_restriction="Require ip ${IP_ADMIN}"
        info "Restricción de acceso a Webmin activada para la IP: ${IP_ADMIN}"
    else
        advertencia "Sin IP administrativa resuelta. Webmin accesible sin restricción de IP (solo protegido por login)."
        ip_restriction="Require all granted"
    fi

    # Generar vhost
    mkdir -p "${BASE_DIR}/config/vhosts"
    cat > "${BASE_DIR}/config/vhosts/webmin.unahconecta.conf" <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN_WEBMIN}
    ServerAdmin ${SERVER_ADMIN_EMAIL}

    # Proxy a Webmin interno — se usa 127.0.0.1 explícito (no localhost) para
    # evitar problemas con resolución de nombre en sistemas con IPv6 dual-stack.
    # ProxyPreserveHost On: envía el header Host original al backend (ej.
    # webmin.unahconecta.com), evitando que Webmin muestre 127.0.0.1 en el login.
    ProxyPreserveHost On
    ProxyPass / http://127.0.0.1:${WEBMIN_PORT}/
    ProxyPassReverse / http://127.0.0.1:${WEBMIN_PORT}/

    <Location />
        # Capa adicional de seguridad para un panel de administración root
        ${ip_restriction}
    </Location>

    ErrorLog \${APACHE_LOG_DIR}/webmin_error.log
    CustomLog \${APACHE_LOG_DIR}/webmin_access.log combined
</VirtualHost>
EOF

    desplegar_y_habilitar "webmin.unahconecta.conf"

    systemctl reload apache2 >/dev/null 2>&1 || error "No se pudo recargar Apache tras habilitar proxy."
    ok "Reverse proxy configurado."

    paso "10" "Cerrando el puerto directo de Webmin (${WEBMIN_PORT}/tcp) en UFW"
    if command -v ufw >/dev/null 2>&1; then
        ufw delete allow "${WEBMIN_PORT}/tcp" >/dev/null 2>&1 || true
        ok "Acceso directo cerrado. Webmin es accesible solo vía proxy local."
    fi
else
    # Bug fix (d): si hay IP administrativa resuelta, restringir UFW a esa IP
    paso "10" "Abriendo el puerto ${WEBMIN_PORT}/tcp en UFW"
    if command -v ufw >/dev/null 2>&1; then
        if [[ -n "$IP_ADMIN" ]]; then
            ufw allow from "${IP_ADMIN}" to any port "${WEBMIN_PORT}" proto tcp \
                >/dev/null 2>&1 || error "No se pudo abrir el puerto ${WEBMIN_PORT} en UFW para ${IP_ADMIN}."
            ok "Puerto ${WEBMIN_PORT}/tcp habilitado en UFW solo para ${IP_ADMIN}."
        else
            ufw allow "${WEBMIN_PORT}/tcp" >/dev/null 2>&1 \
                || error "No se pudo abrir el puerto ${WEBMIN_PORT} en UFW."
            ok "Puerto ${WEBMIN_PORT}/tcp habilitado en UFW (sin restricción de IP)."
        fi
    else
        advertencia "UFW no está instalado en el sistema."
    fi
fi

# --- Paso 8: Instalar unidades systemd para sincronización dinámica de IP ---
paso "10" "Verificando configuración de sincronización dinámica de IP administrativa"

if [[ "$ADMIN_IP_MODE" == "dynamic" ]]; then
    if [[ -z "$ADMIN_DDNS_HOSTNAME" ]]; then
        advertencia "ADMIN_IP_MODE=dynamic pero ADMIN_DDNS_HOSTNAME está vacío."
        advertencia "Completa ADMIN_DDNS_HOSTNAME en config.env y vuelve a ejecutar este script."
        advertencia "Las unidades systemd de sincronización NO serán instaladas."
    else
        info "Modo dinámico activado. Instalando unidades systemd de sincronización de IP..."

        local_service="${BASE_DIR}/systemd/sync-admin-ip.service"
        local_sync_script="${BASE_DIR}/scripts/sync-admin-ip.sh"

        if [[ ! -f "$local_service" ]]; then
            error "No se encontró ${BASE_DIR}/systemd/sync-admin-ip.service."
        fi

        if [[ ! -f "$local_sync_script" ]]; then
            error "No se encontró ${local_sync_script}. Es necesario para el servicio de sincronización."
        fi

        # Copiar script de sincronización a /usr/local/bin
        install -m 0755 "$local_sync_script" /usr/local/bin/sync-admin-ip.sh \
            || error "No se pudo instalar sync-admin-ip.sh en /usr/local/bin."

        # Copiar el .service
        cp "$local_service" /etc/systemd/system/sync-admin-ip.service \
            || error "No se pudo copiar sync-admin-ip.service."

        # Generar el .timer dinámicamente con el valor real de ADMIN_IP_SYNC_INTERVAL_MIN
        # (el archivo en systemd/ tiene 5min hardcodeado como documentación/plantilla;
        # aquí se genera el timer con el valor real de config.env)
        cat > /etc/systemd/system/sync-admin-ip.timer <<TIMEREOF
[Unit]
Description=UNAH-CONECTA: Timer de sincronización de IP administrativa (Webmin DDNS)

[Timer]
OnBootSec=30sec
OnUnitActiveSec=${ADMIN_IP_SYNC_INTERVAL_MIN}min
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable sync-admin-ip.timer >/dev/null 2>&1 \
            || error "No se pudo habilitar sync-admin-ip.timer."
        systemctl start sync-admin-ip.timer >/dev/null 2>&1 \
            || error "No se pudo iniciar sync-admin-ip.timer."

        ok "Unidades systemd de sincronización instaladas y activadas."
        info "El timer sincronizará la IP cada ${ADMIN_IP_SYNC_INTERVAL_MIN} minuto(s)."
    fi
else
    info "ADMIN_IP_MODE=${ADMIN_IP_MODE}. No se requiere sincronización dinámica de IP."
fi

# --- Paso 9: Verificación final ---
paso "10" "Validando el funcionamiento de Webmin"

sleep 3
HTTP_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" "${PROTOCOLO_INTERNO}://localhost:${WEBMIN_PORT}/" || echo "000")

if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "401" || "$HTTP_STATUS" == "302" ]]; then
    ok "Webmin responde correctamente en localhost (HTTP ${HTTP_STATUS})."
else
    error "Webmin no respondió correctamente (HTTP ${HTTP_STATUS}). Revise el estado con: systemctl status webmin"
fi

# Bug fix (b): mostrar IP real del servidor con hostname -I en vez de fallback con DOMAIN_WP
SERVER_IP="$(hostname -I | awk '{print $1}')"

echo ""
echo "Script 10-webmin.sh finalizado con éxito."
if [[ -n "${DOMAIN_WEBMIN:-}" ]]; then
    echo "Accede a Webmin desde: http://${DOMAIN_WEBMIN}/"
else
    echo "Accede a Webmin desde: https://${SERVER_IP}:${WEBMIN_PORT}/"
fi