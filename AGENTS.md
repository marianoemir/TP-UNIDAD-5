# Food Store — Instrucciones para Agentes

TP Unidad 5 — Administración y seguridad: roles, auditoría, incidentes y
protección de datos personales (Base de Datos II, UTN).

## Stack Tecnológico

| Componente | Tecnología / Versión | Propósito |
|---|---|---|
| Motor BD | PostgreSQL 16+ (el grupo usa 18 en local) | Base de datos relacional |
| Lenguaje | SQL / PL/pgSQL | Roles, permisos, funciones, scripts de prueba |
| Extensión | `pgcrypto` | `crypt()` y `gen_salt()`: hash de contraseñas (la usan `fn_autenticar` y `fn_resetear_password`) |
| Cliente | pgAdmin 4 y `psql` (SQL Shell) | `\du` es un meta-comando de `psql`: no funciona en el Query Tool de pgAdmin. Alternativa equivalente: `SELECT … FROM pg_roles` |
| Herramientas del TP | OpenCode, Kiro, Git | Obligatorias según la consigna: cada una deja evidencia que se evalúa |

## Alcance ético (regla principal del TP)

Todo lo que pide este TP —incluido el simulacro de incidente— se ejecuta
**exclusivamente contra la instancia propia de Food Store** (`copia_u5`).
Ninguna instrucción de este repo habilita probar técnicas de ataque contra
sistemas de terceros, bases de otros equipos o servicios ajenos. Ante
cualquier duda de alcance, se trabaja solo sobre el entorno propio.

## Metodología de trabajo: Plantilla y Copia de Trabajo

El grupo (3 integrantes) trabaja con **dos bases separadas** en el mismo
servidor PostgreSQL local, administradas con pgAdmin:

1. **`plantilla_food_store`** — base limpia y de referencia (ya existe de la
   U4: `schema.sql` → `objects.sql` → `data.sql`). No recibe `carga_masiva.sql`
   ni ningún script de este TP.
2. **`copia_u5`** — base nueva para esta unidad. Se crea con `Create >
   Database...` eligiendo `plantilla_food_store` como **Template** (requiere
   que nadie esté conectado a la plantilla). Ahí se corre `carga_masiva.sql`,
   los scripts de índices/vistas heredados y todo lo de `sql/`.
   **No reutilizar** `copia_trabajo` ni `copia_fnbc`: tienen cambios de la U4.

### Los roles son del servidor, no de la base (cambio clave respecto de la U4)

- Un `CREATE ROLE` **sobrevive** a `DROP DATABASE copia_u5`. Borrar y recrear
  la copia no deshace los roles: para empezar de cero hay que limpiarlos
  explícitamente. `sql/roles.sql` debe tener un bloque de limpieza (`DROP
  OWNED BY … ; DROP ROLE …`) probado, equivalente al `down.sql` de la U4.
- **Antes de la Parte A**: respaldar los roles existentes del servidor
  (`pg_dumpall --roles-only` por línea de comandos o, como mínimo, guardar el
  resultado de `SELECT * FROM pg_roles`). Ese dump contiene **hashes de
  contraseñas**: va en `respaldos/`, que está en `.gitignore`, y **jamás se
  sube al repo**. No confundir con el entregable `sql/roles.sql`, que sí se
  versiona.
- **`ALTER SYSTEM` (Parte B) no se puede probar dentro de `BEGIN…ROLLBACK`.**
  Antes de cambiar cada parámetro se anota su valor original (`SHOW …`) en
  `docs/informe_auditoria.md`. Para volver atrás: `ALTER SYSTEM RESET <param>;`
  + `SELECT pg_reload_conf();`.
- `GRANT` y `REVOKE` sí son transaccionales: se prueban primero dentro de
  `BEGIN … ROLLBACK`.

## Protocolo de seguridad (obligatorio, ver `protocolo_seguridad.md`)

1. Antes de escribir `roles.sql`: spec en Kiro (`requirements` + `design`) que
   justifique cada rol y cada privilegio.
2. Todo script, propio o generado por IA, se lee línea por línea y se prueba
   en `copia_u5` (nunca en la plantilla) antes de darlo por bueno.
