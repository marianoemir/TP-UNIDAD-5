# Design — Roles y permisos de mínimo privilegio (Food Store, Parte A)

> Spec definitiva. Los nombres de objeto corresponden exactamente a la base real (`copia_u5`).
> Esta sección se escribe **antes** de `sql/roles.sql` (requisito de la consigna).

---

## 1. Decisiones de diseño confirmadas

| # | Tema | Hallazgo en la base real | Decisión adoptada | Alternativa descartada y motivo |
|---|---|---|---|---|
| **D1** | `sp_crear_pedido` es `SECURITY INVOKER` | El procedimiento lee `usuario`, hace `SELECT … FOR UPDATE` y `UPDATE` sobre `producto`, inserta en `pedido` y `detalle_pedido`, y dispara triggers que también leen `producto` y actualizan `pedido`. Con el diseño original de la clase, `app_web` no tiene permisos sobre ninguna de esas tablas y la llamada falla. | Cambiar el procedimiento a `SECURITY DEFINER SET search_path = public, pg_temp`. `REVOKE ALL ON PROCEDURE … FROM PUBLIC`. `GRANT EXECUTE` solo a `rol_app_escritura`. El cuerpo, los triggers y la lógica no se modifican. `rol_app_escritura` **no** recibe ningún privilegio de tabla. | GRANTs por columna sobre `usuario`, `producto`, `pedido`, `detalle_pedido` a `rol_app_escritura`: amplía la superficie innecesariamente y expone la tabla `usuario` al backend. |
| **D2** | `fn_autenticar` es `SECURITY INVOKER` | Lee `usuario.contrasena` para comparar el hash. `app_web` no tiene ningún permiso sobre `usuario`, así que la llamada falla con `permission denied`. | Cambiar a `SECURITY DEFINER SET search_path = public, pg_temp`. Firma: `fn_autenticar(p_mail TEXT, p_pass TEXT) RETURNS TABLE(id BIGINT, rol rol)`. `REVOKE ALL ON FUNCTION … FROM PUBLIC`. `GRANT EXECUTE` solo a `rol_app_auth`. | `GRANT SELECT (id, mail, contrasena, rol, eliminado) ON usuario TO rol_app_auth`: expone los hashes bcrypt al rol y a cualquier consulta directa posterior. |
| **D3** | `admin_datos` con atributos administrativos | El apunte de la clase lo crea con `CREATEDB CREATEROLE`. | `admin_datos` con `LOGIN`, `NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE`. Ser dueño de los objetos del esquema no requiere atributos de servidor. | Mantener `CREATEDB CREATEROLE`: privilegios amplios que permiten crear bases y roles en todo el servidor, innecesarios para administrar una sola base. |
| **D4** | Dueño de los objetos es `postgres` | `SELECT tablename, tableowner FROM pg_tables WHERE schemaname = 'public'` muestra `postgres` como dueño de todo. `ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos` no cubriría los objetos existentes. | Transferir la propiedad a `admin_datos` con `ALTER TABLE … OWNER TO`, `ALTER VIEW … OWNER TO`, `ALTER MATERIALIZED VIEW … OWNER TO`, `ALTER FUNCTION … OWNER TO`, `ALTER PROCEDURE … OWNER TO`, objeto por objeto. **Nunca** `REASSIGN OWNED BY postgres`: ese comando afecta objetos de `postgres` en todo el servidor (otras bases, roles del sistema). | Dejar `postgres` como dueño: `ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos` solo cubriría objetos futuros creados por él; `admin_datos` no podría administrar los existentes. |
| **D5** | `v_usuario_seguro` expone `celular` | La vista oculta `contrasena` pero incluye `celular`. Si soporte recibe `SELECT` sobre la vista, accede al teléfono sin decisión explícita. | `rol_soporte` recibe `GRANT SELECT (id, nombre, apellido, mail, rol, eliminado, created_at) ON usuario` directamente (sin `celular` ni `contrasena`). **No** recibe permiso sobre `v_usuario_seguro`. Si en el futuro soporte necesita llamar al cliente, se agrega `celular` y se justifica en la bitácora. | Dar `SELECT` sobre `v_usuario_seguro` a soporte: expone `celular` implícitamente, sin que el equipo tomara esa decisión. |
| **D6** | Dueño de las rutinas `SECURITY DEFINER` | Una función `SECURITY DEFINER` corre con los privilegios de su dueño. Si el dueño fuera `postgres` (superusuario), la función tendría acceso sin restricciones a todo el servidor. `fn_autenticar` y `fn_resetear_password` no existen en `base_heredada`: se crean en `roles.sql`. `sp_crear_pedido` existe y hoy pertenece a `postgres`. | `sp_crear_pedido` pasa a `admin_datos` en el paso 5 (cambio de dueño junto con el resto de los objetos heredados). `fn_autenticar` y `fn_resetear_password` se crean directamente con `admin_datos` como dueño en el paso 6: inmediatamente después de cada `CREATE OR REPLACE FUNCTION` se ejecuta `ALTER FUNCTION … OWNER TO admin_datos`. `admin_datos` no es superusuario, así que la superficie de las funciones queda acotada a los objetos que ese rol puede acceder como dueño. | Dejar el dueño en `postgres`: la función heredaría privilegios de superusuario durante su ejecución, lo que viola el principio de mínimo privilegio. |

