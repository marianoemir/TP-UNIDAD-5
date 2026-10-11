-- ============================================================================
-- verificacion_roles.sql — Pruebas T01 a T23 de la Parte A (con rol real)
-- Sigue docs/kiro_roles_spec/design.md, seccion 6.
--
-- Ejecutar CONECTADO A copia_u5 como postgres, TODO EL SCRIPT DE UNA VEZ (F5).
-- El resultado es la tabla final: una fila por prueba con OK o FALLO.
--
-- Como funciona: cada prueba se ejecuta con SET LOCAL ROLE <rol> dentro de un
-- subbloque que SIEMPRE termina en excepcion, asi que todo se deshace solo
-- (no queda ningun pedido, ni cambio de contrasena, ni rol activo). Un error de
-- permisos no frena el script. Usa solo objetos temporales de esta sesion.
--
-- Esperado: 'ok' = la sentencia funciona; 'filas' = funciona y devuelve >= 1
-- fila; 'denegado' = falla con "permission denied" / "must be owner".
-- Si una prueba da FALLO: es un hallazgo; corregir roles.sql y registrarlo en
-- la bitacora.
-- Nota: T04 y T14 usan una contrasena de prueba; no correr con auditoria
-- (log_statement) activa si el log va a compartirse.
-- ============================================================================

DROP TABLE IF EXISTS pg_temp.resultados;
CREATE TEMP TABLE resultados (
    id        TEXT,
    rol       TEXT,
    esperado  TEXT,
    obtenido  TEXT,
    estado    TEXT
);

