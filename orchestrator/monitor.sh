#!/bin/bash
# Cognitive Stack v2 — Torre de Control / Monitor
# Monitorea el estado de todos los agentes en tiempo real
# Uso: ./monitor.sh [--once] [--json]

set -e

WORKSPACE="${WORKSPACE:-/home/cmx/cmx-core}"
STATE_FILE="$WORKSPACE/orchestrator/agent_state.json"
LOG_DIR="$WORKSPACE/orchestrator/logs/active"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

# Modos
ONCE=false
JSON_OUTPUT=false

if [[ "${1:-}" == "--once" ]]; then
    ONCE=true
fi

if [[ "${1:-}" == "--json" ]]; then
    JSON_OUTPUT=true
fi

# ============================================================
# FUNCIONES DE FORMATEO
# ============================================================

format_duration() {
    local start_ts="$1"
    local end_ts="$2"
    
    if [ -z "$start_ts" ] || [ "$start_ts" == "null" ]; then
        echo "-"
        return
    fi
    
    local start_epoch
    local end_epoch
    
    # Convertir ISO8601 a epoch
    start_epoch=$(date -d "$start_ts" +%s 2>/dev/null || echo "0")
    
    if [ -z "$end_ts" ] || [ "$end_ts" == "null" ]; then
        # Aún corriendo - calcular duración hasta ahora
        end_epoch=$(date +%s)
    else
        end_epoch=$(date -d "$end_ts" +%s 2>/dev/null || echo "0")
    fi
    
    local diff=$((end_epoch - start_epoch))
    local mins=$((diff / 60))
    local secs=$((diff % 60))
    
    printf "%d:%02d" $mins $secs
}

format_status() {
    local status="$1"
    local requires_hitl="$2"
    local confidence="$3"
    
    case "$status" in
        "pending")
            echo -e "${DIM}⏸ PENDING${NC}"
            ;;
        "running")
            echo -e "${CYAN}🔄 RUNNING${NC}"
            ;;
        "completed")
            echo -e "${GREEN}✅ DONE${NC}"
            ;;
        "failed")
            echo -e "${RED}❌ FAILED${NC}"
            ;;
        "timeout")
            echo -e "${RED}⏱ TIMEOUT${NC}"
            ;;
        "cancelled")
            echo -e "${YELLOW}🚫 CANCELLED${NC}"
            ;;
        *)
            echo -e "${DIM}$status${NC}"
            ;;
    esac
}

format_confidence() {
    local score="$1"
    local requires_hitl="$2"
    
    if [ "$score" == "0" ] || [ -z "$score" ] || [ "$score" == "null" ]; then
        echo -e "${DIM}-${NC}"
        return
    fi
    
    if [ "$requires_hitl" == "true" ]; then
        echo -e "${RED}⚠️ $score/10${NC}"
    elif [ "$score" -ge 8 ]; then
        echo -e "${GREEN}$score/10${NC}"
    elif [ "$score" -ge 6 ]; then
        echo -e "${YELLOW}$score/10${NC}"
    else
        echo -e "${RED}$score/10${NC}"
    fi
}

check_pid_alive() {
    local pid="$1"
    if [ -n "$pid" ] && [ "$pid" != "null" ] && [ "$pid" != "0" ]; then
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${CYAN}[$pid]${NC}"
        else
            echo -e "${DIM}[dead]$NC"
        fi
    else
        echo -e "${DIM}-${NC}"
    fi
}

# ============================================================
# RENDERIZADO DE TABLA
# ============================================================

