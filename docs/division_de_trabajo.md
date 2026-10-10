# División de trabajo — TP Unidad 5 (Food Store)

Equipo de 3 integrantes. Reemplazar los nombres de **Integrante 2** e **Integrante 3** por los reales.

| Sigla | Integrante |
|---|---|
| **M** | Mariano |
| **I2** | Integrante 2 (completar) |
| **I3** | Integrante 3 (completar) |

## 1. Reparto por parte

| Parte | Tramo | Responsable | Archivos |
|---|---|---|---|
| **A** | Completa: spec de Kiro, `roles.sql`, verificación (`pg_roles` / `role_table_grants`), auditoría del script con OpenCode | **M** | `docs/kiro_roles_spec/`, `sql/roles.sql` |
| **B** | Completa: parámetros de auditoría, secuencia de pruebas, log, respuestas de los puntos 3 y 4 | **I2** | `sql/auditoria_test.sql`, `docs/informe_auditoria.md`, `docs/log_auditoria_prueba.txt` |
| **C** | Puntos 1 y 2: script del simulacro y verificación del intento de escalamiento | **M** | `sql/simulacro_incidente.sql` |
| **C** | Punto 3 y 4: ejecutar el simulacro con la auditoría activa, extraer y anonimizar el log, entregárselo a OpenCode (sesión limpia) | **I2** | `docs/log_simulacro_anonimizado.txt` (+ respuesta completa de la IA, guardada tal cual) |
| **C** | Puntos 5 y 6: contraste IA vs. lo ejecutado e informe de contención | **I3** | `docs/informe_incidente.md` |
| **D** | Completa: `usuario_anon`, consultas gemelas, equivalencia, texto sobre qué no sale hacia una IA | **I3** | `sql/usuario_anon.sql`, `docs/verificacion_equivalencia.md` |
| **E** | Consolidación de la bitácora e historial de Git | **Los tres** | `BITACORA.md` |

## 2. Quién depende de quién

| Quien necesita… | …de | Qué necesita | Para qué |
|---|---|---|---|
| **I2** (simulacro) | **M** | `sql/roles.sql` (aunque sea una v0) | Los roles existen en el servidor de I2 para poder correr el simulacro |
| **I2** (simulacro) | **M** | `sql/simulacro_incidente.sql` y la tabla "qué rol ejecuta cada paso" | Ejecutar la secuencia exacta con la auditoría activa |
| **M** (simulacro) | **I2** | Los parámetros de auditoría y sus valores, ya definidos en `informe_auditoria.md` | Que el script de M genere una secuencia legible en el log (login fallido, lectura, etc.) |
| **I3** (contraste e informe) | **I2** | `log_simulacro_anonimizado.txt` y la respuesta completa de OpenCode | Contrastar lo que dijo la IA contra el log |
| **I3** (contraste e informe) | **M** | El script del simulacro y el resultado del intento de escalamiento (¿falló o no?) | Saber qué se ejecutó realmente y si hay un hallazgo |
| **I3** (Parte D) | — | Nada de A, B ni C | Parte independiente: solo necesita `usuario` en `copia_u5` |
| **I2** (Parte B) | — | Nada de A, C ni D | Parte independiente: arranca desde el día uno |
| **M** (Parte A) | — | Nada de B, C ni D | Es la base de los demás |
| **Parte E** | Los tres | Las bitácoras personales de cada uno (`bitacora_m.md`, `bitacora_i2.md`, `bitacora_i3.md`) | Consolidar en `BITACORA.md` |

Resumen de flujo:

```
M  (Parte A: roles.sql) ──► M  (simulacro: script) ──► I2 (ejecuta + log + OpenCode) ──► I3 (contraste + contención)
I2 (Parte B: auditoría) ───────────────────────────────┘
I3 (Parte D)  ── independiente ── (se une en C punto 5 y 6)
```