---

## 2. Arquitectura de roles

```
Rol de login      Roles de grupo (NOLOGIN)        Objetos sobre los que actúa
─────────────────────────────────────────────────────────────────────────────
app_web ────────► rol_app_lectura  ─────────────► SELECT: v_productos_vigentes
                │                                         v_categorias_vigentes
                │
                ├───────────────► rol_app_escritura ───► EXECUTE: sp_crear_pedido(BIGINT,forma_pago,JSONB)
                │                                        (sin privilegios de tabla)
                │
                └───────────────► rol_app_auth ────────► EXECUTE: fn_autenticar(TEXT,TEXT)
                                                         (sin privilegios de tabla)

(sin rol de login asignado)
                  rol_soporte ────────────────────────► SELECT(columnas): usuario
                                                        SELECT: v_pedidos_resumen
                                                        EXECUTE: fn_resetear_password(BIGINT,TEXT)

                  rol_reportes ───────────────────────► SELECT: mv_facturacion_categoria_mes

admin_datos ──── dueño de todos los objetos del esquema public (tablas, vistas, funciones, procedimientos, tipos)
                 No tiene privilegios explícitos de DML: el dueño puede hacer ALTER/DROP/GRANT,
                 no necesita GRANT adicional sobre sus propios objetos.
```

Regla: los privilegios viven en roles de grupo; los logins solo reciben membresías.
Todo grupo recibe `GRANT USAGE ON SCHEMA public`.

---

## 3. Tabla de privilegios esperados ("ni más, ni menos")

Esta tabla es la fuente de verdad. La verificación de la sección 4 debe coincidir exactamente.

### 3a. Atributos de los roles

| Rol | `rolcanlogin` | `rolsuper` | `rolcreaterole` | `rolcreatedb` | Contraseña en script |
|---|:---:|:---:|:---:|:---:|---|
| `rol_app_lectura` | `f` | `f` | `f` | `f` | — |
| `rol_app_escritura` | `f` | `f` | `f` | `f` | — |
| `rol_app_auth` | `f` | `f` | `f` | `f` | — |
| `rol_soporte` | `f` | `f` | `f` | `f` | — |
| `rol_reportes` | `f` | `f` | `f` | `f` | — |
| `app_web` | `t` | `f` | `f` | `f` | `'cambiar_en_produccion'` |
| `admin_datos` | `t` | `f` | `f` | `f` | `'cambiar_en_produccion'` |

### 3b. Membresías (`pg_auth_members`)

| Rol de grupo | Miembro (login) |
|---|---|
| `rol_app_lectura` | `app_web` |
| `rol_app_escritura` | `app_web` |
| `rol_app_auth` | `app_web` |

`rol_soporte` y `rol_reportes` no tienen miembros de login en `roles.sql`.
Los logins de prueba para soporte se crean en `simulacro_incidente.sql`.

### 3c. Privilegios sobre tablas y vistas (`role_table_grants`)

