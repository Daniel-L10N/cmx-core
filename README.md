# CMX-CORE — Sistema Autónomo Multi-Agente

> **v2.3.0** | Orquestación de IA con memoria, pipelines SDD y selección inteligente de modelos | 138 tests automatizados

[![Test Suite](https://github.com/Daniel-L10N/cmx-core/actions/workflows/test.yml/badge.svg)](https://github.com/Daniel-L10N/cmx-core/actions/workflows/test.yml)
![Bash](https://img.shields.io/badge/Bash-4.0%2B-blue)
![Python](https://img.shields.io/badge/Python-3.10%2B-green)
![Tests](https://img.shields.io/badge/Tests-138-brightgreen)
![License](https://img.shields.io/badge/License-MIT-yellow)

---

## ¿Qué es CMX-CORE?

Un **sistema de orquestación multi-agente** que construye software usando IA de forma estructurada, con memoria persistente, selección inteligente de modelos y pipelines automatizados.

- 🧠 **Cerebro autónomo** — Analiza tareas, selecciona la IA óptima por costo/capacidad
- 📋 **Pipeline SDD** — Spec → Design → Tasks → Implementation → Verification
- 💾 **Memoria persistente** — SQLite + FTS5 con búsqueda full-text
- 🔄 **Selección inteligente** — Elige automáticamente entre OpenCode, Gemini, OpenRouter
- 📊 **Observabilidad** — Logging centralizado, métricas, monitoreo en tiempo real
- 🔒 **Seguro** — SQL injection prevention, file locking, timeouts, validación de inputs
- 🔌 **Extensible** — Sistema de plugins con hooks

---

## Instalación

### Requisitos

| Paquete | Versión | Para qué |
|---------|---------|----------|
| `bash` | 4.0+ | Shell del sistema |
| `jq` | 1.6+ | Procesamiento JSON |
| `sqlite3` | 3.35+ | Base de datos + FTS5 |
| `python3` | 3.10+ | AI Selector + tests |
| `git` | 2.0+ | Control de versiones |
| `opencode` | latest | Motor de ejecución IA (opcional) |

### Paso 1: Clonar

```bash
git clone https://github.com/Daniel-L10N/cmx-core.git
cd cmx-core
```

### Paso 2: Instalar dependencias

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install -y bash jq sqlite3 python3 python3-pip git

# Fedora/RHEL
sudo dnf install -y bash jq sqlite3 python3 python3-pip git

# macOS
brew install bash jq sqlite3 python3 git
pip3 install pytest
```

### Paso 3: Verificar

```bash
# Ejecutar tests (deben pasar 119/120+)
bash tests/test-security.sh

# Tests Python (deben pasar 19/19)
python3 -m pytest tests/test_ai_selector.py -v
```

### Paso 4: Inicializar

```bash
# Inicializar memoria SQLite
./cmx init

# Ver estado
./cmx status

# Verificar entorno
./cmx env-check
```

### Paso 5 (Opcional): Configurar IAs

Copia el archivo de ejemplo y agrega tus API keys:

```bash
cp .env.example .env
nano .env  # Agrega tus API keys
```

El sistema funciona con **opencode** instalado. Gemini CLI y OpenRouter son opcionales (fallback automático).

---

## Uso Rápido

### Nivel 1: CLI (tareas simples)

```bash
# Ejecutar una tarea
./cmx task "crear una función que valide emails"

# Con modo autónomo (sin preguntas)
./cmx task "crear endpoint de health check" --mode autonomous

# Con proyecto y contexto
./cmx task "crear componente de tabla" \
    --project mi-app \
    --context "Usar React + TypeScript + Tailwind"

# Consultar memoria
./cmx memories mi-app decision           # Ver decisiones
./cmx search "autenticación" mi-app      # Búsqueda full-text

# Administración
./cmx status                             # Estado del sistema
./cmx list-ias                           # IAs disponibles
./cmx env-check                          # Verificar entorno
./cmx backup                             # Backup de la DB
./cmx cleanup mi-app                     # Cleanup post-proyecto
```

### Nivel 2: Cerebro Directo

```bash
# Ejecutar con control total
./brain.sh --task "implementar sistema de login JWT" \
    --mode hybrid \
    --project api-backend

# Con contexto adicional
./brain.sh --task "analizar vulnerabilidades" \
    --context "Revisar auth, SQL injection, XSS" \
    --mode autonomous

# Ver logs en tiempo real
tail -f logs/cmx-$(date +%Y%m%d).log

# Ver métricas
source lib/metrics.sh && metrics_init "mi-app" && metrics_report
```

### Nivel 3: Pipeline SDD (features complejas)

```bash
# Pipeline autónomo completo
./brain.sh --task "implementar sistema de autenticación JWT" \
    --mode autonomous --project api-backend

# Monitorear el pipeline
./orchestrator/monitor.sh --once    # Estado actual
./orchestrator/monitor.sh           # Monitoreo continuo

# Parar todo
./orchestrator/stop-all.sh
```

---

## Guía de Uso Completa

### Comandos del CLI `cmx`

| Comando | Descripción |
|---------|-------------|
| `cmx task "..."` | Ejecutar tarea con el cerebro |
| `cmx task "..." --mode autonomous` | Sin aprobación humana |
| `cmx task "..." --project nombre` | Proyecto específico |
| `cmx memories [proyecto] [tipo]` | Consultar memorias |
| `cmx search "query" [proyecto]` | Búsqueda full-text (FTS5) |
| `cmx status` | Estado del sistema |
| `cmx list-ias` | IAs registradas y su estado |
| `cmx env-check` | Verificar API keys y entorno |
| `cmx init` | Inicializar memoria SQLite |
| `cmx backup` | Crear backup de la DB |
| `cmx restore <archivo>` | Restaurar desde backup |
| `cmx cleanup <proyecto>` | Síntesis + cleanup post-proyecto |
| `cmx help` | Ayuda completa |

### Niveles de Autonomía

| Nivel | Descripción | Aprobaciones |
|-------|-------------|--------------|
| `manual` | Cada paso requiere aprobación | Todas las fases |
| `hybrid` | Solo decisiones críticas | spec, design |
| `autonomous` | Opera solo, reporta al final | Ninguna |

### Observabilidad

```bash
# Logs (JSON lines, parseable)
tail -f logs/cmx-$(date +%Y%m%d).log

# Modo DEBUG
CMX_LOG_LEVEL=0 ./brain.sh --task "..."

# Métricas del día
source lib/metrics.sh
metrics_init "cmx-core"
metrics_report              # Resumen formateado
metrics_report_json         # Output JSON

# Cache de contexto
source lib/context-cache.sh
context_cache_init "/path/to/cmx-core"
context_cache_stats         # Stats del cache
context_cache_invalidate    # Forzar re-cache
```

### Plugins

```bash
source lib/plugins.sh
plugins_init "/path/to/cmx-core"

# Registrar plugin
plugins_register "mi-notifier" "/path/to/notifier.sh" "Notificaciones Slack"

# Gestionar
plugins_list
plugins_disable "mi-notifier"
plugins_enable "mi-notifier"
plugins_unregister "mi-notifier"
```

### Tests

```bash
# Suite completa (120 tests bash + 19 Python)
bash tests/test-security.sh
python3 -m pytest tests/test_ai_selector.py -v

# Por categoría
bash tests/test-security.sh sql        # SQL injection
bash tests/test-security.sh timeout    # Timeouts
bash tests/test-security.sh logger     # Logging
bash tests/test-security.sh syntax     # Syntax check
```

---

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────┐
│                        CMX-CORE v2.3.0                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Usuario ──▶ cmx CLI ──▶ brain.sh (Cerebro)                    │
│                              │                                  │
│              ┌───────────────┼───────────────┐                 │
│              ▼               ▼               ▼                  │
│        ai-selector     context-cache    lib/logger.sh           │
│        (Python)        (hash-based)     lib/metrics.sh          │
│              │                              │                   │
│              ▼                              ▼                   │
│  ┌───────────────────┐          ┌──────────────────────┐       │
│  │  pipeline.sh      │          │  memories.db         │       │
│  │  (DAG + state     │          │  (SQLite + FTS5)     │       │
│  │   locking)        │          │                      │       │
│  └────────┬──────────┘          └──────────────────────┘       │
│           │                                                     │
│           ▼                                                     │
│  ┌───────────────────────────────────────────────────┐         │
│  │  agents/                                           │         │
│  │  explorer → proposer → spec → design → tasks      │         │
│  │  → implementer (AI Selector) → verifier → archiver │         │
│  └───────────────────────────────────────────────────┘         │
│                                                                 │
│  lib/plugins.sh ──▶ Sistema de plugins extensible              │
│  lib/state-lock.sh ──▶ File locking (flock + mkdir fallback)   │
│  lib/agent-ai.sh ──▶ Wrapper AI para agentes                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Componentes

| Componente | Archivo | Descripción |
|-----------|---------|-------------|
| CLI | `cmx` | Punto de entrada principal |
| Cerebro | `brain.sh` | Analiza, selecciona IA, delega |
| AI Selector | `lib/ai_selector.py` | Selección inteligente (Python) |
| Pipeline | `orchestrator/pipeline.sh` | DAG engine + state locking |
| Monitor | `orchestrator/monitor.sh` | UI de monitoreo en terminal |
| Logger | `lib/logger.sh` | Logging centralizado |
| Metrics | `lib/metrics.sh` | Métricas de ejecución |
| Memoria | `memories.db` | SQLite + FTS5 full-text search |
| Context Cache | `lib/context-cache.sh` | Cache con hash invalidation |
| State Lock | `lib/state-lock.sh` | File locking (flock + mkdir) |
| Agent AI | `lib/agent-ai.sh` | Wrapper AI Selector para agentes |
| Plugins | `lib/plugins.sh` | Sistema de plugins con hooks |

### IAs Soportadas

| IA | Tipo | Costo | Mejor para |
|----|------|-------|------------|
| **OpenCode** | CLI | Gratis | Implementation, coding |
| **Gemini CLI** | CLI | Gratis | Tareas triviales, análisis |
| **OpenRouter** | API | Variable | Síntesis, fallback |
| **Ollama** | CLI local | Local | Offline, privacidad |

---

## Estructura del Proyecto

```
cmx-core/
├── cmx                         # CLI principal
├── brain.sh                    # Cerebro autónomo
├── run.sh                      # Pipeline SDD tradicional
│
├── lib/                        # ← Bibliotecas reutilizables (v2.2.0+)
│   ├── logger.sh               # Logging centralizado
│   ├── metrics.sh              # Métricas de ejecución
│   ├── ai_selector.py          # AI Selector (Python)
│   ├── agent-ai.sh             # Wrapper AI para agentes
│   ├── state-lock.sh           # File locking
│   ├── context-cache.sh        # Cache de contexto
│   └── plugins.sh              # Sistema de plugins
│
├── scripts/                    # Scripts del sistema autónomo
│   ├── ai-selector.sh          # Wrapper → Python delegation
│   ├── ai-executor.sh          # Ejecutor con retry/fallback
│   ├── memory-save.sh          # Guardar en SQLite (SQL-safe)
│   ├── memory-query.sh         # Consultar con FTS5
│   ├── cleanup-project.sh      # Síntesis post-proyecto
│   ├── check-environment.sh    # Pre-flight check
│   ├── backup-memories.sh      # Backup DB
│   ├── restore-memories.sh     # Restore DB
│   └── cmx-memories-init.sh    # Inicializar SQLite
│
├── orchestrator/               # Motor de orquestación
│   ├── pipeline.sh             # DAG engine + state locking
│   ├── brain-adapter.sh        # Conecta brain → pipeline
│   ├── monitor.sh              # UI de monitoreo
│   ├── agent-comm.sh           # Comunicación entre agentes
│   └── summary.sh              # Resúmenes HITL
│
├── agents/                     # Agentes SDD
│   ├── explorer.sh             # Explora codebase
│   ├── implementer.sh          # Implementa código (con AI Selector)
│   └── ...                     # proposer, spec, design, tasks, etc.
│
├── config/                     # Configuración
│   ├── ai-registry.json        # Registro de IAs
│   ├── autonomy.yaml           # Niveles de autonomía
│   └── prompts/base.txt        # Prompt base
│
├── tests/                      # Tests automatizados
│   ├── test-security.sh        # 120 tests bash
│   └── test_ai_selector.py     # 19 tests Python
│
├── .github/workflows/          # CI/CD
│   └── test.yml                # GitHub Actions
│
└── artifacts/                  # Artefactos generados por el pipeline
```

---

## Flujo de Trabajo Típico

```bash
# 1. Verificar que todo está bien
cmx env-check && cmx status

# 2. Ejecutar una tarea
cmx task "crear endpoint de health check" --project mi-api

# 3. Revisar qué se hizo
cmx memories mi-api decision
cmx search "health check" mi-api

# 4. Ver métricas
source lib/metrics.sh && metrics_init "mi-api" && metrics_report

# 5. Cuando termines el proyecto
cmx cleanup mi-api    # Sintetiza lecciones y limpia
```

---

## Alias Útiles

Agrega a tu `~/.bashrc`:

```bash
# CMX-CORE
alias cmx='cd ~/cmx-core && ./cmx'
alias cmx-task='cd ~/cmx-core && ./cmx task'
alias cmx-status='cd ~/cmx-core && ./cmx status'
alias cmx-logs='tail -f ~/cmx-core/logs/cmx-$(date +%Y%m%d).log'
alias cmx-metrics='cd ~/cmx-core && source lib/metrics.sh && metrics_init "cmx-core" && metrics_report'
alias cmx-test='cd ~/cmx-core && bash tests/test-security.sh'
```

---

## Solución de Problemas

| Problema | Solución |
|----------|----------|
| `jq: command not found` | `sudo apt install jq` |
| `sqlite3: command not found` | `sudo apt install sqlite3` |
| `Permission denied` | `chmod +x cmx brain.sh scripts/*.sh` |
| IA no responde | Los timeouts están configurados (5min/3min/2min) |
| Error de memoria | `./cmx init` para reinicializar SQLite |
| Algo se rompió | `bash tests/test-security.sh` para diagnosticar |

---

## Changelog

### v2.3.0 — Production Ready
- CI/CD con GitHub Actions
- AI Selector migrado a Python (19 tests unitarios)
- Wrapper bash con fallback automático

### v2.2.0 — Quality & Observability
- Logging centralizado (lib/logger.sh)
- Métricas de ejecución (lib/metrics.sh)
- Agent AI Wrapper (lib/agent-ai.sh)
- State Locking con flock (lib/state-lock.sh)
- Context Cache (lib/context-cache.sh)
- Plugin System (lib/plugins.sh)
- 120 tests bash automatizados

### v2.1.1 — Security Hardening
- SQL Injection prevention (4 capas)
- Timeouts en todas las ejecuciones de IA
- Fix: cleanup-project.sh (JSON → SQLite)
- Fix: variable CLEANUP no definida en CLI

### v2.1.0 — SQLite + FTS5
- Migración de JSON a SQLite
- Búsqueda full-text con FTS5
- brain-adapter.sh
- Cost-based AI selection
- Backup/Restore

---

## Contribuir

1. Fork del repo
2. Crear branch: `git checkout -b feature/nueva-funcionalidad`
3. Commit: `git commit -m "feat: agregar nueva funcionalidad"`
4. **Ejecutar tests**: `bash tests/test-security.sh && python3 -m pytest tests/test_ai_selector.py -v`
5. Push y abrir Pull Request

---

## Licencia

MIT License — Daniel-L10N

---

## Links

- 📦 **Repo**: https://github.com/Daniel-L10N/cmx-core
- 📖 **Manual**: Ver `MANUAL.md`
- 🐛 **Issues**: https://github.com/Daniel-L10N/cmx-core/issues

---

*¡Construye más, codifica menos!*
