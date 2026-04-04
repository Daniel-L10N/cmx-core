#!/bin/bash
# AI Selector - Selecciona la mejor IA basada en tipo de tarea
# Uso: ai-selector.sh <task-type> [project]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_FILE="$PROJECT_ROOT/config/ai-registry.json"
MEMORY_SCRIPT="$PROJECT_ROOT/scripts/memory-query.sh"

TASK_TYPE="${1:-general}"
PROJECT="${2:-cmx-core}"

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_select() { echo -e "${BLUE}[SELECT]${NC} $1"; }

# Verificar que el registry existe
if [ ! -f "$REGISTRY_FILE" ]; then
    echo "{\"error\": \"Registry not found\", \"ia\": \"opencode\", \"fallback\": null}"
    exit 1
fi

# Obtener reglas de selección
SELECTION_RULES=$(jq -r ".selection_rules.\"$TASK_TYPE\" // .selection_rules.general" "$REGISTRY_FILE")

# Convertir a array
IAS_PREFERRED=$(echo "$SELECTION_RULES" | jq -r '.[]' 2>/dev/null || echo "opencode")

# Consultar decisiones previas del proyecto (para aprendizaje)
PREVIOUS_DECISIONS=$("$MEMORY_SCRIPT" "$PROJECT" "" "decision" 10 2>/dev/null | jq -r 'length' || echo "0")

# Por cada IA preferida, verificar disponibilidad
SELECTED_IA=""
FALLBACK_IA=""

while IFS= read -r ia; do
    [ -z "$ia" ] && continue
    
    # Verificar si está disponible
    status=$(jq -r ".ias.\"$ia\".status" "$REGISTRY_FILE" 2>/dev/null || echo "unavailable")
    
    if [ "$status" = "available" ]; then
        # Verificar variables de entorno requeridas
        requires_env=$(jq -r ".ias.\"$ia\".requires_env // [] | .[]" "$REGISTRY_FILE" 2>/dev/null || echo "")
        available=true
        
        if [ -n "$requires_env" ]; then
            while IFS= read -r var; do
                [ -z "$var" ] && continue
                if [ -z "${!var}" ]; then
                    available=false
                    break
                fi
            done <<< "$requires_env"
        fi
        
        if [ "$available" = true ]; then
            if [ -z "$SELECTED_IA" ]; then
                SELECTED_IA="$ia"
            fi
        else
            [ -z "$FALLBACK_IA" ] && FALLBACK_IA="$ia"
        fi
    else
        [ -z "$FALLBACK_IA" ] && FALLBACK_IA="$ia"
    fi
done <<< "$IAS_PREFERRED"

# Si no hay IA disponible, usar fallback hardcoded
if [ -z "$SELECTED_IA" ]; then
    SELECTED_IA="${FALLBACK_IA:-opencode}"
fi

# Obtener capacidades y razón de selección
CAPABILITIES=$(jq -r ".ias.\"$SELECTED_IA\".capabilities | join(\", \")" "$REGISTRY_FILE" 2>/dev/null || echo "general")
BEST_FOR=$(jq -r ".ias.\"$SELECTED_IA\".best_for | join(\", \")" "$REGISTRY_FILE" 2>/dev/null || echo "general")

log_select "Tarea: $TASK_TYPE → IA: $SELECTED_IA"

# Generar razón basada en capacidades
REASON="Seleccionado $SELECTED_IA para tarea '$TASK_TYPE' porque es óptimo para: $BEST_FOR"

# Si hay decisiones previas, mencionarlo
if [ "$PREVIOUS_DECISIONS" -gt 0 ]; then
    REASON="$REASON ( proyecto tiene $PREVIOUS_DECISIONS decisiones previas)"
fi

# Output JSON
echo "{"
echo "  \"status\": \"selected\","
echo "  \"task_type\": \"$TASK_TYPE\","
echo "  \"ia\": \"$SELECTED_IA\","
echo "  \"reason\": \"$REASON\","
echo "  \"capabilities\": \"$CAPABILITIES\","
echo "  \"fallback\": \"$FALLBACK_IA\","
echo "  \"project\": \"$PROJECT\","
echo "  \"previous_decisions\": $PREVIOUS_DECISIONS,"
echo "  \"timestamp\": \"$(date -Iseconds)\""
echo "}"