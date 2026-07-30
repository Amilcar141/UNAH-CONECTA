#!/bin/bash
#
# ==============================================================================
# 12-restore.sh
# ------------------------------------------------------------------------------
# Proyecto: UNAH-CONECTA
# Funcion:  Restaurar en un SERVIDOR NUEVO los respaldos generados por
#           09-backup.sh (bases de datos y archivos de WordPress y Moodle).
#           Script adicional, fuera de la secuencia principal de 11 scripts.
#
# Escenario de uso: clonar/migrar el sitio completo a otra instancia.
#
# REQUISITO PREVIO OBLIGATORIO:
#   El servidor destino ya debe tener ejecutados los scripts 01-08, es decir:
#   Ubuntu Server, Apache2, MariaDB, PHP, WordPress y Moodle instalados "en
#   blanco", con Virtual Hosts configurados. Este script NO instala el stack
#   base: unicamente reemplaza bases de datos y archivos con el contenido de
#   un respaldo previo.
#
# ARCHIVOS DE RESPALDO QUE ESTE SCRIPT ESPERA ENCONTRAR (ya copiados a
# RESTORE_SOURCE_DIR antes de ejecutar este script, por ejemplo via scp desde
# la PC local donde se descargaron los backups):
#   wp_db_<TIMESTAMP>.sql.gz
#   moodle_db_<TIMESTAMP>.sql.gz
#   wp_content_<TIMESTAMP>.tar.gz
#   moodledata_<TIMESTAMP>.tar.gz
#
# VARIABLE NUEVA QUE ESTE SCRIPT NECESITA EN config.env
# (agregar tambien a config.env.example):
#
#   RESTORE_SOURCE_DIR
#       Ruta en el servidor destino donde se colocan manualmente los 4
#       archivos de respaldo antes de ejecutar este script (ej. via scp).
#       Sugerido: /opt/unah-conecta/restore_incoming
#
# VARIABLES YA EXISTENTES EN config.env QUE ESTE SCRIPT UTILIZA:
#   DB_WP_NAME, PATH_WP, DB_MOODLE_NAME, PATH_MOODLE, MOODLE_DATA_DIR
#
# USO:
#   sudo ./scripts/12-restore.sh <TIMESTAMP>
#
#   <TIMESTAMP> es el sello de tiempo que identifica la corrida de respaldo a
#   restaurar, por ejemplo: 20260730_143210
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

cd "$BASE_DIR"

source "${BASE_DIR}/helpers.sh"
source "${BASE_DIR}/config.env"

require_root

# ------------------------------------------------------------------------------
# Paso 1: Validar argumento y localizar los 4 archivos de respaldo
# ------------------------------------------------------------------------------
paso "1" "Validando archivos de respaldo a restaurar"

