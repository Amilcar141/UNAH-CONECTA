#!/bin/bash
###############################################################################
# 04-php.sh
# Proyecto: UNAH-CONECTA
# Función: Instalación y configuración de PHP 8.3 y extensiones necesarias.
# Ejecución: sudo ./04-php.sh (o mediante menu.sh)
# NOTA DE COMPATIBILIDAD: Se ha seleccionado la versión PHP 8.3. En Ubuntu
# Server 24.04 LTS esta versión está en los repositorios nativos. Para
# garantizar la compatibilidad con Ubuntu Server 26.04 LTS (que trae PHP 8.5
# nativo, no soportado por Moodle 4.5), se utiliza el repositorio de terceros
# ppa:ondrej/php de forma idempotente, en lugar de utilizar Docker.
# Esto asegura la máxima compatibilidad comprobada para WordPress y
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
    # Solo configurar repos y actualizar índices si se va a instalar algún paquete
    if ! $PHP_INSTALADO; then
        CODENAME=$(lsb_release -sc)

        if [[ "$CODENAME" == "resolute" ]]; then
            # Ubuntu 26.04+: ppa:ondrej/php no publica paquetes para esta
            # versión: usar el repositorio packages.sury.org en su lugar.
            info "Detectado Ubuntu ${CODENAME}, configurando packages.sury.org..."
            
            if ! grep -q "packages.sury.org" /etc/apt/sources.list.d/php.list 2>/dev/null; then
                apt-get install -y -qq ca-certificates curl lsb-release >/dev/null 2>&1 || error "Error al instalar dependencias base (curl, ca-certificates)."
                curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb || error "Error al descargar la llave del repositorio sury.org."
                dpkg -i /tmp/debsuryorg-archive-keyring.deb >/dev/null 2>&1 || error "Error al instalar la llave del repositorio sury.org."
                echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ ${CODENAME} main" \
                    | tee /etc/apt/sources.list.d/php.list > /dev/null || error "Error al agregar el repositorio packages.sury.org."
                ok "Repositorio packages.sury.org configurado."
            else
                info "El repositorio packages.sury.org ya se encuentra configurado. Omitiendo."
            fi
        else
            # Ubuntu 22.04/24.04: la PPA clásica sigue funcionando normalmente.
            info "Detectado Ubuntu ${CODENAME}, asegurando repositorio ppa:ondrej/php..."
            apt-get install -y -qq software-properties-common >/dev/null 2>&1 || error "Error al instalar software-properties-common."
            
            if ! grep -q "^deb .*ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
                add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1 || error "Error al agregar el repositorio ppa:ondrej/php."
                ok "Repositorio ppa:ondrej/php agregado."
            else
                info "El repositorio ppa:ondrej/php ya se encuentra configurado. Omitiendo."
            fi
        fi
        
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

# --- Paso 5: Configurar max_input_vars en php.ini (FPM y CLI) ---
paso "04" "Configurando max_input_vars en php.ini para FPM y CLI"

ajustar_max_input_vars() {
    local ini_file="$1"
    local context="$2"

    if [ -f "$ini_file" ]; then
        # Verificar si ya está configurado exactamente en 5000 y descomentado
        if grep -qE "^max_input_vars = 5000" "$ini_file"; then
            advertencia "max_input_vars ya está configurado en 5000 en php.ini (${context}). Omitiendo modificación."
        else
            info "Ajustando max_input_vars = 5000 en php.ini (${context})..."
            # Verificar si existe la directiva comentada o sin comentar
            if ! grep -qE "^;?[[:space:]]*max_input_vars" "$ini_file"; then
                # Si no existe en absoluto, se añade dinámicamente bajo la sección [PHP]
                sed -i '/^\[PHP\]/a max_input_vars = 5000' "$ini_file"
            else
                # Utilizar exactamente el comando sed indicado en los requisitos
                sed -i 's/^;[[:space:]]*max_input_vars.*/max_input_vars = 5000/; s/^max_input_vars.*/max_input_vars = 5000/' "$ini_file"
            fi
            ok "max_input_vars configurado en php.ini (${context})."
        fi
    else
        error "No se encontró el archivo php.ini en: ${ini_file}"
    fi
}

ajustar_max_input_vars "/etc/php/${PHP_VERSION}/fpm/php.ini" "FPM"
ajustar_max_input_vars "/etc/php/${PHP_VERSION}/cli/php.ini" "CLI"

# Verificar con grep en ambos archivos que la línea exacta max_input_vars = 5000 esté presente
info "Verificando valores aplicados de max_input_vars..."
if grep -qE "^max_input_vars = 5000" "/etc/php/${PHP_VERSION}/cli/php.ini"; then
    ok "Verificación de max_input_vars para CLI en php.ini exitosa (5000)."
else
    error "La verificación de max_input_vars para CLI falló en el archivo php.ini."
fi

if grep -qE "^max_input_vars = 5000" "/etc/php/${PHP_VERSION}/fpm/php.ini"; then
    ok "Verificación de max_input_vars para FPM en php.ini exitosa (5000)."
else
    error "La verificación de max_input_vars para FPM falló en el archivo php.ini."
fi

# --- Paso 6: Habilitación y reinicio del servicio ---
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