Si el intento de escalamiento **no falla**, es un hallazgo: **M** corrige `roles.sql`, vuelve a probar y **avisa a I2 e I3** para que repitan lo que dependa de eso.

## 3. Preparación del entorno (cada integrante, en su propio servidor, con pgAdmin 4)

Cada integrante tiene su servidor PostgreSQL local; los roles y `ALTER SYSTEM` son de cada servidor, no del repo.

1. **Crear `plantilla_food_store`** (Create > Database…, sin template) y, desde el Query Tool, correr en este orden:
   `base_heredada/schema.sql` → `objects.sql` → `data.sql`.
   La plantilla **no** recibe `carga_masiva.sql` ni ningún script de la U5.
2. **Desconectar** la base `plantilla_food_store` en pgAdmin (nadie puede estar conectado a una base usada como template).
3. **Crear `copia_u5`** (Create > Database…) y en la pestaña *Definition* elegir `plantilla_food_store` como **Template**.
4. **En `copia_u5`**, correr: `carga_masiva.sql` → `indices_semana3.sql` → `indices.sql` → `views.sql` → `materializadas.sql`.
5. **Respaldar los roles existentes** antes de la Parte A: `pg_dumpall --roles-only > respaldos/roles_AAAAMMDD.sql` (o, como mínimo, guardar el resultado de `SELECT * FROM pg_roles`). `respaldos/` está en `.gitignore`: ese archivo tiene hashes y **nunca se sube**.
6. Recién ahí cada uno arranca con su parte, siempre sobre `copia_u5`.

Notas de pgAdmin 4:
- `\du` solo existe en `psql` (SQL Shell). En el Query Tool, usar `SELECT … FROM pg_roles`.
- `ALTER SYSTEM` no puede correr dentro de una transacción: verificar que el Query Tool esté en modo auto-commit antes de usarlo.

## 4. Orden sugerido

| Fase | M | I2 | I3 |
|---|---|---|---|
| **0** | Entorno (sección 3) | Entorno (sección 3) | Entorno (sección 3) |
| **1** | Spec de Kiro y `roles.sql` v0 → **commit y push** | Parte B completa | Parte D completa |
| **2** | `roles.sql` final + verificación + auditoría con OpenCode; script del simulacro | Corre `roles.sql` y el script de M con la auditoría activa; extrae y anonimiza el log | Termina D y lee el log de I2 |
| **3** | Verifica el escalamiento y corrige si falla | OpenCode en sesión limpia con el log; guarda la respuesta completa | Contraste IA vs. ejecutado e informe de contención |
| **4** | Parte E | Parte E | Parte E |

## 5. Git

- **Una rama por integrante**: `parte-a-roles-simulacro` (M), `parte-b-log` (I2), `parte-c-d-analisis` (I3). Cada uno commitea con su propio usuario.
- **Un commit (o una serie corta) por entregable**, con mensajes que digan qué se hizo y por qué.
- **Todo se mergea a `main` antes de dar una parte por cerrada.**
- `roles.sql` es el archivo que más dependencias tiene: M hace `push` de la v0 apenas esté, para que I2 pueda trabajar.
- Bitácora: cada uno en su archivo personal mientras trabaja; se consolida en `BITACORA.md` en la Parte E. Cada uno registra **al menos un caso real** en que OpenCode propuso algo incorrecto, inseguro o de más.

## 6. Reglas que aplican a los tres

- Todo se ejecuta **solo** contra la propia `copia_u5`.
- Nada con datos personales reales (ni hashes) se envía a OpenCode. `data.sql` contiene datos reales de integrantes: no se pega ni se adjunta.
- Los logs se anonimizan antes de dárselos a la IA **y** antes de commitearlos.
- Todo script generado por IA se lee línea por línea y se prueba en `BEGIN … ROLLBACK` antes de aplicarse.
- La decisión de contención es del equipo; la IA propone, nunca ejecuta.
