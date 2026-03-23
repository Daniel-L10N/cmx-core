#!/bin/bash
# Cognitive Stack v2 — Kill Switch
# Detiene TODOS los agentes en ejecución y limpia procesos huérfanos
# Uso: ./stop-all.sh [--force]

set -e

WORKSPACE="${WORKSPACE:-/home/cmx/cmx-core}"
LOG_DIR="$WORKSPACE/orchestrator/logs"
ACTIVE_DIR="$LOG_DIR/active"
STATE_FILE="$WORKSPACE/orchestrator/agent_state.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

FORCE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

echo -e "${RED}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║          🛑 COGNITIVE STACK — KILL SWITCH               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ============================================================
# 1. CONTAR PROCESOS ACTIVOS
# ============================================================

echo -e "${BLUE}[1/4]${NC} Escaneando procesos activos..."

ACTIVE_PIDS=$(find "$ACTIVE_DIR" -name "*.pid" -exec cat {} \; 2>/dev/null | grep -E '^[0-9]+$' | sort -u)
ACTIVE_COUNT=$(echo "$ACTIVE_PIDS" | grep -c '[0-9]' || echo 0)

echo "   PIDs encontrados: $ACTIVE_COUNT"

# ============================================================
# 2. MATAR PROCESOS POR PID FILE
# ============================================================

echo -e "${BLUE}[2/4]${NC} Terminando agentes por PID..."

if [ -n "$ACTIVE_PIDS" ]; then
    for pid in $ACTIVE_PIDS; do
        if kill -0 "$pid" 2>/dev/null; then
            PROC_NAME=$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
            echo -e "   ${YELLOW}→${NC} PID $pid ($PROC_NAME)..."
            
            if [ "$FORCE" == "true" ]; then
                kill -9 "$pid" 2>/dev/null && echo -e "     ${RED}✗${NC} SIGKILL enviado" || true
            else
                kill -TERM "$pid" 2>/dev/null && echo -e "     ${YELLOW}✓${NC} SIGTERM enviado" || true
            fi
        else
            echo -e "   ${GREEN}✓${NC} PID $pid ya no existe"
        fi
    done
else
    echo "   No hay PIDs activos en $ACTIVE_DIR"
fi

# ============================================================
# 3. MATAR PROCESOS OPENCOD/AGENTES (pkill)
# ============================================================

echo -e "${BLUE}[3/4]${NC} Limpiando procesos opencode/sdd-..."

if pgrep -f "opencode.*sdd-" > /dev/null 2>&1; then
    OPENCODE_PIDS=$(pgrep -f "opencode.*sdd-")
    for pid in $OPENCODE_PIDS; do
        echo -e "   ${YELLOW}→${NC} opencode PID $pid..."
        if [ "$FORCE" == "true" ]; then
            kill -9 "$pid" 2>/dev/null || true
        else
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
    echo -e "   ${RED}!${NC} Procesos opencode terminados"
else
    echo -e "   ${GREEN}✓${NC} No hay procesos opencode activos"
fi

# ============================================================
# 4. ACTUALIZAR STATE.JSON
# ============================================================

echo -e "${BLUE}[4/4]${NC} Actualizando agent_state.json..."

if [ -f "$STATE_FILE" ]; then
    # Marcar todos los agentes como cancelled
    for agent in explorer proposer spec design tasks implementer verifier archiver; do
        if jq -e ".agents.$agent.status" "$STATE_FILE" > /dev/null 2>&1; then
            jq ".agents.$agent.status = \"cancelled\" | .agents.$agent.pid = null" \
                "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null && \
                mv "${STATE_FILE}.tmp" "$STATE_FILE"
        fi
    done
    echo -e "   ${GREEN}✓${NC} Estado actualizado"
else
    echo -e "   ${YELLOW}!${NC} agent_state.json no encontrado"
fi

# ============================================================
# 5. LIMPIEZA DE PID FILES
# ============================================================

echo ""
echo -e "${BLUE}[INFO]${NC} Limpiando archivos PID..."

rm -f "$ACTIVE_DIR"/*.pid 2>/dev/null && \
    echo -e "   ${GREEN}✓${NC} PID files eliminados" || \
    echo -e "   ${GREEN}✓${NC} No había PID files"

# ============================================================
# RESULTADO
# ============================================================

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ KILL SWITCH COMPLETADO${NC}"
echo ""
echo -e "  Agentes terminados: ${RED}$ACTIVE_COUNT${NC}"
echo -e "  Modo: $([ "$FORCE" == "true" ] && echo "${RED}FORCE (SIGKILL)${NC}" || echo "${YELLOW}GRACEFUL (SIGTERM)${NC}")"
echo ""
echo -e "  Uso para forzar: ${BLUE}$0 --force${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
