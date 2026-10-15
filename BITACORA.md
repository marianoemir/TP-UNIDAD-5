# Bitácora de uso de IA — TP Unidad 5 (Food Store)

Consolidación de la Parte E. Cada fila es una interacción real con una IA, tomada de las bitácoras personales
(`bitacora_m.md`, `bitacora_andres.md`, `bitacora_Facundo.md`) y de la evidencia guardada en `docs/`.
Nunca se envió a una IA un dato personal real ni un hash: solo valores sintéticos y logs ya anonimizados.

## Herramientas declaradas

| Herramienta | Quién | Para qué |
|---|---|---|
| **Kiro** | Mariano | Especificación de la Parte A (`docs/kiro_roles_spec/`: requirements y design) |
| **OpenCode** | Mariano, Andrés | Auditoría de `roles.sql` (A); reconstrucción del log en sesión limpia (C.4); consulta gemela de la Parte D |
| **Claude (claude.ai)** | Mariano | Reparto del trabajo, borrador de `roles.sql`, `verificacion_roles.sql`, script del simulacro, reescritura de `informe_incidente.md` |
| **Muse Spark (vía OpenCode)** | Andrés | Guía paso a paso de la Parte B y borradores de scripts e informe |
| **Gemini** | Facundo | Primera versión del contraste y de la contención (C.5–C.6) |

## Constancia de reconstrucción

La consigna parte de artefactos de la Clase 1 y 2. Ninguno estaba en el repositorio heredado (`base_heredada/` solo
trae los 10 `.sql` de las Unidades 1 a 4), así que se reconstruyeron:

| Artefacto | Qué pasó | Cómo se resolvió |
|---|---|---|
| `roles.sql` | No había un `roles.sql` en el repo ni roles creados en el servidor; los creó el equipo. | Se escribió desde la spec de Kiro. Es re-ejecutable: si los roles ya existían, quita permisos y membresías viejos antes de otorgar los de la spec |
| `fn_autenticar` | No está en `base_heredada` | Se crea en `roles.sql` a partir del patrón de la clase, como `SECURITY DEFINER` con dueño `admin_datos` (decisión D2) |
| `fn_resetear_password` | No está en `base_heredada` | Ídem, con `SECURITY DEFINER` (D6) y filtro `rol <> 'ADMIN'` |
| `usuario_anon` | No estaba en el repo | Se creó desde cero en `sql/usuario_anon.sql` con valores deterministas derivados del `id` |

## Parte A — Roles y permisos (Mariano)