| Rol | Objeto | Privilegios |
|---|---|---|
| `rol_app_lectura` | `v_productos_vigentes` | `SELECT` |
| `rol_app_lectura` | `v_categorias_vigentes` | `SELECT` |
| `rol_soporte` | `v_pedidos_resumen` | `SELECT` |
| `rol_reportes` | `mv_facturacion_categoria_mes` | `SELECT` |

Ninguna tabla base (`categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`)
aparece en esta lista para ningún rol de aplicación.

### 3d. Privilegios por columna (`column_privileges`)

| Rol | Tabla | Columnas con `SELECT` | Columnas sin permiso |
|---|---|---|---|
| `rol_soporte` | `usuario` | `id`, `nombre`, `apellido`, `mail`, `rol`, `eliminado`, `created_at` | `celular`, `contrasena` |

### 3e. Privilegios sobre rutinas (`role_routine_grants`)

| Rol | Rutina | Privilegio |
|---|---|---|
| `rol_app_escritura` | `sp_crear_pedido(bigint, forma_pago, jsonb)` | `EXECUTE` |
| `rol_app_auth` | `fn_autenticar(text, text)` | `EXECUTE` |
| `rol_soporte` | `fn_resetear_password(bigint, text)` | `EXECUTE` |

`PUBLIC` no debe aparecer en esta tabla para ninguna de las tres rutinas; la consulta 4e
lo verifica explícitamente incluyendo `'PUBLIC'` en el filtro de `grantee`.

---

## 4. Consultas de verificación

Ejecutar como el mismo rol que corrió los `GRANT` (habitualmente `postgres`).

```sql
-- 4a. Atributos (equivalente de \du para los roles del proyecto)
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolcanlogin
FROM   pg_roles
WHERE  rolname IN (
           'rol_app_lectura','rol_app_escritura','rol_app_auth',
           'rol_soporte','rol_reportes','app_web','admin_datos')
ORDER  BY rolname;

-- 4b. Membresías
SELECT r.rolname AS rol, m.rolname AS miembro
FROM   pg_auth_members am
JOIN   pg_roles r ON r.oid = am.roleid
JOIN   pg_roles m ON m.oid = am.member
WHERE  r.rolname IN (
           'rol_app_lectura','rol_app_escritura','rol_app_auth',
           'rol_soporte','rol_reportes')
ORDER  BY 1, 2;

-- 4c. Privilegios sobre tablas y vistas
-- Excluye admin_datos (es dueño; sus privilegios no aparecen como GRANTs explícitos)
-- y PUBLIC (no debe tener nada otorgado).
-- NOTA: information_schema.role_table_grants NO incluye vistas materializadas.
-- El permiso sobre mv_facturacion_categoria_mes se verifica por separado con pg_class (ver abajo).
SELECT grantee, table_name, privilege_type
FROM   information_schema.role_table_grants
WHERE  grantee IN (
           'rol_app_lectura','rol_app_escritura','rol_app_auth',
           'rol_soporte','rol_reportes','app_web')
ORDER  BY grantee, table_name, privilege_type;

-- Verificar el permiso SELECT de rol_reportes sobre la vista materializada:
SELECT relname, relacl
FROM   pg_class
WHERE  relname = 'mv_facturacion_categoria_mes';
-- Resultado esperado en relacl: contiene "rol_reportes=r/admin_datos"

-- 4d. Privilegios por columna (solo rol_soporte / tabla usuario)
SELECT grantee, table_name, column_name, privilege_type
FROM   information_schema.column_privileges
WHERE  grantee = 'rol_soporte'
  AND  table_name = 'usuario'
ORDER  BY column_name;

-- 4e. Privilegios sobre las tres rutinas propias del proyecto
-- Incluye PUBLIC en la lista: el resultado esperado para PUBLIC es cero filas
-- (confirma que REVOKE ALL FROM PUBLIC surtió efecto). Sin este filtro, no es
-- posible detectar si PUBLIC tiene EXECUTE sobre alguna de las tres rutinas.
-- NOTA: la columna routine_type no existe en information_schema.role_routine_grants.
SELECT grantee, routine_name, privilege_type
FROM   information_schema.role_routine_grants
WHERE  routine_schema = 'public'
  AND  routine_name IN (
           'sp_crear_pedido','fn_autenticar','fn_resetear_password')
  AND  grantee IN (
           'rol_app_lectura','rol_app_escritura','rol_app_auth',
           'rol_soporte','rol_reportes','app_web','PUBLIC')
ORDER  BY grantee, routine_name;

-- 4f. Dueño de los objetos
SELECT schemaname, tablename, tableowner
FROM   pg_tables
WHERE  schemaname = 'public'
ORDER  BY tablename;

SELECT schemaname, viewname, viewowner
FROM   pg_views
WHERE  schemaname = 'public'
ORDER  BY viewname;

SELECT schemaname, matviewname, matviewowner
FROM   pg_matviews
WHERE  schemaname = 'public';

SELECT proname, proowner::regrole AS owner
FROM   pg_proc
WHERE  pronamespace = 'public'::regnamespace
  AND  proname IN (
           'sp_crear_pedido','fn_autenticar','fn_resetear_password',
           'calcular_total_pedido','fn_set_subtotal',
           'fn_recalcular_total','fn_validar_estado_pedido')
ORDER  BY proname;

-- Dueño de los tipos ENUM del proyecto
SELECT typname, typowner::regrole AS owner
FROM   pg_type
WHERE  typname IN ('rol','estado_pedido','forma_pago');
```

