-- ============================================================================
-- roles.sql — Roles y permisos de minimo privilegio (Food Store, Parte A)
-- TP Unidad 5 — Base de Datos II
--
-- Sigue docs/kiro_roles_spec/design.md (seccion 5), paso por paso.
-- Ejecutar CONECTADO A copia_u5 como postgres (superusuario).
--
-- Todo el script va en una transaccion: si algo falla, ejecutar ROLLBACK; y no
-- queda nada a medias. Para un ensayo sin efectos, cambiar el COMMIT final por
-- ROLLBACK.
-- Es re-ejecutable: se puede correr mas de una vez sin error.
-- Las contrasenas son solo un marcador; cambiarlas fuera de este archivo.
-- ============================================================================

BEGIN;

-- Proteccion: no correr sobre la plantilla ni sobre la base 'postgres'.
DO $$
BEGIN
    IF current_database() IN ('postgres', 'plantilla_food_store') THEN
        RAISE EXCEPTION 'Base equivocada (%). Conectarse a copia_u5.', current_database();
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- Paso 1. Extension para crypt() / gen_salt() (la usan fn_autenticar y
--         fn_resetear_password).
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ----------------------------------------------------------------------------
-- Paso 2. Roles de grupo (NOLOGIN). Concentran los privilegios.
--         Si ya existian (version de la clase), se fuerzan los atributos.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_rol TEXT;
BEGIN
    FOREACH v_rol IN ARRAY ARRAY[
        'rol_app_lectura', 'rol_app_escritura', 'rol_app_auth',
        'rol_soporte', 'rol_reportes'
    ] LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_rol) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', v_rol);
        END IF;
        EXECUTE format(
            'ALTER ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE', v_rol);
    END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- Paso 3. Uso del esquema para cada grupo.
-- ----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public
    TO rol_app_lectura, rol_app_escritura, rol_app_auth, rol_soporte, rol_reportes;

-- ----------------------------------------------------------------------------
-- Paso 4. Roles de login. Deben existir ANTES del cambio de dueño.
--         D3: admin_datos sin SUPERUSER, CREATEDB ni CREATEROLE.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'admin_datos') THEN
        CREATE ROLE admin_datos WITH LOGIN PASSWORD 'cambiar_en_produccion'
            NOSUPERUSER NOCREATEDB NOCREATEROLE;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_web') THEN
        CREATE ROLE app_web WITH LOGIN PASSWORD 'cambiar_en_produccion'
            NOSUPERUSER NOCREATEDB NOCREATEROLE;
    END IF;
END $$;

ALTER ROLE admin_datos LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER ROLE app_web     LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;

-- admin_datos es dueño de los objetos y debe poder crear nuevos en public
-- (desde PostgreSQL 15 PUBLIC ya no tiene CREATE sobre ese esquema).
GRANT USAGE, CREATE ON SCHEMA public TO admin_datos;
-- Defensa en profundidad: quitar CREATE residual de PUBLIC sobre el esquema.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- Paso 5. D4/D6: la propiedad pasa a admin_datos, objeto por objeto.
--         NUNCA usar REASSIGN OWNED BY postgres (afecta a todo el servidor).
--         Solo objetos que YA existen en la base heredada.
-- ----------------------------------------------------------------------------
ALTER TABLE categoria      OWNER TO admin_datos;
ALTER TABLE producto       OWNER TO admin_datos;
ALTER TABLE usuario        OWNER TO admin_datos;
ALTER TABLE pedido         OWNER TO admin_datos;
ALTER TABLE detalle_pedido OWNER TO admin_datos;

ALTER VIEW v_categorias_vigentes OWNER TO admin_datos;
ALTER VIEW v_productos_vigentes  OWNER TO admin_datos;
ALTER VIEW v_pedidos_resumen     OWNER TO admin_datos;
ALTER VIEW v_pedido_detalle      OWNER TO admin_datos;
ALTER VIEW v_usuario_seguro      OWNER TO admin_datos;

ALTER MATERIALIZED VIEW mv_facturacion_categoria_mes OWNER TO admin_datos;

ALTER FUNCTION calcular_total_pedido(BIGINT) OWNER TO admin_datos;
ALTER FUNCTION fn_set_subtotal()             OWNER TO admin_datos;
ALTER FUNCTION fn_recalcular_total()         OWNER TO admin_datos;
ALTER FUNCTION fn_validar_estado_pedido()    OWNER TO admin_datos;

ALTER PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB) OWNER TO admin_datos;

ALTER TYPE rol           OWNER TO admin_datos;
ALTER TYPE estado_pedido OWNER TO admin_datos;
ALTER TYPE forma_pago    OWNER TO admin_datos;

-- ----------------------------------------------------------------------------
-- Paso 6. Rutinas SECURITY DEFINER (D1, D2, D6).
--         Corren con los privilegios de su dueño (admin_datos, no superusuario).
--         Las tres piezas son inseparables: SET search_path, REVOKE FROM PUBLIC
--         y GRANT EXECUTE puntual (este ultimo en el paso 7).
-- ----------------------------------------------------------------------------

-- D1: sp_crear_pedido ya existe; solo cambia el atributo. El cuerpo y los
--     triggers no se tocan.
ALTER PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB)
    SECURITY DEFINER SET search_path = public, pg_temp;
REVOKE ALL ON PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB) FROM PUBLIC;

