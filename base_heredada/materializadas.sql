-- VISTA MATERIALIZADA: mv_facturacion_categoria_mes
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT 
    c.id AS categoria_id,
    c.nombre AS categoria,
    DATE_TRUNC('month', p.fecha)::DATE AS mes,
    COUNT(DISTINCT p.id) AS total_pedidos,
    SUM(dp.cantidad * dp.precio_unitario) AS total_facturado
FROM categoria c
JOIN producto pr ON pr.categoria_id = c.id
JOIN detalle_pedido dp ON dp.producto_id = pr.id
JOIN pedido p ON p.id = dp.pedido_id
WHERE p.estado = 'CONFIRMADO' AND p.eliminado = FALSE
GROUP BY c.id, c.nombre, DATE_TRUNC('month', p.fecha)
ORDER BY mes DESC, total_facturado DESC
WITH DATA;

-- ÍNDICE ÚNICO: idx_mv_facturacion_cat_mes_pk
CREATE UNIQUE INDEX idx_mv_facturacion_cat_mes_pk
ON mv_facturacion_categoria_mes (categoria_id, mes);