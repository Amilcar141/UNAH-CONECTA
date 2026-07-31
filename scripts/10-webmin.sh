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
# VARIABLES OPCIONALES DE config.env:
#   WEBMIN_PORT (Puerto de escucha de Webmin. Por defecto: 10000)
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
    apt-get update -y >/dev/null 2>&1 || error "Fallo al actualizar los repositorios APT."
    apt-get install -y perl libnet-ssleay-perl openssl libauthen-pam-perl \
        libpam-runtime libio-pty-perl apt-show-versions python3 unzip curl \
        >/dev/null 2>&1 || error "Error al instalar las dependencias de Webmin."
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
    apt-get install -f -y >/dev/null 2>&1 || error "Error al resolver dependencias del paquete Webmin."

    dpkg -s webmin >/dev/null 2>&1 || error "El paquete Webmin no quedó instalado correctamente."
    rm -f /tmp/webmin-current.deb
    ok "Webmin instalado correctamente desde el paquete .deb oficial."
fi

# --- Paso 5: Configurar el puerto de escucha ---
paso "10" "Configurando el puerto de Webmin (${WEBMIN_PORT})"

if [ -f /etc/webmin/miniserv.conf ]; then
    sed -i "s/^port=.*/port=${WEBMIN_PORT}/" /etc/webmin/miniserv.conf \
        || error "No se pudo modificar el puerto de Webmin en miniserv.conf."
    ok "Puerto de Webmin configurado en ${WEBMIN_PORT}."
else
    error "No se encontró el archivo de configuración /etc/webmin/miniserv.conf. La instalación pudo haber fallado."
fi

# --- Paso 6: Habilitar e iniciar el servicio ---
paso "10" "Habilitando e iniciando el servicio Webmin"

systemctl enable webmin >/dev/null 2>&1 || error "No se pudo habilitar el servicio Webmin en el arranque."
systemctl restart webmin || error "No se pudo iniciar/reiniciar el servicio Webmin."
ok "Servicio Webmin habilitado e iniciado."

# --- Paso 7: Apertura del puerto en el firewall UFW ---
paso "10" "Abriendo el puerto ${WEBMIN_PORT}/tcp en UFW"

if command -v ufw >/dev/null 2>&1; then
    ufw allow "${WEBMIN_PORT}/tcp" >/dev/null 2>&1 || error "No se pudo abrir el puerto ${WEBMIN_PORT} en UFW."
    ok "Puerto ${WEBMIN_PORT}/tcp habilitado en UFW."
else
    advertencia "UFW no está instalado en el sistema. Ejecute 08-security.sh antes de este script para habilitar el firewall."
fi

# --- Paso 8: Verificación final ---
paso "10" "Validando el funcionamiento de Webmin"

sleep 3
HTTP_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" "https://localhost:${WEBMIN_PORT}/" || echo "000")

if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "401" ]]; then
    ok "Webmin responde correctamente en https://localhost:${WEBMIN_PORT}/ (HTTP ${HTTP_STATUS})."
else
    error "Webmin no respondió correctamente (HTTP ${HTTP_STATUS}). Revise el estado con: systemctl status webmin"
fi

echo "Script 10-webmin.sh finalizado con éxito."
echo "Accede a Webmin desde: https://${DOMAIN_WP:-<IP_DEL_SERVIDOR>}:${WEBMIN_PORT}/"