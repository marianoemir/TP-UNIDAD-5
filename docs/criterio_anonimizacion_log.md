# Criterio de anonimización del log del simulacro (Parte C.3)

Este archivo documenta cómo se anonimizó `docs/log_simulacro_anonimizado.txt`. **No se le entrega a la IA**:
a OpenCode se le pasa únicamente el contenido del log, sin este mapa y sin comentarios (la consigna pide no
agregar contexto adicional al que el log ofrece).

Encabezado que tenía originalmente el archivo del log (movido acá):

```
-- Log anonimizado — Parte C.3 (simulacro de incidente)
-- Base propia copia_u5, 2026-10-12 08:21:56 -03 a 08:22:04 -03, log_statement='all'.
-- Recorte entre 'simulacro: preparacion' y 'simulacro: paso 4'.
-- Anonimización aplicada (criterio usuario_anon, valores sintéticos deterministas):
--   cliente.simulacro@example.com -> usuario.sim.0001@ejemplo.test
--   'Cliente' / 'Simulacro' -> 'Usuario' / 'Simulado'
--   '2610000000' -> '2000000000'
--   'ClaveSimulacro-2026' -> 'CLAVE_OK_SINTETICA'
--   'intento_incorrecto_N' -> 'CLAVE_ERRONEA_N'
--   'Sim-Soporte-2026' -> 'CLAVE_SOPORTE_TEST'
--   host=::1 -> host=IP_ANONIMIZADA
-- Se conservan roles del motor (postgres, app_web, soporte_sim, admin_datos),
-- timestamps y textos de sentencia: son lo necesario para auditar (quién/qué/cuándo).
-- Se excluyó ruido de pgAdmin (pga4dash) anterior y posterior al recorte.
```

## Por qué se movió

La primera versión del log incluía este encabezado dentro del mismo archivo y se le pasó completo a OpenCode
(ver `docs/respuesta_opencode_simulacro_v1.md`). Eso revelaba los valores originales y agregaba contexto que el log
no tiene (por ejemplo, que se había excluido ruido de pgAdmin), y la respuesta lo usó. La Parte C.4 se repitió con el
log sin encabezado (`docs/respuesta_opencode_simulacro.md`).
