-- ==========================================
-- BASE DE DATOS
-- CLÍNICA VETERINARIA PATITAS
-- ==========================================


-- SUCURSALES
CREATE TABLE sucursales (
    id_sucursal INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    ciudad TEXT NOT NULL,
    direccion TEXT,
    horario TEXT
);


-- USUARIOS
CREATE TABLE usuarios (
    id_usuario INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    correo TEXT NOT NULL UNIQUE,
    contrasena TEXT NOT NULL,
    tipo_usuario TEXT NOT NULL
);


-- CLIENTES
CREATE TABLE clientes (
    id_cliente INTEGER PRIMARY KEY AUTOINCREMENT,
    id_usuario INTEGER,
    nombre TEXT NOT NULL,
    telefono TEXT,
    correo TEXT,

    FOREIGN KEY (id_usuario)
    REFERENCES usuarios(id_usuario)
);


-- MASCOTAS
CREATE TABLE mascotas (
    id_mascota INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    especie TEXT NOT NULL,
    raza TEXT,
    edad INTEGER,
    sexo TEXT,
    id_cliente INTEGER NOT NULL,

    FOREIGN KEY (id_cliente)
    REFERENCES clientes(id_cliente)
);


-- DOCTORES
CREATE TABLE doctores (
    id_doctor INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    especialidad TEXT,
    telefono TEXT,
    id_sucursal INTEGER NOT NULL,

    FOREIGN KEY (id_sucursal)
    REFERENCES sucursales(id_sucursal)
);


-- EMPLEADOS
CREATE TABLE empleados (
    id_empleado INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    puesto TEXT NOT NULL,
    telefono TEXT,
    id_sucursal INTEGER NOT NULL,

    FOREIGN KEY (id_sucursal)
    REFERENCES sucursales(id_sucursal)
);


-- SERVICIOS
CREATE TABLE servicios (
    id_servicio INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    descripcion TEXT,
    precio REAL NOT NULL
);


-- CITAS
CREATE TABLE citas (
    id_cita INTEGER PRIMARY KEY AUTOINCREMENT,
    fecha TEXT NOT NULL,
    hora TEXT NOT NULL,
    estado TEXT DEFAULT 'Programada',

    id_cliente INTEGER NOT NULL,
    id_mascota INTEGER NOT NULL,
    id_doctor INTEGER NOT NULL,
    id_servicio INTEGER NOT NULL,
    id_sucursal INTEGER NOT NULL,

    FOREIGN KEY (id_cliente)
    REFERENCES clientes(id_cliente),

    FOREIGN KEY (id_mascota)
    REFERENCES mascotas(id_mascota),

    FOREIGN KEY (id_doctor)
    REFERENCES doctores(id_doctor),

    FOREIGN KEY (id_servicio)
    REFERENCES servicios(id_servicio),

    FOREIGN KEY (id_sucursal)
    REFERENCES sucursales(id_sucursal)
);


-- PRODUCTOS
CREATE TABLE productos (
    id_producto INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre TEXT NOT NULL,
    descripcion TEXT,
    categoria TEXT,
    precio REAL NOT NULL
);


-- INVENTARIO
CREATE TABLE inventario (
    id_inventario INTEGER PRIMARY KEY AUTOINCREMENT,
    id_producto INTEGER NOT NULL,
    id_sucursal INTEGER NOT NULL,
    existencias INTEGER DEFAULT 0,

    FOREIGN KEY (id_producto)
    REFERENCES productos(id_producto),

    FOREIGN KEY (id_sucursal)
    REFERENCES sucursales(id_sucursal)
);


-- COMPRAS
CREATE TABLE compras (
    id_compra INTEGER PRIMARY KEY AUTOINCREMENT,
    id_cliente INTEGER NOT NULL,
    fecha TEXT NOT NULL,
    total REAL NOT NULL,

    FOREIGN KEY (id_cliente)
    REFERENCES clientes(id_cliente)
);


-- DETALLE DE COMPRA
CREATE TABLE detalle_compra (
    id_detalle INTEGER PRIMARY KEY AUTOINCREMENT,
    id_compra INTEGER NOT NULL,
    id_producto INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    precio REAL NOT NULL,

    FOREIGN KEY (id_compra)
    REFERENCES compras(id_compra),

    FOREIGN KEY (id_producto)
    REFERENCES productos(id_producto)
);


-- VENTAS
CREATE TABLE ventas (
    id_venta INTEGER PRIMARY KEY AUTOINCREMENT,
    id_cliente INTEGER,
    fecha TEXT NOT NULL,
    total REAL NOT NULL,

    FOREIGN KEY (id_cliente)
    REFERENCES clientes(id_cliente)
);

-- ==========================================
-- SUCURSALES
-- ==========================================

INSERT INTO sucursales
(nombre, ciudad, direccion, horario)
VALUES
(
    'Patitas Centro',
    'Monterrey, Nuevo León',
    'Centro de Monterrey',
    'Lunes a sábado de 9:00 AM a 8:00 PM'
);

INSERT INTO sucursales
(nombre, ciudad, direccion, horario)
VALUES
(
    'Patitas Valle',
    'San Pedro Garza García, Nuevo León',
    'San Pedro Garza García',
    'Lunes a sábado de 9:00 AM a 8:00 PM'
);


-- ==========================================
-- SERVICIOS
-- ==========================================

INSERT INTO servicios
(nombre, descripcion, precio)
VALUES
(
    'Consulta general',
    'Revisión médica general de la mascota',
    350
);

INSERT INTO servicios
(nombre, descripcion, precio)
VALUES
(
    'Vacunación',
    'Aplicación de vacunas para perros y gatos',
    300
);

INSERT INTO servicios
(nombre, descripcion, precio)
VALUES
(
    'Desparasitación',
    'Tratamiento contra parásitos',
    250
);

INSERT INTO servicios
(nombre, descripcion, precio)
VALUES
(
    'Estética',
    'Baño, corte y limpieza de la mascota',
    400
);


-- ==========================================
-- DOCTORES
-- ==========================================

INSERT INTO doctores
(nombre, especialidad, telefono, id_sucursal)
VALUES
(
    'Carlos Martínez',
    'Medicina veterinaria general',
    '8112345678',
    1
);

INSERT INTO doctores
(nombre, especialidad, telefono, id_sucursal)
VALUES
(
    'Ana Rodríguez',
    'Medicina preventiva',
    '8187654321',
    2
);

INSERT INTO doctores
(nombre, especialidad, telefono, id_sucursal)
VALUES
(
    'Luis García',
    'Cirugía veterinaria',
    '8111112222',
    1
);


-- ==========================================
-- PRODUCTOS
-- ==========================================

INSERT INTO productos
(nombre, descripcion, categoria, precio)
VALUES
(
    'Alimento Premium Perro',
    'Alimento para perro adulto',
    'Alimentos',
    650
);

INSERT INTO productos
(nombre, descripcion, categoria, precio)
VALUES
(
    'Pelota para perro',
    'Juguete resistente para mascotas',
    'Accesorios',
    120
);

INSERT INTO productos
(nombre, descripcion, categoria, precio)
VALUES
(
    'Shampoo para mascotas',
    'Shampoo para higiene y cuidado',
    'Higiene',
    180
);