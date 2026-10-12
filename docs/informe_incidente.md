# Informe de Incidente y Contraste — Parte C (Puntos 5 y 6)

## 1. Contraste: Respuesta de OpenCode vs. Realidad del Log (`docs/informe_incidente.md`)

A partir del análisis del log anonimizado (`docs/log_simulacro_anonimizado.txt`)[cite: 10] y de la respuesta generada por OpenCode en sesión limpia (`docs/respuesta_opencode_simulacro.md`)[cite: 8], se realiza el siguiente contraste:

*   **Lo que la IA acertó:** 
    *   Reconstruyó con precisión la secuencia cronológica dividida en las 5 sesiones (preparación del entorno, 5 intentos fallidos de autenticación, inicio de sesión exitoso, lectura masiva de la tabla de usuarios y los 3 intentos fallidos de escalamiento de privilegios)[cite: 8].
    *   Identificó correctamente que el modelo de mínimos privilegios (`NOSUPERUSER`, `NOCREATEDB`, `NOCREATEROLE` y ausencia del rol `admin_datos`) resistió perfectamente los ataques, bloqueando los tres intentos de escalamiento (`GRANT`, `SET ROLE` y `CREATE ROLE`)[cite: 8].
    *   Señaló con acierto un **hallazgo transversal de seguridad**: el parámetro `log_statement = 'all'` expone credenciales y datos sensibles en texto plano dentro del propio archivo de log, convirtiéndolo en un activo altamente sensible[cite: 8].

*   **Lo que la IA omitió o no pudo sustentar:**
    *   La IA indicó que el log no muestra el resultado de la función `fn_autenticar` ni el mecanismo de bloqueo tras los intentos fallidos, sugiriendo limitaciones sobre el comportamiento interno de la función[cite: 8]. Sin embargo, el script original del simulacro ejecutó los intentos secuencialmente para medir el comportamiento sin causar errores de sintaxis en el motor[cite: 7].
    *   No pudo determinar de forma concluyente si el paso 3 (la lectura masiva de la tabla `usuario` por parte del rol `soporte_sim`) constituyó un abuso real o un uso previsto del rol, ya que el log solo registra la ejecución de la sentencia `SELECT` sin contexto de negocio adicional[cite: 8].

---

## 2. Decisión de Contención del Equipo

Tomando como base la evidencia directa obtenida del log anonimizado y el comportamiento verificado del motor PostgreSQL, el equipo de trabajo adopta formalmente las siguientes medidas de contención y mitigación:

1.  **Gestión de Cuentas de Prueba:** 
    *   Se procede a deshabilitar el acceso de inicio de sesión para la cuenta de soporte utilizada en el simulacro mediante la instrucción `ALTER ROLE soporte_sim NOLOGIN;` para evitar accesos residuales[cite: 8].
    *   Se procede a eliminar o bloquear lógicamente el usuario sintético de prueba (`usuario.sim.0001@ejemplo.test`) creado en la base de datos[cite: 8].
2.  **Revocación de Permisos Temporales:**
    *   Se eliminan los privilegios y membresías otorgadas exclusivamente para las pruebas de simulación (`REVOKE rol_soporte FROM soporte_sim;` y posterior eliminación del rol con `DROP ROLE soporte_sim;`)[cite: 8].
3.  **Ajuste y Protección de Niveles de Auditoría:**
    *   Debido al riesgo de exposición de credenciales en texto plano detectado al utilizar `log_statement = 'all'`, se establece como directiva de seguridad que dicho nivel de detalle solo se mantenga en ventanas estrictamente controladas de auditoría forense, recomendando retornar a niveles operativos estándar (`mod` o combinaciones con `log_min_duration_statement`) para entornos productivos comunes[cite: 8].
    *   Se restringen de manera estricta los permisos de lectura sobre el directorio de logs del servidor PostgreSQL (`C:\Program Files\PostgreSQL\... \log`), limitando su acceso exclusivamente al rol de administración autorizado (`admin_datos` / DBA)[cite: 5].