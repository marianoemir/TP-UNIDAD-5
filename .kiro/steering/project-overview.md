# Food Store — Visión General del Proyecto

## Descripción

Sistema de venta de comida implementado íntegramente en **PostgreSQL**.
Cubre el ciclo completo: categorías → productos → usuarios → pedidos con sus
detalles. Las Unidades 1 a 4 construyeron y optimizaron el modelo; la
**Unidad 5** le agrega la capa de **administración y seguridad**: quién puede
hacer qué (roles y permisos), qué queda registrado (auditoría), cómo se
reconstruye un incidente y cómo se protegen los datos personales.

## Metodología: dos bases (plantilla + copia de trabajo)

`plantilla_food_store` (limpia: `schema.sql` → `objects.sql` → `data.sql`) y
`copia_u5` (creada con esa plantilla como **Template**; ahí corren
`carga_masiva.sql`, los scripts heredados y todo lo de `sql/`). No se reutilizan
`copia_trabajo` ni `copia_fnbc` de la U4. Atención: **los roles pertenecen al
servidor, no a la base** — borrar `copia_u5` no los elimina. Detalle en
`AGENTS.md`.

## Trabajo Práctico en curso: Unidad 5 (Administración y Seguridad)

Cinco partes, en este orden, cada una con evidencia técnica verificable:

| Parte | Tema | Evidencia |
|---|---|---|
| A | Diseño e implementación de roles y permisos de mínimo privilegio | `roles.sql`, spec de Kiro, salida de `\du` y `role_table_grants` |
| B | Activación y prueba de la auditoría | Informe de configuración, fragmento de log, respuestas escritas |
| C | Laboratorio: simulacro de incidente de acceso indebido | Script, log anonimizado, respuesta de la IA, contraste, informe de contención |
| D | Anonimización y verificación de equivalencia | `usuario_anon`, consultas gemelas, resultados lado a lado |
| E | Cierre: bitácora de IA e historial de Git | `BITACORA.md` consolidada |

Herramientas obligatorias: **OpenCode** (asistente de terminal), **Kiro**
(especificación previa) y **Git** (avance por partes, sin un único commit
final). Todo se ejecuta únicamente contra la instancia propia.

## Archivos del proyecto

### Base heredada (`base_heredada/`, sin modificar)

| Archivo | Contenido |
|---|---|
| `schema.sql` | Tipos ENUM, tablas, constraints y los 3 índices originales |
| `objects.sql` | 4 vistas base, `calcular_total_pedido`, triggers, `sp_crear_pedido` |
| `data.sql` | Datos de prueba chicos (**incluye datos reales de integrantes**) |
| `carga_masiva.sql` | ≥50.000 productos, ≥20.000 usuarios, ≥200.000 pedidos (hashes de contraseña ficticios) |
| `indices_semana3.sql` | 2 índices parciales sobre `pedido` |
| `indices.sql` | `idx_producto_nombre_lower_vigente` |
| `views.sql` | `v_usuario_seguro` |
| `materializadas.sql` | `mv_facturacion_categoria_mes` + índice único |
| `queries.sql` | Banco de consultas (no se ejecuta de una vez) |
| `transacciones.sql` | Escenarios de atomicidad y concurrencia |

### Entregables de la U5

`sql/roles.sql`, `sql/auditoria_test.sql`, `sql/simulacro_incidente.sql`,
`sql/usuario_anon.sql`; `docs/` con la spec de Kiro, los informes y los logs;
y `BITACORA.md`. Árbol completo en `AGENTS.md`.

## Tablas del modelo

```
categoria
producto       → FK categoria_id → categoria
usuario
pedido         → FK usuario_id   → usuario
detalle_pedido → FK pedido_id    → pedido
               → FK producto_id  → producto
```

## Tipos ENUM definidos

```sql
CREATE TYPE rol           AS ENUM ('ADMIN','USUARIO');
CREATE TYPE estado_pedido AS ENUM ('PENDIENTE','CONFIRMADO','TERMINADO','CANCELADO');
CREATE TYPE forma_pago    AS ENUM ('TARJETA','TRANSFERENCIA','EFECTIVO');
```