if [ $# -ne 1 ]; then
    error "Uso: sudo ./scripts/12-restore.sh <TIMESTAMP>  (ej. 20260730_143210)"
fi

TIMESTAMP="$1"

WP_DB_GZ="${RESTORE_SOURCE_DIR}/wp_db_${TIMESTAMP}.sql.gz"
MOODLE_DB_GZ="${RESTORE_SOURCE_DIR}/moodle_db_${TIMESTAMP}.sql.gz"
WP_CONTENT_TAR="${RESTORE_SOURCE_DIR}/wp_content_${TIMESTAMP}.tar.gz"
MOODLEDATA_TAR="${RESTORE_SOURCE_DIR}/moodledata_${TIMESTAMP}.tar.gz"

for archivo in "$WP_DB_GZ" "$MOODLE_DB_GZ" "$WP_CONTENT_TAR" "$MOODLEDATA_TAR"; do
    if [ ! -s "$archivo" ]; then
        error "No se encontro (o esta vacio) el archivo esperado: ${archivo}"
    fi
done

ok "Los 4 archivos de respaldo para el timestamp ${TIMESTAMP} fueron localizados"

# ------------------------------------------------------------------------------
# Paso 2: Confirmacion explicita antes de sobrescribir datos existentes
# ------------------------------------------------------------------------------
paso "2" "Confirmacion de la operacion"

advertencia "Esta operacion SOBRESCRIBIRA las bases de datos ${DB_WP_NAME} y ${DB_MOODLE_NAME},"
advertencia "asi como el contenido de wp-content y moodledata en este servidor."
read -r -p "Escriba 'RESTAURAR' en mayusculas para continuar: " CONFIRMACION

if [ "$CONFIRMACION" != "RESTAURAR" ]; then
    error "Operacion cancelada por el usuario."
fi

# ------------------------------------------------------------------------------
# Paso 3: Restaurar base de datos de WordPress
# ------------------------------------------------------------------------------
paso "3" "Restaurando base de datos de WordPress"

WP_DB_SQL_TMP="$(mktemp)"
gunzip -c "$WP_DB_GZ" > "$WP_DB_SQL_TMP"

if ! grep -q "CREATE TABLE" "$WP_DB_SQL_TMP"; then
    rm -f "$WP_DB_SQL_TMP"
    error "El dump de WordPress descomprimido no contiene tablas. Restauracion abortada."
fi

mysql "$DB_WP_NAME" < "$WP_DB_SQL_TMP"
rm -f "$WP_DB_SQL_TMP"

ok "Base de datos de WordPress restaurada en ${DB_WP_NAME}"

# ------------------------------------------------------------------------------
# Paso 4: Restaurar base de datos de Moodle
# ------------------------------------------------------------------------------
paso "4" "Restaurando base de datos de Moodle"

MOODLE_DB_SQL_TMP="$(mktemp)"
gunzip -c "$MOODLE_DB_GZ" > "$MOODLE_DB_SQL_TMP"

if ! grep -q "CREATE TABLE" "$MOODLE_DB_SQL_TMP"; then
    rm -f "$MOODLE_DB_SQL_TMP"
    error "El dump de Moodle descomprimido no contiene tablas. Restauracion abortada."
fi

mysql "$DB_MOODLE_NAME" < "$MOODLE_DB_SQL_TMP"
rm -f "$MOODLE_DB_SQL_TMP"

ok "Base de datos de Moodle restaurada en ${DB_MOODLE_NAME}"

# ------------------------------------------------------------------------------
# Paso 5: Restaurar archivos de WordPress (wp-content)
# ------------------------------------------------------------------------------
paso "5" "Restaurando archivos de WordPress (wp-content)"

if ! tar -tzf "$WP_CONTENT_TAR" > /dev/null 2>&1; then
    error "El archivo wp_content_${TIMESTAMP}.tar.gz esta corrupto o incompleto."
fi

if [ -d "${PATH_WP}/wp-content" ]; then
    mv "${PATH_WP}/wp-content" "${PATH_WP}/wp-content_previo_$(date +%Y%m%d_%H%M%S)"
fi

tar -xzf "$WP_CONTENT_TAR" -C "$PATH_WP"

chown -R www-data:www-data "${PATH_WP}/wp-content"

ok "Archivos de WordPress (wp-content) restaurados en ${PATH_WP}/wp-content"

# ------------------------------------------------------------------------------
# Paso 6: Restaurar archivos de Moodle (moodledata)
# ------------------------------------------------------------------------------
paso "6" "Restaurando archivos de Moodle (moodledata)"

if ! tar -tzf "$MOODLEDATA_TAR" > /dev/null 2>&1; then
    error "El archivo moodledata_${TIMESTAMP}.tar.gz esta corrupto o incompleto."
fi

if [ -d "$MOODLE_DATA_DIR" ]; then
    mv "$MOODLE_DATA_DIR" "${MOODLE_DATA_DIR}_previo_$(date +%Y%m%d_%H%M%S)"
fi

# IMPORTANTE: 09-backup.sh empaqueta moodledata con rutas relativas
# (tar -czf archivo.tar.gz -C "$MOODLE_DATA_DIR" .), por lo que hay que
# recrear el directorio destino y extraer DENTRO de el (no en su carpeta
# padre): extraer en el padre esparce los archivos sueltos ahi, mezclados
# con lo que ya exista, en vez de reconstruir moodledata/ como carpeta.
mkdir -p "$MOODLE_DATA_DIR"
tar -xzf "$MOODLEDATA_TAR" -C "$MOODLE_DATA_DIR"

chown -R www-data:www-data "$MOODLE_DATA_DIR"

ok "Archivos de Moodle (moodledata) restaurados en ${MOODLE_DATA_DIR}"

# ------------------------------------------------------------------------------
# Paso 7: Purgar caches de Moodle
# ------------------------------------------------------------------------------
paso "7" "Purgando caches de Moodle"

if [ -f "${PATH_MOODLE}/admin/cli/purge_caches.php" ]; then
    sudo -u www-data php "${PATH_MOODLE}/admin/cli/purge_caches.php"
    ok "Caches de Moodle purgadas correctamente"
else
    advertencia "No se encontro admin/cli/purge_caches.php. Purgue las caches manualmente desde el panel de Moodle."
fi

# ------------------------------------------------------------------------------
# Paso 8: Aviso final sobre pasos manuales pendientes
# ------------------------------------------------------------------------------
paso "8" "Restauracion completada"

ok "Restauracion del respaldo ${TIMESTAMP} finalizada correctamente"
info "Recuerde verificar manualmente:"
info "  - Que la URL/dominio en la tabla mdl_config coincida con este servidor"
info "  - Que wp-config.php y config.php de Moodle apunten a las credenciales de BD correctas de este servidor"
info "  - El acceso al sitio desde el navegador antes de dar la migracion por completa"