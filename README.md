# Cognitive Stack — SDD Pipeline Engine

## Sistema de Orquestación Multi-Agente Real

Este stack implementa un sistema de orquestación de agentes con:

- **Agentes reales** (procesos Bash independientes)
- **DAG ejecutable** (pipeline.yaml con dependencias)
- **Contratos validados** (JSON Schemas para cada fase)
- **HITL real** (gates de aprobación con bloqueo)

---

## Estructura

```
cmx-core/
├── agents/                    # Agentes reales (procesos)
│   ├── explorer.sh
│   ├── proposer.sh
│   ├── spec-writer.sh
│   ├── designer.sh
│   ├── task-planner.sh
│   ├── implementer.sh
│   ├── verifier.sh
│   └── archiver.sh
├── dag/
│   └── pipeline.yaml          # DAG ejecutable con dependencias
├── schemas/                   # JSON Schemas para validación
│   ├── proposal.schema.json
│   ├── spec.schema.json
│   ├── design.schema.json
│   ├── tasks.schema.json
│   ├── apply.schema.json
│   ├── verify.schema.json
│   └── examples/              # Ejemplos válidos e inválidos
├── orchestrator/
│   ├── pipeline.sh            # Motor DAG
│   └── state.json             # Estado del pipeline
├── validators/
│   └── validate.sh            # Validador de schemas
└── run.sh                     # Comando único
```

---

## Uso Rápido

```bash
cd /home/cmx/cmx-core

# Inicializar
./run.sh init

# Ver estado
./run.sh status

# Ejecutar pipeline completo (con HITL)
./run.sh run mi-feature "nueva funcionalidad"

# Solo una fase
./run.sh explore "investigar autenticación"
./run.sh validate proposal schemas/examples/proposal.valid.json
```

---

## Alias Disponibles

Agregar a `~/.bashrc`:

```bash
alias cs-pipeline='cd /home/cmx/cmx-core && ./run.sh'
alias cs-run='cd /home/cmx/cmx-core && ./run.sh run'
alias cs-status='cd /home/cmx/cmx-core && ./run.sh status'
```

---

## Flujo del Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│ EXPLORE → PROPOSE → [SPEC ║ DESIGN] → TASKS → APPLY →     │
│                                        VERIFY → ARCHIVE     │
└─────────────────────────────────────────────────────────────┘
         ↑            ↑                    ↑
         │            │                    │
      HITL          HITL                 HITL
```

### GATES de Aprobación (HITL Real)

| Gate | Fase | Bloqueo |
|------|------|---------|
| `proposal_approved` | propose | ✅ Sí |
| `spec_approved` | spec | ✅ Sí |
| `design_approved` | design | ✅ Sí |
| `tasks_approved` | tasks | ✅ Sí |
| `batch_approved` | apply | ✅ Sí |
| `archive_approved` | archive | ✅ Sí |

---

## Contratos de Salida

Cada fase produce artifacts con schema definido:

| Fase | Schema | Campos Requeridos |
|------|--------|-------------------|
| propose | `proposal.schema.json` | name, approach, risks, rollback_plan |
| spec | `spec.schema.json` | title, scenarios, acceptance_criteria |
| design | `design.schema.json` | architecture, data_model, api_contract |
| tasks | `tasks.schema.json` | phases, total_tasks, estimated_hours |
| apply | `apply.schema.json` | batch, tasks_completed, files_changed |
| verify | `verify.schema.json` | overall_status, scenarios_tested, issues |

### Ejemplo de Validación

```bash
# Validar proposal
./run.sh validate proposal artifacts/proposals/mi-feature.md

# Validar spec
./run.sh validate spec artifacts/specs/mi-feature.md
```

---

## Arquitectura Técnica

### 1. Agentes Reales

Cada agente es un script Bash que:
- Se ejecuta como proceso independiente
- Recibe parámetros: PROJECT, CHANGE_NAME, BATCH
- Produce artifact en ubicación predefinida
- Retorna código de salida (0=éxito, 1=fallo)
- Logs en `orchestrator/logs/`

### 2. DAG Ejecutable

Archivo `dag/pipeline.yaml` define:
- Fases con dependencias
- Condiciones de ejecución
- GATES de aprobación
- Tiempos de timeout
- Modo (parallel/sequential)

### 3. Pipeline Engine

`orchestrator/pipeline.sh`:
- Lee estado desde `state.json`
- Ejecuta fases según DAG
- Valida contratos antes de continuar
- Solicita aprobación humana en gates
- Registra progreso en logs

### 4. Sistema de Validación

`validators/validate.sh`:
- Verifica JSON válido
- Valida campos requeridos
- Compara tipos de datos
- Reporta errores específicos

---

## Estado del Pipeline

```json
{
  "pipeline": "SDD",
  "version": "1.0.0",
  "current_phase": "apply",
  "change_name": "mi-feature",
  "approved_gates": {
    "proposal_approved": true,
    "spec_approved": true,
    "design_approved": true,
    "tasks_approved": true
  },
  "artifacts": {
    "exploration": "artifacts/exploration/mi-feature.md",
    "proposal": "artifacts/proposals/mi-feature.md",
    "spec": "artifacts/specs/mi-feature.md"
  },
  "phases_completed": ["explore", "propose", "spec", "design", "tasks"]
}
```

---

## Comparación: Antes vs Después

| Aspecto | Antes | Después |
|---------|-------|---------|
| Agentes | Prompts en JSON | Procesos Bash reales |
| DAG | Texto en prompt | YAML ejecutable |
| Validación | Manual | Automática con Schemas |
| HITL | Sugerencia | Bloqueo real |
| Estado | Solo contexto | JSON persistente |

---

## Dependencias

- `bash` 4+
- `jq` 1.6+
- `opencode` (para ejecutar agentes)
- `python3` (opcional, para validación avanzada)

Instalación de dependencias:
```bash
sudo dnf install -y jq
```

---

## Troubleshooting

### Error: "Schema no encontrado"
```bash
ls -la schemas/
```

### Error: "JSON inválido"
```bash
jq empty tu-archivo.json
```

### Resetear pipeline
```bash
./run.sh reset
```

### Ver logs
```bash
tail -f orchestrator/logs/*.log
```
