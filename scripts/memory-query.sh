#!/bin/bash
# Memory Query - Consulta decisiones en cmx-memories (SQLite backend)
# Uso: memory-query.sh [project] [agent] [type] [limit]
# Uso: memory-query.sh --search "query" [project] [type] [limit]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORIES_DB="$PROJECT_ROOT/memories.db"

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[QUERY]${NC} $1"; }
log_search() { echo -e "${YELLOW}[SEARCH]${NC} $1"; }

# Parsear argumentos
SEARCH_QUERY=""
PROJECT=""
AGENT=""
TYPE=""
LIMIT="50"

while [[ $# -gt 0 ]]; do
    case $1 in
        --search|-s)
            SEARCH_QUERY="$2"
            shift 2
            ;;
        --project|-p)
            PROJECT="$2"
            shift 2
            ;;
        --agent|-a)
            AGENT="$2"
            shift 2
            ;;
        --type|-t)
            TYPE="$2"
            shift 2
            ;;
        --limit|-l)
            LIMIT="$2"
            shift 2
            ;;
        -*)
            # Ignorar opciones desconocidas para backwards compatibility
            shift
            ;;
        *)
            # Argumentos posicionales (legacy)
            if [ -z "$PROJECT" ]; then
                PROJECT="$1"
            elif [ -z "$AGENT" ]; then
                AGENT="$1"
            elif [ -z "$TYPE" ]; then
                TYPE="$1"
            elif [ -z "$LIMIT" ] && [[ "$1" =~ ^[0-9]+$ ]]; then
                LIMIT="$1"
            fi
            shift
            ;;
    esac
done

# Si no existe el archivo, devolver vacío
if [ ! -f "$MEMORIES_DB" ]; then
    echo "[]"
    exit 0
fi

# Modo búsqueda FTS5
if [ -n "$SEARCH_QUERY" ]; then
    log_search "Búsqueda FTS5: '$SEARCH_QUERY'"
    
    # Escapar comillas para FTS5
    ESCAPED_QUERY=$(echo "$SEARCH_QUERY" | sed "s/'/''/g")
    
    # Construir consulta FTS5 con filtros opcionales
    FTS_WHERE=""
    if [ -n "$PROJECT" ]; then
        FTS_WHERE="AND m.project = '$PROJECT'"
    fi
    if [ -n "$TYPE" ]; then
        FTS_WHERE="$FTS_WHERE AND m.type = '$TYPE'"
    fi
    
    # Consulta FTS5 con bm25 ranking
    RESULT=$(sqlite3 "$MEMORIES_DB" "
    SELECT json_group_array(
        json_object(
            'id', m.id,
            'type', m.type,
            'title', m.title,
            'content', m.content,
            'project', m.project,
            'agent', m.agent,
            'task_id', m.task_id,
            'phase', m.phase,
            'created_at', m.created_at,
            'updated_at', m.updated_at
        )
    )
    FROM memories m
    INNER JOIN memories_fts fts ON m.id = fts.rowid
    WHERE memories_fts MATCH '$ESCAPED_QUERY'
    $FTS_WHERE
    ORDER BY bm25(memories_fts)
    LIMIT $LIMIT;
    ")
    
    if [ -z "$RESULT" ] || [ "$RESULT" = "[]" ]; then
        echo "[]"
    else
        echo "$RESULT"
    fi
    exit 0
fi

# Modo consulta tradicional (por filtros)
WHERE_CLAUSE="1=1"

if [ -n "$PROJECT" ]; then
    ESCAPED_PROJECT=$(echo "$PROJECT" | sed "s/'/''/g")
    WHERE_CLAUSE="$WHERE_CLAUSE AND project = '$ESCAPED_PROJECT'"
fi

if [ -n "$AGENT" ]; then
    ESCAPED_AGENT=$(echo "$AGENT" | sed "s/'/''/g")
    WHERE_CLAUSE="$WHERE_CLAUSE AND agent = '$ESCAPED_AGENT'"
fi

if [ -n "$TYPE" ]; then
    ESCAPED_TYPE=$(echo "$TYPE" | sed "s/'/''/g")
    WHERE_CLAUSE="$WHERE_CLAUSE AND type = '$ESCAPED_TYPE'"
fi

# Consulta SQL
RESULT=$(sqlite3 "$MEMORIES_DB" "
SELECT json_group_array(
    json_object(
        'id', id,
        'type', type,
        'title', title,
        'content', content,
        'project', project,
        'agent', agent,
        'task_id', task_id,
        'phase', phase,
        'created_at', created_at,
        'updated_at', updated_at
    )
)
FROM (
    SELECT * FROM memories
    WHERE $WHERE_CLAUSE
    ORDER BY created_at DESC
    LIMIT $LIMIT
);
")

if [ -z "$RESULT" ] || [ "$RESULT" = "[]" ]; then
    echo "[]"
else
    echo "$RESULT"
fi