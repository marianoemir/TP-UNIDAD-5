-- ============================================================================
-- auditoria_test.sql — Parte B.2: secuencia de prueba de auditoría
-- TP Unidad 5 — Base de Datos II
--
-- SE EJECUTA SOLO contra la base propia (copia_u5).
-- Secuencia pedida: lectura + inserción + actualización + login fallido.
-- Todo va en una transacción con ROLLBACK para no dejar basura en copia_u5.
-- El log del servidor igual registra las sentencias (log_statement = 'all').
--
-- Los marcadores 'auditoria_test: inicio/fin' (RAISE NOTICE) sirven para
-- recortar el fragmento del log para docs/log_auditoria_prueba.txt.
-- ============================================================================

-- Protección: no correr sobre la plantilla ni sobre 'postgres'.
DO $$
BEGIN
    IF current_database() IN ('postgres', 'plantilla_food_store') THEN
        RAISE EXCEPTION 'Base equivocada (%). Conectarse a copia_u5.', current_database();
    END IF;
END $$;

BEGIN;

DO $$ BEGIN RAISE NOTICE 'auditoria_test: inicio'; END $$;

-- 1. LECTURA: catálogo público (operación rutinaria de app_web).
SELECT * FROM v_productos_vigentes LIMIT 5;

-- 2. INSERCIÓN: categoría de prueba (nombre único con prefijo para no chocar).
INSERT INTO categoria (nombre, descripcion)
VALUES ('CAT_AUDIT_TEST', 'Categoria de prueba de auditoria - Parte B')
RETURNING id, nombre;

-- 3. ACTUALIZACIÓN: misma fila de prueba.
UPDATE categoria
SET descripcion = 'Categoria de prueba de auditoria - Parte B (modificada)'
WHERE nombre = 'CAT_AUDIT_TEST';

-- 4. LOGIN FALLIDO: mail inexistente + clave incorrecta (0 filas, no error).
SELECT * FROM fn_autenticar('no.existe.audit@example.com', 'clave_incorrecta_1');

DO $$ BEGIN RAISE NOTICE 'auditoria_test: fin'; END $$;

ROLLBACK;
