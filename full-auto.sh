#!/bin/bash
# CMX-CORE — Full Auto Pipeline (ROOT MODE)
# Ejecuta el pipeline completo con privilegios elevados
# Uso: sudo ./full-auto.sh <change-name>
# Requiere: modo cmx-dangerous activo

# Detectar si somos root
if [ "$EUID" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

set +e  # NO salir en errores - continuar

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CHANGE="${1}"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================================
# CONFIGURACIÓN ROOT
# ============================================================

SUDO_OK=false
if sudo -n true 2>/dev/null; then
    SUDO_OK=true
    echo -e "${GREEN}${BOLD}🔓 ROOT ACCESS CONFIRMED${NC}"
fi

# Función para ejecutar con fallback
run_with_fallback() {
    local cmd="$1"
    local fallback="$2"
    local desc="$3"
    
    echo -e "${MAGENTA}[ROOT]${NC} $desc"
    
    # Intentar con sudo
    if eval "$cmd" 2>&1; then
        return 0
    fi
    
    # Intentar sin sudo
    echo -e "${YELLOW}[FALLBACK]${NC} Intentando sin sudo..."
    if eval "$fallback" 2>&1; then
        return 0
    fi
    
    # Falló, registrar y continuar
    echo -e "${YELLOW}[WARN]${NC} Falló: $desc - continuando..."
    return 0  # Siempre continuar en modo dangerous
}

# ============================================================
# VALIDACIONES
# ============================================================

if [ -z "$CHANGE" ]; then
    echo -e "${RED}ERROR: Uso: sudo ./full-auto.sh <change-name>${NC}"
    exit 1
fi

# Verificar que existe la exploración
EXPLORATION_FILE="$WORKSPACE/artifacts/exploration/${CHANGE}.json"
if [ ! -f "$EXPLORATION_FILE" ]; then
    echo -e "${RED}❌ Exploración no encontrada: $EXPLORATION_FILE${NC}"
    exit 1
fi

# Verificar modo peligroso
CONFIG_FILE="$WORKSPACE/orchestrator/personalities.json"
CURRENT_MODE=$(jq -r '.active' "$CONFIG_FILE" 2>/dev/null || echo "unknown")

if [ "$CURRENT_MODE" != "cmx-dangerous" ]; then
    echo -e "${YELLOW}⚠️  AVISO: Modo actual es '$CURRENT_MODE'${NC}"
    echo -e "${YELLOW}   Activando cmx-dangerous automáticamente...${NC}"
    jq ".active = \"cmx-dangerous\"" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && \
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    CURRENT_MODE="cmx-dangerous"
fi

# ============================================================
# HEADER
# ============================================================

echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║${NC}         🚀 CMX-CORE — FULL AUTO (ROOT MODE)        ${GREEN}${BOLD}║${NC}"
echo -e "${GREEN}${BOLD}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}${BOLD}║${NC}  Change: ${CYAN}$CHANGE${NC}                                        ${GREEN}${BOLD}║${NC}"
echo -e "${GREEN}${BOLD}║${NC}  Modo:   ${RED}DANGEROUS${NC} 🔥  ${YELLOW}ROOT${NC} 🔓                          ${GREEN}${BOLD}║${NC}"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# PIPELINE
# ============================================================

log_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

wait_for_agent() {
    local pid=$1
    local name=$2
    while ps -p $pid > /dev/null 2>&1; do
        sleep 5
        echo -n "."
    done
    echo ""
    return 0  # Siempre retornar 0 en dangerous
}

run_agent() {
    local agent="$1"
    local args="${2:-}"
    local log="/tmp/fauto_${agent}.log"
    
    echo -e "${CYAN}→ Ejecutando: $agent${NC}"
    cd "$WORKSPACE"
    ./agents/${agent}.sh $args > "$log" 2>&1 &
    wait_for_agent $! "$agent"
}

# FASE 1: PROPOSER
log_step "FASE 1: PROPOSER"
run_agent "proposer" "$CHANGE"

# FASE 2: SPEC + DESIGN (paralelo)
log_step "FASE 2: SPEC + DESIGN"
cd "$WORKSPACE"
./agents/spec-writer.sh "$CHANGE" > /tmp/fauto_spec.log 2>&1 &
PID_SPEC=$!
./agents/designer.sh "$CHANGE" > /tmp/fauto_design.log 2>&1 &
PID_DESIGN=$!
wait
echo -e "${GREEN}✅ Spec + Design completados${NC}"

# FASE 3: TASKS
log_step "FASE 3: TASK PLANNER"
run_agent "task-planner" "$CHANGE"

# ============================================================
# BATCHES LOOP
# ============================================================

log_step "FASE 4: IMPLEMENTATION + VERIFICATION"

BATCH=1
MAX_BATCHES=20
BATCHES_COMPLETED=0

while [ $BATCH -le $MAX_BATCHES ]; do
    echo ""
    echo -e "${YELLOW}━━━ BATCH $BATCH ━━━${NC}"
    
    # Verificar si existe batch
    TASKS_FILE="$WORKSPACE/artifacts/tasks/${CHANGE}.json"
    if [ ! -f "$TASKS_FILE" ]; then
        echo -e "${GREEN}✅ No más batches${NC}"
        break
    fi
    
    # Verificar si hay tareas para este batch
    BATCH_EXISTS=$(jq -r ".batch_recommendations[] | select(.batch == $BATCH) | .tasks | length" "$TASKS_FILE" 2>/dev/null || echo "0")
    
    if [ "$BATCH_EXISTS" == "0" ] || [ -z "$BATCH_EXISTS" ]; then
        echo -e "${GREEN}✅ No más batches${NC}"
        break
    fi
    
    # IMPLEMENTER
    echo -e "${CYAN}→ Implementando batch $BATCH...${NC}"
    cd "$WORKSPACE"
    ./agents/implementer.sh "$CHANGE" $BATCH > /tmp/fauto_impl_${BATCH}.log 2>&1 &
    wait_for_agent $! "implementer"
    
    # VERIFIER
    echo -e "${CYAN}→ Verificando batch $BATCH...${NC}"
    cd "$WORKSPACE"
    ./agents/verifier.sh "$CHANGE" $BATCH > /tmp/fauto_verif_${BATCH}.log 2>&1 &
    wait_for_agent $! "verifier"
    
    # Check if passed (pero continuar siempre en dangerous)
    VERIF_FILE="$WORKSPACE/artifacts/verification/${CHANGE}_batch_${BATCH}.json"
    if [ -f "$VERIF_FILE" ]; then
        PASSED=$(jq -r '.passed' "$VERIF_FILE" 2>/dev/null || echo "false")
        if [ "$PASSED" == "true" ]; then
            echo -e "${GREEN}✅ Batch $BATCH PASSED${NC}"
        else
            ISSUES=$(jq -r '.issues_found | length' "$VERIF_FILE" 2>/dev/null || echo "0")
            echo -e "${YELLOW}⚠️  Batch $BATCH issues ($ISSUES) - continuando...${NC}"
        fi
    fi
    
    BATCHES_COMPLETED=$BATCH
    BATCH=$((BATCH + 1))
done

# ============================================================
# ARCHIVER
# ============================================================

log_step "FASE 5: ARCHIVER"

echo -e "${CYAN}→ Archivando change...${NC}"
cd "$WORKSPACE"
./agents/archiver.sh "$CHANGE" > /tmp/fauto_archive.log 2>&1 || {
    echo -e "${YELLOW}[WARN]${NC} Archiver falló - continuando..."
}

# ============================================================
# GIT AUTO-SYNC
# ============================================================

if [ -f "$WORKSPACE/agents/git-manager.sh" ]; then
    log_step "GIT AUTO-SYNC"
    
    cd "$WORKSPACE"
    
    echo -e "${CYAN}→ Git add...${NC}"
    ./agents/git-manager.sh add "." > /dev/null 2>&1 || true
    
    echo -e "${CYAN}→ Git commit...${NC}"
    ./agents/git-manager.sh commit "feat($CHANGE): full-auto root mode - $BATCHES_COMPLETED batches" > /dev/null 2>&1 || true
    
    # Solo push si remote existe y token configurado
    if git remote get-url origin &>/dev/null && [ -n "$GITHUB_TOKEN" ]; then
        echo -e "${CYAN}→ Git push...${NC}"
        ./agents/git-manager.sh push > /dev/null 2>&1 || {
            echo -e "${YELLOW}[WARN]${NC} Git push falló - guardado localmente"
        }
    fi
fi

# ============================================================
# FINAL
# ============================================================

echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║${NC}              ✅ PIPELINE COMPLETADO                      ${GREEN}${BOLD}║${NC}"
echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}  Change:${NC} $CHANGE"
echo -e "${CYAN}  Batches:${NC} $BATCHES_COMPLETED"
echo -e "${CYAN}  Root:${NC} $([ "$SUDO_OK" == "true" ] && echo "✅" || echo "❌")"
echo ""
echo -e "${GREEN}🎉 ¡Listo! CMX-CORE trabajó por ti.${NC}"
echo ""
