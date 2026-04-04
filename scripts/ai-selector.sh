#!/bin/bash
# AI Selector — Wrapper de compatibilidad (v2.3.0)
# Delega a la implementación Python (lib/ai_selector.py)
# Mantiene la misma interfaz CLI que la versión bash original.
#
# Uso: ai-selector.sh <task-type> [project]
# Si Python no está disponible, fallback a la implementación bash original.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_SELECTOR="$PROJECT_ROOT/lib/ai_selector.py"
BASH_SELECTOR="$PROJECT_ROOT/scripts/ai-selector.bash.bak"

TASK_TYPE="${1:-general}"
PROJECT="${2:-cmx-core}"

# Intentar usar la versión Python primero
if command -v python3 >/dev/null 2>&1 && [ -f "$PYTHON_SELECTOR" ]; then
    exec python3 "$PYTHON_SELECTOR" "$TASK_TYPE" "$PROJECT"
fi

# Fallback: si no hay Python, verificar si guardamos el bash original
if [ -f "$BASH_SELECTOR" ]; then
    exec bash "$BASH_SELECTOR" "$TASK_TYPE" "$PROJECT"
fi

# Último recurso: error
echo '{"error": "Python3 no disponible y no hay fallback bash", "ia": null}'
exit 1
