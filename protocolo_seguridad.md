# Protocolo de Seguridad — Food Store

Este documento define los pasos obligatorios que se aplican **siempre**, sin excepción,
antes de que cualquier script (propio o generado por IA) toque la base de datos del proyecto.
Es un protocolo **permanente del proyecto**, no de una entrega puntual: aplica igual a la
entrega ya consolidada (índices, vistas, vista materializada de facturación) y al
Trabajo Práctico en curso (Unidad 4 — FNBC y desnormalización), y a cualquier entrega futura.

> **Nota Unidad 5:** en el TP de la Unidad 5 la base de trabajo es `copia_u5` (creada desde
> `plantilla_food_store`), no `copia_trabajo`. Los pasos de este protocolo aplican igual. Además, los
> roles pertenecen al servidor y sobreviven a `DROP DATABASE`: ver `AGENTS.md`.

## Motor y entorno

- Motor: PostgreSQL
- Base "plantilla" con el esquema y el seed chico ya aplicados: `plantilla_food_store`
- Base de trabajo descartable: `copia_trabajo`

Cada integrante puede crear y administrar estas dos bases con la herramienta que le resulte
más cómoda: **pgAdmin** (interfaz gráfica) o **línea de comandos** (`createdb`/`psql`). Ambas
vías son válidas y equivalentes — lo que importa es respetar el rol de cada base (Paso 1),
no la herramienta usada para crearla.

## Paso 1 — Copia

Nunca se trabaja directamente sobre la base que contiene datos que importan.
Antes de cualquier cambio se crea una copia descartable a partir de la plantilla.
Elegí la vía que uses vos — ambas producen el mismo resultado (un
`CREATE DATABASE ... TEMPLATE plantilla_food_store` de Postgres):

**Vía gráfica (pgAdmin):**
`Create > Database...` → en la pestaña "General" el nombre `copia_trabajo`, y en la
pestaña "Template" elegir `plantilla_food_store`.

**Vía línea de comandos:**
```bash
createdb -T plantilla_food_store copia_trabajo
```

Si la plantilla `plantilla_food_store` todavía no existe, se crea una vez a partir del esquema
(gráfico: `Create > Database...` sin template, y correr los tres scripts desde el Query Tool
de pgAdmin; por comandos:):

```bash
createdb plantilla_food_store
psql -d plantilla_food_store -f "schema.sql"
psql -d plantilla_food_store -f "objects.sql"
psql -d plantilla_food_store -f "data.sql"
```

Todo el trabajo de cualquier entrega (carga masiva, índices, vistas, vista materializada,
tablas nuevas de un TP, disparadores) se ejecuta sobre `copia_trabajo`, nunca sobre
`plantilla_food_store` ni sobre ninguna base con datos reales de producción. Si una
`copia_trabajo` queda en mal estado, se borra y se vuelve a crear desde `plantilla_food_store`
por cualquiera de las dos vías — no hay que rehacer el seed a mano.

## Paso 2 — Transacción

Todo script que escriba datos (INSERT, UPDATE, DELETE, o que agregue
restricciones) se ejecuta primero dentro de una transacción abierta:

```sql
BEGIN;

-- acá va el script generado por la IA o el cambio propio

-- se revisa: cuántas filas afectó, qué mensajes tiró, si el resultado
-- es el esperado

ROLLBACK; -- primero SIEMPRE se revierte para confirmar que se entendió el efecto
```

Recién cuando el efecto fue inspeccionado y es el esperado, se repite la
operación terminando en `COMMIT` en lugar de `ROLLBACK`.

**Nota práctica:** al medir el costo de una carga de escritura (por ejemplo,
varios cientos de `INSERT` en `detalle_pedido` para comparar antes/después de
crear un índice), conviene envolver esa carga de prueba en su propia
transacción con `ROLLBACK` al final, para no dejar datos de prueba
permanentes en `copia_trabajo` que después ensucien otras mediciones.

## Paso 3 — Respaldo

Antes de cualquier cambio estructural se saca un respaldo de la copia de
trabajo, independiente del `ROLLBACK`:

