#!/bin/bash
###############################################################################
# 01-update.sh
# Proyecto: UNAH-CONECTA
# Función: Actualización del sistema operativo e instalación de utilidades base
# Ejecución: sudo ./01-update.sh (o mediante menu.sh)
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

# Suprimir needrestart y triggers de dpkg durante instalaciones
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Opciones globales de apt para suprimir la salida del pseudo-terminal de dpkg
APT_OPTS=(-y -qq -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")

# --- Paso 1: Actualizar índices de paquetes ---
paso "01" "Actualizando los índices de paquetes del repositorio"
apt-get update -y -qq -o Dpkg::Use-Pty=0 >/dev/null 2>&1 || error "Error al ejecutar apt-get update. Verifique su conexión a internet."
ok "Índices de paquetes actualizados."

# --- Paso 2: Verificar y aplicar actualizaciones de paquetes ---
paso "01" "Verificando actualizaciones pendientes del sistema"
# Obtener la lista de paquetes actualizables omitiendo la primera línea de encabezado
UPGRADABLE_LIST=$(apt list --upgradable 2>/dev/null | tail -n +2 || true)
# Filtrar líneas vacías para obtener el conteo preciso
UPGRADABLE_COUNT=$(echo "$UPGRADABLE_LIST" | grep -v '^$' | wc -l || echo 0)

if [ "$UPGRADABLE_COUNT" -eq 0 ]; then
    ok "El sistema operativo ya se encuentra actualizado (0 paquetes pendientes)."
else
    info "Se encontraron $UPGRADABLE_COUNT paquetes pendientes de actualización. Aplicando actualizaciones..."
    apt-get upgrade "${APT_OPTS[@]}" >/dev/null 2>&1 || error "Error al aplicar apt-get upgrade en el sistema."
    ok "Actualización de paquetes del sistema completada."
fi

# --- Paso 3: Instalación idempotente de utilidades base ---
paso "01" "Instalando utilidades base necesarias para el despliegue"
REQUIRED_PACKAGES=(curl wget unzip software-properties-common ca-certificates gnupg lsb-release ufw)
MISSING_PACKAGES=()

for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
    ok "Todas las utilidades base (curl, wget, unzip, etc.) ya están instaladas."
else
    info "Instalando utilidades faltantes: ${MISSING_PACKAGES[*]}"
    apt-get install "${APT_OPTS[@]}" "${MISSING_PACKAGES[@]}" >/dev/null 2>&1 || error "Error al instalar las utilidades base requeridas."
    ok "Utilidades base instaladas correctamente."
fi

# --- Paso 4: Comprobación de reinicio requerido ---
if [ -f /var/run/reboot-required ]; then
    advertencia "El sistema operativo requiere un reinicio para completar la aplicación de actualizaciones."
fi

ok "Script 01-update.sh finalizado con éxito."