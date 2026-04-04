#!/bin/bash
# Memory Save - Guarda decisiones en cmx-memories (SQLite backend)
# Uso: memory-save.sh <type> <title> <content> [project] [agent] [task_id] [phase]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORIES_DB="$PROJECT_ROOT/memories.db"

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

TYPE="${1:-decision}"
TITLE="${2:-Untitled}"
CONTENT="$3"
PROJECT="${4:-cmx-core}"
AGENT="${5:-system}"
TASK_ID="${6:-}"
PHASE="${7:-}"

log_ok() { echo -e "${GREEN}[SAVE]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [ -z "$CONTENT" ]; then
    log_error "Contenido no proporcionado"
    echo "Uso: memory-save.sh <type> <title> <content> [project] [agent> [task_id] [phase]"
    exit 1
fi

# Verificar que la base de datos existe
if [ ! -f "$MEMORIES_DB" ]; then
    log_error "Base de datos no encontrada: $MEMORIES_DB"
    log_error "Ejecuta primero: cmx-memories-init.sh"
    exit 1
fi

# Generar task_id si no se proporciona
if [ -z "$TASK_ID" ]; then
    TASK_ID="task-$(date +%s)"
fi

# Escapar contenido para SQL (prevenir inyección y errores)
# Usar SQLite con parameterized queries a través de bash
ESCAPED_TITLE=$(echo "$TITLE" | sed "s/'/''/g")
ESCAPED_CONTENT=$(echo "$CONTENT" | sed "s/'/''/g")
ESCAPED_PROJECT=$(echo "$PROJECT" | sed "s/'/''/g")
ESCAPED_AGENT=$(echo "$AGENT" | sed "s/'/''/g")
ESCAPED_TASK_ID=$(echo "$TASK_ID" | sed "s/'/''/g")
ESCAPED_PHASE=$(echo "$PHASE" | sed "s/'/''/g")

# Insertar en la base de datos
RESULT=$(sqlite3 "$MEMORIES_DB" "
INSERT INTO memories (type, title, content, project, agent, task_id, phase, created_at, updated_at)
VALUES (
    '$TYPE',
    '$ESCAPED_TITLE',
    '$ESCAPED_CONTENT',
    '$ESCAPED_PROJECT',
    '$ESCAPED_AGENT',
    '$ESCAPED_TASK_ID',
    '$ESCAPED_PHASE',
    datetime('now'),
    datetime('now')
);
SELECT last_insert_rowid();
")

if [ $? -eq 0 ]; then
    TIMESTAMP=$(date -Iseconds)
    log_ok "Memoria guardada: ID=$RESULT, type=$TYPE, project=$PROJECT"
    
    # Output JSON para consumo programático
    echo "{"
    echo "  \"status\": \"saved\","
    echo "  \"id\": $RESULT,"
    echo "  \"type\": \"$TYPE\","
    echo "  \"project\": \"$PROJECT\","
    echo "  \"agent\": \"$AGENT\","
    echo "  \"task_id\": \"$TASK_ID\","
    echo "  \"phase\": \"$PHASE\","
    echo "  \"timestamp\": \"$TIMESTAMP\""
    echo "}"
else
    log_error "Error al guardar la memoria"
    exit 1
fi