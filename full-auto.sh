#!/bin/bash
# CMX-CORE — Full Auto Pipeline (DANGEROUS MODE)
# Ejecula el pipeline completo con privilegios elevados
# Uso: ./full-auto.sh <change-name>
# Requiere: modo cmx-dangerous activo

set +e  # NO salir en errores - continuar siempre

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CHANGE="${1}"

# ============================================================
# CARGAR CONTRASEÑA SUDO SI EXISTE
# ============================================================

SUDO_PASS_FILE="$HOME/.cmx-secrets/sudo.pass"
SUDO_READY=false

if [ -f "$SUDO_PASS_FILE" ]; then
    SUDO_PASSWORD=$(cat "$SUDO_PASS_FILE")
    SUDO_READY=true
fi

# Función para ejecutar con sudo
sudo_cmd() {
    if [ "$SUDO_READY" == "true" ]; then
        echo "$SUDO_PASSWORD" | sudo -S "$@" 2>/dev/null
    else
        sudo "$@" 2>/dev/null
    fi
}

# Verificar acceso sudo
SUDO_OK=false
if sudo -n true 2>/dev/null || [ "$SUDO_READY" == "true" ]; then
    if [ "$SUDO_READY" == "true" ]; then
        echo "$SUDO_PASSWORD" | sudo -S true 2>/dev/null && SUDO_OK=true
    else
        SUDO_OK=true
    fi
fi

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
# VALIDACIONES
# ============================================================

if [ -z "$CHANGE" ]; then
    echo -e "${RED}ERROR: Uso: ./full-auto.sh <change-name>${NC}"
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
    echo -e "${YELLOW}⚠️  Activando modo dangerous...${NC}"
    jq ".active = \"cmx-dangerous\"" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && \
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    CURRENT_MODE="cmx-dangerous"
fi

# ============================================================
# HEADER
# ============================================================

echo ""
echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║${NC}         🚀 CMX-CORE — FULL AUTO (DANGEROUS)      ${GREEN}${BOLD}║${NC}"
echo -e "${GREEN}${BOLD}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}${BOLD}║${NC}  Change: ${CYAN}$CHANGE${NC}                                        ${GREEN}${BOLD}║${NC}"
echo -e "${GREEN}${BOLD}║${NC}  Modo:   ${RED}DANGEROUS${NC} 🔥                             ${GREEN}${BOLD}║${NC}"
echo -e "${GREEN}${BOLD}║${NC}  Sudo:    $([ "$SUDO_OK" == "true" ] && echo "${GREEN}✅ LISTO" || echo "${YELLOW}⚠️ LIMITADO${NC})                    ${GREEN}${BOLD}║${NC}"
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
    while ps -p $pid > /dev/null 2>&1; do
        sleep 5
        echo -n "."
    done
    echo ""
}

# FASE 1: PROPOSER
log_step "FASE 1: PROPOSER"
cd "$WORKSPACE"
./agents/proposer.sh "$CHANGE" > /tmp/fauto_proposer.log 2>&1 &
wait_for_agent $!

# FASE 2: SPEC + DESIGN (paralelo)
log_step "FASE 2: SPEC + DESIGN"
./agents/spec-writer.sh "$CHANGE" > /tmp/fauto_spec.log 2>&1 &
PID_SPEC=$!
./agents/designer.sh "$CHANGE" > /tmp/fauto_design.log 2>&1 &
PID_DESIGN=$!
wait
echo -e "${GREEN}✅ Spec + Design completados${NC}"

# FASE 3: TASKS
log_step "FASE 3: TASK PLANNER"
./agents/task-planner.sh "$CHANGE" > /tmp/fauto_tasks.log 2>&1 &
wait_for_agent $!

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
    
    TASKS_FILE="$WORKSPACE/artifacts/tasks/${CHANGE}.json"
    if [ ! -f "$TASKS_FILE" ]; then
        echo -e "${GREEN}✅ No más batches${NC}"
        break
    fi
    
    BATCH_EXISTS=$(jq -r ".batch_recommendations[] | select(.batch == $BATCH) | .tasks | length" "$TASKS_FILE" 2>/dev/null || echo "0")
    
    if [ "$BATCH_EXISTS" == "0" ] || [ -z "$BATCH_EXISTS" ]; then
        echo -e "${GREEN}✅ No más batches${NC}"
        break
    fi
    
    # IMPLEMENTER
    echo -e "${CYAN}→ Implementando batch $BATCH...${NC}"
    ./agents/implementer.sh "$CHANGE" $BATCH > /tmp/fauto_impl_${BATCH}.log 2>&1 &
    wait_for_agent $!
    
    # VERIFIER
    echo -e "${CYAN}→ Verificando batch $BATCH...${NC}"
    ./agents/verifier.sh "$CHANGE" $BATCH > /tmp/fauto_verif_${BATCH}.log 2>&1 &
    wait_for_agent $!
    
    VERIF_FILE="$WORKSPACE/artifacts/verification/${CHANGE}_batch_${BATCH}.json"
    if [ -f "$VERIF_FILE" ]; then
        PASSED=$(jq -r '.passed' "$VERIF_FILE" 2>/dev/null || echo "false")
        if [ "$PASSED" == "true" ]; then
            echo -e "${GREEN}✅ Batch $BATCH PASSED${NC}"
        else
            echo -e "${YELLOW}⚠️  Batch $BATCH issues - continuando...${NC}"
        fi
    fi
    
    BATCHES_COMPLETED=$BATCH
    BATCH=$((BATCH + 1))
done

# ============================================================
# ARCHIVER
# ============================================================

log_step "FASE 5: ARCHIVER"
./agents/archiver.sh "$CHANGE" > /tmp/fauto_archive.log 2>&1 || {
    echo -e "${YELLOW}[WARN]${NC} Archiver falló - continuando..."
}

# ============================================================
# GIT AUTO-SYNC
# ============================================================

if [ -f "$WORKSPACE/agents/git-manager.sh" ]; then
    log_step "GIT AUTO-SYNC"
    
    ./agents/git-manager.sh add "." > /dev/null 2>&1 || true
    ./agents/git-manager.sh commit "feat($CHANGE): full-auto dangerous - $BATCHES_COMPLETED batches" > /dev/null 2>&1 || true
    
    if git remote get-url origin &>/dev/null && [ -n "$GITHUB_TOKEN" ]; then
        ./agents/git-manager.sh push > /dev/null 2>&1 || {
            echo -e "${YELLOW}[WARN]${NC} Git push falló"
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
echo -e "${CYAN}  Sudo:  ${NC}$([ "$SUDO_OK" == "true" ] && echo "${GREEN}✅" || echo "${YELLOW}⚠️")"
echo ""
echo -e "${GREEN}🎉 ¡Listo! CMX-CORE trabajó por ti.${NC}"
echo ""
