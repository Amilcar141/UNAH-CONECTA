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
    apt-get update -y -qq >/dev/null 2>&1 || error "Error al actualizar índices de paquetes."
    apt-get install -y -qq ufw >/dev/null 2>&1 || error "Error al instalar UFW."
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

# Permitir HTTP (80) y HTTPS (443) prefiriendo el perfil de aplicación si existe
if ufw app list 2>/dev/null | grep -q "Apache Full"; then
    ufw allow "Apache Full" >/dev/null 2>&1 || error "Error al aplicar perfil 'Apache Full' en UFW."
else
    ufw allow 80/tcp >/dev/null 2>&1 || error "Error al permitir HTTP (80) en UFW."
    ufw allow 443/tcp >/dev/null 2>&1 || error "Error al permitir HTTPS (443) en UFW."
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
if ! echo "$UFW_STATUS" | grep -qE "(Apache Full|80/tcp.*ALLOW|443/tcp.*ALLOW)"; then
    error "Los puertos para el tráfico web (80/443) no aparecen correctamente en UFW."
fi
ok "UFW habilitado y configurado exitosamente. Reglas de entrada verificadas."

# --- Paso 3: Endurecimiento de SSH (SSHD) ---
paso "08" "Aplicando endurecimiento básico del servicio SSH (sshd_config)"

SSHD_CONF="/etc/ssh/sshd_config"
SSHD_BACKUP="/etc/ssh/sshd_config.bak.original"

if [ ! -f "$SSHD_BACKUP" ]; then
    cp "$SSHD_CONF" "$SSHD_BACKUP" || error "Error al crear el respaldo original de la configuración SSH."
    info "Se creó el respaldo original en ${SSHD_BACKUP}."
fi

# Función idempotente para editar configuraciones en sshd_config usando sed
update_ssh_config() {
    local key="$1"
    local value="$2"
    if grep -qE "^#?${key}\b" "$SSHD_CONF"; then
        sed -i -E "s/^#?${key}\b.*/${key} ${value}/" "$SSHD_CONF"
    else
        echo "${key} ${value}" >> "$SSHD_CONF"
    fi
}

info "Configurando directivas de seguridad en SSH..."
# 1. Deshabilitar inicio de sesión directo a root
update_ssh_config "PermitRootLogin" "no"

# 2. Configurar el tiempo de espera en el login (LoginGraceTime) a 30 segundos
update_ssh_config "LoginGraceTime" "30"

# 3. Actualizar el puerto si no es 22
if [[ "$SSH_PORT" != "22" ]]; then
    update_ssh_config "Port" "${SSH_PORT}"
    info "Puerto SSH cambiado a ${SSH_PORT}. (UFW ya fue adaptado a este puerto)."
fi

# 4. Manejo de la autenticación por contraseña
if [[ "${SSH_DISABLE_PASSWORD_AUTH,,}" == "true" ]]; then
    update_ssh_config "PasswordAuthentication" "no"
else
    # No se fuerza a yes ni se sobrescribe para respetar entornos mixtos, pero 
    # emitimos la advertencia exigida por requerimientos:
    advertencia "SSH_DISABLE_PASSWORD_AUTH está en false. La autenticación por contraseña sigue PERMITIDA en SSH."
fi

ok "Configuración de sshd_config actualizada."

# --- Paso 4: Validación y reinicio del servicio SSH ---
paso "08" "Validando configuración de SSH antes de recargar el servicio"

if ! sshd -t >/dev/null 2>&1; then
    advertencia "La validación de sintaxis de sshd falló tras las modificaciones."
    cp "$SSHD_BACKUP" "$SSHD_CONF"
    error "Se restauró el respaldo original (sshd_config.bak.original). Abortando para prevenir que el servidor quede inaccesible por red."
fi

ok "Sintaxis de configuración de SSH comprobada y válida."

info "Reiniciando el demonio ssh..."
systemctl restart ssh >/dev/null 2>&1 || error "Error crítico al intentar reiniciar el servicio ssh."

if systemctl is-active --quiet ssh; then
    ok "Servicio SSH reiniciado y operando con normalidad."
else
    error "CRÍTICO: El servicio SSH dejó de funcionar tras el reinicio. Debe revisar la consola provista por su nube (ej. AWS/Azure) para recuperar el control local."
fi

# --- Paso 5: Resumen final ---
paso "08" "Resumen de políticas de Seguridad"
info "--------------------------------------------------------"
info "- UFW Activo: Deniega todo tráfico entrante no explícito."
info "- UFW Excepciones: Puerto SSH (${SSH_PORT}), HTTP (80), HTTPS (443)."
info "- SSH (sshd_config):"
info "  * Puerto escucha: ${SSH_PORT}"
info "  * PermitRootLogin: no"
info "  * LoginGraceTime: 30"
if [[ "${SSH_DISABLE_PASSWORD_AUTH,,}" == "true" ]]; then
    info "  * PasswordAuthentication: no (Solo llaves SSH)"
else
    info "  * PasswordAuthentication: Mantenido activo"
fi
info "--------------------------------------------------------"

echo "Script 08-security.sh finalizado con éxito."
