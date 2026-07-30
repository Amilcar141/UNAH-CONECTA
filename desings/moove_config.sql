/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19  Distrib 10.11.14-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: moodle_db
-- ------------------------------------------------------
-- Server version	10.11.14-MariaDB-0ubuntu0.24.04.1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Dumping data for table `mdl_config_plugins`
--
-- WHERE:  plugin='theme_moove'

LOCK TABLES `mdl_config_plugins` WRITE;
/*!40000 ALTER TABLE `mdl_config_plugins` DISABLE KEYS */;
REPLACE INTO `mdl_config_plugins` VALUES
(2105,'theme_moove','brandcolor','#0A2C5C'),
(2114,'theme_moove','disableteacherspic','1'),
(2116,'theme_moove','displaymarketingbox','1'),
(2109,'theme_moove','enableclassicbreadcrumb','0'),
(2108,'theme_moove','enablecourseindex','1'),
(2122,'theme_moove','facebook',''),
(2118,'theme_moove','faqcount','0'),
(2101,'theme_moove','favicon','/favicon-unah-conecta.ico'),
(2107,'theme_moove','fontsite','Roboto'),
(2112,'theme_moove','googleanalytics',''),
(2113,'theme_moove','hvpcss',''),
(2126,'theme_moove','instagram',''),
(2124,'theme_moove','linkedin',''),
(2104,'theme_moove','loginbgimg',''),
(2100,'theme_moove','logo','/logo.png'),
(2121,'theme_moove','mail',''),
(2133,'theme_moove','marketing1content','<p>Accede a todo el material y actividades de tus asignaturas en un solo lugar</p>'),
(2132,'theme_moove','marketing1heading','Tus Cursos'),
(2131,'theme_moove','marketing1icon','/book-open-solid.png'),
(2136,'theme_moove','marketing2content','<p>Herramientas y contenido interactivo para tu formación académica</p>'),
(2135,'theme_moove','marketing2heading','Recursos Digitales'),
(2134,'theme_moove','marketing2icon','/laptop-code-solid.png'),
(2139,'theme_moove','marketing3content','<p>Desarrolla las competencias que el mercado laboral demanda hoy</p>'),
(2138,'theme_moove','marketing3heading','Preparación Profesional'),
(2137,'theme_moove','marketing3icon','/briefcase-solid.png'),
(2142,'theme_moove','marketing4content','<p>Conecta con estudiantes, tutores y docentes de toda la UNAH</p>'),
(2141,'theme_moove','marketing4heading','Comunidad Académica'),
(2140,'theme_moove','marketing4icon','/users-solid.png'),
(2130,'theme_moove','marketingcontent','<p>Plataforma educativa institucional de la Universidad Nacional Autónoma de Honduras.<br>Accede a tus cursos, recursos y actividades académicas.</p>'),
(2129,'theme_moove','marketingheading','UNAH CONECTA'),
(2120,'theme_moove','mobile',''),
(2117,'theme_moove','numbersfrontpage','1'),
(2143,'theme_moove','numbersfrontpagecontent','<h2>La plataforma educativa oficial de la Universidad Nacional Autónoma de Honduras. <br>Aprende, participa y crece académicamente desde un solo lugar.</h2>'),
(2102,'theme_moove','preset','default.scss'),
(2103,'theme_moove','presetfiles',''),
(2111,'theme_moove','scss',''),
(2110,'theme_moove','scsspre',''),
(2106,'theme_moove','secondarymenucolor','#0A2C5C'),
(2115,'theme_moove','slidercount','0'),
(2128,'theme_moove','telegram',''),
(2123,'theme_moove','twitter',''),
(2098,'theme_moove','version','2024100802'),
(2119,'theme_moove','website','www.unahconecta.com'),
(2127,'theme_moove','whatsapp',''),
(2125,'theme_moove','youtube','');
/*!40000 ALTER TABLE `mdl_config_plugins` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-07-30 19:45:47
