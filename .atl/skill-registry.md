# Skill Registry - cmx-core

**Última actualización**: 2026-04-03

## Project Skills

| Skill | Path | Description |
|-------|------|-------------|
| frontend-react | `skills/frontend-react.md` | React/Next.js/TypeScript |
| backend-django | `skills/backend-django.md` | Django/DRF |
| cognitive-context | `skills/cognitive-context.md` | Contexto cognitivo del pipeline |

## SDD Pipeline Skills

| Phase | Agent Script | Description |
|-------|--------------|-------------|
| explore | `agents/explorer.sh` | Exploración de ideas |
| propose | `agents/proposer.sh` | Generación de propuestas |
| spec | `agents/spec-writer.sh` | Escritura de especificaciones |
| design | `agents/designer.sh` | Diseño UI/UX |
| tasks | `agents/task-planner.sh` | Planificación de tareas |
| apply | `agents/implementer.sh` | Implementación |
| verify | `agents/verifier.sh` | Verificación |
| archive | `agents/archiver.sh` | Archivado |

## Orchestrator Commands

- `pipeline.sh run <change> [start-phase]` - Ejecutar pipeline
- `pipeline.sh status` - Mostrar estado
- `pipeline.sh reset` - Resetear estado
- `summary.sh summary [change]` - Resumen ejecutivo
- `summary.sh hitl <change>` - Resumen para HITL

## Active Changes

- `agente-comunicacion` - Propuesta parcialmente implementada (background agents, summary.sh)