| Prompt enviado a la IA | Respuesta relevante recibida (resumida) | Validación o corrección humana aplicada |
|---|---|---|
| **Kiro, 1.º prompt:** spec de la Parte A con los roles, las decisiones D1 a D5 y las restricciones (sin `GRANT ALL`, `ALTER DEFAULT PRIVILEGES`, pruebas en `BEGIN…ROLLBACK`) | `requirements.md` (12 requisitos) y `design.md` (decisiones, privilegios esperados, consultas de verificación, orden de `roles.sql`, pruebas) | Lectura línea por línea. Cumplía las restricciones de seguridad, pero el orden de `roles.sql` tenía errores: `ALTER … OWNER TO admin_datos` antes de crear ese rol; `GRANT EXECUTE` sobre funciones inexistentes; funciones `SECURITY DEFINER` a nombre de `postgres` (es decir, con privilegios de superusuario); y una limpieza con `DROP OWNED BY admin_datos` que habría borrado todas las tablas. Además `log_statement = 'mod'` no registraba los `SELECT` del simulacro y la clave de prueba quedaba en texto plano en el log |
| **Kiro, 2.º prompt:** lista de esos errores | Corrigió el orden, agregó D6 y el `REASSIGN OWNED` previo | Quedaban errores: el paso 5 hacía `ALTER FUNCTION` sobre funciones aún inexistentes; la limpieza omitía `admin_datos` y `DROP ROLE` habría fallado por sus default privileges; la consulta 4e perdía la detección de `PUBLIC`: el error fue de Claude, que armó esta lista: su punto 5 pedía excluir `PUBLIC` de las consultas 4c y 4e, y Kiro lo cumplió tal cual; se corrigió en el 3.º prompt |
| **Kiro, 3.º prompt:** siete correcciones puntuales | Corrigió los siete puntos | Verifiqué nombres y firmas de todos los objetos contra `objects.sql` y `views.sql` |
| **Claude:** borrador de `roles.sql` a partir de `design.md` | Script de 10 pasos, en transacción y re-ejecutable | Lectura bloque por bloque. Ensayo con `ROLLBACK` sin errores; ejecución con `COMMIT` sin errores. Consultas 4a–4f coinciden con la tabla de privilegios esperados (`docs/verificacion_permisos.md`) |
| **Kiro:** consulta 4e del `design.md` | Usa la columna `routine_type`, que no existe en `information_schema.role_routine_grants` | Dio `ERROR: no existe la columna «routine_type»`. La corregí; el resultado esperado (tres `EXECUTE`, cero filas para `PUBLIC`) se cumplió |
| **Kiro:** consulta 4c del `design.md` | Da por hecho que muestra todos los permisos de tablas y vistas | `information_schema` no incluye vistas materializadas, así que faltaba el permiso de `rol_reportes`. Lo verifiqué con `relacl` de `pg_class`: `rol_reportes=r/admin_datos` |
| **Kiro:** sincronizar la spec con `roles.sql` (seis cambios) | Los aplicó, pero dejó en el paso 9 `has_function_privilege('app_web', 'fn_autenticar(text,text)', 'EXECUTE')` con resultado esperado `false` | Daría `true`: `app_web` es miembro de `rol_app_auth` y hereda `EXECUTE`. La reemplacé por la prueba con una función nueva creada por `admin_datos` (`f_prueba`), que dio `false` |
| **Claude:** `sql/verificacion_roles.sql` (pruebas T01–T23 con `SET LOCAL ROLE`) | Script que muestra `OK` o `FALLO` por prueba | La primera corrida dio 21 de 23. **T22** estaba mal diseñada por la IA: `SET ROLE` se valida contra el usuario de la sesión (`postgres`) y siempre funciona; la reemplacé por una comprobación de membresía. **T23** reveló que el filtro `rol <> 'ADMIN'` estaba en `roles.sql` pero no aplicado en la base (solo había corrido el ensayo con `ROLLBACK`); lo confirmé con `pg_get_functiondef`. Tras re-ejecutar con `COMMIT`: 23 de 23 en `OK` |
| **OpenCode:** auditar `sql/roles.sql` (privilegios de más, `SECURITY DEFINER`, orden, re-ejecutabilidad, escalamiento). La primera sesión abrió otro proyecto por error y se descartó; se repitió sobre este repo | Informe con 10 hallazgos. No propuso ningún `GRANT ALL`. Marcó como **Crítico (H1)** que `REVOKE` de una membresía inexistente da ERROR y rompe la primera corrida. Propuso además longitud mínima y tabla de auditoría en `fn_resetear_password`, cambiar el cuerpo de `sp_crear_pedido`, una lista de bases permitidas y rotar el marcador de contraseña | **H1 era incorrecto:** el ensayo y la ejecución reales terminaron sin errores, con 8 `WARNING` (en PostgreSQL 16+ son avisos). **Se aplicó** solo el filtro `rol <> 'ADMIN'` (H2) y `REVOKE CREATE … FROM PUBLIC` (H7). **Se descartó** la longitud mínima y la tabla de auditoría (la spec no las prevé), H4 (exige tocar `sp_crear_pedido`, que D1 deja intacto), H6 (impediría usar otro nombre de base), H3 y H5. OpenCode ejecutó los dos cambios con instrucciones exactas y se revisó el diff antes de aceptarlos. Verificado con T23 y T01–T22: 23 de 23 |
| **Claude:** sincronizar `design.md` y `requirements.md` con el filtro `ADMIN`, el `REVOKE CREATE`, T22 y T23 | Edición puntual de R4, de `fn_resetear_password`, del paso 4 y de la tabla de pruebas | Revisé que cada cambio refleje `roles.sql` y `verificacion_roles.sql`. Fue una edición manual y no una regeneración en Kiro, y queda declarado acá |

