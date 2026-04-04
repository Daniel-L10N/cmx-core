#!/bin/bash
# AI Selector - Selecciona la mejor IA basada en tipo de tarea, costo y disponibilidad
# Uso: ai-selector.sh <task-type> [project] [--cost-aware] [--fallback]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_FILE="$PROJECT_ROOT/config/ai-registry.json"
MEMORY_SCRIPT="$PROJECT_ROOT/scripts/memory-query.sh"

# Cargar .env si existe
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

TASK_TYPE="${1:-general}"
PROJECT="${2:-cmx-core}"
COST_AWARE=true

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log_select() { echo -e "${BLUE}[SELECT]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_fallback() { echo -e "${YELLOW}[FALLBACK]${NC} $1"; }

# ============================================================================
# FUNCIONES AUXILIARES
# ============================================================================

# Verificar si una IA está disponible
is_ia_available() {
    local ia="$1"
    local status=$(jq -r ".ias.\"$ia\".status" "$REGISTRY_FILE" 2>/dev/null || echo "unavailable")
    
    if [ "$status" != "available" ]; then
        return 1
    fi
    
    # Verificar tipo de IA
    local ia_type=$(jq -r ".ias.\"$ia\".type" "$REGISTRY_FILE" 2>/dev/null || echo "cli")
    
    case "$ia_type" in
        cli|cli-direct)
            local command=$(jq -r ".ias.\"$ia\".command" "$REGISTRY_FILE" 2>/dev/null)
            command -v "$command" >/dev/null 2>&1
            ;;
        api)
            local requires_env=$(jq -r ".ias.\"$ia\".requires_env // [] | .[]" "$REGISTRY_FILE" 2>/dev/null || echo "")
            if [ -n "$requires_env" ]; then
                local var_value="${!requires_env}"
                [ -n "$var_value" ]
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

# Obtener nivel de costo de una IA
get_cost_level() {
    local ia="$1"
    jq -r ".ias.\"$ia\".cost_level // 3" "$REGISTRY_FILE" 2>/dev/null || echo "3"
}

# Detectar si una tarea es trivial (para selección por costo)
is_task_trivial() {
    local task="$1"
    local trivial_keywords=$(jq -r '.cost_based_selection.trivial_task_keywords | join("|")' "$REGISTRY_FILE" 2>/dev/null || echo "")
    
    echo "$task" | grep -qiE "$trivial_keywords"
}

# ============================================================================
# SELECCIÓN PRINCIPAL
# ============================================================================

# Verificar que el registry existe
if [ ! -f "$REGISTRY_FILE" ]; then
    echo "{\"error\": \"Registry not found\", \"ia\": \"opencode\", \"fallback\": null}"
    exit 1
fi

# Análisis de trivialidad de la tarea
TASK_INPUT="$TASK_TYPE"
if is_task_trivial "$TASK_TYPE"; then
    log_select "Tarea trivial detectada - priorizando eficiencia de costo"
    TASK_TYPE="trivial"
fi

# Obtener reglas de selección
SELECTION_RULES=$(jq -r ".selection_rules.\"$TASK_TYPE\" // .selection_rules.general" "$REGISTRY_FILE")
IAS_PREFERRED=$(echo "$SELECTION_RULES" | jq -r '.[]' 2>/dev/null || echo "opencode")

# Consultar decisiones previas
PREVIOUS_DECISIONS=$("$MEMORY_SCRIPT" "$PROJECT" "" "decision" 10 2>/dev/null | jq -r 'length' || echo "0")

# ============================================================================
# SELECCIÓN CON FALLBACK CHAIN
# ============================================================================

SELECTED_IA=""
FALLBACK_CHAIN=()
REASON=""

