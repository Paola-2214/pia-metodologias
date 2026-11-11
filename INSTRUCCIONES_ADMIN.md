from flask import Flask, render_template, request, redirect, url_for, session
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import date
import sqlite3
import os


# ==========================================
# CONFIGURACIÓN DE FLASK
# ==========================================

app = Flask(__name__)

# Persistir clave local para evitar cierre de sesión en cada reinicio.
CLAVE_LOCAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".patitas_secret")
if "PATITAS_SECRET_KEY" in os.environ:
    app.secret_key = os.environ["PATITAS_SECRET_KEY"]
else:
    if not os.path.exists(CLAVE_LOCAL):
        with open(CLAVE_LOCAL, "w", encoding="utf-8") as secreto:
            secreto.write(os.urandom(32).hex())
    with open(CLAVE_LOCAL, encoding="utf-8") as secreto:
        app.secret_key = secreto.read().strip()


# ==========================================
# CONEXIÓN A LA BASE DE DATOS
# ==========================================

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

RUTA_DB = os.path.join(
    BASE_DIR,
    "database",
    "patitas.db"
)


def conectar_db():

    conexion = sqlite3.connect(RUTA_DB)

    conexion.row_factory = sqlite3.Row
    conexion.execute("PRAGMA foreign_keys = ON")
    conexion.execute("PRAGMA busy_timeout = 5000")

    return conexion


# ==========================================
# CREAR ADMINISTRADOR INICIAL
# ==========================================

def crear_admin():

    conexion = conectar_db()

    admin = conexion.execute("""
        SELECT *
        FROM usuarios
        WHERE correo = ?
    """, (
        "admin@patitas.com",
    )).fetchone()


    if admin is None and os.environ.get("PATITAS_ADMIN_PASSWORD"):

        contrasena_segura = generate_password_hash(
            os.environ["PATITAS_ADMIN_PASSWORD"]
        )

        conexion.execute("""
            INSERT INTO usuarios
            (
                nombre,
                correo,
                contrasena,
                tipo_usuario
            )
            VALUES (?, ?, ?, ?)
        """, (
            "Administrador Patitas",
            "admin@patitas.com",
            contrasena_segura,
            "Administrador"
        ))

        conexion.commit()


    conexion.close()


crear_admin()


# ==========================================
# CREAR INVENTARIO INICIAL
# ==========================================

def crear_inventario_inicial():

    conexion = conectar_db()


    productos = conexion.execute("""
        SELECT id_producto
        FROM productos
    """).fetchall()


    sucursales = conexion.execute("""
        SELECT id_sucursal
        FROM sucursales
    """).fetchall()


    for producto in productos:

        for sucursal in sucursales:

            existe = conexion.execute("""
                SELECT *
                FROM inventario

                WHERE id_producto = ?
                AND id_sucursal = ?
            """, (
                producto["id_producto"],
                sucursal["id_sucursal"]
            )).fetchone()


            if existe is None:

                conexion.execute("""
                    INSERT INTO inventario
                    (
                        id_producto,
                        id_sucursal,
                        existencias
                    )
                    VALUES (?, ?, ?)
                """, (
                    producto["id_producto"],
                    sucursal["id_sucursal"],
                    10
                ))


    conexion.commit()

    conexion.close()


crear_inventario_inicial()

# ==========================================
# CREAR TABLA DE NOTIFICACIONES
# ==========================================

def crear_tabla_notificaciones():

    conexion = conectar_db()

    conexion.execute("""
        CREATE TABLE IF NOT EXISTS notificaciones
        (
            id_notificacion INTEGER PRIMARY KEY AUTOINCREMENT,

            id_cliente INTEGER NOT NULL,

            id_cita INTEGER NOT NULL,

            mensaje TEXT NOT NULL,

            leida INTEGER DEFAULT 0,

            fecha_creacion TEXT DEFAULT CURRENT_TIMESTAMP,

            FOREIGN KEY (id_cliente)
            REFERENCES clientes(id_cliente),

            FOREIGN KEY (id_cita)
            REFERENCES citas(id_cita)
        )
    """)

    conexion.commit()

    conexion.close()


crear_tabla_notificaciones()



# ==========================================
# PÁGINA PRINCIPAL
# ==========================================

@app.route("/")
def inicio():

    conexion = conectar_db()


    # ======================================
    # SERVICIOS
    # ======================================

    servicios = conexion.execute("""
        SELECT *
        FROM servicios
        ORDER BY nombre
    """).fetchall()


    # ======================================
    # PRODUCTOS
    # ======================================

    productos = conexion.execute("""
        SELECT *
        FROM productos
        ORDER BY nombre
    """).fetchall()


    # ======================================
    # DOCTORES
    # ======================================

    doctores = conexion.execute("""
        SELECT
            doctores.id_doctor,
            doctores.nombre,
            doctores.especialidad,
            doctores.telefono,
            doctores.id_sucursal,

            sucursales.nombre AS sucursal

        FROM doctores

        INNER JOIN sucursales
        ON doctores.id_sucursal =
           sucursales.id_sucursal

        ORDER BY doctores.nombre
    """).fetchall()


    # ======================================
    # SUCURSALES
    # ======================================

    sucursales = conexion.execute("""
        SELECT *
        FROM sucursales
        ORDER BY nombre
    """).fetchall()


    # ======================================
    # NOTIFICACIONES NUEVAS
    # ======================================

    notificaciones_pendientes = 0


    if (
        "id_usuario" in session
        and session.get("tipo_usuario") == "Cliente"
    ):

        cliente_notificaciones = conexion.execute("""
            SELECT id_cliente
            FROM clientes
            WHERE id_usuario = ?
        """, (
            session["id_usuario"],
        )).fetchone()


        if cliente_notificaciones:

            notificaciones_pendientes = conexion.execute("""
                SELECT COUNT(*) AS total
                FROM notificaciones

                WHERE id_cliente = ?
                AND leida = 0
            """, (
                cliente_notificaciones["id_cliente"],
            )).fetchone()["total"]


    conexion.close()


    return render_template(
        "index.html",

        servicios=servicios,
        productos=productos,
        doctores=doctores,
        sucursales=sucursales,

        notificaciones_pendientes=notificaciones_pendientes
    )

