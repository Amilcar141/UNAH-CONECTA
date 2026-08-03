#!/bin/bash
###############################################################################
# deploy-all.sh
# Proyecto: UNAH-CONECTA
# Función: Orquestador para ejecutar la secuencia completa de despliegue.
#          Actualmente abarca los scripts del 01 al 11 (sin SSL).
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

# La lista de scripts y su orden vienen de MAIN_SEQUENCE_SCRIPTS, definida en
# helpers.sh como fuente única de verdad. No duplicar la lista aquí: si necesitas
# agregar, eliminar o reordenar un script, hazlo solo en helpers.sh.
SCRIPTS_A_EJECUTAR=("${MAIN_SEQUENCE_SCRIPTS[@]}")

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
