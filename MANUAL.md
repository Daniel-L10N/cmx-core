# Manual de Usuario — CMX-CORE v2.1.0

> **Sistema de Control Modular MX**  
> **Versión**: 2.1.0 | **Fecha**: 2026-04-03

---

## 🚀 Inicio Rápido

```bash
# 1. Clonar el repositorio
git clone https://github.com/Daniel-L10N/cmx-core.git
cd cmx-core

# 2. Inicializar el sistema
source .env  # Configurar variables de entorno (si tienes)
./cmx init

# 3. Ejecutar una tarea
./cmx task "crear una API REST con autenticación"

# 4. Ver estado
./cmx status
```

---

## 📋 Modos de Uso

### Modo 1: Sistema Autónomo (Recomendado)

El cerebro analiza tu tarea y selecciona la mejor IA automáticamente.

```bash
# Ejecutar tarea - el sistema decide cómo ejecutarla
./cmx task "tu descripción" --mode hybrid

# Modes disponibles:
# - manual: cada paso requiere aprobación
# - hybrid: solo decisiones críticas requieren aprobación  
# - autonomous: opera autonomously, reporta al final
```

### Modo 2: Pipeline SDD Tradicional

Desarrollo estructurado paso a paso.

```bash
./run.sh run mi-feature "descripción"
# O paso a paso:
./run.sh explore "tema"
./run.sh propose
./run.sh spec
./run.sh design
./run.sh tasks
./run.sh apply 1
./run.sh verify 1
./run.sh archive
```

---

## 🤖 AI Providers

### Proveedores Configurados (v2.1.0)

| Provider | Cost | Modelos | Comandos |
|----------|------|---------|-----------|
| **OpenCode** | Gratis | big-pickle, gpt-5-nano, minimax-m2.5-free, nemotron-3-super-free, qwen3.6-plus-free | `opencode run "task"` |
| **Gemini CLI** | Gratis | gemini-2.0-flash, gemini-2.0-pro | `gemini -p "task"` |
| **OpenRouter** | Gratis* | deepseek, llama3.2, gemma-2-2b, mistral | API |

*Requiere API key (créditos gratuitos mensuales)

### Cost-Based Selection

El sistema selecciona automáticamente la IA más eficiente:

- **Tareas triviales** (comentarios, traducciones, resúmenes) → **gemini** (cost_level: 1)
- **Tareas de código** (implementación, refactoring) → **opencode** (cost_level: 2)
- **Análisis complejos** → **gemini** o **openrouter**
- **Fallback automático** si la IA primaria falla

### Configurar API Keys

```bash
# Editar .env
nano .env

# Agregar:
OPENROUTER_API_KEY="tu-api-key-de-openrouter"

# Los demás providers no necesitan API key
```

---

## 💾 cmx-memories (SQLite + FTS5)

### Comandos de Memoria

```bash
# Guardar memoria
./scripts/memory-save.sh <type> <title> <content> [project] [agent] [task_id]

# Consultar memorias
./cmx memories [project] [agent] [type] [limit]

# Buscar (FTS5 full-text)
./cmx search "query" [project] [type]

# Backup
./cmx backup
# Restore
./cmx restore <archivo-backup>
```

### Tipos de Memoria

| Tipo | Descripción |
|------|-------------|
| `decision` | Decisiones del orquestador |
| `synthesis` | Lecciones aprendidas |
| `task` | Tareas del proyecto |
| `note` | Notas generales |
| `bugfix` | Correcciones de bugs |
| `architecture` | Decisiones arquitectónicas |

---

## 🔧 Scripts Utilitarios

### Setup y Configuración

```bash
# Setup de AI providers
bash scripts/setup-ai-providers.sh

# Test de conectividad
bash scripts/test-ai-providers.sh

# Verificar entorno
./cmx env-check
```

### Base de Datos

