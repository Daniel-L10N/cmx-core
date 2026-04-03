#!/bin/bash
# =============================================================================
# Summary Generator - SDD Phase 3
# Genera resúmenes ejecutivos de máximo 10 líneas por agente
# Lee status.json y summary.json de cada agente
# =============================================================================

set -euo pipefail

WORKSPACE="${WORKSPACE:-/home/cmx/cmx-core}"
AGENT_COMM_DIR="$WORKSPACE/artifacts/agent-comm"

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

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

format_duration() {
    local start_ts="$1"
    local end_ts="$2"
    
    if [ -z "$start_ts" ] || [ "$start_ts" == "null" ]; then
        echo "-"
        return
    fi
    
    local start_epoch end_epoch
    start_epoch=$(date -d "$start_ts" +%s 2>/dev/null || echo "0")
    
    if [ -z "$end_ts" ] || [ "$end_ts" == "null" ]; then
        end_epoch=$(date +%s)
    else
        end_epoch=$(date -d "$end_ts" +%s 2>/dev/null || echo "0")
    fi
    
    local diff=$((end_epoch - start_epoch))
    local mins=$((diff / 60))
    local secs=$((diff % 60))
    
    printf "%d:%02d" $mins $secs
}

get_status_emoji() {
    local status="$1"
    case "$status" in
        "pending")    echo "⏸" ;;
        "running")    echo "🔄" ;;
        "completed")  echo "✅" ;;
        "failed")     echo "❌" ;;
        "timeout")    echo "⏱" ;;
        "cancelled")  echo "🚫" ;;
        *)            echo "❓" ;;
    esac
}

get_status_color() {
    local status="$1"
    case "$status" in
        "pending")    echo "$DIM" ;;
        "running")    echo "$CYAN" ;;
        "completed")  echo "$GREEN" ;;
        "failed"|"timeout") echo "$RED" ;;
        "cancelled")  echo "$YELLOW" ;;
        *)            echo "$NC" ;;
    esac
}

# -----------------------------------------------------------------------------
# generate_summary
# Genera resumen para un agente específico
# -----------------------------------------------------------------------------
generate_summary() {
    local agent="$1"
    local change="${2:-}"
    
    if [ -z "$agent" ]; then
        echo "ERROR: agent requerido" >&2
        return 1
    fi
    
    # Buscar archivos de status y summary
    local status_file=""
    local summary_file=""
    
    if [ -n "$change" ]; then
        status_file="$AGENT_COMM_DIR/$change/${agent}_status.json"
        summary_file="$AGENT_COMM_DIR/$change/${agent}_summary.json"
    else
        # Buscar en cualquier change
        for dir in "$AGENT_COMM_DIR"/*/; do
            if [ -f "$dir/${agent}_status.json" ]; then
                status_file="$dir/${agent}_status.json"
                summary_file="$dir/${agent}_summary.json"
                change=$(basename "$dir")
                break
            fi
        done
    fi
    
    if [ -z "$status_file" ] || [ ! -f "$status_file" ]; then
        return 1
    fi
    
    # Extraer información
    local status summary started_at completed_at exit_code output_path
    status=$(jq -r '.status // "pending"' "$status_file")
    summary=$(jq -r '.summary // null' "$status_file")
    started_at=$(jq -r '.started_at // null' "$status_file")
    completed_at=$(jq -r '.completed_at // null' "$status_file")
    exit_code=$(jq -r '.exit_code // null' "$status_file")
    output_path=$(jq -r '.output_path // null' "$status_file")
    
    # Calcular duración
    local duration
    duration=$(format_duration "$started_at" "$completed_at")
    
    # Formatear salida
    local emoji color
    emoji=$(get_status_emoji "$status")
    color=$(get_status_color "$status")
    
    echo ""
    echo -e "${color}=== ${agent^^} ===${NC}"
    echo -e "  ${emoji} Status: ${status} | Duración: ${duration}"
    
    # Mostrar resumen o summary
    if [ -n "$summary" ] && [ "$summary" != "null" ]; then
        # Limitar a 10 líneas máximo
        echo "$summary" | head -10
    elif [ -f "$summary_file" ]; then
        cat "$summary_file" | head -10
    else
        echo -e "  ${DIM}(Sin resumen disponible)${NC}"
    fi
    
    # Mostrar exit code si hay error
    if [ "$status" == "failed" ] && [ -n "$exit_code" ] && [ "$exit_code" != "null" ]; then
        echo -e "  ${RED}Exit code: ${exit_code}${NC}"
    fi
    
    # Mostrar output path si existe
    if [ -n "$output_path" ] && [ "$output_path" != "null" ]; then
        echo -e "  Output: ${output_path}"
    fi
    
    return 0
}

# -----------------------------------------------------------------------------
# generate_all_summaries
# Genera resúmenes para todos los agentes
# -----------------------------------------------------------------------------
generate_all_summaries() {
    local change="${1:-}"
    
    # Lista de agentes conocidos
    local agents=("explorer" "proposer" "spec" "design" "tasks" "implementer" "verifier" "archiver")
    
    # Si no hay change, detectar el más reciente
    if [ -z "$change" ]; then
        local latest_dir=""
        local latest_time=0
        
        for dir in "$AGENT_COMM_DIR"/*/; do
            if [ -d "$dir" ]; then
                local dir_time=$(stat -c %Y "$dir" 2>/dev/null || echo "0")
                if [ "$dir_time" -gt "$latest_time" ]; then
                    latest_time=$dir_time
                    latest_dir="$dir"
                fi
            fi
        done
        
        if [ -n "$latest_dir" ]; then
            change=$(basename "$latest_dir")
        fi
    fi
    
    if [ -z "$change" ]; then
        echo -e "${YELLOW}No se encontró ningún change con estado${NC}"
        return 1
    fi
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}        ${WHITE}RESÚMENES EJECUTIVOS - ${change}${NC}              ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    
    for agent in "${agents[@]}"; do
        generate_summary "$agent" "$change" || true
    done
}

