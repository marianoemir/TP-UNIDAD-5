-- ============================================================================
-- simulacro_incidente.sql - Parte C: simulacro de incidente de acceso indebido
-- TP Unidad 5 - Base de Datos II
--
-- SE EJECUTA SOLO contra la base propia (copia_u5). No usar contra sistemas de terceros.
--
-- Este archivo NO se corre de una vez: lo orquesta sql/simulacro_incidente.ps1, que
-- invoca psql una vez por paso, conectandose como el login que corresponde (asi el log
-- del servidor registra al usuario real de cada paso y no siempre a postgres):
--
--   paso 0  postgres      preparacion: usuario de prueba y login de soporte de prueba
--   paso 1  app_web       varios intentos FALLIDOS de inicio de sesion (fn_autenticar)
--   paso 2  app_web       inicio de sesion EXITOSO
--   paso 3  soporte_sim   LECTURA MASIVA de la tabla usuario
--   paso 4  soporte_sim   intento de ESCALAMIENTO a admin_datos (debe FALLAR)
--   paso 9  postgres      limpieza (solo con -Limpiar)
--
-- El paso se elige con la variable psql :paso (-v paso=N). Cada paso emite un marcador
-- (DO ... RAISE NOTICE 'simulacro: ...') que queda en el log y delimita el fragmento.
--
-- Requisito para que el log sirva: log_statement = 'all' (con 'mod' no se registran
-- los SELECT de los pasos 1 a 3). Las sentencias y las claves de PRUEBA quedan en el log
-- en texto plano: anonimizar el log antes de compartirlo o commitearlo.
-- ============================================================================

SELECT (:paso = 0) AS p0, (:paso = 1) AS p1, (:paso = 2) AS p2,
       (:paso = 3) AS p3, (:paso = 4) AS p4, (:paso = 9) AS p9 \gset

-- ----------------------------------------------------------------------------
-- Paso 0 (postgres): preparacion
-- ----------------------------------------------------------------------------
\if :p0
DO $$ BEGIN RAISE NOTICE 'simulacro: preparacion'; END $$;

-- Usuario de la aplicacion con hash REAL (los hashes de carga_masiva.sql son ficticios y
-- crypt() puede fallar con ellos). Clave de prueba: ClaveSimulacro-2026
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol)
SELECT 'Cliente', 'Simulacro', 'cliente.simulacro@example.com', '2610000000',
       crypt('ClaveSimulacro-2026', gen_salt('bf')), 'USUARIO'
WHERE NOT EXISTS (
    SELECT 1 FROM usuario WHERE mail = 'cliente.simulacro@example.com');

-- Login de bajo privilegio: solo es miembro de rol_soporte.
SELECT format('CREATE ROLE soporte_sim LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L',
              :'pass_soporte')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'soporte_sim') \gexec
SELECT format('ALTER ROLE soporte_sim LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L',
              :'pass_soporte') \gexec
GRANT rol_soporte TO soporte_sim;
\endif

-- ----------------------------------------------------------------------------
-- Paso 1 (app_web): intentos fallidos de inicio de sesion
-- ----------------------------------------------------------------------------
\if :p1
DO $$ BEGIN RAISE NOTICE 'simulacro: paso 1 - intentos fallidos (inicio)'; END $$;
SELECT * FROM fn_autenticar('cliente.simulacro@example.com', 'intento_incorrecto_1');
DO $$ BEGIN PERFORM pg_sleep(1); END $$;
SELECT * FROM fn_autenticar('cliente.simulacro@example.com', 'intento_incorrecto_2');
DO $$ BEGIN PERFORM pg_sleep(1); END $$;
SELECT * FROM fn_autenticar('cliente.simulacro@example.com', 'intento_incorrecto_3');
DO $$ BEGIN PERFORM pg_sleep(1); END $$;
SELECT * FROM fn_autenticar('cliente.simulacro@example.com', 'intento_incorrecto_4');
DO $$ BEGIN PERFORM pg_sleep(1); END $$;
SELECT * FROM fn_autenticar('cliente.simulacro@example.com', 'intento_incorrecto_5');
\endif

-- ----------------------------------------------------------------------------
-- Paso 2 (app_web): inicio de sesion exitoso
-- ----------------------------------------------------------------------------
\if :p2
DO $$ BEGIN RAISE NOTICE 'simulacro: paso 2 - inicio de sesion exitoso'; END $$;
SELECT * FROM fn_autenticar('cliente.simulacro@example.com', 'ClaveSimulacro-2026');
\endif

-- ----------------------------------------------------------------------------
-- Paso 3 (soporte_sim): lectura masiva de usuario
-- Es un permiso LEGITIMO de rol_soporte (columnas permitidas); lo anomalo del incidente
-- es el patron (login fallido -> login exitoso -> lectura masiva -> escalamiento).
-- ----------------------------------------------------------------------------
\if :p3
DO $$ BEGIN RAISE NOTICE 'simulacro: paso 3 - lectura masiva de usuario'; END $$;
SELECT id, nombre, apellido, mail, rol, eliminado, created_at FROM usuario ORDER BY id;
\endif

-- ----------------------------------------------------------------------------
-- Paso 4 (soporte_sim): intento de escalamiento. Los TRES intentos deben FALLAR.
-- Si alguno funciona, es un HALLAZGO: el esquema de la Parte A tiene un defecto.
-- ----------------------------------------------------------------------------
\if :p4
DO $$ BEGIN RAISE NOTICE 'simulacro: paso 4 - intento de escalamiento'; END $$;
-- Intento 1: otorgarse la membresia en admin_datos.
GRANT admin_datos TO soporte_sim;
-- Intento 2: asumir el rol admin_datos.
SET ROLE admin_datos;
-- Intento 3: crear un rol nuevo (operacion reservada).
CREATE ROLE intruso_sim LOGIN;
\endif

-- ----------------------------------------------------------------------------
-- Paso 9 (postgres): limpieza. Elimina todo lo creado por el paso 0 (y cualquier
-- resto de un escalamiento que hubiera funcionado).
-- ----------------------------------------------------------------------------
\if :p9
DO $$ BEGIN RAISE NOTICE 'simulacro: limpieza'; END $$;
DELETE FROM usuario WHERE mail = 'cliente.simulacro@example.com';
DROP ROLE IF EXISTS intruso_sim;
DROP ROLE IF EXISTS soporte_sim;
\endif