---

## 5. Orden de ejecución de `roles.sql`

1. `CREATE EXTENSION IF NOT EXISTS pgcrypto;`
   *(la extensión la instala el rol que tiene permisos; en `copia_u5` la corre `postgres`)*

2. **Roles de grupo** (cinco bloques `DO $$ IF NOT EXISTS … $$`, `NOLOGIN`).

3. **`GRANT USAGE ON SCHEMA public`** a cada rol de grupo.

4. **Roles de login** (dos bloques `DO $$ IF NOT EXISTS … $$`, `LOGIN`, contraseñas con
   marcador `'cambiar_en_produccion'`):
   `admin_datos` y `app_web`.
   Los roles de login deben existir **antes** del cambio de dueño: `ALTER … OWNER TO admin_datos`
   falla si el rol no existe aún.
   Inmediatamente después de crear `admin_datos`:
   `GRANT USAGE, CREATE ON SCHEMA public TO admin_datos;`
   Desde PostgreSQL 15, `PUBLIC` ya no tiene `CREATE` sobre el esquema `public`; sin este
   `GRANT`, `admin_datos` no puede crear nuevos objetos en el esquema aunque sea dueño de
   los existentes.
   Justo después: `REVOKE CREATE ON SCHEMA public FROM PUBLIC;` como defensa en profundidad
   (en PostgreSQL 15 o superior ya es el valor por omisión; se deja explícito).

5. **Cambio de dueño** a `admin_datos` (**D4**, **D6**):
   Solo para los objetos que ya existen en la base heredada.
   - Tablas: `ALTER TABLE categoria OWNER TO admin_datos;` ídem para `producto`, `usuario`, `pedido`, `detalle_pedido`.
   - Vistas: `ALTER VIEW v_categorias_vigentes OWNER TO admin_datos;` ídem para `v_productos_vigentes`, `v_pedidos_resumen`, `v_pedido_detalle`, `v_usuario_seguro`.
   - Vista materializada: `ALTER MATERIALIZED VIEW mv_facturacion_categoria_mes OWNER TO admin_datos;`
   - Funciones heredadas: `ALTER FUNCTION calcular_total_pedido(BIGINT) OWNER TO admin_datos;` ídem para `fn_set_subtotal()`, `fn_recalcular_total()`, `fn_validar_estado_pedido()`.
   - Procedimiento heredado: `ALTER PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB) OWNER TO admin_datos;`
   - Tipos ENUM: `ALTER TYPE rol OWNER TO admin_datos;` ídem para `estado_pedido`, `forma_pago`.
   - **`fn_autenticar` y `fn_resetear_password` no existen todavía**: su cambio de dueño se hace en el paso 6, inmediatamente después de crearlas (**D6**).

