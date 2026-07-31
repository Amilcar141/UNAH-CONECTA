<?php
// =========================================================================
// LÓGICA DE MATRÍCULAS - UNAH CONECTA
// =========================================================================
function unah_backend_matriculas_logic() {
    global $wpdb;
    $output = '';

    if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['btn_matricular'])) {
        $id_usuario = get_current_user_id();
        $codigo_curso = sanitize_text_field($_POST['codigo_curso']);
        
        if ($id_usuario > 0) {
            $tabla = 'Matriculas_Demo'; 
            
            $wpdb->query("CREATE TABLE IF NOT EXISTS $tabla (
                id INT AUTO_INCREMENT PRIMARY KEY,
                id_usuario INT NOT NULL,
                codigo_curso VARCHAR(50) NOT NULL,
                estado_matricula VARCHAR(20),
                fecha_inscripcion DATETIME
            )");

            $insertado = $wpdb->insert(
                $tabla,
                array(
                    'id_usuario' => $id_usuario,
                    'codigo_curso' => $codigo_curso,
                    'estado_matricula' => 'Activa', 
                    'fecha_inscripcion' => current_time('mysql')
                )
            );

            if ($insertado) {
                $output .= '<div style="color: #155724; background-color: #d4edda; border-color: #c3e6cb; padding: 15px; border-radius: 5px; margin-bottom: 20px; font-weight: 600;">
                    <i class="fas fa-check-circle"></i> ¡Inscripción exitosa en ' . esc_html($codigo_curso) . '! Tu matrícula está activa en la base de datos.
                </div>';
            } else {
                $output .= '<div style="color: #721c24; background-color: #f8d7da; border-color: #f5c6cb; padding: 15px; border-radius: 5px; margin-bottom: 20px; font-weight: 600;">
                    <i class="fas fa-exclamation-triangle"></i> Error en MariaDB: ' . $wpdb->last_error . '
                </div>';
            }
        } else {
            $output .= '<div style="color: #856404; background-color: #fff3cd; border-color: #ffeeba; padding: 15px; border-radius: 5px; margin-bottom: 20px; font-weight: 600;">
                <i class="fas fa-lock"></i> Por seguridad, debes iniciar sesión.
            </div>';
        }
    }

    $output .= '
    <div style="background: #ffffff; padding: 30px; border-radius: 10px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); border-top: 4px solid #003366; max-width: 500px; margin: 20px auto;">
        <h3 style="color: #003366; margin-top: 0; font-family: Inter, sans-serif;"><i class="fas fa-edit"></i> Formulario de Inscripción</h3>
        <p style="color: #6b7280; font-size: 0.9rem; margin-bottom: 20px;">Ingresa el código del curso o diplomado al que deseas aplicar en este periodo académico.</p>
        <form method="POST" action="">
            <label style="display: block; margin-bottom: 8px; font-weight: 600; color: #1f2937; font-family: Inter, sans-serif;">Código del Curso/Módulo:</label>
            <input type="text" name="codigo_curso" placeholder="Ej: INFO-2026" required style="width: 100%; padding: 12px; margin-bottom: 20px; border: 1px solid #d1d5db; border-radius: 6px; box-sizing: border-box; font-family: Inter, sans-serif;">
            <button type="submit" name="btn_matricular" style="background: #FFCC00; color: #003366; padding: 12px 24px; border: none; border-radius: 6px; cursor: pointer; font-weight: 700; width: 100%; font-size: 1rem; transition: background 0.3s; font-family: Inter, sans-serif;">
                Confirmar Matrícula
            </button>
        </form>
    </div>';
    return $output;
}
add_shortcode('unah_matriculas', 'unah_backend_matriculas_logic');


// =========================================================================
// DISEÑO INSTITUCIONAL: LOGIN DE UNAH-CONECTA
// =========================================================================
function unah_custom_login_styles() {
    // Logo servido desde el propio tema para no depender de ningún servidor externo
    $logo_url = get_stylesheet_directory_uri() . '/UNAH-Conecta.png';
    echo '<style type="text/css">
        body.login {
            background-color: #f9fafb !important;
            font-family: "Inter", sans-serif !important;
        }
        body.login div#login h1 a {
            background-image: url("' . esc_url($logo_url) . '") !important;
            background-size: contain !important;
            background-repeat: no-repeat !important;
            width: 100% !important;
            height: 95px !important;
            margin-bottom: 20px !important;
        }
        body.login div#login form {
            background: #ffffff !important;
            border-radius: 10px !important;
            box-shadow: 0 4px 20px rgba(0,0,0,0.08) !important;
            border-top: 5px solid #003366 !important;
            padding: 35px 30px !important;
        }
        body.login form .input, body.login input[type=text], body.login input[type=password] {
            border: 1px solid #d1d5db !important;
            border-radius: 6px !important;
            padding: 12px !important;
            background: #f9fafb !important;
        }
        body.login .button.button-primary {
            background: #FFCC00 !important;
            border-color: #FFCC00 !important;
            color: #003366 !important;
            font-weight: 700 !important;
            border-radius: 6px !important;
            width: 100% !important;
        }
    </style>';
}
add_action('login_enqueue_scripts', 'unah_custom_login_styles');


