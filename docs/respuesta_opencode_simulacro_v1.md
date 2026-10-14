# Respuesta OpenCode — Parte C.4 (sesión limpia, sin contexto extra)
# Fecha: 2026-10-12
# Prompt usado: "Analiza el siguiente log anonimizado de PostgreSQL. Reconstruye qué ocurrió paso por paso y propón una hipótesis de contención. No tienes más contexto que el log. --- LOG --- (contenido completo de docs/log_simulacro_anonimizado.txt) --- FIN LOG ---"
# Log entregado: docs/log_simulacro_anonimizado.txt
# Nota: respuesta completa, sin editar (consigna Parte C punto 4).

--- RESPUESTA COMPLETA ---

Análisis basado solo en el log 08:21:56 -03 a 08:22:04 -03, base copia_u5, log_statement='all'.
No hay evidencia de compromiso exitoso en este recorte. Lo que hay es una secuencia controlada en 5 sesiones:

1. Reconstrucción paso por paso
08:21:56 - simulacro: preparacion - postgres:

Crea usuario de prueba usuario.sim.0001@ejemplo.test con crypt(gen_salt('bf')), idempotente por WHERE NOT EXISTS.
Crea rol soporte_sim LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD 'CLAVE_SOPORTE_TEST' - idempotente vía pg_roles, luego ALTER ROLE para forzar password.
GRANT rol_soporte TO soporte_sim; - ejecutado por postgres, legítimo dentro de preparación.
Sesión 0.066s. Marcador SELECT (0=0)... es harness del simulacro, no actividad atacante.
08:21:57-08:22:01 - simulacro: paso 1 - intentos fallidos - app_web:

5x SELECT * FROM fn_autenticar('usuario.sim.0001...', 'CLAVE_ERRONEA_N') con pg_sleep(1) entre cada uno.
Sesión 4.079s en un solo puerto 55506.
Patrón compatible con prueba de fuerza bruta / bloqueo por intentos. El log no muestra el resultado de la función, ni tabla de intentos/bloqueo: no se puede afirmar si fn_autenticar bloqueó, contó intentos o solo devolvió falso.
08:22:02 - simulacro: paso 2 - inicio de sesion exitoso - app_web:

1x fn_autenticar(..., 'CLAVE_OK_SINTETICA').
Sesión 0.040s, puerto nuevo 51721. Sin error posterior registrado. Sugiere que tras 5 fallos la clave válida sigue funcionando - a verificar contra política esperada.
08:22:03 - simulacro: paso 3 - lectura masiva de usuario - soporte_sim:

SELECT id, nombre, apellido, mail, rol, eliminado, created_at FROM usuario ORDER BY id;
Relevante: evita contrasena y celular. Aun así es enumeración completa de usuarios. Si rol_soporte lo permite, es funcionamiento esperado, pero en incidente real sería exfiltración potencial.
Sesión 0.201s.
08:22:04 - simulacro: paso 4 - intento de escalamiento - soporte_sim:

GRANT admin_datos TO soporte_sim; -> ERROR: denegado, solo roles con ADMIN en admin_datos.
SET ROLE admin_datos; -> ERROR: denegado.
CREATE ROLE intruso_sim LOGIN; -> ERROR: solo roles con CREATEROLE.
Los 3 bloqueos confirman mínimo privilegio: NOSUPERUSER NOCREATEDB NOCREATEROLE + sin ADMIN OPTION se mantuvieron.
2. Hallazgo transversal
log_statement='all' dejó CLAVE_OK_SINTETICA y CLAVE_SOPORTE_TEST en texto claro en el log, en INSERT, CREATE/ALTER ROLE. El log mismo es ahora material sensible.

3. Hipótesis de contención - solo con este log
Hipótesis: actividad contenida en cuentas de prueba, sin escalamiento logrado. Contención proporcional:

Congelar cuentas de simulacro, no borrar aún: ALTER ROLE soporte_sim NOLOGIN; y bloquear login de usuario.sim.0001@ejemplo.test a nivel app si existe flag eliminado/bloqueo. Preserva evidencia en copia_u5.
Revertir grants de preparación: REVOKE rol_soporte FROM soporte_sim; una vez preservado el log, luego DROP ROLE soporte_sim y borrado del usuario sintético.
Rotar y sacar secretos del log: rotar cualquier password real que haya compartido patrón con CLAVE_*, restringir acceso al archivo de log, bajar log_statement de all a ddl/mod o usar log_min_duration + no loguear argumentos de fn_autenticar.
Verificar lo que el log no muestra: código de fn_autenticar - ¿cuenta/bloquea tras 5 fallos?; definición de rol_soporte - ¿debería poder hacer SELECT masivo?; admin_datos membership - confirmar que nadie tiene ADMIN OPTION indebido.
No asumir alcance: host=IP_ANONIMIZADA, ruido pga4dash excluido y ventana de 8s impiden descartar actividad paralela. Si esto fuera real, preservar pg_authid, pg_stat_statements, logs completos antes de purgar.
Limitación explícita: sin salidas de fn_autenticar, sin pg_hba, sin definición de roles, no se puede concluir si paso 1 debió bloquear paso 2, ni si paso 3 es abuso o uso previsto de soporte.
