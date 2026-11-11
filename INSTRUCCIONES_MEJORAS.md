"""Validaciones y controles de Patitas. Ejecuta migraciones sin borrar datos existentes."""
import os, re, csv, io, secrets, sqlite3, smtplib, hashlib, calendar, zipfile
from datetime import datetime, timedelta, date, time
from decimal import Decimal, InvalidOperation
from email.message import EmailMessage
from functools import wraps
from xml.sax.saxutils import escape
from zoneinfo import ZoneInfo
from flask import (request, redirect, url_for, session, render_template, abort,
                   flash, Response, send_file)
from werkzeug.security import generate_password_hash, check_password_hash

ZONA = ZoneInfo('America/Monterrey')
DURACION_MIN = 60
ANTICIPACION_CANCELACION_H = 4
HORARIOS = {0:(9,20), 1:(9,20), 2:(9,20), 3:(9,20), 4:(9,20), 5:(9,20)}

def ahora(): return datetime.now(ZONA).replace(tzinfo=None)
def entero(s):
    try:
        n = int(s)
        return n if n > 0 else None
    except (ValueError, TypeError): return None

def dinero(s):
    try:
        v = Decimal(str(s))
        if not v.is_finite() or v < 0 or v > 99999999 or v.as_tuple().exponent < -2: raise ValueError()
        return float(v)
    except (InvalidOperation, ValueError, TypeError): raise ValueError('Precio inválido (máximo dos decimales).')

def normalizar_correo(s): return (s or '').strip().casefold()
def existe(db,tabla,columna,id_):
    # Usar únicamente identificadores constantes definidos en llamadas internas.
    return db.execute(f'SELECT 1 FROM {tabla} WHERE {columna}=?',(id_,)).fetchone() is not None

def cliente_actual(db):
    if session.get('tipo_usuario')!='Cliente': abort(403)
    cl=db.execute('SELECT * FROM clientes WHERE id_usuario=?',(session.get('id_usuario'),)).fetchone()
    if not cl: abort(403)
    return cl

def admin():
    if not session.get('id_usuario'): return redirect(url_for('login'))
    if session.get('tipo_usuario')!='Administrador': abort(403)
    return None

