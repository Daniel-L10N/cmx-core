#!/bin/bash
# Memory Query - Consulta decisiones en cmx-memories (SQLite backend)
# Uso: memory-query.sh [project] [agent] [type] [limit]
# Uso: memory-query.sh --search "query" [project] [type] [limit]
#
# v2.1.1 — SECURITY: Input validation + robust SQL escaping + sanitization

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORIES_DB="$PROJECT_ROOT/memories.db"

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[QUERY]${NC} $1" >&2; }
log_search() { echo -e "${YELLOW}[SEARCH]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# CONSTANTES DE SEGURIDAD
# ============================================================================

VALID_TYPES="decision synthesis task note bugfix architecture"
MAX_LIMIT=1000
DEFAULT_LIMIT=50
MAX_QUERY_LENGTH=500

# ============================================================================
# SQL ESCAPE ROBUSTO (v2.1.1 — Security Hardening)
# ============================================================================

sql_escape() {
    local input="$1"

    # Paso 1: Escapar backslashes primero
    input="${input//\\/\\\\}"

    # Paso 2: Escapar comillas simples (SQLite: '' = literal ')
    input="${input//\'/\'\'}"

    # Paso 3: Escapar comillas dobles
    input="${input//\"/\\\"}"

    # Paso 4: Escapar caracteres de control
    input="${input//$'\t'/\\t}"
    input="${input//$'\n'/\\n}"
    input="${input//$'\r'/\\r}"

    echo "$input"
}

# Validar que un valor sea un tipo de memoria válido
validate_type() {
    local type_val="$1"
    if [ -z "$type_val" ]; then
        return 0  # Empty is OK (no filter)
    fi
    for vt in $VALID_TYPES; do
        if [ "$type_val" = "$vt" ]; then
            return 0
        fi
    done
    log_error "Tipo de memoria inválido: '$type_val'"
    log_error "Tipos válidos: $VALID_TYPES"
    return 1
}

# Validar y sanitizar un límite numérico
sanitize_limit() {
    local limit_val="$1"
    # Si no es numérico, usar default
    if ! [[ "$limit_val" =~ ^[0-9]+$ ]]; then
        log_warn "Límite inválido '$limit_val', usando $DEFAULT_LIMIT"
        echo "$DEFAULT_LIMIT"
        return
    fi
    # Si excede el máximo, caparlo
    if [ "$limit_val" -gt "$MAX_LIMIT" ]; then
        log_warn "Límite $limit_val excede máximo $MAX_LIMIT, capando..."
        echo "$MAX_LIMIT"
        return
    fi
    # Si es 0 o negativo, usar default
    if [ "$limit_val" -le 0 ]; then
        echo "$DEFAULT_LIMIT"
        return
    fi
    echo "$limit_val"
}

# ============================================================================
# PARSEO DE ARGUMENTOS
# ============================================================================

SEARCH_QUERY=""
PROJECT=""
AGENT=""
TYPE=""
LIMIT="$DEFAULT_LIMIT"

while [[ $# -gt 0 ]]; do
    case $1 in
        --search|-s)
            SEARCH_QUERY="$2"
            # Validar longitud de query
            if [ ${#SEARCH_QUERY} -gt $MAX_QUERY_LENGTH ]; then
                log_warn "Query excede $MAX_QUERY_LENGTH caracteres, truncando..."
                SEARCH_QUERY="${SEARCH_QUERY:0:$MAX_QUERY_LENGTH}"
            fi
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

# Sanitizar límite
LIMIT=$(sanitize_limit "$LIMIT")

# Validar tipo si se proporcionó
if [ -n "$TYPE" ]; then
    validate_type "$TYPE" || exit 1
fi

# Si no existe el archivo, devolver vacío
if [ ! -f "$MEMORIES_DB" ]; then
    echo "[]"
    exit 0
fi

# ============================================================================
# MODO BÚSQUEDA FTS5
# ============================================================================

if [ -n "$SEARCH_QUERY" ]; then
    log_search "Búsqueda FTS5: '$SEARCH_QUERY'"

    # Sanitizar query para FTS5
    # FTS5 usa su propio tokenizer, pero necesitamos escapar comillas
    ESCAPED_QUERY=$(sql_escape "$SEARCH_QUERY")

    # Construir consulta FTS5 con filtros opcionales
    FTS_WHERE=""
    if [ -n "$PROJECT" ]; then
        ESCAPED_PROJECT=$(sql_escape "$PROJECT")
        FTS_WHERE="AND m.project = '$ESCAPED_PROJECT'"
    fi
    if [ -n "$TYPE" ]; then
        ESCAPED_TYPE=$(sql_escape "$TYPE")
        FTS_WHERE="$FTS_WHERE AND m.type = '$ESCAPED_TYPE'"
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
    " 2>&1) || {
        log_error "Error en búsqueda FTS5: $RESULT"
        echo "[]"
        exit 1
    }

    if [ -z "$RESULT" ] || [ "$RESULT" = "[]" ]; then
        echo "[]"
    else
        echo "$RESULT"
    fi
    exit 0
fi

# ============================================================================
# MODO CONSULTA TRADICIONAL (por filtros)
# ============================================================================

WHERE_CLAUSE="1=1"

if [ -n "$PROJECT" ]; then
    ESCAPED_PROJECT=$(sql_escape "$PROJECT")
    WHERE_CLAUSE="$WHERE_CLAUSE AND project = '$ESCAPED_PROJECT'"
fi

if [ -n "$AGENT" ]; then
    ESCAPED_AGENT=$(sql_escape "$AGENT")
    WHERE_CLAUSE="$WHERE_CLAUSE AND agent = '$ESCAPED_AGENT'"
fi

if [ -n "$TYPE" ]; then
    ESCAPED_TYPE=$(sql_escape "$TYPE")
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
" 2>&1) || {
    log_error "Error en consulta: $RESULT"
    echo "[]"
    exit 1
}

if [ -z "$RESULT" ] || [ "$RESULT" = "[]" ]; then
    echo "[]"
else
    echo "$RESULT"
fi
