# Food Store — Objetos del Esquema y Patrones

## Triggers — NO MODIFICAR

Funcionan de forma automática; no se tocan, reescriben ni reemplazan.

| Trigger | Tabla | Evento | Función | Qué hace |
|---|---|---|---|---|
| `trg_subtotal` | `detalle_pedido` | `BEFORE INSERT OR UPDATE` (fila) | `fn_set_subtotal()` | Copia `precio` de `producto` a `precio_unitario` si llega `NULL`; calcula `subtotal` |
| `trg_total_ins` | `detalle_pedido` | `AFTER INSERT` (sentencia) | `fn_recalcular_total()` | Recalcula `pedido.total` |
| `trg_total_upd` | `detalle_pedido` | `AFTER UPDATE` (sentencia) | `fn_recalcular_total()` | Ídem para `UPDATE` |
| `trg_validar_estado_pedido` | `pedido` | `BEFORE UPDATE OF estado` (fila) | `fn_validar_estado_pedido()` | Bloquea `CONFIRMADO → PENDIENTE` |

**Consecuencia para los permisos:** las funciones de trigger no son
`SECURITY DEFINER`, así que corren con los privilegios de quien dispara la
operación. Para insertar en `detalle_pedido`, el rol necesita además
`SELECT` sobre `producto` (lo lee `fn_set_subtotal`) y `UPDATE` sobre `pedido`
(lo escribe `fn_recalcular_total`).

## Procedimiento `sp_crear_pedido` — único camino para altas de pedidos

```sql
CALL sp_crear_pedido(
    p_usuario_id BIGINT,
    p_forma_pago forma_pago,
    p_items      JSONB   -- [{"producto_id": N, "cantidad": N}, ...]
);
```

Nunca `INSERT INTO pedido` + `INSERT INTO detalle_pedido` a mano. Garantiza:
usuario vigente, producto vigente y disponible, stock suficiente, descuento de
stock en la misma transacción, `FOR UPDATE` sobre el producto y rollback si
falla un ítem. Errores: usuario inexistente o eliminado; producto inexistente,
eliminado o no disponible; stock insuficiente.

**Consecuencia para los permisos:** es `SECURITY INVOKER` y, además de
insertar en `pedido` y `detalle_pedido`, **lee `usuario`**, hace `SELECT …
FOR UPDATE` sobre `producto` (requiere privilegio `UPDATE` sobre al menos una
columna) y **actualiza `producto.stock`**. Quien la ejecute necesita esos
privilegios, o la función debe cambiar de modelo. Es una decisión de diseño de
la Parte A (ver `AGENTS.md`); no se resuelve "a ojo".

## Vistas — usar en vez de reescribir el filtro a mano

| Vista | Para qué sirve | Archivo |
|---|---|---|
| `v_categorias_vigentes` | Categorías con `eliminado = FALSE` | `objects.sql` |
| `v_productos_vigentes` | Productos + categoría, ambos vigentes | `objects.sql` |
| `v_pedidos_resumen` | Pedidos vigentes + nombre completo del usuario | `objects.sql` |
| `v_pedido_detalle` | Líneas de detalle vigentes + nombre del producto | `objects.sql` |
| `v_usuario_seguro` | Usuarios **sin** `contrasena`; para listar/exponer usuarios, nunca `SELECT * FROM usuario` fuera de la autenticación | `views.sql` |

## Vista materializada `mv_facturacion_categoria_mes` (`materializadas.sql`)

Facturación por categoría y mes (pedidos `CONFIRMADO` vigentes). No se
actualiza sola: `REFRESH MATERIALIZED VIEW CONCURRENTLY
mv_facturacion_categoria_mes;`. El índice único `idx_mv_facturacion_cat_mes_pk`
`(categoria_id, mes)` es lo que permite el `CONCURRENTLY`: no borrarlo.

## Patrones de seguridad (Unidad 5)

