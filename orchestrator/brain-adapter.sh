#!/bin/bash
# Brain Adapter — Conecta brain.sh con pipeline.sh SDD
# Uso: brain-adapter.sh --task-id <id> --intent <explore|propose|spec|design|tasks|apply|verify|archive|auto> --change <name> [--mode <hybrid|autonomous|manual>]
#
# Este script traduce las decisiones del cerebro en ejecución del pipeline SDD

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PIPELINE="$PROJECT_ROOT/orchestrator/pipeline.sh"
MEMORY_SAVE="$PROJECT_ROOT/scripts/memory-save.sh"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
MODE="hybrid"
START_PHASE="explore"
CHANGE_NAME=""

log() { echo -e "${BLUE}[ADAPTER]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# PARSEO DE ARGUMENTOS
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --task-id)
            TASK_ID="$2"
            shift 2
            ;;
        --intent|-i)
            INTENT="$2"
            shift 2
            ;;
        --change|-c)
            CHANGE_NAME="$2"
            shift 2
            ;;
        --mode|-m)
            MODE="$2"
            shift 2
            ;;
        --start-phase|-s)
            START_PHASE="$2"
            shift 2
            ;;
        --help|-h)
            echo "Brain Adapter - Conecta brain.sh con pipeline.sh SDD"
            echo ""
            echo "Uso: $0 --task-id <id> --intent <intent> --change <name> [opciones]"
            echo ""
            echo "Opciones requeridas:"
            echo "  --task-id <id>    ID de la tarea"
            echo "  --intent <intent> Tipo de intención (auto|explore|propose|spec|design|tasks|apply|verify|archive)"
            echo "  --change <name>   Nombre del change"
            echo ""
            echo "Opciones opcionales:"
            echo "  --mode            Modo de ejecución: hybrid, autonomous, manual (default: hybrid)"
            echo "  --start-phase     Fase inicial del pipeline (default: explore)"
            echo ""
            echo "Ejemplos:"
            echo "  $0 --task-id task-123 --intent auto --change nueva-feature"
            echo "  $0 --task-id task-456 --intent spec --change fix-bug --start-phase spec"
            exit 0
            ;;
        *)
            log_error "Opción desconocida: $1"
            exit 1
            ;;
    esac
done

# Validar argumentos requeridos
if [ -z "$TASK_ID" ]; then
    log_error "Falta --task-id"
    exit 1
fi

if [ -z "$INTENT" ]; then
    log_error "Falta --intent"
    exit 1
fi

if [ -z "$CHANGE_NAME" ]; then
    log_error "Falta --change"
    exit 1
fi

# =============================================================================
# MAPEO DE INTENT A FASE(S)
# =============================================================================

# Función para determinar qué fase ejecutar basado en el intent
map_intent_to_phase() {
    local intent="$1"
    case "$intent" in
        auto)
            # Modo automático: determina la fase basada en el análisis del brain
            echo "explore"
            ;;
        explore)
            echo "explore"
            ;;
        propose)
            echo "propose"
            ;;
        spec)
            echo "spec"
            ;;
        design)
            echo "design"
            ;;
        tasks)
            echo "tasks"
            ;;
        apply)
            echo "apply"
            ;;
        verify)
            echo "verify"
            ;;
        archive)
            echo "archive"
            ;;
        full)
            # Ejecutar pipeline completo
            echo "full"
            ;;
        *)
            log_error "Intent desconocido: $intent"
            echo "explore"  # fallback
            ;;
    esac
}

# Determinar fase(s) a ejecutar
PHASE=$(map_intent_to_phase "$INTENT")

log "Iniciando brain-adapter para tarea: $TASK_ID"
log "Intent: $INTENT -> Phase: $PHASE"
log "Change: $CHANGE_NAME"
log "Mode: $MODE"

# Guardar decisión del adapter
"$MEMORY_SAVE" "decision" "brain-adapter-start" \
    "Brain adapter iniciado: intent=$INTENT, phase=$PHASE, change=$CHANGE_NAME, mode=$MODE" \
    "cmx-core" "brain-adapter" "$TASK_ID" "adapter"

# =============================================================================
# DETECCIÓN DE MODO DE AUTONOMÍA
# =============================================================================

# Si el intent es "auto", analizar el tipo de tarea para determinar el flujo
if [ "$INTENT" = "auto" ]; then
    log "Modo automático - determinando flujo completo..."
    
    # En modo auto, ejecutamos el pipeline completo
    PHASE="full"
fi

# =============================================================================
# EJECUCIÓN DEL PIPELINE
# =============================================================================

log "Ejecutando pipeline.sh..."

#depending on the phase, call pipeline with different arguments
case "$PHASE" in
    full)
        log "Ejecutando pipeline completo para: $CHANGE_NAME"
        "$PIPELINE" run "$CHANGE_NAME" 2>&1
        PIPELINE_EXIT=$?
        ;;
    *)
        log "Ejecutando fase '$PHASE' para: $CHANGE_NAME"
        "$PIPELINE" run "$CHANGE_NAME" "$PHASE" 2>&1
        PIPELINE_EXIT=$?
        ;;
esac

# =============================================================================
# PROCESAR RESULTADO
# =============================================================================

if [ $PIPELINE_EXIT -eq 0 ]; then
    log_ok "Pipeline completado exitosamente"
    
    # Guardar resultado exitoso
    "$MEMORY_SAVE" "decision" "brain-adapter-success" \
        "Pipeline completado: phase=$PHASE, change=$CHANGE_NAME, exit=$PIPELINE_EXIT" \
        "cmx-core" "brain-adapter" "$TASK_ID" "adapter"
    
    # Output JSON para consumo programático
    echo "{"
    echo "  \"status\": \"success\","
    echo "  \"task_id\": \"$TASK_ID\","
    echo "  \"intent\": \"$INTENT\","
    echo "  \"phase\": \"$PHASE\","
    echo "  \"change\": \"$CHANGE_NAME\","
    echo "  \"mode\": \"$MODE\","
    echo "  \"exit_code\": $PIPELINE_EXIT,"
    echo "  \"timestamp\": \"$(date -Iseconds)\""
    echo "}"
else
    log_error "Pipeline falló con código: $PIPELINE_EXIT"
    
    # Guardar resultado fallido
    "$MEMORY_SAVE" "decision" "brain-adapter-failure" \
        "Pipeline falló: phase=$PHASE, change=$CHANGE_NAME, exit=$PIPELINE_EXIT" \
        "cmx-core" "brain-adapter" "$TASK_ID" "adapter"
    
    # Output JSON para consumo programático
    echo "{"
    echo "  \"status\": \"failed\","
    echo "  \"task_id\": \"$TASK_ID\","
    echo "  \"intent\": \"$INTENT\","
    echo "  \"phase\": \"$PHASE\","
    echo "  \"change\": \"$CHANGE_NAME\","
    echo "  \"mode\": \"$MODE\","
    echo "  \"exit_code\": $PIPELINE_EXIT,"
    echo "  \"timestamp\": \"$(date -Iseconds)\""
    echo "}"
    
    exit $PIPELINE_EXIT
fi