3. Se verifica con `\du` y `information_schema.role_table_grants` que cada
   rol tiene **exactamente** lo previsto en la spec: ni más, ni menos.
4. Ningún permiso propuesto por una IA se aplica sin auditarlo contra la
   tabla de diseño; las discrepancias y la decisión tomada van a
   `BITACORA.md`.
5. Nada con datos personales reales se envía a un asistente de IA (ver
   regla 16).

## Estructura de carpetas (la define la consigna de la U5)

```
food-store-tp-u5/
├── sql/
│   ├── roles.sql                 roles, GRANT/REVOKE, fn_autenticar, fn_resetear_password, limpieza
│   ├── auditoria_test.sql        secuencia de pruebas de la Parte B
│   ├── simulacro_incidente.sql   simulacro de la Parte C
│   └── usuario_anon.sql          anonimización de la Parte D
├── docs/
│   ├── kiro_roles_spec/          requirements.md y design.md (Kiro)
│   ├── informe_auditoria.md
│   ├── log_auditoria_prueba.txt
│   ├── log_simulacro_anonimizado.txt
│   ├── informe_incidente.md
│   └── verificacion_equivalencia.md
├── base_heredada/                los 10 .sql de Food Store (U1–U4), sin modificar
├── BITACORA.md                   bitácora de IA (formato obligatorio)
├── AGENTS.md  protocolo_seguridad.md  README.md
└── .kiro/steering/               project-overview.md, conventions.md, objects-and-patterns.md
```

`respaldos/` existe solo en local y está en `.gitignore`.

## Orden de ejecución

```
En plantilla_food_store (ya hecho en la U4):
  base_heredada/schema.sql → objects.sql → data.sql

En copia_u5 (creada con TEMPLATE plantilla_food_store):
  carga_masiva.sql → indices_semana3.sql → indices.sql → views.sql
  → materializadas.sql                      (base heredada)
  → sql/roles.sql                           (Parte A: abre con CREATE EXTENSION pgcrypto)
  → sql/auditoria_test.sql                  (Parte B)
  → sql/simulacro_incidente.sql             (Parte C: crea sus usuarios de prueba con hash real)
  → sql/usuario_anon.sql                    (Parte D)
```

## Diferencias entre el material de cátedra y la base real

El apunte de la Clase 1/2 se escribió contra nombres que **no coinciden
exactamente** con esta base. Copiar los bloques tal cual falla o deja
permisos mal otorgados. Cada caso se resuelve y se asienta en `BITACORA.md`
(la consigna lo exige: "dejar constancia de la reconstrucción").

| El material usa | La base real tiene | Qué hacer |
|---|---|---|
| `v_usuarios_publico` (sin `contrasena` ni `celular`) | `v_usuario_seguro` (`views.sql`), solo sin `contrasena` | Usar la real. Revisar si expone `celular` y decidir si alcanza |
| `mv_ventas_categoria_mes` | `mv_facturacion_categoria_mes` (`materializadas.sql`) | Usar la real |
| `crypt()` / `gen_salt()` | `pgcrypto` no está instalada en ningún `.sql` heredado | `CREATE EXTENSION IF NOT EXISTS pgcrypto;` al inicio de `roles.sql` |
| Hashes bcrypt válidos | Hash **ficticio** (`'$2a$10$e8.y7/S8S.a...hash_ficticio'`) en los ~20.000 usuarios de `carga_masiva.sql` y marcadores `'hash_*'` en `data.sql` | Ninguna contraseña coincide y `crypt()` puede fallar por sal inválida. Crear usuarios de prueba con `crypt('…', gen_salt('bf'))` para el login exitoso del simulacro |
| `ALTER DEFAULT PRIVILEGES FOR ROLE admin_datos` | Las tablas las creó el rol que corrió `schema.sql`, no `admin_datos` | La sentencia solo cubre objetos que cree `admin_datos`: transferir el dueño o usar `FOR ROLE <dueño real>`; comprobarlo creando una tabla de prueba |
| `rol_app_escritura`: SELECT/INSERT/UPDATE en `pedido` y `detalle_pedido` + EXECUTE en `sp_crear_pedido` | `sp_crear_pedido` es `SECURITY INVOKER`: lee `usuario`, hace `SELECT … FOR UPDATE` y `UPDATE` sobre `producto`; `fn_set_subtotal` lee `producto` | Con el diseño de la clase, `app_web` probablemente **no puede** ejecutar el procedimiento. Probarlo (`SET ROLE app_web`) y resolverlo: GRANTs mínimos por columna o `SECURITY DEFINER` con `search_path` fijo. Registrarlo como hallazgo |
| `fn_autenticar` como función de login de la aplicación (`SECURITY INVOKER`) | Consulta `usuario` (incluida `contrasena`), pero `app_web` no recibe ningún permiso sobre esa tabla en el diseño de la clase | Si la ejecuta `app_web`, falla con `permission denied`. Decidir cómo se resuelve (permiso mínimo por columna o función acotada) y justificarlo. Lo mismo para definir **con qué rol se ejecuta cada paso del simulacro** (la "lectura masiva de `usuario`" también necesita un rol que pueda leerla) |
| `\du` | es de `psql` | SQL Shell, o `pg_roles` desde pgAdmin |

