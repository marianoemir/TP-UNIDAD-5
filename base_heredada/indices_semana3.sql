-- ============================================================
-- FOOD STORE — indices_semana3.sql
-- Índices creados y medidos en el TP3 (Semana 3), que este TP4
-- da por existentes según los "Requisitos previos".
-- Correr DESPUÉS de carga_masiva.sql sobre copia_trabajo.
-- No olvidar ANALYZE después de crearlos.
-- ============================================================

-- Consulta 1 del TP3: Historial de pedidos por rango de fechas y estado
-- Aceptado: Seq Scan -> Bitmap Heap Scan (~2.1x más rápido)
CREATE INDEX idx_pedido_fecha_estado_vigente
ON pedido(fecha, estado)
WHERE eliminado = FALSE;

-- Consulta 3 del TP3: Ranking de clientes por total gastado
-- Aceptado: Seq Scan -> Index Only Scan, Heap Fetches: 0 (~1.7x más rápido)
CREATE INDEX idx_pedido_usuario_total_estado
ON pedido(usuario_id, total)
WHERE eliminado = FALSE AND estado IN ('CONFIRMADO', 'TERMINADO');

-- Nota: el índice idx_producto_categoria_precio_vigente (Consulta 2 del TP3)
-- NO se recrea acá porque fue descartado — el optimizador lo ignoró y no
-- produjo ninguna mejora medible (ver Tabla_de_resultados_seccion_2.2.md del TP3).

-- Actualizar estadísticas después de crear los índices
ANALYZE pedido;
