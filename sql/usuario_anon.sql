-- ============================================================================
-- usuario_anon.sql - Parte D: tabla anonimizada de usuario
-- TP Unidad 5 - Base de Datos II
--
-- Datos sinteticos DETERMINISTAS (se derivan del id: el mismo id da siempre el mismo
-- valor), segun el patron visto en clase. Se conservan solo los campos necesarios para
-- analisis agregados (rol, eliminado, created_at). Se ejecuta SOLO en la base propia
-- (copia_u5). Es re-ejecutable.
--
-- No se copia ningun dato personal real: ni nombre, ni apellido, ni mail, ni celular, ni
-- hash de contrasena.
-- ============================================================================

DROP TABLE IF EXISTS usuario_anon;

CREATE TABLE usuario_anon AS
SELECT id,
       'Usuario '  || id                    AS nombre,
       'Apellido ' || id                    AS apellido,
       'usuario'   || id || '@ejemplo.test' AS mail,
       NULL::VARCHAR                        AS celular,
       'hash_no_valido'                     AS contrasena,
       rol, eliminado, created_at
FROM   usuario;

ALTER TABLE usuario_anon ADD PRIMARY KEY (id);
ANALYZE usuario_anon;

-- Comprobacion rapida: misma cantidad de filas que la tabla real.
SELECT (SELECT COUNT(*) FROM usuario)      AS filas_usuario,
       (SELECT COUNT(*) FROM usuario_anon) AS filas_usuario_anon;
