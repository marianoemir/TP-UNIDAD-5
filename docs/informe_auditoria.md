# Informe de auditoría — Parte B (Paquete 1)

## 1. Parámetros modificados

Valores originales verificados el 2026-10-12 con `SELECT name, setting FROM pg_settings`.

| Parámetro | Valor original | Valor configurado | Cómo se aplicó |
|---|---|---|---|
| `log_connections` | `off` | `on` | `ALTER SYSTEM SET log_connections = 'on';` |
| `log_disconnections` | `off` | `on` | `ALTER SYSTEM SET log_disconnections = 'on';` |
| `log_statement` | `none` | `all` | `ALTER SYSTEM SET log_statement = 'all';` |

Aplicación y verificación:

```sql
-- Ver valores originales (antes de cambiar):
SHOW log_connections;
SHOW log_disconnections;
SHOW log_statement;

-- Cambiar (en autocommit, NO dentro de BEGIN…ROLLBACK):
ALTER SYSTEM SET log_connections = 'on';
ALTER SYSTEM SET log_disconnections = 'on';
ALTER SYSTEM SET log_statement = 'all';
SELECT pg_reload_conf();

-- Verificar:
SHOW log_connections;
SHOW log_disconnections;
SHOW log_statement;
```

Nota: la consigna pide como mínimo un nivel que registre modificaciones (`mod`),
pero para el simulacro de la Parte C hace falta **`all`**: con `mod` no se
registran los `SELECT` (intentos de `fn_autenticar`, lectura masiva de `usuario`).
Por eso se deja en `all` desde la Parte B.

Ubicación del log (valores de referencia del servidor):

- `logging_collector` = `on`
- `log_directory` = `log`
- `log_filename` = `postgresql-%Y-%m-%d_%H%M%S.log`
- Ruta completa del archivo usado = `C:\Program Files\PostgreSQL\17\data\log\` + archivo `postgresql-%Y-%m-%d_%H%M%S.log` más reciente al 2026-10-12 08:12 (ver `docs/log_auditoria_prueba.txt`)

Para volver atrás:

```sql
ALTER SYSTEM RESET log_connections;
ALTER SYSTEM RESET log_disconnections;
ALTER SYSTEM RESET log_statement;
SELECT pg_reload_conf();
```

## 2. Secuencia de prueba

Script: `sql/auditoria_test.sql` (lectura + inserción + actualización + login fallido,
en transacción con `ROLLBACK`).
Fragmento de log: `docs/log_auditoria_prueba.txt` (recorte entre
`auditoria_test: inicio` y `auditoria_test: fin`).

## 3. Lectura del fragmento (punto 3)

Sobre `docs/log_auditoria_prueba.txt` (2026-10-12 08:12:02 -03):

- **Quién:** el login del motor que ejecutó el script (sesión de pgAdmin como superusuario; en el simulacro se verá `user=app_web` y `user=soporte_sim` en las líneas de `connection authorized`).
- **Qué:** el texto completo de la sentencia (`sentencia: SELECT * FROM v_productos_vigentes…`, `INSERT INTO categoria…`, `UPDATE categoria…`, `SELECT * FROM fn_autenticar…`). Se distinguen la lectura, la inserción, la actualización y el login fallido (0 filas, sin error).
- **Cuándo:** el timestamp al inicio de la línea (`2026-10-12 08:12:02 -03`).
- **Desde dónde:** las líneas de `connection received: host=… port=…` y `connection authorized: user=… database=copia_u5` que aportan `log_connections` / `log_disconnections` (en este recorte pgAdmin reutilizó una sesión ya abierta, por eso el bloque aparece como una sola sentencia; con `psql -f` cada sentencia queda en un `LOG` separado con su timestamp).

Qué queda **fuera** del alcance de este mecanismo nativo (nociones):

- No hay detalle fila por fila (valores antes/después de cada fila, solo el texto SQL). Ese nivel lo daría la extensión `pgaudit`, con granularidad por rol y clase de sentencia e incluso operaciones anidadas dentro de funciones y procedimientos.
- No identifica al usuario de la aplicación, solo al login del motor, y no estructura los parámetros.
- Con `log_statement = 'all'` el log captura también literales sensibles (mails y claves de prueba en `fn_autenticar`), por eso el propio log debe tratarse como sensible y anonimizarse antes de compartirlo.

## 4. El log como activo sensible (punto 4)

Sí, el archivo de log es en sí mismo un activo sensible porque concentra quién se conectó, desde dónde, qué sentencias ejecutó y cuándo, incluyendo lecturas masivas y claves de prueba en texto plano cuando `log_statement` está en `all`. Solo deberían leerlo el DBA (`admin_datos`) y el administrador del SO, con permisos de sistema de archivos restringidos al dueño del servicio postgres y sin versionar ni enviar fragmentos sin anonimizar.
