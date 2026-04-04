# CMX-CORE - Sistema de Control Modular MX

> **v2.1.0** | Pipeline de desarrollo con Agentes de IA | Construye aplicaciones completas usando agentes especializados con supervisión humana.

---

## ¿Qué es CMX-CORE?

Es un **sistema de orquestación multi-agente** que te permite construir software usando IA de forma estructurada:

- 🔍 **Explora** ideas y requerimientos
- 🧠 **Cerebro autónomo** - sistema con memoria y selección inteligente de IA
- 📋 **Propone** soluciones técnicas
- 📝 **Especifica** requisitos exactos
- 🎨 **Diseña** la arquitectura
- ⚒️ **Implementa** en batches controlado
- ✅ **Verifica** cada paso
- 📦 **Archiva** el resultado

---

## Dos Modos de Uso

### Modo 1: Pipeline SDD Tradicional

El pipeline original de cmx-core para desarrollo estructurado:

```bash
cd cmx-core

# 1. Inicializar el workspace
./run.sh init

# 2. Ejecutar pipeline completo (con HITL)
./run.sh run mi-feature "crear una app de tareas con React"

# O ejecutar paso a paso:
./run.sh explore "autenticación JWT"
./run.sh propose
./run.sh spec
./run.sh design
./run.sh tasks
./run.sh apply 1
./run.sh verify 1
./run.sh archive
```

### Modo 2: Sistema Autónomo (NUEVO)

El nuevo sistema autónomo con cerebro propio:

```bash
cd cmx-core

# Inicializar memoria
./cmx init

# Ver estado
./cmx status

# Listar IAs disponibles
./cmx list-ias

# Ejecutar tarea con el cerebro
./cmx task "crear una API REST" --mode autonomous

# Ver decisiones del cerebro
./cmx memories cmx-core decision

# Cleanup post-proyecto (síntesis automática)
./cmx cleanup mi-proyecto
```

---

## Requisitos Previos

### Sistema Operativo
- Linux (Ubuntu 22.04+, Debian 11+, Fedora 38+)
- macOS (con Bash 4+)
- WSL2 (Windows Subsystem for Linux)

### Dependencias

| Paquete | Versión mínima | Para qué sirve |
|---------|---------------|----------------|
| `bash` | 4.0+ | Shell del sistema |
| `jq` | 1.6+ | Procesamiento JSON |
| `git` | 2.0+ | Control de versiones |
| `opencode` | latest | Motor de ejecución de agentes IA |

### Instalar dependencias

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y bash jq git curl

# Fedora/RHEL
sudo dnf install -y bash jq git curl

# macOS
brew install jq git curl
```

### Instalar OpenCode

```bash
# Instalación oficial
curl -sSL https://opencode.ai/install.sh | sh

# Verificar instalación
opencode --version
```

---

## Instalación en 3 Pasos

### 1. Clonar el repositorio

```bash
git clone https://github.com/Daniel-L10N/cmx-core.git
cd cmx-core
```

### 2. Verificar estructura

```bash
ls -la
# Debe mostrar:
# agents/   dag/   orchestrator/   schemas/   validators/
# run.sh    README.md   MANUAL.md
```

### 3. ¡Listo! 🚀

```bash
# Ver ayuda
./run.sh help

# Ver estado
./run.sh status
```

---

## Uso Rápido

### Flujo Completo de Desarrollo

```bash
cd cmx-core

# 1. Inicializar el workspace
./run.sh init

# 2. Ejecutar pipeline completo (con HITL)
./run.sh run mi-feature "crear una app de tareas con React"

