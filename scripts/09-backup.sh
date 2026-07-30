#!/bin/bash
###############################################################################
# 09-backup.sh
# Proyecto: UNAH-CONECTA
# Función: Script unificado de respaldo de bases de datos y archivos esenciales
#          para las plataformas WordPress y Moodle.
# Ejecución: sudo ./09-backup.sh (o mediante menu.sh / crontab)
#
# VARIABLES REQUERIDAS DE config.env:
#   DB_WP_NAME, DB_WP_USER, DB_WP_PASS, PATH_WP
#   DB_MOODLE_NAME, DB_MOODLE_USER, DB_MOODLE_PASS, MOODLE_DATA_DIR
#   BACKUP_DIR
#
# VARIABLES NUEVAS A AGREGAR A config.env:
#   BACKUP_RETENTION_DIAS (Días a conservar los archivos de respaldo)
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

# Configurar valores por defecto si no existen
BACKUP_RETENTION_DIAS="${BACKUP_RETENTION_DIAS:-7}"

# --- Paso 1: Inicialización de variables y entorno de backups ---
paso "09" "Inicializando entorno de respaldos"

# Timestamp único compartido para toda esta corrida
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
info "Generando respaldo con identificador: ${TIMESTAMP}"

# Crear directorio de backups si no existe y asegurar permisos restrictivos
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR" || error "Error al crear el directorio de respaldos: ${BACKUP_DIR}."
fi
chmod 700 "$BACKUP_DIR" || error "Error al establecer permisos 700 en: ${BACKUP_DIR}."
ok "Directorio de respaldos verificado y protegido."

# --- Paso 2: Respaldo de la base de datos de WordPress ---
paso "09" "Realizando el dump de la base de datos de WordPress"

WP_SQL="${BACKUP_DIR}/wp_db_${TIMESTAMP}.sql"
WP_SQL_GZ="${WP_SQL}.gz"

# mysqldump con --single-transaction y --quick para eficiencia y no bloquear escrituras
mysqldump -u "${DB_WP_USER}" -p"${DB_WP_PASS}" --single-transaction --quick "${DB_WP_NAME}" > "$WP_SQL" 2>/dev/null \
    || error "Error al ejecutar mysqldump sobre la base de datos ${DB_WP_NAME}."

# Verificación de integridad básica: tamaño > 0 y presencia de CREATE TABLE
if [ ! -s "$WP_SQL" ] || ! grep -q "CREATE TABLE" "$WP_SQL"; then
    rm -f "$WP_SQL"
    error "La base de datos de WordPress no se respaldó correctamente o el archivo está corrupto."
fi

# Comprimir dump posterior a la validación
gzip -f "$WP_SQL" || error "Error al comprimir el dump de WordPress."
ok "Base de datos de WordPress respaldada y comprimida correctamente."

# --- Paso 3: Respaldo de la base de datos de Moodle ---
paso "09" "Realizando el dump de la base de datos de Moodle"

MOODLE_SQL="${BACKUP_DIR}/moodle_db_${TIMESTAMP}.sql"
MOODLE_SQL_GZ="${MOODLE_SQL}.gz"

mysqldump -u "${DB_MOODLE_USER}" -p"${DB_MOODLE_PASS}" --single-transaction --quick "${DB_MOODLE_NAME}" > "$MOODLE_SQL" 2>/dev/null \
    || error "Error al ejecutar mysqldump sobre la base de datos ${DB_MOODLE_NAME}."

# Verificación de integridad básica
if [ ! -s "$MOODLE_SQL" ] || ! grep -q "CREATE TABLE" "$MOODLE_SQL"; then
    rm -f "$MOODLE_SQL"
    error "La base de datos de Moodle no se respaldó correctamente o el archivo está corrupto."
fi

gzip -f "$MOODLE_SQL" || error "Error al comprimir el dump de Moodle."
ok "Base de datos de Moodle respaldada y comprimida correctamente."

