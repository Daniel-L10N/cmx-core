# Manual de Operaciones Rápido — CMX-CORE

> **Sistema de Control Modular MX**  
> **Autor**: Daniel-L10N  
> **Workspace base**: `/home/cmx/cmx-core`

---

## 🎭 0. Personalidades CMX-CORE

CMX-CORE tiene 3 modos de autonomía. Elige según tu necesidad:

### Selector de Modo

```bash
cd /home/cmx/cmx-core

# Ver modo actual
./set-mode.sh

# Cambiar a modo peligroso (Daniel™)
./set-mode.sh dangerous
```

### Los 3 Modos

| Modo | Rigor | HITL | Uso |
|-------|-------|------|-----|
| 🔒 **Professional** | 10/10 | Cada paso | Proyectos críticos |
| ⚖️ **Standard** | 5/10 | En errores | Desarrollo diario |
| ⚡ **Dangerous** | 2/10 | Nunca | ¡Daniel™ se va a fumar! 🚬 |

### Modo DANGEROUS para Daniel™ ☕

**¿Te vas? ¿Quieres que CMX-CORE trabaje solo?**

```bash
cd /home/cmx/cmx-core

# 1. Activa modo peligroso
./set-mode.sh dangerous

# 2. Asegúrate de tener la exploración
# artifacts/exploration/mi-feature.json

# 3. ¡ACTIVAR PILOTO AUTOMÁTICO!
./full-auto.sh mi-feature

# 4. Levántate, café,回来 y tu proyecto está listo 🎉
```

El modo dangerous:
- ❌ No pregunta nada
- ❌ No se detiene en errores
- ❌ No requiere aprobación
- ✅ Encadena TODO: proposer → spec → design → tasks → batches → archiver
- ✅ Git auto-commit al final

---

## 1. Punto de Partida: Archivo JSON de Idea Inicial

### Dónde crear el archivo

```bash
mkdir -p /home/cmx/cmx-core/artifacts/exploration
```

### Estructura mínima del JSON

Crea: `artifacts/exploration/mi-feature.json`

```json
{
  "type": "exploration_input",
  "version": "1.0.0",
  "change": "mi-feature",
  "description": "Descripción de lo que quieres construir",
  "workspace": "/home/cmx/cmx-core",
  "constraints": {
    "language": "typescript",
    "framework": "nextjs"
  }
}
```

---

## 2. Fase de Arquitectura

### Opción A: Manual (Standard/Professional)

```bash
./agents/proposer.sh mi-feature
./agents/spec-writer.sh mi-feature &
./agents/designer.sh mi-feature &
wait
./agents/task-planner.sh mi-feature
```

### Opción B: Automático (Dangerous)

```bash
./full-auto.sh mi-feature
```

---

## 3. Fase de Fabricación: Batches

### Ciclo manual

```bash
# Batch N
./agents/implementer.sh mi-feature N
./agents/verifier.sh mi-feature N
```

### Si falla el verificador

```bash
# Ver qué falló
cat artifacts/verification/mi-feature_batch_N.json | jq

# Corregir archivos
# Re-ejecutar
./agents/implementer.sh mi-feature N
./agents/verifier.sh mi-feature N
```

---

## 4. Monitoreo

```bash
# Estado actual
./orchestrator/monitor.sh --once

# Monitoreo continuo
./orchestrator/monitor.sh

# Parar todo
./orchestrator/stop-all.sh
```

---

## 5. Cierre

```bash
./agents/archiver.sh mi-feature
```

---

## 📁 Estructura de Archivos

| Tipo | Ruta |
|------|------|
| Exploración | `artifacts/exploration/{change}.json` |
| Propuesta | `artifacts/proposals/{change}.json` |
| Spec | `artifacts/specs/{change}.json` |
| Tasks | `artifacts/tasks/{change}.json` |
| Implementación | `artifacts/implementation/{change}_batch_{N}.json` |
| Verificación | `artifacts/verification/{change}_batch_{N}.json` |
| Archive | `artifacts/archive/{change}_{timestamp}/` |
| Modos | `orchestrator/personalities.json` |

---

## 🚀 Quick Start Daniel™

```bash
cd /home/cmx/cmx-core

# 1. Crear idea
echo '{"change":"mi-app","description":"mi app"}' > artifacts/exploration/mi-app.json

# 2. Modo peligroso
./set-mode.sh dangerous

# 3. ¡A trabajar! 
./full-auto.sh mi-app

# 4. ☕ Café + Cigarro + Volver con proyecto listo
```

---

*CMX-CORE v2 — Control Modular MX*