```bash
# Inicializar DB SQLite
bash scripts/cmx-memories-init.sh

# Migrar JSON a SQLite
bash scripts/migrate-to-sqlite.sh

# Backup
bash scripts/backup-memories.sh

# Restore
bash scripts/restore-memories.sh <archivo>
```

### AI Execution

```bash
# Selector de IA (muestra qué IA se usaría)
bash scripts/ai-selector.sh <task-type>

# Ejecutor con retry automático
bash scripts/ai-executor.sh <ia> <task>
# Si falla, automáticamente intenta con la siguiente en fallback chain
```

---

## 📁 Estructura de Archivos

```
cmx-core/
├── brain.sh              # Cerebro principal
├── brain-adapter.sh     # Puente brain → pipeline
├── cmx                   # CLI principal
├── run.sh               # Pipeline SDD tradicional
├── memories.db           # Base de datos SQLite + FTS5
├── .env                 # Variables de entorno
│
├── agents/              # Agentes SDD
│   ├── explorer.sh
│   ├── proposer.sh
│   └── ...
│
├── orchestrator/        # Orquestación
│   ├── pipeline.sh
│   ├── brain-adapter.sh
│   └── monitor.sh
│
├── scripts/             # Scripts del sistema autónomo
│   ├── ai-selector.sh      # Selección con cost-awareness
│   ├── ai-executor.sh     # Ejecución con retry
│   ├── memory-save.sh     # Guardar en SQLite
│   ├── memory-query.sh    # Query + FTS5
│   ├── backup-memories.sh
│   ├── restore-memories.sh
│   └── migrate-to-sqlite.sh
│
├── config/
│   ├── ai-registry.json   # Registro de IAs (v3.0)
│   └── autonomy.yaml      # Niveles de autonomía
│
└── artifacts/           # Artefactos generados
    ├── exploration/
    ├── proposals/
    ├── specs/
    ├── designs/
    ├── tasks/
    ├── implementation/
    ├── verification/
    └── archive/
```

---

## ⚡ Referencia Rápida

### Comandos cmx CLI

```bash
./cmx task "descripción"        # Ejecutar tarea
./cmx status                   # Ver estado
./cmx list-ias                 # Listar IAs disponibles
./cmx env-check               # Verificar entorno
./cmx memories [filtros]      # Ver memorias
./cmx search "query"          # Buscar en memorias
./cmx init                    # Inicializar sistema
./cmx backup                  # Crear backup
./cmx restore <archivo>       # Restaurar backup
./cmx cleanup <proyecto>      # Cleanup post-proyecto
./cmx help                    # Ver ayuda
```

### Variables de Entorno

```bash
# Required para OpenRouter (opcional)
OPENROUTER_API_KEY=...

# No requiere configuración
# - OpenCode: modelos gratuitos incluidos
# - Gemini CLI: usa su propia autenticación
```

---

## 🔍 Solución de Problemas

### "No hay proveedores disponibles"

```bash
# Verificar que las IAs están disponibles
./cmx list-ias

# Ver entorno
./cmx env-check

# Test de conectividad
bash scripts/test-ai-providers.sh
```

### La base de datos no funciona

```bash
# Re-inicializar
bash scripts/cmx-memories-init.sh

# Restore desde backup
bash scripts/restore-memories.sh backups/memories_*.db.gz
```

### El pipeline no ejecuta

```bash
# Ver estado
./orchestrator/pipeline.sh status

# Resetear
./orchestrator/pipeline.sh reset
```

---

## 📊 Versiones

| Versión | Fecha | Cambios |
|---------|-------|---------|
| v2.1.0 | 2026-04-03 | SQLite + FTS5, brain-adapter, AI providers, cost-based selection |
| v1.3.1 | 2026-03-22 | Sistema autónomo básico |
| v1.0 | 2026-01-01 | Pipeline SDD |

---

*Manual generado para CMX-CORE v2.1.0*  
*https://github.com/Daniel-L10N/cmx-core*