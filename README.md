# UNAH-CONECTA

Proyecto académico desarrollado para la asignatura **Sistemas Operativos II** de la **Universidad Nacional Autónoma de Honduras (UNAH Campus Choluteca)**. 
Este proyecto proporciona una solución completa para el despliegue automatizado, mediante Bash Scripting, de una infraestructura LAMP capaz de alojar de manera simultánea:
- **WordPress**: Para portal web.
- **Moodle 4.5**: Como plataforma virtual de aprendizaje.

## Stack Tecnológico
Todo el entorno se configura automáticamente empleando versiones específicas validadas en el código:
- **Sistema Operativo**: Ubuntu Server 26.04 LTS ("resolute").
- **Servidor Web**: Apache2.
- **Lenguaje**: PHP 8.3 (vía repositorio `packages.sury.org`).
- **Base de Datos**: MariaDB.
- **Aplicaciones**: WordPress y Moodle 4.5 LTS.
- **Administración**: Webmin.
- **Seguridad y SSL**: UFW y Let's Encrypt (Certbot).

## Arquitectura
El proyecto distribuye los servicios mediante Virtual Hosts dinámicos en Apache2. WordPress y Moodle operan bajo subdominios independientes (ej. `www.unahconecta.com` y `moodle.unahconecta.com`) pero comparten los recursos del servidor y el procesamiento vía PHP-FPM 8.3. Opcionalmente, se configura un proxy reverso para acceder a Webmin de manera segura, restringido por IP estática o dinámica (DDNS).