render_table() {
    local change_name
    local pipeline_version
    local started_at
    
    change_name=$(jq -r '.change_name // "N/A"' "$STATE_FILE")
    pipeline_version=$(jq -r '.version // "N/A"' "$STATE_FILE")
    started_at=$(jq -r '.started_at // "N/A"' "$STATE_FILE")
    
    # Header
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}        ${WHITE}🎛  COGNITIVE STACK — TORRE DE CONTROL${NC}                        ${BLUE}║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    printf "${BLUE}║${NC}  ${WHITE}Change:${NC} %-20s  ${WHITE}Pipeline:${NC} %-10s  ${WHITE}Refresh:${NC} 2s        ${BLUE}║\n" \
        "$change_name" "v$pipeline_version"
    printf "${BLUE}║${NC}  ${WHITE}Started:${NC} %-67s  ${BLUE}║\n" "$started_at"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    printf "${BLUE}║${NC}  ${WHITE}%-12s${NC} ${WHITE}%-14s${NC} ${WHITE}%-10s${NC} ${WHITE}%-6s${NC} ${WHITE}%-30s${NC} ${BLUE}║${NC}\n" \
        "AGENTE" "STATUS" "DURACIÓN" "CONF" "OUTPUT/PID"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Agentes en orden
    local agents=("explorer" "proposer" "spec" "design" "tasks" "implementer" "verifier" "archiver")
    
    for agent in "${agents[@]}"; do
        local status pid confidence requires_hitl start_time end_time output_file
        
        status=$(jq -r ".agents.$agent.status // \"pending\"" "$STATE_FILE")
        pid=$(jq -r ".agents.$agent.pid // null" "$STATE_FILE")
        confidence=$(jq -r ".agents.$agent.confidence_score // 0" "$STATE_FILE")
        requires_hitl=$(jq -r ".agents.$agent.requires_hitl // false" "$STATE_FILE")
        start_time=$(jq -r ".agents.$agent.started_at // null" "$STATE_FILE")
        end_time=$(jq -r ".agents.$agent.completed_at // null" "$STATE_FILE")
        output_file=$(jq -r ".agents.$agent.output_file // null" "$STATE_FILE")
        
        # Calcular duración
        local duration
        duration=$(format_duration "$start_time" "$end_time")
        
        # Formatear status
        local status_formatted
        status_formatted=$(format_status "$status" "$requires_hitl" "$confidence")
        
        # Formatear confidence
        local conf_formatted
        conf_formatted=$(format_confidence "$confidence" "$requires_hitl")
        
        # Output o PID
        local output_info
        if [ "$status" == "running" ]; then
            output_info=$(check_pid_alive "$pid")
        elif [ -n "$output_file" ] && [ "$output_file" != "null" ]; then
            # Extraer solo el nombre del archivo
            output_info=$(basename "$output_file" 2>/dev/null || echo "$output_file")
        else
            output_info="-"
        fi
        
        # Línea HITL requerida
        local hitl_marker=""
        if [ "$requires_hitl" == "true" ] && [ "$status" != "pending" ]; then
            hitl_marker=" 🚨"
        fi
        
        # Color de fondo para línea según estado
        local line_color="$NC"
        case "$status" in
            "running") line_color="${CYAN}" ;;
            "failed"|"timeout") line_color="${RED}" ;;
        esac
        
        printf "${BLUE}║${NC}  %-12s ${status_formatted}%s %-10s ${conf_formatted} %-30s ${BLUE}║${NC}\n" \
            "$agent" "" "$duration" "$output_info"
        
    done
    
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════════════════════╣${NC}"
    
    # Footer con información adicional
    local active_count=0
    local hitl_required=0
    
    for agent in explorer proposer spec design tasks implementer verifier archiver; do
        local status=$(jq -r ".agents.$agent.status // \"pending\"" "$STATE_FILE")
        local hitl=$(jq -r ".agents.$agent.requires_hitl // false" "$STATE_FILE")
        
        if [ "$status" == "running" ]; then
            active_count=$((active_count + 1))
        fi
        if [ "$hitl" == "true" ]; then
            hitl_required=$((hitl_required + 1))
        fi
    done
    
    printf "${BLUE}║${NC}  ${WHITE}PIDS activos:${NC} ${CYAN}%d${NC}" "$active_count"
    
    if [ "$hitl_required" -gt 0 ]; then
        echo -e "  ${RED}⚠️  HITL REQUERIDO: $hitl_required${NC}"
    else
        echo ""
    fi
    
    echo -e "  ${DIM}🛑 stop-all.sh${NC} para detener | ${DIM}Ctrl+C para salir${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================
# MODO JSON (para integración)
# ============================================================

render_json() {
    cat "$STATE_FILE"
}

# ============================================================
# LOOP PRINCIPAL
# ============================================================

main() {
    if [ ! -f "$STATE_FILE" ]; then
        echo -e "${RED}ERROR: agent_state.json no encontrado${NC}"
        exit 1
    fi
    
    if [ "$JSON_OUTPUT" == "true" ]; then
        render_json
        exit 0
    fi
    
    if [ "$ONCE" == "true" ]; then
        # Modo single-shot (para testing)
        tput clear 2>/dev/null || echo ""
        render_table
        exit 0
    fi
    
    # Modo continuo
    while true; do
        tput clear 2>/dev/null || echo ""
        render_table
        sleep 2
    done
}

main "$@"
