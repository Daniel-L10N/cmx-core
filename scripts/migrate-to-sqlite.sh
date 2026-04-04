#!/bin/bash
# Migrate to SQLite - Migra datos de memories.json a memories.db
# Uso: migrate-to-sqlite.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JSON_FILE="$PROJECT_ROOT/memories.json"
DB_FILE="$PROJECT_ROOT/memories.db"

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[MIGRATE]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verificar que existe el archivo JSON
if [ ! -f "$JSON_FILE" ]; then
    log_error "No se encontró: $JSON_FILE"
    exit 1
fi

# Verificar que existe la base de datos
if [ ! -f "$DB_FILE" ]; then
    log_error "No se encontró: $DB_FILE"
    log_error "Ejecuta primero: cmx-memories-init.sh"
    exit 1
fi

log "Iniciando migración de $JSON_FILE a $DB_FILE"

# Contar memorias en JSON
MEMORY_COUNT=$(jq '.memories | length' "$JSON_FILE")
log "Memorias encontradas en JSON: $MEMORY_COUNT"

if [ "$MEMORY_COUNT" -eq 0 ]; then
    log_warn "No hay memorias para migrar"
    exit 0
fi

# Migrar cada memoria
MIGRATED=0
FAILED=0

for i in $(seq 0 $((MEMORY_COUNT - 1))); do
    # Extraer cada memoria
    MEM=$(jq -r ".memories[$i]" "$JSON_FILE")
    
    ID=$(echo "$MEM" | jq -r '.id')
    TYPE=$(echo "$MEM" | jq -r '.type')
    TITLE=$(echo "$MEM" | jq -r '.title')
    CONTENT=$(echo "$MEM" | jq -r '.content')
    PROJECT=$(echo "$MEM" | jq -r '.project')
    AGENT=$(echo "$MEM" | jq -r '.agent')
    TASK_ID=$(echo "$MEM" | jq -r '.task_id // empty')
    PHASE=$(echo "$MEM" | jq -r '.phase // empty')
    CREATED=$(echo "$MEM" | jq -r '.created_at')
    UPDATED=$(echo "$MEM" | jq -r '.updated_at')
    
    # Escapar para SQL
    ESCAPED_TITLE=$(echo "$TITLE" | sed "s/'/''/g")
    ESCAPED_CONTENT=$(echo "$CONTENT" | sed "s/'/''/g")
    ESCAPED_PROJECT=$(echo "$PROJECT" | sed "s/'/''/g")
    ESCAPED_AGENT=$(echo "$AGENT" | sed "s/'/''/g")
    ESCAPED_TASK_ID=$(echo "$TASK_ID" | sed "s/'/''/g")
    ESCAPED_PHASE=$(echo "$PHASE" | sed "s/'/''/g")
    
    # Convertir formato de fecha ISO a SQLite
    CREATED_SQL=$(echo "$CREATED" | sed 's/T/ /g' | sed 's/-06:00//g')
    UPDATED_SQL=$(echo "$UPDATED" | sed 's/T/ /g' | sed 's/-06:00//g')
    
    # Insertar en SQLite
    if sqlite3 "$DB_FILE" "
    INSERT INTO memories (id, type, title, content, project, agent, task_id, phase, created_at, updated_at)
    VALUES ($ID, '$TYPE', '$ESCAPED_TITLE', '$ESCAPED_CONTENT', '$ESCAPED_PROJECT', '$ESCAPED_AGENT', '$ESCAPED_TASK_ID', '$ESCAPED_PHASE', '$CREATED_SQL', '$UPDATED_SQL');
    " 2>/dev/null; then
        MIGRATED=$((MIGRATED + 1))
    else
        # Puede fallar si el ID ya existe (PK constraint)
        # Intentar sin especificar ID (auto-increment)
        if sqlite3 "$DB_FILE" "
        INSERT INTO memories (type, title, content, project, agent, task_id, phase, created_at, updated_at)
        VALUES ('$TYPE', '$ESCAPED_TITLE', '$ESCAPED_CONTENT', '$ESCAPED_PROJECT', '$ESCAPED_AGENT', '$ESCAPED_TASK_ID', '$ESCAPED_PHASE', '$CREATED_SQL', '$UPDATED_SQL');
        " 2>/dev/null; then
            MIGRATED=$((MIGRATED + 1))
        else
            FAILED=$((FAILED + 1))
        fi
    fi
done

log_ok "Migración completada: $MIGRATED insertadas, $FAILED fallidas"

# Contar total en SQLite
TOTAL=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM memories;")
log "Total memorias en SQLite: $TOTAL"

# Verificar que FTS5 está sincronizado
FTS_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM memories_fts;")
log "Índices FTS5: $FTS_COUNT"

if [ "$TOTAL" -eq "$FTS_COUNT" ]; then
    log_ok "FTS5 sincronizado correctamente"
else
    log_warn "FTS5 desincronizado: $TOTAL memorias vs $FTS_COUNT índices"
    log "Reconstruyendo índice FTS5..."
    sqlite3 "$DB_FILE" "INSERT INTO memories_fts(memories_fts) VALUES('rebuild');"
    log_ok "Índice FTS5 reconstruido"
fi

echo ""
echo "Migración finalizada exitosamente"