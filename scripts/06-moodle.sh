#!/bin/bash
###############################################################################
# 06-moodle.sh
# Proyecto: UNAH-CONECTA
# Función: Descarga, configuración e instalación desatendida de Moodle 4.5 LTS.
# Ejecución: sudo ./06-moodle.sh (o mediante menu.sh)
#
# VARIABLES REQUERIDAS DE config.env:
#   DOMAIN_MOODLE, PATH_MOODLE, DB_MOODLE_NAME, DB_MOODLE_USER, DB_MOODLE_PASS
#
# VARIABLES NUEVAS A AGREGAR A config.env:
#   MOODLE_DATA_DIR (Ruta de datos, FUERA del DocumentRoot, ej: /var/moodledata)
#   MOODLE_BRANCH (Rama de Git de Moodle a clonar, ej: MOODLE_405_STABLE)
#   MOODLE_SITE_NAME (Nombre del sitio Moodle)
#   MOODLE_ADMIN_USER (Nombre de usuario administrador)
#   MOODLE_ADMIN_PASS (Contraseña del administrador)
#   MOODLE_ADMIN_EMAIL (Correo del administrador)
###############################################################################

set -euo pipefail

# Resolver directorios base usando BASH_SOURCE
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Cambiar de directorio a BASE_DIR para que helpers.sh resuelva el conteo de PASOS
cd "$BASE_DIR"

# Cargar funciones de salida compartidas y variables de configuración
source "./helpers.sh"
source "./config.env"

# Verificar privilegios de root/sudo al inicio
require_root

# Configurar frontend no interactivo para evitar diálogos de apt
export DEBIAN_FRONTEND=noninteractive

# Verificar existencia de las nuevas variables requeridas para la instalación
if [[ -z "${MOODLE_DATA_DIR:-}" || -z "${MOODLE_BRANCH:-}" || -z "${MOODLE_SITE_NAME:-}" || \
      -z "${MOODLE_ADMIN_USER:-}" || -z "${MOODLE_ADMIN_PASS:-}" || -z "${MOODLE_ADMIN_EMAIL:-}" ]]; then
    error "Faltan variables requeridas de Moodle en config.env (MOODLE_DATA_DIR, MOODLE_BRANCH, etc.)."
fi

# --- Paso 1: Verificación de idempotencia ---
paso "06" "Comprobando si Moodle ya está instalado"
if [ -f "${PATH_MOODLE}/config.php" ]; then
    advertencia "Moodle ya parece estar instalado (config.php detectado en ${PATH_MOODLE}). Omitiendo el despliegue."
    exit 0
fi

# --- Paso 2: Descarga del código fuente ---
paso "06" "Descargando código fuente de Moodle (${MOODLE_BRANCH})"

if ! command -v git >/dev/null 2>&1; then
    error "La herramienta git no está instalada en el sistema."
fi

# Verificar si el directorio ya existe y no está vacío
if [ -d "$PATH_MOODLE" ] && [ "$(ls -A "$PATH_MOODLE")" ]; then
    error "El directorio destino ${PATH_MOODLE} ya existe y no está vacío. Abortando instalación."
fi

# Clonar Moodle usando la rama especificada
info "Clonando repositorio oficial de Moodle..."
git clone --branch "${MOODLE_BRANCH}" --depth 1 https://github.com/moodle/moodle.git "${PATH_MOODLE}" >/dev/null 2>&1 || error "Error al clonar el repositorio de Moodle."

if [ ! -f "${PATH_MOODLE}/version.php" ]; then
    error "El archivo version.php no se encontró tras la clonación. Descarga corrupta."
fi

# Verificar cadena de versión
if ! grep -q "4\.5" "${PATH_MOODLE}/version.php"; then
    advertencia "El archivo version.php no parece contener la versión 4.5. Puede que la rama clonada no corresponda a Moodle 4.5 LTS."
fi
ok "Código fuente de Moodle descargado correctamente."

# --- Paso 3: Preparación del directorio de datos (moodledata) ---
paso "06" "Preparando directorio de datos (moodledata)"
info "IMPORTANTE: El directorio moodledata debe residir fuera de la raíz web."

# Validación de seguridad: moodledata no debe estar dentro del webroot
REAL_PATH_MOODLE=$(realpath -m "$PATH_MOODLE")
REAL_MOODLE_DATA=$(realpath -m "$MOODLE_DATA_DIR")

if [[ "$REAL_MOODLE_DATA" == "$REAL_PATH_MOODLE"* ]]; then
    error "Por razones de seguridad, MOODLE_DATA_DIR (${MOODLE_DATA_DIR}) no puede ser un subdirectorio de PATH_MOODLE (${PATH_MOODLE})."
fi

if [ ! -d "$MOODLE_DATA_DIR" ]; then
    mkdir -p "$MOODLE_DATA_DIR" || error "Error al crear el directorio de datos ${MOODLE_DATA_DIR}."
fi