```bash
pg_dump copia_trabajo > copia_trabajo_YYYYMMDD_HHMM.sql
```

**Se considera cambio estructural, y requiere respaldo previo, cualquiera de:**
- `ALTER`, `DROP`
- `CREATE TRIGGER`, `CREATE FUNCTION`
- `CREATE INDEX`
- `CREATE VIEW`
- `CREATE MATERIALIZED VIEW`
- Cualquier migración de datos entre tablas (por ejemplo, al descomponer un
  esquema en tablas nuevas)

Los respaldos se guardan fuera del repo (son pesados y no se versionan), con
fecha y hora en el nombre.

**Recomendación general:** sacar un respaldo separado justo antes de empezar
cada bloque de trabajo que agregue objetos distintos (por ejemplo: antes de
crear índices, antes de crear una vista, antes de crear una vista
materializada, antes de migrar datos a tablas descompuestas de un TP), para
poder volver atrás a un punto intermedio sin perder el trabajo de las demás
partes del equipo.

## Paso 4 — Estadísticas actualizadas antes de medir

Después de crear un índice, correr:

```sql
ANALYZE <tabla>;
```

Sin este paso, el optimizador puede seguir usando estadísticas viejas y el
plan de `EXPLAIN ANALYZE` no refleja el índice recién creado — esto invalida
cualquier comparación "antes/después" de rendimiento.

## Paso 5 — Verificación de equivalencia (vistas)

Para toda vista nueva (simple, materializada, o una vista de compatibilidad
que reconstruye una relación descompuesta, como la del TP de FNBC), antes de
darla por válida:

1. Ejecutar la vista (`SELECT * FROM v_nombre;` o con las columnas que exponga).
2. Ejecutar la consulta manual equivalente, escrita por el propio estudiante.
3. Comparar conteo de filas (`SELECT COUNT(*) FROM tabla_vieja` vs.
   `SELECT COUNT(*) FROM vista`).
4. Comparar contenido idéntico con `EXCEPT` **en los dos sentidos** — esto ya
   no es opcional ("si hace falta"), es obligatorio para toda vista de
   compatibilidad de una descomposición:

```sql
-- Detecta pérdida de datos (algo que estaba y desapareció)
SELECT * FROM tabla_original
EXCEPT
SELECT * FROM vista_compatibilidad;

-- Detecta filas espurias (algo que aparece pero nunca existió:
-- señal de que el JOIN de la descomposición no era sin pérdida)
SELECT * FROM vista_compatibilidad
EXCEPT
SELECT * FROM tabla_original;
```

Ambas consultas deben devolver **0 filas**. Un solo `EXCEPT` no alcanza: cada
dirección detecta un error distinto, y pasar solo una no descarta el otro.

Este paso se aplica siempre a partir de esta versión del protocolo — las
vistas ya existentes (`v_productos_vigentes`, `v_pedidos_resumen`,
`v_pedido_detalle`) no habían pasado por esta verificación formal cuando se
crearon, pero cualquier vista nueva sí debe pasar por acá, sin excepción.

## Paso 6 — Migraciones estructurales: expandir, migrar, verificar, contraer

Para cualquier cambio que reestructure tablas ya en uso (una descomposición
por FNBC, un renombre, un split de columnas), no se aplica el cambio de una
vez: se hace en cuatro etapas, con el esquema viejo y el nuevo conviviendo
hasta que el nuevo esté verificado.

1. **Expandir** — crear las tablas nuevas sin tocar nada de lo viejo. El
   sistema sigue funcionando exactamente igual que antes.
2. **Migrar** — copiar los datos a las tablas nuevas, sin borrar el origen
   (`INSERT INTO nueva SELECT ... FROM vieja`, nunca `DELETE`/`DROP` en este
   paso). Si la migración falla por una restricción (por ejemplo, una clave
   duplicada), **eso es información**: revela que una dependencia funcional
   asumida no se cumple en los datos reales. Se resuelve con el negocio antes
   de seguir, nunca forzando el script para que "pase".
3. **Verificar** — conteo de filas + los dos `EXCEPT` del Paso 5, antes de
   confirmar nada.