// =========================================================================
// DASHBOARD ESTUDIANTIL ESTILO UNAH (SIN CENSO Y CON 2 TARJETAS EN MATRÍCULA)
// =========================================================================
function unah_dashboard_estudiante_logic() {
    if (!is_user_logged_in()) {
        return '<div style="padding: 20px; background: #fff3cd; color: #856404; border-radius: 6px; font-family: Inter, sans-serif;">Debes iniciar sesión para ver tu portal académico. <a href="' . wp_login_url() . '">Iniciar Sesión</a></div>';
    }

    $current_user = wp_get_current_user();
    if (!empty($current_user->first_name) && !empty($current_user->last_name)) {
        $nombre = $current_user->first_name . ' ' . $current_user->last_name;
    } else {
        $nombre = $current_user->user_login;
    }
    $email = $current_user->user_email;
    $iniciales = strtoupper(substr($nombre, 0, 2));

    $num_cuenta = get_user_meta($current_user->ID, 'unah_num_cuenta', true) ?: '20201002345';
    $indice_periodo = get_user_meta($current_user->ID, 'unah_indice_periodo', true) ?: '85%';
    $indice_global = get_user_meta($current_user->ID, 'unah_indice_global', true) ?: '82%';

    $html = '<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">';
    $html .= '<div style="font-family: Inter, sans-serif; max-width: 1300px; margin: 30px auto; padding: 0 20px;">';
    
    // Tarjeta de Identificación Estudiantil
    $html .= '<div style="background: linear-gradient(135deg, #002b5c 0%, #001a38 100%); color: #ffffff; padding: 40px; border-radius: 16px; box-shadow: 0 12px 35px rgba(0,0,0,0.15); display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 30px; margin-bottom: 40px; border-left: 8px solid #FFCC00;">';
    $html .= '<div style="display: flex; align-items: center; gap: 25px;">';
    $html .= '<div style="background: #FFCC00; color: #002b5c; width: 80px; height: 80px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 2rem; font-weight: 800; box-shadow: 0 4px 12px rgba(0,0,0,0.25);">' . $iniciales . '</div>';
    $html .= '<div>';
    $html .= '<span style="background: rgba(255,204,0,0.2); color: #FFCC00; padding: 5px 14px; border-radius: 20px; font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px;">Estudiante Activo</span>';
    $html .= '<h2 style="margin: 10px 0 6px 0; font-size: 2rem; font-weight: 700; color: #ffffff;">' . esc_html($nombre) . '</h2>';
    $html .= '<p style="margin: 0; color: #94a3b8; font-size: 0.95rem;"><i class="fas fa-id-card" style="color: #FFCC00;"></i> Cuenta: ' . esc_html($num_cuenta) . ' &nbsp;|&nbsp; <i class="fas fa-graduation-cap" style="color: #FFCC00;"></i> Ingeniería en Sistemas &nbsp;|&nbsp; <i class="fas fa-map-marker-alt" style="color: #FFCC00;"></i> C.U.R.L.P.</p>';
    $html .= '</div></div>';
    
    $html .= '<div style="display: flex; gap: 20px;">';
    $html .= '<div style="background: rgba(255,255,255,0.08); padding: 18px 25px; border-radius: 12px; text-align: center; border: 1px solid rgba(255,255,255,0.1);"><span style="display: block; font-size: 0.75rem; color: #94a3b8; text-transform: uppercase; font-weight: 600;">Índice Periodo</span><span style="font-size: 2rem; font-weight: 800; color: #FFCC00;">' . esc_html($indice_periodo) . '</span></div>';
    $html .= '<div style="background: rgba(255,255,255,0.08); padding: 18px 25px; border-radius: 12px; text-align: center; border: 1px solid rgba(255,255,255,0.1);"><span style="display: block; font-size: 0.75rem; color: #94a3b8; text-transform: uppercase; font-weight: 600;">Índice Global</span><span style="font-size: 2rem; font-weight: 800; color: #38bdf8;">' . esc_html($indice_global) . '</span></div>';
    $html .= '</div></div>';

    // Fila 1: Módulo Académico (3 Tarjetas lado a lado)
    $html .= '<h3 style="color: #002b5c; font-size: 1.2rem; border-bottom: 2px solid #e5e7eb; padding-bottom: 10px; margin-bottom: 25px; font-weight: 700;"><i class="fas fa-book-reader" style="color: #002b5c; margin-right: 8px;"></i> Módulo Académico</h3>';
    $html .= '<div style="display: flex; justify-content: space-between; gap: 20px; margin-bottom: 40px; flex-wrap: nowrap;">';
    $html .= '<div style="flex: 0 0 32%; background: #ffffff; padding: 25px; border-radius: 14px; box-shadow: 0 4px 20px rgba(0,0,0,0.04); border-top: 4px solid #002b5c;"><div style="color: #2563eb; font-size: 1.6rem; margin-bottom: 15px;"><i class="fas fa-history"></i></div><h4 style="color: #002b5c; margin: 0 0 10px 0; font-size: 1.1rem;">Historial académico</h4><p style="color: #6b7280; font-size: 0.88rem; margin: 0; line-height: 1.5;">Consulta tu historial completo de clases aprobadas, índices por periodo y asignaturas cursadas.</p></div>';
    $html .= '<div style="flex: 0 0 32%; background: #ffffff; padding: 25px; border-radius: 14px; box-shadow: 0 4px 20px rgba(0,0,0,0.04); border-top: 4px solid #002b5c;"><div style="color: #10b981; font-size: 1.6rem; margin-bottom: 15px;"><i class="fas fa-chart-line"></i></div><h4 style="color: #002b5c; margin: 0 0 10px 0; font-size: 1.1rem;">Ver calificaciones</h4><p style="color: #6b7280; font-size: 0.88rem; margin: 0; line-height: 1.5;">Notas y evaluaciones del periodo actual sincronizadas en tiempo real desde el sistema base.</p></div>';
    $html .= '<div style="flex: 0 0 32%; background: #ffffff; padding: 25px; border-radius: 14px; box-shadow: 0 4px 20px rgba(0,0,0,0.04); border-top: 4px solid #002b5c;"><div style="color: #8b5cf6; font-size: 1.6rem; margin-bottom: 15px;"><i class="fas fa-calendar-alt"></i></div><h4 style="color: #002b5c; margin: 0 0 10px 0; font-size: 1.1rem;">Planificación académica</h4><p style="color: #6b7280; font-size: 0.88rem; margin: 0; line-height: 1.5;">Revisa la oferta de espacios pedagógicos y secciones habilitadas para la carrera.</p></div>';
    $html .= '</div>';

    // Fila 2: Gestión de Matrícula y Servicios (2 Tarjetas distribuidas horizontalmente)
    $html .= '<h3 style="color: #002b5c; font-size: 1.2rem; border-bottom: 2px solid #e5e7eb; padding-bottom: 10px; margin-bottom: 25px; font-weight: 700;"><i class="fas fa-edit" style="color: #002b5c; margin-right: 8px;"></i> Gestión de Matrícula y Servicios</h3>';
    global $wpdb;
    $matricula_page_id = $wpdb->get_var("SELECT ID FROM {$wpdb->posts} WHERE post_content LIKE '%[unah_dashboard]%' AND post_status = 'publish' LIMIT 1");
    $matricula_url = $matricula_page_id ? esc_url(home_url('/?page_id=' . $matricula_page_id)) : esc_url(home_url('/'));

    $html .= '<div style="display: flex; justify-content: flex-start; gap: 20px; margin-bottom: 40px; flex-wrap: nowrap;">';
    $html .= '<div onclick="window.location.href=\'' . $matricula_url . '\'" style="flex: 0 0 32%; background: #ffffff; padding: 25px; border-radius: 14px; box-shadow: 0 4px 20px rgba(0,0,0,0.04); border-top: 4px solid #FFCC00; cursor: pointer; transition: transform 0.2s;"><div style="color: #d97706; font-size: 1.6rem; margin-bottom: 15px;"><i class="fas fa-clipboard-check"></i></div><h4 style="color: #002b5c; margin: 0 0 10px 0; font-size: 1.1rem;">Realizar Matrícula</h4><p style="color: #6b7280; font-size: 0.88rem; margin: 0; line-height: 1.5;">Accede al portal de inscripción para registrar tus asignaturas del periodo académico.</p></div>';
    $html .= '<div style="flex: 0 0 32%; background: #ffffff; padding: 25px; border-radius: 14px; box-shadow: 0 4px 20px rgba(0,0,0,0.04); border-top: 4px solid #FFCC00;"><div style="color: #059669; font-size: 1.6rem; margin-bottom: 15px;"><i class="fas fa-certificate"></i></div><h4 style="color: #002b5c; margin: 0 0 10px 0; font-size: 1.1rem;">Exámenes de suficiencia</h4><p style="color: #6b7280; font-size: 0.88rem; margin: 0; line-height: 1.5;">Solicitud e inscripción formal a procesos de evaluación por suficiencia.</p></div>';
    $html .= '</div>';

    $html .= '</div>';
    return $html;
}
add_shortcode('unah_dashboard', 'unah_dashboard_estudiante_logic');


// =========================================================================
// REDIRECCIÓN UNIVERSAL PARA ALUMNOS AL DASHBOARD Y OCULTAR BARRA
// =========================================================================
function unah_login_redirect($redirect_to, $request, $user) {
    if (is_object($user) && isset($user->roles) && is_array($user->roles)) {
        if (in_array('alumno', $user->roles)) {
            global $wpdb;
            $dashboard_id = $wpdb->get_var("SELECT ID FROM {$wpdb->posts} WHERE post_content LIKE '%[unah_dashboard]%' AND post_status = 'publish' LIMIT 1");
            if ($dashboard_id) {
                return home_url('/?page_id=' . $dashboard_id);
            }
        }
    }
    return $redirect_to;
}
add_filter('login_redirect', 'unah_login_redirect', 99, 3);
add_filter('show_admin_bar', '__return_false');