**Sobre el punto A.4 de la consigna** (registrar un caso en que la IA propuso un permiso más amplio de lo necesario): no apareció
ninguna propuesta de `GRANT ALL`. El caso más cercano es la primera spec de Kiro, que dejaba las funciones `SECURITY DEFINER`
a nombre de `postgres`: cualquier llamador las habría ejecutado con privilegios de superusuario. Se corrigió con D6 y con
dueño `admin_datos`.

## Parte B — Auditoría (Andrés)

| Prompt enviado a la IA | Respuesta relevante recibida (resumida) | Validación o corrección humana aplicada |
|---|---|---|
| Guía para el Paquete 1 con mi estado (`copia_u5` lista, `roles.sql` corrido, respaldo hecho) | Plan por partes y pedido de los 6 `SHOW` para documentar los valores originales | Ejecuté los `SHOW`: `off/off/none`, colector `on`. Los anoté en el informe |
| Cómo activar la auditoría. Los 4 `ALTER SYSTEM` juntos dieron `ERROR 25001` (dentro de un bloque de transacción) | Correrlos de a uno, en autocommit | Lo apliqué: `log_statement` quedó en `all`, pero `log_connections` y `log_disconnections` seguían en `off`. No lo dejé pasar y pedí diagnóstico |
| Diagnóstico de por qué dos parámetros no quedaban (`pg_settings`, `pg_file_settings`, `auto.conf`) | El `auto.conf` tenía los 3 valores (`applied=true`); faltaba recarga efectiva: `pg_reload_conf()` y reconectar, o reiniciar el servicio | Verifiqué `pg_conf_load_time` antes y después y reconecté: quedaron `on/on/all` con source `configuration file`. Recién ahí di por cerrado el punto B.1 |
| Cómo correr `auditoria_test.sql`; lo pegué como texto y dio `ERROR 42601` | En pgAdmin se abre con File→Open o se pega el contenido; una ruta no es SQL | Lo abrí y lo ejecuté: `NOTICE` de inicio y fin, `ROLLBACK` en 46 ms. Confirmé que no dejó datos de prueba |
| Cómo recortar el log (rango de líneas de la prueba) | Un bloque de pgAdmin llega como una sola `sentencia:` con todo el script, no una línea `LOG` por sentencia | Lo documenté en el informe (con `psql -f` quedaría separado). Guardé solo el recorte inicio→fin, sin ruido `pga4dash` |
| **Mariano · Claude:** completar la Parte B (conexión fallida real y corrección del punto 4). La IA propuso `sql/auditoria_test.ps1`, que corre el script con `psql -f` e intenta una conexión de `app_web` con clave incorrecta | Script que deja marcas `auditoria_b: inicio/fin` y la corrección del punto 4: los permisos del archivo de log son del sistema operativo y `admin_datos` no accede a archivos | Lo ejecuté: se rechazó la conexión con `FATAL`. **Imprecisión de la IA:** su guía daba por hecho que la auditoría estaba activa en mi servidor y no pidió comprobarlo antes. Lo detecté porque el log no tenía ninguna de las marcas (`marcas: 0` en todos los archivos) y solo mostraba el `FATAL`, que se registra siempre |
| **Mariano · Claude:** diagnóstico de por qué faltaban las sentencias en el log | Consultar `pg_settings`: `log_connections=off`, `log_disconnections=off`, `log_statement=none`, todos con source `default` | Confirmado en mi servidor (la configuración de Andrés no se hereda). Activé los tres con `ALTER SYSTEM` y `pg_reload_conf()`. `log_connections` quedó en `off` porque tipeé mal la contraseña en ese comando; lo vi en la verificación siguiente de `pg_settings` y lo repetí. Verificado: `on`, `on`, `all` con source `configuration file` |
| **Mariano · Claude:** extraer el fragmento con `Get-Content -Encoding UTF8` | Comandos de PowerShell para recortar entre las marcas y guardar en archivo | **Error de la IA:** el log mezcla codificaciones y esa lectura dañó las tildes y las comillas angulares (33 caracteres `?`). Lo vi al revisar el texto. Restauré las tildes con las palabras de los mensajes del servidor y dejé la edición declarada en el encabezado de `docs/log_auditoria_prueba.txt`. No se tocó ninguna sentencia, hora ni puerto |

## Parte C — Simulacro de incidente

