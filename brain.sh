#!/bin/bash
# Brain - Cerebro principal del sistema autónomo cmx-core
# Uso: brain.sh --task "descripción" [--mode autonomous|hybrid|manual] [--context "contexto"] [--project <name>]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"

# Cargar variables de entorno
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

# Scripts
CHECK_ENV="$PROJECT_ROOT/scripts/check-environment.sh"
AI_SELECTOR="$PROJECT_ROOT/scripts/ai-selector.sh"
MEMORY_SAVE="$PROJECT_ROOT/scripts/memory-save.sh"
BRAIN_ADAPTER="$PROJECT_ROOT/orchestrator/brain-adapter.sh"

# ============================================================================
# LOGGING CENTRALIZADO (v2.2.0)
# ============================================================================
source "$PROJECT_ROOT/lib/logger.sh" 2>/dev/null || true
source "$PROJECT_ROOT/lib/metrics.sh" 2>/dev/null || true
source "$PROJECT_ROOT/lib/context-cache.sh" 2>/dev/null || true

# Inicializar context cache
context_cache_init "$PROJECT_ROOT" "$PROJECT_ROOT/.context-cache" 2>/dev/null || true

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
TASK_START_TIME=$(date +%s)

# Alias de compatibilidad: las funciones log_* del logger.sh reemplazan las locales
# Si logger.sh no cargó, las funciones locales de abajo sirven como fallback
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

# ============================================================================
# INICIALIZAR LOGGING Y MÉTRICAS (v2.2.0)
# ============================================================================
log_init "brain" "$PROJECT_ROOT/logs" 2>/dev/null || true
metrics_init "$PROJECT" "$PROJECT_ROOT/logs" 2>/dev/null || true

log_info "Iniciando cerebro para proyecto: $PROJECT"
metrics_task_start "$TASK_ID" "$TASK" "$PROJECT"

log_info "Tarea: $TASK"
log_info "Modo: $MODE"

# 1. Pre-flight check
log_info "Ejecutando check de entorno..."
metrics_record "env_check_start" "running" "" "brain"
CHECK_RESULT=$("$CHECK_ENV" --strict 2>&1) || true
echo "$CHECK_RESULT" | head -5

# Extraer status del check
CHECK_STATUS=$(echo "$CHECK_RESULT" | jq -r '.status' 2>/dev/null || echo "unknown")

if [ "$CHECK_STATUS" = "error" ]; then
    log_error "Check de entorno falló. Abortando."
    metrics_error "brain" "environment_check_failed" "status=$CHECK_STATUS"
    exit 1
fi

metrics_record "env_check_end" "$CHECK_STATUS" "" "brain"

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

log_info "Tipo de tarea detectado: $TASK_TYPE"

# 3. Seleccionar IA
log_info "Seleccionando IA óptima..."
SELECTION=$("$AI_SELECTOR" "$TASK_TYPE" "$PROJECT" 2>/dev/null)
SELECTED_IA=$(echo "$SELECTION" | jq -r '.ia' 2>/dev/null || echo "opencode")
SELECTION_REASON=$(echo "$SELECTION" | jq -r '.reason' 2>/dev/null || echo "default")
SELECTED_COST=$(echo "$SELECTION" | jq -r '.cost_level // 0' 2>/dev/null || echo "0")

log_ok "IA seleccionada: $SELECTED_IA"

# Registrar métrica de selección de IA
metrics_ia_selection "$SELECTED_IA" "$TASK_TYPE" "$SELECTED_COST" "$SELECTION_REASON"

# Guardar decisión de selección
"$MEMORY_SAVE" "decision" "ia-selection" \
    "Seleccionado $SELECTED_IA para tarea tipo '$TASK_TYPE'. Razón: $SELECTION_REASON" \
    "$PROJECT" "ai-selector" "$TASK_ID" "selection"

# 4. Obtener configuración de autonomía
HITL_GATES=$(jq -r ".levels.\"$MODE\".hitl_gates // [] | join(\", \")" "$AUTONOMY_FILE" 2>/dev/null || echo "")
log "HITL gates para modo '$MODE': $HITL_GATES"

