#!/bin/bash
# CMX-CORE — Selector de Personalidades
# Uso: ./set-mode.sh [professional|standard|dangerous]
# Sin argumentos: muestra menú interactivo

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CONFIG_FILE="$WORKSPACE/orchestrator/personalities.json"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

get_current_mode() {
    jq -r '.active' "$CONFIG_FILE" 2>/dev/null || echo "unknown"
}

set_mode() {
    local mode="$1"
    local valid_modes=("cmx-professional" "cmx-standard" "cmx-dangerous")
    
    # Validar modo
    local valid=false
    for m in "${valid_modes[@]}"; do
        if [ "$mode" == "$m" ]; then
            valid=true
            break
        fi
    done
    
    if [ "$valid" == "false" ]; then
        echo -e "${RED}❌ Modo inválido: $mode${NC}"
        echo "Modos válidos: ${valid_modes[*]}"
        return 1
    fi
    
    # Actualizar config
    jq ".active = \"$mode\"" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && \
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    
    # Feedback
    case "$mode" in
        "cmx-professional")
            echo -e "${RED}${BOLD}🔒 MODO PROFESSIONAL ACTIVADO${NC}"
            echo -e "${RED}   Rigor: 10/10 | HITL: cada paso | Auto: nunca${NC}"
            ;;
        "cmx-standard")
            echo -e "${YELLOW}${BOLD}⚖️ MODO STANDARD ACTIVADO${NC}"
            echo -e "${YELLOW}   Rigor: 5/10 | HITL: en errores | Auto: sí${NC}"
            ;;
        "cmx-dangerous")
            echo -e "${GREEN}${BOLD}⚡ MODO DANGEROUS ACTIVADO${NC}"
            echo -e "${GREEN}   Rigor: 2/10 | HITL: nunca | Auto: TOTAL${NC}"
            ;;
    esac
    
    echo ""
    echo -e "${CYAN}💾 Guardado en: $CONFIG_FILE${NC}"
    return 0
}

show_menu() {
    local current=$(get_current_mode)
    
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║${NC}         🎭 CMX-CORE — Selector de Personalidades      ${BOLD}║${NC}"
    echo -e "${BOLD}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  Modo actual: ${CYAN}$current${NC}                                    ${BOLD}║${NC}"
    echo -e "${BOLD}╠════════════════════════════════════════════════════════════╣${NC}"
    echo ""
    echo -e "  ${RED}1)${NC} 🔒 ${RED}CMX Professional${NC}"
    echo -e "      Rigor máximo | HITL en cada paso"
    echo -e "      Para proyectos críticos de producción"
    echo ""
    echo -e "  ${YELLOW}2)${NC} ⚖️ ${YELLOW}CMX Standard${NC}"
    echo -e "      Modo equilibrado | HITL en errores"
    echo -e "      Para desarrollo diario"
    echo ""
    echo -e "  ${GREEN}3)${NC} ⚡ ${GREEN}CMX Dangerous${NC}"
    echo -e "      Autonomía total | Sin interrupciones"
    echo -e "      Para Daniel™ - Deja trabajar y levántate ☕"
    echo ""
    echo -e "${BOLD}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}  q) Salir                                               ${BOLD}║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "${CYAN}Selecciona modo [1-3]: ${NC}"
}

show_status() {
    local current=$(get_current_mode)
    local mode_info=$(jq -r ".personalities.$current" "$CONFIG_FILE")
    local rigor=$(jq -r ".personalities.$current.parameters.rigor" "$CONFIG_FILE")
    local hitl=$(jq -r ".personalities.$current.parameters.hitl_frequency" "$CONFIG_FILE")
    
    echo ""
    echo -e "${BOLD}=== Estado Actual ===${NC}"
    echo -e "Modo: ${CYAN}$current${NC}"
    echo -e "Rigor: $rigor/10"
    echo -e "HITL: $hitl"
    echo ""
}

# Main
if [ $# -gt 0 ]; then
    # Modo no interactivo
    set_mode "$1"
else
    # Menú interactivo
    while true; do
        clear
        show_menu
        read -n1 choice
        
        case "$choice" in
            1) set_mode "cmx-professional" ;;
            2) set_mode "cmx-standard" ;;
            3) set_mode "cmx-dangerous" ;;
            q|Q) echo ""; exit 0 ;;
            *) echo -e "\n${RED}Opción inválida${NC}" ;;
        esac
        
        if [ $# -eq 0 ]; then
            echo ""
            read -n1 -p "Enter para continuar..."
        fi
    done
fi
