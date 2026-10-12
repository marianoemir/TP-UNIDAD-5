# Bitácora de IA — Paquete B: Datos y análisis (Parte C.5–C.6 y Mediciones)

## Declaración de herramientas

- **Gemini (Google)**: Asistencia en la redacción, contraste del análisis de IA vs. la realidad del log del simulacro, estructuración de las medidas de contención e integración del informe de incidente.
- **OpenCode (sesión previa/limpia)**: Generación del análisis primario del log anonimizado.
- Todos los hallazgos y medidas propuestas fueron revisados y contrastados con la evidencia técnica original (`sql/simulacro_incidente.sql`, `docs/log_simulacro_anonimizado.txt`, `docs/respuesta_opencode_simulacro.md` y `docs/constancia_escalamiento.txt`).

## Registros

| Prompt enviado a la IA | Respuesta relevante recibida (resumida) | Validación o corrección humana aplicada |
|---|---|---|
| Análisis del log y generación de contraste entre OpenCode y la realidad del log del simulacro (Punto 5) | Estructuración de coincidencias (fuerza bruta, lectura masiva, bloqueo por mínimos privilegios y riesgo de credenciales en logs) e inconsistencias/omisiones (falta de visibilidad interna de `fn_autenticar`, falta de contexto de negocio en la lectura masiva). | Verificado contra `docs/respuesta_opencode_simulacro.md` y `sql/simulacro_incidente.sql`. Se confirmó que la IA reconstruyó la secuencia cronológica pero no podía verificar si el fallo de autenticación ejecutaba un bloqueo activo en DB. |
| Formulación de la decisión de contención del equipo (Punto 6) | Propuesta de 3 ejes: congelamiento y borrado de cuentas sintéticas (`ALTER ROLE soporte_sim NOLOGIN;`), revocación de privilegios de simulación (`REVOKE`/`DROP`), y ajuste en niveles de log (`log_statement` a niveles operativos) junto a la protección del directorio de logs. | Validado técnicamente con el esquema de roles y la normativa de mínimos privilegios. Se adoptó formalmente la estrategia de contención en `docs/informe_incidente.md`. |
| Redacción unificada del documento `docs/informe_incidente.md` conteniendo los puntos 5 y 6 | Documento Markdown estructurado con secciones de Contraste (OpenCode vs Realidad) y Decisión de Contención con comandos SQL específicos. | Revisión general de coherencia con el resto del paquete y almacenamiento definitivo en el repositorio. |

## Caso de IA incorrecta / insegura / de más

OpenCode sugirió originalmente que el paso 3 (lectura masiva de la tabla de usuarios) podría requerir una reevaluación de los permisos del rol de soporte o que constituyó una exfiltración confirmada. Sin embargo, en el contexto de negocio y del simulacro, la columna de contraseñas no fue leída y la lectura masiva formaba parte de las funciones de un rol de soporte. La sugerencia se acotó en el informe como una limitación de contexto de la IA al analizar logs aislados.

## Nota sobre el historial de Git (Parte E, punto 3)

Trabajo en mi rama asignada, realizando commits específicos por entregable:
- Redacción del contraste e informe de incidente (`docs/informe_incidente.md`).
- Creación de la bitácora personal de IA.