# O ejecutar paso a paso:
./run.sh explore "autenticación JWT"
./run.sh propose
./run.sh spec
./run.sh design
./run.sh tasks
./run.sh apply 1
./run.sh verify 1
./run.sh archive
```

### Comandos Principales

| Comando | Descripción |
|---------|-------------|
| `./run.sh init` | Inicializar workspace |
| `./run.sh status` | Ver estado actual |
| `./run.sh run "nombre" "descripción"` | Ejecutar pipeline completo |
| `./run.sh explore "tema"` | Investigar un tema |
| `./run.sh validate <tipo> <archivo>` | Validar schema |
| `./run.sh reset` | Resetear pipeline |

---

## Arquitectura del Sistema

### Sistema Autónomo (Modo Nuevo)

```
┌─────────────────────────────────────────────────────────────────────┐
│                    CMX-CORE SISTEMA AUTÓNOMO                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐   │
│  │   Usuario    │────▶│   brain.sh   │────▶│ ai-selector.sh   │   │
│  │  (cualquier  │     │   (Cerebro)  │     │ (Selecciona IA) │   │
│  │    IA)       │     └──────────────┘     └────────┬─────────┘  │
│  └──────────────┘                                    │            │
│                                                      ▼            │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │              INYECTOR DE CONTEXTO (3 CAPAS)                  │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │ │
│  │  │  BASE       │→ │  PROYECTO   │→ │  TAREA (DAG)         │ │ │
│  │  │  prompts/   │  │  CONTEXT.md │  │  pipeline.sh         │ │ │
│  │  │  base.txt   │  │  AGENT.md   │  │  pasa al agente     │ │ │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘ │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                      │            │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────┐   │
│  │  Agentes     │◀────│  pipeline.sh │◀────│  agentes/         │   │
│  │  Existentes  │     │  (DAG exec)  │     │  (explorer, etc) │   │
│  └──────────────┘     └──────────────┘     └──────────────────┘   │
│                              │                                    │
│                              ▼                                    │
│  ┌──────────────────────────────────────────────────────────────┐ │
│  │                    CMX-MEMORIES                              │ │
│  │  ┌─────────────────────┐  ┌─────────────────────────────┐     │ │
│  │  │  Estado (decisiones)│  │  Síntesis (Lecciones)       │     │ │
│  │  │  project+agent+phase│  │  type: synthesis            │     │ │
│  │  │  durante proyecto  │  │  generado por IA            │     │ │
│  │  └─────────────────────┘  └─────────────────────────────┘     │ │
│  └──────────────────────────────────────────────────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Componentes del Sistema Autónomo

| Componente | Archivo | Descripción |
|-----------|---------|-------------|
| Cerebro | `brain.sh` | Orquestador central - analiza tareas, selecciona IA, delega |
| Adapter | `brain-adapter.sh` | Conecta brain con pipeline SDD - traduce decisiones en ejecución |
| Selector IA | `ai-selector.sh` | Selecciona la mejor IA basada en tipo de tarea |
| Memoria | `memories.db` | Base de datos de decisiones (SQLite + FTS5 backend) |
| Pre-flight | `check-environment.sh` | Valida API keys antes de ejecutar |
| CLI | `cmx` | Punto de entrada principal |
| Cleanup | `cleanup-project.sh` | Síntesis automática post-proyecto |

### IAs Registradas (v2.1.0)

| IA | Estado | Cost Level | Modelos | Best For |
|----|--------|------------|----------|-----------|
| opencode | ✅ available | 2 (gratis) | big-pickle, gpt-5-nano, etc. | implementation, coding |
| gemini | ✅ available | 1 (gratis) | gemini-2.0-flash | trivial tasks, analysis |
| openrouter | ✅ available | 1 (gratis) | deepseek, llama3.2, gemma | synthesis, fallback |
| ollama | ⚠️ offline | 5 (local) | llama3.2 | offline, privacy |

---

### Pipeline SDD (Modo Tradicional)

