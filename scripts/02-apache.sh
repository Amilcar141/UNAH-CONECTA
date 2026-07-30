#!/bin/bash
###############################################################################
# 02-apache.sh
# Proyecto: UNAH-CONECTA
# Función: Instalación y configuración base de Apache2 con sus módulos
# Ejecución: sudo ./02-apache.sh (o mediante menu.sh)
###############################################################################

set -euo pipefail

# Resolver directorios base usando BASH_SOURCE
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Cambiar de directorio a BASE_DIR para que helpers.sh resuelva correctamente el conteo de PASOS
cd "$BASE_DIR"

# Cargar funciones de salida compartidas y variables de configuración
source "./helpers.sh"
source "./config.env"

# Verificar privilegios de root/sudo al inicio
require_root

# Configurar frontend no interactivo para evitar diálogos de apt
export DEBIAN_FRONTEND=noninteractive

# --- Paso 1: Instalación de Apache2 ---
paso "02" "Verificando estado de la instalación de Apache2"

if command -v apache2 >/dev/null 2>&1; then
    advertencia "Apache2 ya se encuentra instalado en el sistema. Omitiendo instalación."
else
    info "Apache2 no está instalado. Iniciando instalación de apache2..."
    apt-get update -y -qq || error "Error al actualizar índices de paquetes antes de instalar Apache2."
    apt-get install -y -qq apache2 || error "Error durante la instalación del paquete apache2."
    ok "Apache2 instalado con éxito."
fi

# --- Paso 2: Habilitar módulos necesarios ---
paso "02" "Habilitando módulos de Apache requeridos"
info "Habilitando módulos rewrite, proxy, proxy_fcgi y setenvif..."
a2enmod rewrite proxy proxy_fcgi setenvif >/dev/null 2>&1 || error "Error al habilitar los módulos de Apache2 con a2enmod."
ok "Módulos de Apache2 habilitados correctamente."

# --- Paso 3: Respaldo del sitio por defecto ---
paso "02" "Creando respaldo de la configuración por defecto de Apache"
DEFAULT_CONF="/etc/apache2/sites-available/000-default.conf"
BACKUP_CONF="${DEFAULT_CONF}.bak"

if [ -f "$DEFAULT_CONF" ]; then
    if [ ! -f "$BACKUP_CONF" ]; then
        cp "$DEFAULT_CONF" "$BACKUP_CONF" || error "Error al crear el respaldo de 000-default.conf."
        ok "Respaldo creado en ${BACKUP_CONF}."
    else
        advertencia "El archivo de respaldo ${BACKUP_CONF} ya existe. No se sobrescribirá."
    fi
else
    info "No se encontró el archivo de configuración por defecto para respaldar."
fi

# --- Paso 4: Validar sintaxis y reiniciar servicio ---
paso "02" "Verificando sintaxis de configuración de Apache"
if apache2ctl configtest >/dev/null 2>&1; then
    ok "Sintaxis de configuración de Apache2 válida."
else
    error "La prueba de sintaxis de Apache2 (configtest) ha fallado. Abortando reinicio."
fi

info "Habilitando y reiniciando el servicio de Apache2..."
systemctl enable apache2 >/dev/null 2>&1 || error "Error al habilitar el inicio automático de Apache2."
systemctl restart apache2 >/dev/null 2>&1 || error "Error al reiniciar el servicio Apache2."

# --- Paso 5: Verificación del estado del servicio ---
if systemctl is-active --quiet apache2; then
    ok "El servicio Apache2 está activo y ejecutándose correctamente."
else
    error "El servicio Apache2 no está activo tras intentar iniciarlo."
fi

echo "Script 02-apache.sh finalizado con éxito."
