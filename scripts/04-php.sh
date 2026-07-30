#!/bin/bash
###############################################################################
# 04-php.sh
# Proyecto: UNAH-CONECTA
# Función: Instalación y configuración de PHP 8.3 y extensiones necesarias.
# Ejecución: sudo ./04-php.sh (o mediante menu.sh)
# NOTA DE COMPATIBILIDAD: Se ha seleccionado la versión nativa PHP 8.3 de
# los repositorios de Ubuntu Server 24.04 LTS en lugar de utilizar Docker.
# Esto asegura la máxima compatibilidad nativa comprobada para WordPress y
# Moodle 4.5 LTS corriendo sobre Apache con proxy_fcgi por socket unix.
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

# Definir la versión de PHP compartida por ambas aplicaciones
PHP_VERSION="8.3"

# --- Paso 1: Verificación de PHP Base ---
paso "04" "Verificando el estado actual de la instalación de PHP"

PHP_INSTALADO=false
if command -v php >/dev/null 2>&1; then
    VERSION_ACTUAL=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    if [[ "$VERSION_ACTUAL" == "$PHP_VERSION" ]]; then
        advertencia "PHP ${PHP_VERSION} ya está instalado y activo en el sistema. Omitiendo instalación del paquete base."
        PHP_INSTALADO=true
    else
        info "Se detectó la versión de PHP ${VERSION_ACTUAL}, pero se requiere la versión ${PHP_VERSION}."
    fi
fi

# --- Paso 2: Instalación de PHP-FPM y extensiones ---
paso "04" "Instalando paquetes y extensiones requeridas para Moodle y WordPress"

# Lista de extensiones críticas para WordPress y Moodle 4.5 LTS
EXTENSIONS=(
    "fpm"
    "cli"
    "mysql"
    "curl"
    "gd"
    "mbstring"
    "xml"
    "zip"
    "soap"
    "intl"
    "bcmath"
    "xmlrpc"
)

# Convertir la lista al nombre oficial de los paquetes de Debian/Ubuntu
PAQUETES_A_INSTALAR=()
for ext in "${EXTENSIONS[@]}"; do
    PKG_NAME="php${PHP_VERSION}-${ext}"
    if ! dpkg -s "$PKG_NAME" >/dev/null 2>&1; then
        PAQUETES_A_INSTALAR+=("$PKG_NAME")
    fi
done

if [ ${#PAQUETES_A_INSTALAR[@]} -eq 0 ]; then
    ok "Todos los paquetes y extensiones de PHP ${PHP_VERSION} ya están instalados."
else
    info "Instalando paquetes faltantes: ${PAQUETES_A_INSTALAR[*]}"
    # Solo actualizar índices si se va a instalar algún paquete
    if ! $PHP_INSTALADO; then
        apt-get update -y -qq >/dev/null 2>&1 || error "Error al actualizar índices de paquetes."
    fi
    apt-get install -y -qq "${PAQUETES_A_INSTALAR[@]}" >/dev/null 2>&1 || error "Error durante la instalación de paquetes de PHP."
    ok "Paquetes y extensiones instalados correctamente."
fi

# --- Paso 3: Verificación de módulos críticos en PHP ---
paso "04" "Validando que las extensiones críticas de PHP estén cargadas"
MODULOS_CRITICOS=(mysqli curl gd mbstring xml zip intl)
MODULOS_CARGADOS=$(php -m)

for modulo in "${MODULOS_CRITICOS[@]}"; do
    if ! echo "$MODULOS_CARGADOS" | grep -iq "^${modulo}$"; then
        error "La extensión crítica de PHP '${modulo}' no está cargada."
    fi
done
ok "Todas las extensiones críticas están cargadas y activas."

# --- Paso 4: Configuración del pool de PHP-FPM ---
paso "04" "Configurando el pool compartido de PHP-FPM"
FPM_POOL_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"

if [ -f "$FPM_POOL_CONF" ]; then
    info "Ajustando parámetros de rendimiento e incremento de límites en www.conf..."
    
    # 1. pm.max_children (Valor razonable: 15 para entornos limitados)
    if grep -q "^pm.max_children = 15" "$FPM_POOL_CONF"; then
        info "pm.max_children ya está configurado en 15."
    else
        sed -i 's/^;\?pm.max_children =.*/pm.max_children = 15/' "$FPM_POOL_CONF"
    fi

    # 2. memory_limit (Requisito para Moodle/WP: 256M)
    if grep -q "^php_admin_value\[memory_limit\] = 256M" "$FPM_POOL_CONF"; then
        info "php_admin_value[memory_limit] ya está configurado en 256M."
    else
        # Si ya existe comentada o con otro valor, la reemplaza, sino la agrega al final
        if grep -q "php_admin_value\[memory_limit\]" "$FPM_POOL_CONF"; then
            sed -i 's/^;\?php_admin_value\[memory_limit\].*/php_admin_value[memory_limit] = 256M/' "$FPM_POOL_CONF"
        else
            echo "php_admin_value[memory_limit] = 256M" >> "$FPM_POOL_CONF"
        fi
    fi

    # 3. upload_max_filesize (Requisito subir instaladores/plugins: 64M)
    if grep -q "^php_value\[upload_max_filesize\] = 64M" "$FPM_POOL_CONF"; then
        info "php_value[upload_max_filesize] ya está configurado en 64M."
    else
        # Si ya existe comentada o con otro valor, la reemplaza, sino la agrega al final
        if grep -q "php_value\[upload_max_filesize\]" "$FPM_POOL_CONF"; then
            sed -i 's/^;\?php_value\[upload_max_filesize\].*/php_value[upload_max_filesize] = 64M/' "$FPM_POOL_CONF"
        else
            echo "php_value[upload_max_filesize] = 64M" >> "$FPM_POOL_CONF"
        fi
    fi
    
    ok "Parámetros aplicados en www.conf."
else
    error "No se pudo encontrar el archivo de configuración del pool FPM: ${FPM_POOL_CONF}."
fi

# --- Paso 5: Habilitación y reinicio del servicio ---
paso "04" "Reiniciando y verificando servicio PHP-FPM"
info "Habilitando e iniciando php${PHP_VERSION}-fpm..."
systemctl enable "php${PHP_VERSION}-fpm" >/dev/null 2>&1 || error "Error al habilitar el servicio php${PHP_VERSION}-fpm."
systemctl restart "php${PHP_VERSION}-fpm" >/dev/null 2>&1 || error "Error al reiniciar el servicio php${PHP_VERSION}-fpm."

# Verificar si el servicio está activo
if systemctl is-active --quiet "php${PHP_VERSION}-fpm"; then
    ok "El servicio php${PHP_VERSION}-fpm está activo y en ejecución."
else
    error "El servicio php${PHP_VERSION}-fpm no se encuentra activo."
fi

# Verificar la existencia física del socket UNIX
SOCKET_PATH="/run/php/php${PHP_VERSION}-fpm.sock"
if [ -S "$SOCKET_PATH" ]; then
    ok "Socket de conexión localizado correctamente en: ${SOCKET_PATH}."
else
    error "No se encontró el socket de PHP-FPM en la ruta esperada: ${SOCKET_PATH}."
fi

echo "Script 04-php.sh finalizado con éxito."