4. **Contraer** — recién cuando la verificación cerró, y preferentemente en
   una migración posterior (no en la misma sesión), se elimina la tabla vieja
   o la columna que quedó redundante.

Todo cambio de este tipo se entrega con dos archivos, no uno:

- **`up.sql`**: los pasos 1 a 3 (expandir, migrar, verificar), dentro de
  `BEGIN...COMMIT`.
- **`down.sql`**: el procedimiento inverso completo (recrear la tabla vieja
  si se llegó a contraer, o simplemente `DROP` de lo nuevo si no), también
  dentro de `BEGIN...COMMIT`.

**Regla dura:** un `up.sql` sin su `down.sql` probado no se considera
terminado. Se prueba ejecutando `up.sql`, después `down.sql`, y verificando
que la base quedó exactamente como estaba antes de empezar — si el `down.sql`
no se probó así, no cuenta como existente.

## Paso 7 — Los cuatro requisitos de una desnormalización controlada

Antes de dar por válida cualquier redundancia introducida a propósito
(`tp_desnormalizacion_top_categorias.sql`, o cualquier columna precalculada
futura), las cuatro condiciones siguientes tienen que estar explícitamente
cubiertas — si falta una sola, no es una desnormalización controlada, es el
mismo problema de un esquema heredado sin disciplina:

1. **Motivo medido.** No alcanza con "puede ser lento": tiene que existir una
   medición con `EXPLAIN ANALYZE`, antes y después, con el número concreto.
2. **Un único dueño del dato.** Exactamente un mecanismo escribe el dato
   redundante (un trigger, o el `REFRESH` de una vista materializada — nunca
   los dos a la vez, ni dos triggers distintos sobre el mismo valor). Si dos
   caminos pueden escribirlo, el dato ya está roto en potencia.
3. **Una consulta de conciliación.** Que compare el valor redundante contra
   el valor recalculado desde la fuente de verdad, ejecutable en cualquier
   momento, y cuyo resultado esperado sea vacío.
4. **Documentado y reversible.** Escrito en el informe (qué patrón se eligió
   y por qué) y con un procedimiento concreto para revertirlo sin pérdida de
   información (eliminar la columna o la vista materializada, dado que la
   fuente de verdad normalizada sigue intacta).

Una propuesta de desnormalización que no pueda responder estas cuatro cosas
con precisión no se entrega — no importa que el SQL compile.

**Distinción que no hay que confundir (dato histórico vs. dato redundante):**
antes de proponer eliminar o "limpiar" una columna por parecer duplicada de
otra, preguntarse: *si la borro, ¿puedo reconstruir el valor exacto a partir
del resto de la base?* Si sí, es redundancia (candidata a esto). Si no —por
ejemplo, `detalle_pedido.precio_unitario`, que es el precio al momento de la
venta y no se recalcula nunca aunque `producto.precio` cambie después— es un
dato histórico y no se toca. Este es un error típico de una sugerencia
generada por IA: presentar un dato histórico como si fuera redundancia
duplicada.

## Regla de fondo

Ningún script generado por OpenCode o Kiro se ejecuta directamente sobre la base. El flujo
siempre es:

1. Especificar primero en Kiro (spec guardada en `specs/`, con la plantilla
   de la sección "Plantilla de spec" más abajo).
2. Generar con OpenCode a partir de esa spec.
3. Leer línea por línea antes de aplicar.
4. Probar dentro de `BEGIN...ROLLBACK` sobre `copia_trabajo`.
5. Si el cambio es estructural (índice, vista, vista materializada, o una
   migración de tablas), sacar respaldo antes del `COMMIT` final (Paso 3). Si
   además reestructura tablas ya en uso, seguir el patrón expandir-migrar-
   verificar-contraer del Paso 6, con su `up.sql`/`down.sql`.
6. Si el cambio afecta índices, correr `ANALYZE` antes de medir (Paso 4).
7. Si el cambio es una vista, verificar equivalencia con conteo + los dos
   `EXCEPT` (Paso 5) antes de darla por válida.
8. Si el cambio introduce una redundancia deliberada, confirmar los cuatro
   requisitos del Paso 7 antes de entregarlo.