# Propietario www-data y permisos restrictivos 770 (lectura, escritura y ejecución solo para propietario y grupo)
chown www-data:www-data "$MOODLE_DATA_DIR" || error "Error al cambiar propiedad del directorio de datos."
chmod 770 "$MOODLE_DATA_DIR" || error "Error al asignar permisos 770 al directorio de datos."
ok "Directorio de datos preparado y protegido."

# --- Paso 4: Generación de config.php (Instalación no interactiva) ---
paso "06" "Iniciando instalación no interactiva de Moodle"

# Cambiar propiedad del webroot temporalmente a www-data para que pueda escribir el config.php
chown -R www-data:www-data "$PATH_MOODLE"

# Log temporal para capturar la salida del instalador de Moodle
MOODLE_INSTALL_LOG="/tmp/moodle_install_$(date +%Y%m%d%H%M%S).log"

info "Ejecutando el instalador CLI oficial de Moodle..."
info "(Esto puede tardar varios minutos durante la creación de la base de datos)"

# Se usa 'sudo -u www-data php -d' para sobreescribir php.ini en línea de comandos:
# - max_input_vars=5000   → Moodle requiere > 1500; el valor por defecto (1000) causa fallos silenciosos
# - memory_limit=256M     → Asegura suficiente memoria para el proceso de instalación
# - max_execution_time=0  → Sin límite de tiempo para el script CLI (puede tardar varios minutos)
if sudo -u www-data php \
    -d max_input_vars=5000 \
    -d memory_limit=256M \
    -d max_execution_time=0 \
    "${PATH_MOODLE}/admin/cli/install.php" \
    --non-interactive \
    --agree-license \
    --wwwroot="http://${DOMAIN_MOODLE}" \
    --dataroot="${MOODLE_DATA_DIR}" \
    --dbtype=mariadb \
    --dbhost=localhost \
    --dbname="${DB_MOODLE_NAME}" \
    --dbuser="${DB_MOODLE_USER}" \
    --dbpass="${DB_MOODLE_PASS}" \
    --fullname="${MOODLE_SITE_NAME}" \
    --shortname="UNAHCONECTA" \
    --adminuser="${MOODLE_ADMIN_USER}" \
    --adminpass="${MOODLE_ADMIN_PASS}" \
    --adminemail="${MOODLE_ADMIN_EMAIL}" \
    >"$MOODLE_INSTALL_LOG" 2>&1; then
    ok "Instalador CLI de Moodle ejecutado sin errores."
else
    # Si falló, mostrar las últimas líneas del log para diagnóstico sin inundar la terminal
    advertencia "El instalador CLI de Moodle reportó un error. Últimas líneas del log:"
    tail -n 15 "$MOODLE_INSTALL_LOG" | while IFS= read -r line; do
        info "  $line"
    done
    error "El instalador de Moodle falló. Log completo disponible en: ${MOODLE_INSTALL_LOG}"
fi

if [ ! -f "${PATH_MOODLE}/config.php" ]; then
    error "La instalación falló porque el archivo config.php no fue generado."
fi
ok "Instalación completada y archivo config.php generado."

# --- Paso 5: Configuración de permisos finales ---
paso "06" "Asegurando permisos y propiedad de archivos de Moodle"

chown -R www-data:www-data "$PATH_MOODLE" || error "Error al reasignar la propiedad a www-data."
find "$PATH_MOODLE" -type d -exec chmod 755 {} + || error "Error al asignar permisos 755 a directorios."
find "$PATH_MOODLE" -type f -exec chmod 644 {} + || error "Error al asignar permisos 644 a archivos."
chmod 600 "${PATH_MOODLE}/config.php" || error "Error al asegurar el archivo config.php."

ok "Permisos establecidos de forma segura."

# --- Paso 6: Configuración del cron para Moodle ---
paso "06" "Configurando tarea programada (cron) de Moodle"

if crontab -u www-data -l 2>/dev/null | grep -q "${PATH_MOODLE}/admin/cli/cron.php"; then
    info "El cron de Moodle ya está configurado para el usuario www-data."
else
    # Concatenar el cron existente (si lo hay) y agregar la nueva línea
    (crontab -u www-data -l 2>/dev/null || true; echo "* * * * * /usr/bin/php ${PATH_MOODLE}/admin/cli/cron.php >/dev/null 2>&1") | crontab -u www-data - || error "Error al registrar la tarea cron."
    ok "Tarea cron configurada para ejecutarse cada minuto."
fi

# --- Paso 7: Verificación Final ---
paso "06" "Validando configuración final"

if grep -q "$DB_MOODLE_NAME" "${PATH_MOODLE}/config.php"; then
    ok "El archivo config.php vincula correctamente con la base de datos (${DB_MOODLE_NAME})."
else
    error "El archivo config.php se generó pero no contiene el nombre esperado de la base de datos."
fi

if crontab -u www-data -l 2>/dev/null | grep -q "cron.php"; then
    ok "Se verificó la existencia del cron de Moodle en crontab."
else
    advertencia "La entrada del cron no se detectó. Deberá revisarse manualmente."
fi

echo "Script 06-moodle.sh finalizado con éxito."