6. **Creación y configuración de funciones `SECURITY DEFINER`** (**D1**, **D2**, **D6**):
   - `sp_crear_pedido` ya existe (heredado). Cambiar solo el atributo:
     `ALTER PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB) SECURITY DEFINER SET search_path = public, pg_temp;`
     `REVOKE ALL ON PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB) FROM PUBLIC;`
   - `fn_autenticar` no existe: crear con `CREATE OR REPLACE FUNCTION`, `SECURITY DEFINER`,
     `SET search_path = public, pg_temp`, firma `(p_mail TEXT, p_pass TEXT) RETURNS TABLE(id BIGINT, rol rol)`.
     Inmediatamente después: `ALTER FUNCTION fn_autenticar(TEXT, TEXT) OWNER TO admin_datos;`
     Luego: `REVOKE ALL ON FUNCTION fn_autenticar(TEXT, TEXT) FROM PUBLIC;`
   - `fn_resetear_password` no existe: crear con `CREATE OR REPLACE FUNCTION`, `SECURITY DEFINER`,
     `SET search_path = public, pg_temp`. El `UPDATE` filtra `AND eliminado = FALSE AND rol <> 'ADMIN'`:
     `rol_soporte` no puede resetear la contraseña de un usuario `ADMIN` de la aplicación (cierra un
     camino de escalamiento lógico: fijar la clave del administrador y entrar con `fn_autenticar`).
     La función no emite error en ese caso: simplemente no modifica la fila.
     Inmediatamente después: `ALTER FUNCTION fn_resetear_password(BIGINT, TEXT) OWNER TO admin_datos;`
     Luego: `REVOKE ALL ON FUNCTION fn_resetear_password(BIGINT, TEXT) FROM PUBLIC;`

7. **Privilegios sobre objetos** — un `GRANT` por rol y por objeto:

   **7.0 Limpieza previa.** Si los roles ya existían de una versión anterior (por ejemplo,
   de la clase), pueden arrastrar permisos que contradigan la spec. Se revoca todo antes de
   otorgar, para que el resultado sea exactamente el esperado:
   ```sql
   REVOKE ALL ON ALL TABLES    IN SCHEMA public
       FROM rol_app_lectura, rol_app_escritura, rol_app_auth, rol_soporte, rol_reportes, app_web;
   REVOKE ALL ON ALL SEQUENCES IN SCHEMA public
       FROM rol_app_lectura, rol_app_escritura, rol_app_auth, rol_soporte, rol_reportes, app_web;
   REVOKE ALL ON ALL ROUTINES  IN SCHEMA public
       FROM rol_app_lectura, rol_app_escritura, rol_app_auth, rol_soporte, rol_reportes, app_web;
   ```

   Luego los `GRANT` puntuales:
   - `rol_app_lectura`: `SELECT` sobre `v_productos_vigentes`, `v_categorias_vigentes`.
   - `rol_soporte`: `SELECT (id, nombre, apellido, mail, rol, eliminado, created_at) ON usuario`;
     `SELECT ON v_pedidos_resumen`.
   - `rol_reportes`: `SELECT ON mv_facturacion_categoria_mes`.
   - `rol_app_escritura`: `EXECUTE ON PROCEDURE sp_crear_pedido(BIGINT, forma_pago, JSONB)`.
   - `rol_app_auth`: `EXECUTE ON FUNCTION fn_autenticar(TEXT, TEXT)`.
   - `rol_soporte`: `EXECUTE ON FUNCTION fn_resetear_password(BIGINT, TEXT)`.

8. **Membresías**: `GRANT rol_app_lectura, rol_app_escritura, rol_app_auth TO app_web`.
   Antes del `GRANT`, revocar membresías heredadas que no corresponden:
   ```sql
   REVOKE admin_datos
       FROM app_web, rol_app_lectura, rol_app_escritura, rol_app_auth, rol_soporte, rol_reportes;
   REVOKE rol_soporte, rol_reportes FROM app_web;
   ```

