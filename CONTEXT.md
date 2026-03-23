# CMX-CORE — Sistema de Control Modular MX

**Última actualización**: 2026-03-22

## Stack Tecnológico

### Frontend
- **Framework**: Next.js 14+ (App Router)
- **UI**: React 18+
- **Lenguaje**: TypeScript (strict mode)
- **Estilos**: Tailwind CSS
- **Estado**: Zustand / React Query

### Backend
- **Framework**: Django 5+
- **API**: Django REST Framework
- **Auth**: JWT (SimpleJWT)
- **DB**: PostgreSQL (prod), SQLite (dev)

## Workspace

**Ruta base**: `/home/cmx/cmx-core/`

```
/home/cmx/cmx-core/
├── agents/             # Agentes del pipeline SDD
│   ├── explorer.sh
│   ├── proposer.sh
│   ├── spec-writer.sh
│   ├── designer.sh
│   ├── task-planner.sh
│   ├── implementer.sh
│   ├── verifier.sh
│   └── archiver.sh
├── orchestrator/       # Orquestación y monitoreo
│   ├── monitor.sh
│   ├── stop-all.sh
│   ├── pipeline.sh
│   └── agent_state.json
├── artifacts/          # Specs, proposals, designs, archives
└── skills/             # Skills del proyecto
    ├── frontend-react.md
    └── backend-django.md
```

## Memorias (Engram)

Ubicación: `~/.engram/` (compartido entre OpenCode y Gemini CLI)

Para buscar memorias:
```
mem_search(query: "{búsqueda}", project: "cmx-core")
```

## Flujo de Trabajo

```
1. cd /home/cmx/cmx-core
2. ./agents/explorer.sh <change>       → Explorar idea
3. ./agents/proposer.sh <change>       → Generar propuesta
4. ./agents/spec-writer.sh <change>     → Escribir spec
5. ./agents/designer.sh <change>        → Diseño UI/UX
6. ./agents/task-planner.sh <change>    → Plan de tareas
7. ./agents/implementer.sh <change> N   → Implementar batch N
8. ./agents/verifier.sh <change> N      → Verificar batch N
9. [HITL]                              → Aprobación humana si falla
10. ./agents/archiver.sh <change>        → Cerrar y persistir
```

## Skills Disponibles

| Skill | Ruta | Descripción |
|-------|------|-------------|
| frontend-react | `skills/frontend-react.md` | React/Next.js/TS |
| backend-django | `skills/backend-django.md` | Django/DRF |

## Monitoreo

```bash
# Estado actual (una vez)
./orchestrator/monitor.sh --once

# Monitoreo continuo
./orchestrator/monitor.sh

# Parar todos los agentes
./orchestrator/stop-all.sh
```

## Notas

- El orquestador NUNCA hace trabajo directo — siempre delega
- HITL en: propuesta → spec → apply
- Guardar decisiones importantes en Engram con `mem_save`