```
┌─────────────────────────────────────────────────────────────┐
│                    CMX-CORE PIPELINE                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐                │
│  │ EXPLORE │───▶│ PROPOSE │───▶│  SPEC   │                │
│  └─────────┘    └─────────┘    └─────────┘                │
│       │              │              │                       │
│       │              │              │                       │
│       ▼              ▼              ▼                       │
│  ┌─────────────────────────────────────────┐               │
│  │              HITL GATES                 │               │
│  │   (Aprobación humana requerida)        │               │
│  └─────────────────────────────────────────┘               │
│                       │                                      │
│       ┌───────────────┴───────────────┐                     │
│       ▼                               ▼                      │
│  ┌─────────┐                   ┌─────────┐                  │
│  │  DESIGN │                   │  TASKS  │                  │
│  └─────────┘                   └─────────┘                  │
│       │                               │                       │
│       └───────────────┬───────────────┘                     │
│                       ▼                                      │
│              ┌─────────────┐                                │
│              │    APPLY    │                                │
│              │  (batches)  │                                │
│              └─────────────┘                                │
│                       │                                      │
│                       ▼                                      │
│              ┌─────────────┐                                │
│              │   VERIFY    │                                │
│              └─────────────┘                                │
│                       │                                      │
│                       ▼                                      │
│              ┌─────────────┐                                │
│              │   ARCHIVE   │                                │
│              └─────────────┘                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Agentes Disponibles

| Agente | Función |
|--------|---------|
| `explorer.sh` | Investiga el tema y contexto |
| `proposer.sh` | Genera propuesta técnica |
| `spec-writer.sh` | Escribe especificación formal |
| `designer.sh` | Diseña arquitectura UI/UX |
| `task-planner.sh` | Planifica tareas de implementación |
| `implementer.sh` | Implementa código |
| `verifier.sh` | Verifica implementación |
| `archiver.sh` | Archiva y cierra el cambio |

---

## Estructura de Archivos

```
cmx-core/
├── agents/              # Scripts de agentes SDD
│   ├── explorer.sh
│   ├── proposer.sh
│   └── ...
├── orchestrator/        # Motor de orquestación
│   ├── pipeline.sh
│   ├── monitor.sh
│   ├── brain-adapter.sh     # ← NUEVO: conecta brain → pipeline
│   └── state.json
├── schemas/             # JSON Schemas de validación
├── dag/                 # Definición del DAG
├── validators/          # Validadores
├── config/               # Configuración del Sistema Autónomo
│   ├── ai-registry.json # Registro de IAs disponibles
│   ├── autonomy.yaml    # Niveles de autonomía
│   └── prompts/
│       └── base.txt     # Capa base de prompts
├── scripts/             # Scripts del Sistema Autónomo
│   ├── brain.sh         # Cerebro principal
│   ├── ai-selector.sh   # Selector de IA
│   ├── memory-save.sh   # Guardar decisiones (SQLite)
│   ├── memory-query.sh  # Consultar decisiones (FTS5)
│   ├── cmx-memories-init.sh  # Inicializar DB SQLite
│   ├── migrate-to-sqlite.sh  # Migración JSON→SQLite
│   ├── backup-memories.sh    # Backup DB
│   ├── restore-memories.sh   # Restore DB
│   ├── check-environment.sh  # Pre-flight check
│   └── cleanup-project.sh    # Síntesis automática
├── brain.sh             # Punto de entrada del cerebro
├── cmx                  # CLI principal del sistema autónomo
├── memories.db          # ← NUEVO: Base SQLite + FTS5
├── memories.json        # Original (backup)
├── artifacts/           # Artefactos generados
├── backups/             # ← NUEVO: Backups de DB
├── run.sh              # Punto de entrada SDD tradicional
├── README.md
└── MANUAL.md
```

---

## Sistema Autónomo - Guía Completa

### Primeros Pasos

```bash
# 1. Navegar al proyecto
cd cmx-core

# 2. Inicializar memoria cmx-memories
./cmx init

# 3. Ver estado del sistema
./cmx status

# 4. Listar IAs disponibles
./cmx list-ias
```

### Comandos del CLI cmx

```bash
# Ejecutar una tarea con el cerebro
./cmx task "crear una API REST con autenticación JWT" --mode autonomous
./cmx task "analizar el código existente" --mode hybrid

# Ver estado del sistema
./cmx status

# Listar IAs disponibles
./cmx list-ias

# Verificar entorno (API keys)
./cmx env-check

# Consultar memorias/decisiones
./cmx memories cmx-core decision
./cmx memories cmx-core synthesis

# Cleanup post-proyecto (síntesis automática)
./cmx cleanup mi-proyecto
```

### Opciones de tarea

| Opción | Descripción | Ejemplo |
|--------|-------------|---------|
| `--task` | Descripción de la tarea | `"crear una API REST"` |
| `--mode` | Nivel de autonomía | `manual`, `hybrid`, `autonomous` |
| `--project` | Nombre del proyecto | `cmx-core` |
| `--context` | Contexto adicional | `"usar TypeScript"` |

### Niveles de Autonomía

| Nivel | Descripción | Aprobaciones |
|-------|-------------|--------------|
| `manual` | Cada paso requiere aprobación humana | Todas las fases |
| `hybrid` | Solo decisiones críticas requieren aprobación | spec, design |
| `autonomous` | Opera de forma autónoma, reporta al final | Ninguna |

### Variables de Entorno Requeridas

Para que el sistema funcione completamente, configura estas variables:

```bash
# API Keys (agregar a ~/.bashrc o .env)
export OPENCOD_API_KEY="tu-api-key"
export GEMINI_API_KEY="tu-api-key"
export OPENROUTER_API_KEY="tu-api-key"

