<!DOCTYPE html>
<html <?php language_attributes(); ?>>
<head>
    <meta charset="<?php bloginfo('charset'); ?>">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title><?php the_title(); ?> | UNAH-CONECTA</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <link rel="stylesheet" href="<?php echo get_stylesheet_uri(); ?>">
    <?php wp_head(); ?>
</head>
<body <?php body_class(); ?> style="background-color: #f9fafb; display: flex; flex-direction: column; min-height: 100vh;">

    <!-- Barra de Navegación Simplificada -->
    <nav class="unah-navbar">
        <div class="brand">
            <img src="<?php echo get_stylesheet_directory_uri(); ?>/UNAH-Conecta.png" alt="Logo UNAH Conecta" class="unah-logo">
        </div>
        <a href="<?php echo home_url(); ?>" class="btn-login" style="background-color: #4b5563;">
            <i class="fas fa-arrow-left"></i> Volver al Inicio
        </a>
    </nav>

    <!-- Contenedor Dinámico de la Página -->
    <main style="max-width: 800px; margin: 40px auto; padding: 0 20px; flex-grow: 1; width: 100%; box-sizing: border-box;">
        <?php
        // El Loop de WordPress: Aquí es donde la magia ocurre y se renderiza el Shortcode
        if ( have_posts() ) {
            while ( have_posts() ) {
                the_post();
                echo '<h2 style="color: #003366; font-family: \'Inter\', sans-serif; border-bottom: 3px solid #FFCC00; padding-bottom: 10px; margin-bottom: 30px;">' . get_the_title() . '</h2>';
                
                the_content(); // Esto carga el formulario [unah_matriculas]
            }
        }
        ?>
    </main>

    <!-- Footer -->
    <footer class="unah-footer">
        <p>&copy; <?php echo date('Y'); ?> Universidad Nacional Autónoma de Honduras (UNAH). Proyecto desarrollado por Equipo 3.</p>
    </footer>

    <?php wp_footer(); ?>
</body>
</html>
