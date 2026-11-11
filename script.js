<!DOCTYPE html>
<html lang="es">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>Registrarse - Veterinaria Patitas</title>

    <link rel="stylesheet"
          href="{{ url_for('static', filename='css/estilos.css') }}">
</head>

<body>

    <div class="contenedor-formulario">

        <div class="formulario">

            <h1>🐾 Crear cuenta</h1>

            <p class="texto-formulario">
                Regístrate en Clínica Veterinaria Patitas
            </p>

            {% if error %}
                <div class="mensaje-error">
                    {{ error }}
                </div>
            {% endif %}

            <form method="POST">
<input type="hidden" name="_csrf" value="{{ csrf_token() }}">

                <label>Nombre completo</label>
                <input
                    type="text"
                    name="nombre"
                    placeholder="Ingresa tu nombre"
                    required
                >

                <label>Correo electrónico</label>
                <input
                    type="email"
                    name="correo"
                    placeholder="ejemplo@correo.com"
                    required
                >

                <label>Teléfono</label>
                <input
                    type="text"
                    name="telefono"
                    placeholder="81 1234 5678"
                >

                <label>Contraseña</label>
                <input
                    type="password"
                    name="contrasena"
                    placeholder="Ingresa una contraseña"
                    required
                >

                <label>Confirmar contraseña</label>
                <input
                    type="password"
                    name="confirmar"
                    placeholder="Repite tu contraseña"
                    required
                >

                <button
                    type="submit"
                    class="boton-formulario"
                >
                    Registrarme
                </button>

            </form><p>Por seguridad, nunca compartas tu contraseña.</p>

            <p class="enlace-formulario">

                ¿Ya tienes una cuenta?

                <a href="{{ url_for('login') }}">
                    Iniciar sesión
                </a>

            </p>

            <a
                href="{{ url_for('inicio') }}"
                class="volver"
            >
                ← Volver al inicio
            </a>

        </div>

    </div>

</body>
</html>