# ==========================================
# REGISTRO DE CLIENTES
# ==========================================

@app.route("/registro", methods=["GET", "POST"])
def registro():

    error = None


    if request.method == "POST":

        nombre = request.form["nombre"].strip()
        correo = request.form["correo"].strip()
        telefono = request.form["telefono"].strip()

        contrasena = request.form["contrasena"]
        confirmar = request.form["confirmar"]


        if not nombre or not correo or not contrasena:

            error = "Completa todos los campos obligatorios."


        elif contrasena != confirmar:

            error = "Las contraseñas no coinciden."


        else:

            conexion = conectar_db()


            usuario_existente = conexion.execute("""
                SELECT *
                FROM usuarios
                WHERE correo = ?
            """, (
                correo,
            )).fetchone()


            if usuario_existente:

                error = "Ya existe una cuenta con ese correo."


            else:

                contrasena_segura = generate_password_hash(
                    contrasena
                )


                cursor = conexion.execute("""
                    INSERT INTO usuarios
                    (
                        nombre,
                        correo,
                        contrasena,
                        tipo_usuario
                    )
                    VALUES (?, ?, ?, ?)
                """, (
                    nombre,
                    correo,
                    contrasena_segura,
                    "Cliente"
                ))


                id_usuario = cursor.lastrowid


                conexion.execute("""
                    INSERT INTO clientes
                    (
                        id_usuario,
                        nombre,
                        telefono,
                        correo
                    )
                    VALUES (?, ?, ?, ?)
                """, (
                    id_usuario,
                    nombre,
                    telefono,
                    correo
                ))


                conexion.commit()
                conexion.close()


                return redirect(
                    url_for("login")
                )


            conexion.close()


    return render_template(
        "registro.html",
        error=error
    )


# ==========================================
# INICIAR SESIÓN
# ==========================================

@app.route("/login", methods=["GET", "POST"])
def login():

    error = None


    if request.method == "POST":

        correo = request.form["correo"].strip()
        contrasena = request.form["contrasena"]


        conexion = conectar_db()


        usuario = conexion.execute("""
            SELECT *
            FROM usuarios
            WHERE correo = ?
        """, (
            correo,
        )).fetchone()


        conexion.close()


        if usuario and check_password_hash(
            usuario["contrasena"],
            contrasena
        ):

            session["id_usuario"] = usuario["id_usuario"]
            session["nombre"] = usuario["nombre"]
            session["tipo_usuario"] = usuario["tipo_usuario"]


            # ADMINISTRADOR
            if usuario["tipo_usuario"] == "Administrador":

                return redirect(
                    url_for("panel_admin")
                )


            # CLIENTE
            return redirect(
                url_for("inicio")
            )


        else:

            error = "Correo o contraseña incorrectos."


    return render_template(
        "login.html",
        error=error
    )


# ==========================================
# CERRAR SESIÓN
# ==========================================

@app.route("/logout")
def logout():

    session.clear()

    return redirect(
        url_for("inicio")
    )


# ==========================================
# MASCOTAS
# ==========================================