| Prompt enviado a la IA | Respuesta relevante recibida (resumida) | Validación o corrección humana aplicada |
|---|---|---|
| **Mariano · Claude:** script del simulacro (SQL por pasos y orquestador PowerShell que se conecta como cada login) | `simulacro_incidente.sql` (pasos 0 a 4 y limpieza, con `\if`) y `simulacro_incidente.ps1` | Ejecutado en `copia_u5` (PostgreSQL 17.10): 5 intentos fallidos con 0 filas, inicio exitoso con 1 fila, lectura de 20007 filas, y los 3 intentos de escalamiento con permiso denegado (`docs/constancia_escalamiento.txt`). **El escalamiento falló: no hay hallazgo sobre `roles.sql`** |
| **Andrés · Muse Spark:** cómo ejecutar el orquestador. Dio `-File no existe` | Era el directorio de trabajo (`C:\WINDOWS\system32`); usar `Set-Location` al repo o ruta absoluta | Reejecuté desde el repo: pasos 0–4 OK, 3 de 3 escalamientos denegados. Restauré con `git checkout` la constancia de Mariano para no pisar su entregable |
| **Andrés · Muse Spark:** recorte y anonimización del log (líneas 8085–8148) | Bloque con conexiones, sentencias, 3 `ERROR` y desconexiones | Anonimicé antes de versionar: mail, nombres, celular, claves y `host=::1` → `IP_ANONIMIZADA`; excluí el ruido `pga4dash`. Criterio documentado en `docs/criterio_anonimizacion_log.md` |
| **Andrés · OpenCode, 1.ª corrida (C.4):** log anonimizado con prompt fijo y sin contexto | Reconstrucción en 5 sesiones con patrón de fuerza bruta, lectura masiva y 3 denegaciones; hallazgo de claves en claro por `log_statement='all'` | Guardada sin editar (hoy en `docs/respuesta_opencode_simulacro_v1.md`). **Después se descartó como evidencia:** el archivo del log llevaba un encabezado con el mapa de valores originales y la IA usó información que solo estaba ahí (la exclusión de ruido de pgAdmin). No se ejecutó nada de lo propuesto |
| **Mariano · OpenCode, 2.ª corrida (C.4):** mismo prompt, con el log sin encabezado (70 líneas) en una carpeta vacía fuera del repo. | Reconstrucción con referencias de línea, 3 denegaciones y contención proporcional (`docs/respuesta_opencode_simulacro.md`) | Es la respuesta que se contrasta. El encabezado se movió a `docs/criterio_anonimizacion_log.md`, para no dárselo a la IA |
| **Facundo · Gemini:** contraste entre OpenCode y el log (C.5) | Coincidencias (fuerza bruta, lectura masiva, bloqueo por mínimo privilegio, claves en el log) y omisiones | Verificado contra la respuesta de OpenCode y contra `simulacro_incidente.sql`. **Esta versión fue reemplazada** por la de Mariano (abajo) |
| **Facundo · Gemini:** decisión de contención (C.6) | Tres ejes: `ALTER ROLE soporte_sim NOLOGIN`, revocar privilegios del simulacro, bajar `log_statement` y proteger el directorio de logs | Validado contra el esquema de roles. Se conservó la idea de `NOLOGIN` y la protección del log |
| **Mariano · Claude:** reescribir `docs/informe_incidente.md` (C.5 y C.6) con la 2.ª respuesta de OpenCode | Informe con cuatro afirmaciones de la IA que el log no sustenta, límites del experimento y decisión de contención | Revisé cada afirmación contra el log: (1) "`app_web` ya estaba autenticado": cada paso abre una conexión nueva con `scram-sha-256`; (2) "el umbral de bloqueo es mayor que 5": el log no muestra resultados; (3) "el paso 3 demuestra sobre-permiso": esas columnas son las de `rol_soporte` por diseño; (4) "`postgres` remoto está justificado": la conexión era local y `IP_ANONIMIZADA` borró ese dato. **La decisión de contención es del equipo, y nada se ejecutó a partir de lo que sugirió la IA** |

## Parte D — Anonimización y equivalencia

