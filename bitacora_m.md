# Bitácora de IA — Mariano (se consolida en BITACORA.md en la Parte E)

## Declaración de herramientas

- **Kiro**: spec de la Parte A (requirements y design).
- **Claude (claude.ai)**: apoyo para dividir el trabajo, revisar la spec de Kiro, y redactar un borrador de
  `sql/roles.sql` y de esta bitácora. Todo fue revisado y probado por mí antes de usarse.
- **OpenCode**: auditoría de `roles.sql` (una primera sesión se descartó por abrir otro proyecto; la segunda se hizo sobre este repo) y aplicación de dos cambios puntuales con instrucciones exactas.

## Constancia de reconstrucción

| Artefacto | Qué pasó | Cómo se resolvió |
|---|---|---|
| `roles.sql` | **[VERIFICAR]** No había una versión de la Clase 1 en el repositorio | Se escribió desde la spec de Kiro; se ejecuta de forma re-ejecutable y quita permisos viejos si los roles ya existían |
| `fn_autenticar` | No está en `base_heredada` | Se crea en `roles.sql` a partir del patrón de la clase, pasada a `SECURITY DEFINER` (D2) |
| `fn_resetear_password` | No está en `base_heredada` | Se crea en `roles.sql` a partir del patrón de la clase, con `SECURITY DEFINER` (D6) |

## Registros (Parte A)

| Prompt enviado a la IA | Respuesta relevante recibida (resumida) | Validación o corrección humana aplicada |
|---|---|---|
| **Kiro, 1.º prompt:** pedí la spec de la Parte A con los roles, las decisiones ya tomadas (D1 a D5) y las restricciones (sin `GRANT ALL`, `ALTER DEFAULT PRIVILEGES`, pruebas en `BEGIN…ROLLBACK`) | Generó `requirements.md` (12 requisitos) y `design.md` (decisiones, privilegios esperados, consultas de verificación, orden de `roles.sql`, 20 pruebas, contrato con la Parte C) | Revisé línea por línea. Cumplía las restricciones de seguridad, pero el orden de `roles.sql` tenía errores: (1) `ALTER … OWNER TO admin_datos` antes de crear ese rol; (2) `GRANT EXECUTE` sobre funciones aún no creadas; (3) las funciones `SECURITY DEFINER` quedarían a nombre de `postgres`, es decir con privilegios de superusuario; (4) la limpieza con `DROP OWNED BY admin_datos` habría borrado todas las tablas. Además `log_statement = 'mod'` no registraba los `SELECT` del simulacro y la clave de prueba quedaba en texto plano en el log |
| **Kiro, 2.º prompt:** lista de esos errores para corregir | Corrigió el orden, agregó D6, el `REASSIGN OWNED` previo y la advertencia de privacidad del log | Quedaban errores: el paso 5 hacía `ALTER FUNCTION` sobre funciones que no existen todavía; la limpieza omitía `admin_datos` y `DROP ROLE` fallaría por sus default privileges; la consulta 4e perdía la detección de `PUBLIC` |
| **Kiro, 3.º prompt:** siete correcciones puntuales | Corrigió los siete puntos | Verifiqué los nombres y firmas de todos los objetos contra `objects.sql` y `views.sql`: coinciden |
| Borrador de `roles.sql` generado con Claude a partir de `design.md` | Script de 10 pasos, en transacción y re-ejecutable | Lo leí bloque por bloque. Ensayo con `ROLLBACK`: sin errores, 8 avisos por membresías inexistentes y dueños sin cambios. Ejecución con `COMMIT`: sin errores y las cinco tablas pasaron a `admin_datos`. Consultas 4a, 4b, 4c, 4d, 4e (corregida) y 4f coinciden con la tabla de privilegios esperados (ver `docs/verificacion_permisos.md`). La prueba de default privileges (`f_prueba`) dio `false`, como se esperaba. Pruebas T01 a T23: 23 de 23 en `OK` tras re-ejecutar `roles.sql` con `COMMIT` (ver `docs/verificacion_permisos.md`, sección 5) |
| Consulta 4e de `design.md` (Kiro) | Usa `routine_type`, columna que no existe en `information_schema.role_routine_grants` | Al ejecutarla dio `ERROR: no existe la columna «routine_type»`. Corregí la consulta quitando esa columna; el resultado esperado (tres `EXECUTE` y cero filas para `PUBLIC`) se cumplió |
| Consulta 4c de `design.md` (Kiro) | Da por hecho que la 4c muestra todos los permisos de tablas y vistas | `information_schema` no incluye las vistas materializadas, así que el permiso de `rol_reportes` no aparece. Lo verifiqué con `relacl` de `pg_class`: `rol_reportes=r/admin_datos` |
| Kiro: sincronizar la spec con `roles.sql` (seis cambios: `ALTER DEFAULT PRIVILEGES` global para funciones, `GRANT CREATE` sobre `public`, paso 7.0, consultas 4c y 4e, T21 y T22) | Aplicó los seis cambios, pero en el paso 9 dejó una verificación con `has_function_privilege('app_web', 'fn_autenticar(text,text)', 'EXECUTE')` y resultado esperado `false` | Al leer el archivo vi que daría `true`: `app_web` es miembro de `rol_app_autenticar` y hereda `EXECUTE`. La reemplacé por la prueba con una función nueva creada por `admin_datos` (`f_prueba`), que ya había ejecutado y dio `false` |
| Script de pruebas T01 a T23 (`sql/verificacion_roles.sql`) generado con Claude a partir de la sección 6 de `design.md`, con T21 y T22 de Kiro y T23 agregada | Script que ejecuta cada prueba con `SET LOCAL ROLE` y muestra una tabla de `OK` o `FALLO` | La primera corrida dio 21 de 23. **T22** estaba mal diseñada por la IA: `SET ROLE` se valida contra el usuario de la sesión (`postgres`) y siempre funciona; la reemplacé por una comprobación de membresía. **T23** detectó que el filtro `rol <> 'ADMIN'` estaba en `roles.sql` pero no aplicado en la base, porque solo había ejecutado el ensayo con `ROLLBACK`; lo confirmé con `pg_get_functiondef`. Tras re-ejecutar `roles.sql` con `COMMIT`: 23 de 23 en `OK` |
| Ejecución repetida de `roles.sql` | Terminó en `COMMIT` con avisos y con "ya recibió membresía" en los tres `GRANT` | Evidencia de que el script es re-ejecutable (R12) |
| **OpenCode:** auditar `sql/roles.sql` (privilegios de más, funciones `SECURITY DEFINER`, orden, re-ejecutabilidad, escalamiento). Una primera sesión abrió otro proyecto por error y la descarté; la repetí con el repo correcto | Informe con 10 hallazgos. No propuso ningún `GRANT ALL` ni permiso más amplio. Marcó como Crítico (H1) que `REVOKE` de una membresía inexistente da ERROR y rompe la primera corrida; propuso además modificar `fn_resetear_password` (longitud mínima, tabla de auditoría), el cuerpo de `sp_crear_pedido`, una lista permitida de bases y rotar el marcador de contraseña | **H1 era incorrecto:** mi propia ejecución (ensayo con `ROLLBACK` y ejecución con `COMMIT`) terminó sin errores y solo emitió 8 `WARNING` en esos `REVOKE`; en PostgreSQL 16 o superior son avisos. No apliqué el cambio. **Decisión del equipo sobre H2:** se aplicó solo el filtro `rol <> 'ADMIN'` en `fn_resetear_password`; se descartó la longitud mínima y la tabla de auditoría, que la spec no prevé; la función no hace nada (sin error) si el usuario es ADMIN. **H7** se aplicó (`REVOKE CREATE … FROM PUBLIC`). H4 exige modificar el cuerpo de `sp_crear_pedido`, que D1 deja intacto; H6 impediría usar otro nombre de base; H3 y H5 no se aplicaron. Los dos cambios los ejecutó OpenCode con instrucciones exactas mías y revisé el diff antes de aceptarlos. Verificado con T23 y repitiendo T01 a T22: 23 de 23 en `OK` |
| Sincronización de la spec (`design.md`, `requirements.md`) con el filtro `ADMIN`, el `REVOKE CREATE`, T22 y T23, hecha a mano con ayuda de Claude | Edición puntual de R4, de la descripción de `fn_resetear_password`, del paso 4 y de la tabla de pruebas | Revisé que cada cambio refleje lo que hace `roles.sql` y lo que prueba `verificacion_roles.sql`. Por tratarse de una edición manual y no de una regeneración en Kiro, queda declarado acá |

