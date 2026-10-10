# Food Store — Convenciones de Base de Datos y de Seguridad

## Nombres de tablas

Los nombres de tabla son **en singular y en español**:

```
categoria, producto, usuario, pedido, detalle_pedido
```

No usar plural (`productos`), ni inglés (`product`), ni PascalCase. Las
tablas nuevas de esta unidad (por ejemplo `usuario_anon`) siguen la misma regla.

## Columna `eliminado` — Borrado lógico

**Nunca se ejecuta `DELETE`** sobre las tablas del proyecto. Todas tienen
`eliminado BOOLEAN NOT NULL DEFAULT FALSE` y la baja es siempre:

```sql
UPDATE <tabla> SET eliminado = TRUE WHERE id = :id AND eliminado = FALSE;
```

Toda consulta de datos vigentes filtra `WHERE eliminado = FALSE`, **en cada
tabla del JOIN**, no solo en la principal. Las vistas `v_categorias_vigentes`,
`v_productos_vigentes`, `v_pedidos_resumen`, `v_pedido_detalle` y
`v_usuario_seguro` ya aplican el filtro: usarlas cuando cubran el caso.

Baja de un pedido completo (detalles primero, luego el pedido):

```sql
BEGIN;
    UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = :id;
    UPDATE pedido SET eliminado = TRUE WHERE id = :id;
COMMIT;
```

Esto vale también para la seguridad: `fn_autenticar` y `fn_resetear_password`
filtran `eliminado = FALSE`, de modo que un usuario dado de baja no puede
autenticarse ni recibir un reseteo.

## Columnas con reglas propias

- `detalle_pedido.precio_unitario` **congela** el precio al momento de la
  venta; no se recalcula si cambia `producto.precio`.
- `producto.disponible`: `sp_crear_pedido` rechaza productos con
  `disponible = FALSE` aunque tengan stock.
- `pedido.estado`: el trigger `trg_validar_estado_pedido` impide pasar de
  `CONFIRMADO` a `PENDIENTE`. No se valida a mano.

## Restricciones de integridad destacadas

- `categoria.nombre` → `UNIQUE`
- `usuario.mail` → `UNIQUE` + `CHECK` de formato (`chk_usuario_mail_formato`)
- `pedido.fecha` → `CHECK (fecha <= CURRENT_DATE)`
- `detalle_pedido(pedido_id, producto_id)` → `UNIQUE`
- `producto.precio >= 0`, `producto.stock >= 0`, `detalle_pedido.cantidad > 0`
- `detalle_pedido.pedido_id` con `ON DELETE RESTRICT`

## Tipos de datos a respetar

| Campo | Tipo |
|---|---|
| IDs | `BIGINT GENERATED ALWAYS AS IDENTITY` |
| Precios y totales | `NUMERIC(10,2)` / `NUMERIC(12,2)` |
| Fechas con zona | `TIMESTAMPTZ` (`created_at`) |
| Fecha del pedido | `DATE` |
| Contraseña | `VARCHAR(255)` — **solo hash**, nunca texto plano |

## Convenciones de seguridad (Unidad 5)

### Roles

- **Roles de grupo** (definen *qué* se puede hacer): `rol_<función>`, **sin
  `LOGIN`**. Los permisos se otorgan a estos roles, no a las personas ni a la
  aplicación.
- **Roles de login** (definen *quién* se conecta): nombre por función
  (`app_web`, `admin_datos`). No tienen permisos propios sobre objetos: solo
  reciben membresía en roles de grupo.
- Ningún rol de aplicación (`rol_app_*`, `rol_soporte`, `rol_reportes`,
  `app_web`) lleva `SUPERUSER`, `CREATEROLE` ni `CREATEDB`. Los atributos de
  `admin_datos` se justifican por escrito en la spec de Kiro.
- Cada rol y cada privilegio se justifica en una oración: qué operación
  habilita y por qué esa y no otra.

### Estilo de los scripts de roles

- **Re-ejecutables:** `CREATE ROLE` no admite `IF NOT EXISTS`. Envolverlo para
  poder correr `roles.sql` más de una vez (los roles sobreviven a `DROP
  DATABASE`):

  ```sql
  DO $$
  BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_soporte') THEN
          CREATE ROLE rol_soporte;
      END IF;
  END $$;
  ```