@app.route("/mascotas", methods=["GET", "POST"])
def mascotas():

    if "id_usuario" not in session:

        return redirect(
            url_for("login")
        )


    if session["tipo_usuario"] != "Cliente":

        return redirect(
            url_for("inicio")
        )


    conexion = conectar_db()


    cliente = conexion.execute("""
        SELECT *
        FROM clientes
        WHERE id_usuario = ?
    """, (
        session["id_usuario"],
    )).fetchone()


    if cliente is None:

        conexion.close()

        return redirect(
            url_for("inicio")
        )


    error = None


    # ======================================
    # REGISTRAR MASCOTA
    # ======================================

    if request.method == "POST":

        nombre = request.form["nombre"].strip()
        especie = request.form["especie"].strip()
        raza = request.form["raza"].strip()
        edad = request.form["edad"].strip()
        sexo = request.form["sexo"].strip()


        if not nombre or not especie:

            error = (
                "El nombre y la especie son obligatorios."
            )


        elif edad and not edad.isdigit():

            error = (
                "La edad debe ser un número entero."
            )


        else:

            if edad:

                edad_guardar = int(edad)

            else:

                edad_guardar = None


            conexion.execute("""
                INSERT INTO mascotas
                (
                    nombre,
                    especie,
                    raza,
                    edad,
                    sexo,
                    id_cliente
                )
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                nombre,
                especie,
                raza,
                edad_guardar,
                sexo,
                cliente["id_cliente"]
            ))


            conexion.commit()
            conexion.close()


            return redirect(
                url_for("mascotas")
            )


    lista_mascotas = conexion.execute("""
        SELECT *
        FROM mascotas

        WHERE id_cliente = ?

        ORDER BY id_mascota DESC
    """, (
        cliente["id_cliente"],
    )).fetchall()


    conexion.close()


    return render_template(
        "mascotas.html",
        mascotas=lista_mascotas,
        error=error
    )


# ==========================================
# CITAS
# ==========================================

@app.route("/citas", methods=["GET", "POST"])
def citas():

    if "id_usuario" not in session:

        return redirect(
            url_for("login")
        )


    if session["tipo_usuario"] != "Cliente":

        return redirect(
            url_for("inicio")
        )


    conexion = conectar_db()


    cliente = conexion.execute("""
        SELECT *
        FROM clientes
        WHERE id_usuario = ?
    """, (
        session["id_usuario"],
    )).fetchone()


    if cliente is None:

        conexion.close()

        return redirect(
            url_for("inicio")
        )


    mascotas = conexion.execute("""
        SELECT *
        FROM mascotas
        WHERE id_cliente = ?
        ORDER BY nombre
    """, (
        cliente["id_cliente"],
    )).fetchall()


    servicios = conexion.execute("""
        SELECT *
        FROM servicios
        ORDER BY nombre
    """).fetchall()


    sucursales = conexion.execute("""
        SELECT *
        FROM sucursales
        ORDER BY nombre
    """).fetchall()


    doctores = conexion.execute("""
        SELECT
            doctores.id_doctor,
            doctores.nombre,
            doctores.especialidad,
            doctores.id_sucursal,

            sucursales.nombre AS sucursal

        FROM doctores

        INNER JOIN sucursales
        ON doctores.id_sucursal =
           sucursales.id_sucursal

        ORDER BY doctores.nombre
    """).fetchall()


    error = None


        # ======================================
    # REGISTRAR CITA
    # ======================================

    if request.method == "POST":

        id_mascota = request.form["mascota"]
        id_servicio = request.form["servicio"]
        id_doctor = request.form["doctor"]
        id_sucursal = request.form["sucursal"]
        fecha = request.form["fecha"]
        hora = request.form["hora"]


        # ==================================
        # VALIDAR CAMPOS
        # ==================================

        if (
            not id_mascota
            or not id_servicio
            or not id_doctor
            or not id_sucursal
            or not fecha
            or not hora
        ):

            error = "Completa todos los campos."


        else:

            # ==================================
            # VERIFICAR QUE LA MASCOTA
            # PERTENEZCA AL CLIENTE
            # ==================================

            mascota_cliente = conexion.execute("""
                SELECT *
                FROM mascotas

                WHERE id_mascota = ?
                AND id_cliente = ?
            """, (
                id_mascota,
                cliente["id_cliente"]
            )).fetchone()


            # ==================================
            # VERIFICAR QUE EL DOCTOR
            # PERTENEZCA A LA SUCURSAL
            # ==================================

            doctor_correcto = conexion.execute("""
                SELECT *
                FROM doctores

                WHERE id_doctor = ?
                AND id_sucursal = ?
            """, (
                id_doctor,
                id_sucursal
            )).fetchone()


            # ==================================
            # VALIDACIONES
            # ==================================

            if mascota_cliente is None:

                error = (
                    "La mascota seleccionada no es válida."
                )


            elif doctor_correcto is None:

                error = (
                    "El doctor seleccionado no pertenece "
                    "a esa sucursal."
                )


            else:

                # ==================================
                # GUARDAR LA CITA
                # ==================================

                cursor = conexion.execute("""
                    INSERT INTO citas
                    (
                        fecha,
                        hora,
                        estado,
                        id_cliente,
                        id_mascota,
                        id_doctor,
                        id_servicio,
                        id_sucursal
                    )

                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (
                    fecha,
                    hora,
                    "Programada",
                    cliente["id_cliente"],
                    id_mascota,
                    id_doctor,
                    id_servicio,
                    id_sucursal
                ))


                # ==================================
                # OBTENER ID DE LA NUEVA CITA
                # ==================================

                id_cita = cursor.lastrowid


                # ==================================
                # CREAR NOTIFICACIÓN
                # ==================================

                conexion.execute("""
                    INSERT INTO notificaciones
                    (
                        id_cliente,
                        id_cita,
                        mensaje,
                        leida
                    )

                    VALUES (?, ?, ?, ?)
                """, (
                    cliente["id_cliente"],
                    id_cita,
                    "Tienes una nueva cita programada.",
                    0
                ))


                # ==================================
                # GUARDAR LOS CAMBIOS
                # ==================================

                conexion.commit()

                conexion.close()


                # ==================================
                # REGRESAR A MIS CITAS
                # ==================================

                return redirect(
                    url_for(
                        "citas",
                        exito="1"
                    )
                )


    # ======================================
    # CONSULTAR CITAS DEL CLIENTE
    # ======================================

    lista_citas = conexion.execute("""
        SELECT
            citas.id_cita,
            citas.fecha,
            citas.hora,
            citas.estado,

            mascotas.nombre AS mascota,
            servicios.nombre AS servicio,
            doctores.nombre AS doctor,
            sucursales.nombre AS sucursal

        FROM citas

        INNER JOIN mascotas
        ON citas.id_mascota =
           mascotas.id_mascota

        INNER JOIN servicios
        ON citas.id_servicio =
           servicios.id_servicio

        INNER JOIN doctores
        ON citas.id_doctor =
           doctores.id_doctor

        INNER JOIN sucursales
        ON citas.id_sucursal =
           sucursales.id_sucursal

        WHERE citas.id_cliente = ?

        ORDER BY
            citas.fecha,
            citas.hora
    """, (
        cliente["id_cliente"],
    )).fetchall()


    conexion.close()


    return render_template(
        "citas.html",
        mascotas=mascotas,
        servicios=servicios,
        doctores=doctores,
        sucursales=sucursales,
        citas=lista_citas,
        error=error,
        exito=request.args.get("exito")
    )


