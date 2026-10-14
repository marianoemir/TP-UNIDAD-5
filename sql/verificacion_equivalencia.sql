-- ============================================================================
-- verificacion_equivalencia.sql - Parte D: la anonimizacion no distorsiona los agregados
-- Ejecutar en copia_u5, UNA CONSULTA POR VEZ (en pgAdmin solo se muestra la ultima).
-- ============================================================================

-- 1) Agregacion sobre usuario_anon: usuarios por rol y mes de alta.
SELECT rol, date_trunc('month', created_at)::date AS mes_alta, COUNT(*) AS usuarios
FROM   usuario_anon
GROUP  BY rol, date_trunc('month', created_at)
ORDER  BY mes_alta, rol;

-- 2) Consulta equivalente sobre la tabla real usuario.
SELECT rol, date_trunc('month', created_at)::date AS mes_alta, COUNT(*) AS usuarios
FROM   usuario
GROUP  BY rol, date_trunc('month', created_at)
ORDER  BY mes_alta, rol;

-- 3) Resultados LADO A LADO (una sola grilla para adjuntar como evidencia).
WITH r AS (
    SELECT rol, date_trunc('month', created_at)::date AS mes_alta, COUNT(*) AS n
    FROM usuario GROUP BY 1, 2),
a AS (
    SELECT rol, date_trunc('month', created_at)::date AS mes_alta, COUNT(*) AS n
    FROM usuario_anon GROUP BY 1, 2)
SELECT COALESCE(r.rol, a.rol)           AS rol,
       COALESCE(r.mes_alta, a.mes_alta) AS mes_alta,
       r.n                              AS usuarios_real,
       a.n                              AS usuarios_anon,
       (r.n IS NOT DISTINCT FROM a.n)   AS coincide
FROM r FULL JOIN a ON r.rol = a.rol AND r.mes_alta = a.mes_alta
ORDER BY mes_alta, rol;

-- 4) Diferencia en los dos sentidos: ambas tienen que devolver 0 filas.
(SELECT rol, date_trunc('month', created_at) AS mes, COUNT(*) FROM usuario_anon GROUP BY 1, 2)
EXCEPT
(SELECT rol, date_trunc('month', created_at) AS mes, COUNT(*) FROM usuario      GROUP BY 1, 2);

(SELECT rol, date_trunc('month', created_at) AS mes, COUNT(*) FROM usuario      GROUP BY 1, 2)
EXCEPT
(SELECT rol, date_trunc('month', created_at) AS mes, COUNT(*) FROM usuario_anon GROUP BY 1, 2);

-- 5) Control adicional: el agrupamiento por mes es poco exigente si todos los usuarios
--    se cargaron el mismo mes; este agrupa tambien por eliminado y por dia de alta.
WITH r AS (
    SELECT rol, eliminado, created_at::date AS dia, COUNT(*) AS n FROM usuario GROUP BY 1, 2, 3),
a AS (
    SELECT rol, eliminado, created_at::date AS dia, COUNT(*) AS n FROM usuario_anon GROUP BY 1, 2, 3)
SELECT COALESCE(r.rol, a.rol) AS rol, COALESCE(r.eliminado, a.eliminado) AS eliminado,
       COALESCE(r.dia, a.dia) AS dia, r.n AS usuarios_real, a.n AS usuarios_anon,
       (r.n IS NOT DISTINCT FROM a.n) AS coincide
FROM r FULL JOIN a ON r.rol = a.rol AND r.eliminado = a.eliminado AND r.dia = a.dia
ORDER BY dia, rol, eliminado;
