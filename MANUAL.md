# Manual de Operaciones Rápido — CMX-CORE

> **Sistema de Control Modular MX**  
> **Proyecto de ejemplo**: `mi-nueva-app`  
> **Workspace base**: `/home/cmx/cmx-core`

---

## 1. Punto de Partida: Archivo JSON de Idea Inicial

### Dónde crear el archivo

```bash
# Crear directorio de exploración
mkdir -p /home/cmx/cmx-core/artifacts/exploration
```

### Estructura mínima del JSON

Crea el archivo en: `artifacts/exploration/mi-nueva-app.json`

```json
{
  "type": "exploration_input",
  "version": "1.0.0",
  "change": "mi-nueva-app",
  "description": "Descripción breve de la feature que quieres construir",
  "workspace": "/home/cmx/cmx-core",
  "constraints": {
    "language": "typescript",
    "framework": "nextjs",
    "styling": "tailwind"
  }
}
```

### Ejecutar Explorer

```bash
cd /home/cmx/cmx-core
./agents/explorer.sh /home/cmx/cmx-core mi-nueva-app
```

---

## 2. Fase de Arquitectura: Orden de Comandos

### Secuencia lineal (necesario completar uno antes del siguiente)

```bash
# 1. PROPOSER — Genera propuesta formal
./agents/proposer.sh mi-nueva-app

# 🔄 Se puede paralelizar con spec y design después de proposer
# (Ver abajo)

# 2. SPEC-WRITER — Genera especificación técnica
./agents/spec-writer.sh mi-nueva-app

# 3. DESIGNER — Genera diseño UI/UX  
./agents/designer.sh mi-nueva-app

# 4. TASK-PLANNER — Genera plan de tareas
./agents/task-planner.sh mi-nueva-app
```

### Paralelización opcional (después de proposer)

```bash
# Estos dos pueden ejecutarse EN PARALELO después de proposer:
./agents/spec-writer.sh mi-nueva-app &
./agents/designer.sh mi-nueva-app &

# Waiting...
wait
```

---

## 3. Fase de Fabricación: Ciclo de Batches

### Estructura del ciclo

Cada batch = `implementer.sh` + `verifier.sh` + **HITL approval**

### Comando fresco del ciclo

```bash
# --- BATCH 1: Setup Inicial ---
./agents/implementer.sh mi-nueva-app 1
./agents/verifier.sh mi-nueva-app 1
# 🛑 HITL: Revisar artifacts/verification/mi-nueva-app_batch_1.json

# --- BATCH 2: Funcionalidad Core ---
./agents/implementer.sh mi-nueva-app 2  
./agents/verifier.sh mi-nueva-app 2
# 🛑 HITL: Revisar artifacts/verification/mi-nueva-app_batch_2.json

# --- BATCH 3: Tests y Polish ---
./agents/implementer.sh mi-nueva-app 3
./agents/verifier.sh mi-nueva-app 3
# 🛑 HITL: Revisar artifacts/verification/mi-nueva-app_batch_3.json
```

### La Puerta de Aprobación (HITL)

**Cuándo el verificador FALLA** → Debes intervenir manualmente:

| Condición | Acción Required |
|-----------|-----------------|
| `passed: false` | Revisar `issues_found[]` en el JSON de verificación |
| `confidence < 8` | Revisar código manualmente |
| `severity: high/medium` en issues | **Corregir los problemas antes de continuar** |

### Si el verificador falla

```bash
# 1. Ver qué falló
cat /home/cmx/cmx-core/artifacts/verification/mi-nueva-app_batch_N.json | jq

# 2. Si hay issues HIGH/MEDIUM:
#    - Leer los archivos problemáticos
#    - Corregir manualmente o delegar a implementer con el mismo batch

# 3. Re-ejecutar implementación (mismo batch)
./agents/implementer.sh mi-nueva-app N

# 4. Volver a verificar
./agents/verifier.sh mi-nueva-app N
```

---

## 4. Monitoreo y Cierre

### Monitoreo en tiempo real

```bash
# Ver estado actual (una vez)
./orchestrator/monitor.sh --once

# Monitoreo continuo (refresca cada 2s)
./orchestrator/monitor.sh
```

### Indicadores visuales en monitor

| Status | Significado |
|--------|-------------|
| 🔄 RUNNING | Agente ejecutándose |
| ✅ DONE | Completado exitosamente |
| ❌ FAILED | Falló |
| ⏸ PENDING | No iniciado |
| 🚨 (rojo) | HITL requerido |

### Finalizar y archivar

```bash
# Cuando TODOS los batches pasaron
./agents/archiver.sh mi-nueva-app
```

Esto mueve todos los artifacts a `artifacts/archive/mi-nueva-app_TIMESTAMP/`

---

## Quick Reference — Comandos en una línea

```bash
# Fase 1: Exploración
cd /home/cmx/cmx-core
./agents/explorer.sh mi-nueva-app

# Fase 2: Arquitectura (lineal)
./agents/proposer.sh mi-nueva-app
./agents/spec-writer.sh mi-nueva-app  
./agents/designer.sh mi-nueva-app
./agents/task-planner.sh mi-nueva-app

# Fase 3: Fabricación (repetir N batches)
./agents/implementer.sh mi-nueva-app N
./agents/verifier.sh mi-nueva-app N
# [HITL: revisar manualmente]
# Repetir para siguiente batch

# Cierre
./agents/archiver.sh mi-nueva-app
```

---

## Ubicaciones clave

| Artefacto | Ruta |
|-----------|------|
| Exploración | `artifacts/exploration/{change}.{json,md}` |
| Propuesta | `artifacts/proposals/{change}.json` |
| Spec | `artifacts/specs/{change}.json` |
| Diseño | `artifacts/designs/{change}.json` |
| Tareas | `artifacts/tasks/{change}.json` |
| Implementación | `artifacts/implementation/{change}_batch_{N}.json` |
| Verificación | `artifacts/verification/{change}_batch_{N}.json` |
| Estado actual | `orchestrator/agent_state.json` |
| Logs activos | `orchestrator/logs/active/` |
| Archive | `artifacts/archive/{change}_{timestamp}/` |

---

## Sistema Autónomo - Referencia Rápida

### Inicialización

```bash
cd /home/cmx/cmx-core
./cmx init
```

### Comandos Principales

```bash
# Ejecutar tarea
./cmx task "descripción" [--mode autonomous|hybrid|manual] [--project nombre]

# Estado del sistema
./cmx status

# Listar IAs
./cmx list-ias

# Verificar entorno
./cmx env-check

# Ver memorias
./cmx memories [proyecto] [agente] [tipo]

# Cleanup post-proyecto
./cmx cleanup <proyecto>
```

### Archivos del Sistema Autónomo

| Componente | Ruta |
|------------|------|
| Cerebro | `brain.sh` |
| CLI | `cmx` |
| Registro IAs | `config/ai-registry.json` |
| Autonomía | `config/autonomy.yaml` |
| Memorias | `memories.json` |
| Decisiones | `artifacts/memories/` |

---

*Generated: CMX-CORE v2 — Sistema de Control Modular MX*