# ==========================================
# PRODUCTOS / COMPRAS
# ==========================================

@app.route("/productos", methods=["GET", "POST"])
def productos():

    if "id_usuario" not in session:

        return redirect(
            url_for("login")
        )


    if session["tipo_usuario"] != "Cliente":

        return redirect(
            url_for("inicio")
        )


    conexion = conectar_db()


    cliente = conexion.execute("""
        SELECT *
        FROM clientes
        WHERE id_usuario = ?
    """, (
        session["id_usuario"],
    )).fetchone()


    if cliente is None:

        conexion.close()

        return redirect(
            url_for("inicio")
        )


    lista_productos = conexion.execute("""
        SELECT *
        FROM productos
        ORDER BY nombre
    """).fetchall()


    sucursales = conexion.execute("""
        SELECT *
        FROM sucursales
        ORDER BY nombre
    """).fetchall()


    inventario = conexion.execute("""
        SELECT
            inventario.id_inventario,
            inventario.id_producto,
            inventario.id_sucursal,
            inventario.existencias,

            productos.nombre AS producto,
            sucursales.nombre AS sucursal

        FROM inventario

        INNER JOIN productos
        ON inventario.id_producto =
           productos.id_producto

        INNER JOIN sucursales
        ON inventario.id_sucursal =
           sucursales.id_sucursal

        ORDER BY
            productos.nombre,
            sucursales.nombre
    """).fetchall()


    error = None


    # ======================================
    # REALIZAR COMPRA
    # ======================================

    if request.method == "POST":

        id_producto = request.form["producto"]
        id_sucursal = request.form["sucursal"]
        cantidad = request.form["cantidad"]


        if (
            not id_producto
            or not id_sucursal
            or not cantidad
        ):

            error = "Completa todos los campos."


        elif not cantidad.isdigit():

            error = "La cantidad debe ser un número."


        elif int(cantidad) <= 0:

            error = "La cantidad debe ser mayor a cero."


        else:

            cantidad = int(cantidad)


            producto = conexion.execute("""
                SELECT *
                FROM productos
                WHERE id_producto = ?
            """, (
                id_producto,
            )).fetchone()


            stock = conexion.execute("""
                SELECT *
                FROM inventario

                WHERE id_producto = ?
                AND id_sucursal = ?
            """, (
                id_producto,
                id_sucursal
            )).fetchone()


            if producto is None:

                error = "El producto no existe."


            elif stock is None:

                error = (
                    "No existe inventario "
                    "para ese producto."
                )


            elif stock["existencias"] < cantidad:

                error = (
                    "No hay suficientes existencias. "
                    f"Disponibles: {stock['existencias']}"
                )


            else:

                total = (
                    producto["precio"] * cantidad
                )

                fecha_actual = (
                    date.today().isoformat()
                )


                # COMPRA

                cursor = conexion.execute("""
                    INSERT INTO compras
                    (
                        id_cliente,
                        fecha,
                        total
                    )
                    VALUES (?, ?, ?)
                """, (
                    cliente["id_cliente"],
                    fecha_actual,
                    total
                ))


                id_compra = cursor.lastrowid


                # DETALLE DE COMPRA

                conexion.execute("""
                    INSERT INTO detalle_compra
                    (
                        id_compra,
                        id_producto,
                        cantidad,
                        precio
                    )
                    VALUES (?, ?, ?, ?)
                """, (
                    id_compra,
                    id_producto,
                    cantidad,
                    producto["precio"]
                ))


                # VENTA

                conexion.execute("""
                    INSERT INTO ventas
                    (
                        id_cliente,
                        fecha,
                        total
                    )
                    VALUES (?, ?, ?)
                """, (
                    cliente["id_cliente"],
                    fecha_actual,
                    total
                ))


                # DESCONTAR INVENTARIO

                conexion.execute("""
                    UPDATE inventario

                    SET existencias =
                        existencias - ?

                    WHERE id_producto = ?
                    AND id_sucursal = ?
                """, (
                    cantidad,
                    id_producto,
                    id_sucursal
                ))


                conexion.commit()
                conexion.close()


                return redirect(
                    url_for(
                        "productos",
                        exito="1"
                    )
                )


    # ======================================
    # HISTORIAL DE COMPRAS
    # ======================================

    compras = conexion.execute("""
        SELECT
            compras.id_compra,
            compras.fecha,
            compras.total,

            productos.nombre AS producto,

            detalle_compra.cantidad,
            detalle_compra.precio

        FROM compras

        INNER JOIN detalle_compra
        ON compras.id_compra =
           detalle_compra.id_compra

        INNER JOIN productos
        ON detalle_compra.id_producto =
           productos.id_producto

        WHERE compras.id_cliente = ?

        ORDER BY compras.id_compra DESC
    """, (
        cliente["id_cliente"],
    )).fetchall()


    conexion.close()


    return render_template(
        "productos.html",
        productos=lista_productos,
        sucursales=sucursales,
        inventario=inventario,
        compras=compras,
        error=error,
        exito=request.args.get("exito")
    )


