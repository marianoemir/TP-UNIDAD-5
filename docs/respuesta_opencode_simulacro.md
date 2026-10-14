# Respuesta de OpenCode — Parte C.4 (segunda corrida, log sin encabezado)

Prompt: "Analiza el siguiente log anonimizado de PostgreSQL. Reconstruye qué ocurrió paso por paso y propón
una hipótesis de contención. No tienes más contexto que el log."

Entrada: `docs/log_simulacro_anonimizado.txt` (70 líneas, sin encabezado), en una sesión nueva de OpenCode abierta
sobre una carpeta que contenía solo ese archivo (fuera del repositorio).

Respuesta completa, sin editar:

---

En `log_simulacro_anonimizado.txt:1-70` hay 5 sesiones `psql`, todas contra `copia_u5`, todas desde `IP_ANONIMIZADA`, en 8 segundos (`08:21:56` a `08:22:04 -03`).

Es un simulacro declarado, no un incidente real. Evidencia: `RAISE NOTICE 'simulacro: ...'`, balizas `SELECT (N = ...) AS pN`, datos sintéticos `usuario.sim.0001@ejemplo.test`, `CLAVE_OK_SINTETICA / CLAVE_ERRONEA_* / CLAVE_SOPORTE_TEST`.

### Reconstrucción paso por paso

**0. Preparación `postgres:54959` (`:7-20`):**
* `postgres` autenticado por `scram-sha-256` crea usuario de prueba en `usuario` con `crypt(...,gen_salt('bf'))`, idempotente via `WHERE NOT EXISTS`.
* Crea `soporte_sim LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE`, idempotente via `format(... ) WHERE NOT EXISTS` + `CREATE / ALTER ROLE`.
* `GRANT rol_soporte TO soporte_sim`. Único `GRANT` exitoso del log.
* Desconexión normal `0:00:00.066`.

**1. Paso 1 - 5 fallidos `app_web:55506` (`:24-36`):**
* Baliza `(1 = ...)`.
* `SELECT * FROM fn_autenticar('usuario.sim.0001@...','CLAVE_ERRONEA_1'..'_5')` con `pg_sleep(1)` entre cada uno.
* Sin `ERROR` a nivel Postgres: la función devuelve fallo lógico, no excepción. Sin fallo de autenticación Postgres — `app_web` ya estaba autenticado.
* Sesión `0:00:04.079`, coherente con 4x `sleep(1)`.

**2. Paso 2 - login exitoso `app_web:51721` (`:40-44`):**
* Baliza `(2 = ...)`.
* `fn_autenticar(...,'CLAVE_OK_SINTETICA')` una vez, sin error, desconexión inmediata `0:00:00.040`.
* Implicancia: tras 5 fallos la cuenta **no se bloqueó** o el umbral es `>5`. El log no muestra el resultado devuelto.

**3. Paso 3 - lectura masiva `soporte_sim:51722` (`:48-52`):**
* Baliza `(3 = ...)`.
* `SELECT id,nombre,apellido,mail,rol,eliminado,created_at FROM usuario ORDER BY id`.
* Lectura completa de tabla, pero **sin** `contrasena, celular`. No hay `COPY`, `pg_dump`, `SELECT pg_sleep` exfiltrante. Volumen de filas no visible en `log_statement=all`.

**4. Paso 4 - escalamiento fallido `soporte_sim:51724` (`:56-70`):**
* `GRANT admin_datos TO soporte_sim` -> `ERROR: denegado, sólo roles con ADMIN` (`:60-62`).
* `SET ROLE admin_datos` -> `ERROR: denegado` (`:64-65`).
* `CREATE ROLE intruso_sim LOGIN` -> `ERROR: sólo CREATEROLE` (`:67-69`).
* Los 3 intentos fallan. No hay persistencia, no hay nuevo rol, no hay cambio de pertenencia. Desconexión normal.

### Hipótesis de contención

**H0 (favorecida): simulacro controlado contenido en `copia_u5`, sin escalamiento ni persistencia.**
Sostienen H0: fallos de privilegio explícitos, rol creado `NOSUPERUSER/NOCREATEDB/NOCREATEROLE`, base llamada `copia_*` (no prod), ventana de 8s, misma IP, desconexiones limpias.

**H1 (alternativa a descartar): si fuera real, sería fuerza bruta exitosa + abuso de rol soporte + intento de escalamiento.**

En ambos casos, contención mínima verificable solo con lo visto:

1. Preservar este log. No rotar/eliminar nada antes de auditar.
2. Neutralizar artefactos del simulacro: `ALTER ROLE soporte_sim NOLOGIN`, `REVOKE rol_soporte FROM soporte_sim`, eliminar `usuario.sim.0001@ejemplo.test`, rotar `CLAVE_SOPORTE_TEST`.
3. Verificar que lo denegado no ocurrió por otra vía: `SELECT * FROM pg_roles WHERE rolname IN ('soporte_sim','intruso_sim')`, `SELECT * FROM information_schema.role_table_grants`, miembros de `admin_datos` y `rol_soporte` sin cambios.
4. Revisar `fn_autenticar`: ¿bloquea tras N fallos? El log sugiere que con 5 no bloquea. Definir umbral + alerta.
5. Revisar `rol_soporte`: ¿realmente necesita `SELECT` full sobre `usuario`? Paso 3 demuestra sobre-permiso de lectura.
6. Confirmar que `IP_ANONIMIZADA` era el operador autorizado y que `postgres` remoto por `psql` está justificado; si no, bloquear en `pg_hba.conf`/firewall.

Lo que el log **no** permite afirmar: filas exfiltradas, resultado de `fn_autenticar`, actividad fuera de `08:21:56-08:22:04`, otras IPs, o si `copia_u5` contiene datos reales.
