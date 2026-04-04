#!/bin/bash
# Memory Save - Guarda decisiones en cmx-memories (SQLite backend)
# Uso: memory-save.sh <type> <title> <content> [project] [agent] [task_id] [phase]
#
# v2.1.1 — SECURITY: Input validation + robust SQL escaping + size limits

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
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ============================================================================
# CONSTANTES DE SEGURIDAD
# ============================================================================

# Tipos de memoria válidos
VALID_TYPES="decision synthesis task note bugfix architecture"

# Límites de tamaño (bytes)
MAX_TITLE_LENGTH=500
MAX_CONTENT_LENGTH=500000  # ~500KB
MAX_PROJECT_LENGTH=100
MAX_AGENT_LENGTH=100

# ============================================================================
# VALIDACIÓN DE INPUT
# ============================================================================

validate_inputs() {
    # Verificar que el contenido no esté vacío
    if [ -z "$CONTENT" ]; then
        log_error "Contenido no proporcionado"
        echo "Uso: memory-save.sh <type> <title> <content> [project] [agent] [task_id] [phase]"
        exit 1
    fi

    # Validar tipo de memoria
    local type_valid=false
    for vt in $VALID_TYPES; do
        if [ "$TYPE" = "$vt" ]; then
            type_valid=true
            break
        fi
    done
    if [ "$type_valid" = false ]; then
        log_error "Tipo de memoria inválido: '$TYPE'"
        log_error "Tipos válidos: $VALID_TYPES"
        exit 1
    fi

    # Validar longitud de title
    if [ ${#TITLE} -gt $MAX_TITLE_LENGTH ]; then
        log_warn "Title excede $MAX_TITLE_LENGTH caracteres, truncando..."
        TITLE="${TITLE:0:$MAX_TITLE_LENGTH}"
    fi

    # Validar longitud de content
    if [ ${#CONTENT} -gt $MAX_CONTENT_LENGTH ]; then
        log_warn "Content excede $MAX_CONTENT_LENGTH caracteres, truncando..."
        CONTENT="${CONTENT:0:$MAX_CONTENT_LENGTH}"
    fi

    # Validar longitud de project
    if [ ${#PROJECT} -gt $MAX_PROJECT_LENGTH ]; then
        log_warn "Project excede $MAX_PROJECT_LENGTH caracteres, truncando..."
        PROJECT="${PROJECT:0:$MAX_PROJECT_LENGTH}"
    fi

    # Validar longitud de agent
    if [ ${#AGENT} -gt $MAX_AGENT_LENGTH ]; then
        log_warn "Agent excede $MAX_AGENT_LENGTH caracteres, truncando..."
        AGENT="${AGENT:0:$MAX_AGENT_LENGTH}"
    fi

    # Validar que no haya caracteres NUL
    if echo "$CONTENT" | grep -qP '\x00' 2>/dev/null; then
        log_error "Contenido contiene caracteres NUL no permitidos"
        exit 1
    fi
}

# ============================================================================
# SQL ESCAPE ROBUSTO (v2.1.1 — Security Hardening)
# ============================================================================

# Escapa contenido para uso seguro en SQL literals de SQLite
# Protege contra: SQL injection, caracteres especiales, secuencias de comentario
sql_escape() {
    local input="$1"

    # Paso 1: Escapar backslashes primero (antes que comillas simples)
    input="${input//\\/\\\\}"

    # Paso 2: Escapar comillas simples (SQLite: '' = literal ')
    input="${input//\'/\'\'}"

    # Paso 3: Escapar comillas dobles
    input="${input//\"/\\\"}"

    # Paso 4: Escapar tabuladores y newlines para evitar corrupción de SQL
    input="${input//$'\t'/\\t}"
    input="${input//$'\n'/\\n}"
    input="${input//$'\r'/\\r}"

    echo "$input"
}

# ============================================================================
# MAIN
# ============================================================================

# 1. Validar inputs
validate_inputs

# 2. Verificar que la base de datos existe
if [ ! -f "$MEMORIES_DB" ]; then
    log_error "Base de datos no encontrada: $MEMORIES_DB"
    log_error "Ejecuta primero: cmx init"
    exit 1
fi

# 3. Generar task_id si no se proporciona
if [ -z "$TASK_ID" ]; then
    TASK_ID="task-$(date +%s)-$$"
fi

# 4. Escapar contenido con función segura
ESCAPED_TITLE=$(sql_escape "$TITLE")
ESCAPED_CONTENT=$(sql_escape "$CONTENT")
ESCAPED_PROJECT=$(sql_escape "$PROJECT")
ESCAPED_AGENT=$(sql_escape "$AGENT")
ESCAPED_TASK_ID=$(sql_escape "$TASK_ID")
ESCAPED_PHASE=$(sql_escape "$PHASE")

# 5. Validar que el SQL resultante no contenga patrones peligrosos
#    (doble verificación de seguridad)
validate_sql_safety() {
    local escaped="$1"
    local field_name="$2"

    # Verificar que no haya secuencias de comentario SQL residuales
    if echo "$escaped" | grep -qiE "(--|/\*|\*/)" 2>/dev/null; then
        log_warn "Patrones de comentario SQL detectados en $field_name — sanitizando"
        escaped="${escaped//--/\\-\\-}"
        escaped="${escaped//\*\*/\\*\\*}"
    fi

    echo "$escaped"
}

ESCAPED_TITLE=$(validate_sql_safety "$ESCAPED_TITLE" "title")
ESCAPED_CONTENT=$(validate_sql_safety "$ESCAPED_CONTENT" "content")

# 6. Insertar en la base de datos con transacción
RESULT=$(sqlite3 "$MEMORIES_DB" "
BEGIN TRANSACTION;
INSERT INTO memories (type, title, content, project, agent, task_id, phase, created_at, updated_at)
VALUES (
    '$(sql_escape "$TYPE")',
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
COMMIT;
" 2>&1) || {
    log_error "Error al guardar la memoria: $RESULT"
    exit 1
}

# Verificar que el resultado es un número (ID válido)
if ! [[ "$RESULT" =~ ^[0-9]+$ ]]; then
    log_error "Resultado inesperado de la base de datos: $RESULT"
    exit 1
fi

# 7. Output exitoso
TIMESTAMP=$(date -Iseconds)
log_ok "Memoria guardada: ID=$RESULT, type=$TYPE, project=$PROJECT"

# Output JSON para consumo programático
cat << EOF
{
  "status": "saved",
  "id": $RESULT,
  "type": "$TYPE",
  "title": "$ESCAPED_TITLE",
  "project": "$ESCAPED_PROJECT",
  "agent": "$ESCAPED_AGENT",
  "task_id": "$ESCAPED_TASK_ID",
  "phase": "$ESCAPED_PHASE",
  "timestamp": "$TIMESTAMP"
}
EOF
