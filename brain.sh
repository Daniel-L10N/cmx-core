#!/bin/bash
# Brain - Cerebro principal del sistema autónomo cmx-core
# Uso: brain.sh --task "descripción" [--mode autonomous|hybrid|manual] [--context "contexto"] [--project <name>]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"

# Scripts
CHECK_ENV="$PROJECT_ROOT/scripts/check-environment.sh"
AI_SELECTOR="$PROJECT_ROOT/scripts/ai-selector.sh"
MEMORY_SAVE="$PROJECT_ROOT/scripts/memory-save.sh"

# Configs
REGISTRY_FILE="$PROJECT_ROOT/config/ai-registry.json"
AUTONOMY_FILE="$PROJECT_ROOT/config/autonomy.yaml"
PROMPT_BASE="$PROJECT_ROOT/config/prompts/base.txt"
CONTEXT_FILE="$PROJECT_ROOT/CONTEXT.md"
AGENT_FILE="$PROJECT_ROOT/AGENT.md"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default values
MODE="hybrid"
PROJECT="cmx-core"
TASK=""
CONTEXT=""
TASK_ID="task-$(date +%s)"

log() { echo -e "${BLUE}[BRAIN]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        --task)
            TASK="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --context)
            CONTEXT="$2"
            shift 2
            ;;
        --project)
            PROJECT="$2"
            shift 2
            ;;
        --task-id)
            TASK_ID="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$TASK" ]; then
    echo "Uso: brain.sh --task \"descripción\" [--mode autonomous|hybrid|manual] [--context \"contexto\"] [--project <name>]"
    echo ""
    echo "Opciones:"
    echo "  --task       Descripción de la tarea (requerido)"
    echo "  --mode       Nivel de autonomía: manual, hybrid, autonomous (default: hybrid)"
    echo "  --context    Contexto adicional para la tarea"
    echo "  --project    Nombre del proyecto (default: cmx-core)"
    echo "  --task-id    ID único de la tarea (auto-generado si no se provee)"
    exit 1
fi

log "Iniciando cerebro para proyecto: $PROJECT"
log "Tarea: $TASK"
log "Modo: $MODE"

# 1. Pre-flight check
log "Ejecutando check de entorno..."
CHECK_RESULT=$("$CHECK_ENV" --strict 2>&1) || true
echo "$CHECK_RESULT" | head -5

# Extraer status del check
CHECK_STATUS=$(echo "$CHECK_RESULT" | jq -r '.status' 2>/dev/null || echo "unknown")

if [ "$CHECK_STATUS" = "error" ]; then
    log_error "Check de entorno falló. Abortando."
    exit 1
fi

# Guardar decisión de entorno
"$MEMORY_SAVE" "decision" "environment-check" \
    "Check de entorno: $CHECK_STATUS" \
    "$PROJECT" "brain" "$TASK_ID" "initialization"

# 2. Analizar tarea - clasificar tipo
log "Analizando tarea..."
TASK_LOWER=$(echo "$TASK" | tr '[:upper:]' '[:lower:]')

if echo "$TASK_LOWER" | grep -qE "(crear|implementar|escribir|codificar|build|make|add|new|function|api|endpoint|component)"; then
    TASK_TYPE="coding"
elif echo "$TASK_LOWER" | grep -qE "(analizar|revisar|debug|error|bug|investigar|examinar|review)"; then
    TASK_TYPE="analysis"
elif echo "$TASK_LOWER" | grep -qE "(buscar|investigar|research|document|explorar)"; then
    TASK_TYPE="research"
else
    TASK_TYPE="general"
fi

log "Tipo de tarea detectado: $TASK_TYPE"

# 3. Seleccionar IA
log "Seleccionando IA óptima..."
SELECTION=$("$AI_SELECTOR" "$TASK_TYPE" "$PROJECT" 2>/dev/null)
SELECTED_IA=$(echo "$SELECTION" | jq -r '.ia' 2>/dev/null || echo "opencode")
SELECTION_REASON=$(echo "$SELECTION" | jq -r '.reason' 2>/dev/null || echo "default")