9. **`ALTER DEFAULT PRIVILEGES`** (para objetos futuros creados por `admin_datos`):
   ```sql
   ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA public
       REVOKE ALL ON TABLES FROM PUBLIC;
   ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
       REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
   ```
   El `REVOKE` sobre `TABLES` lleva `IN SCHEMA public` porque el privilegio predeterminado
   de tablas es por esquema. El `REVOKE` sobre `FUNCTIONS` va **sin `IN SCHEMA`**: el
   privilegio `EXECUTE` para `PUBLIC` es un valor predeterminado global de PostgreSQL y un
   `REVOKE` acotado a un esquema no lo quita. La entrada en `pg_default_acl` para funciones
   tendrá `defaclnamespace = 0` (campo de esquema vacío).

   Comprobación: `SELECT defaclrole::regrole, defaclnamespace::regnamespace, defaclobjtype, defaclacl FROM pg_default_acl;`
   Solo aparecerá **una fila**, la de `FUNCTIONS` (`defaclobjtype = 'f'`), con
   `defaclnamespace` vacío o `0`. El `REVOKE ALL ON TABLES FROM PUBLIC`
   no genera entrada en `pg_default_acl` porque PostgreSQL no guarda el privilegio por omisión cuando
   coincide con el valor predeterminado (sin privilegios para PUBLIC); la ausencia de fila para tablas
   es el comportamiento correcto. Para confirmar que funciona, crear una tabla de prueba como `admin_datos`
   y verificar que ningún rol de aplicación recibe `SELECT` automáticamente.
   Para confirmar el efecto sobre funciones **nuevas** (no sirve probar con `fn_autenticar`: `app_web`
   hereda `EXECUTE` de `rol_app_auth`, así que daría `true`), se crea una función de prueba como
   `admin_datos`, se consulta y se borra:
   ```sql
   SET ROLE admin_datos;
   CREATE FUNCTION public.f_prueba() RETURNS int LANGUAGE sql AS 'SELECT 1';
   RESET ROLE;
   SELECT has_function_privilege('app_web', 'public.f_prueba()', 'EXECUTE');
   -- esperado: false (PUBLIC no recibe EXECUTE sobre funciones nuevas)
   DROP FUNCTION public.f_prueba();
   ```

10. **Bloque de limpieza** (comentado; descomentarlo solo para partir de cero):
    ```sql
    -- Paso 1: transferir la propiedad de los objetos de admin_datos a postgres,
    -- para que DROP OWNED BY admin_datos no elimine las tablas del esquema.
    -- REASSIGN OWNED BY admin_datos TO postgres;
    --
    -- Paso 2: revocar los privilegios otorgados por cada rol y limpiar sus
    -- DEFAULT PRIVILEGES. admin_datos se incluye aquí porque, tras el REASSIGN,
    -- ya no tiene objetos pero sí tiene ALTER DEFAULT PRIVILEGES a su nombre;
    -- DROP ROLE admin_datos fallaría con "owner of default privileges" si se omite.
    -- DROP OWNED BY rol_app_lectura, rol_app_escritura, rol_app_auth,
    --               rol_soporte, rol_reportes, app_web, admin_datos;
    --
    -- Paso 3: eliminar todos los roles del proyecto.
    -- DROP ROLE IF EXISTS rol_app_lectura, rol_app_escritura, rol_app_auth,
    --                     rol_soporte, rol_reportes, app_web, admin_datos;
    ```
    **Advertencia:** `DROP OWNED BY admin_datos` sin el `REASSIGN` previo eliminaría todas
    las tablas del esquema. Por eso el `REASSIGN` va siempre primero.

---

## 6. Tabla de pruebas

Cada prueba negativa va en su propio `BEGIN … ROLLBACK` para que el error no aborte el
bloque completo. Se ejecuta con `SET LOCAL ROLE` desde `postgres`.