# ==========================================
# PANEL DEL ADMINISTRADOR
# ==========================================

@app.route("/admin")
def panel_admin():

    if "id_usuario" not in session:

        return redirect(
            url_for("login")
        )


    if session["tipo_usuario"] != "Administrador":

        return redirect(
            url_for("inicio")
        )


    conexion = conectar_db()


    # TOTALES

    total_clientes = conexion.execute("""
        SELECT COUNT(*) AS total
        FROM clientes
    """).fetchone()["total"]


    total_mascotas = conexion.execute("""
        SELECT COUNT(*) AS total
        FROM mascotas
    """).fetchone()["total"]


    total_citas = conexion.execute("""
        SELECT COUNT(*) AS total
        FROM citas
    """).fetchone()["total"]


    total_productos = conexion.execute("""
        SELECT COUNT(*) AS total
        FROM productos
    """).fetchone()["total"]


    total_ventas = conexion.execute("""
        SELECT COALESCE(SUM(total), 0) AS total
        FROM ventas
    """).fetchone()["total"]


    # CITAS

    citas_admin = conexion.execute("""
        SELECT
            citas.id_cita,
            citas.fecha,
            citas.hora,
            citas.estado,

            clientes.nombre AS cliente,
            mascotas.nombre AS mascota,
            servicios.nombre AS servicio,
            doctores.nombre AS doctor,
            sucursales.nombre AS sucursal

        FROM citas

        INNER JOIN clientes
        ON citas.id_cliente =
           clientes.id_cliente

        INNER JOIN mascotas
        ON citas.id_mascota =
           mascotas.id_mascota

        INNER JOIN servicios
        ON citas.id_servicio =
           servicios.id_servicio

        INNER JOIN doctores
        ON citas.id_doctor =
           doctores.id_doctor

        INNER JOIN sucursales
        ON citas.id_sucursal =
           sucursales.id_sucursal

        ORDER BY
            citas.fecha,
            citas.hora
    """).fetchall()


    # INVENTARIO

    inventario_admin = conexion.execute("""
        SELECT
            productos.nombre AS producto,
            productos.precio AS precio,

            sucursales.nombre AS sucursal,

            inventario.existencias

        FROM inventario

        INNER JOIN productos
        ON inventario.id_producto =
           productos.id_producto

        INNER JOIN sucursales
        ON inventario.id_sucursal =
           sucursales.id_sucursal

        ORDER BY
            productos.nombre,
            sucursales.nombre
    """).fetchall()


    # CLIENTES

    clientes_admin = conexion.execute("""
        SELECT *
        FROM clientes
        ORDER BY nombre
    """).fetchall()


    conexion.close()


    return render_template(
        "admin.html",

        total_clientes=total_clientes,
        total_mascotas=total_mascotas,
        total_citas=total_citas,
        total_productos=total_productos,
        total_ventas=total_ventas,

        citas=citas_admin,
        inventario=inventario_admin,
        clientes=clientes_admin
    )


# ==========================================
# ADMINISTRAR PRODUCTOS
# ==========================================