-- D2: fn_autenticar devuelve solo (id, rol); la contrasena nunca sale de la funcion.
--     Todas las columnas van calificadas (u.id, u.rol) para no chocar con las
--     columnas de salida id y rol.
CREATE OR REPLACE FUNCTION fn_autenticar(p_mail TEXT, p_pass TEXT)
RETURNS TABLE(id BIGINT, rol rol)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.rol
    FROM   usuario u
    WHERE  u.mail = p_mail
    AND    u.contrasena = crypt(p_pass, u.contrasena)
    AND    u.eliminado = FALSE;
END;
$$;
ALTER FUNCTION fn_autenticar(TEXT, TEXT) OWNER TO admin_datos;
REVOKE ALL ON FUNCTION fn_autenticar(TEXT, TEXT) FROM PUBLIC;

-- fn_resetear_password: un unico UPDATE acotado; guarda solo el hash.
CREATE OR REPLACE FUNCTION fn_resetear_password(p_usuario_id BIGINT, p_nueva TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE usuario
    SET    contrasena = crypt(p_nueva, gen_salt('bf'))
    WHERE  id = p_usuario_id
    AND    eliminado = FALSE
    AND    rol <> 'ADMIN';
END;
$$;
ALTER FUNCTION fn_resetear_password(BIGINT, TEXT) OWNER TO admin_datos;
REVOKE ALL ON FUNCTION fn_resetear_password(BIGINT, TEXT) FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- Paso 7. Privilegios sobre objetos: uno por rol y por objeto, sin GRANT ALL.
-- ----------------------------------------------------------------------------

-- 7.0 Limpieza previa: si los roles existian de la clase, pueden traer permisos
--     viejos. Se quitan todos para que el resultado sea exactamente el de la spec.
REVOKE ALL ON ALL TABLES    IN SCHEMA public
    FROM rol_app_lectura, rol_app_escritura, rol_app_auth, rol_soporte, rol_reportes, app_web;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public
    FROM rol_app_lectura, rol_app_escritura, rol_app_auth, rol_soporte, rol_reportes, app_web;
REVOKE ALL ON ALL ROUTINES  IN SCHEMA public
    FROM rol_app_lectura, rol_app_escritura, rol_app_auth, rol_soporte, rol_reportes, app_web;

-- rol_app_lectura: solo las dos vistas del catalogo vigente (ya filtran eliminado).
GRANT SELECT ON v_productos_vigentes, v_categorias_vigentes TO rol_app_lectura;

-- rol_app_escritura: unicamente EJECUTAR el procedimiento de alta de pedidos;
-- no recibe ningun privilegio de tabla (D1).
GRANT EXECUTE ON PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB)
    TO rol_app_escritura;

-- rol_app_auth: unicamente EJECUTAR la autenticacion (D2).
GRANT EXECUTE ON FUNCTION fn_autenticar(TEXT, TEXT) TO rol_app_auth;

-- rol_soporte: identifica al cliente sin ver contrasena ni celular (D5) ...
GRANT SELECT (id, nombre, apellido, mail, rol, eliminado, created_at)
    ON usuario TO rol_soporte;
GRANT SELECT ON v_pedidos_resumen TO rol_soporte;
-- ... y puede destrabarlo con el reseteo acotado.
GRANT EXECUTE ON FUNCTION fn_resetear_password(BIGINT, TEXT) TO rol_soporte;

-- rol_reportes: solo la vista materializada de facturacion (datos agregados).
GRANT SELECT ON mv_facturacion_categoria_mes TO rol_reportes;

-- ----------------------------------------------------------------------------
-- Paso 8. Membresias. El login solo recibe membresias, ningun privilegio propio.
--         Se quitan membresias heredadas que no corresponden (escalamiento).
-- ----------------------------------------------------------------------------
REVOKE admin_datos
    FROM app_web, rol_app_lectura, rol_app_escritura, rol_app_auth, rol_soporte, rol_reportes;
REVOKE rol_soporte, rol_reportes FROM app_web;

GRANT rol_app_lectura, rol_app_escritura, rol_app_auth TO app_web;

-- ----------------------------------------------------------------------------
-- Paso 9. Objetos futuros creados por admin_datos.
--         Tablas: PUBLIC ya no recibe nada por omision; se deja explicito.
--         Funciones: el EXECUTE para PUBLIC es el valor por omision GLOBAL de
--         PostgreSQL, y un REVOKE "IN SCHEMA" no puede quitarlo; por eso este
--         ALTER DEFAULT PRIVILEGES va SIN "IN SCHEMA".
-- ----------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA public
    REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

COMMIT;   -- cambiar por ROLLBACK; para un ensayo sin efectos

-- ----------------------------------------------------------------------------
-- Paso 10. LIMPIEZA (comentada). Descomentar SOLO para partir de cero.
--          El orden es obligatorio.
-- ----------------------------------------------------------------------------
-- BEGIN;
-- -- 1) Devolver la propiedad a postgres. Sin esto, DROP OWNED BY admin_datos
-- --    BORRARIA todas las tablas, vistas y funciones del esquema.
-- REASSIGN OWNED BY admin_datos TO postgres;
-- -- 2) Revocar privilegios y limpiar default privileges. admin_datos se incluye
-- --    porque, aunque ya no posee objetos, tiene ALTER DEFAULT PRIVILEGES a su
-- --    nombre; sin esto DROP ROLE admin_datos falla.
-- DROP OWNED BY rol_app_lectura, rol_app_escritura, rol_app_auth,
--               rol_soporte, rol_reportes, app_web, admin_datos;
-- -- 3) Eliminar los siete roles del proyecto.
-- DROP ROLE IF EXISTS rol_app_lectura, rol_app_escritura, rol_app_auth,
--                     rol_soporte, rol_reportes, app_web, admin_datos;
-- COMMIT;
