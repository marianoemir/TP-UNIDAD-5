# Verificación de permisos — Parte A

Base: `copia_u5` · Ejecutado como `postgres` · Fecha: 2026-10-10
Fuente de los resultados esperados: `docs/kiro_roles_spec/design.md`, secciones 3 y 4.

## 1. Estado inicial (antes de `roles.sql`)

Dueño de las tablas del esquema `public`:

```
"categoria"       "postgres"
"producto"        "postgres"
"usuario"         "postgres"
"pedido"          "postgres"
"detalle_pedido"  "postgres"
```

**Hallazgo (D4):** las cinco tablas eran del superusuario `postgres`, no de `admin_datos`. Por eso
`ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos` no habría cubierto nada sin el cambio de dueño.

> [COMPLETAR si se capturaron] Atributos de roles (`pg_roles`) y `role_table_grants` previos.

## 2. Ejecución de `roles.sql`

| Intento | Cierre | Resultado |
|---|---|---|
| Ensayo | `ROLLBACK` | Sin errores. Dueños sin cambios (siguen `postgres`) |
| Real | `COMMIT` | Sin errores. Dueños cambiados a `admin_datos` |

Ambas ejecuciones emitieron 8 avisos (`WARNING`) del paso 8: los `REVOKE` de membresías que no existían.
Son esperados: confirman que los roles no traían membresías heredadas.

## 3. Después de `roles.sql`

### 3.1 Dueño de las tablas

```
"categoria"       "admin_datos"
"producto"        "admin_datos"
"usuario"         "admin_datos"
"detalle_pedido"  "admin_datos"
"pedido"          "admin_datos"
```

### 3.2 Consulta 4a — atributos de los roles

```
"admin_datos"        false  false  false  true
"app_web"            false  false  false  true
"rol_app_auth"       false  false  false  false
"rol_app_escritura"  false  false  false  false
"rol_app_lectura"    false  false  false  false
"rol_reportes"       false  false  false  false
"rol_soporte"        false  false  false  false
```

Columnas: `rolname`, `rolsuper`, `rolcreaterole`, `rolcreatedb`, `rolcanlogin`.
**Coincide:** solo `admin_datos` y `app_web` inician sesión; ninguno tiene `SUPERUSER`, `CREATEROLE` ni `CREATEDB` (D3).

### 3.3 Consulta 4b — membresías

```
"rol_app_auth"       "app_web"
"rol_app_escritura"  "app_web"
"rol_app_lectura"    "app_web"
```

**Coincide:** `app_web` es miembro de los tres grupos de aplicación; `rol_soporte` y `rol_reportes` no tienen miembros.

### 3.4 Consulta 4c — privilegios sobre tablas y vistas

```
"rol_app_lectura"  "v_categorias_vigentes"  "SELECT"
"rol_app_lectura"  "v_productos_vigentes"   "SELECT"
"rol_soporte"      "v_pedidos_resumen"      "SELECT"
```

**Coincide:** ni un privilegio de más ni de menos. `rol_app_escritura` y `rol_app_auth` no tienen privilegios de tabla (D1, D2).

> **Observación:** `information_schema` no incluye las vistas materializadas, por lo que el permiso de
> `rol_reportes` sobre `mv_facturacion_categoria_mes` no aparece en esta consulta. Se verifica en 3.7.

### 3.5 Consulta 4d — privilegios por columna de `rol_soporte` sobre `usuario`

```
"rol_soporte"  "usuario"  "apellido"    "SELECT"
"rol_soporte"  "usuario"  "created_at"  "SELECT"
"rol_soporte"  "usuario"  "eliminado"   "SELECT"
"rol_soporte"  "usuario"  "id"          "SELECT"
"rol_soporte"  "usuario"  "mail"        "SELECT"
"rol_soporte"  "usuario"  "nombre"      "SELECT"
"rol_soporte"  "usuario"  "rol"         "SELECT"
```

**Coincide:** 7 columnas. `celular` y `contrasena` quedan fuera (D5).

### 3.6 Consulta 4e — privilegios sobre las tres rutinas propias

La consulta de la spec falla (`no existe la columna «routine_type»`: esa columna no existe en
`role_routine_grants`). Versión corregida, sin esa columna:

```sql
SELECT grantee, routine_name, privilege_type
FROM   information_schema.role_routine_grants
WHERE  routine_schema = 'public'
  AND  routine_name IN ('sp_crear_pedido','fn_autenticar','fn_resetear_password')
  AND  grantee IN ('rol_app_lectura','rol_app_escritura','rol_app_auth',
                   'rol_soporte','rol_reportes','app_web','PUBLIC')
ORDER  BY grantee, routine_name;
```

Resultado:

```
"rol_app_auth"       "fn_autenticar"         "EXECUTE"
"rol_app_escritura"  "sp_crear_pedido"       "EXECUTE"
"rol_soporte"        "fn_resetear_password"  "EXECUTE"
```

**Coincide:** tres filas, cada rutina con `EXECUTE` solo para su rol. **Cero filas para `PUBLIC`**:
el `REVOKE ALL … FROM PUBLIC` surtió efecto.

### 3.7 Vista materializada: `relacl`

```sql
SELECT relname, relacl FROM pg_class WHERE relname = 'mv_facturacion_categoria_mes';
```

```
"mv_facturacion_categoria_mes"  ["admin_datos=arwdDxtm/admin_datos","rol_reportes=r/admin_datos"]
```

**Coincide:** `rol_reportes=r/...` es solo `SELECT`, otorgado por el dueño. El resto son los privilegios del propio dueño.

### 3.8 Consulta 4f — dueño de los objetos

Tipos:

```
"rol"            "admin_datos"
"estado_pedido"  "admin_datos"
"forma_pago"     "admin_datos"
```

Vistas, vista materializada y rutinas (13 filas):

```
"matview"  "mv_facturacion_categoria_mes"  "admin_datos"
"rutina"   "calcular_total_pedido"         "admin_datos"
"rutina"   "fn_autenticar"                 "admin_datos"
"rutina"   "fn_recalcular_total"           "admin_datos"
"rutina"   "fn_resetear_password"          "admin_datos"
"rutina"   "fn_set_subtotal"               "admin_datos"
"rutina"   "fn_validar_estado_pedido"      "admin_datos"
"rutina"   "sp_crear_pedido"               "admin_datos"
"vista"    "v_categorias_vigentes"         "admin_datos"
"vista"    "v_pedido_detalle"              "admin_datos"
"vista"    "v_pedidos_resumen"             "admin_datos"
"vista"    "v_productos_vigentes"          "admin_datos"
"vista"    "v_usuario_seguro"              "admin_datos"
```

**Coincide:** 5 tablas, 5 vistas, 1 vista materializada, 7 rutinas y 3 tipos con dueño `admin_datos` (D4, D6).

## 4. Privilegios por omisión de objetos futuros (`ALTER DEFAULT PRIVILEGES`)

Prueba: como `admin_datos` se crea una función nueva y se consulta si `app_web` (que hereda de `PUBLIC`)
puede ejecutarla.

```sql
SET ROLE admin_datos;
CREATE FUNCTION public.f_prueba() RETURNS int LANGUAGE sql AS 'SELECT 1';
RESET ROLE;
SELECT has_function_privilege('app_web', 'public.f_prueba()', 'EXECUTE');
DROP FUNCTION public.f_prueba();
```

Resultado del `SELECT`:

```
false
```

**Coincide con lo esperado (`false`).** Esto confirma dos cosas:

1. `admin_datos` pudo crear una función en `public`: el `GRANT CREATE ON SCHEMA public TO admin_datos`
   de `roles.sql` surtió efecto.
2. `PUBLIC` no recibe `EXECUTE` sobre funciones nuevas: el `ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos
   REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` (sin `IN SCHEMA`) funciona.

Para dejar la prueba reproducible, la función de prueba se eliminó al terminar.

## 5. Pruebas T01–T23 con rol real

Script: `sql/verificacion_roles.sql`, ejecutado como `postgres` en `copia_u5`. Cada prueba corre con
`SET LOCAL ROLE <rol>` dentro de un subbloque que siempre termina en excepción, así que no deja cambios.
T01 a T21 vienen de la sección 6 de `design.md`; T22 y T23 se agregaron durante el trabajo.

Resultado final (23 de 23 en `OK`):