# -----------------------------------------------------------------------------
# generate_hitl_summary
# Genera resumen para aprobación HITL
# -----------------------------------------------------------------------------
generate_hitl_summary() {
    local change="${1:-}"
    
    if [ -z "$change" ]; then
        echo "ERROR: change requerido para HITL summary" >&2
        return 1
    fi
    
    local status_file="$AGENT_COMM_DIR/$change/${change}_status.json"
    
    # Buscar cualquier agente que requiera approval
    local agents_need_approval=()
    
    for agent_file in "$AGENT_COMM_DIR/$change"/*_status.json; do
        if [ -f "$agent_file" ]; then
            local status summary
            status=$(jq -r '.status // "pending"' "$agent_file")
            summary=$(jq -r '.summary // null' "$agent_file")
            
            if [ "$status" == "completed" ] || [ "$status" == "failed" ]; then
                local agent_name
                agent_name=$(basename "$agent_file" | sed 's/_status.json//')
                
                echo ""
                echo -e "${YELLOW}📋 ${agent_name^^}:${NC}"
                
                if [ -n "$summary" ] && [ "$summary" != "null" ]; then
                    # Resumen máximo 5 líneas para HITL
                    echo "$summary" | head -5 | sed 's/^/   /'
                else
                    echo -e "   ${DIM}(Sin resumen)${NC}"
                fi
            fi
        fi
    done
}

# -----------------------------------------------------------------------------
# show_executive_summary
# Muestra resumen ejecutivo (máx 10 líneas total)
# -----------------------------------------------------------------------------
show_executive_summary() {
    local change="${1:-}"
    
    # Si no hay change, detectar el más reciente
    if [ -z "$change" ]; then
        for dir in "$AGENT_COMM_DIR"/*/; do
            if [ -d "$dir" ]; then
                change=$(basename "$dir")
                break
            fi
        done
    fi
    
    if [ -z "$change" ]; then
        echo -e "${YELLOW}No hay cambios activos${NC}"
        return 1
    fi
    
    local comm_dir="$AGENT_COMM_DIR/$change"
    
    echo -e "${MAGENTA}════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  📊 RESUMEN EJECUTIVO - ${change}${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════${NC}"
    
    # Contadores
    local total=0
    local completed=0
    local running=0
    local failed=0
    
    for status_file in "$comm_dir"/*_status.json; do
        [ -f "$status_file" ] || continue
        total=$((total + 1))
        
        local status
        status=$(jq -r '.status // "pending"' "$status_file")
        
        case "$status" in
            "completed") completed=$((completed + 1)) ;;
            "running")   running=$((running + 1)) ;;
            "failed"|"timeout") failed=$((failed + 1)) ;;
        esac
    done
    
    echo ""
    echo -e "  ${WHITE}Progreso:${NC} ${GREEN}${completed}${NC}/${total} completados"
    echo -e "  ${WHITE}Corriendo:${NC} ${CYAN}${running}${NC}"
    if [ "$failed" -gt 0 ]; then
        echo -e "  ${WHITE}Fallidos:${NC} ${RED}${failed}${NC}"
    fi
    
    # Mostrar últimos resúmenes (máx 10 líneas)
    echo ""
    echo -e "${WHITE}Últimas actividades:${NC}"
    
    local line_count=0
    for status_file in "$comm_dir"/*_status.json; do
        [ -f "$status_file" ] || continue
        
        local agent status summary started_at completed_at
        agent=$(basename "$status_file" | sed 's/_status.json//')
        status=$(jq -r '.status // "pending"' "$status_file")
        summary=$(jq -r '.summary // null' "$status_file")
        started_at=$(jq -r '.started_at // null' "$status_file")
        completed_at=$(jq -r '.completed_at // null' "$status_file")
        
        local emoji
        emoji=$(get_status_emoji "$status")
        
        local duration
        duration=$(format_duration "$started_at" "$completed_at")
        
        if [ -n "$summary" ] && [ "$summary" != "null" ]; then
            # Primera línea del resumen
            local first_line
            first_line=$(echo "$summary" | head -1 | cut -c1-60)
            printf "  %s %-12s %s %s\n" "$emoji" "$agent" "$duration" "$first_line"
            line_count=$((line_count + 1))
        else
            printf "  %s %-12s %s\n" "$emoji" "$agent" "$duration"
            line_count=$((line_count + 1))
        fi
        
        # Máximo 10 líneas
        if [ "$line_count" -ge 10 ]; then
            break
        fi
    done
    
    echo ""
    echo -e "${DIM}Usa --detailed para ver estado completo${NC}"
    echo ""
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
    summary|exec)
        show_executive_summary "$1"
        ;;
    all)
        generate_all_summaries "$1"
        ;;
    agent)
        generate_summary "$1" "$2"
        ;;
    hitl)
        generate_hitl_summary "$1"
        ;;
    help|--help|-h)
        cat << 'EOF'
Summary Generator v3 — Resúmenes Ejecutivos para HITL
=====================================================

Uso: summary.sh <comando> [opciones]

COMANDOS:
  summary [change]     Resumen ejecutivo (máx 10 líneas)
  all [change]        Resúmenes de todos los agentes
  agent <name> [change]  Resumen de un agente específico
  hitl <change>       Resumen para aprobación HITL
  help                Este mensaje

EJEMPLOS:
  ./summary.sh summary
  ./summary.sh summary mi-change
  ./summary.sh hitl mi-change

EOF
        ;;
    *)
        show_executive_summary "$COMMAND"
        ;;
esac
