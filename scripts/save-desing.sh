#!/bin/bash
###############################################################################
# 13-guardar-diseno.sh
# Proyecto: UNAH-CONECTA
#
# Exporta la personalización del tema Moove (theme_moove) desde una instancia
# de Moodle YA CONFIGURADA, para poder reaplicarla luego en otra instancia
# nueva mediante 14-aplicar-diseno.sh.
#
# Script fuera de la secuencia principal de despliegue (01-11).
# Orden sugerido: 13 (posterior a 06-moodle.sh)
#
# VARIABLE NUEVA REQUERIDA — agregar a config.env.example:
#   DISENO_EXPORT_DIR="/opt/unah-conecta/diseno-tema"
#   # Ruta donde se guardan/leen los archivos de exportación del diseño
#   # del tema (dumps SQL y listado de imágenes).
###############################################################################

set -euo pipefail

# --- Resolución de rutas y carga de dependencias del proyecto ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# helpers.sh calcula PASOS con `find ./scripts -type f | wc -l` usando ruta
# relativa, por eso nos posicionamos en BASE_DIR antes de cargarlo.
cd "$BASE_DIR"
source "./helpers.sh"
source "./config.env"

require_root

# --- Validación de la variable nueva (no viene garantizada en todo config.env) ---
if [[ -z "${DISENO_EXPORT_DIR:-}" ]]; then
    error "La variable DISENO_EXPORT_DIR no está definida en config.env. Agregala, ej: DISENO_EXPORT_DIR=\"/opt/unah-conecta/diseno-tema\""
fi

# --- Wrapper de mysqldump: usa MYSQL_PWD scoped al comando, nunca -p en la
# línea de comandos (que quedaría visible en `ps aux` para cualquier usuario) ---
exportar_tabla() {
    local tabla="$1"
    local condicion="$2"
    local destino="$3"

    MYSQL_PWD="$DB_MOODLE_PASS" mysqldump \
        -u "$DB_MOODLE_USER" \
        --no-create-info \
        --replace \
        "$DB_MOODLE_NAME" "$tabla" \
        --where="$condicion" > "$destino"
}



paso "1" "Preparando directorio de exportación de diseño"
mkdir -p "$DISENO_EXPORT_DIR"
chmod 700 "$DISENO_EXPORT_DIR"
ok "Directorio listo: $DISENO_EXPORT_DIR"

paso "2" "Exportando configuración de colores/ajustes de theme_moove"
ARCHIVO_CONFIG="${DISENO_EXPORT_DIR}/moove_config.sql"
exportar_tabla "mdl_config_plugins" "plugin='theme_moove'" "$ARCHIVO_CONFIG"
if [[ ! -s "$ARCHIVO_CONFIG" ]]; then
    error "El export de configuración de theme_moove quedó vacío. ¿El plugin tiene ajustes guardados en mdl_config_plugins?"
fi
ok "Configuración exportada: $ARCHIVO_CONFIG"

paso "3" "Exportando el ajuste de tema activo del sitio"
ARCHIVO_TEMA="${DISENO_EXPORT_DIR}/theme_activo.sql"
exportar_tabla "mdl_config" "name='theme'" "$ARCHIVO_TEMA"
if [[ ! -s "$ARCHIVO_TEMA" ]]; then
    error "El export del tema activo quedó vacío. Verificá que exista la fila 'theme' en mdl_config."
fi
ok "Tema activo exportado: $ARCHIVO_TEMA"

paso "4" "Listando imágenes asociadas al tema (logo, favicon, fondo de login)"
ARCHIVO_IMAGENES="${DISENO_EXPORT_DIR}/imagenes_theme.txt"
MYSQL_PWD="$DB_MOODLE_PASS" mysql \
    -u "$DB_MOODLE_USER" \
    -N -B \
    "$DB_MOODLE_NAME" \
    -e "SELECT filename, component, filearea FROM mdl_files WHERE component='theme_moove' AND filesize > 0;" \
    > "$ARCHIVO_IMAGENES"

if [[ ! -s "$ARCHIVO_IMAGENES" ]]; then
    advertencia "No se detectaron imágenes registradas para theme_moove en mdl_files."
else
    info "Imágenes detectadas en el tema:"
    info "$(cat "$ARCHIVO_IMAGENES")"
fi

paso "5" "Resumen de la exportación"
info "Archivos sobreescritos en esta corrida:"
info "  - $ARCHIVO_CONFIG"
info "  - $ARCHIVO_TEMA"
info "  - $ARCHIVO_IMAGENES"

info "IMPORTANTE: este script NO puede extraer las imágenes reales (logo.png, favicon.png, etc.)"
info "porque Moodle las guarda en su File API interno (moodledata), no como archivos sueltos."
info "Conservá esas imágenes aparte, ya guardadas localmente, para subirlas manualmente en el destino."

info "El diseño actual ya se encuentra exportado en ${DISENO_EXPORT_DIR}."
info "Para publicarlo y que esté disponible en otras instancias de EC2, debes agregarlo al repositorio."
info "Recuerda ejecutar manualmente:"
info "  cd ${DISENO_EXPORT_DIR}"
info "  git add ."
info "  git commit -m \"Actualizar diseño Moodle\""
info "  git push"

ok "Exportación de diseño completada."