```
"T01"  "app_web"            "filas"          "filas"          "OK"
"T02"  "app_web"            "denegado"       "denegado"       "OK"
"T03"  "app_web"            "denegado"       "denegado"       "OK"
"T04"  "app_web"            "ok"             "ok"             "OK"
"T05"  "app_web"            "denegado"       "denegado"       "OK"
"T06"  "app_web"            "denegado"       "denegado"       "OK"
"T07"  "app_web"            "ok"             "ok"             "OK"
"T08"  "app_web"            "denegado"       "denegado"       "OK"
"T09"  "rol_soporte"        "filas"          "filas"          "OK"
"T10"  "rol_soporte"        "denegado"       "denegado"       "OK"
"T11"  "rol_soporte"        "denegado"       "denegado"       "OK"
"T12"  "rol_soporte"        "denegado"       "denegado"       "OK"
"T13"  "rol_soporte"        "filas"          "filas"          "OK"
"T14"  "rol_soporte"        "ok"             "ok"             "OK"
"T15"  "rol_soporte"        "denegado"       "denegado"       "OK"
"T16"  "rol_soporte"        "denegado"       "denegado"       "OK"
"T17"  "rol_reportes"       "filas"          "filas"          "OK"
"T18"  "rol_reportes"       "denegado"       "denegado"       "OK"
"T19"  "rol_reportes"       "denegado"       "denegado"       "OK"
"T20"  "rol_app_escritura"  "denegado"       "denegado"       "OK"
"T21"  "app_web"            "denegado"       "denegado"       "OK"
"T22"  "app_web"            "sin_membresia"  "sin_membresia"  "OK"
"T23"  "rol_soporte"        "sin_cambio"     "sin_cambio"     "OK"
```

Columnas: prueba, rol, resultado esperado, resultado obtenido, estado.
`denegado` = `permission denied` o `must be owner`; `filas` = funciona y devuelve al menos una fila.

### Historia de las corridas

| Corrida | Resultado | Causa |
|---|---|---|
| 1.ª | 21 de 23. `FALLO` en T22 y T23 | **T22:** la prueba estaba mal diseñada. `SET ROLE` se valida contra el usuario de la sesión (`postgres`, superusuario) y siempre funciona, por lo que no mide los permisos de `app_web`. Se reemplazó por la comprobación de membresía con `pg_has_role('app_web','admin_datos','MEMBER')`. **T23:** detectó que el filtro `rol <> 'ADMIN'` de `fn_resetear_password` estaba en el archivo `roles.sql` pero **no aplicado en la base** |
| 2.ª y 3.ª | 22 de 23. T22 en `OK`, T23 en `FALLO` | `pg_get_functiondef` mostró que la función seguía sin el filtro: `roles.sql` no se había re-ejecutado con `COMMIT` desde la edición |
| 4.ª | **23 de 23** | Se re-ejecutó `roles.sql` con `COMMIT` (avisos de membresías ya existentes, prueba de re-ejecutabilidad). `pg_get_functiondef` confirmó el `AND rol <> 'ADMIN'` |

### Qué demuestran

- **R1, R2, R3:** `app_web` lee solo las vistas del catálogo, crea pedidos únicamente con `sp_crear_pedido` y no puede
  leer ni escribir tablas ni la columna `contrasena`.
- **R4:** `rol_soporte` lee las columnas permitidas de `usuario` y `v_pedidos_resumen`, no puede leer `contrasena`,
  `celular` ni hacer `SELECT *`, y puede ejecutar el reseteo acotado.
- **R5:** `rol_reportes` solo lee la vista materializada y no puede refrescarla ni leer tablas base.
- **R8:** `rol_soporte` no puede otorgarse `admin_datos` (T15); `app_web` no es miembro de `admin_datos` (T22).
- **Escalamiento lógico (T23):** `rol_soporte` no puede resetear la contraseña de un usuario `ADMIN` de la aplicación.
  La función no emite error en ese caso: simplemente no modifica la fila.
- **Límite de T22:** prueba la membresía, no una conexión real. Intentar `SET ROLE admin_datos` conectado como
  `app_web` se ejercita en el simulacro de la Parte C.

## 6. Resumen

| Verificación | Estado |
|---|---|
| Atributos de roles (4a) | Coincide |
| Membresías (4b) | Coincide |
| Privilegios de tablas y vistas (4c) | Coincide |
| Privilegios por columna (4d) | Coincide |
| Privilegios de rutinas, sin `PUBLIC` (4e corregida) | Coincide |
| Vista materializada (`relacl`) | Coincide |
| Dueños de objetos (4f) | Coincide |
| Default privileges de funciones (`f_prueba`) | Coincide |
| Pruebas T01–T23 con rol real | Coincide (23 de 23) |