`rol` es un dato de la aplicación (columna `usuario.rol`). **No** es un rol de
PostgreSQL y no protege nada a nivel del motor: los roles de la U5 se crean
con `CREATE ROLE`.

## Orden de ejecución

```
plantilla_food_store:  schema.sql → objects.sql → data.sql
copia_u5:              carga_masiva.sql → indices_semana3.sql → indices.sql
                       → views.sql → materializadas.sql
                       → sql/roles.sql → sql/auditoria_test.sql
                       → sql/simulacro_incidente.sql → sql/usuario_anon.sql
```

## Diseño de roles (punto de partida: Clase 1, sección 4.3)

Esta es la tabla de la clase **con los nombres de la base real**. Es el
punto de partida, no la respuesta final: la Parte A pide una versión revisada
y justificada por el equipo, y la verificación debe coincidir con la spec de
Kiro "ni más, ni menos".

| Rol | Tipo | Acceso previsto | Para qué |
|---|---|---|---|
| `rol_app_lectura` | grupo (sin LOGIN) | `SELECT` en `v_productos_vigentes`, `v_categorias_vigentes` | Catálogo público del sitio |
| `rol_app_escritura` | grupo | `SELECT/INSERT/UPDATE` en `pedido`, `detalle_pedido`; `EXECUTE` en `sp_crear_pedido(BIGINT, forma_pago, JSONB)`; sin `DELETE` ni `TRUNCATE` | Flujo de compra de la aplicación |
| `rol_soporte` | grupo | `SELECT` en `v_usuario_seguro`, `v_pedidos_resumen`; (a evaluar) permiso por columna sobre `usuario` | Atención al cliente, sin ver contraseñas ni tocar stock |
| `rol_reportes` | grupo | `SELECT` en `mv_facturacion_categoria_mes` y vistas analíticas | Panel gerencial, solo lectura |
| `app_web` | login | Miembro de `rol_app_lectura` + `rol_app_escritura` | Conexión real del backend |
| `admin_datos` | login | Dueño del esquema; sin `SUPERUSER` | Administración de la base |

Puntos que la spec de Kiro debe resolver explícitamente (ver "Diferencias
entre el material de cátedra y la base real" en `AGENTS.md`):

- `rol_app_escritura` y `sp_crear_pedido`: el procedimiento es `SECURITY
  INVOKER` y toca `usuario` y `producto`; con los permisos de la tabla
  anterior, `app_web` probablemente no pueda ejecutarlo.
- `fn_autenticar`: es `SECURITY INVOKER` y lee `usuario`; con la tabla de
  arriba, `app_web` no tiene permiso sobre esa tabla. Misma pregunta para el
  simulacro de la Parte C: definir con qué rol se ejecuta cada paso (login
  fallido, login exitoso, lectura masiva de `usuario`, intento de
  escalamiento) y justificarlo; ningún rol de aplicación del diseño base
  puede leer `usuario` directamente.
- `admin_datos`: el script del apunte lo crea con `CREATEDB CREATEROLE`.
  Son privilegios amplios: justificarlos o quitarlos.
- `ALTER DEFAULT PRIVILEGES` debe referirse al rol que realmente es dueño de
  las tablas.

## Vistas disponibles

| Vista | Descripción | Archivo | Consumidor previsto |
|---|---|---|---|
| `v_categorias_vigentes` | Categorías con `eliminado = FALSE` | `objects.sql` | `rol_app_lectura` |
| `v_productos_vigentes` | Productos y categorías activos | `objects.sql` | `rol_app_lectura` |
| `v_pedidos_resumen` | Pedidos vigentes con nombre completo del usuario | `objects.sql` | `rol_soporte` |
| `v_pedido_detalle` | Líneas de detalle vigentes con nombre del producto | `objects.sql` | — |
| `v_usuario_seguro` | Usuarios sin la columna `contrasena` | `views.sql` | `rol_soporte` |

## Vista materializada

| Vista materializada | Descripción | Archivo |
|---|---|---|
| `mv_facturacion_categoria_mes` | Facturación agregada por categoría y mes (solo pedidos `CONFIRMADO` vigentes). No se actualiza sola: requiere `REFRESH MATERIALIZED VIEW CONCURRENTLY`. Índice único `(categoria_id, mes)`. | `materializadas.sql` |
