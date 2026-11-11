# Recuperación segura de cuentas

En PowerShell, desde la carpeta `VeterinariaPatitas`, ejecuta:

```powershell
python recuperar_cuenta.py
```

Introduce el correo de la cuenta, luego escribe la contraseña nueva dos veces. No se muestra en la pantalla y se guarda como hash. **Solo debe ejecutar esto el administrador con acceso autorizado al servidor o a la PC de la clínica**. No es una función para permitir a los clientes cambiar contraseñas de terceros.

Para clientes desde internet, configura las variables `PATITAS_SMTP_HOST`, `PATITAS_SMTP_PORT` (587), `PATITAS_SMTP_USER`, `PATITAS_SMTP_PASSWORD`, `PATITAS_FROM_EMAIL`, `PATITAS_PUBLIC_URL`. Después usa la opción «¿Olvidaste tu contraseña?» del inicio de sesión; se enviará un enlace que expira en 20 minutos. No expongas esta página en internet sin HTTPS (`PATITAS_HTTPS=1`), secretos seguros y limitación de intentos.
