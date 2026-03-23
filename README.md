# CMX-CORE - Sistema de Control Modular MX

> **Pipeline de desarrollo con Agentes de IA**  
> Construye aplicaciones completas usando agentes especializados con supervisión humana.

---

## ¿Qué es CMX-CORE?

Es un **sistema de orquestación multi-agente** que te permite construir software usando IA de forma estructurada:

- 🔍 **Explora** ideas y requerimientos
- 📋 **Propone** soluciones técnicas
- 📝 **Especifica** requisitos exactos
- 🎨 **Diseña** la arquitectura
- ⚒️ **Implementa** en batches controlado
- ✅ **Verifica** cada paso
- 📦 **Archiva** el resultado

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
├── agents/              # Scripts de agentes
│   ├── explorer.sh
│   ├── proposer.sh
│   └── ...
├── orchestrator/        # Motor de orquestación
│   ├── pipeline.sh
│   ├── monitor.sh
│   └── state.json
├── schemas/             # JSON Schemas de validación
├── dag/                 # Definición del DAG
├── validators/          # Validadores
├── artifacts/           # Artefactos generados
│   ├── exploration/
│   ├── proposals/
│   ├── specs/
│   ├── designs/
│   ├── tasks/
│   ├── implementation/
│   ├── verification/
│   └── archive/
├── run.sh              # Punto de entrada único
└── README.md
```

---

## Ejemplo: Crear una App

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
alias cs='cd ~/cmx-core && ./run.sh'
alias cs-run='cd ~/cmx-core && ./run.sh run'
alias cs-status='cd ~/cmx-core && ./run.sh status'
alias cs-init='cd ~/cmx-core && ./run.sh init'
```

### Variables de entorno

```bash
# Opcional: Directorio de trabajo custom
export CMX_WORKSPACE=/tu/path/custom
```

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