@app.route("/admin/productos", methods=["GET", "POST"])
def admin_productos():

    if "id_usuario" not in session:

        return redirect(
            url_for("login")
        )


    if session["tipo_usuario"] != "Administrador":

        return redirect(
            url_for("inicio")
        )


    conexion = conectar_db()

    error = None


    if request.method == "POST":

        accion = request.form.get("accion")


        # ==================================
        # AGREGAR PRODUCTO
        # ==================================

        if accion == "agregar":

            nombre = request.form["nombre"].strip()
            descripcion = request.form["descripcion"].strip()
            categoria = request.form["categoria"].strip()
            precio = request.form["precio"].strip()


            if not nombre or not categoria or not precio:

                error = (
                    "Completa los campos obligatorios."
                )


            else:

                try:

                    precio = float(precio)


                    if precio < 0:

                        error = (
                            "El precio no puede ser negativo."
                        )

                    else:

                        cursor = conexion.execute("""
                            INSERT INTO productos
                            (
                                nombre,
                                descripcion,
                                categoria,
                                precio
                            )
                            VALUES (?, ?, ?, ?)
                        """, (
                            nombre,
                            descripcion,
                            categoria,
                            precio
                        ))


                        id_producto = cursor.lastrowid


                        sucursales = conexion.execute("""
                            SELECT *
                            FROM sucursales
                        """).fetchall()


                        for sucursal in sucursales:

                            conexion.execute("""
                                INSERT INTO inventario
                                (
                                    id_producto,
                                    id_sucursal,
                                    existencias
                                )
                                VALUES (?, ?, ?)
                            """, (
                                id_producto,
                                sucursal["id_sucursal"],
                                0
                            ))


                        conexion.commit()
                        conexion.close()


                        return redirect(
                            url_for(
                                "admin_productos",
                                exito="agregado"
                            )
                        )


                except ValueError:

                    error = (
                        "El precio debe ser un número."
                    )


        # ==================================
        # EDITAR / ELIMINAR PRODUCTOS (SOLO ADMIN)
        # ==================================
        elif accion == "editar":
            try:
                id_producto = int(request.form.get("id_producto", ""))
                nombre = request.form.get("nombre", "").strip()
                descripcion = request.form.get("descripcion", "").strip()
                categoria = request.form.get("categoria", "").strip()
                precio = float(request.form.get("precio", ""))
                if not nombre or not categoria or not (0 <= precio < 100000000):
                    raise ValueError()
                cursor = conexion.execute("""
                    UPDATE productos SET nombre=?, descripcion=?, categoria=?, precio=?
                    WHERE id_producto=?
                """, (nombre, descripcion, categoria, precio, id_producto))
                if cursor.rowcount == 0:
                    error = "El producto ya no existe."
                else:
                    conexion.commit()
                    return redirect(url_for("admin_productos", exito="editado"))
            except (ValueError, TypeError):
                error = "Verifica los datos del producto y el precio."

        elif accion == "eliminar":
            try:
                id_producto = int(request.form.get("id_producto", ""))
                vendido = conexion.execute(
                    "SELECT 1 FROM detalle_compra WHERE id_producto=? LIMIT 1",
                    (id_producto,)
                ).fetchone()
                if vendido:
                    error = "No se puede eliminar un producto con historial de compras."
                else:
                    conexion.execute("DELETE FROM inventario WHERE id_producto=?", (id_producto,))
                    cursor = conexion.execute("DELETE FROM productos WHERE id_producto=?", (id_producto,))
                    conexion.commit()
                    if cursor.rowcount:
                        return redirect(url_for("admin_productos", exito="eliminado"))
                    error = "El producto no existe."
            except (ValueError, TypeError):
                error = "Identificador de producto inválido."

        # ==================================
        # ACTUALIZAR INVENTARIO
        # ==================================

        elif accion == "inventario":

            id_producto = request.form["id_producto"]
            id_sucursal = request.form["id_sucursal"]
            existencias = request.form["existencias"]


            if not existencias.isdigit():

                error = (
                    "Las existencias deben ser "
                    "un número entero."
                )


            else:

                conexion.execute("""
                    UPDATE inventario

                    SET existencias = ?

                    WHERE id_producto = ?
                    AND id_sucursal = ?
                """, (
                    int(existencias),
                    id_producto,
                    id_sucursal
                ))


                conexion.commit()
                conexion.close()


                return redirect(
                    url_for(
                        "admin_productos",
                        exito="inventario"
                    )
                )


    productos_admin = conexion.execute("""
        SELECT *
        FROM productos
        ORDER BY nombre
    """).fetchall()


    inventario_admin = conexion.execute("""
        SELECT
            inventario.id_producto,
            inventario.id_sucursal,
            inventario.existencias,

            productos.nombre AS producto,
            sucursales.nombre AS sucursal

        FROM inventario

        INNER JOIN productos
        ON inventario.id_producto =
           productos.id_producto

        INNER JOIN sucursales
        ON inventario.id_sucursal =
           sucursales.id_sucursal

        ORDER BY
            productos.nombre,
            sucursales.nombre
    """).fetchall()


    conexion.close()


    return render_template(
        "admin_productos.html",

        productos=productos_admin,
        inventario=inventario_admin,

        error=error,

        exito=request.args.get("exito")
    )


# ==========================================
# ADMINISTRAR SERVICIOS
# ==========================================

@app.route("/admin/servicios", methods=["GET", "POST"])
def admin_servicios():

    if "id_usuario" not in session:

        return redirect(
            url_for("login")
        )


    if session["tipo_usuario"] != "Administrador":

        return redirect(
            url_for("inicio")
        )


    conexion = conectar_db()

    error = None


    if request.method == "POST":

        accion = request.form.get("accion")


        # ==================================
        # AGREGAR SERVICIO
        # ==================================

        if accion == "agregar":

            nombre = request.form["nombre"].strip()
            descripcion = request.form["descripcion"].strip()
            precio = request.form["precio"].strip()


            if not nombre or not precio:

                error = (
                    "Nombre y precio son obligatorios."
                )


            else:

                try:

                    precio = float(precio)


                    if precio < 0:

                        error = (
                            "El precio no puede ser negativo."
                        )

                    else:

                        conexion.execute("""
                            INSERT INTO servicios
                            (
                                nombre,
                                descripcion,
                                precio
                            )
                            VALUES (?, ?, ?)
                        """, (
                            nombre,
                            descripcion,
                            precio
                        ))


                        conexion.commit()
                        conexion.close()


                        return redirect(
                            url_for(
                                "admin_servicios",
                                exito="agregado"
                            )
                        )


                except ValueError:

                    error = (
                        "El precio debe ser un número."
                    )


        # ==================================
        # EDITAR SERVICIO
        # ==================================

        elif accion == "editar":

            id_servicio = request.form["id_servicio"]

            nombre = request.form["nombre"].strip()
            descripcion = request.form["descripcion"].strip()
            precio = request.form["precio"].strip()


            if not nombre or not precio:

                error = (
                    "Nombre y precio son obligatorios."
                )


            else:

                try:

                    precio = float(precio)


                    if precio < 0:

                        error = (
                            "El precio no puede ser negativo."
                        )

                    else:

                        conexion.execute("""
                            UPDATE servicios

                            SET
                                nombre = ?,
                                descripcion = ?,
                                precio = ?

                            WHERE id_servicio = ?
                        """, (
                            nombre,
                            descripcion,
                            precio,
                            id_servicio
                        ))


                        conexion.commit()
                        conexion.close()


                        return redirect(
                            url_for(
                                "admin_servicios",
                                exito="editado"
                            )
                        )


                except ValueError:

                    error = (
                        "El precio debe ser un número."
                    )


        # ==================================
        # ELIMINAR SERVICIO
        # ==================================

        elif accion == "eliminar":

            id_servicio = request.form["id_servicio"]


            citas_servicio = conexion.execute("""
                SELECT COUNT(*) AS total

                FROM citas

                WHERE id_servicio = ?
            """, (
                id_servicio,
            )).fetchone()["total"]


            if citas_servicio > 0:

                error = (
                    "No puedes eliminar este servicio "
                    "porque tiene citas registradas."
                )


            else:

                conexion.execute("""
                    DELETE FROM servicios

                    WHERE id_servicio = ?
                """, (
                    id_servicio,
                ))


                conexion.commit()
                conexion.close()


                return redirect(
                    url_for(
                        "admin_servicios",
                        exito="eliminado"
                    )
                )


    servicios_admin = conexion.execute("""
        SELECT *
        FROM servicios
        ORDER BY nombre
    """).fetchall()


    conexion.close()


    return render_template(
        "admin_servicios.html",

        servicios=servicios_admin,

        error=error,

        exito=request.args.get("exito")
    )

