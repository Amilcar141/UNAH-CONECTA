# UNAH-CONECTA

Proyecto de automatización de infraestructura y despliegue para la Universidad Nacional Autónoma de Honduras (UNAH). 
Este repositorio automatiza la instalación, configuración y securización de una pila LAMP (Linux, Apache, MariaDB, PHP) especializada para alojar simultáneamente:
- **WordPress** (Portal Institucional y Dashboard Estudiantil).
- **Moodle 4.5 LTS** (Plataforma Virtual de Aprendizaje).

Toda la infraestructura está validada para ejecutarse sobre **Ubuntu Server 26.04 LTS**, forzando la compatibilidad a **PHP 8.3** vía el repositorio de Ondřej Surý.

## ⚙️ Estructura del Proyecto

El proyecto está diseñado de forma modular. Todos los scripts deben ejecutarse con privilegios de superusuario (`root`/`sudo`).

### 1. Variables Globales (`config.env`)
Toda la configuración del proyecto (credenciales, rutas, dominios) está centralizada en `config.env`. Antes de ejecutar el orquestador, asegúrese de editar este archivo y personalizar:
- Dominios (`DOMAIN_WP`, `DOMAIN_MOODLE`).
- Contraseñas de Base de Datos (`DB_WP_PASS`, `DB_MOODLE_PASS`).
- Contraseñas de Administración Web (`WP_ADMIN_PASS`, `MOODLE_ADMIN_PASS`).
- Contraseña para usuarios de prueba (`WP_DEMO_PASS`).
- Configuración de Firewall y Webmin (`WEBMIN_PORT`, `SSH_PORT`).

### 2. Módulos de Despliegue (`scripts/`)
1. `01-update.sh`: Actualiza la lista de paquetes del SO.
2. `02-apache.sh`: Instala Apache2 y habilita módulos (rewrite, ssl, proxy_fcgi).
3. `03-mariadb.sh`: Instala MariaDB, lo securiza, crea bases de datos y usuarios.
4. `04-php.sh`: Instala PHP 8.3 (vía ppa:ondrej/php) y extensiones requeridas por WP/Moodle.
5. `05-wordpress.sh`: Descarga WordPress vía WP-CLI, instala la base, aplica el **tema institucional**, crea el rol `alumno` y publica las páginas base.
6. `06-moodle.sh`: Despliega Moodle 4.5 estable y configura su cron.
7. `07-vhosts.sh`: Genera de forma dinámica los Virtual Hosts (vhosts) conectando Apache a PHP-FPM y activa los sitios.
8. `08-security.sh`: Configura reglas de Firewall (UFW) y endurecimiento básico.
9. `09-backup.sh`: Configura tareas automatizadas para respaldar el servidor.
10. `10-webmin.sh`: Despliega el panel de administración Webmin.
11. `11-monitor.sh`: Tarea de cron para monitorizar el estado de los servicios críticos (RAM, CPU, Disco, Apache, MariaDB).

### 3. Tema Institucional (`unah-conecta-theme/`)
El proyecto incluye un tema propio de WordPress que se instala y activa automáticamente en el paso 05. Este tema aporta:
- Formularios de login personalizados con los colores de la universidad.
- Redirección automática del rol `alumno` hacia su dashboard (ignorando wp-admin).
- Páginas creadas dinámicamente con shortcodes para ver índices académicos e inscripción de clases.

### 4. Archivos Planos y Configuración (`config/`)
Para facilitar la auditoría y el mantenimiento, los scripts del proyecto generan respaldos en archivos planos (flat files) de la configuración inyectada al sistema:
- **Base de Datos:** `config/database_setup.sql` contiene las sentencias exactas usadas en `03-mariadb.sh`.
- **Virtual Hosts:** Al ejecutarse `07-vhosts.sh`, Apache genera automáticamente copias de los archivos de configuración vhost en `config/vhosts/` (`unahconecta.conf` y `moodle.unahconecta.conf`).

## Cómo Ejecutar

El proyecto incluye dos métodos principales para el despliegue:

### Método A: Menú Interactivo
Una interfaz gráfica simple en la terminal para ejecutar partes específicas.
```bash
sudo ./menu.sh
```

### Método B: Despliegue Automatizado (Orquestador)
Ejecuta los módulos del 01 al 11 secuencialmente. Si algún módulo falla, el orquestador se detiene automáticamente.
```bash
sudo ./scripts/deploy-all.sh
```

## Logs de Instalación
Todos los módulos utilizan funciones de salida estandarizadas (`helpers.sh`). Los registros detallados de cada instalación individual se almacenan en: `/var/log/unahconecta/`. 
Puedes visualizar estos logs desde la opción 8 del menú interactivo.