`usuario.rol` (ENUM `ADMIN`/`USUARIO`) **no es** un rol de PostgreSQL: es un
dato de la aplicación. Los roles de esta unidad se crean con `CREATE ROLE` y
el motor los hace cumplir; la columna no protege nada a nivel del motor.

## Vistas y objetos heredados (NO recrear)

Son los objetos sobre los que se otorgan permisos; están en `base_heredada/`.

- `objects.sql`: `v_categorias_vigentes`, `v_productos_vigentes`,
  `v_pedidos_resumen`, `v_pedido_detalle`; función `calcular_total_pedido`;
  triggers `trg_subtotal`, `trg_total_ins`, `trg_total_upd`,
  `trg_validar_estado_pedido`; procedimiento `sp_crear_pedido(BIGINT,
  forma_pago, JSONB)`.
- `views.sql`: `v_usuario_seguro`.
- `materializadas.sql`: `mv_facturacion_categoria_mes` (requiere `REFRESH
  MATERIALIZED VIEW CONCURRENTLY`; no se actualiza sola).
- Índices (6, en `schema.sql`, `indices_semana3.sql` e `indices.sql`): no se
  proponen índices nuevos en este TP.

## Reglas Duras del Proyecto

Heredadas de las unidades anteriores:

1. **Nombres de tablas:** singular y español.
2. **Borrado lógico:** nunca `DELETE`; `UPDATE … SET eliminado = TRUE`.
3. **Altas de pedidos:** siempre `CALL sp_crear_pedido(...)`.
4. **Triggers automáticos:** no modificar `trg_subtotal`, `trg_total_ins`,
   `trg_total_upd`, `trg_validar_estado_pedido`.
5. **Vistas vigentes:** usarlas en vez de escribir el filtro a mano.
6. **JOINs y borrado lógico:** `eliminado = FALSE` en cada tabla del JOIN.

Propias de la Unidad 5 (seguridad):

7. **Mínimo privilegio:** un privilegio puntual sobre un objeto puntual, según
   la tabla de diseño. Nunca `GRANT ALL`, ni `GRANT … ON ALL TABLES` "por
   comodidad".
8. **Sin atributos administrativos en roles de aplicación:** `rol_app_lectura`,
   `rol_app_escritura`, `rol_soporte`, `rol_reportes` y `app_web` jamás con
   `SUPERUSER`, `CREATEROLE` ni `CREATEDB`. `admin_datos` nunca es `SUPERUSER`.
9. **Grupo vs. login:** los permisos viven en roles de grupo (sin `LOGIN`); los
   roles de login (`app_web`, `admin_datos`) solo reciben membresías.
10. **Sin SQL por concatenación:** el dato del usuario viaja como parámetro
    (parámetros tipados o `EXECUTE … USING`), nunca dentro del texto del comando.
11. **Funciones `SECURITY DEFINER`:** siempre con `SET search_path = public,
    pg_temp`, `REVOKE ALL … FROM PUBLIC`, `GRANT EXECUTE` solo al rol que la
    necesita, y haciendo una única tarea acotada.
12. **Contraseñas:** solo como hash (`crypt` + `gen_salt('bf')`). En scripts
    versionados, solo marcadores (`'cambiar_en_produccion'`). Ninguna
    contraseña real en el repo ni en un log que se entregue.
