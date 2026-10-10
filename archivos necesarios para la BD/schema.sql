-- ============================================================
-- FOOD STORE - schema.sql
-- Tipos, tablas, restricciones e índices
-- ============================================================

-- Tipos enumerados
CREATE TYPE rol AS ENUM ('ADMIN','USUARIO');
CREATE TYPE estado_pedido AS ENUM ('PENDIENTE','CONFIRMADO','TERMINADO','CANCELADO');
CREATE TYPE forma_pago AS ENUM ('TARJETA','TRANSFERENCIA','EFECTIVO');

-- ============================================================
-- CATEGORIA
-- ============================================================
CREATE TABLE categoria (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- corregido: BIGGINT -> BIGINT
    nombre       VARCHAR(80) NOT NULL UNIQUE,
    descripcion  VARCHAR(255),
    eliminado    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- PRODUCTO
-- ============================================================
CREATE TABLE producto (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre        VARCHAR(120) NOT NULL,
    precio        NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
    descripcion   VARCHAR(255),
    stock         INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    imagen        VARCHAR(255),
    disponible    BOOLEAN NOT NULL DEFAULT TRUE,
    categoria_id  BIGINT NOT NULL REFERENCES categoria(id),
    eliminado     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- USUARIO
-- ============================================================
CREATE TABLE usuario (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre       VARCHAR(80) NOT NULL,
    apellido     VARCHAR(80) NOT NULL,
    mail         VARCHAR(120) NOT NULL UNIQUE,
    celular      VARCHAR(30),
    contrasena   VARCHAR(255) NOT NULL,
    rol          rol NOT NULL DEFAULT 'USUARIO',
    eliminado    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_usuario_mail_formato CHECK (
        mail ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    )
);

-- ============================================================
-- PEDIDO
-- ============================================================
CREATE TABLE pedido (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha        DATE NOT NULL DEFAULT CURRENT_DATE CHECK (fecha <= CURRENT_DATE),
    estado       estado_pedido NOT NULL DEFAULT 'PENDIENTE',
    total        NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    forma_pago   forma_pago NOT NULL,
    usuario_id   BIGINT NOT NULL REFERENCES usuario(id),
    eliminado    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- DETALLE_PEDIDO
-- ============================================================
CREATE TABLE detalle_pedido (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cantidad         INTEGER NOT NULL CHECK (cantidad > 0),
    precio_unitario  NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal         NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
    pedido_id        BIGINT NOT NULL REFERENCES pedido(id) ON DELETE RESTRICT,
    producto_id      BIGINT NOT NULL REFERENCES producto(id),
    eliminado        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (pedido_id, producto_id)
);

-- ============================================================
-- ÍNDICES REQUERIDOS
-- ============================================================

-- Soporta el listado de productos por categoría
CREATE INDEX idx_producto_categoria_id ON producto(categoria_id);

-- Soporta el historial de pedidos por usuario
CREATE INDEX idx_pedido_usuario_id ON pedido(usuario_id);

-- Índice parcial: solo productos no eliminados, para búsquedas por nombre
CREATE INDEX idx_producto_nombre_vigente ON producto(nombre) WHERE eliminado = FALSE;
