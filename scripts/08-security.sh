#!/bin/bash
###############################################################################
# 08-security.sh
# Proyecto: UNAH-CONECTA
# Función: Endurecimiento de seguridad base (Configuración UFW y SSH).
# Ejecución: sudo ./08-security.sh (o mediante menu.sh)
#
# VARIABLES NUEVAS A AGREGAR A config.env:
#   SSH_PORT (Por defecto 22, permite personalizar el puerto SSH de escucha).
#   SSH_DISABLE_PASSWORD_AUTH (true/false. Controla si se prohíbe el login con
#       contraseña. Por defecto es 'false' en el entorno académico para evitar 
#       bloquear accidentalmente al equipo, pero es recomendado activarlo (true) 
#       solo si todos usan llaves SSH).
###############################################################################

set -euo pipefail

# Resolver directorios base usando BASH_SOURCE
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Cambiar de directorio a BASE_DIR para que helpers.sh resuelva el conteo de PASOS
cd "$BASE_DIR"

# Cargar funciones de salida compartidas y variables de configuración
source "./helpers.sh"
if [ -f "./config.env" ]; then
    source "./config.env"
fi

# Verificar privilegios de root/sudo al inicio
require_root

# Configurar frontend no interactivo
export DEBIAN_FRONTEND=noninteractive

# Asignar valores por defecto a variables opcionales en caso de no existir en config.env
SSH_PORT="${SSH_PORT:-22}"
SSH_DISABLE_PASSWORD_AUTH="${SSH_DISABLE_PASSWORD_AUTH:-false}"

# --- Paso 1: Verificación e Instalación de UFW ---
paso "08" "Verificando instalación del firewall UFW"

if command -v ufw >/dev/null 2>&1; then
    ok "UFW ya se encuentra instalado."
else
    info "UFW no detectado. Instalando ufw..."
    if ! apt-get update -y -qq > /tmp/apt_update_ufw.log 2>&1; then
        error "Error al actualizar índices de paquetes. Detalle:\n$(cat /tmp/apt_update_ufw.log)"
    fi
    if ! apt-get install -y -qq ufw > /tmp/apt_install_ufw.log 2>&1; then
        error "Error al instalar UFW. Detalle:\n$(cat /tmp/apt_install_ufw.log)"
    fi
    ok "UFW instalado correctamente."
fi

# --- Paso 2: Configuración e inicialización de UFW ---
paso "08" "Configurando reglas de red en el firewall UFW"

# Informar si el firewall ya estaba activo
if ufw status | grep -q "Status: active"; then
    info "UFW ya se encontraba activo. Se actualizarán las reglas requeridas."
fi

# Establecer políticas por defecto
ufw default deny incoming >/dev/null 2>&1 || error "Error al denegar tráfico entrante por defecto en UFW."
ufw default allow outgoing >/dev/null 2>&1 || error "Error al permitir tráfico saliente por defecto en UFW."

# IMPORTANTE: Se permite el puerto SSH ANTES de habilitar el firewall
info "Configurando excepciones en firewall..."
ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1 || error "Error al permitir el puerto SSH (${SSH_PORT}) en UFW."

# Permitir HTTP (80). En modo IP sin SSL no se requiere el 443.
# Se usa el perfil 'Apache' (solo 80) si existe; de lo contrario se abre 80/tcp directo.
if ufw app list 2>/dev/null | grep -qE "^  Apache$"; then
    ufw allow "Apache" >/dev/null 2>&1 || error "Error al aplicar perfil 'Apache' (HTTP 80) en UFW."
else
    ufw allow 80/tcp >/dev/null 2>&1 || error "Error al permitir HTTP (80) en UFW."
fi

# Abrir puerto extra de Moodle si usa un puerto diferente al 80
# (aplica cuando se usa IP temporal con DOMAIN_MOODLE="IP:PUERTO")
MOODLE_PUERTO="${DOMAIN_MOODLE##*:}"
if [[ "$MOODLE_PUERTO" =~ ^[0-9]+$ && "$MOODLE_PUERTO" != "80" ]]; then
    ufw allow "${MOODLE_PUERTO}/tcp" >/dev/null 2>&1 || error "Error al permitir el puerto de Moodle (${MOODLE_PUERTO}) en UFW."
    info "Puerto adicional de Moodle (${MOODLE_PUERTO}/tcp) habilitado en UFW."
fi

# Habilitar firewall de forma forzada y sin interactividad
ufw --force enable >/dev/null 2>&1 || error "Error al habilitar UFW."

# Verificar que las reglas clave están habilitadas
UFW_STATUS=$(ufw status verbose)
if ! echo "$UFW_STATUS" | grep -qE "${SSH_PORT}.*ALLOW"; then
    error "CRÍTICO: El puerto SSH (${SSH_PORT}) no aparece como ALLOW en UFW. Abortando."
fi
if ! echo "$UFW_STATUS" | grep -qE "(Apache|80/tcp.*ALLOW)"; then
    error "El puerto HTTP (80) no aparece correctamente habilitado en UFW."