# Verificar que están configuradas
./cmx env-check
```

---

## Ejemplo: Crear una App (Modo Tradicional)

```bash
# 1. Navegar al proyecto
cd cmx-core

# 2. Inicializar
./run.sh init

# 3. Ejecutar con tu idea
./run.sh run mi-app "una app de notas con React y localStorage"

# 4. El sistema:
#    - Explorará la idea
#    - Propondrá arquitectura
#    - Escribirá specs
#    - Implementará en batches
#    - Verificará cada batch
#    - Te pide aprobación en cada HITL gate
```

---

## Configuración Opcional

### Alias útiles (agregar a ~/.bashrc)

```bash
# Modo SDD tradicional
alias cs='cd ~/cmx-core && ./run.sh'
alias cs-run='cd ~/cmx-core && ./run.sh run'
alias cs-status='cd ~/cmx-core && ./run.sh status'
alias cs-init='cd ~/cmx-core && ./run.sh init'

# Sistema Autónomo
alias cmx='cd ~/cmx-core && ./cmx'
alias cmx-task='cd ~/cmx-core && ./cmx task'
alias cmx-status='cd ~/cmx-core && ./cmx status'
```

### Variables de entorno

```bash
# Directorio de trabajo custom
export CMX_WORKSPACE=/tu/path/custom

# API Keys para el sistema autónomo
export OPENCOD_API_KEY="..."
export GEMINI_API_KEY="..."
export OPENROUTER_API_KEY="..."
```

---

## Estado del Proyecto

### ✅ v2.1.0 Completado

- Cerebro principal (`brain.sh`)
- CLI principal (`cmx`)
- Registro de IAs (`config/ai-registry.json`) - v3.0
- Niveles de autonomía (`config/autonomy.yaml`)
- Pre-flight check (`check-environment.sh`)
- cmx-memories (**SQLite + FTS5 backend**)
- ai-selector con cost-based selection
- ai-executor con retry/fallback automático
- Síntesis automática (`cleanup-project.sh`)
- brain-adapter.sh (conecta brain → pipeline)
- Scripts de backup/restore
- Setup de AI providers

### Características v2.1.0

| Feature | Descripción |
|---------|-------------|
| **SQLite Backend** | memories.db con FTS5 búsqueda full-text |
| **Cost-Based Selection** | Tareas triviales → gemini (cost 1) |
| **Retry Logic** | Fallback automático si IA falla |
| **3 AI Providers** | OpenCode, Gemini CLI, OpenRouter |
| **Backup/Restore** | Compresión + integrity check |

---

## Solución de Problemas

### "Command not found: jq"

```bash
# Ubuntu/Debian
sudo apt install jq

# Fedora
sudo dnf install jq

# macOS
brew install jq
```

### "Permission denied" en scripts

```bash
chmod +x run.sh agents/*.sh
```

### Ver logs

```bash
tail -f orchestrator/logs/*.log
```

### Resetear todo

```bash
./run.sh reset
```

---

## Tecnologías Soportadas

### Frontend
- React / Next.js
- Vue / Nuxt
- Svelte
- TypeScript
- Tailwind CSS

### Backend
- Node.js / Express
- Python / Django / FastAPI
- Go
- Rust

### Bases de Datos
- PostgreSQL
- MySQL
- SQLite
- MongoDB

---

## Contribuir

1. Fork del repo
2. Crear branch: `git checkout -b feature/nueva-funcionalidad`
3. Commit: `git commit -m "feat: agregar nueva funcionalidad"`
4. Push: `git push origin feature/nueva-funcionalidad`
5. Abrir Pull Request

---

## Licencia

MIT License - Daniel-L10N

---

## Links

- 📦 **Repositorio**: https://github.com/Daniel-L10N/cmx-core
- 📖 **Documentación**: Ver `MANUAL.md` para guía detallada
- 🐛 **Issues**: https://github.com/Daniel-L10N/cmx-core/issues

---

*¡Construye más, codifica menos!*