## Diferencias entre `roles.sql` y la spec de Kiro (a reflejar en la spec)

Hallazgos al traducir la spec a SQL. Los puntos 1 y 2 quedaron **confirmados** con la prueba de `f_prueba` (ver `docs/verificacion_permisos.md`, sección 4); el punto 3 se aplicó sin errores, aunque no había permisos viejos que quitar:

1. `ALTER DEFAULT PRIVILEGES … REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` no puede llevar `IN SCHEMA`: según la documentación de PostgreSQL, el `REVOKE` por esquema no quita un privilegio otorgado globalmente, y el `EXECUTE` para `PUBLIC` es el valor por omisión global. En el script va sin `IN SCHEMA`.
2. `admin_datos` necesita `CREATE` sobre el esquema `public` para poder crear objetos nuevos (desde PostgreSQL 15 `PUBLIC` no lo tiene). La spec no lo contemplaba.
3. Si los roles ya existían de la clase, pueden traer permisos viejos: el script los quita con `REVOKE ALL ON ALL TABLES/SEQUENCES/ROUTINES` y revoca membresías sobrantes antes de otorgar lo de la spec.

## Limitaciones de diseño aceptadas

- `app_web` puede crear un pedido para cualquier `p_usuario_id`: `sp_crear_pedido` no valida que coincida con el usuario conectado.

## Caso más significativo de error de la IA (Parte E, punto 2)

**[COMPLETAR al cierre.]** Candidato: la primera spec de Kiro, con el orden de `roles.sql` y la limpieza que habría borrado las tablas.

## Nota sobre el historial de Git (Parte E, punto 3)

**[COMPLETAR al cierre.]**
