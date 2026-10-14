# Informe de auditoría — Parte B

## 1. Parámetros modificados

Valores originales verificados el 2026-10-14 con `SELECT name, setting, source FROM pg_settings` en el servidor donde se
capturó la evidencia final. Coinciden con los que Andrés había verificado el 2026-10-12 en el suyo.

| Parámetro | Valor original | Valor configurado | Cómo se aplicó |
|---|---|---|---|
| `log_connections` | `off` (source `default`) | `on` | `ALTER SYSTEM SET log_connections = 'on';` |
| `log_disconnections` | `off` (source `default`) | `on` | `ALTER SYSTEM SET log_disconnections = 'on';` |
| `log_statement` | `none` (source `default`) | `all` | `ALTER SYSTEM SET log_statement = 'all';` |

`logging_collector` ya estaba en `on` (source `configuration file`), así que el servidor escribe el log en archivos de
`C:\Program Files\PostgreSQL\17\data\log\`. Después de los cambios, `pg_settings` mostró los tres parámetros con source
`configuration file`.

Aplicación y verificación (cada `ALTER SYSTEM` en autocommit, uno por vez):

```sql
-- Ver valores originales (antes de cambiar):
SELECT name, setting, source FROM pg_settings
WHERE name IN ('log_connections','log_disconnections','log_statement','logging_collector');

-- Cambiar:
ALTER SYSTEM SET log_connections = 'on';
ALTER SYSTEM SET log_disconnections = 'on';
ALTER SYSTEM SET log_statement = 'all';
SELECT pg_reload_conf();

-- Verificar (desde una conexión nueva):
SELECT name, setting, source FROM pg_settings
WHERE name IN ('log_connections','log_disconnections','log_statement');
```

Nota: la consigna pide como mínimo un nivel que registre modificaciones (`mod`), pero para el simulacro de la Parte C hace
falta **`all`**: con `mod` no se registran los `SELECT` (intentos de `fn_autenticar`, lectura masiva de `usuario`). Por eso
se deja en `all` desde la Parte B.

Para volver atrás:

```sql
ALTER SYSTEM RESET log_connections;
ALTER SYSTEM RESET log_disconnections;
ALTER SYSTEM RESET log_statement;
SELECT pg_reload_conf();
```

## 2. Secuencia de prueba

Script: `sql/auditoria_test.ps1`. Corre `sql/auditoria_test.sql` con `psql -f`, de modo que cada sentencia llega al
servidor por separado y queda en su propia línea del log. La secuencia es una lectura (`SELECT … v_productos_vigentes`), una
inserción, una actualización y una llamada a `fn_autenticar` con un mail inexistente, todo dentro de una transacción con
`ROLLBACK`. Después el script intenta conectarse como `app_web` con una contraseña incorrecta. Antes y después emite las marcas
`auditoria_b: inicio` y `auditoria_b: fin`.

Fragmento de log: `docs/log_auditoria_prueba.txt`, recortado entre esas dos marcas (ejecución del 2026-10-14, 20:55:26).
Reemplaza a una captura anterior hecha desde pgAdmin, donde todo el script llegaba como una única sentencia y no había
ningún rechazo de conexión.

## 3. Lectura del fragmento (punto 3)

- **Quién:** las líneas `conexión autorizada: usuario=postgres base_de_datos=copia_u5 nombre_de_aplicación=psql` y
  `desconexión: … usuario=postgres base=copia_u5` identifican al login del motor y a la base. En el intento rechazado, el
  `FATAL` nombra al usuario `app_web`.
- **Qué:** cada sentencia aparece completa en una línea `sentencia:`: el `SELECT`, el `INSERT`, el `UPDATE`, la llamada a
  `fn_autenticar` y también `BEGIN` y `ROLLBACK`.
- **Cuándo:** el sello de fecha y hora al comienzo de cada línea (`2026-10-14 20:55:26 -03`), con precisión de segundos. Las
  líneas de desconexión agregan la duración de la sesión (por ejemplo `0:00:00.126` para la sesión de la prueba).
- **Desde dónde:** `conexión recibida: host=::1 port=46715` da la dirección y el puerto de origen (aquí, la propia máquina
  por IPv6 local). La línea `conexión autenticada` agrega el método (`scram-sha-256`) y la línea de `pg_hba.conf` que se aplicó.

Hay **dos clases de login fallido**, y el log las muestra distinto:

- `fn_autenticar` con credenciales incorrectas: solo deja la sentencia (`sentencia: SELECT * FROM fn_autenticar(…)`). El
  log no dice si devolvió 0 filas ni si falló, así que no se distingue de uno exitoso sin otra información.
- Conexión con contraseña incorrecta: deja `conexión recibida`, un `FATAL: la autentificación password falló para el usuario
  «app_web»` y un `DETALLE` con la regla de `pg_hba.conf` aplicada. No hay línea `conexión autenticada` ni `desconexión`
  para ese intento.

Qué queda **fuera** del alcance de este mecanismo nativo (nociones):

- **No hay detalle fila por fila**, solo el texto SQL. Ese nivel lo daría la extensión `pgaudit`, con granularidad por rol y
  clase de sentencia, e incluso para operaciones anidadas dentro de funciones y procedimientos.
- **Las líneas `sentencia:` no traen usuario, base ni identificador de sesión.** En este servidor el prefijo de cada línea
  tiene solo fecha y hora, así que para saber quién ejecutó una sentencia hay que seguir el orden respecto de las líneas de
  conexión. Con muchas sesiones simultáneas eso se vuelve ambiguo. Un prefijo más completo (`log_line_prefix`) con proceso,
  usuario y base lo resolvería.
- **Registra la intención, no el resultado.** El `INSERT` y el `UPDATE` aparecen en el log aunque el script terminó con
  `ROLLBACK`: nada de eso quedó en la base. El log tampoco informa cuántas filas se afectaron ni qué devolvió una consulta.
- No identifica al usuario de la aplicación (solo al login del motor), y con `log_statement = 'all'` captura también
  literales sensibles, como el mail y la clave de prueba pasados a `fn_autenticar`.

## 4. El log como activo sensible (punto 4)

Sí: el archivo de log es en sí mismo un activo sensible, porque concentra quién se conectó, desde dónde, qué sentencias ejecutó y cuándo, y con `log_statement = 'all'` incluye además mails y claves de prueba en texto plano. Los permisos de lectura de ese archivo los define el sistema operativo y no el motor: solo deberían poder leerlo la cuenta de servicio de PostgreSQL y los administradores del equipo. El rol `admin_datos` no tiene acceso a archivos del servidor (desde SQL solo pueden leerlos los superusuarios o los roles con `pg_read_server_files`), y un fragmento no se versiona ni se comparte sin anonimizarlo antes.