# 5. Inyector de contexto de 3 capas (con cache — v2.2.0)
log_info "Construyendo contexto de 3 capas..."

# Capa 1: Base (genérica) — desde cache
if type context_cache_get_layer1 >/dev/null 2>&1; then
    CONTEXT_LAYER_1=$(context_cache_get_layer1)
else
    CONTEXT_LAYER_1=$(cat "$PROMPT_BASE" 2>/dev/null || echo "# Sistema Base\nEres cmx-core.")
fi

# Capa 2: Proyecto (específica) — desde cache
if type context_cache_get_layer2 >/dev/null 2>&1; then
    CONTEXT_LAYER_2=$(context_cache_get_layer2)
else
    CONTEXT_LAYER_2=""
    if [ -f "$CONTEXT_FILE" ]; then
        CONTEXT_LAYER_2=$(cat "$CONTEXT_FILE")
    fi
    if [ -f "$AGENT_FILE" ]; then
        CONTEXT_LAYER_2="$CONTEXT_LAYER_2

---

$(cat "$AGENT_FILE")"
    fi
fi

# Capa 3: Tarea (dinámica — no cacheable)
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

# ============================================================================
# TIMEOUTS POR IA (v2.1.1 — Security & Reliability Hardening)
# ============================================================================
# Cada IA tiene un timeout específico basado en su velocidad esperada.
# Si el comando `timeout` no está disponible, se usa un fallback con background PID.

TIMEOUT_OPENCODE="${TIMEOUT_OPENCODE:-300}"    # 5 min
TIMEOUT_GEMINI="${TIMEOUT_GEMINI:-180}"        # 3 min
TIMEOUT_OPENROUTER="${TIMEOUT_OPENROUTER:-120}" # 2 min

# Wrapper de ejecución con timeout + graceful shutdown
run_with_timeout() {
    local timeout_sec="$1"
    shift
    local cmd="$@"

    # Verificar si el comando `timeout` está disponible
    if command -v timeout >/dev/null 2>&1; then
        # timeout command disponible: usa SIGTERM + SIGKILL
        timeout --signal=TERM --kill-after=10 "$timeout_sec" bash -c "$cmd" 2>&1
        return $?
    else
        # Fallback: implementación manual con background PID
        local temp_output
        temp_output=$(mktemp)

        bash -c "$cmd" > "$temp_output" 2>&1 &
        local pid=$!
        local elapsed=0

        while kill -0 "$pid" 2>/dev/null; do
            sleep 1
            elapsed=$((elapsed + 1))

            if [ "$elapsed" -ge "$timeout_sec" ]; then
                log_warn "Timeout ($timeout_sec s) — enviando SIGTERM a PID $pid"
                kill -TERM "$pid" 2>/dev/null || true
                sleep 5
                if kill -0 "$pid" 2>/dev/null; then
                    log_error "SIGTERM ignorado — enviando SIGKILL"
                    kill -9 "$pid" 2>/dev/null || true
                fi
                cat "$temp_output"
                rm -f "$temp_output"
                return 124  # Timeout exit code
            fi
        done

        wait "$pid" 2>/dev/null
        local exit_code=$?
        cat "$temp_output"
        rm -f "$temp_output"
        return $exit_code
    fi
}

# 6. Ejecutar la tarea con la IA seleccionada (con timeouts — v2.1.1)
log "Ejecutando tarea con $SELECTED_IA (timeout: ${TIMEOUT_OPENCODE}s)..."

# Determinar si la tarea requiere pipeline SDD
# Si es "spec-driven" o el modo es autonomous, usar brain-adapter
USE_PIPELINE=false
INTENT="auto"