- **Orden:** extensión → roles de grupo → `GRANT USAGE ON SCHEMA` → privilegios
  por objeto → funciones y sus `GRANT EXECUTE` → roles de login → membresías →
  `ALTER DEFAULT PRIVILEGES` → bloque de limpieza (comentado y probado).
- **Privilegios explícitos:** un `GRANT` por rol y por objeto, con la lista
  puntual de privilegios. Sin `GRANT ALL`, sin `ON ALL TABLES`.
- **Permiso por columna** cuando una tabla tiene columnas que el rol no debe
  ver (ejemplo: `usuario` sin `contrasena`): `GRANT SELECT (id, nombre, …) ON
  usuario TO rol_soporte;`.
- **Contraseñas en scripts:** solo marcadores (`'cambiar_en_produccion'`).
  Una contraseña real nunca se versiona.

### Funciones y procedimientos

- Prefijos: `fn_` para funciones, `sp_` para procedimientos, `p_` para
  parámetros (`p_mail`, `p_usuario_id`).
- Entradas **siempre como parámetros tipados**; jamás concatenadas dentro de
  una cadena SQL. Si hace falta SQL dinámico, `EXECUTE … USING`.
- `SECURITY INVOKER` es el valor por omisión y se explicita. `SECURITY DEFINER`
  solo para tareas acotadas, con `SET search_path = public, pg_temp`,
  `REVOKE ALL … FROM PUBLIC` y `GRANT EXECUTE` solo al rol que la necesita.
- Las funciones de `pgcrypto` (`crypt`, `gen_salt`) requieren la extensión
  instalada; `search_path` debe incluir el esquema donde quedó.

### Contraseñas

- Almacenar `crypt(p_clave, gen_salt('bf'))`; comparar con
  `contrasena = crypt(p_clave, contrasena)`.
- La base heredada trae hashes **ficticios**: no autentican a nadie. Los
  usuarios de prueba que deban iniciar sesión se crean con hash real y viven
  solo en `copia_u5`.

### Auditoría y logs

- Parámetros mínimos: `log_connections`, `log_disconnections` y `log_statement`
  en un nivel que registre modificaciones (`mod` o superior).
- Con `log_statement`, los **literales de cada sentencia quedan en el log**
  (mails, nombres, valores). Por eso el log es un activo sensible: acceso solo
  para quien lo necesita (cuenta del servicio y administrador) y nunca se
  comparte ni se entrega a una IA sin anonimizar.
- Todo parámetro tocado con `ALTER SYSTEM` se registra con su valor anterior
  y su valor nuevo.

### Anonimización

- Valores sintéticos **deterministas**: `'Usuario ' || id`, `'Apellido ' || id`,
  `'usuario' || id || '@ejemplo.test'`. Mantienen la unicidad y la
  cardinalidad; un valor fijo como `'Anónimo'` para todas las filas las rompe.
- `celular` → `NULL`; `contrasena` → `'hash_no_valido'`.
- Al anonimizar un log: mails, nombres e IDs de personas reemplazados por
  valores sintéticos **consistentes** (la misma persona, el mismo valor en
  todo el log), para que la secuencia siga siendo reconstruible.
- Prueba de equivalencia: la misma agregación sobre `usuario_anon` y sobre
  `usuario` debe dar los mismos conteos y agrupamientos.

### Datos personales y asistentes de IA

Nunca se envía a una IA: filas reales de `usuario` (mail, celular, nombre,
apellido, contraseña —ni hasheada—), logs sin anonimizar, ni respaldos.
`base_heredada/data.sql` contiene datos reales de integrantes del grupo: no se
pega ni se adjunta. Se trabaja con `usuario_anon` o con extractos sintéticos.

## Índices existentes (referencia; no se agregan índices en este TP)

```
schema.sql          idx_producto_categoria_id, idx_pedido_usuario_id,
                    idx_producto_nombre_vigente
indices_semana3.sql idx_pedido_fecha_estado_vigente,
                    idx_pedido_usuario_total_estado
indices.sql         idx_producto_nombre_lower_vigente
```
