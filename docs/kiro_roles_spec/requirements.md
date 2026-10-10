# Requirements — Roles y permisos de mínimo privilegio (Food Store, Parte A)

> Spec definitiva. Todas las decisiones marcadas **[D#]** están confirmadas por el equipo
> y se corresponden con la sección de decisiones de `design.md`.
> Cada rol y cada privilegio se justifica en una oración: qué habilita y por qué ese y no otro.

---

## Contexto

- Motor: PostgreSQL 16+ (el grupo usa 18 en local). Base de trabajo: `copia_u5`.
- Hoy las cinco tablas (`categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`)
  son propiedad del rol `postgres`. La Parte A las pasa a `admin_datos` (**D4**).
- `usuario.rol` (ENUM `ADMIN`/`USUARIO`) es un dato de la aplicación: **no** es un rol
  de PostgreSQL y no protege nada a nivel del motor.
- Los roles pertenecen al servidor: sobreviven a `DROP DATABASE copia_u5`.

---

## Requisitos

### R1 — Catálogo público de solo lectura

**Historia:** como sitio web, quiero listar productos y categorías vigentes sin tener
acceso directo a las tablas base.

- WHEN `app_web` consulta `v_productos_vigentes` o `v_categorias_vigentes`
  THEN el sistema SHALL retornar filas.
- WHEN `app_web` intenta `SELECT` directamente sobre `producto`, `categoria` o cualquier
  otra tabla base THEN el sistema SHALL responder `permission denied`.
- **Rol:** `rol_app_lectura` (grupo, NOLOGIN).
  **Justificación:** `SELECT` sobre las dos vistas vigentes es suficiente para servir el
  catálogo; las vistas ya aplican `eliminado = FALSE` y no exponen datos sensibles.

---

### R2 — Alta de pedidos por un único camino

**Historia:** como backend, quiero crear pedidos únicamente a través del procedimiento
transaccional `sp_crear_pedido`.

- WHEN `app_web` ejecuta `CALL sp_crear_pedido(p_usuario_id, p_forma_pago, p_items)`
  con datos válidos THEN el sistema SHALL crear el pedido, sus detalles y descontar stock
  en la misma transacción.
- WHEN `app_web` intenta `INSERT`, `UPDATE`, `DELETE` o `TRUNCATE` directo sobre
  `pedido`, `detalle_pedido`, `producto`, `usuario` o `categoria`
  THEN el sistema SHALL responder `permission denied`.
- WHEN `app_web` intenta `SELECT` sobre `pedido`, `detalle_pedido` o `producto`
  directamente THEN el sistema SHALL responder `permission denied`.
- **Rol:** `rol_app_escritura` (grupo, NOLOGIN). **Decisión confirmada D1.**
  **Justificación:** `EXECUTE` sobre `sp_crear_pedido` es el único privilegio necesario
  porque el procedimiento corre como `SECURITY DEFINER` y gestiona internamente todos los
  accesos a tablas; darle permisos de tabla al rol ampliaría la superficie de ataque sin
  aportar funcionalidad.

---

### R3 — Autenticación sin exponer la contraseña

**Historia:** como backend, quiero validar un inicio de sesión sin que ningún rol de
aplicación pueda leer `usuario.contrasena`.

- WHEN `app_web` ejecuta `SELECT * FROM fn_autenticar(p_mail, p_pass)`
  THEN el sistema SHALL devolver `(id BIGINT, rol rol)` solo si la clave coincide y
  `eliminado = FALSE`; en caso contrario, cero filas.
- WHEN cualquier rol de aplicación (`app_web`, `rol_soporte`, `rol_reportes`)
  intenta `SELECT contrasena FROM usuario`
  THEN el sistema SHALL responder `permission denied`.
- **Rol:** `rol_app_auth` (grupo, NOLOGIN). **Decisión confirmada D2.**
  **Justificación:** `EXECUTE` sobre `fn_autenticar` es el único privilegio necesario
  porque la función corre como `SECURITY DEFINER` y es la única pieza que compara el hash;
  darle acceso directo a `usuario` al backend expondría los hashes.

---

### R4 — Soporte sin ver contraseñas ni número de celular

**Historia:** como agente de soporte, quiero consultar usuarios y sus pedidos, y resetear
contraseñas, sin acceder a datos sensibles ni modificar stock o roles.

- WHEN `rol_soporte` consulta las columnas `id`, `nombre`, `apellido`, `mail`, `rol`,
  `eliminado`, `created_at` de la tabla `usuario` THEN el sistema SHALL retornar filas.
- WHEN `rol_soporte` consulta `usuario.contrasena`, `usuario.celular` o hace `SELECT *`
  sobre `usuario` THEN el sistema SHALL responder `permission denied`.
- WHEN `rol_soporte` consulta `v_pedidos_resumen`
  THEN el sistema SHALL retornar filas.
- WHEN `rol_soporte` ejecuta `SELECT fn_resetear_password(p_usuario_id, p_nueva)`
  THEN el sistema SHALL guardar el hash nuevo en `usuario.contrasena`.
- WHEN `rol_soporte` intenta modificar `producto`, `pedido`, `detalle_pedido` o ejecutar
  `GRANT` sobre cualquier rol THEN el sistema SHALL responder `permission denied`.
- **Rol:** `rol_soporte` (grupo, NOLOGIN). **Decisión confirmada D5.**
  **Justificación:** permiso por columna sobre `usuario` (sin `celular` ni `contrasena`)
  porque soporte necesita identificar al cliente y destrabarlo, pero no tiene caso de uso
  que requiera su teléfono; `fn_resetear_password` es `SECURITY DEFINER` y acota la
  operación a un solo `UPDATE`.

> **Nota sobre `v_usuario_seguro`:** la vista expone `celular`. `rol_soporte` **no**
> recibe permiso sobre ella; recibe permiso por columna directamente sobre `usuario`,
> que es más restrictivo (**D5**).

---

### R5 — Reportes de solo lectura

**Historia:** como panel gerencial, quiero leer la facturación agregada por categoría y mes.

- WHEN `rol_reportes` consulta `mv_facturacion_categoria_mes`
  THEN el sistema SHALL retornar filas.
- WHEN `rol_reportes` intenta `REFRESH MATERIALIZED VIEW mv_facturacion_categoria_mes`,
  `SELECT` sobre tablas base o ejecutar cualquier DML
  THEN el sistema SHALL responder `permission denied`.
- **Rol:** `rol_reportes` (grupo, NOLOGIN).
  **Justificación:** `SELECT` sobre la vista materializada es suficiente para el panel;
  los datos ya están agregados y el equipo controla cuándo se refresca.

---

### R6 — Administración sin superusuario

**Historia:** como administrador de datos, quiero ser dueño de todos los objetos del
esquema `public` sin necesitar privilegios de servidor.

- WHEN se consulta `pg_roles` THEN `admin_datos` SHALL tener
  `rolsuper = false`, `rolcreaterole = false`, `rolcreatedb = false`. **Decisión D3.**
- WHEN se consulta `pg_tables WHERE schemaname = 'public'` THEN las cinco tablas, las
  vistas, la vista materializada y las funciones SHALL tener `tableowner = admin_datos`
  (o `proowner = admin_datos` para rutinas). **Decisión D4.**
- El cambio de dueño SHALL realizarse con `ALTER TABLE … OWNER TO admin_datos`,
  `ALTER VIEW … OWNER TO`, `ALTER MATERIALIZED VIEW … OWNER TO`,
  `ALTER FUNCTION … OWNER TO`, `ALTER PROCEDURE … OWNER TO`, objeto por objeto.
  **Nunca** con `REASSIGN OWNED BY postgres`.
- `admin_datos` SHALL recibir `GRANT USAGE, CREATE ON SCHEMA public`: a partir de
  PostgreSQL 15 `PUBLIC` ya no tiene `CREATE` sobre el esquema `public`, por lo que el
  rol que administra los objetos necesita ese privilegio explícito para poder crear nuevos
  objetos bajo su propio nombre.
- **Justificación:** ser dueño de los objetos alcanza para `ALTER`, `GRANT` y `REFRESH`;
  `CREATEDB` y `CREATEROLE` son privilegios de servidor que no se necesitan para
  administrar una base.

---

### R7 — Grupo vs. login

- Los cinco roles de grupo (`rol_app_lectura`, `rol_app_escritura`, `rol_app_auth`,
  `rol_soporte`, `rol_reportes`) SHALL ser `NOLOGIN` y concentrar los privilegios sobre
  objetos.
- Los roles de login (`app_web`, `admin_datos`) SHALL recibir solo membresías, sin
  privilegios propios sobre objetos.
- `app_web` SHALL ser miembro de `rol_app_lectura`, `rol_app_escritura` y `rol_app_auth`.
- Ningún rol de aplicación SHALL tener `SUPERUSER`, `CREATEROLE` ni `CREATEDB`.

---

### R8 — Escalamiento de privilegios bloqueado

- WHEN un rol de aplicación (por ejemplo, `rol_soporte`) intenta
  `GRANT admin_datos TO rol_soporte` o cualquier variante de escalamiento
  THEN el sistema SHALL responder `permission denied`.

---

### R9 — Tablas y funciones futuras sin permisos abiertos

- WHEN `admin_datos` cree una tabla nueva en `schema public`
  THEN ningún rol de aplicación SHALL recibir privilegios sobre ella automáticamente.
  Se usa `ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos IN SCHEMA public
  REVOKE ALL ON TABLES FROM PUBLIC`.
- WHEN se cree una función o procedimiento nuevo
  THEN `PUBLIC` SHALL NOT tener `EXECUTE` por omisión.
  Se usa `ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` (**sin `IN SCHEMA`**).
  Motivo: el privilegio `EXECUTE` para `PUBLIC` es un valor predeterminado **global** de
  PostgreSQL; un `REVOKE` acotado a un esquema no lo quita. La entrada resultante en
  `pg_default_acl` tendrá `defaclnamespace = 0` (sin esquema). La verificación con
  `has_function_privilege('app_web', 'fn_autenticar(text,text)', 'EXECUTE')` debe retornar
  `false` para confirmar que el revoke tuvo efecto.

---

### R10 — Funciones SECURITY DEFINER acotadas

- Toda función con `SECURITY DEFINER` SHALL declarar
  `SET search_path = public, pg_temp` (evita sustitución de objetos por otro esquema).
- Toda función con `SECURITY DEFINER` SHALL tener
  `REVOKE ALL ON FUNCTION … FROM PUBLIC` antes del `GRANT EXECUTE` específico.
- `GRANT EXECUTE` SHALL otorgarse solo al rol que efectivamente necesita la función.
- Todas las entradas SHALL viajar como parámetros tipados; nunca concatenadas en SQL dinámico.

---

### R11 — Verificación "ni más, ni menos"

- La salida combinada de las cinco consultas de verificación (ver `design.md` sección 4)
  SHALL coincidir exactamente con la tabla de privilegios esperados (`design.md` sección 3):
  ningún privilegio extra, ninguno faltante.
- La verificación SHALL ejecutarse con el mismo rol que corrió los `GRANT` (habitualmente
  `postgres`), para que `information_schema.role_table_grants` muestre todas las filas.

---

### R12 — Re-ejecutable y reversible

- `roles.sql` SHALL poder correrse más de una vez sin error (los `CREATE ROLE` se
  envuelven en `DO $$ IF NOT EXISTS … $$`).
- `roles.sql` SHALL incluir un bloque de limpieza comentado y probado que permita partir
  de cero sin dejar objetos huérfanos ni borrar tablas accidentalmente. El bloque tiene
  tres pasos en orden obligatorio:
  1. `REASSIGN OWNED BY admin_datos TO postgres` — transfiere la propiedad de las tablas
     antes de que `DROP OWNED BY` las elimine.
  2. `DROP OWNED BY rol_app_lectura, rol_app_escritura, rol_app_auth, rol_soporte,
     rol_reportes, app_web, admin_datos` — revoca los privilegios otorgados por cada rol
     y limpia sus `DEFAULT PRIVILEGES`. `admin_datos` debe incluirse aquí aunque ya no
     tenga objetos tras el `REASSIGN`, porque tiene `ALTER DEFAULT PRIVILEGES` registrados
     a su nombre; si se omite, `DROP ROLE admin_datos` falla con "owner of default privileges".
  3. `DROP ROLE IF EXISTS …` — elimina los siete roles del proyecto.
- **Nunca** ejecutar `DROP OWNED BY admin_datos` sin el `REASSIGN` previo: borraría todas
  las tablas del esquema.