case "$SELECTED_IA" in
    opencode)
        # opencode puede ejecutar directamente O via pipeline
        if [ "$MODE" = "autonomous" ] || echo "$TASK" | grep -qiE "(implementar|crear feature|escribir spec|design|build)"; then
            USE_PIPELINE=true
            INTENT="auto"
            log "Tarea detectada como SDD - usando brain-adapter"
        else
            # Usar opencode directamente CON TIMEOUT
            log "Ejecutando opencode con timeout de ${TIMEOUT_OPENCODE}s..."
            RESPONSE=$(run_with_timeout "$TIMEOUT_OPENCODE" "opencode run '$TASK'" 2>&1) || {
                exit_code=$?
                if [ $exit_code -eq 124 ]; then
                    log_error "TIMEOUT: opencode excedió ${TIMEOUT_OPENCODE}s"
                    RESPONSE="ERROR: Timeout — opencode no respondió en ${TIMEOUT_OPENCODE}s"
                else
                    log_warn "opencode falló con exit code $exit_code"
                    RESPONSE="ERROR: opencode falló (exit code: $exit_code)"
                fi
            }
        fi
        ;;
    gemini)
        # Usar gemini CLI CON TIMEOUT
        log "Ejecutando gemini con timeout de ${TIMEOUT_GEMINI}s..."
        RESPONSE=$(run_with_timeout "$TIMEOUT_GEMINI" "gemini -p '$TASK'" 2>&1) || {
            exit_code=$?
            if [ $exit_code -eq 124 ]; then
                log_error "TIMEOUT: gemini excedió ${TIMEOUT_GEMINI}s"
                RESPONSE="ERROR: Timeout — gemini no respondió en ${TIMEOUT_GEMINI}s"
            else
                log_warn "gemini falló con exit code $exit_code"
                RESPONSE="ERROR: gemini falló (exit code: $exit_code)"
            fi
        }
        ;;
    openrouter)
        # Usar openrouter CON TIMEOUT
        log "Ejecutando openrouter con timeout de ${TIMEOUT_OPENROUTER}s..."
        RESPONSE=$(run_with_timeout "$TIMEOUT_OPENROUTER" "openrouter '$TASK'" 2>&1) || {
            exit_code=$?
            if [ $exit_code -eq 124 ]; then
                log_error "TIMEOUT: openrouter excedió ${TIMEOUT_OPENROUTER}s"
                RESPONSE="ERROR: Timeout — openrouter no respondió en ${TIMEOUT_OPENROUTER}s"
            else
                log_warn "openrouter falló con exit code $exit_code"
                RESPONSE="ERROR: openrouter falló (exit code: $exit_code)"
            fi
        }
        ;;
    *)
        RESPONSE="IA $SELECTED_IA no implementada aún"
        ;;
esac

# Si requiere pipeline, ejecutar brain-adapter
if [ "$USE_PIPELINE" = true ]; then
    CHANGE_NAME=$(echo "$TASK" | sed 's/ /-/g' | tr -cd '[:alnum:]-_' | cut -c1-50)
    
    log "Dispatching a pipeline SDD: $CHANGE_NAME"
    ADAPTER_RESULT=$("$BRAIN_ADAPTER" \
        --task-id "$TASK_ID" \
        --intent "$INTENT" \
        --change "$CHANGE_NAME" \
        --mode "$MODE" 2>&1) || true
    
    log "Resultado del pipeline:"
    echo "$ADAPTER_RESULT"
    
    # Actualizar response con resultado del pipeline
    RESPONSE="Pipeline SDD ejecutado: $ADAPTER_RESULT"
fi

# 7. Guardar resultado
"$MEMORY_SAVE" "decision" "task-execution" \
    "Tarea '$TASK' ejecutada con $SELECTED_IA. Respuesta: ${RESPONSE:0:200}..." \
    "$PROJECT" "brain" "$TASK_ID" "execution"

# 8. Calcular duración y registrar métricas finales
TASK_END_TIME=$(date +%s)
TASK_DURATION=$((TASK_END_TIME - TASK_START_TIME))

# Determinar status para métricas
if echo "$RESPONSE" | grep -qi "ERROR\|TIMEOUT\|failed"; then
    TASK_STATUS="error"
else
    TASK_STATUS="success"
fi

metrics_task_end "$TASK_ID" "$TASK_STATUS" "${TASK_DURATION}s" "$SELECTED_IA"
metrics_record "task_total_duration" "${TASK_DURATION}s" "type=$TASK_TYPE,status=$TASK_STATUS" "brain"

# 9. Output final
log_ok "Tarea completada en ${TASK_DURATION}s"

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