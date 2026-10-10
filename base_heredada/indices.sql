-- ============================================================
-- FOOD STORE — indices.sql
-- Parte A — Índices aceptados en la entrega de Índices, Vistas
-- y Vistas Materializadas (Unidad 3, Semana 1)
--
-- Se evaluaron 3 consultas candidatas (ver specs/parteA_consulta1.md,
-- parteA_consulta2.md, parteA_consulta3.md e informe_mediciones.md
-- para el detalle completo de cada medición).
--
-- De las 3, se ACEPTÓ 1 y se DESCARTARON 2 (ambas por sobreindexación,
-- con motivos distintos):
--   - Consulta 1 (Top 5 productos vendidos): descartada, sin filtro
--     selectivo, ~100% de las filas participan.
--   - Consulta 2 (Pedidos > promedio): descartada, selectividad 50.05%,
--     mejora insuficiente (~19%, no un orden de magnitud).
--   - Consulta 3 (Búsqueda de productos por nombre): ACEPTADA.
-- ============================================================

-- Consulta 3 — Búsqueda de productos por nombre (case-insensitive)
-- Requiere text_pattern_ops para que el índice soporte LIKE 'prefijo%'
-- (un B-Tree con operator class por defecto no sirve para ese operador
-- salvo en locale C — ver nota en informe_mediciones.md).
-- Mejora medida: 50.191 ms -> 0.222 ms (~226x), Seq Scan -> Bitmap Heap Scan.
CREATE INDEX idx_producto_nombre_lower_vigente
ON producto (lower(nombre) text_pattern_ops)
WHERE eliminado = FALSE;

-- Actualizar estadísticas después de crear el índice
ANALYZE producto;
