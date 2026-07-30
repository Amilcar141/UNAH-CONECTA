#!/bin/bash
###############################################################################
# 05-wordpress.sh
# Proyecto: UNAH-CONECTA
# Función: Descarga, configuración e instalación desatendida de WordPress
#          mediante la utilidad WP-CLI.
# Ejecución: sudo ./05-wordpress.sh (o mediante menu.sh)
#
# VARIABLES REQUERIDAS DE config.env:
#   DOMAIN_WP, PATH_WP, DB_WP_NAME, DB_WP_USER, DB_WP_PASS
#
# VARIABLES NUEVAS A AGREGAR A config.env:
#   WP_TITLE (Título de la instalación de WordPress)
#   WP_ADMIN_USER (Nombre de usuario administrador del sitio)
#   WP_ADMIN_PASS (Contraseña del usuario administrador del sitio)
#   WP_ADMIN_EMAIL (Dirección de correo del administrador)
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

# Verificar existencia de las nuevas variables requeridas para la instalación
if [[ -z "${WP_TITLE:-}" || -z "${WP_ADMIN_USER:-}" || -z "${WP_ADMIN_PASS:-}" || -z "${WP_ADMIN_EMAIL:-}" ]]; then
    error "Faltan variables de configuración de WordPress (WP_TITLE, WP_ADMIN_USER, WP_ADMIN_PASS o WP_ADMIN_EMAIL) en config.env."
fi

# --- Paso 1: Instalación idempotente de WP-CLI ---
paso "05" "Verificando el estado de instalación de WP-CLI"

if command -v wp >/dev/null 2>&1; then
    ok "La utilidad WP-CLI ya está instalada en el sistema."
else
    info "WP-CLI no se encuentra instalado. Iniciando descarga..."
    wget -q -O /tmp/wp-cli.phar https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar || error "Fallo al descargar WP-CLI."
    
    if [ ! -s /tmp/wp-cli.phar ]; then
        error "El archivo descargado de WP-CLI está vacío o es corrupto."
    fi
    
    chmod +x /tmp/wp-cli.phar
    mv /tmp/wp-cli.phar /usr/local/bin/wp || error "No se pudo mover el ejecutable de WP-CLI a /usr/local/bin/wp."
    ok "WP-CLI instalado correctamente."
fi

# Verificar funcionamiento básico de WP-CLI
wp --info --allow-root >/dev/null 2>&1 || error "Error al validar la ejecución de WP-CLI."

# --- Paso 2: Verificación de idempotencia de la instalación de WordPress ---
paso "05" "Comprobando si WordPress ya está instalado en el directorio destino"

if [ -f "${PATH_WP}/wp-config.php" ]; then
    advertencia "WordPress ya parece estar instalado (wp-config.php detectado en ${PATH_WP}). Omitiendo el despliegue."
    exit 0
fi

# --- Paso 3: Preparación del directorio destino ---
paso "05" "Preparando el directorio de instalación"

if [ ! -d "$PATH_WP" ]; then
    mkdir -p "$PATH_WP" || error "No se pudo crear el directorio de instalación ${PATH_WP}."
    ok "Directorio ${PATH_WP} creado con éxito."
else
    # Comprobar si el directorio no está vacío
    if [ "$(ls -A "$PATH_WP")" ]; then
        # Validar si corresponde a una instalación parcial
        if [ -f "${PATH_WP}/wp-load.php" ]; then
            advertencia "El directorio de instalación no está vacío, pero se detecta una instalación parcial (wp-load.php presente). Continuando..."
        else
            error "El directorio destino ${PATH_WP} no está vacío y contiene archivos desconocidos. Abortando para evitar sobrescribir datos."
        fi
    else
        ok "Directorio destino ${PATH_WP} preparado y vacío."
    fi
fi

# --- Paso 4: Descarga del núcleo de WordPress ---
paso "05" "Descargando WordPress en español"

wp core download --path="${PATH_WP}" --locale=es_ES --allow-root >/dev/null 2>&1 || error "Error al descargar WordPress usando WP-CLI."

if [ ! -f "${PATH_WP}/wp-load.php" ]; then
    error "La descarga de WordPress falló o el archivo wp-load.php no se generó."
fi
ok "Núcleo de WordPress descargado exitosamente."

# --- Paso 5: Generación del archivo de configuración (wp-config.php) ---
paso "05" "Generando el archivo wp-config.php"

wp config create \
    --dbname="${DB_WP_NAME}" \
    --dbuser="${DB_WP_USER}" \
    --dbpass="${DB_WP_PASS}" \
    --dbhost="localhost" \
    --path="${PATH_WP}" \
    --allow-root >/dev/null 2>&1 || error "Error al generar wp-config.php. Verifique las credenciales de la base de datos."

if [ ! -f "${PATH_WP}/wp-config.php" ]; then
    error "No se pudo crear el archivo wp-config.php."
fi
ok "Archivo wp-config.php generado."

# Validar conexión real a base de datos
info "Verificando conexión activa a la base de datos..."
wp db check --path="${PATH_WP}" --allow-root >/dev/null 2>&1 || error "Fallo de conexión a la base de datos. Verifique que 03-mariadb.sh se haya ejecutado correctamente."
ok "Conexión a la base de datos validada exitosamente."

# --- Paso 6: Instalación desatendida del sitio ---
paso "05" "Ejecutando la instalación de WordPress"

wp core install \
    --url="${DOMAIN_WP}" \
    --title="${WP_TITLE}" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASS}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --path="${PATH_WP}" \
    --allow-root >/dev/null 2>&1 || error "Error durante la ejecución del comando core install de WordPress."

ok "WordPress instalado y base de datos inicializada."

# --- Paso 7: Configuración de permisos y propiedad (Seguridad) ---
paso "05" "Estableciendo la propiedad y permisos de archivos de WordPress"

# Ajustar propietario a www-data (servidor web de Apache)
chown -R www-data:www-data "$PATH_WP" || error "Error al asignar propietario a www-data en ${PATH_WP}."

# Asignar permisos diferenciados de manera recursiva
find "$PATH_WP" -type d -exec chmod 755 {} + || error "Error al asignar permisos 755 a los directorios."
find "$PATH_WP" -type f -exec chmod 644 {} + || error "Error al asignar permisos 644 a los archivos."

# Privilegio restrictivo para archivo de configuración con credenciales sensibles
chmod 600 "${PATH_WP}/wp-config.php" || error "Error al asegurar los permisos de wp-config.php."

ok "Propiedad y permisos configurados de forma segura."

# --- Paso 8: Verificación final ---
paso "05" "Validando instalación"

wp core is-installed --path="${PATH_WP}" --allow-root >/dev/null 2>&1 || error "La instalación de WordPress no se completó correctamente."
ok "Verificación de WP-CLI exitosa: WordPress está marcado como instalado."

# Validación de respuesta HTTP simulando cabecera Host de dominio
HTTP_STATUS=$(curl -I -s -o /dev/null -w "%{http_code}" -H "Host: ${DOMAIN_WP}" http://localhost || echo "000")
if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "302" ]]; then
    ok "Prueba de red local simulando Host ${DOMAIN_WP} exitosa (HTTP ${HTTP_STATUS})."
else
    advertencia "La petición HTTP local retornó código ${HTTP_STATUS}. Esto es normal si el Virtual Host correspondiente aún no está habilitado."
fi

echo "Script 05-wordpress.sh finalizado con éxito."
