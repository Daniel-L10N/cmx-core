#!/bin/bash
# Cognitive Stack v2 — Agent: Archiver
# Archiva todos los artifacts y logs al completar un change
# Input: change-name
# Output: artifacts/archive/{change}_{timestamp}/

set -e

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CHANGE="${1}"

# ============================================================
# VALIDACIONES
# ============================================================

if [ -z "$CHANGE" ]; then
    echo "ERROR: Uso: archiver.sh <change-name>"
    exit 1
fi

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[ARCHIVER]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================
# RUTAS
# ============================================================

STATE_FILE="$WORKSPACE/orchestrator/agent_state.json"
ARCHIVE_DIR="$WORKSPACE/artifacts/archive/${CHANGE}_$(date +%Y%m%d_%H%M%S)"
ACTIVE_LOGS="$WORKSPACE/orchestrator/logs/active"
HISTORY_LOGS="$WORKSPACE/orchestrator/logs/history"

# ============================================================
# PREPARAR DIRECTORIOS
# ============================================================

log "Iniciando archivado para: $CHANGE"
log "Directorio de archive: $ARCHIVE_DIR"

mkdir -p "$ARCHIVE_DIR"
mkdir -p "$HISTORY_LOGS"

# ============================================================
# MOVER ARTIFACTS A ARCHIVE
# ============================================================

log "Moviendo artifacts a archive..."

# Proposals
if [ -d "$WORKSPACE/artifacts/proposals" ]; then
    for file in "$WORKSPACE/artifacts/proposals/${CHANGE}"*.json; do
        if [ -f "$file" ]; then
            mv "$file" "$ARCHIVE_DIR/"
            log_ok "Archivado: $(basename "$file")"
        fi
    done
fi

# Specs
if [ -d "$WORKSPACE/artifacts/specs" ]; then
    for file in "$WORKSPACE/artifacts/specs/${CHANGE}"*.json; do
        if [ -f "$file" ]; then
            mv "$file" "$ARCHIVE_DIR/"
            log_ok "Archivado: $(basename "$file")"
        fi
    done
fi

# Designs
if [ -d "$WORKSPACE/artifacts/designs" ]; then
    for file in "$WORKSPACE/artifacts/designs/${CHANGE}"*.json; do
        if [ -f "$file" ]; then
            mv "$file" "$ARCHIVE_DIR/"
            log_ok "Archivado: $(basename "$file")"
        fi
    done
fi

# Tasks
if [ -d "$WORKSPACE/artifacts/tasks" ]; then
    for file in "$WORKSPACE/artifacts/tasks/${CHANGE}"*.json; do
        if [ -f "$file" ]; then
            mv "$file" "$ARCHIVE_DIR/"
            log_ok "Archivado: $(basename "$file")"
        fi
    done
fi

# Implementation (all batches)
if [ -d "$WORKSPACE/artifacts/implementation" ]; then
    for file in "$WORKSPACE/artifacts/implementation/${CHANGE}"*.json; do
        if [ -f "$file" ]; then
            mv "$file" "$ARCHIVE_DIR/"
            log_ok "Archivado: $(basename "$file")"
        fi
    done
fi

# Verification (all batches)
if [ -d "$WORKSPACE/artifacts/verification" ]; then
    for file in "$WORKSPACE/artifacts/verification/${CHANGE}"*.json; do
        if [ -f "$file" ]; then
            mv "$file" "$ARCHIVE_DIR/"
            log_ok "Archivado: $(basename "$file")"
        fi
    done
fi

# Exploration
if [ -d "$WORKSPACE/artifacts/exploration" ]; then
    for file in "$WORKSPACE/artifacts/exploration/${CHANGE}"*.json; do
        if [ -f "$file" ]; then
            mv "$file" "$ARCHIVE_DIR/"
            log_ok "Archivado: $(basename "$file")"
        fi
    done
fi

# ============================================================
# MOVER LOGS A HISTORY
# ============================================================

log "Moviendo logs a history..."

for logfile in "$ACTIVE_LOGS"/*.log; do
    if [ -f "$logfile" ]; then
        mv "$logfile" "$HISTORY_LOGS/"
        log_ok "Histórico: $(basename "$logfile")"
    fi
done

# Limpiar PID files
rm -f "$ACTIVE_LOGS"/*.pid 2>/dev/null || true

# ============================================================
# ACTUALIZAR STATE
# ============================================================

log "Actualizando agent_state.json..."

if [ -f "$STATE_FILE" ]; then
    # Actualizar status del archiver
    jq ".agents.archiver.status = \"completed\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && \
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    # Actualizar completed_at general
    TIMESTAMP=$(date -Iseconds)
    jq ".completed_at = \"$TIMESTAMP\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && \
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    # Actualizar status del archiver agent
    jq ".agents.archiver.completed_at = \"$TIMESTAMP\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && \
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    
    jq ".agents.archiver.confidence_score = 10" "$STATE_FILE" > "${STATE_FILE}.tmp" && \
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

# ============================================================
# RESUMEN
# ============================================================

log_ok "=========================================="
log_ok "Archivado completado"
log_ok "Change: $CHANGE"
log_ok "Archive: $ARCHIVE_DIR"
log_ok "=========================================="

# Mostrar contenido del archive
log "Contenido del archive:"
ls -la "$ARCHIVE_DIR/"

# ============================================================
# GIT PUSH + TAGS
# ============================================================

log "Ejecutando git push..."

if git rev-parse --git-dir > /dev/null 2>&1; then
    # git push
    if git push; then
        log_ok "git push completado"
    else
        log_error "git push falló"
    fi
    
    # Generar tag automático
    TAG_NAME="${CHANGE}_$(date +%Y%m%d_%H%M%S)"
    TAG_MESSAGE="Archivado automático del change: $CHANGE"
    
    log "Creando tag: $TAG_NAME"
    git tag -a "$TAG_NAME" -m "$TAG_MESSAGE"
    
    # git push --tags
    if git push --tags; then
        log_ok "git push --tags completado"
    else
        log_error "git push --tags falló"
    fi
else
    log_error "No es un repositorio git"
fi

exit 0
