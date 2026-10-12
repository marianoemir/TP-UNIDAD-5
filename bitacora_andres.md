# Bitácora de IA — Andrés (Paquete 1: Partes B y C.3–C.4)

## Declaración de herramientas

- **Muse Spark (vía OpenCode)**: guía paso a paso del Paquete 1, borradores de `sql/auditoria_test.sql`, `docs/informe_auditoria.md`, anonimización de `docs/log_simulacro_anonimizado.txt`. Todo ejecutado y verificado por mí en mi `copia_u5` antes de commitear.
- **OpenCode (sesión limpia, C.4)**: reconstrucción del log anonimizado + hipótesis de contención. Respuesta guardada tal cual en `docs/respuesta_opencode_simulacro.md`.
- No se usó otra IA. No se envió a ninguna IA datos personales reales: solo valores sintéticos (`CAT_AUDIT_TEST`, `usuario.sim.0001@ejemplo.test`, `CLAVE_*_TEST`) y el log ya anonimizado.

## Registros

| Prompt enviado a la IA | Respuesta relevante recibida (resumida) | Validación o corrección humana aplicada |
|---|---|---|
| Pedí guía para el Paquete 1 con mi estado (copia_u5 lista, roles.sql corrido, respaldo hecho) | Plan por partes + pedido de los 6 `SHOW` para documentar originales | Ejecuté los `SHOW` en mi servidor: `off/off/none`, colector `on`. Los anoté en el informe; no apliqué nada sin verificar |
| Pedí cómo activar auditoría; al correr los 4 `ALTER SYSTEM` juntos dio `ERROR 25001: no puede ser ejecutado dentro de un bloque de transacción` | Indicación de correrlos de a uno por vez en autocommit (F5 por sentencia) | Lo apliqué: `log_statement` quedó en `all`, pero `log_connections`/`log_disconnections` seguían en `off`. No lo dejé pasar: pedí diagnóstico |
| Diagnóstico de por qué dos parámetros no quedaban (`pg_settings`, `config_file`, `pg_file_settings`, `auto.conf`) | El `auto.conf` sí tenía los 3 (`applied=true`); faltaba recarga efectiva → `pg_reload_conf()` + reconectar, y si no, restart del servicio | Verifiqué `pg_conf_load_time` antes/después y reconecté: quedaron `on/on/all` con source `configuration file`. Recién ahí di por cerrada la B.1 |
| Pedí cómo correr `auditoria_test.sql`; lo pegué como texto (`sql/auditoria_test.sql`) y dio `ERROR 42601` | Aclaración: en pgAdmin se abre con File→Open o se pega el contenido; la ruta no es SQL | Abrí el archivo y lo ejecuté: `NOTICE inicio/fin` + `ROLLBACK` en 46 ms. Confirmé que no dejó basura (`CAT_AUDIT_TEST` dentro de transacción con ROLLBACK) |
| Pedí cómo recortar el log (líneas con `auditoria_test`, luego rango 7275..7345) | El bloque pgAdmin llega como una sola `sentencia:` con todo el script (no una línea LOG por sentencia) | Lo acepté y lo documenté en el informe punto 3 (con `psql -f` quedaría separado). Guardé solo el recorte inicio→fin en `docs/log_auditoria_prueba.txt`, sin ruido `pga4dash` |
| Ejecución del simulacro: `.\sql\simulacro_incidente.ps1` dio error de `-File no existe` | Era el cwd (`C:\WINDOWS\system32`); solución con `Set-Location` al repo o ruta absoluta | Reejecuté desde el repo: pasos 0–4 OK (5 fallidos, 1 éxito, 20007 filas, 3/3 escalamientos denegados). Restauré `docs/constancia_escalamiento.txt` de Mariano con `git checkout` para no pisar su entregable |
| Recorte del log del simulacro (marcas `simulacro:` líneas 8085–8148, rango 8070..8170) | Bloque completo con conexiones, sentencias, 3 `ERROR` y desconexiones | Anonimicé antes de versionar: mail→`usuario.sim.0001@ejemplo.test`, nombres→`Usuario/Simulado`, celular→`2000000000`, claves→`CLAVE_*_TEST/SINTETICA`, `host=::1`→`IP_ANONIMIZADA`; excluí ruido `pga4dash`. Guardado en `docs/log_simulacro_anonimizado.txt` |
| Sesión limpia OpenCode con solo el log anonimizado (prompt fijo, sin contexto del TP) | Reconstrucción en 5 sesiones con timestamps, patrón fuerza bruta + éxito + lectura masiva + 3 denegaciones; hallazgo de claves en claro por `log_statement='all'`; contención proporcional (congelar `soporte_sim` con `NOLOGIN`, revocar, rotar secretos, verificar `fn_autenticar`/`rol_soporte`) | Guardé la respuesta **completa sin editar** en `docs/respuesta_opencode_simulacro.md`. No ejecuté nada de lo propuesto (la contención la decide el equipo en C.6, Paquete 2). El contraste qué acertó/omitió lo hace el Paquete 2 contra `sql/simulacro_incidente.sql` |

## Caso de IA incorrecta / insegura / de más

No hubo propuesta de `GRANT ALL` ni permiso de más en este paquete. El caso más significativo fue el diagnóstico de los dos parámetros que no quedaban: mi primera hipótesis habría sido repetir los `ALTER SYSTEM` sin más, pero la tabla `pg_file_settings` + el contenido del `auto.conf` mostraron que el archivo estaba bien (`applied=true`) y que el problema era la recarga/visibilidad en la sesión (`pg_conf_load_time` + reconnect). Sin esa verificación habría dejado el informe con valores inconsistentes (`off` en `pg_settings` vs `on` en disco).

## Nota sobre el historial de Git (Parte E, punto 3)

Trabajo en rama `Andrés`, un commit por entregable con mensajes `feat(...)`: Parte B (auditoría), C.3 (log anonimizado), C.4 (respuesta OpenCode) y bitácora. Un commit inicial quedó con autor provisorio y lo corregí con `git commit --amend --author` a mi usuario real antes de pushear.
