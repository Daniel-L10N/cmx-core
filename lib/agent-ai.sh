#!/bin/bash
# =============================================================================
# CMX-CORE — Agent AI Execution Wrapper
# v2.2.0
#
# Permite que los agentes SDD usen el AI Selector en lugar de hardcodear opencode.
# Cada agente obtiene la IA óptima para su tipo de tarea y ejecuta con timeout.
#
# Uso (desde un agente):
#   source lib/agent-ai.sh
#   agent_ai_init "$WORKSPACE" "$CHANGE"
#   RESULT=$(agent_ai_exec "implementar" "tu prompt aquí")
#   agent_ai_report
#
# Funciones exportadas:
#   agent_ai_init <workspace> <change>     — Inicializa el wrapper
#   agent_ai_exec <task_type> <prompt>     — Ejecuta con IA seleccionada
#   agent_ai_exec_file <task_type> <file>  — Ejecuta con prompt desde archivo
#   agent_ai_report                         — Muestra resumen de uso de IA
#   agent_ai_get_selected                   — Retorna la IA seleccionada
# =============================================================================

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

AGENT_AI_WORKSPACE=""
AGENT_AI_CHANGE=""
AGENT_AI_SELECTED_IA=""
AGENT_AI_MODEL=""
AGENT_AI_COST_LEVEL=""
AGENT_AI_SELECTION_REASON=""
AGENT_AI_EXECUTIONS=0
AGENT_AI_TOTAL_DURATION=0
AGENT_AI_TIMEOUTS=0
AGENT_AI_ERRORS=0

# Timeouts por IA (configurables via env)
AGENT_AI_TIMEOUT_OPENCODE="${AGENT_AI_TIMEOUT_OPENCODE:-300}"
AGENT_AI_TIMEOUT_GEMINI="${AGENT_AI_TIMEOUT_GEMINI:-180}"
AGENT_AI_TIMEOUT_OPENROUTER="${AGENT_AI_TIMEOUT_OPENROUTER:-120}"

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

agent_ai_init() {
    local workspace="${1:-.}"
    local change="${2:-unknown}"

    AGENT_AI_WORKSPACE="$workspace"
    AGENT_AI_CHANGE="$change"

    # Encontrar project root
    local project_root=""
    if [ -d "$workspace/lib" ]; then
        project_root="$workspace"
    elif [ -d "$workspace/../lib" ]; then
        project_root="$workspace/.."
    else
        project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    fi

    # Cargar dependencias
    AGENT_AI_SELECTOR="$project_root/scripts/ai-selector.sh"
    AGENT_AI_LOGGER="$project_root/lib/logger.sh"

    if [ -f "$AGENT_AI_LOGGER" ]; then
        source "$AGENT_AI_LOGGER" 2>/dev/null || true
    fi

    # Log
    if type log_info >/dev/null 2>&1; then
        log_info "Agent AI Wrapper initialized for change: $change"
    fi
}

# ============================================================================
# SELECCIÓN DE IA
# ============================================================================

agent_ai_select() {
    local task_type="${1:-coding}"

    if [ ! -f "$AGENT_AI_SELECTOR" ]; then
        # Fallback si el selector no existe
        AGENT_AI_SELECTED_IA="opencode"
        AGENT_AI_MODEL=""
        AGENT_AI_COST_LEVEL="2"
        AGENT_AI_SELECTION_REASON="AI Selector no disponible, fallback a opencode"
        return 0
    fi

    local selection
    selection=$("$AGENT_AI_SELECTOR" "$task_type" "$AGENT_AI_CHANGE" 2>/dev/null) || true

    if [ -z "$selection" ]; then
        AGENT_AI_SELECTED_IA="opencode"
        AGENT_AI_MODEL=""
        AGENT_AI_COST_LEVEL="2"
        AGENT_AI_SELECTION_REASON="Selector falló, fallback a opencode"
        return 1
    fi

    AGENT_AI_SELECTED_IA=$(echo "$selection" | jq -r '.ia' 2>/dev/null || echo "opencode")
    AGENT_AI_MODEL=$(echo "$selection" | jq -r '.model' 2>/dev/null || echo "")
    AGENT_AI_COST_LEVEL=$(echo "$selection" | jq -r '.cost_level' 2>/dev/null || echo "0")
    AGENT_AI_SELECTION_REASON=$(echo "$selection" | jq -r '.reason' 2>/dev/null || echo "")

    if type log_info >/dev/null 2>&1; then
        log_info "AI selected: $AGENT_AI_SELECTED_IA (cost: $AGENT_AI_COST_LEVEL) — $AGENT_AI_SELECTION_REASON"
    fi

    return 0
}

# ============================================================================
# EJECUCIÓN CON IA
# ============================================================================

# Wrapper interno con timeout
_agent_ai_run_with_timeout() {
    local timeout_sec="$1"
    local cmd="$2"

    if command -v timeout >/dev/null 2>&1; then
        timeout --signal=TERM --kill-after=10 "$timeout_sec" bash -c "$cmd" 2>&1
        return $?
    else
        # Fallback manual
        local temp_output
        temp_output=$(mktemp)
        bash -c "$cmd" > "$temp_output" 2>&1 &
        local pid=$!
        local elapsed=0

        while kill -0 "$pid" 2>/dev/null; do
            sleep 1
            elapsed=$((elapsed + 1))
            if [ "$elapsed" -ge "$timeout_sec" ]; then
                kill -TERM "$pid" 2>/dev/null || true
                sleep 5
                kill -9 "$pid" 2>/dev/null || true
                cat "$temp_output"
                rm -f "$temp_output"
                return 124
            fi
        done

        wait "$pid" 2>/dev/null
        local exit_code=$?
        cat "$temp_output"
        rm -f "$temp_output"
        return $exit_code
    fi
}

