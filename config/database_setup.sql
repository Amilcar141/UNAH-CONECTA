-- =====================================================================
-- UNAH-CONECTA: Configuración Inicial de Base de Datos
-- Este archivo es un respaldo plano (flat file) de las sentencias SQL 
-- generadas y ejecutadas por el script 03-mariadb.sh.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Securización Inicial de MariaDB
-- ---------------------------------------------------------------------
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;

-- ---------------------------------------------------------------------
-- 2. Base de Datos y Usuario para WordPress
-- (Las credenciales mostradas corresponden a las definidas en config.env)
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS `wordpress_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'wp_user'@'localhost' IDENTIFIED BY 'WordPress1234*';
GRANT ALL PRIVILEGES ON `wordpress_db`.* TO 'wp_user'@'localhost';
FLUSH PRIVILEGES;

-- ---------------------------------------------------------------------
-- 3. Base de Datos y Usuario para Moodle
-- (Las credenciales mostradas corresponden a las definidas en config.env)
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS `moodle_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'moodle_user'@'localhost' IDENTIFIED BY 'moodle1234*';
GRANT ALL PRIVILEGES ON `moodle_db`.* TO 'moodle_user'@'localhost';
FLUSH PRIVILEGES;
