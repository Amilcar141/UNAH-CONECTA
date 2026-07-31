#!/bin/bash
###############################################################################
# deploy-all.sh
# Proyecto: UNAH-CONECTA
# Función: Orquestador para ejecutar la secuencia completa de despliegue.
#          Actualmente abarca los scripts del 01 al 11.
# Ejecución: sudo ./deploy-all.sh (o mediante menu.sh)
###############################################################################

set -euo pipefail

# Resolver directorios base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Cambiar a BASE_DIR para el conteo de pasos en helpers.sh
cd "$BASE_DIR"

# Cargar funciones de salida
source "./helpers.sh"

# Verificar privilegios de root/sudo al inicio
require_root

info "================================================================"
info "        Iniciando despliegue completo de UNAH-CONECTA"
info "================================================================"

# Lista de scripts a ejecutar secuencialmente
SCRIPTS_A_EJECUTAR=(
    "01-update.sh"
    "02-apache.sh"
    "03-mariadb.sh"
    "04-php.sh"
    "05-wordpress.sh"
    "06-moodle.sh"
    "07-vhosts.sh"
    "08-security.sh"
    "09-backup.sh"
    "10-webmin.sh"
    "11-monitor.sh"
)

# Iterar sobre cada script y ejecutarlo de forma aislada para detenerse en caso de error
for script in "${SCRIPTS_A_EJECUTAR[@]}"; do
    script_path="${SCRIPT_DIR}/${script}"
    
    if [ -f "$script_path" ]; then
        info ">>> Iniciando: ${script}"
        
        # Ejecutar el script. Si devuelve código distinto a 0, se detiene el orquestador
        bash "$script_path" || error "El script ${script} ha fallado. Se aborta la secuencia completa."
        
        info ">>> Finalizado: ${script}"
        echo ""
    else
        error "Archivo no encontrado: ${script_path}. No se puede continuar el despliegue."
    fi
done

ok "================================================================"
ok "            Despliegue completado exitosamente"
ok "================================================================"
