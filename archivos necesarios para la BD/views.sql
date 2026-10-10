-- ============================================================================
-- PARTE B - VISTAS PARA LOS REPORTES DEL SISTEMA (Facundo)
-- ============================================================================
--
-- NOTA DE REUTILIZACIÓN:
-- Las siguientes 3 vistas ya existen en 'Archivos necesarios para la BD/objects.sql'
-- y son validadas según sus specs en 'specs/parteB_*.md':
--   1. v_productos_vigentes
--   2. v_pedidos_resumen
--   3. v_pedido_detalle
--
-- No se recrean aquí para preservar los objetos creados originalmente.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Vista Nueva: v_usuario_seguro
-- Objetivo: Exponer datos de usuario ocultando la contraseña por seguridad.
-- Spec: specs/parteB_v_usuario_seguro.md
-- ----------------------------------------------------------------------------

CREATE OR REPLACE VIEW v_usuario_seguro AS
SELECT 
    id,
    nombre,
    apellido,
    mail,
    celular,
    rol,
    eliminado,
    created_at
FROM usuario;

COMMENT ON VIEW v_usuario_seguro IS 'Vista segura de usuarios que excluye la columna sensible de contraseña para reportes generales.';