| # | Prueba | Rol bajo prueba | Operación | Resultado esperado | Requisito |
|---|---|---|---|---|---|
| T01 | Catálogo: lectura de vista | `app_web` | `SELECT * FROM v_productos_vigentes LIMIT 1` | Filas (OK) | R1 |
| T02 | Catálogo: lectura directa de tabla | `app_web` | `SELECT * FROM producto LIMIT 1` | `permission denied` | R1 |
| T03 | Catálogo: lectura directa de usuario | `app_web` | `SELECT * FROM usuario LIMIT 1` | `permission denied` | R1, R3 |
| T04 | Alta de pedido: llamada válida | `app_web` | `CALL sp_crear_pedido(<id_válido>, 'EFECTIVO', '[{"producto_id":<id>,"cantidad":1}]')` | OK | R2 |
| T05 | Alta de pedido: INSERT directo | `app_web` | `INSERT INTO pedido(usuario_id, forma_pago) VALUES (1,'EFECTIVO')` | `permission denied` | R2 |
| T06 | Alta de pedido: UPDATE directo sobre producto | `app_web` | `UPDATE producto SET stock = 99 WHERE id = 1` | `permission denied` | R2 |
| T07 | Autenticación: llamada a función | `app_web` | `SELECT * FROM fn_autenticar('test@test.com','clave')` | 0 filas (hash ficticio) u OK con usuario de prueba real | R3 |
| T08 | Autenticación: lectura directa de contrasena | `app_web` | `SELECT contrasena FROM usuario LIMIT 1` | `permission denied` | R3 |
| T09 | Soporte: columnas permitidas | `rol_soporte` | `SELECT id, nombre, mail FROM usuario LIMIT 1` | Filas (OK) | R4 |
| T10 | Soporte: columna contrasena | `rol_soporte` | `SELECT contrasena FROM usuario LIMIT 1` | `permission denied` | R4 |
| T11 | Soporte: columna celular | `rol_soporte` | `SELECT celular FROM usuario LIMIT 1` | `permission denied` | R4, D5 |
| T12 | Soporte: SELECT * sobre usuario | `rol_soporte` | `SELECT * FROM usuario LIMIT 1` | `permission denied` | R4 |
| T13 | Soporte: pedidos resumen | `rol_soporte` | `SELECT * FROM v_pedidos_resumen LIMIT 1` | Filas (OK) | R4 |
| T14 | Soporte: resetear contraseña | `rol_soporte` | `SELECT fn_resetear_password(<id_válido>, 'NuevaClave123')` | OK | R4 |
| T15 | Soporte: escalamiento de privilegios | `rol_soporte` | `GRANT admin_datos TO rol_soporte` | `permission denied` | R8 |
| T16 | Soporte: modificar producto | `rol_soporte` | `UPDATE producto SET precio = 1 WHERE id = 1` | `permission denied` | R4 |
| T17 | Reportes: vista materializada | `rol_reportes` | `SELECT * FROM mv_facturacion_categoria_mes LIMIT 1` | Filas (OK) | R5 |
| T18 | Reportes: REFRESH | `rol_reportes` | `REFRESH MATERIALIZED VIEW mv_facturacion_categoria_mes` | `permission denied` | R5 |
| T19 | Reportes: tabla base | `rol_reportes` | `SELECT * FROM pedido LIMIT 1` | `permission denied` | R5 |
| T20 | Verificación "ni más": rol_app_escritura sin SELECT en tablas | `rol_app_escritura` | `SELECT * FROM pedido LIMIT 1` | `permission denied` | R2, D1 |
| T21 | app_web no puede ejecutar fn_resetear_password | `app_web` | `SELECT fn_resetear_password(1, 'x')` | `permission denied` | R3, R4 |
| T22 | app_web no puede asumir el rol admin_datos | `app_web` | `SELECT pg_has_role('app_web','admin_datos','MEMBER')` | `false` (sin membresía) | R7, R8 |
| T23 | rol_soporte no puede resetear la contraseña de un ADMIN de la aplicación | `rol_soporte` | `SELECT fn_resetear_password(<id_de_un_ADMIN>, 'NuevaClave123')` y comparar el hash antes y después | sin cambio | R4, R8 |

> **Nota sobre T22:** no se prueba con `SET ROLE admin_datos` desde la sesión de pruebas, porque `SET ROLE` se valida
> contra el usuario de la sesión (`postgres`, superusuario) y siempre funciona. Se comprueba la membresía, que es lo que
> habilitaría ese `SET ROLE`. El intento real, conectado como `app_web`, se hace en el simulacro de la Parte C.