log_ok "IA seleccionada: $SELECTED_IA"

# Guardar decisión de selección
"$MEMORY_SAVE" "decision" "ia-selection" \
    "Seleccionado $SELECTED_IA para tarea tipo '$TASK_TYPE'. Razón: $SELECTION_REASON" \
    "$PROJECT" "ai-selector" "$TASK_ID" "selection"

# 4. Obtener configuración de autonomía
HITL_GATES=$(jq -r ".levels.\"$MODE\".hitl_gates // [] | join(\", \")" "$AUTONOMY_FILE" 2>/dev/null || echo "")
log "HITL gates para modo '$MODE': $HITL_GATES"

# 5. Inyector de contexto de 3 capas
log "Construyendo contexto de 3 capas..."

# Capa 1: Base (genérica)
CONTEXT_LAYER_1=$(cat "$PROMPT_BASE" 2>/dev/null || echo "# Sistema Base\nEres cmx-core.")

# Capa 2: Proyecto (específica)
CONTEXT_LAYER_2=""
if [ -f "$CONTEXT_FILE" ]; then
    CONTEXT_LAYER_2=$(cat "$CONTEXT_FILE")
fi
if [ -f "$AGENT_FILE" ]; then
    CONTEXT_LAYER_2="$CONTEXT_LAYER_2\n\n$(cat "$AGENT_FILE")"
fi

# Capa 3: Tarea (dinámica)
CONTEXT_LAYER_3="## Tarea Actual
Tarea: $TASK
Tipo: $TASK_TYPE
Proyecto: $PROJECT
Contexto adicional: ${CONTEXT:-ninguno}
Modo de autonomía: $MODE"

# Combinar capas
FULL_CONTEXT="$CONTEXT_LAYER_1

---

$CONTEXT_LAYER_2

---

$CONTEXT_LAYER_3"

# Guardar contexto generado
echo "$FULL_CONTEXT" > "$PROJECT_ROOT/artifacts/context-${TASK_ID}.txt"

log_ok "Contexto preparado"

# 6. Ejecutar la tarea con la IA seleccionada
log "Ejecutando tarea con $SELECTED_IA..."

case "$SELECTED_IA" in
    opencode)
        # Usar opencode para ejecutar la tarea
        RESPONSE=$(opencode run "$TASK" 2>&1) || true
        ;;
    gemini)
        # Usar gemini CLI
        RESPONSE=$(gemini "$TASK" 2>&1) || true
        ;;
    openrouter)
        # Usar openrouter (asumiendo agente configurado)
        RESPONSE=$(openrouter "$TASK" 2>&1) || true
        ;;
    *)
        RESPONSE="IA $SELECTED_IA no implementada aún"
        ;;
esac

# 7. Guardar resultado
"$MEMORY_SAVE" "decision" "task-execution" \
    "Tarea '$TASK' ejecutada con $SELECTED_IA. Respuesta: ${RESPONSE:0:200}..." \
    "$PROJECT" "brain" "$TASK_ID" "execution"

# 8. Output final
log_ok "Tarea completada"

echo ""
echo "========================================="
echo "RESULTADO"
echo "========================================="
echo "{"
echo "  \"status\": \"completed\","
echo "  \"task_id\": \"$TASK_ID\","
echo "  \"project\": \"$PROJECT\","
echo "  \"task_type\": \"$TASK_TYPE\","
echo "  \"ia_used\": \"$SELECTED_IA\","
echo "  \"mode\": \"$MODE\","
echo "  \"hitl_gates\": \"$HITL_GATES\","
echo "  \"timestamp\": \"$(date -Iseconds)\""
echo "}"
echo ""
echo "Respuesta de la IA:"
echo "$RESPONSE"
echo ""
echo "========================================="