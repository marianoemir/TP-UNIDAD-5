# Informe de incidente — Parte C (puntos 5 y 6)

Simulacro de acceso indebido contra `copia_u5`, reconstruido con ayuda de IA y contrastado por el equipo.

> **Autoría:** esta versión reemplaza la anterior de Facundo y fue reescrita por Mariano con ayuda de Claude, con
> la respuesta de OpenCode de la segunda corrida (`docs/respuesta_opencode_simulacro.md`). La decisión de la
> sección 5 es del equipo.

## 1. Qué se ejecutó realmente

Script: `sql/simulacro_incidente.sql` (orquestado por `sql/simulacro_incidente.ps1`). Cada paso se conecta como el
login que corresponde. El log fue capturado en el servidor de Andrés, con `log_statement = 'all'`; la constancia
de resultados es de la ejecución de Mariano (`docs/constancia_escalamiento.txt`).

| Paso | Login | Qué se ejecutó | Resultado real |
|---|---|---|---|
| 0 | `postgres` | Preparación: usuario de prueba con hash real y login `soporte_sim` (miembro de `rol_soporte`) | Sin errores |
| 1 | `app_web` | 5 llamadas a `fn_autenticar` con clave incorrecta, con 1 segundo entre cada una | 5 resultados con **0 filas** |
| 2 | `app_web` | `fn_autenticar` con la clave correcta | **1 fila** |
| 3 | `soporte_sim` | `SELECT id, nombre, apellido, mail, rol, eliminado, created_at FROM usuario` | **20007 filas** leídas |
| 4 | `soporte_sim` | `GRANT admin_datos TO soporte_sim`, `SET ROLE admin_datos`, `CREATE ROLE intruso_sim` | Los **3 fallaron** con permiso denegado |

## 2. Qué respondió la IA

Se le pidió a OpenCode, en una sesión nueva y sin más contexto que el log anonimizado, que reconstruyera lo ocurrido
y propusiera una hipótesis de contención. Hubo **dos corridas**:

- **Primera (`docs/respuesta_opencode_simulacro_v1.md`):** el archivo del log incluía un encabezado con el mapa de
  valores originales y comentarios sobre el criterio. La respuesta usó información que solo estaba en ese encabezado
  (la exclusión de ruido de pgAdmin). Se descartó como evidencia limpia.
- **Segunda (`docs/respuesta_opencode_simulacro.md`):** con el log sin encabezado (70 líneas, en una carpeta vacía).
  Es la que se contrasta acá. Sus referencias de línea (`:7-20`, `:24-36`, `:56-70`) coinciden con ese archivo.

## 3. Contraste entre la IA y lo ejecutado

### Lo que acertó

- Contó **5 sesiones** `psql` contra `copia_u5` en unos 8 segundos (`08:21:56` a `08:22:04`).
- Interpretó bien el paso 1: 5 llamadas a `fn_autenticar` sin error de PostgreSQL, con la duración de la sesión
  (`4,079 s`) coherente con las 4 pausas de 1 segundo.
- Identificó que la lectura masiva pidió solo las columnas permitidas, sin `contrasena` ni `celular`.
- Reconstruyó los **3 intentos de escalamiento** y su causa: falta de la opción `ADMIN` sobre `admin_datos` y falta del
  atributo `CREATEROLE`. Concluyó que no hubo persistencia ni cambio de membresías.
- Señaló que el único `GRANT` exitoso fue el de la preparación.
- Reconoció sus límites: el log no muestra el resultado de las consultas, el volumen de filas ni la actividad fuera
  de esa ventana.

### Lo que omitió

- **No dijo cuántas filas se leyeron (20007), ni que `fn_autenticar` devolvió 0 filas cinco veces y 1 fila al final.**
  No podía saberlo: `log_statement` registra las sentencias, no sus resultados. Lo advirtió a medias.
- **No señaló que el log contiene claves en texto plano**, algo que sí había señalado en la primera corrida.

### Lo que afirmó sin que el log lo sustente