CREATE OR REPLACE FUNCTION pg_temp.probar(
    p_id TEXT, p_rol TEXT, p_sql TEXT, p_esperado TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_obtenido TEXT;
    v_filas    BIGINT;
BEGIN
    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', p_rol);
        EXECUTE p_sql;
        GET DIAGNOSTICS v_filas = ROW_COUNT;
        IF p_esperado = 'filas' AND v_filas = 0 THEN
            RAISE EXCEPTION 'sin filas' USING ERRCODE = 'ZZ002';
        END IF;
        RAISE EXCEPTION 'ok' USING ERRCODE = 'ZZ001';
    EXCEPTION
        WHEN SQLSTATE 'ZZ001' THEN v_obtenido := CASE WHEN p_esperado = 'filas' THEN 'filas' ELSE 'ok' END;
        WHEN SQLSTATE 'ZZ002' THEN v_obtenido := 'sin_filas';
        WHEN insufficient_privilege THEN v_obtenido := 'denegado';
        WHEN OTHERS THEN v_obtenido := 'error: ' || SQLERRM;
    END;
    INSERT INTO pg_temp.resultados
    VALUES (p_id, p_rol, p_esperado, v_obtenido,
            CASE WHEN v_obtenido = p_esperado THEN 'OK' ELSE 'FALLO' END);
END;
$$;

-- R1 — Catalogo
SELECT pg_temp.probar('T01', 'app_web', 'SELECT * FROM v_productos_vigentes LIMIT 1', 'filas');
SELECT pg_temp.probar('T02', 'app_web', 'SELECT * FROM producto LIMIT 1', 'denegado');
SELECT pg_temp.probar('T03', 'app_web', 'SELECT * FROM usuario LIMIT 1', 'denegado');

-- R2 — Alta de pedidos (los ids se buscan como postgres, antes del cambio de rol)
SELECT pg_temp.probar('T04', 'app_web',
    format($q$CALL sp_crear_pedido(%s, 'EFECTIVO', '[{"producto_id":%s,"cantidad":1}]'::jsonb)$q$,
           (SELECT id FROM usuario  WHERE NOT eliminado ORDER BY id LIMIT 1),
           (SELECT id FROM producto WHERE NOT eliminado AND disponible AND stock > 0 ORDER BY id LIMIT 1)),
    'ok');
SELECT pg_temp.probar('T05', 'app_web',
    $q$INSERT INTO pedido(usuario_id, forma_pago) VALUES (1, 'EFECTIVO')$q$, 'denegado');
SELECT pg_temp.probar('T06', 'app_web', 'UPDATE producto SET stock = 99 WHERE id = 1', 'denegado');

-- R3 — Autenticacion
SELECT pg_temp.probar('T07', 'app_web',
    $q$SELECT * FROM fn_autenticar('test@test.com', 'clave')$q$, 'ok');
SELECT pg_temp.probar('T08', 'app_web', 'SELECT contrasena FROM usuario LIMIT 1', 'denegado');

-- R4 — Soporte
SELECT pg_temp.probar('T09', 'rol_soporte', 'SELECT id, nombre, mail FROM usuario LIMIT 1', 'filas');
SELECT pg_temp.probar('T10', 'rol_soporte', 'SELECT contrasena FROM usuario LIMIT 1', 'denegado');
SELECT pg_temp.probar('T11', 'rol_soporte', 'SELECT celular FROM usuario LIMIT 1', 'denegado');
SELECT pg_temp.probar('T12', 'rol_soporte', 'SELECT * FROM usuario LIMIT 1', 'denegado');
SELECT pg_temp.probar('T13', 'rol_soporte', 'SELECT * FROM v_pedidos_resumen LIMIT 1', 'filas');
SELECT pg_temp.probar('T14', 'rol_soporte',
    format($q$SELECT fn_resetear_password(%s, 'NuevaClave123')$q$,
           (SELECT id FROM usuario WHERE NOT eliminado ORDER BY id LIMIT 1)),
    'ok');

-- R8 — Escalamiento bloqueado
SELECT pg_temp.probar('T15', 'rol_soporte', 'GRANT admin_datos TO rol_soporte', 'denegado');
SELECT pg_temp.probar('T16', 'rol_soporte', 'UPDATE producto SET precio = 1 WHERE id = 1', 'denegado');

-- R5 — Reportes
SELECT pg_temp.probar('T17', 'rol_reportes', 'SELECT * FROM mv_facturacion_categoria_mes LIMIT 1', 'filas');
SELECT pg_temp.probar('T18', 'rol_reportes', 'REFRESH MATERIALIZED VIEW mv_facturacion_categoria_mes', 'denegado');
SELECT pg_temp.probar('T19', 'rol_reportes', 'SELECT * FROM pedido LIMIT 1', 'denegado');

-- "Ni mas": rol_app_escritura no lee tablas
SELECT pg_temp.probar('T20', 'rol_app_escritura', 'SELECT * FROM pedido LIMIT 1', 'denegado');

-- Extras: aislamiento entre grupos y escalamiento por SET ROLE
SELECT pg_temp.probar('T21', 'app_web',
    $q$SELECT fn_resetear_password(1, 'NuevaClave123')$q$, 'denegado');
-- T22: app_web no puede asumir admin_datos. No se prueba con SET ROLE desde esta sesion:
-- SET ROLE se valida contra el usuario de la sesion (postgres, superusuario) y siempre
-- funcionaria. Se comprueba la membresia, que es lo que habilitaria ese SET ROLE.
INSERT INTO pg_temp.resultados
SELECT 'T22', 'app_web', 'sin_membresia',
       CASE WHEN pg_has_role('app_web', 'admin_datos', 'MEMBER') THEN 'es_miembro' ELSE 'sin_membresia' END,
       CASE WHEN pg_has_role('app_web', 'admin_datos', 'MEMBER') THEN 'FALLO' ELSE 'OK' END;

-- T23: rol_soporte NO puede resetear la clave de un usuario ADMIN de la aplicacion
-- (filtro "rol <> 'ADMIN'" de fn_resetear_password). Se compara el hash antes y despues.
DO $$
DECLARE
    v_admin   BIGINT;
    v_antes   TEXT;
    v_despues TEXT;
    v_res     TEXT := 'sin_admin';
BEGIN
    SELECT id, contrasena INTO v_admin, v_antes
    FROM   usuario
    WHERE  rol = 'ADMIN' AND NOT eliminado
    ORDER  BY id LIMIT 1;

    IF v_admin IS NOT NULL THEN
        BEGIN
            SET LOCAL ROLE rol_soporte;
            PERFORM fn_resetear_password(v_admin, 'NuevaClave123');
            RESET ROLE;
            SELECT contrasena INTO v_despues FROM usuario WHERE id = v_admin;
            v_res := CASE WHEN v_despues = v_antes THEN 'sin_cambio' ELSE 'cambiado' END;
            RAISE EXCEPTION 'fin' USING ERRCODE = 'ZZ001';   -- deshace todo
        EXCEPTION
            WHEN SQLSTATE 'ZZ001' THEN NULL;
        END;
    END IF;

    INSERT INTO pg_temp.resultados
    VALUES ('T23', 'rol_soporte', 'sin_cambio', v_res,
            CASE WHEN v_res = 'sin_cambio' THEN 'OK' ELSE 'FALLO' END);
END $$;

-- Resultado: copiar esta tabla a docs/verificacion_permisos.md (seccion 5)
SELECT id, rol, esperado, obtenido, estado FROM pg_temp.resultados ORDER BY id;