9. Recién ahí `COMMIT` y commit en Git — separado y descriptivo por cada
   pieza (índice, vista, vista materializada, o migración).

Ningún paso de esta lista se salta, incluso cuando el cambio parece trivial.

## Plantilla de spec (para `specs/`, antes de generar con OpenCode)

Toda spec que se le pase a OpenCode para generar una migración o una
refactorización sigue esta estructura — una spec pobre produce una migración
pobre, aunque el SQL resultante compile:

```markdown
# Spec: refactorización <nombre>

## 1. Contexto
Tabla(s) afectadas, volumen aproximado de filas, quién las consulta hoy.

## 2. Reglas de negocio (confirmadas con: ______)
- R1: <en castellano> → <notación formal X → Y>
- R2: ...
Evidencia en los datos: <consulta de verificación (GROUP BY ... HAVING
COUNT(DISTINCT y) > 1) + resultado>

## 3. Diagnóstico
Claves candidatas: ...
Forma normal actual: ... porque la dependencia <Fn> tiene determinante
no superclave / dependencia multivaluada con determinante no superclave.

## 4. Esquema objetivo
DDL de las tablas resultantes + vista de compatibilidad.

## 5. Plan de migración (expandir–migrar–verificar–contraer)
Paso a paso, en orden, indicando qué paso es reversible sin pérdida.

## 6. Criterios de aceptación
- [ ] COUNT(*) coincide antes y después
- [ ] Los dos EXCEPT devuelven 0 filas
- [ ] Todas las consultas existentes siguen funcionando (vista de
      compatibilidad)
- [ ] down.sql ejecutado y verificado: la base vuelve al estado inicial

## 7. Plan de reversión
Contenido de down.sql y qué se pierde si se revierte después de que ya se
escribieron datos nuevos con el esquema nuevo.

## 8. Riesgos
Qué puede salir mal y cómo se detecta.
```

**Nota:** la evidencia de una consulta que devuelve 0 filas en la sección 2
**no prueba** que la dependencia funcional exista — solo prueba que se
cumple en los datos de hoy. La dependencia la confirma el negocio (o, en
este proyecto, el enunciado del TP), nunca solamente el resultado de una
consulta.

## Aplicación al TP en curso (Unidad 4 — FNBC y Desnormalización)

Este protocolo aplica igual a los dos artefactos nuevos de ese TP:

- **`tp_fnbc_control_lote.sql`**: la creación de `lote`, `deposito`,
  `control_lote_almacen` y las tablas descompuestas son cambios estructurales
  (Paso 3, respaldo previo). Como esto es una descomposición sobre un esquema
  con datos ya cargados (la instancia de ejemplo), sigue el patrón completo
  del Paso 6 (expandir–migrar–verificar–contraer, con `up.sql`/`down.sql`
  probado). La vista de compatibilidad que reconstruye la relación original
  mediante `JOIN` pasa por la verificación del Paso 5: conteo de filas **y
  los dos `EXCEPT`**, no solo uno.
- **`tp_desnormalizacion_top_categorias.sql`**: correr sobre `copia_trabajo`
  ya cargada con `carga_masiva.sql` (para que el `EXPLAIN ANALYZE` tenga
  volumen real que medir). Antes de dar por válido el patrón elegido, tiene
  que cumplir los cuatro requisitos del Paso 7 (motivo medido, único dueño
  del dato, consulta de conciliación, documentado y reversible). Si el patrón
  elegido es una vista materializada, requiere respaldo previo (Paso 3) y, si
  agrega un índice de apoyo, `ANALYZE` antes de medir (Paso 4). Si el patrón
  elegido es columna + trigger, el `CREATE TRIGGER`/`CREATE FUNCTION` también
  requiere respaldo previo (Paso 3) — y ese trigger debe ser el **único**
  mecanismo que escribe la columna redundante (requisito 2 del Paso 7). El
  script de auditoría de desincronización se prueba primero dentro de
  `BEGIN...ROLLBACK` sobre un caso simulado antes de confiar en que detecta
  el problema real.