fi
ok "UFW habilitado y configurado exitosamente. Reglas de entrada verificadas."

# --- Paso 3: Endurecimiento de SSH mediante archivo drop-in ---
# Ubuntu 24.04 y 26.04 usan /etc/ssh/sshd_config.d/ para sobreescribir directivas de forma
# limpia y sin editar el archivo principal con regex (que era la causa del fallo anterior).
paso "08" "Aplicando endurecimiento básico del servicio SSH"

SSHD_CONF="/etc/ssh/sshd_config"
SSHD_DROP_IN="/etc/ssh/sshd_config.d/99-unah-conecta.conf"
SSHD_BACKUP="/etc/ssh/sshd_config.bak.original"

# Crear directorio drop-in si no existe (puede no existir en instalaciones mínimas)
mkdir -p /etc/ssh/sshd_config.d

# Respaldar configuración principal original (solo la primera vez)
if [ ! -f "$SSHD_BACKUP" ]; then
    cp "$SSHD_CONF" "$SSHD_BACKUP" || error "Error al crear el respaldo original de la configuración SSH."
    info "Respaldo original creado en ${SSHD_BACKUP}."
fi

info "Generando archivo de hardening SSH en ${SSHD_DROP_IN}..."

# Escribir el archivo drop-in con las directivas de seguridad.
# Este archivo tiene prioridad sobre /etc/ssh/sshd_config al ser leído después.
cat > "$SSHD_DROP_IN" <<EOF
# UNAH-CONECTA - Hardening SSH
# Generado automáticamente por 08-security.sh
# No editar manualmente; volver a ejecutar el script para regenerar.

# Deshabilitar inicio de sesión directo como root
PermitRootLogin no

# Reducir tiempo de espera antes de desconectar un intento sin autenticar (segundos)
LoginGraceTime 30

EOF

# Agregar directiva de puerto si es diferente al 22
if [[ "$SSH_PORT" != "22" ]]; then
    echo "Port ${SSH_PORT}" >> "$SSHD_DROP_IN"
    info "Puerto SSH configurado a ${SSH_PORT} en el archivo drop-in."
fi

# Controlar autenticación por contraseña según configuración
if [[ "${SSH_DISABLE_PASSWORD_AUTH,,}" == "true" ]]; then
    echo "PasswordAuthentication no" >> "$SSHD_DROP_IN"
    info "PasswordAuthentication deshabilitada (solo llaves SSH)."
else
    advertencia "SSH_DISABLE_PASSWORD_AUTH está en false. La autenticación por contraseña sigue PERMITIDA en SSH."
fi

ok "Archivo de hardening SSH generado."

# --- Paso 4: Validación OBLIGATORIA antes de reiniciar SSH ---
paso "08" "Validando configuración de SSH antes de recargar el servicio"

# Asegurar que el directorio de separación de privilegios para SSH exista
# (sshd -t puede fallar si no existe /run/sshd en algunas configuraciones)
mkdir -p /run/sshd

# Capturar la salida de error de sshd -t para mostrarla si falla
SSHD_TEST_OUTPUT=$(sshd -t 2>&1 || true)

if ! sshd -t >/dev/null 2>&1; then
    # Mostrar el error real antes de abortar (ayuda a diagnosticar)
    advertencia "La validación de sintaxis de sshd falló. Detalle del error:"
    echo "$SSHD_TEST_OUTPUT" | while IFS= read -r line; do
        info "  $line"
    done
    # Eliminar el drop-in defectuoso para restaurar el estado original
    rm -f "$SSHD_DROP_IN"
    error "Se eliminó el archivo drop-in defectuoso. La configuración original de SSH permanece intacta."
fi

ok "Sintaxis de configuración de SSH comprobada y válida."

info "Reiniciando el demonio ssh..."
systemctl restart ssh >/dev/null 2>&1 || error "Error crítico al intentar reiniciar el servicio ssh."

if systemctl is-active --quiet ssh; then
    ok "Servicio SSH reiniciado y operando con normalidad."
else
    error "CRÍTICO: El servicio SSH dejó de funcionar tras el reinicio. Revise la consola del proveedor cloud para recuperar acceso."
fi

# --- Paso 5: Resumen final ---
paso "08" "Resumen de políticas de Seguridad aplicadas"
info "--------------------------------------------------------"
info "- UFW Activo: Deniega todo tráfico entrante no explícito."
info "- UFW Excepciones: Puerto SSH (${SSH_PORT}), HTTP (80), Moodle (${MOODLE_PUERTO})."
info "- SSH Drop-in: ${SSHD_DROP_IN}"
info "  * Puerto escucha : ${SSH_PORT}"
info "  * PermitRootLogin: no"
info "  * LoginGraceTime : 30 segundos"
if [[ "${SSH_DISABLE_PASSWORD_AUTH,,}" == "true" ]]; then
    info "  * PasswordAuthentication: no (Solo llaves SSH)"
else
    info "  * PasswordAuthentication: Habilitada (configuración académica)"
fi
info "--------------------------------------------------------"

echo "Script 08-security.sh finalizado con éxito."
