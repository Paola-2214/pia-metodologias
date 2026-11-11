# Acceso de administrador - Veterinaria Patitas

1. Instala Flask y Werkzeug (`pip install flask werkzeug`).
2. Ejecuta `python app.py` desde la carpeta VeterinariaPatitas.
3. Abre `http://127.0.0.1:5000/login`.
4. En la base de datos de ejemplo, el usuario administrador inicial es `admin@patitas.com` y su contraseña inicial es `Patitas123` (si aún no se había creado). Cámbiala antes de publicar la aplicación.
5. El administrador entra a `/admin` y a `/admin/productos` para agregar, editar y eliminar productos y modificar existencias por sucursal. `/admin/servicios` permite gestionar servicios.

**Importante:** La contraseña inicial solo se usa cuando se crea el usuario administrador por primera vez. Para una instalación nueva puedes establecer `PATITAS_ADMIN_PASSWORD` antes de arrancar. En producción configura `PATITAS_SECRET_KEY` con una clave aleatoria, usa HTTPS, desactiva `debug=True`, implementa protección CSRF y cambia la contraseña inicial. La eliminación de productos con historial de compras está bloqueada para preservar registros.


## NUEVO: Doctores y resumen interactivo
- Entra con el administrador y abre /admin.
- Pulsa Doctores para agregar, editar o eliminar médicos (si tienen citas registradas no se podrán eliminar).
- Pulsa las tarjetas de Clientes, Mascotas, Citas, Productos o Ventas para ver el detalle.
- En Citas puedes cambiar el estado y guardar.
- También hay un acceso a Servicios en el panel.
- Estos módulos requieren ejecutar Flask; no funcionan abriendo el HTML sin servidor.
