#!/bin/bash
###############################################################################
# 03-mariadb.sh
# Proyecto: UNAH-CONECTA
# Función: Instalación de MariaDB, securización inicial y creación de bases de 
#          datos y usuarios para WordPress y Moodle.
# Ejecución: sudo ./03-mariadb.sh (o mediante menu.sh)
# NOTA: Este script requiere que las contraseñas DB_WP_PASS y DB_MOODLE_PASS
#       estén definidas en config.env. Asegúrese de agregarlas a config.env.
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

# Validar la existencia de contraseñas de BD en las variables cargadas
if [[ -z "${DB_WP_PASS:-}" || -z "${DB_MOODLE_PASS:-}" ]]; then
    error "Las variables DB_WP_PASS y/o DB_MOODLE_PASS no están definidas en config.env."
fi

# Configurar frontend no interactivo para evitar diálogos de apt
export DEBIAN_FRONTEND=noninteractive

# Suprimir needrestart y triggers de dpkg (man-db, etc.) durante instalaciones
# NEEDRESTART_MODE=a  → responde auto a cualquier prompt de needrestart
# NEEDRESTART_SUSPEND → bloquea completamente la ejecución de needrestart
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Opciones extra de apt para suprimir la salida del pseudo-terminal de dpkg
APT_OPTS=(-y -qq -o Dpkg::Use-Pty=0 -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold")

# --- Paso 1: Instalación de MariaDB ---
paso "03" "Verificando instalación del servidor MariaDB"

if command -v mariadb >/dev/null 2>&1 || command -v mysql >/dev/null 2>&1; then
    advertencia "El servidor MariaDB ya se encuentra instalado. Omitiendo instalación del paquete."
else
    info "MariaDB no está instalado. Instalando mariadb-server y mariadb-client..."
    if ! apt-get update -y -qq -o Dpkg::Use-Pty=0 > /tmp/apt_update_mariadb.log 2>&1; then
        error "Error al actualizar índices de paquetes antes de instalar MariaDB. Detalle:\n$(cat /tmp/apt_update_mariadb.log)"
    fi
    if ! apt-get install "${APT_OPTS[@]}" mariadb-server mariadb-client > /tmp/apt_install_mariadb.log 2>&1; then
        error "Error durante la instalación de MariaDB. Detalle:\n$(cat /tmp/apt_install_mariadb.log)"
    fi
    ok "MariaDB instalado con éxito."
fi

# --- Paso 2: Habilitar y arrancar el servicio ---
paso "03" "Asegurando el estado del servicio MariaDB"
info "Habilitando e iniciando MariaDB..."
systemctl enable mariadb >/dev/null 2>&1 || error "Error al habilitar el inicio automático de MariaDB."
systemctl start mariadb >/dev/null 2>&1 || error "Error al iniciar el servicio de MariaDB."

# Verificar si el servicio está activo
if systemctl is-active --quiet mariadb; then
    ok "El servicio MariaDB está activo y ejecutándose."
else
    error "El servicio MariaDB no se encuentra activo."
fi

# --- Paso 3: Securización inicial (Equivalente no interactivo a mysql_secure_installation) ---
paso "03" "Ejecutando tareas de securización inicial de MariaDB"

# Eliminar usuarios anónimos, desactivar login root remoto y borrar base de datos test
mysql -s -e "
    DELETE FROM mysql.user WHERE User='';
    DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    DROP DATABASE IF EXISTS test;
    DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
    FLUSH PRIVILEGES;
" || error "Error al ejecutar la securización inicial de la base de datos."

ok "Securización completada con éxito."

# --- Paso 4: Creación de base de datos y usuario para WordPress ---
paso "03" "Configurando la base de datos para WordPress"

# Verificar e instalar base de datos
DB_WP_EXISTS=$(mysql -sN -e "SHOW DATABASES LIKE '${DB_WP_NAME}';")
if [[ "$DB_WP_EXISTS" == "$DB_WP_NAME" ]]; then
    advertencia "La base de datos de WordPress (${DB_WP_NAME}) ya existe."
else
    mysql -e "CREATE DATABASE \`${DB_WP_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || error "Error al crear la base de datos para WordPress."
    ok "Base de datos para WordPress (${DB_WP_NAME}) creada."
fi

# Verificar y configurar usuario e instalar privilegios
USER_WP_EXISTS=$(mysql -sN -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE User = '${DB_WP_USER}' AND Host = 'localhost');")
if [[ "$USER_WP_EXISTS" -eq 1 ]]; then
    advertencia "El usuario de WordPress (${DB_WP_USER}) ya existe. Actualizando privilegios..."
else
    mysql -e "CREATE USER '${DB_WP_USER}'@'localhost' IDENTIFIED BY '${DB_WP_PASS}';" || error "Error al crear el usuario de WordPress."
    ok "Usuario de WordPress (${DB_WP_USER}) creado."
fi

mysql -e "
    GRANT ALL PRIVILEGES ON \`${DB_WP_NAME}\`.* TO '${DB_WP_USER}'@'localhost';
    FLUSH PRIVILEGES;
" || error "Error al asignar privilegios al usuario de WordPress."
ok "Privilegios asignados correctamente sobre la base de datos de WordPress."

# --- Paso 5: Creación de base de datos y usuario para Moodle ---
paso "03" "Configurando la base de datos para Moodle"

# Verificar e instalar base de datos
DB_MOODLE_EXISTS=$(mysql -sN -e "SHOW DATABASES LIKE '${DB_MOODLE_NAME}';")
if [[ "$DB_MOODLE_EXISTS" == "$DB_MOODLE_NAME" ]]; then
    advertencia "La base de datos de Moodle (${DB_MOODLE_NAME}) ya existe."
else
    mysql -e "CREATE DATABASE \`${DB_MOODLE_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || error "Error al crear la base de datos para Moodle."
    ok "Base de datos para Moodle (${DB_MOODLE_NAME}) creada."
fi

# Verificar y configurar usuario e instalar privilegios
USER_MOODLE_EXISTS=$(mysql -sN -e "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE User = '${DB_MOODLE_USER}' AND Host = 'localhost');")
if [[ "$USER_MOODLE_EXISTS" -eq 1 ]]; then
    advertencia "El usuario de Moodle (${DB_MOODLE_USER}) ya existe. Actualizando privilegios..."
else
    mysql -e "CREATE USER '${DB_MOODLE_USER}'@'localhost' IDENTIFIED BY '${DB_MOODLE_PASS}';" || error "Error al crear el usuario de Moodle."
    ok "Usuario de Moodle (${DB_MOODLE_USER}) creado."
fi

mysql -e "
    GRANT ALL PRIVILEGES ON \`${DB_MOODLE_NAME}\`.* TO '${DB_MOODLE_USER}'@'localhost';
    FLUSH PRIVILEGES;
" || error "Error al asignar privilegios al usuario de Moodle."
ok "Privilegios asignados correctamente sobre la base de datos de Moodle."

# --- Paso 6: Verificación de conexiones de los usuarios creados ---
paso "03" "Validando el acceso de los nuevos usuarios de base de datos"

# Conexión WordPress
if mysql -u "${DB_WP_USER}" -p"${DB_WP_PASS}" -h "localhost" "${DB_WP_NAME}" -e "SELECT 1;" >/dev/null 2>&1; then
    ok "Conexión de prueba exitosa para el usuario de WordPress."
else
    error "Fallo de autenticación para el usuario de WordPress."
fi

# Conexión Moodle
if mysql -u "${DB_MOODLE_USER}" -p"${DB_MOODLE_PASS}" -h "localhost" "${DB_MOODLE_NAME}" -e "SELECT 1;" >/dev/null 2>&1; then
    ok "Conexión de prueba exitosa para el usuario de Moodle."
else
    error "Fallo de autenticación para el usuario de Moodle."
fi

echo "Script 03-mariadb.sh finalizado con éxito."