13. **Vistas de usuario:** ninguna expone `contrasena`; sin `SELECT *` dentro
    de una definición de vista.
14. **Auditoría:** no se registran contraseñas ni filas completas con datos
    personales; el propio log es un activo sensible y se trata como tal.
15. **Todo lo propuesto por IA se audita** línea por línea contra la tabla de
    diseño antes de aplicarse.
16. **Datos personales e IA:** jamás se envía a un asistente de IA filas reales
    de `usuario` (mail, celular, nombre, apellido, contraseña —ni hasheada—),
    logs sin anonimizar, ni backups. Se trabaja sobre `usuario_anon` o sobre
    extractos con identificadores sintéticos. Ojo: `data.sql` contiene datos
    reales de integrantes del grupo.
17. **Contención:** la decisión de contención ante un incidente es del equipo,
    tomada a partir de evidencia. Un agente propone; **nunca ejecuta** una
    acción de contención ni modifica permisos por su cuenta.

## Trabajo Práctico en curso — Unidad 5

| Parte | Qué se entrega | Dónde |
|---|---|---|
| A. Roles y permisos | `roles.sql` revisado/ampliado (incluye un permiso por columna sobre `usuario` y `ALTER DEFAULT PRIVILEGES`), spec de Kiro, salida de la verificación (`\du` + `role_table_grants`) | `sql/roles.sql`, `docs/kiro_roles_spec/` |
| B. Auditoría | Parámetros activados (`log_connections`, `log_disconnections`, `log_statement`), log de pruebas (lectura, inserción, actualización, login fallido), respuestas a los puntos 3 y 4 | `sql/auditoria_test.sql`, `docs/informe_auditoria.md`, `docs/log_auditoria_prueba.txt` |
| C. Simulacro | Script (login fallidos → login exitoso → lectura masiva de `usuario` → intento de escalamiento a `admin_datos`), log anonimizado, respuesta completa de la IA, contraste escrito, informe de contención | `sql/simulacro_incidente.sql`, `docs/log_simulacro_anonimizado.txt`, `docs/informe_incidente.md` |
| D. Datos personales | `usuario_anon`, consulta de agregación sobre `usuario_anon` y su equivalente sobre `usuario`, resultados lado a lado, texto sobre qué no debe salir hacia una IA | `sql/usuario_anon.sql`, `docs/verificacion_equivalencia.md` |
| E. Cierre | `BITACORA.md` consolidada, caso más significativo de error de la IA, revisión del historial de Git | `BITACORA.md` |

Reglas de proceso que se evalúan:

- **Git:** avance por partes, con commits legibles; **no** se acepta un único
  commit final. Cada integrante commitea su parte con su usuario. Todo se
  mergea a `main` antes de dar una parte por cerrada (en la U4 hubo trabajo
  que quedó en una rama sin mergear).
- **`BITACORA.md`:** una tabla de tres columnas (*Prompt enviado a la IA*,
  *Respuesta relevante recibida (resumida)*, *Validación o corrección humana
  aplicada*). Un registro como mínimo por cada parte donde se usó OpenCode;
  al menos **un caso real** en que la IA propuso algo incorrecto, inseguro o
  de más, y cómo se detectó. Incluye la constancia de la reconstrucción de
  `roles.sql`, `fn_autenticar`, `fn_resetear_password` y `usuario_anon`.
  Si en alguna parte se usó otra IA además de OpenCode, se declara.
- **OpenCode, Parte C punto 4:** el log anonimizado se entrega en una
  **sesión limpia**, sin contexto adicional al que el log ofrece; la
  respuesta completa se guarda tal cual.
- **Kiro:** la spec se escribe **antes** de `roles.sql`.

## Base de Conocimiento y Steering

- `.kiro/steering/project-overview.md`: visión general, orden de ejecución y
  diseño de roles.
- `.kiro/steering/conventions.md`: convenciones de base de datos y de
  seguridad.
- `.kiro/steering/objects-and-patterns.md`: objetos heredados y patrones SQL
  de seguridad (GRANT, `SECURITY DEFINER`, anonimización, verificación).