# --- Paso 4: Respaldo de archivos de WordPress (wp-content) ---
paso "09" "Respaldando archivos de wp-content de WordPress"

WP_TAR="${BACKUP_DIR}/wp_content_${TIMESTAMP}.tar.gz"

if [ ! -d "${PATH_WP}/wp-content" ]; then
    error "No se encontró el directorio wp-content en: ${PATH_WP}."
fi

# Respaldar de manera relativa para evitar guardar rutas absolutas en el tar
tar -czf "$WP_TAR" -C "${PATH_WP}" wp-content || error "Error al comprimir wp-content."

# Validar integridad del archivo comprimido
tar -tzf "$WP_TAR" >/dev/null 2>&1 || error "El archivo comprimido wp_content_${TIMESTAMP}.tar.gz está corrupto."
ok "Archivos de WordPress (wp-content) respaldados."

# --- Paso 5: Respaldo de archivos de Moodle (moodledata) ---
paso "09" "Respaldando directorio de datos (moodledata) de Moodle"

MOODLE_TAR="${BACKUP_DIR}/moodledata_${TIMESTAMP}.tar.gz"

if [ ! -d "$MOODLE_DATA_DIR" ]; then
    error "No se encontró el directorio moodledata en: ${MOODLE_DATA_DIR}."
fi

# Comprimir moodledata de forma relativa
tar -czf "$MOODLE_TAR" -C "$(dirname "${MOODLE_DATA_DIR}")" "$(basename "${MOODLE_DATA_DIR}")" || error "Error al comprimir moodledata."

# Validar integridad
tar -tzf "$MOODLE_TAR" >/dev/null 2>&1 || error "El archivo comprimido moodledata_${TIMESTAMP}.tar.gz está corrupto."
ok "Directorio de datos de Moodle (moodledata) respaldado."

# --- Paso 6: Resumen de tamaños generados ---
paso "09" "Resumen de archivos de respaldos generados"

info "Detalle de almacenamiento de la ejecución actual:"
du -h "$WP_SQL_GZ" || true
du -h "$MOODLE_SQL_GZ" || true
du -h "$WP_TAR" || true
du -h "$MOODLE_TAR" || true

# --- Paso 7: Política de retención automática ---
paso "09" "Aplicando política de retención automática (Conservar: ${BACKUP_RETENTION_DIAS} días)"

# Obtener listado de archivos que exceden los días definidos de retención
ARCHIVOS_A_ELIMINAR=$(find "$BACKUP_DIR" -type f -mtime +"$BACKUP_RETENTION_DIAS" \
    \( -name "wp_db_*.sql.gz" -o -name "moodle_db_*.sql.gz" -o -name "wp_content_*.tar.gz" -o -name "moodledata_*.tar.gz" \) 2>/dev/null || true)

CANTIDAD_ELIMINADOS=0
if [[ -n "$ARCHIVOS_A_ELIMINAR" ]]; then
    CANTIDAD_ELIMINADOS=$(echo "$ARCHIVOS_A_ELIMINAR" | grep -v '^$' | wc -l || echo 0)
    echo "$ARCHIVOS_A_ELIMINAR" | xargs rm -f || error "Error al eliminar respaldos antiguos."
fi

info "Se eliminaron ${CANTIDAD_ELIMINADOS} archivos de respaldo antiguos."

# --- Paso 8: Verificación final ---
paso "09" "Verificación de éxito del proceso"

if [ -s "$WP_SQL_GZ" ] && [ -s "$MOODLE_SQL_GZ" ] && [ -s "$WP_TAR" ] && [ -s "$MOODLE_TAR" ]; then
    ok "Todos los archivos de respaldo se generaron correctamente y tienen tamaño mayor a 0."
else
    error "Uno o más archivos de respaldo están ausentes o vacíos."
fi

echo "Script 09-backup.sh finalizado con éxito."