Los bloques de abajo son **patrones**, no la solución: los nombres de objeto
son los de la base real, y cada permiso concreto lo decide y justifica la
spec de Kiro de la Parte A.

### 1. Roles de grupo y de login, re-ejecutables

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_app_lectura') THEN
        CREATE ROLE rol_app_lectura;            -- grupo: sin LOGIN
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_web') THEN
        CREATE ROLE app_web WITH LOGIN PASSWORD 'cambiar_en_produccion';
    END IF;
END $$;

GRANT USAGE ON SCHEMA public TO rol_app_lectura;
GRANT rol_app_lectura TO app_web;               -- el login solo recibe membresías
```

### 2. Privilegios puntuales (nunca `GRANT ALL`)

```sql
GRANT SELECT ON v_productos_vigentes, v_categorias_vigentes TO rol_app_lectura;
GRANT SELECT, INSERT, UPDATE ON pedido, detalle_pedido    TO rol_app_escritura;
GRANT EXECUTE ON PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB)
    TO rol_app_escritura;
```

### 3. Permiso a nivel de columna

```sql
-- rol_soporte ve todo de usuario salvo contrasena (y, si se decide, celular)
GRANT SELECT (id, nombre, apellido, mail, rol, eliminado, created_at)
    ON usuario TO rol_soporte;
```

### 4. `ALTER DEFAULT PRIVILEGES` con el dueño correcto

Solo afecta a objetos creados por el rol indicado en `FOR ROLE` (por omisión,
quien ejecuta la sentencia). Si las tablas las creó otro rol, no cubre nada.

```sql
SELECT tablename, tableowner FROM pg_tables WHERE schemaname = 'public';  -- ¿quién es dueño?

ALTER DEFAULT PRIVILEGES FOR ROLE <dueño_real> IN SCHEMA public
    REVOKE ALL ON TABLES FROM PUBLIC;           -- la política concreta la define la spec

-- Comprobación: crear una tabla de prueba como ese dueño y mirar
SELECT defaclrole::regrole, defaclnamespace::regnamespace, defaclobjtype, defaclacl
FROM pg_default_acl;
```

### 5. Autenticación (`fn_autenticar`, versión de la Clase 2)

```sql
CREATE OR REPLACE FUNCTION fn_autenticar(p_mail TEXT, p_pass TEXT)
RETURNS TABLE(id BIGINT, rol rol) AS $$
BEGIN
    RETURN QUERY
    SELECT u.id, u.rol
    FROM   usuario u
    WHERE  u.mail = p_mail
    AND    u.contrasena = crypt(p_pass, u.contrasena)
    AND    u.eliminado = FALSE;
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;
```

Parámetros tipados, sin concatenación, borrado lógico respetado. Corre con los
privilegios de quien la llama: ese rol necesita leer `usuario` (incluida
`contrasena`). Con el diseño de la clase, `app_web` no tiene ningún permiso
sobre `usuario`: hay que decidir cómo se resuelve y documentarlo. Con los
hashes ficticios de la base heredada devolverá siempre cero filas (o fallará):
probar con usuarios de prueba creados con hash real.

### 6. Reseteo de contraseña acotado (`SECURITY DEFINER`)

```sql
CREATE OR REPLACE FUNCTION fn_resetear_password(p_usuario_id BIGINT, p_nueva TEXT)
RETURNS VOID
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE usuario
    SET    contrasena = crypt(p_nueva, gen_salt('bf'))
    WHERE  id = p_usuario_id AND eliminado = FALSE;
END;
$$ LANGUAGE plpgsql;

