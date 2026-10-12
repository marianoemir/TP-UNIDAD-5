# Verificación de Equivalencia de Datos — Parte D

## 1. Consultas de Agregación Utilizadas

### Consulta sobre la tabla real (`usuario`)
\`\`\`sql
SELECT 
    rol,
    TO_CHAR(created_at, 'YYYY-MM') AS mes_alta,
    COUNT(*) AS total_usuarios
FROM usuario
GROUP BY rol, TO_CHAR(created_at, 'YYYY-MM')
ORDER BY mes_alta, rol;
\`\`\`

### Consulta equivalente sobre la tabla anonimizada (`usuario_anon`)
\`\`\`sql
SELECT 
    rol,
    mes_alta,
    COUNT(*) AS total_usuarios
FROM usuario_anon
GROUP BY rol, mes_alta
ORDER BY mes_alta, rol;
\`\`\`

## 2. Resultados Obtenidos
Ambas consultas fueron ejecutadas contra la base de datos `copia_u5` y arrojaron exactamente el mismo resultado cuantitativo y de agrupamiento:
- **ADMIN**: 1 usuario (mes `2026-10`)
- **USUARIO**: 20,005 usuarios (mes `2026-10`)

Esto demuestra que la tabla sintética `usuario_anon` preserva la integridad de los metadatos necesarios (rol y mes de alta) para realizar análisis estadísticos y minería de datos de forma segura.

## 3. Consideraciones sobre Información Sensible
Información crítica de Food Store como nombres, apellidos, correos electrónicos reales, números de teléfono y hashes de contraseñas **nunca** debe ser enviada a una IA ni expuesta en entornos públicos o de prueba sin un proceso estricto de anonimización. La exposición de estos datos vulnera la privacidad de los usuarios y expone credenciales o canales de contacto directos ante posibles brechas de seguridad.