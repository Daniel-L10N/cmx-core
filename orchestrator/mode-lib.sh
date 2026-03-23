#!/bin/bash
# CMX-CORE — Mode Reader Library
# Funciones para que los agentes lean la personalidad activa

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CONFIG_FILE="$WORKSPACE/orchestrator/personalities.json"

# ============================================================
# FUNCIONES DE MODO
# ============================================================

get_mode() {
    jq -r '.active' "$CONFIG_FILE" 2>/dev/null || echo "cmx-standard"
}

get_mode_param() {
    local param="$1"
    local mode=$(get_mode)
    jq -r ".personalities.$mode.parameters.$param" "$CONFIG_FILE" 2>/dev/null
}

is_professional() {
    [ "$(get_mode)" == "cmx-professional" ]
}

is_standard() {
    [ "$(get_mode)" == "cmx-standard" ]
}

is_dangerous() {
    [ "$(get_mode)" == "cmx-dangerous" ]
}

should_hitl() {
    local frequency=$(get_mode_param "hitl_frequency")
    case "$frequency" in
        "every_step") return 0 ;;
        "on_failure") return 1 ;;
        "never") return 1 ;;
        *) return 1 ;;
    esac
}

should_auto_continue() {
    local auto=$(get_mode_param "auto_continue")
    [ "$auto" == "true" ]
}

get_confidence_threshold() {
    get_mode_param "confidence_threshold"
}

require_stack_confirmation() {
    local req=$(get_mode_param "require_stack_confirmation")
    [ "$req" == "true" ]
}

require_security_review() {
    local req=$(get_mode_param "require_security_review")
    [ "$req" == "true" ]
}

# ============================================================
# HELPERS PARA AGENTES
# ============================================================

mode_warn() {
    if is_professional; then
        echo -e "${YELLOW}[MODE:WARN]${NC} $1" >&2
    fi
}

mode_error() {
    echo -e "${RED}[MODE:ERROR]${NC} $1" >&2
}

mode_info() {
    if [ "$(get_mode_param "verbose_logging")" == "true" ]; then
        echo -e "${CYAN}[MODE:INFO]${NC} $1"
    fi
}

# Verificar si debemos pausar para HITL
check_hitl() {
    if should_hitl; then
        echo -e "${RED}⚠️  HITL REQUERIDO${NC}"
        echo -e "${RED}   Modo: $(get_mode)${NC}"
        echo -e "${RED}   El agente se detiene hasta aprobación manual${NC}"
        return 0  # Pausar
    fi
    return 1  # Continuar
}

# ============================================================
# EXPORTAR PARA SUB-SHells
# ============================================================

export CMX_MODE=$(get_mode)
export CMX_WORKSPACE="$WORKSPACE"