def init(db):
    def add(table, name, ddl):
        names={x['name'] for x in db.execute(f'PRAGMA table_info({table})')}
        if name not in names: db.execute(f'ALTER TABLE {table} ADD COLUMN {name} {ddl}')
    add('productos','activo','INTEGER NOT NULL DEFAULT 1')
    add('servicios','activo','INTEGER NOT NULL DEFAULT 1')
    add('doctores','activo','INTEGER NOT NULL DEFAULT 1')
    add('mascotas','activo','INTEGER NOT NULL DEFAULT 1')
    add('compras','fecha_hora','TEXT')
    add('compras','id_sucursal','INTEGER')
    add('ventas','fecha_hora','TEXT')
    add('citas','fecha_fin','TEXT')
    add('usuarios','password_version','INTEGER NOT NULL DEFAULT 0')
    db.executescript('''
      CREATE TABLE IF NOT EXISTS movimientos_inventario (
        id_movimiento INTEGER PRIMARY KEY AUTOINCREMENT,
        id_producto INTEGER NOT NULL REFERENCES productos(id_producto),
        id_sucursal INTEGER NOT NULL REFERENCES sucursales(id_sucursal),
        tipo TEXT NOT NULL CHECK(tipo IN ('entrada','salida','ajuste')),
        cantidad INTEGER NOT NULL, existencias_antes INTEGER NOT NULL,
        existencias_despues INTEGER NOT NULL, motivo TEXT NOT NULL,
        id_usuario INTEGER REFERENCES usuarios(id_usuario),
        fecha_hora TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS ausencias_doctores (
        id_ausencia INTEGER PRIMARY KEY AUTOINCREMENT,
        id_doctor INTEGER NOT NULL REFERENCES doctores(id_doctor),
        inicio TEXT NOT NULL, fin TEXT NOT NULL, motivo TEXT,
        CHECK (fin>inicio));
      CREATE TABLE IF NOT EXISTS sucursal_servicio (
        id_sucursal INTEGER NOT NULL REFERENCES sucursales(id_sucursal),
        id_servicio INTEGER NOT NULL REFERENCES servicios(id_servicio),
        PRIMARY KEY(id_sucursal,id_servicio));
      CREATE TABLE IF NOT EXISTS tokens_recuperacion (
        id_token INTEGER PRIMARY KEY AUTOINCREMENT,
        id_usuario INTEGER NOT NULL REFERENCES usuarios(id_usuario),
        token_hash TEXT NOT NULL UNIQUE, expira TEXT NOT NULL,
        utilizado INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS historial_clinico (
        id_historial INTEGER PRIMARY KEY AUTOINCREMENT,
        id_mascota INTEGER NOT NULL REFERENCES mascotas(id_mascota),
        descripcion TEXT NOT NULL, fecha TEXT NOT NULL);
    ''')
    # Normaliza cuentas antiguas; revisar duplicados de correo antes de forzar unicidad.
    for r in db.execute('SELECT id_usuario, correo FROM usuarios').fetchall():
        db.execute('UPDATE usuarios SET correo=? WHERE id_usuario=?', (normalizar_correo(r['correo']), r['id_usuario']))
    db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_usuarios_correo_ci ON usuarios(lower(trim(correo)))')
    # No eliminar duplicados históricos en silencio.
    dups=db.execute('''SELECT id_producto,id_sucursal,COUNT(*) c FROM inventario
        GROUP BY id_producto,id_sucursal HAVING c>1''').fetchall()
    if dups: raise RuntimeError('Hay inventarios duplicados. Revisarlos antes de iniciar: '+str([tuple(d) for d in dups]))
    db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_inventario_producto_sucursal ON inventario(id_producto,id_sucursal)')
    db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_mascota_cliente ON mascotas(id_cliente,lower(trim(nombre)),lower(trim(especie)),lower(trim(coalesce(raza,\'\')))) WHERE activo=1')
    db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS uq_cita_doctor_fecha_hora
      ON citas(id_doctor,fecha,hora) WHERE estado IN ('Programada','Confirmada','En proceso')''')
    db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS uq_cita_mascota_fecha_hora
      ON citas(id_mascota,fecha,hora) WHERE estado IN ('Programada','Confirmada','En proceso')''')
    db.execute('INSERT OR IGNORE INTO sucursal_servicio(id_sucursal,id_servicio) SELECT id_sucursal,id_servicio FROM sucursales CROSS JOIN servicios')
    db.commit()

def csrf_token():
    if '_csrf' not in session: session['_csrf']=secrets.token_urlsafe(32)
    return session['_csrf']

def instalar(app, conectar_db):
    app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE='Lax',
                      PERMANENT_SESSION_LIFETIME=timedelta(hours=4), MAX_CONTENT_LENGTH=1024*1024)
    # Para publicar por HTTPS: PATITAS_HTTPS=1
    app.config['SESSION_COOKIE_SECURE']=os.environ.get('PATITAS_HTTPS')=='1'
    with conectar_db() as db: init(db)
    @app.context_processor
    def contexto(): return {'csrf_token': csrf_token}
    @app.before_request
    def validar_csrf():
        if request.method in ('POST','PUT','PATCH','DELETE'):
            esperado=session.get('_csrf')
            recibido=request.form.get('_csrf') or request.headers.get('X-CSRF-Token')
            if not esperado or not recibido or not secrets.compare_digest(esperado, recibido):
                abort(400, 'Formulario vencido o no autorizado. Recarga la página.')
        # La seguridad de rutas antiguas sigue dependiendo de sus controles originales.

    @app.errorhandler(400)
    def error_400(e): return f'<h2>Solicitud no válida</h2><p>{escape(str(e.description))}</p><a href="/">Inicio</a>',400

    def registrar():
        error=None
        if request.method=='POST':
            nombre=request.form.get('nombre','').strip()
            correo=normalizar_correo(request.form.get('correo'))
            telefono=request.form.get('telefono','').strip()
            passw=request.form.get('contrasena','')
            if not 2<=len(nombre)<=100: error='El nombre debe tener entre 2 y 100 caracteres.'
            elif not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+', correo) or len(correo)>254: error='Correo no válido.'
            elif telefono and not re.fullmatch(r'\d{10}',telefono): error='El teléfono debe tener 10 dígitos.'
            elif len(passw)<8 or len(passw)>128: error='La contraseña debe tener entre 8 y 128 caracteres.'
            elif passw!=request.form.get('confirmar',''): error='Las contraseñas no coinciden.'
            else:
                db=conectar_db()
                try:
                    db.execute('BEGIN IMMEDIATE')
                    cursor=db.execute('INSERT INTO usuarios(nombre,correo,contrasena,tipo_usuario) VALUES(?,?,?,?)',
                                     (nombre,correo,generate_password_hash(passw),'Cliente'))
                    db.execute('INSERT INTO clientes(id_usuario,nombre,telefono,correo) VALUES(?,?,?,?)',
                               (cursor.lastrowid,nombre,telefono,correo))
                    db.commit(); return redirect(url_for('login',registrado='1'))
                except sqlite3.IntegrityError:
                    db.rollback(); error='Ese correo ya está registrado.'
                except sqlite3.Error:
                    db.rollback(); error='No se pudo crear la cuenta. Inténtalo de nuevo.'
                finally: db.close()
        return render_template('registro.html',error=error)
    app.view_functions['registro']=registrar

    def ingresar():
        error=None
        if request.method=='POST':
            correo=normalizar_correo(request.form.get('correo'))
            db=conectar_db()
            u=db.execute('SELECT * FROM usuarios WHERE lower(trim(correo))=?',(correo,)).fetchone()
            db.close()
            if u and check_password_hash(u['contrasena'],request.form.get('contrasena','')):
                session.clear(); session.permanent=True
                session.update(id_usuario=u['id_usuario'],nombre=u['nombre'],tipo_usuario=u['tipo_usuario'],password_version=u['password_version'])
                return redirect(url_for('panel_admin') if u['tipo_usuario']=='Administrador' else url_for('inicio'))
            error='Correo o contraseña incorrectos.'
        return render_template('login.html',error=error)
    app.view_functions['login']=ingresar

    @app.before_request
    def validar_sesion():
        if session.get('id_usuario') and request.endpoint not in ('static','logout'):
            db=conectar_db()
            u=db.execute('SELECT tipo_usuario,password_version FROM usuarios WHERE id_usuario=?',(session['id_usuario'],)).fetchone()
            db.close()
            if not u or u['password_version']!=session.get('password_version',0) or u['tipo_usuario']!=session.get('tipo_usuario'):
                session.clear(); return redirect(url_for('login'))

    @app.route('/cambiar-contrasena',methods=['GET','POST'])
    def cambiar_contrasena():
        if not session.get('id_usuario'): return redirect(url_for('login'))
        error=None
        if request.method=='POST':
            anterior=request.form.get('actual',''); nueva=request.form.get('nueva','')
            if not 8<=len(nueva)<=128 or nueva!=request.form.get('confirmar',''):
                error='La nueva contraseña debe tener 8–128 caracteres y coincidir.'
            else:
                db=conectar_db()
                try:
                    db.execute('BEGIN IMMEDIATE')
                    u=db.execute('SELECT contrasena FROM usuarios WHERE id_usuario=?',(session['id_usuario'],)).fetchone()
                    if not u or not check_password_hash(u['contrasena'],anterior): error='Contraseña actual incorrecta.'
                    elif check_password_hash(u['contrasena'],nueva): error='La nueva contraseña debe ser diferente.'
                    else:
                        db.execute('UPDATE usuarios SET contrasena=?, password_version=password_version+1 WHERE id_usuario=?',
                                   (generate_password_hash(nueva),session['id_usuario']))
                        db.commit();session.clear(); return redirect(url_for('login',cambiada='1'))
                finally: db.close()
        return render_template('seguridad.html',titulo='Cambiar contraseña',tipo='cambiar',error=error)

    @app.route('/recuperar',methods=['GET','POST'])
    def recuperar():
        # Sin envío de correo ni formulario de solicitud. Soporte verifica identidad
        # y restablece la clave mediante recuperar_cuenta.py en el servidor.
        return render_template('seguridad.html',titulo='Recuperación de contraseña',tipo='recuperar',
            mensaje='Para recuperar tu contraseña, comunícate con la administración de Veterinaria Patitas. Verificarán tu identidad y te ayudarán a recuperar el acceso.')

    def mis_mascotas():
        if not session.get('id_usuario'): return redirect(url_for('login'))
        db=conectar_db(); cl=cliente_actual(db); error=None
        if request.method=='POST':
            accion=request.form.get('accion','agregar')
            if accion=='eliminar':
                id_=entero(request.form.get('id_mascota'))
                r=db.execute('SELECT * FROM mascotas WHERE id_mascota=? AND id_cliente=? AND activo=1',(id_,cl['id_cliente'])).fetchone()
                if not r: error='Mascota no encontrada.'
                elif db.execute('SELECT 1 FROM historial_clinico WHERE id_mascota=? LIMIT 1',(id_,)).fetchone():
                    error='La mascota tiene historial médico; no puede eliminarse.'
                elif db.execute('SELECT 1 FROM citas WHERE id_mascota=? AND estado IN (\'Programada\',\'Confirmada\',\'En proceso\') LIMIT 1',(id_,)).fetchone():
                    error='No puedes eliminar una mascota con citas activas o próximas.'
                elif db.execute('SELECT 1 FROM citas WHERE id_mascota=? LIMIT 1',(id_,)).fetchone():
                    error='La mascota tiene citas históricas. Para conservarlas, el registro no puede eliminarse.'
                else:
                    db.execute('UPDATE mascotas SET activo=0 WHERE id_mascota=?',(id_,));db.commit()
                    db.close(); return redirect(url_for('mascotas',exito='eliminada'))
            else:
                nombre=request.form.get('nombre','').strip()
                especie=request.form.get('especie','').strip()
                raza=request.form.get('raza','').strip()
                edad=request.form.get('edad','').strip()
                sexo=request.form.get('sexo','').strip()
                if not 2<=len(nombre)<=60 or not especie or len(especie)>60:
                    error='El nombre (2 a 60 caracteres) y la especie son obligatorios.'
                elif edad and (not edad.isdigit() or int(edad)>100): error='Edad inválida (0 a 100).'
                else:
                    try:
                        db.execute('INSERT INTO mascotas(nombre,especie,raza,edad,sexo,id_cliente) VALUES(?,?,?,?,?,?)',
                            (nombre,especie,raza,int(edad) if edad else None,sexo,cl['id_cliente']))
                        db.commit();db.close();return redirect(url_for('mascotas',exito='registrada'))
                    except sqlite3.IntegrityError:
                        db.rollback();error='Ya tienes una mascota registrada con el mismo nombre, especie y raza.'
        lista=db.execute('SELECT * FROM mascotas WHERE id_cliente=? AND activo=1 ORDER BY id_mascota DESC',(cl['id_cliente'],)).fetchall()
        db.close();return render_template('mascotas.html',mascotas=lista,error=error)
    app.view_functions['mascotas']=mis_mascotas

    def actualizar_estados(db):
        # Una cita vencida no se considera completada sin confirmación humana.
        now=ahora()
        inicio=now.strftime('%Y-%m-%d %H:%M')
        db.execute('''UPDATE citas SET estado='En proceso' WHERE estado IN ('Programada','Confirmada')
           AND (fecha || ' ' || hora)<=? AND datetime(fecha || ' ' || hora,'+60 minutes')>datetime(?)''',(inicio,inicio))
        db.execute('''UPDATE citas SET estado='Pendiente revisión' WHERE estado IN ('Programada','Confirmada','En proceso')
           AND datetime(fecha || ' ' || hora,'+60 minutes')<=datetime(?)''',(inicio,))
        db.commit()

    def validar_cita(db,cliente,form):
        ids={k:entero(form.get(k)) for k in ('mascota','servicio','doctor','sucursal')}
        if not all(ids.values()): raise ValueError('Completa todos los campos de la cita.')
        try: inicio=datetime.strptime(form.get('fecha','')+' '+form.get('hora',''),'%Y-%m-%d %H:%M')
        except ValueError: raise ValueError('La fecha y hora no tienen un formato válido.')
        fin=inicio+timedelta(minutes=DURACION_MIN)
        now=ahora()
        if inicio<=now: raise ValueError('No puedes agendar citas en fechas u horas que ya pasaron.')
        if inicio.weekday() not in HORARIOS: raise ValueError('La sucursal no atiende los domingos.')
        abrir,cerrar=HORARIOS[inicio.weekday()]
        if inicio.date()!=fin.date() or inicio.time()<time(abrir) or fin.time()>time(cerrar):
            raise ValueError(f'Horario de sucursales: lunes a sábado de {abrir}:00 a {cerrar}:00, citas de {DURACION_MIN} minutos.')
        if not db.execute('SELECT 1 FROM mascotas WHERE id_mascota=? AND id_cliente=? AND activo=1', (ids['mascota'],cliente['id_cliente'])).fetchone():
            raise ValueError('La mascota no pertenece al cliente o está inactiva.')
        if not existe(db,'sucursales','id_sucursal',ids['sucursal']): raise ValueError('La sucursal no existe.')
        if not db.execute('SELECT 1 FROM doctores WHERE id_doctor=? AND id_sucursal=? AND activo=1',(ids['doctor'],ids['sucursal'])).fetchone():
            raise ValueError('El doctor no está activo o no pertenece a esa sucursal.')
        if not db.execute('SELECT 1 FROM servicios WHERE id_servicio=? AND activo=1',(ids['servicio'],)).fetchone():
            raise ValueError('El servicio no existe o está desactivado.')
        if not db.execute('SELECT 1 FROM sucursal_servicio WHERE id_servicio=? AND id_sucursal=?',(ids['servicio'],ids['sucursal'])).fetchone():
            raise ValueError('Este servicio no se ofrece en la sucursal seleccionada.')
        if db.execute('SELECT 1 FROM ausencias_doctores WHERE id_doctor=? AND inicio<? AND fin>?',
                      (ids['doctor'],fin.isoformat(timespec='minutes'),inicio.isoformat(timespec='minutes'))).fetchone():
            raise ValueError('El doctor está ausente en ese horario.')
        rows=db.execute('''SELECT * FROM citas WHERE estado IN ('Programada','Confirmada','En proceso') AND fecha IN (?,?)
          AND (id_doctor=? OR id_mascota=?)''', (inicio.date().isoformat(),(inicio-timedelta(days=1)).date().isoformat(),ids['doctor'],ids['mascota'])).fetchall()
        for c in rows:
            ci=datetime.strptime(c['fecha']+' '+c['hora'],'%Y-%m-%d %H:%M')
            cf=ci+timedelta(minutes=DURACION_MIN)
            if inicio<cf and fin>ci: raise ValueError('El horario ya está ocupado por otra cita de ese doctor o mascota.')
        return ids,inicio

    def mis_citas():
        if not session.get('id_usuario'): return redirect(url_for('login'))
        db=conectar_db();cl=cliente_actual(db);actualizar_estados(db);error=None
        if request.method=='POST':
            try:
                db.execute('BEGIN IMMEDIATE')
                if request.form.get('accion')=='cancelar':
                    cid=entero(request.form.get('id_cita'))
                    c=db.execute('SELECT * FROM citas WHERE id_cita=? AND id_cliente=?',(cid,cl['id_cliente'])).fetchone()
                    if not c: raise ValueError('La cita no existe o no te pertenece.')
                    ci=datetime.strptime(c['fecha']+' '+c['hora'],'%Y-%m-%d %H:%M')
                    if c['estado'] not in ('Programada','Confirmada') or ci-ahora()<timedelta(hours=ANTICIPACION_CANCELACION_H):
                        raise ValueError('Solo puedes cancelar citas programadas con al menos 4 horas de anticipación.')
                    db.execute("UPDATE citas SET estado='Cancelada' WHERE id_cita=?",(cid,))
                else:
                    ids,inicio=validar_cita(db,cl,request.form)
                    cursor=db.execute('''INSERT INTO citas(fecha,hora,estado,id_cliente,id_mascota,id_doctor,id_servicio,id_sucursal)
                     VALUES(?,?,?,?,?,?,?,?)''',(inicio.date().isoformat(),inicio.strftime('%H:%M'),'Programada',cl['id_cliente'],
                     ids['mascota'],ids['doctor'],ids['servicio'],ids['sucursal']))
                    db.execute('INSERT INTO notificaciones(id_cliente,id_cita,mensaje,leida) VALUES(?,?,?,0)',
                               (cl['id_cliente'],cursor.lastrowid,'Tienes una nueva cita programada.'))
                db.commit();db.close();return redirect(url_for('citas',exito='1'))
            except ValueError as e: db.rollback();error=str(e)
            except sqlite3.IntegrityError: db.rollback();error='El horario ya fue reservado o los datos no son válidos.'
        pets=db.execute('SELECT * FROM mascotas WHERE id_cliente=? AND activo=1 ORDER BY nombre',(cl['id_cliente'],)).fetchall()
        servicios=db.execute('SELECT * FROM servicios WHERE activo=1 ORDER BY nombre').fetchall()
        sucursales=db.execute('SELECT * FROM sucursales ORDER BY nombre').fetchall()
        doctores=db.execute('SELECT d.*,s.nombre sucursal FROM doctores d JOIN sucursales s ON s.id_sucursal=d.id_sucursal WHERE d.activo=1 ORDER BY d.nombre').fetchall()
        citas=db.execute('''SELECT c.*,m.nombre mascota,s.nombre servicio,d.nombre doctor,su.nombre sucursal FROM citas c
         JOIN mascotas m ON m.id_mascota=c.id_mascota JOIN servicios s ON s.id_servicio=c.id_servicio
         JOIN doctores d ON d.id_doctor=c.id_doctor JOIN sucursales su ON su.id_sucursal=c.id_sucursal
         WHERE c.id_cliente=? ORDER BY c.fecha,c.hora''',(cl['id_cliente'],)).fetchall()
        db.close()
        return render_template('citas.html',mascotas=pets,servicios=servicios,sucursales=sucursales,doctores=doctores,citas=citas,error=error,exito=request.args.get('exito'))
    app.view_functions['citas']=mis_citas

    def registrar_movimiento(db,producto,sucursal,tipo,cantidad,antes,despues,motivo):
        db.execute('''INSERT INTO movimientos_inventario(id_producto,id_sucursal,tipo,cantidad,existencias_antes,existencias_despues,motivo,id_usuario,fecha_hora)
            VALUES(?,?,?,?,?,?,?,?,?)''',(producto,sucursal,tipo,cantidad,antes,despues,motivo,session.get('id_usuario'),ahora().isoformat(timespec='seconds')))

    def compras():
        if not session.get('id_usuario'):return redirect(url_for('login'))
        db=conectar_db();cl=cliente_actual(db);error=None
        if request.method=='POST':
            p=entero(request.form.get('producto'));s=entero(request.form.get('sucursal'));q=entero(request.form.get('cantidad'))
            if not all((p,s,q)) or q>1000: error='Selecciona un producto, sucursal y una cantidad válida (1 a 1000).'
            else:
                try:
                    db.execute('BEGIN IMMEDIATE')
                    pr=db.execute('SELECT * FROM productos WHERE id_producto=? AND activo=1',(p,)).fetchone()
                    if not pr: raise ValueError('El producto no existe o está desactivado.')
                    if not existe(db,'sucursales','id_sucursal',s): raise ValueError('La sucursal no existe.')
                    inv=db.execute('SELECT * FROM inventario WHERE id_producto=? AND id_sucursal=?',(p,s)).fetchone()
                    if not inv or inv['existencias']<q: raise ValueError('Inventario insuficiente o sin existencias.')
                    total=float(Decimal(str(pr['precio']))*q)
                    stamp=ahora().isoformat(timespec='seconds');fecha=stamp[:10]
                    updated=db.execute('''UPDATE inventario SET existencias=existencias-? WHERE id_producto=? AND id_sucursal=? AND existencias>=?''',(q,p,s,q))
                    if updated.rowcount!=1: raise ValueError('El producto se agotó. Inténtalo de nuevo.')
                    c=db.execute('INSERT INTO compras(id_cliente,fecha,total,fecha_hora,id_sucursal) VALUES(?,?,?,?,?)',
                        (cl['id_cliente'],fecha,total,stamp,s)).lastrowid
                    db.execute('INSERT INTO detalle_compra(id_compra,id_producto,cantidad,precio) VALUES(?,?,?,?)',(c,p,q,pr['precio']))
                    db.execute('INSERT INTO ventas(id_cliente,fecha,total,fecha_hora) VALUES(?,?,?,?)',(cl['id_cliente'],fecha,total,stamp))
                    registrar_movimiento(db,p,s,'salida',q,inv['existencias'],inv['existencias']-q,f'Compra #{c}')
                    db.commit();db.close();return redirect(url_for('productos',exito='1'))
                except ValueError as e: db.rollback();error=str(e)
                except sqlite3.Error: db.rollback();error='No se completó la compra; no se descontó inventario.'
        productos=db.execute('SELECT * FROM productos WHERE activo=1 ORDER BY nombre').fetchall()
        sucursales=db.execute('SELECT * FROM sucursales ORDER BY nombre').fetchall()
        inventario=db.execute('''SELECT i.*,p.nombre producto,s.nombre sucursal FROM inventario i
        JOIN productos p ON i.id_producto=p.id_producto JOIN sucursales s ON i.id_sucursal=s.id_sucursal WHERE p.activo=1 ORDER BY p.nombre,s.nombre''').fetchall()
        historial=db.execute('''SELECT c.id_compra,c.fecha,c.total,p.nombre producto,d.cantidad,d.precio FROM compras c
        JOIN detalle_compra d ON d.id_compra=c.id_compra JOIN productos p ON d.id_producto=p.id_producto
        WHERE c.id_cliente=? ORDER BY c.id_compra DESC''',(cl['id_cliente'],)).fetchall()
        db.close();return render_template('productos.html',productos=productos,sucursales=sucursales,inventario=inventario,compras=historial,error=error,exito=request.args.get('exito'))
    app.view_functions['productos']=compras

    @app.route('/admin/inventario/movimiento',methods=['GET','POST'])
    def movimiento_inventario():
        x=admin()
        if x:return x
        db=conectar_db();error=None
        if request.method=='POST':
            par=request.form.get('par_inventario','')
            if par:
                partes=par.split(':')
                p=entero(partes[0]) if len(partes)==2 else None
                s=entero(partes[1]) if len(partes)==2 else None
            else:
                p=entero(request.form.get('id_producto'));s=entero(request.form.get('id_sucursal'))
            tipo=request.form.get('tipo');q=entero(request.form.get('cantidad'));motivo=request.form.get('motivo','').strip()[:200]
            if tipo not in ('entrada','salida') or not all((p,s,q)) or q>100000 or not motivo:
                error='Indica producto, sucursal, tipo, cantidad positiva y motivo.'
            else:
                try:
                    db.execute('BEGIN IMMEDIATE')
                    pr=db.execute('SELECT * FROM productos WHERE id_producto=? AND activo=1',(p,)).fetchone()
                    inv=db.execute('SELECT * FROM inventario WHERE id_producto=? AND id_sucursal=?',(p,s)).fetchone()
                    if not pr or not inv:raise ValueError('Producto o sucursal inválidos.')
                    antes=inv['existencias'];despues=antes+q if tipo=='entrada' else antes-q
                    if despues<0:raise ValueError('No puedes retirar más mercancía que la disponible.')
                    db.execute('UPDATE inventario SET existencias=? WHERE id_inventario=?',(despues,inv['id_inventario']))
                    registrar_movimiento(db,p,s,tipo,q,antes,despues,motivo)
                    db.commit();db.close()
                    if request.form.get('retorno')=='productos':
                        return redirect(url_for('admin_productos',movimiento='1')+'#inventario')
                    return redirect(url_for('movimiento_inventario',guardado='1'))
                except ValueError as e:db.rollback();error=str(e)
                except sqlite3.Error:db.rollback();error='No se pudo registrar el movimiento.'
        inventario=db.execute('''SELECT i.*,p.nombre producto,s.nombre sucursal FROM inventario i JOIN productos p ON i.id_producto=p.id_producto
                   JOIN sucursales s ON s.id_sucursal=i.id_sucursal ORDER BY p.nombre,s.nombre''').fetchall()
        historial=db.execute('''SELECT m.*,p.nombre producto,s.nombre sucursal FROM movimientos_inventario m JOIN productos p ON p.id_producto=m.id_producto
                   JOIN sucursales s ON s.id_sucursal=m.id_sucursal ORDER BY m.id_movimiento DESC LIMIT 100''').fetchall()
        db.close();return render_template('movimientos.html',inventario=inventario,historial=historial,error=error)

    def administrar_productos():
        x=admin()
        if x:return x
        db=conectar_db();error=None
        if request.method=='POST':
            act=request.form.get('accion');p=entero(request.form.get('id_producto'))
            try:
                db.execute('BEGIN IMMEDIATE')
                if act in ('agregar','editar'):
                    nombre=request.form.get('nombre','').strip();descripcion=request.form.get('descripcion','').strip()
                    categoria=request.form.get('categoria','').strip();precio=dinero(request.form.get('precio'))
                    if not nombre or not categoria or len(nombre)>120:raise ValueError('Completa nombre y categoría válidos.')
                    if act=='agregar':
                        p=db.execute('INSERT INTO productos(nombre,descripcion,categoria,precio) VALUES(?,?,?,?)',(nombre,descripcion,categoria,precio)).lastrowid
                        db.execute('INSERT OR IGNORE INTO inventario(id_producto,id_sucursal,existencias) SELECT ?,id_sucursal,0 FROM sucursales',(p,))
                    else:
                        if not p or not existe(db,'productos','id_producto',p):raise ValueError('El producto no existe.')
                        db.execute('UPDATE productos SET nombre=?,descripcion=?,categoria=?,precio=? WHERE id_producto=?',
                                   (nombre,descripcion,categoria,precio,p))
                elif act in ('eliminar','activar'):
                    if not p or not existe(db,'productos','id_producto',p):raise ValueError('Producto no encontrado.')
                    db.execute('UPDATE productos SET activo=? WHERE id_producto=?',(0 if act=='eliminar' else 1,p))
                elif act=='inventario':
                    raise ValueError('Para modificar existencias usa Entradas / Salidas, que conserva el historial de mercancía.')
                else:raise ValueError('Acción no permitida.')
                db.commit();db.close();return redirect(url_for('admin_productos',exito='guardado'))
            except (ValueError,sqlite3.IntegrityError) as e:db.rollback();error=str(e)
        productos=db.execute('SELECT * FROM productos ORDER BY nombre').fetchall()
        inv=db.execute('''SELECT i.*,p.nombre producto,s.nombre sucursal FROM inventario i JOIN productos p ON p.id_producto=i.id_producto
        JOIN sucursales s ON s.id_sucursal=i.id_sucursal ORDER BY p.nombre,s.nombre''').fetchall()
        db.close();return render_template('admin_productos.html',productos=productos,inventario=inv,error=error,exito=request.args.get('exito'))
    app.view_functions['admin_productos']=administrar_productos

    def administrar_servicios():
        x=admin()
        if x:return x
        db=conectar_db();error=None
        if request.method=='POST':
            act=request.form.get('accion');sid=entero(request.form.get('id_servicio'))
            try:
                db.execute('BEGIN IMMEDIATE')
                if act in ('agregar','editar'):
                    nom=request.form.get('nombre','').strip();des=request.form.get('descripcion','').strip()
                    precio=dinero(request.form.get('precio'))
                    if not nom or len(nom)>120:raise ValueError('Nombre de servicio inválido.')
                    if act=='agregar':
                        sid=db.execute('INSERT INTO servicios(nombre,descripcion,precio) VALUES(?,?,?)',(nom,des,precio)).lastrowid
                        db.execute('INSERT INTO sucursal_servicio(id_servicio,id_sucursal) SELECT ?,id_sucursal FROM sucursales',(sid,))
                    else:
                        if not sid or not existe(db,'servicios','id_servicio',sid):raise ValueError('El servicio no existe.')
                        db.execute('UPDATE servicios SET nombre=?,descripcion=?,precio=? WHERE id_servicio=?',(nom,des,precio,sid))
                elif act=='eliminar':
                    if not sid or not existe(db,'servicios','id_servicio',sid):raise ValueError('Servicio no encontrado.')
                    db.execute('UPDATE servicios SET activo=0 WHERE id_servicio=?',(sid,))
                elif act=='activar':
                    if not sid or not existe(db,'servicios','id_servicio',sid):raise ValueError('Servicio no encontrado.')
                    db.execute('UPDATE servicios SET activo=1 WHERE id_servicio=?',(sid,))
                else:raise ValueError('Acción desconocida.')
                db.commit();db.close();return redirect(url_for('admin_servicios',exito='editado'))
            except (ValueError,sqlite3.IntegrityError) as e:db.rollback();error=str(e)
        servicios=db.execute('SELECT * FROM servicios ORDER BY nombre').fetchall()
        db.close();return render_template('admin_servicios.html',servicios=servicios,error=error,exito=request.args.get('exito'))
    app.view_functions['admin_servicios']=administrar_servicios

    @app.route('/admin/servicios/sucursales',methods=['GET','POST'])
    def servicios_sucursales():
        x=admin()
        if x:return x
        db=conectar_db();error=None
        if request.method=='POST':
            s=entero(request.form.get('id_servicio'))
            ids=[entero(k) for k in request.form.getlist('sucursales')]
            if not s or not existe(db,'servicios','id_servicio',s) or any(not v or not existe(db,'sucursales','id_sucursal',v) for v in ids):
                error='Servicio o sucursal inválido.'
            else:
                db.execute('DELETE FROM sucursal_servicio WHERE id_servicio=?',(s,))
                db.executemany('INSERT INTO sucursal_servicio(id_servicio,id_sucursal) VALUES(?,?)',[(s,i) for i in set(ids)])
                db.commit();db.close();return redirect(url_for('servicios_sucursales',guardado='1'))
        servicios=db.execute('SELECT * FROM servicios WHERE activo=1 ORDER BY nombre').fetchall()
        sucursales=db.execute('SELECT * FROM sucursales').fetchall()
        configurados={(r['id_servicio'],r['id_sucursal']) for r in db.execute('SELECT * FROM sucursal_servicio')}
        db.close();return render_template('servicio_sucursales.html',servicios=servicios,sucursales=sucursales,configurados=configurados,error=error)

    @app.route('/admin/doctores/ausencias',methods=['GET','POST'])
    def ausencias():
        x=admin()
        if x:return x
        db=conectar_db();error=None
        if request.method=='POST':
            d=entero(request.form.get('id_doctor'))
            try:
                inicio=datetime.fromisoformat(request.form.get('inicio',''))
                fin=datetime.fromisoformat(request.form.get('fin',''))
                if not d or not existe(db,'doctores','id_doctor',d) or inicio>=fin:raise ValueError()
                db.execute('INSERT INTO ausencias_doctores(id_doctor,inicio,fin,motivo) VALUES(?,?,?,?)',
                           (d,inicio.isoformat(timespec='minutes'),fin.isoformat(timespec='minutes'),request.form.get('motivo','')[:200]))
                db.commit();db.close();return redirect(url_for('ausencias',guardado='1'))
            except (ValueError,sqlite3.Error):error='Doctor o rango de fechas inválido.'
        doctores=db.execute('SELECT * FROM doctores WHERE activo=1 ORDER BY nombre').fetchall()
        listado=db.execute('''SELECT a.*,d.nombre doctor FROM ausencias_doctores a JOIN doctores d ON a.id_doctor=d.id_doctor ORDER BY a.inicio DESC LIMIT 100''').fetchall()
        db.close();return render_template('ausencias.html',doctores=doctores,listado=listado,error=error)

    # Mantiene el control de eliminación actual: nunca borrar doctores con citas.
    old_doctores=app.view_functions['admin_doctores']
    @wraps(old_doctores)
    def doctores_seguro(*args,**kwargs):
        bloqueo=admin()
        if bloqueo:return bloqueo
        if request.method=='POST' and request.form.get('accion')=='eliminar':
            db=conectar_db();ident=entero(request.form.get('id_doctor'))
            if not ident or not existe(db,'doctores','id_doctor',ident):db.close();abort(404)
            db.execute('UPDATE doctores SET activo=0 WHERE id_doctor=?',(ident,));db.commit();db.close()
            return redirect(url_for('admin_doctores',guardado='1'))
        return old_doctores(*args,**kwargs)
    app.view_functions['admin_doctores']=doctores_seguro

    old_resumen=app.view_functions['admin_resumen']
    @wraps(old_resumen)
    def resumen_seguro(seccion):
        bloqueo=admin()
        if bloqueo:return bloqueo
        if seccion=='citas':
            db=conectar_db();actualizar_estados(db)
            if request.method=='POST':
                c=entero(request.form.get('id_cita'));estado=request.form.get('estado','')
                row=db.execute('SELECT estado FROM citas WHERE id_cita=?',(c,)).fetchone()
                if not row or estado not in ('Programada','Confirmada','En proceso','Pendiente revisión','Completada','Cancelada'):
                    db.close();abort(400,'Estado inválido.')
                # Solo administradores pueden finalizar/reclasificar citas.
                db.execute('UPDATE citas SET estado=? WHERE id_cita=?',(estado,c));db.commit();db.close()
                return redirect(url_for('admin_resumen',seccion='citas',guardado='1'))
            db.close()
        return old_resumen(seccion)
    app.view_functions['admin_resumen']=resumen_seguro

    def crear_xlsx(hojas):
        """Genera XLSX mínimo interoperable usando solo biblioteca estándar."""
        out=io.BytesIO()
        with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
            z.writestr('[Content_Types].xml','<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'+''.join(f'<Override PartName="/xl/worksheets/sheet{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' for i in range(1,len(hojas)+1))+'</Types>')
            z.writestr('_rels/.rels','<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
            z.writestr('xl/workbook.xml','<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'+''.join(f'<sheet name="{escape(name)}" sheetId="{i}" r:id="rId{i}"/>' for i,(name,_) in enumerate(hojas,1))+'</sheets></workbook>')
            z.writestr('xl/_rels/workbook.xml.rels','<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+''.join(f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet{i}.xml"/>' for i in range(1,len(hojas)+1))+'</Relationships>')
            for i,(name,rows) in enumerate(hojas,1):
                contents=[]
                for rnum,record in enumerate(rows,1):
                    cells=[]
                    for cnum,v in enumerate(record):
                        col='';n=cnum+1
                        while n: n,rem=divmod(n-1,26);col=chr(65+rem)+col
                        ref=f'{col}{rnum}'
                        if isinstance(v,(int,float)) and not isinstance(v,bool):cells.append(f'<c r="{ref}"><v>{v}</v></c>')
                        else:cells.append(f'<c r="{ref}" t="inlineStr"><is><t>{escape(str(v if v is not None else ""))}</t></is></c>')
                    contents.append(f'<row r="{rnum}">'+''.join(cells)+'</row>')
                z.writestr(f'xl/worksheets/sheet{i}.xml','<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'+''.join(contents)+'</sheetData></worksheet>')
        out.seek(0);return out

    @app.route('/admin/reportes',methods=['GET'])
    def reportes():
        x=admin()
        if x:return x
        mes=request.args.get('mes',ahora().strftime('%Y-%m'))
        if not re.fullmatch(r'\d{4}-(0[1-9]|1[0-2])',mes):abort(400,'Mes inválido.')
        inicio=mes+'-01'; y,m=map(int,mes.split('-'))
        siguiente=f'{y+1}-01-01' if m==12 else f'{y}-{m+1:02d}-01'
        db=conectar_db()
        ventas=db.execute('''SELECT v.id_venta,v.fecha,COALESCE(v.fecha_hora,v.fecha) momento,v.total,
          COALESCE(cl.nombre,'Sin cliente') cliente FROM ventas v LEFT JOIN clientes cl ON cl.id_cliente=v.id_cliente
          WHERE v.fecha>=? AND v.fecha<? ORDER BY v.fecha''',(inicio,siguiente)).fetchall()
        compras=db.execute('''SELECT c.id_compra,COALESCE(c.fecha_hora,c.fecha) momento,COALESCE(s.nombre,'No registrada') sucursal,
         p.nombre producto,d.cantidad,d.precio,c.total FROM compras c JOIN detalle_compra d ON d.id_compra=c.id_compra
         JOIN productos p ON p.id_producto=d.id_producto LEFT JOIN sucursales s ON s.id_sucursal=c.id_sucursal
         WHERE c.fecha>=? AND c.fecha<? ORDER BY c.fecha''',(inicio,siguiente)).fetchall()
        citas=db.execute('''SELECT c.id_cita,c.fecha,c.hora,c.estado,m.nombre mascota,d.nombre doctor,s.nombre servicio
         FROM citas c JOIN mascotas m ON m.id_mascota=c.id_mascota JOIN doctores d ON d.id_doctor=c.id_doctor
         JOIN servicios s ON s.id_servicio=c.id_servicio WHERE c.fecha>=? AND c.fecha<? ORDER BY c.fecha,c.hora''',(inicio,siguiente)).fetchall()
        movimientos=db.execute('''SELECT m.fecha_hora,p.nombre producto,s.nombre sucursal,m.tipo,m.cantidad,m.existencias_antes,
            m.existencias_despues,m.motivo FROM movimientos_inventario m JOIN productos p ON p.id_producto=m.id_producto
            JOIN sucursales s ON s.id_sucursal=m.id_sucursal WHERE m.fecha_hora>=? AND m.fecha_hora<? ORDER BY m.fecha_hora''',(inicio,siguiente)).fetchall()
        stock=db.execute('''SELECT p.nombre producto,s.nombre sucursal,i.existencias FROM inventario i
        JOIN productos p ON p.id_producto=i.id_producto JOIN sucursales s ON s.id_sucursal=i.id_sucursal ORDER BY p.nombre,s.nombre''').fetchall()
        db.close()
        total=round(sum(v['total'] for v in ventas),2)
        if request.args.get('descargar')=='1':
            def sh(header,rows):return [header]+[list(r) for r in rows]
            book=crear_xlsx([
              ('Resumen', [['Mes','Ventas registradas','Total MXN','Citas'],[mes,len(ventas),total,len(citas)]]),
              ('Ventas',sh(['ID','Fecha','Fecha y hora','Total MXN','Cliente'],[tuple(v) for v in ventas])),
              ('Compras',sh(['ID','Fecha y hora','Sucursal','Producto','Cantidad','Precio unitario','Total'],[tuple(v) for v in compras])),
              ('Citas',sh(['ID','Fecha','Hora','Estado','Mascota','Doctor','Servicio'],[tuple(v) for v in citas])),
              ('Movimientos',sh(['Fecha y hora','Producto','Sucursal','Tipo','Cantidad','Antes','Después','Motivo'],[tuple(v) for v in movimientos])),
              ('Inventario actual',sh(['Producto','Sucursal','Existencias'],[tuple(v) for v in stock]))])
            return send_file(book,as_attachment=True,download_name=f'reporte_patitas_{mes}.xlsx',mimetype='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
        return render_template('reportes.html',mes=mes,ventas=len(ventas),total=total,citas=len(citas),movimientos=len(movimientos),
                               bajos=[r for r in stock if r['existencias']<=5])