| Afirmación de la IA | Por qué no se sostiene |
|---|---|
| "Sin fallo de autenticación Postgres, `app_web` ya estaba autenticado" | Cada paso abre una conexión nueva, y el propio log muestra la autenticación `scram-sha-256` de `app_web` en cada una (líneas 22 y 38) |
| "Tras 5 fallos la cuenta no se bloqueó o el umbral es mayor que 5" | El log no muestra el resultado de ninguna llamada, así que no permite saber si el inicio de sesión funcionó ni si hubo bloqueo. Además mezcla la cuenta de la aplicación (tabla `usuario`) con el rol de la base. La conclusión coincide con la realidad (`fn_autenticar` no tiene bloqueo), pero no se deduce del log |
| "El paso 3 demuestra sobre-permiso de lectura" | Esas columnas son las que `rol_soporte` tiene por diseño. El log solo muestra el texto de la consulta. Es un juicio de política, no una evidencia |
| "`postgres` remoto por `psql` está justificado" | La conexión era **local**. Al anonimizar el host como `IP_ANONIMIZADA` se perdió ese dato y la IA supuso un acceso remoto |

### Límites del experimento

- La anonimización dejó valores **autodescriptivos** (`CLAVE_OK_SINTETICA`, `CLAVE_ERRONEA_1`, `usuario.sim.0001`).
  Delatan que es un simulacro, y la IA lo usó para favorecer la hipótesis de un ejercicio controlado, en lugar de
  analizar el patrón como si fuera real.
- Reemplazar el host por `IP_ANONIMIZADA` borró que el origen era la propia máquina.

## 4. Qué muestra el incidente

La secuencia (5 intentos fallidos, un inicio de sesión exitoso, una lectura masiva y tres intentos de escalamiento)
es un patrón compatible con un ataque a una credencial. **El esquema de permisos resistió:** los tres intentos
fallaron y no cambió ninguna membresía ni se creó ningún rol. El paso 3 usa un permiso legítimo de `rol_soporte`:
lo anómalo es el patrón completo, no la lectura en sí.

## 5. Decisión de contención del equipo

> **Esta decisión es del equipo y se tomó a partir de la evidencia de las secciones 1, 3 y 4. No es una acción
> ejecutada automáticamente a partir de lo que sugirió la IA.** En el simulacro no se aplicó ninguna de estas
> medidas: describen qué haría el equipo en un caso real.

Medidas que **se adoptan**:

1. **Preservar el log** (copia de solo lectura) antes de cualquier cambio. *(La IA también lo propuso.)*
2. **Verificar que nada cambió por otra vía:** consultar `pg_auth_members`, `pg_roles` y los privilegios para
   confirmar que `admin_datos` y `rol_soporte` no tienen miembros nuevos. *(La IA también lo propuso.)*
3. **Suspender el login que hizo la lectura masiva y los intentos de escalamiento** con `ALTER ROLE <login> NOLOGIN`,
   mientras se revisa si esa actividad estaba autorizada. Es reversible, y se prefiere a borrar el rol.
4. **Forzar el cambio de contraseña de la cuenta de la aplicación atacada**, porque 5 fallos seguidos de un éxito
   pueden indicar una clave adivinada.
5. **Si el origen no está autorizado, bloquearlo** en `pg_hba.conf` o en el firewall. En este caso el origen era local.
6. **Mejoras a mediano plazo:** agregar bloqueo y alerta tras varios intentos fallidos en `fn_autenticar` (hoy no
   existe), alertar sobre lecturas masivas de `usuario`, y proteger el archivo de log (que con `log_statement = 'all'`
   contiene claves en texto plano): permisos del sistema operativo restringidos a la cuenta de servicio de PostgreSQL y
   a los administradores del equipo, y volver a un nivel de registro menos detallado cuando termine la investigación.

Sugerencias de la IA que **se descartan**:

- *Eliminar el usuario de prueba y rotar `CLAVE_SOPORTE_TEST`:* son artefactos del simulacro y valores anonimizados;
  se limpian con `-Limpiar`, no son una medida de contención.
- *Tratar el paso 3 como sobre-permiso de `rol_soporte`:* las columnas están permitidas por diseño (spec de la Parte A).
  Se mantiene el permiso y se agrega la alerta por volumen.
- *Dar por hecho un acceso remoto a bloquear en `pg_hba.conf`:* el origen era local; se bloquearía solo si se
  confirmara que no está autorizado.