REVOKE ALL ON FUNCTION fn_resetear_password FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_resetear_password TO rol_soporte;
```

Las tres piezas son inseparables: `SET search_path` (evita que un objeto falso
en otro esquema reemplace al real), `REVOKE … FROM PUBLIC` (por omisión toda
función es ejecutable por todos) y `GRANT EXECUTE` solo al rol que la necesita.

### 7. Probar un permiso como otro rol

Desde un usuario con privilegio para hacer `SET ROLE` (el que corrió
`roles.sql`). **Cada prueba que debe fallar va en su propio `BEGIN …
ROLLBACK`**: un error dentro de una transacción la deja abortada.

```sql
BEGIN;
SET LOCAL ROLE app_web;
SELECT * FROM usuario LIMIT 1;                  -- esperado según la spec: permission denied
ROLLBACK;

BEGIN;
SET LOCAL ROLE rol_soporte;
GRANT admin_datos TO rol_soporte;               -- escalamiento: debe fallar con permission denied
ROLLBACK;
```

### 8. Verificar "ni más, ni menos"

```sql
-- Equivalente de \du desde pgAdmin
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin
FROM pg_roles WHERE rolname !~ '^pg_' ORDER BY rolname;

-- Membresías
SELECT r.rolname AS rol, m.rolname AS miembro
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
ORDER BY 1, 2;

-- Privilegios sobre tablas y vistas
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte',
                  'rol_reportes','app_web','admin_datos')
ORDER BY grantee, table_name, privilege_type;

-- Lo que la consulta anterior NO muestra: columnas y rutinas
SELECT grantee, table_name, column_name, privilege_type
FROM information_schema.column_privileges
WHERE grantee IN ('rol_soporte') AND table_name = 'usuario';

SELECT grantee, routine_name, privilege_type
FROM information_schema.role_routine_grants
WHERE routine_schema = 'public';
```

`role_table_grants` solo lista privilegios cuyo otorgante o beneficiario es un
rol habilitado para el usuario actual: ejecutarla con el mismo usuario que
corrió los `GRANT`, o faltarán filas.

### 9. Anonimización (`usuario_anon`) y prueba de equivalencia

```sql
CREATE TABLE usuario_anon AS
SELECT id,
       'Usuario '  || id                     AS nombre,
       'Apellido ' || id                     AS apellido,
       'usuario'   || id || '@ejemplo.test'  AS mail,
       NULL::VARCHAR                         AS celular,
       'hash_no_valido'                      AS contrasena,
       rol, eliminado, created_at
FROM   usuario;

-- La misma agregación sobre las dos tablas; ambas diferencias deben dar 0 filas
(SELECT rol, date_trunc('month', created_at) AS mes, COUNT(*) FROM usuario_anon GROUP BY 1,2)
EXCEPT
(SELECT rol, date_trunc('month', created_at),         COUNT(*) FROM usuario      GROUP BY 1,2);
-- … y la misma consulta en el otro sentido (los dos EXCEPT, como en la U4)
```

La consulta equivalente sobre la tabla real, que se le pide a OpenCode, **no
se ejecuta con datos reales dentro de la conversación con la IA**: la IA
recibe la especificación y devuelve la consulta; el resultado se compara
localmente.

### 10. Anonimizar un log antes de dárselo a una IA

Reemplazar mails y nombres por valores sintéticos **consistentes** (la misma
persona, el mismo reemplazo en todo el log) para que la secuencia siga siendo
reconstruible:

```python
import re, sys
vistos = {}
def anon(m):
    return vistos.setdefault(m.group(0), f"usuario{len(vistos)+1}@ejemplo.test")
texto = open(sys.argv[1], encoding="utf-8").read()
texto = re.sub(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", anon, texto)
open(sys.argv[2], "w", encoding="utf-8").write(texto)
```

Después se revisa a mano: nombres propios, apellidos, direcciones IP no
locales y cualquier literal con datos reales. El script no sustituye la
revisión.

## Patrones de consulta heredados

- Preferir las vistas vigentes antes que reescribir `eliminado = FALSE`.
- Filtrar `eliminado = FALSE` en todas las tablas participantes.
- `SUM` con `COALESCE(..., 0)` para evitar `NULL`.
- Productos sin ventas: `LEFT JOIN … WHERE fk IS NULL`, no `NOT IN`.
