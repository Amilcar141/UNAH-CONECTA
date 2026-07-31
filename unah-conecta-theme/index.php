<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo('charset'); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>UNAH-CONECTA | Sistema de Gestión</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="<?php echo get_stylesheet_uri(); ?>?v=3.2">
    <?php wp_head(); ?>
</head>
<body <?php body_class(); ?>>

    <nav class="unah-navbar">
        <div class="brand">
            <!-- AQUÍ VA LA URL QUE COPIASTE -->
            <img src="<?php echo get_stylesheet_directory_uri(); ?>/UNAH-Conecta.png" alt="Logo UNAH Conecta" class="unah-logo">
        </div>
        <a href="<?php echo wp_login_url(); ?>" class="btn-login">
            <i class="fas fa-sign-in-alt"></i> Acceder al Portal
        </a>
    </nav>

    <header class="unah-hero">
        <h1>Gestión <span>Académica</span> Avanzada</h1>
        <p>Plataforma institucional para la administración de matrículas, sincronización con el Campus Virtual Moodle y emisión segura de certificaciones digitales.</p>
    </header>

    <main class="modules-section">
        <div class="unah-grid">
            <?php
                global $wpdb;
                $matricula_page_id = $wpdb->get_var("SELECT ID FROM {$wpdb->posts} WHERE post_content LIKE '%[unah_dashboard]%' AND post_status = 'publish' LIMIT 1");
                $matricula_url = $matricula_page_id ? get_permalink($matricula_page_id) : home_url('/');
            ?>
            <div class="unah-card" onclick="window.location.href='<?php echo esc_url($matricula_url); ?>'" style="cursor: pointer;">
                <div class="icon-wrapper"><i class="fas fa-id-card"></i></div>
                <h3>Matrículas e Inscripciones</h3>
                <p>Gestión automatizada de periodos académicos e inscripciones estudiantiles. Control riguroso del historial de matrículas dentro del ecosistema institucional.</p>
            </div>
            <div class="unah-card">
                <div class="icon-wrapper"><i class="fas fa-sync-alt"></i></div>
                <h3>Integración Moodle</h3>
                <p>Sincronización bidireccional mediante API. Monitoreo en tiempo real del progreso académico y calificaciones provenientes del Campus Virtual.</p>
            </div>
            <div class="unah-card">
                <div class="icon-wrapper"><i class="fas fa-certificate"></i></div>
                <h3>Certificaciones Digitales</h3>
                <p>Emisión validada de certificados mediante tecnología QR. Gestión centralizada de microcredenciales, insignias y sistema de puntaje profesional escalable.</p>
            </div>
        </div>
    </main>

    <footer class="unah-footer">
        <p>&copy; <?php echo date('Y'); ?> Universidad Nacional Autónoma de Honduras (UNAH).</p>
    </footer>

    <?php wp_footer(); ?>
</body>
</html>