### Plantilla de bloque para pruebas negativas

```sql
BEGIN;
SET LOCAL ROLE <rol_bajo_prueba>;
<sentencia que debe fallar>;  -- si no falla: hallazgo → corregir roles.sql y registrar en BITACORA.md
ROLLBACK;
```

---

## 7. Contrato con el simulacro de la Parte C

Define con qué rol se ejecuta cada paso para que el log registre la actividad correcta.
El login de prueba `soporte_prueba` lo crea `simulacro_incidente.sql` (miembro de `rol_soporte`).
No se usa ningún `atacante_prueba` en este diseño: el escalamiento lo intenta el mismo `soporte_prueba`.

**Requisito de auditoría:** `log_statement` debe estar en `'all'` para que los `SELECT`
(no solo los DML) queden registrados. Con `'mod'` los pasos 1, 2 y 3 no aparecen en el log.

**Advertencia de privacidad:** con `log_statement = 'all'`, los literales de cada sentencia
quedan en el log, incluida la clave en texto plano del paso 2. El log debe tratarse como
activo sensible: **anonimizarlo antes de entregarlo o compartirlo**, reemplazando la clave
real por un marcador (`'[CLAVE_REDACTADA]'`) y los mails por valores sintéticos.

| Paso | Rol / login usado | Operación | Resultado esperado en el log |
|---|---|---|---|
| 1. Logins fallidos (×3) | `app_web` | `SELECT * FROM fn_autenticar('prueba@test.com', 'clave_incorrecta')` repetido tres veces, **contra el usuario de prueba con hash real** (no contra usuarios con hash ficticio, que fallarían por sal inválida) | 3 entradas en el log con 0 filas; `log_statement = 'all'` registra la llamada incluyendo el literal de la clave errónea |
| 2. Login exitoso | `app_web` | `SELECT * FROM fn_autenticar('prueba@test.com', 'ClaveReal')` con el mismo usuario de prueba creado con `crypt('ClaveReal', gen_salt('bf'))` en `simulacro_incidente.sql` | 1 fila; la clave en texto plano queda en el log → **anonimizar antes de entregar** |
| 3. Lectura masiva de `usuario` | `soporte_prueba` (miembro de `rol_soporte`) | `SELECT id, nombre, apellido, mail, rol, eliminado, created_at FROM usuario` sin `LIMIT` (~20.000 filas) | Consulta registrada en el log; sin `permission denied` (es el acceso previsto para el rol de soporte) |
| 4. Intento de escalamiento | `soporte_prueba` | `GRANT admin_datos TO soporte_prueba` | `permission denied`; entrada en el log; confirma que el diseño bloquea la escalada |

**Regla de evidencia:** cada paso se ejecuta conectado como el login de prueba (no como
`postgres`), para que `log_connections` / `log_disconnections` y `log_statement` registren
la identidad correcta y la secuencia sea reconstruible.

---

## 8. Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| Una prueba hecha como `postgres` da falsos positivos (postgres puede todo) | Siempre `SET LOCAL ROLE <rol>` dentro de `BEGIN … ROLLBACK` |
| `ALTER … OWNER` queda a medias y las vistas o triggers fallan al ejecutarlas como `app_web` | Ejecutar T01–T04 inmediatamente después del cambio de dueño; si falla, revisar el paso 5 de la sección 5 |
| `app_web` puede crear un pedido para cualquier `p_usuario_id` (no valida que sea el usuario conectado) | Riesgo aceptado en esta unidad; se registra en `BITACORA.md` como limitación de diseño |
| Hashes ficticios en `carga_masiva.sql`: `fn_autenticar` devolverá siempre 0 filas con esos usuarios | Crear un usuario de prueba en `simulacro_incidente.sql` con `crypt('ClaveReal', gen_salt('bf'))` para T07 y el Paso 2 del simulacro |
| `ALTER DEFAULT PRIVILEGES` solo cubre objetos futuros: los existentes ya tienen los permisos que corresponden de los pasos 5 a 7 | Verificar con la consulta 4f que el dueño es `admin_datos` antes de dar el paso de `ALTER DEFAULT PRIVILEGES` |