# Obtener timeout para la IA seleccionada
_agent_ai_get_timeout() {
    case "$AGENT_AI_SELECTED_IA" in
        opencode)    echo "$AGENT_AI_TIMEOUT_OPENCODE" ;;
        gemini)      echo "$AGENT_AI_TIMEOUT_GEMINI" ;;
        openrouter)  echo "$AGENT_AI_TIMEOUT_OPENROUTER" ;;
        *)           echo "300" ;;
    esac
}

# Construir comando de ejecución para la IA seleccionada
_agent_ai_build_cmd() {
    local prompt="$1"

    case "$AGENT_AI_SELECTED_IA" in
        opencode)
            echo "opencode run '$prompt'"
            ;;
        gemini)
            echo "gemini -p '$prompt'"
            ;;
        openrouter)
            echo "openrouter '$prompt'"
            ;;
        *)
            echo "opencode run '$prompt'"
            ;;
    esac
}

# Función principal de ejecución
agent_ai_exec() {
    local task_type="${1:-coding}"
    local prompt="$2"

    if [ -z "$prompt" ]; then
        if type log_error >/dev/null 2>&1; then
            log_error "agent_ai_exec: prompt vacío"
        fi
        echo "ERROR: prompt vacío"
        return 1
    fi

    # Seleccionar IA si no está seleccionada aún
    if [ -z "$AGENT_AI_SELECTED_IA" ]; then
        agent_ai_select "$task_type" || true
    fi

    if [ -z "$AGENT_AI_SELECTED_IA" ]; then
        AGENT_AI_SELECTED_IA="opencode"
    fi

    local timeout
    timeout=$(_agent_ai_get_timeout)
    local cmd
    cmd=$(_agent_ai_build_cmd "$prompt")

    AGENT_AI_EXECUTIONS=$((AGENT_AI_EXECUTIONS + 1))

    if type log_info >/dev/null 2>&1; then
        log_info "Executing with $AGENT_AI_SELECTED_IA (timeout: ${timeout}s) [exec #${AGENT_AI_EXECUTIONS}]"
    fi

    local start_time
    start_time=$(date +%s)

    local output
    output=$(_agent_ai_run_with_timeout "$timeout" "$cmd") || {
        local exit_code=$?
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))
        AGENT_AI_TOTAL_DURATION=$((AGENT_AI_TOTAL_DURATION + duration))

        if [ $exit_code -eq 124 ]; then
            AGENT_AI_TIMEOUTS=$((AGENT_AI_TIMEOUTS + 1))
            if type log_error >/dev/null 2>&1; then
                log_error "TIMEOUT: $AGENT_AI_SELECTED_IA excedió ${timeout}s"
            fi
            echo "ERROR: Timeout — $AGENT_AI_SELECTED_IA no respondió en ${timeout}s"
            return 124
        else
            AGENT_AI_ERRORS=$((AGENT_AI_ERRORS + 1))
            if type log_warn >/dev/null 2>&1; then
                log_warn "$AGENT_AI_SELECTED_IA falló con exit code $exit_code"
            fi
            echo "$output"
            return $exit_code
        fi
    }

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    AGENT_AI_TOTAL_DURATION=$((AGENT_AI_TOTAL_DURATION + duration))

    echo "$output"
    return 0
}

# Ejecutar con prompt desde archivo
agent_ai_exec_file() {
    local task_type="${1:-coding}"
    local prompt_file="$2"

    if [ ! -f "$prompt_file" ]; then
        if type log_error >/dev/null 2>&1; then
            log_error "agent_ai_exec_file: archivo no encontrado: $prompt_file"
        fi
        echo "ERROR: archivo no encontrado: $prompt_file"
        return 1
    fi

    local prompt
    prompt=$(cat "$prompt_file")
    agent_ai_exec "$task_type" "$prompt"
}

# ============================================================================
# REPORTE
# ============================================================================

agent_ai_get_selected() {
    echo "$AGENT_AI_SELECTED_IA"
}

agent_ai_report() {
    echo ""
    echo "=== Agent AI Usage Report ==="
    echo "  Change:          $AGENT_AI_CHANGE"
    echo "  IA Selected:     $AGENT_AI_SELECTED_IA"
    echo "  Model:           $AGENT_AI_MODEL"
    echo "  Cost Level:      $AGENT_AI_COST_LEVEL"
    echo "  Executions:      $AGENT_AI_EXECUTIONS"
    echo "  Total Duration:  ${AGENT_AI_TOTAL_DURATION}s"
    echo "  Timeouts:        $AGENT_AI_TIMEOUTS"
    echo "  Errors:          $AGENT_AI_ERRORS"
    echo "  Selection:       $AGENT_AI_SELECTION_REASON"
    echo ""
}

# ============================================================================
# ALIAS DE COMPATIBILIDAD (para scripts que usan opencode directamente)
# ============================================================================

# agent_ai_run <prompt> — alias corto para agent_ai_exec "coding" <prompt>
agent_ai_run() {
    agent_ai_exec "coding" "$1"
}
