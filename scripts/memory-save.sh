#!/bin/bash
# Memory Save - Guarda decisiones en cmx-memories (JSON backend)
# Uso: memory-save.sh <type> <title> <content> [project] [agent] [task_id] [phase]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORIES_DB="$PROJECT_ROOT/memories.json"

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

# Generar UUID para task_id si no se proporciona
if [ -z "$TASK_ID" ]; then
    TASK_ID="task-$(date +%s)-$RANDOM"
fi

# Crear archivo si no existe
if [ ! -f "$MEMORIES_DB" ]; then
    echo '{"version": "1.0.0", "type": "memories", "memories": []}' > "$MEMORIES_DB"
fi

# Generar ID único
MEMORY_ID=$(date +%s)$RANDOM

# Crear nuevo registro
TIMESTAMP=$(date -Iseconds)
NEW_ENTRY=$(cat <<EOF
{
  "id": $MEMORY_ID,
  "type": "$TYPE",
  "title": "$TITLE",
  "content": "$CONTENT",
  "project": "$PROJECT",
  "agent": "$AGENT",
  "task_id": "$TASK_ID",
  "phase": "$PHASE",
  "created_at": "$TIMESTAMP",
  "updated_at": "$TIMESTAMP"
}
EOF
)

# Agregar al JSON usando jq
TEMP_FILE=$(mktemp)
jq --argjson entry "$NEW_ENTRY" '.memories += [$entry]' "$MEMORIES_DB" > "$TEMP_FILE" && mv "$TEMP_FILE" "$MEMORIES_DB"

log_ok "Memoria guardada: ID=$MEMORY_ID, type=$TYPE, project=$PROJECT"

# Output JSON para consumo programático
echo "{"
echo "  \"status\": \"saved\","
echo "  \"id\": $MEMORY_ID,"
echo "  \"type\": \"$TYPE\","
echo "  \"project\": \"$PROJECT\","
echo "  \"agent\": \"$AGENT\","
echo "  \"task_id\": \"$TASK_ID\","
echo "  \"phase\": \"$PHASE\","
echo "  \"timestamp\": \"$TIMESTAMP\""
echo "}"