# ==========================================
# NOTIFICACIONES
# ==========================================

@app.route("/notificaciones")
def notificaciones():

    if "id_usuario" not in session:
        return redirect(url_for("login"))

    if session["tipo_usuario"] != "Cliente":
        return redirect(url_for("inicio"))

    conexion = conectar_db()

    cliente = conexion.execute("""
        SELECT *
        FROM clientes
        WHERE id_usuario = ?
    """, (
        session["id_usuario"],
    )).fetchone()


    lista_notificaciones = conexion.execute("""
        SELECT
            notificaciones.id_notificacion,
            notificaciones.id_cita,
            notificaciones.mensaje,
            notificaciones.leida,

            citas.fecha,
            citas.hora,
            citas.estado,

            mascotas.nombre AS mascota,
            servicios.nombre AS servicio,
            doctores.nombre AS doctor,
            sucursales.nombre AS sucursal

        FROM notificaciones

        INNER JOIN citas
        ON notificaciones.id_cita = citas.id_cita

        INNER JOIN mascotas
        ON citas.id_mascota = mascotas.id_mascota

        INNER JOIN servicios
        ON citas.id_servicio = servicios.id_servicio

        INNER JOIN doctores
        ON citas.id_doctor = doctores.id_doctor

        INNER JOIN sucursales
        ON citas.id_sucursal = sucursales.id_sucursal

        WHERE notificaciones.id_cliente = ?

        ORDER BY notificaciones.id_notificacion DESC
    """, (
        cliente["id_cliente"],
    )).fetchall()


    conexion.close()


    return render_template(
        "notificaciones.html",
        notificaciones=lista_notificaciones
    )


# ==========================================
# CALENDARIO DE CITAS
# ==========================================

@app.route("/calendario")
def calendario():

    if "id_usuario" not in session:
        return redirect(url_for("login"))

    if session["tipo_usuario"] != "Cliente":
        return redirect(url_for("inicio"))

    id_cita = request.args.get("cita")

    if not id_cita:
        return redirect(url_for("notificaciones"))

    conexion = conectar_db()

    cliente = conexion.execute("""
        SELECT *
        FROM clientes
        WHERE id_usuario = ?
    """, (
        session["id_usuario"],
    )).fetchone()

    cita = conexion.execute("""
        SELECT
            citas.id_cita,
            citas.fecha,
            citas.hora,
            citas.estado,

            mascotas.nombre AS mascota,
            servicios.nombre AS servicio,
            doctores.nombre AS doctor,
            sucursales.nombre AS sucursal

        FROM citas

        INNER JOIN mascotas
        ON citas.id_mascota = mascotas.id_mascota

        INNER JOIN servicios
        ON citas.id_servicio = servicios.id_servicio

        INNER JOIN doctores
        ON citas.id_doctor = doctores.id_doctor

        INNER JOIN sucursales
        ON citas.id_sucursal = sucursales.id_sucursal

        WHERE citas.id_cita = ?
        AND citas.id_cliente = ?
    """, (
        id_cita,
        cliente["id_cliente"]
    )).fetchone()

    conexion.close()

    if cita is None:
        return redirect(url_for("notificaciones"))

    return render_template(
        "calendario.html",
        cita=cita
    )



# ==========================================
# ADMINISTRACIÓN ADICIONAL: DOCTORES Y REPORTES
# ==========================================

from functools import wraps
from flask import abort, flash


def solo_admin(f):
    @wraps(f)
    def protegido(*args, **kwargs):
        if 'id_usuario' not in session:
            return redirect(url_for('login'))
        if session.get('tipo_usuario') != 'Administrador':
            abort(403)
        return f(*args, **kwargs)
    return protegido


