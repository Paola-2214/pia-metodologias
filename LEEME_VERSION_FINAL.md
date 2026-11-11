"""Recuperación LOCAL con acceso al equipo y a la base, sin mostrar contraseñas."""
from pathlib import Path
import sqlite3, getpass
from werkzeug.security import generate_password_hash

DB=Path(__file__).parent/'database'/'patitas.db'
conexion=sqlite3.connect(DB)
correo=input('Correo de la cuenta: ').strip().casefold()
u=conexion.execute('SELECT id_usuario,correo FROM usuarios WHERE lower(trim(correo))=?',(correo,)).fetchone()
if not u:
    print('No hay una cuenta registrada con ese correo.')
else:
    print('Cuenta encontrada:',u[1])
    nueva=getpass.getpass('Nueva contraseña (8-128 caracteres): ')
    confirma=getpass.getpass('Confirmar nueva contraseña: ')
    if not 8<=len(nueva)<=128 or nueva!=confirma:
        print('Contraseñas no válidas o no coinciden. Sin cambios.')
    else:
        conexion.execute('UPDATE usuarios SET contrasena=?,password_version=password_version+1 WHERE id_usuario=?',
                         (generate_password_hash(nueva),u[0]))
        conexion.commit()
        print('Contraseña restablecida. Las sesiones anteriores dejarán de ser válidas.')
conexion.close()