# Intentar cada IA en orden de prioridad
while IFS= read -r ia; do
    [ -z "$ia" ] && continue
    
    log_select "Evaluando: $ia..."
    
    if is_ia_available "$ia"; then
        SELECTED_IA="$ia"
        
        # Obtener información de la IA
        CAPABILITIES=$(jq -r ".ias.\"$ia\".capabilities | join(\", \")" "$REGISTRY_FILE" 2>/dev/null || echo "general")
        BEST_FOR=$(jq -r ".ias.\"$ia\".best_for | join(\", \")" "$REGISTRY_FILE" 2>/dev/null || echo "general")
        COST_LEVEL=$(get_cost_level "$ia")
        COST_DESC=$(jq -r ".ias.\"$ia\".cost_description" "$REGISTRY_FILE" 2>/dev/null || echo "")
        MODEL=$(jq -r ".ias.\"$ia\".default_model" "$REGISTRY_FILE" 2>/dev/null || echo "")
        
        # Generar razón de selección
        if [ "$TASK_TYPE" = "trivial" ]; then
            REASON="Tarea trivial - seleccionado $ia por eficiencia (coste level $COST_LEVEL)"
        else
            REASON="Seleccionado $ia para tarea '$TASK_TYPE' - óptimo para: $BEST_FOR"
        fi
        
        [ -n "$COST_DESC" ] && REASON="$REASON. Costo: $COST_DESC"
        
        log_select "✓ $ia seleccionado (cost_level: $COST_LEVEL)"
        break
    else
        log_warn "✗ $ia no disponible - agregando a fallback"
        FALLBACK_CHAIN+=("$ia")
    fi
done <<< "$IAS_PREFERRED"

# ============================================================================
# FALLBACK SI NADA ESTÁ DISPONIBLE
# ============================================================================

if [ -z "$SELECTED_IA" ]; then
    # Obtener retry config
    MAX_RETRIES=$(jq -r '.retry_config.max_retries // 2' "$REGISTRY_FILE" 2>/dev/null || echo "2")
    
    # Intentar fallback de emergencia
    if command -v opencode >/dev/null 2>&1; then
        SELECTED_IA="opencode"
        MODEL=$(jq -r ".ias.opencode.default_model" "$REGISTRY_FILE" 2>/dev/null || echo "opencode/big-pickle")
        REASON="Fallback de emergencia - usando OpenCode"
        log_fallback "Usando fallback: opencode"
    elif command -v gemini >/dev/null 2>&1; then
        SELECTED_IA="gemini"
        MODEL=$(jq -r ".ias.gemini.default_model" "$REGISTRY_FILE" 2>/dev/null || echo "gemini-2.0-flash")
        REASON="Fallback de emergencia - usando Gemini CLI"
        log_fallback "Usando fallback: gemini"
    else
        echo "{\"error\": \"No hay proveedores AI disponibles\", \"ia\": null, \"fallback\": null}"
        exit 1
    fi
    
    COST_LEVEL=$(get_cost_level "$SELECTED_IA")
    CAPABILITIES=$(jq -r ".ias.\"$SELECTED_IA\".capabilities | join(\", \")" "$REGISTRY_FILE" 2>/dev/null || echo "general")
    BEST_FOR=$(jq -r ".ias.\"$SELECTED_IA\".best_for | join(\", \")" "$REGISTRY_FILE" 2>/dev/null || echo "general")
fi

# ============================================================================
# OUTPUT JSON
# ============================================================================

if [ "$PREVIOUS_DECISIONS" -gt 0 ]; then
    REASON="$REASON (proyecto tiene $PREVIOUS_DECISIONS decisiones previas)"
fi

echo "{"
echo "  \"status\": \"selected\","
echo "  \"task_type\": \"$TASK_TYPE\","
echo "  \"original_task\": \"$TASK_INPUT\","
echo "  \"ia\": \"$SELECTED_IA\","
echo "  \"model\": \"$MODEL\","
echo "  \"cost_level\": $COST_LEVEL,"
echo "  \"reason\": \"$REASON\","
echo "  \"capabilities\": \"$CAPABILITIES\","
echo "  \"fallback_chain\": [\"${FALLBACK_CHAIN[*]}\"],"
echo "  \"project\": \"$PROJECT\","
echo "  \"previous_decisions\": $PREVIOUS_DECISIONS,"
echo "  \"timestamp\": \"$(date -Iseconds)\""
echo "}"