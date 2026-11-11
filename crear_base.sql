# Veterinaria Patitas — versión rediseñada con controles

## Instalación en Windows
1. Extraer el ZIP en otra carpeta y hacer copia de seguridad de `database/patitas.db`.
2. Abrir PowerShell en la carpeta `VeterinariaPatitas` (la que contiene `app.py`).
3. Ejecutar `python -m pip install -r requirements.txt` y después `python app.py`.
4. Abrir `http://127.0.0.1:5000/`.

## Cambios de interfaz
- El menú principal del administrador conserva «Ver página» y «Cerrar sesión».
- Reportes, mercancía, ausencias y servicios por sucursal están como tarjetas con estilo original dentro del panel.
- Se quitó el enlace de contraseña del menú de administración. La función de cambio de contraseña continúa disponible en `/cambiar-contrasena` si el usuario inicia sesión.
- «Olvidé mi contraseña» (`/recuperar`) solo informa que se debe contactar a administración. No envía correo ni solicita datos.
- En **Administrar productos → Modificar existencias** se agregaron **Entrada (+)** y **Salida (-)** con cantidad y motivo. Ambos movimientos se registran en el historial. El botón «Modificar inventario» que hacía asignaciones directas se sustituyó para preservar historial.

## Reglas de negocio
- Registro con correo único a nivel de SQLite y transacción de escritura; contraseñas con hash.
- Especie obligatoria y prevención de mascotas duplicadas activas.
- Protección de mascotas con historial de citas/historial clínico.
- Citas en horarios futuros, doctores activos por sucursal, sin superposiciones ni ausencias y servicios habilitados por sucursal.
- Cancelaciones de clientes solo con al menos cuatro horas antes de la cita.
- Citas en curso aparecen «En proceso»; si vence la hora quedan «Pendiente revisión» hasta que un administrador confirme si fueron completadas o canceladas. Se utiliza duración fija de 60 minutos y horario configurado de lunes a sábado 09:00-20:00; modificar estas constantes en `mejoras.py` según los horarios reales.
- Compras de productos activos con actualización de existencias dentro de una transacción de SQLite.
- Desactivación lógica de productos/servicios/doctores y reportes mensuales Excel en `/admin/reportes`.

## Restablecer contraseñas desde terminal
Ejecutar `python recuperar_cuenta.py` y escribir el correo del usuario y una nueva contraseña. Solo personal autorizado con acceso local al archivo de base de datos. Verificar primero la identidad de la persona.

## Avisos
- El ZIP contiene datos de ejemplo y base de datos. **No sustituir una base de datos con datos reales sin respaldo**.
- Mantener `.patitas_secret`, contraseñas y bases de datos fuera de repositorios públicos; usar HTTPS y controles adicionales antes de publicar el sitio en internet.
- Las migraciones se aplican al iniciar el servidor. Si la base existente tiene duplicados históricos pueden necesitar corregirse primero.
- Verificación realizada: compila el código Python; la migración de SQLite se probó sobre una copia de la DB de este ZIP, en dos ejecuciones. La ejecución web y pruebas de navegador deberán hacerse en tu máquina con Flask.
