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

# Detectar placeholder sin reemplazar
if [[ "${DOMAIN_WP:-}" == *"<IP_PUBLICA>"* ]]; then
    error "DOMAIN_WP contiene el placeholder '<IP_PUBLICA>'. Edita config.env y reemplazalo con la IP real del servidor antes de desplegar."
fi

# VARIABLES NUEVAS A AGREGAR A config.env:
#   WP_THEME_DIR  Ruta relativa desde BASE_DIR a la carpeta del tema institucional
#                 Ejemplo: WP_THEME_DIR="wp-theme/unah-conecta-theme"
if [[ -z "${WP_THEME_DIR:-}" ]]; then
    error "Falta la variable WP_THEME_DIR en config.env (ruta relativa al tema institucional, ej: wp-theme/unah-conecta-theme)."
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

# Log temporal para capturar la salida de wp core install y diagnosticar errores
WP_INSTALL_LOG="/tmp/wp_core_install_$(date +%Y%m%d%H%M%S).log"

# Se agrega http:// explicitamente porque WP-CLI con IPs puras sin esquema
# puede fallar al detectar siteurl/home. Con nombres de dominio WP-CLI lo
# infiere, con IPs no siempre lo hace.
if wp core install \
    --url="http://${DOMAIN_WP}" \
    --title="${WP_TITLE}" \
    --admin_user="${WP_ADMIN_USER}" \
    --admin_password="${WP_ADMIN_PASS}" \
    --admin_email="${WP_ADMIN_EMAIL}" \
    --path="${PATH_WP}" \
    --allow-root >"$WP_INSTALL_LOG" 2>&1; then
    ok "WordPress instalado y base de datos inicializada."
else
    advertencia "wp core install falló. Últimas líneas del log:"
    tail -n 15 "$WP_INSTALL_LOG" | while IFS= read -r line; do
        info "  $line"
    done
    error "Error durante la ejecución del comando core install de WordPress. Log completo: ${WP_INSTALL_LOG}"
fi

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

# Validación de respuesta HTTP directa por IP (sin cabecera Host de dominio)
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://${DOMAIN_WP}/" || echo "000")
if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "302" ]]; then
    ok "Prueba de red HTTP exitosa (HTTP ${HTTP_STATUS}) → http://${DOMAIN_WP}/"
else
    advertencia "La petición HTTP retornó código ${HTTP_STATUS}. Normal si el Virtual Host aún no está habilitado."
fi

# --- Paso 9: Instalación del tema institucional ---
paso "05" "Instalando el tema institucional unah-conecta-theme"

TEMA_SRC="${BASE_DIR}/${WP_THEME_DIR}"
TEMA_DEST="${PATH_WP}/wp-content/themes/unah-conecta-theme"

# Validar que la carpeta del tema exista en el repositorio
if [[ ! -d "$TEMA_SRC" ]]; then
    error "No se encontró la carpeta del tema en ${TEMA_SRC}. Verifique que el repositorio esté actualizado y que WP_THEME_DIR sea correcto."
fi

# Copiar el tema al directorio de temas de WordPress (sobreescribe si ya existe)
info "Copiando tema desde ${TEMA_SRC} hacia ${TEMA_DEST}..."
cp -r "$TEMA_SRC" "$TEMA_DEST" || error "Error al copiar el tema a ${TEMA_DEST}."

# Ajustar propietario igual que el resto de la instalación
chown -R www-data:www-data "$TEMA_DEST" || error "Error al asignar propietario www-data al tema."
find "$TEMA_DEST" -type d -exec chmod 755 {} + || error "Error al asignar permisos 755 a directorios del tema."
find "$TEMA_DEST" -type f -exec chmod 644 {} + || error "Error al asignar permisos 644 a archivos del tema."
ok "Tema copiado y permisos aplicados correctamente."

# --- Paso 10: Activación del tema institucional ---
paso "05" "Activando el tema unah-conecta-theme en WordPress"

wp theme activate unah-conecta-theme --path="${PATH_WP}" --allow-root >/dev/null 2>&1 || error "Error al activar el tema unah-conecta-theme con WP-CLI."

# Verificar que el tema quedó activo
if wp theme is-active unah-conecta-theme --path="${PATH_WP}" --allow-root >/dev/null 2>&1; then
    ok "Tema unah-conecta-theme activado y confirmado como tema activo."
else
    error "El tema fue instalado pero no quedó como activo tras wp theme activate."
fi

echo "Script 05-wordpress.sh finalizado con éxito."