@app.route('/admin/doctores', methods=['GET', 'POST'])
@solo_admin
def admin_doctores():
    db = conectar_db()
    error = None
    if request.method == 'POST':
        accion = request.form.get('accion', '')
        try:
            if accion in ('agregar', 'editar'):
                nombre = request.form.get('nombre', '').strip()
                especialidad = request.form.get('especialidad', '').strip()
                telefono = request.form.get('telefono', '').strip()
                sucursal = request.form.get('id_sucursal', type=int)
                if not nombre or not sucursal or not db.execute('SELECT 1 FROM sucursales WHERE id_sucursal=?', (sucursal,)).fetchone():
                    raise ValueError('Ingresa un nombre y selecciona una sucursal válida.')
                if accion == 'agregar':
                    db.execute('INSERT INTO doctores (nombre, especialidad, telefono, id_sucursal) VALUES (?, ?, ?, ?)', (nombre, especialidad, telefono, sucursal))
                else:
                    doctor_id = request.form.get('id_doctor', type=int)
                    if not doctor_id or not db.execute('SELECT 1 FROM doctores WHERE id_doctor=?', (doctor_id,)).fetchone():
                        raise ValueError('El doctor no existe.')
                    db.execute('UPDATE doctores SET nombre=?, especialidad=?, telefono=?, id_sucursal=? WHERE id_doctor=?', (nombre, especialidad, telefono, sucursal, doctor_id))
            elif accion == 'eliminar':
                doctor_id = request.form.get('id_doctor', type=int)
                if not doctor_id:
                    raise ValueError('Doctor inválido.')
                ocupado = db.execute('SELECT 1 FROM citas WHERE id_doctor=? LIMIT 1', (doctor_id,)).fetchone()
                if ocupado:
                    raise ValueError('No se puede eliminar un doctor con citas registradas. Puedes editar sus datos.')
                db.execute('DELETE FROM doctores WHERE id_doctor=?', (doctor_id,))
            else:
                raise ValueError('Acción no permitida.')
            db.commit()
            db.close()
            return redirect(url_for('admin_doctores', guardado='1'))
        except (ValueError, sqlite3.Error) as exc:
            db.rollback()
            error = str(exc)
    doctores = db.execute('''SELECT d.*, s.nombre AS sucursal FROM doctores d JOIN sucursales s ON s.id_sucursal=d.id_sucursal ORDER BY d.nombre''').fetchall()
    sucursales = db.execute('SELECT * FROM sucursales ORDER BY nombre').fetchall()
    db.close()
    return render_template('admin_doctores.html', doctores=doctores, sucursales=sucursales, error=error)


@app.route('/admin/resumen/<seccion>', methods=['GET', 'POST'])
@solo_admin
def admin_resumen(seccion):
    nombres = {'clientes':'Clientes', 'mascotas':'Mascotas', 'citas':'Citas', 'productos':'Productos', 'ventas':'Ventas'}
    if seccion not in nombres:
        abort(404)
    if seccion == 'productos':
        return redirect(url_for('admin_productos'))
    db = conectar_db()
    error = None
    if request.method == 'POST' and seccion == 'citas':
        cita_id = request.form.get('id_cita', type=int)
        estado = request.form.get('estado', '')
        if cita_id and estado in ('Programada', 'Confirmada', 'Completada', 'Cancelada'):
            db.execute('UPDATE citas SET estado=? WHERE id_cita=?', (estado, cita_id))
            db.commit()
            db.close()
            return redirect(url_for('admin_resumen', seccion='citas', guardado='1'))
        error = 'Selecciona una cita y un estado válido.'
    consultas = {
        'clientes': '''SELECT id_cliente AS id, nombre AS Nombre, telefono AS Teléfono, correo AS Correo FROM clientes ORDER BY nombre''',
        'mascotas': '''SELECT m.id_mascota AS id, m.nombre AS Nombre, m.especie AS Especie, m.raza AS Raza, m.edad AS Edad, m.sexo AS Sexo, c.nombre AS Cliente FROM mascotas m JOIN clientes c ON m.id_cliente=c.id_cliente ORDER BY m.nombre''',
        'citas': '''SELECT c.id_cita AS id, c.fecha AS Fecha, c.hora AS Hora, c.estado AS Estado, cl.nombre AS Cliente, m.nombre AS Mascota, d.nombre AS Doctor, s.nombre AS Servicio, su.nombre AS Sucursal FROM citas c JOIN clientes cl ON c.id_cliente=cl.id_cliente JOIN mascotas m ON c.id_mascota=m.id_mascota JOIN doctores d ON c.id_doctor=d.id_doctor JOIN servicios s ON c.id_servicio=s.id_servicio JOIN sucursales su ON c.id_sucursal=su.id_sucursal ORDER BY c.fecha DESC, c.hora DESC''',
        'ventas': '''SELECT v.id_venta AS id, v.fecha AS Fecha, COALESCE(cl.nombre, 'Sin cliente') AS Cliente, v.total AS Total FROM ventas v LEFT JOIN clientes cl ON v.id_cliente=cl.id_cliente ORDER BY v.fecha DESC'''
    }
    filas = db.execute(consultas[seccion]).fetchall()
    columnas = [k for k in filas[0].keys() if k != 'id'] if filas else {
        'clientes':['Nombre','Teléfono','Correo'],
        'mascotas':['Nombre','Especie','Raza','Edad','Sexo','Cliente'],
        'citas':['Fecha','Hora','Estado','Cliente','Mascota','Doctor','Servicio','Sucursal'],
        'ventas':['Fecha','Cliente','Total']
    }[seccion]
    db.close()
    return render_template('admin_resumen.html', titulo=nombres[seccion], seccion=seccion, filas=filas, columnas=columnas, error=error)


# ==========================================
# EJECUTAR LA APLICACIÓN
# ESTA PARTE SIEMPRE VA HASTA ABAJO
# ==========================================

from mejoras import instalar
instalar(app, conectar_db)

if __name__ == "__main__":
    app.run(debug=False)