#!/bin/bash
###############################################################################
# 14-aplicar-diseno.sh
# Proyecto: UNAH-CONECTA
#
# Aplica en un Moodle NUEVO (con Apache2/MariaDB/PHP/Moodle ya instalados vía
# 01-08, y con theme_moove ya instalado en la misma versión) el diseño
# exportado previamente por 13-guardar-diseno.sh.
# Orden sugerido: 14 (posterior a save-desing.sh en el servidor origen)
#
# Uso: sudo ./scripts/load-desing.sh
#
# Los archivos de la exportación deben estar presentes en el repositorio,
# dentro de la ruta DISENO_EXPORT_DIR. Asegúrate de hacer git pull antes.
###############################################################################

set -euo pipefail

# --- Resolución de rutas y carga de dependencias del proyecto ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

cd "$BASE_DIR"
source "./helpers.sh"
source "./config.env"

require_root

if [[ -z "${DISENO_EXPORT_DIR:-}" ]]; then
    error "La variable DISENO_EXPORT_DIR no está definida en config.env. Agregala, ej: DISENO_EXPORT_DIR=\"/opt/unah-conecta/diseno-tema\""
fi
paso "1" "Localizando archivos de exportación"
ARCHIVO_CONFIG="${DISENO_EXPORT_DIR}/moove_config.sql"
ARCHIVO_TEMA="${DISENO_EXPORT_DIR}/theme_activo.sql"
ARCHIVO_IMAGENES="${DISENO_EXPORT_DIR}/imagenes_theme.txt"

if [[ ! -s "$ARCHIVO_CONFIG" ]]; then
    error "No se encontró (o está vacío): $ARCHIVO_CONFIG. Asegúrate de hacer git pull en el repositorio."
fi
if [[ ! -s "$ARCHIVO_TEMA" ]]; then
    error "No se encontró (o está vacío): $ARCHIVO_TEMA. Asegúrate de hacer git pull en el repositorio."
fi
ok "Archivos de exportación encontrados"

paso "2" "Verificando que theme_moove esté instalado en este servidor"
if [[ ! -d "${PATH_MOODLE}/theme/moove" ]]; then
    error "No se encontró ${PATH_MOODLE}/theme/moove. Instalá el plugin theme_moove en este servidor antes de continuar (este script no lo instala automáticamente)."
fi
ok "theme_moove está presente en ${PATH_MOODLE}/theme/moove"

paso "3" "Importando configuración de colores/ajustes de theme_moove"
MYSQL_PWD="$DB_MOODLE_PASS" mysql -u "$DB_MOODLE_USER" "$DB_MOODLE_NAME" < "$ARCHIVO_CONFIG"
ok "Configuración de theme_moove importada"

paso "4" "Activando Moove como tema del sitio"
# Se activa el tema con admin/cli/cfg.php en vez de importar directamente
# theme_activo.sql contra mdl_config. Razón: cfg.php pasa por
# la capa de configuración propia de Moodle (set_config), que además de
# escribir en mdl_config invalida correctamente la caché de configuración
# interna del sitio. Un INSERT/REPLACE crudo sobre mdl_config deja el dato
# correcto en la tabla, pero el sitio puede seguir sirviendo el valor viejo
# desde caché hasta el purge — y además cfg.php es la vía soportada
# oficialmente por Moodle vía CLI, por lo que es más robusta ante
# diferencias de versión entre el Moodle origen y el destino.
sudo -u www-data php "${PATH_MOODLE}/admin/cli/cfg.php" --name=theme --set=moove
ok "Tema activo configurado como Moove"

paso "5" "Purgando cachés de Moodle"
sudo -u www-data php "${PATH_MOODLE}/admin/cli/purge_caches.php"
ok "Cachés purgadas"

paso "6" "Diseño aplicado — pendiente paso manual de imágenes"
ok "Colores, textos y activación del tema Moove se aplicaron correctamente."
advertencia "El logo, favicon y demás imágenes del tema deben subirse MANUALMENTE desde:"
advertencia "  Administración del sitio > Apariencia > Moove"
advertencia "usando los archivos de imagen que ya tenés guardados localmente."
info "Como referencia de qué imágenes se usaron originalmente, consultá:"
info "  $ARCHIVO_IMAGENES"