# Proposal: agente-comunicacion

## Intent

Rediseñar cómo los agentes SDD se comunican entre sí para permitir:
- Ejecución true-parallel (background) sin bloquear al orquestador
- Comunicación via archivos JSON compartidos en artifacts/
- Resúmenes ejecutivos para HITL (aprobación humana)
- Logs detallados para auditoría
- Orquestador disponible siempre durante trabajo de agentes

**Problema actual**: El orquestador espera (`wait`) a que cada agente termine antes de iniciar el siguiente, mostrando TODO el estado al usuario en lugar de resúmenes ejecutivos.

## Scope

### In Scope
- Modificar `orchestrator/pipeline.sh` para ejecutar agentes en background real sin wait blocking
- Implementar sistema de archivos compartidos en `artifacts/agent-comm/` para comunicación JSON
- Crear `orchestrator/summary.sh` para generar resúmenes ejecutivos de HITL
- Organizar logs en `artifacts/agent-logs/{agent}/{timestamp}/` con estructura consistente
- Modificar `orchestrator/monitor.sh` para mostrar resúmenes en lugar de todo el estado
- Mantener compatibilidad con DAG existente en `dag/pipeline.yaml`

### Out of Scope
- Modificar lógica de agentes individuales (`agents/*.sh`)
- Cambiar el flujo del DAG definido en pipeline.yaml
- Implementar nuevo sistema de persistence (mantener archivos JSON)

## Approach

### Arquitectura Propuesta

```
┌─────────────────────────────────────────────────────────────────┐
│                    ORQUESTADOR (siempre libre)                  │
│  - Lanza agentes sin esperar (nohup &)                         │
│  - Muestra resúmenes HITL                                      │
│  - Disponible para intervención                                │
└─────────────────────────────────────────────────────────────────┘
                              │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    ▼
    ┌─────────┐         ┌─────────┐         ┌─────────┐
    │Agent A  │         │Agent B  │         │Agent C  │
    │(forked) │         │(forked) │         │(forked) │
    └─────────┘         └─────────┘         └─────────┘
         │                    │                    │
         ▼                    ▼                    ▼
    ┌─────────────────────────────────────────────────────────┐
     │           artifacts/agent-comm/{change-name}/ (JSON files)             │
     │  ├── {agent}-input.json    (recibe)                     │
     │  ├── {agent}-output.json   (escribe)                     │
     │  ├── {agent}-status.json   (estado actual)              │
     │  └── {agent}-summary.json  (resumen para HITL)          │
    └─────────────────────────────────────────────────────────┘
         │
         ▼
    ┌─────────────────────────────────────────────────────────┐
     │           artifacts/agent-logs/{change-name}/{agent}/{YYYYMMDD_HHMMSS}/                         │
     │       ├── stdout.log                                     │
     │       ├── stderr.log                                     │
     │       └── metadata.json                                  │
    └─────────────────────────────────────────────────────────┘
```

### Cambios en pipeline.sh

**Antes (líneas 337-368)**:
```bash
(agente) > "$log_file" 2>&1 &  # Ya usa background
wait $pid  # BLOQUEA hasta que termine
```

**Después**:
```bash
nohup agente > "$log_dir/stdout.log" 2>"$log_dir/stderr.log" &
AGENT_PID=$!
echo "$AGENT_PID" > "$artifacts/agent-comm/{agent}-pid.json"
# NO HAY WAIT - retornar inmediatamente
```

### Sistema de Comunicación JSON

Cada agente escribe archivos en `artifacts/agent-comm/{change-name}/`:
- `{agent}-status.json`: Estado actual (running/completed/failed)
- `{agent}-output.json`: Output del agente
- `{agent}-summary.json`: Resumen para HITL (máx 5 líneas)

### Resumen Ejecutivo para HITL

En approval gates, mostrar solo:
```
=== APROBACIÓN REQUERIDA: {gate} ===

📋 RESUMEN: {1-2 oraciones}

OPCIONES:
  A) {Opción 1} — {pros}
  B) {Opción 2} — {pros}  
  C) {Opción 3} — {pros}

⏱ Duración: {X} min
📊 Confianza: {Y}/10
🔗 Ver detalle: {archivo}
```

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `orchestrator/pipeline.sh` | Modified | Eliminar wait blocking, agregar sistema de archivos de comunicación |
| `orchestrator/monitor.sh` | Modified | Mostrar resúmenes ejecutivos, no todo el estado |
| `orchestrator/summary.sh` | New | Generar resúmenes para HITL |
| `artifacts/agent-comm/{change}/` | New | Directorio para archivos JSON de comunicación por proyecto |
| `artifacts/agent-logs/{change}/{agent}/` | New | Directorio para logs estructurados por proyecto y agente |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Agentes compiten por mismos archivos | Low | Usar locks (flock) o archivos atomicos |
| Estado inconsistente si agente falla | Medium | Timeout + cleanup automático |
| Logs excesivamente grandes | Low | Rotación de logs por día/tamaño |
| Complicación de debugging | Medium | Mantener logs de stdout/stderr legibles |

## Rollback Plan

1. Preservar versión original de `pipeline.sh` como `pipeline.sh.bak`
2. Si nuevo sistema falla: `mv pipeline.sh.bak pipeline.sh`
3. Los archivos en `artifacts/` son idempotentes - regenerables

## Dependencies

- None - cambios autocontenidos en orchestrator/

## Success Criteria

- [ ] Agentes se ejecutan en background real sin bloquear orquestador
- [ ] Orquestador puede iniciar múltiples agentes en paralelo
- [ ] HITL muestra resúmenes de máximo 10 líneas
- [ ] Logs organizados en estructura consistente
- [ ] Sistema compatible con DAG existente
- [ ] Mismo comportamiento para casos de uso típicos