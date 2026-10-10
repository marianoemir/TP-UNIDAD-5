# TP Unidad 5 — Food Store: administración y seguridad

Base de Datos II — Tecnicatura Universitaria en Programación (UTN) · Ciclo 2026

Roles y permisos de mínimo privilegio, auditoría, simulacro de incidente y protección de datos
personales sobre la base de Food Store (PostgreSQL 16+). Todo se ejecuta **solo** contra la instancia
propia `copia_u5`.

## Estructura

```
base_heredada/   los 10 .sql de Food Store (U1–U4), sin modificar
sql/             roles.sql, auditoria_test.sql, simulacro_incidente.sql, usuario_anon.sql
docs/            spec de Kiro, informes y logs (solo logs anonimizados)
BITACORA.md      bitácora de uso de IA
AGENTS.md        instrucciones para agentes y reglas del proyecto
protocolo_seguridad.md   protocolo permanente de trabajo seguro
.kiro/steering/  contexto del proyecto para Kiro
```

## Puesta en marcha (cada integrante, en su servidor local)

1. `plantilla_food_store` (U4): `schema.sql` → `objects.sql` → `data.sql`.
2. Crear `copia_u5` con `plantilla_food_store` como Template.
3. En `copia_u5`: `carga_masiva.sql` → `indices_semana3.sql` → `indices.sql` → `views.sql` → `materializadas.sql`.
4. Respaldar los roles existentes en `respaldos/` (ignorada por Git) **antes** de la Parte A.

Detalle completo y reglas duras en `AGENTS.md`.
