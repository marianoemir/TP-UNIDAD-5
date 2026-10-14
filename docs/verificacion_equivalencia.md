# Verificación de equivalencia — Parte D

Base: `copia_u5` (PostgreSQL 17) · Ejecutado como `postgres` · Fecha: 2026-10-14
Scripts: `sql/usuario_anon.sql` (crea la tabla) y `sql/verificacion_equivalencia.sql` (las consultas).

## 1. La tabla `usuario_anon`

`usuario_anon` se crea con `sql/usuario_anon.sql` a partir de `usuario`, con valores sintéticos **deterministas**
(se derivan del `id`: el mismo `id` produce siempre el mismo valor), según el patrón visto en clase:

| Columna | Valor en `usuario_anon` |
|---|---|
| `nombre`, `apellido` | `'Usuario ' \|\| id`, `'Apellido ' \|\| id` |
| `mail` | `'usuario' \|\| id \|\| '@ejemplo.test'` |
| `celular` | `NULL` |
| `contrasena` | `'hash_no_valido'` (no se copia ningún hash real) |
| `rol`, `eliminado`, `created_at` | Se conservan, porque alcanzan para análisis agregados |

Comprobación de filas (consulta final de `usuario_anon.sql`):

```
filas_usuario  filas_usuario_anon
20006          20006
```

## 2. Las dos consultas

**Especificación dada a OpenCode** (sin ningún dato real): una agregación sobre `usuario_anon` que cuente usuarios
por rol y por mes de alta, y pedir la consulta equivalente sobre la tabla real `usuario`.

Consulta sobre `usuario_anon`:

```sql
SELECT rol, date_trunc('month', created_at)::date AS mes_alta, COUNT(*) AS usuarios
FROM   usuario_anon
GROUP  BY rol, date_trunc('month', created_at)
ORDER  BY mes_alta, rol;
```

Consulta equivalente sobre `usuario`, devuelta por OpenCode (idéntica salvo el `FROM`):

```sql
SELECT rol, date_trunc('month', created_at)::date AS mes_alta, COUNT(*) AS usuarios
FROM   usuario
GROUP  BY rol, date_trunc('month', created_at)
ORDER  BY mes_alta, rol;
```

OpenCode respondió **dos veces** a este pedido, y las dos con la misma consulta:

1. **Primera respuesta:** citó `sql/verificacion_equivalencia.sql:13-16`, es decir que leyó la consulta del archivo
   del repositorio (donde ya estaba escrita) y no la derivó solo de la especificación.
2. **Segunda respuesta:** devolvió la misma consulta sin citar ningún archivo.

La consulta es correcta en ambos casos, y la prueba de que lo es no son esas respuestas sino la comparación de
resultados de la sección 3.

## 3. Resultados

Las consultas se ejecutaron localmente. A la IA se le dio la especificación y ella devolvió la consulta; **los datos
reales no se pegaron en ninguna conversación con la IA**.

**Sobre `usuario_anon`:**

```
"ADMIN"    "2026-10-01"  1
"USUARIO"  "2026-10-01"  20005
```

**Sobre `usuario`:**

```
"ADMIN"    "2026-10-01"  1
"USUARIO"  "2026-10-01"  20005
```

**Lado a lado** (una sola consulta con `FULL JOIN`):

```
rol        mes_alta      usuarios_real  usuarios_anon  coincide
"ADMIN"    "2026-10-01"  1              1              true
"USUARIO"  "2026-10-01"  20005          20005          true
```

**Diferencia en los dos sentidos** (`EXCEPT`, `usuario_anon` menos `usuario` y `usuario` menos `usuario_anon`):
ambas devolvieron **0 filas**.

### Control adicional

Todos los usuarios se cargaron el mismo mes, así que agrupar por mes casi no exige nada. Se repitió la comparación
agrupando también por `eliminado` y por día de alta:

```
rol        eliminado  dia           usuarios_real  usuarios_anon  coincide
"ADMIN"    false      "2026-10-10"  1              1              true
"USUARIO"  false      "2026-10-10"  20004          20004          true
"USUARIO"  true       "2026-10-10"  1              1              true
```

## 4. Conclusión y límites

Los conteos, los agrupamientos y la diferencia en ambos sentidos coinciden: la anonimización **no distorsiona los
agregados** por rol, mes de alta, día de alta y estado `eliminado`.

Límites de lo que se demostró:
- Todos los usuarios tienen la misma fecha de alta (la carga se hizo en un solo día), por lo que la comprobación
  por mes y por día es poco exigente.
- `usuario_anon` **no** sirve para consultas que dependan de los datos reemplazados, como el dominio del mail o
  la longitud del nombre. Solo es equivalente para agregados sobre `rol`, `eliminado` y `created_at`.

## 5. Qué información de Food Store no debe llegar a una IA sin anonimizar

Información crítica de Food Store, como nombres, apellidos, correos electrónicos reales, números de teléfono y
hashes de contraseñas, **nunca** debe enviarse a una IA ni exponerse en entornos públicos o de prueba sin un proceso
de anonimización. Tampoco los logs del servidor, porque con `log_statement = 'all'` registran las sentencias con
sus mails y claves en texto plano. La exposición de estos datos vulnera la privacidad de los usuarios y expone
credenciales o canales de contacto directos ante una brecha de seguridad.
