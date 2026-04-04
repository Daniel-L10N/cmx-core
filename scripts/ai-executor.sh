#!/bin/bash
# AI Executor with Retry Logic - Ejecuta tareas con fallback automático
# Uso: ai-executor.sh <ia> <task> [options]
#
# Si la IA principal falla, automáticamente intenta con las demás en el fallback chain

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_FILE="$PROJECT_ROOT/config/ai-registry.json"

# Cargar .env si existe
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PRIMARY_IA="${1:-}"
TASK="$2"
OUTPUT_FILE="${3:-}"

log_exec() { echo -e "${BLUE}[EXEC]${NC} $1"; }
log_retry() { echo -e "${YELLOW}[RETRY]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }

# ============================================================================
# FUNCIONES DE EJECUCIÓN
# ============================================================================

execute_opencode() {
    local task="$1"
    opencode run "$task" 2>&1
}

execute_gemini() {
    local task="$1"
    gemini -p "$task" 2>&1
}

execute_openrouter() {
    local task="$1"
    local model=$(jq -r '.ias.openrouter.default_model' "$REGISTRY_FILE" 2>/dev/null || echo "deepseek/deepseek-chat")
    
    curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$model\", \"messages\": [{\"role\": \"user\", \"content\": \"$task\"}]}" 2>&1 | \
        jq -r '.choices[0].message.content' 2>/dev/null || cat
}

execute_ollama() {
    local task="$1"
    local model=$(jq -r '.ias.ollama.default_model' "$REGISTRY_FILE" 2>/dev/null || echo "llama3.2")
    ollama run "$model" "$task" 2>&1
}

# Ejecutar IA por nombre
execute_ia() {
    local ia="$1"
    local task="$2"
    
    case "$ia" in
        opencode)
            execute_opencode "$task"
            ;;
        gemini)
            execute_gemini "$task"
            ;;
        openrouter)
            execute_openrouter "$task"
            ;;
        ollama)
            execute_ollama "$task"
            ;;
        *)
            echo "IA desconocida: $ia"
            return 1
            ;;
    esac
}

# ============================================================================
# LÓGICA PRINCIPAL
# ============================================================================

if [ -z "$PRIMARY_IA" ] || [ -z "$TASK" ]; then
    echo "Uso: $0 <ia> <task> [output_file]"
    echo ""
    echo "Ejemplos:"
    echo "  $0 opencode 'crear un archivo'"
    echo "  $0 gemini 'analizar este código'"
    echo "  $0 openrouter 'resumir esto'"
    echo ""
    echo "IA primaria será ejecutada. Si falla, intentará con fallback chain."
    exit 1
fi

# Obtener configuración de retry
MAX_RETRIES=$(jq -r '.retry_config.max_retries // 2' "$REGISTRY_FILE" 2>/dev/null || echo "2")
RETRY_DELAY=$(jq -r '.retry_config.retry_delay_seconds // 2' "$REGISTRY_FILE" 2>/dev/null || echo "2")

# Obtener fallback chain
FALLBACK_CHAIN=$(jq -r ".retry_config.fallback_chain.\"$PRIMARY_IA\" // [] | .[]" "$REGISTRY_FILE" 2>/dev/null || echo "")

log_exec "Ejecutando tarea con IA: $PRIMARY_IA"
log_exec "Fallback chain: ${FALLBACK_CHAIN:-ninguno}"
echo ""

# Intentar con IA primaria
attempt=0
current_ia="$PRIMARY_IA"

while [ $attempt -lt $((MAX_RETRIES + 1)) ]; do
    attempt=$((attempt + 1))
    
    log_exec "Intento $attempt/$((MAX_RETRIES + 1)) con $current_ia..."
    
    # Ejecutar
    RESPONSE=$(execute_ia "$current_ia" "$TASK" 2>&1)
    EXIT_CODE=$?
    
    # Verificar si la respuesta es válida (no está vacía ni es error)
    if [ $EXIT_CODE -eq 0 ] && [ -n "$RESPONSE" ] && ! echo "$RESPONSE" | grep -qi "error\|failed\|unavailable"; then
        log_ok "Ejecución exitosa con $current_ia"
        
        # Guardar resultado
        if [ -n "$OUTPUT_FILE" ]; then
            echo "$RESPONSE" > "$OUTPUT_FILE"
            log_exec "Resultado guardado en: $OUTPUT_FILE"
        fi
        
        # Mostrar resultado
        echo ""
        echo "=== RESULTADO ($current_ia) ==="
        echo "$RESPONSE"
        
        # Guardar en memoria
        "$PROJECT_ROOT/scripts/memory-save.sh" "decision" "task-execution" \
            "Tarea ejecutada con $current_ia después de $attempt intento(s)" \
            "cmx-core" "ai-executor" "" "execution"
        
        exit 0
    else
        log_error "Falló con $current_ia: ${RESPONSE:0:100}..."
        
        # Buscar siguiente IA en fallback
        if [ -n "$FALLBACK_CHAIN" ]; then
            next_ia=$(echo "$FALLBACK_CHAIN" | head -1)
            remaining_fallback=$(echo "$FALLBACK_CHAIN" | tail -n +2)
            
            if [ -n "$next_ia" ]; then
                log_retry "Cambiando a fallback: $next_ia"
                FALLBACK_CHAIN="$remaining_fallback"
                current_ia="$next_ia"
                
                # Esperar antes de reintentar
                sleep $RETRY_DELAY
            else
                break
            fi
        else
            break
        fi
    fi
done

# Si llegamos aquí, todo falló
log_error "Todos los intentos fallaron"
echo ""
echo "=== ERROR ==="
echo "No se pudo ejecutar la tarea con ninguna de las IAs disponibles."
echo "IAs intentadas: $PRIMARY_IA ${FALLBACK_CHAIN:-}"

exit 1