| Prompt enviado a la IA | Respuesta relevante recibida (resumida) | Validación o corrección humana aplicada |
|---|---|---|
| **OpenCode:** especificación de una agregación sobre `usuario_anon` (usuarios por rol y mes de alta) y pedido de la consulta equivalente sobre `usuario`. Sin datos reales | Devolvió la misma consulta dos veces. La primera citó `sql/verificacion_equivalencia.sql:13-16`, es decir que **leyó el archivo del repo y no la derivó de la especificación**; la segunda no citó nada | No tomé las respuestas como prueba de corrección: ejecuté ambas consultas en `copia_u5` y comparé. Los conteos y la diferencia `EXCEPT` en los dos sentidos dieron 0 filas (`docs/verificacion_equivalencia.md`) |
| **Mariano:** control adicional tras ver que todos los usuarios se cargaron el mismo mes | — | Agrupación por rol, `eliminado` y día de alta: coincide. Se documentó el límite: la comprobación por mes es poco exigente, y `usuario_anon` solo es equivalente para agregados sobre `rol`, `eliminado` y `created_at` |
| **Facundo · Gemini (no OpenCode):** prompt "Paquete B" (`bitacora_Facundo.md`) que pedía generar `usuario_anon.sql`, `verificacion_equivalencia.md` e `informe_incidente.md`, e **incluía en el propio prompt los resultados esperados** (ADMIN = 1, USUARIO = 20005, periodo 2026-10) y el contenido de la decisión de contención. Sin datos reales | Generó los informes. En `verificacion_equivalencia.md` afirmó que ambas consultas "fueron ejecutadas contra `copia_u5`" y dieron esos conteos | Esa afirmación no tenía sustento: Gemini no ejecuta nada y los números venían del prompt, no de una corrida. El equipo reemplazó esa versión (commit `97f6d12`) por la de Mariano (commit `cfb577e`), que ejecuta ambas consultas en `copia_u5` y compara con `EXCEPT` en los dos sentidos |

## Parte E — Cierre

### Caso más significativo de error o imprecisión de la IA

La primera especificación que generó Kiro para `roles.sql`. Parecía correcta (cumplía las restricciones de seguridad que se le
pidieron) pero su orden de ejecución, de haberse corrido, habría causado daño: la limpieza con `DROP OWNED BY admin_datos`
borraba todas las tablas, que pasaron a ese dueño; las funciones `SECURITY DEFINER` quedaban a nombre de `postgres` y se
ejecutaban con privilegios de superusuario; y se otorgaban permisos sobre funciones que todavía no existían. Se detectó leyendo
el script línea por línea en el orden en que se ejecutaría, comprobando para cada sentencia que el objeto ya existiera, y
verificando después nombres y firmas contra `objects.sql` y `views.sql`. Kiro necesitó tres rondas de corrección y todavía
dejó fallas que solo aparecieron al leer de nuevo y al ejecutar. Dos hallazgos posteriores reforzaron la lección: el ensayo con
`ROLLBACK` no reemplaza a la ejecución real (T23 mostró un filtro que no estaba aplicado en la base), y una prueba puede estar
mal escrita aunque venga de una IA (T22).

### Nota sobre el historial de Git

El historial tiene 17 commits antes de los de cierre de la Parte E y refleja el avance por partes, pero con calidad despareja:

- **Bien:** la rama de Andrés trae un commit por entregable con mensajes `feat(auditoria): …` y `feat(simulacro): …`, y los
  merges entraron por Pull Request (#1 y #2).
- **Mal:** varios commits de Mariano tienen mensajes que no dicen qué se hizo ni por qué (`arreglos.`, `ultimos cambios`,
  `mas cambios..`), y el último de la Parte B salió con el prefijo `eat(auditoria)` en lugar de `feat(auditoria)`. El commit `arreglos criticos` junta en uno solo la reescritura de la Parte C (informe, respuesta de OpenCode,
  log y criterio de anonimización) y de la Parte D (tabla, consultas y verificación), que debieron ser commits separados.
  Los commits de Mariano (Parte A y Parte C.1–C.2) están directo sobre `main`: en el remoto no hay una rama propia suya, como indicaba `docs/division_de_trabajo.md`.
- **Qué se haría distinto:** un commit por entregable con mensaje que explique el motivo, rama por integrante también para
  Mariano, y no reescribir archivos de otra persona en un commit genérico: separar cada reescritura en su propio commit, indicando
  qué versión reemplaza y por qué.