## Requisitos Previos
1. Una instancia de **Ubuntu Server 26.04 LTS** limpia.
2. Acceso como usuario `root` o con privilegios `sudo`.
3. Dominio propio apuntando a la IP pública del servidor (requerido si se desea activar HTTPS vía Let's Encrypt).
4. Puertos abiertos en el firewall de red/Security Group (80, 443, 22, y opcionalmente 10000 para Webmin si no se usa proxy reverso).

## Instalación Rápida
Sigue estos pasos mínimos para levantar la infraestructura utilizando el script de inicialización:

1. Descarga y ejecuta el script de inicialización (`init.sh`). Este script verificará los requisitos de hardware (RAM, Disco, CPU), preparará el directorio destino con los permisos correctos, normalmente lo enviamos a traves de scp (shh copy) directamnte a la carpeta del usuario correspondiente del servidor y lo ejecutamos de la siguiente manera:
   ```bash
   sudo bash init.sh
   ```
2. Entra a la carpeta del proyecto creada por el instalador:
   ```bash
   cd /opt/unah-conecta
   ```
3. Revisa y personaliza las variables importantes en `config.env` (generado automáticamente por `init.sh` desde la plantilla si no existía).
4. Ejecuta la instalación usando el orquestador principal:
   ```bash
   sudo ./scripts/deploy-all.sh
   ```
   *Alternativamente, puedes usar el menú interactivo con `sudo bash menu.sh` y elegir la Opción 1.*

## Configuración (`config.env`)
Antes de ejecutar los scripts, revisa el archivo `config.env`. Estas son las variables **más importantes** a configurar:

| Categoría | Variable | Tipo / Estado | Descripción / Uso |
|-----------|----------|---------------|-------------------|
| **Dominios** | `DOMAIN_WP` | Obligatoria | Dominio principal de WordPress. |
| **Dominios** | `DOMAIN_MOODLE` | Obligatoria | Dominio de Moodle. |
| **BBDD** | `DB_WP_PASS` | Obligatoria (Cambiar) | Contraseña de la base de datos de WordPress. |
| **BBDD** | `DB_MOODLE_PASS` | Obligatoria (Cambiar) | Contraseña de la base de datos de Moodle. |
| **Admin** | `WP_ADMIN_PASS` | Obligatoria (Cambiar) | Contraseña del admin de WordPress. |
| **Admin** | `MOODLE_ADMIN_PASS`| Obligatoria (Cambiar) | Contraseña del admin de Moodle. |
| **Seguridad** | `SSH_PORT` | Opcional (Def: 22) | Puerto SSH. |
| **Seguridad** | `SSH_DISABLE_PASSWORD_AUTH` | Opcional (Def: false)| Deshabilitar login por contraseña en SSH. |
| **Webmin** | `DOMAIN_WEBMIN` | Opcional | Subdominio para reverse proxy de Webmin. |
| **Webmin** | `ADMIN_IP_MODE` | Opcional (Def: static) | Modo de acceso admin: `static` o `dynamic`. |
| **Webmin** | `ADMIN_ALLOWED_IP`| Opcional | IP fija permitida si el modo es `static`. |
| **Webmin** | `ADMIN_DDNS_HOSTNAME`| Opcional | Hostname DDNS para sincronización si es `dynamic`. |

## Estructura de Scripts
El orden de despliegue definido en la secuencia principal (`helpers.sh` -> `deploy-all.sh`) es el siguiente:

| Script | Función / Descripción |
|--------|-----------------------|
| `01-update.sh` | Actualización del sistema operativo e instalación de utilidades base. |
| `02-apache.sh` | Instalación y configuración base de Apache2 con sus módulos. |
| `03-mariadb.sh` | Instalación de MariaDB, securización inicial y creación de bases de datos. |
| `04-php.sh` | Instalación y configuración de PHP 8.3 y extensiones necesarias. |
| `05-wordpress.sh` | Descarga, configuración e instalación desatendida de WordPress. |
| `06-moodle.sh` | Descarga, configuración e instalación desatendida de Moodle 4.5 LTS. |
| `07-vhosts.sh` | Generación dinámica y configuración de Virtual Hosts para Apache2. |
| `08-security.sh` | Endurecimiento de seguridad base (Configuración UFW y SSH). |
| `09-backup.sh` | Script unificado de respaldo de bases de datos y archivos esenciales. |
| `10-webmin.sh` | Instalación y configuración automática de Webmin como plataforma de administración. |
| `07b-ssl.sh` | Emisión e instalación de certificados Let's Encrypt para todos los dominios. |
| `11-monitor.sh` | Generar registros (logs) del estado del servidor. |

**Scripts Auxiliares (fuera de la secuencia principal):**
- `12-restore.sh`: Restaura un respaldo previo generado por `09-backup.sh` en un servidor nuevo.
- `save-desing.sh`: Exporta la personalización del tema de Moodle.
- `load-desing.sh`: Aplica el diseño exportado en Moodle.
- `sync-admin-ip.sh`: Sincroniza la IP administrativa por DDNS.
- `deploy-all.sh`: Orquestador global.

## Panel Interactivo
El proyecto incluye una herramienta interactiva para facilitar la gestión. Se invoca con:
```bash
sudo bash menu.sh
```
El menú está categorizado en:
- **Instalación:** Despliegue completo o por módulos aislados.
- **Mantenimiento:** Actualización y backups manuales.
- **Diagnóstico:** Verificación de servicios, dominios, logs e información del sistema.
- **Personalización Moodle:** Exportar e importar diseños.
- **Recuperación:** Herramienta de restauración de backups en otro servidor.
- **Configuración Adicional:** Gestionar Virtual Hosts, SSL, Webmin o forzar sincronización de IP.

## SSL/HTTPS
El aseguramiento de tráfico vía Let's Encrypt es **opcional**. Para que funcione exitosamente, es indispensable que los dominios especificados apunten a la IP pública del servidor antes de su ejecución. Puede activarse en la opción "Configurar SSL/TLS" del menú o ejecutando directamente el script `07b-ssl.sh`.

## Administración Remota (Webmin)
Webmin provee administración gráfica en el puerto `10000`. Puede configurarse de manera segura a través de un proxy reverso (con el subdominio `DOMAIN_WEBMIN`) y protegiendo el acceso exclusivamente a IPs autorizadas mediante `ADMIN_IP_MODE` (sea `static` fijando una IP en `ADMIN_ALLOWED_IP`, o `dynamic` usando DDNS en `ADMIN_DDNS_HOSTNAME`).

## Backup y Recuperación
El sistema incluye el script `09-backup.sh` que forma parte del ciclo principal para automatizar respaldos. Asimismo, cuenta con el script auxiliar `12-restore.sh` que facilita la migración o recuperación de bases de datos y archivos críticos en una nueva instancia.

## Estructura del Repositorio
```text
UNAH-CONECTA/
├── .git/
├── .gitignore
├── config/
├── config.env
├── desings/
├── docs/
├── helpers.sh
├── menu.sh
├── README.md
├── scripts/
│   ├── 01-update.sh
│   ├── 02-apache.sh
│   ├── 03-mariadb.sh
│   ├── 04-php.sh
│   ├── 05-wordpress.sh
│   ├── 06-moodle.sh
│   ├── 07-vhosts.sh
│   ├── 07b-ssl.sh
│   ├── 08-security.sh
│   ├── 09-backup.sh
│   ├── 10-webmin.sh
│   ├── 11-monitor.sh
│   ├── 12-restore.sh
│   ├── deploy-all.sh
│   ├── load-desing.sh
│   ├── save-desing.sh
│   └── sync-admin-ip.sh
├── systemd/
└── unah-conecta-theme/
```

## Créditos y Autores
- **Director del Proyecto:** Ph.D. Wilson Octavio Villanueva Castillo
- **Coordinador:** Amilcar A. Ponce
- **Equipo de Trabajo:** Ssamir Nuñez, Armando Alcantara, Allan Ramirez,
                         Angel David
- **Institución:** UNAH Campus Choluteca (Asignatura: Sistemas Operativos II)
- **Fecha/Versión:** 31/07/2026
- **GitHub:** https://github.com/Amilcar141/UNAH-CONECTA.git

---
*Proyecto desarrollado con fines académicos para la asignatura Sistemas Operativos II, UNAH-CURLP.*
