#!/bin/bash
# Cognitive Stack v2 — Agent: Implementer
# Implementa un batch de tareas usando OpenCode CLI
# Input: artifacts/tasks/{CHANGE}.json
# Output: artifacts/implementation/{CHANGE}_batch_{BATCH}.json

set -e

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CHANGE="${1}"
BATCH="${2:-1}"

# ============================================================
# VALIDACIONES
# ============================================================

if [ -z "$CHANGE" ]; then
    echo "ERROR: Uso: implementer.sh <change-name> <batch-number>"
    exit 1
fi

STATE_FILE="$WORKSPACE/orchestrator/agent_state.json"
LOG_DIR="$WORKSPACE/orchestrator/logs/active"
TASKS_FILE="$WORKSPACE/artifacts/tasks/${CHANGE}.json"
IMPL_DIR="$WORKSPACE/artifacts/implementation"
PROGRESS_FILE="$WORKSPACE/artifacts/progress/${CHANGE}.json"
OUTPUT_FILE="$IMPL_DIR/${CHANGE}_batch_${BATCH}.json"
TIMESTAMP=$(date -Iseconds)

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[IMPL:BATCH-${BATCH}]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# ============================================================
# FUNCIONES DE ESTADO
# ============================================================

update_state() {
    local agent="$1"
    local field="$2"
    local value="$3"
    
    if [ "$value" == "null" ] || [ "$value" == "true" ] || [ "$value" == "false" ]; then
        jq ".agents.$agent.$field = $value" "$STATE_FILE" > "${STATE_FILE}.tmp" && \
            mv "${STATE_FILE}.tmp" "$STATE_FILE"
    elif [[ "$value" =~ ^[0-9]+$ ]]; then
        jq ".agents.$agent.$field = $value" "$STATE_FILE" > "${STATE_FILE}.tmp" && \
            mv "${STATE_FILE}.tmp" "$STATE_FILE"
    else
        jq ".agents.$agent.$field = \"$value\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && \
            mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
}

mark_started() {
    local pid="$1"
    update_state "implementer" "status" "running"
    update_state "implementer" "pid" "$pid"
    update_state "implementer" "started_at" "$TIMESTAMP"
    update_state "implementer" "log_file" "$LOG_FILE"
}

mark_completed() {
    local confidence="$1"
    update_state "implementer" "status" "completed"
    update_state "implementer" "pid" "null"
    update_state "implementer" "completed_at" "$(date -Iseconds)"
    update_state "implementer" "confidence_score" "$confidence"
    
    if [ "$confidence" -lt 7 ]; then
        update_state "implementer" "requires_hitl" "true"
    fi
}

mark_failed() {
    local error_msg="${1:-Unknown error}"
    update_state "implementer" "status" "failed"
    update_state "implementer" "pid" "null"
    update_state "implementer" "completed_at" "$(date -Iseconds)"
    update_state "implementer" "error" "$error_msg"
}

# ============================================================
# PREPARAR LOG FILE
# ============================================================

LOG_FILE="${LOG_DIR}/impl_${CHANGE}_batch${BATCH}_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"
mkdir -p "$IMPL_DIR"
echo $$ > "${LOG_DIR}/implementer.pid"

log "=========================================="
log "Iniciando Implementer para: $CHANGE"
log "Batch: $BATCH"
log "Tasks: $TASKS_FILE"
log "Output: $OUTPUT_FILE"
log "=========================================="

# ============================================================
# VERIFICAR INPUT
# ============================================================

if [ ! -f "$TASKS_FILE" ]; then
    log_error "Tasks file no encontrado: $TASKS_FILE"
    mark_failed "Tasks file not found"
    exit 1
fi

# Extraer información del batch
log "Extrayendo información del batch $BATCH..."

BATCH_TASKS=$(jq -r ".batch_recommendations[] | select(.batch == $BATCH) | .tasks[]" "$TASKS_FILE" 2>/dev/null)
BATCH_DESC=$(jq -r ".batch_recommendations[] | select(.batch == $BATCH) | .description" "$TASKS_FILE" 2>/dev/null)

if [ -z "$BATCH_TASKS" ]; then
    log_error "No se encontró el batch $BATCH en $TASKS_FILE"
    mark_failed "Batch not found"
    exit 1
fi

log "Batch description: $BATCH_DESC"
log "Tasks a ejecutar:"
echo "$BATCH_TASKS" | while read task; do
    [ -n "$task" ] && echo "  - $task"
done

# ============================================================
# CONSTRUIR PROMPT DETALLADO PARA OPENCOD
# ============================================================

TEMP_PROMPT=$(mktemp)

# Header del prompt
cat > "$TEMP_PROMPT" << 'PROMPT_EOF'
# SDD Agent: Implementer
# Task: Implementar código real basado en las tareas asignadas

## Instrucciones
Eres un ingeniero de software senior. Tu objetivo es ESCRIBIR CÓDIGO REAL en el disco.
Debes crear o modificar los archivos especificados en las tareas del batch actual.

## IMPORTANTE
- USA HERRAMIENTAS DE ESCRITURA para crear archivos
- NO solo describas el código, ESCRÍBELO
- Crea la estructura de directorios necesaria
- Escribe código funcional y completo
- Al finalizar, responde con un JSON puro con el resumen

## Workspace
PROMPT_EOF

echo "$WORKSPACE" >> "$TEMP_PROMPT"

cat >> "$TEMP_PROMPT" << 'PROMPT_EOF'

## Tareas del Batch Actual
PROMPT_EOF

# Agregar detalles de cada tarea
for TASK_ID in $BATCH_TASKS; do
    echo "" >> "$TEMP_PROMPT"
    echo "### $TASK_ID" >> "$TEMP_PROMPT"
    
    # Buscar la tarea en el archivo de tasks
    TASK_TITLE=$(jq -r ".phases[].tasks[] | select(.id == \"$TASK_ID\") | .title" "$TASKS_FILE" 2>/dev/null)
    TASK_DESC=$(jq -r ".phases[].tasks[] | select(.id == \"$TASK_ID\") | .description" "$TASKS_FILE" 2>/dev/null)
    TASK_TYPE=$(jq -r ".phases[].tasks[] | select(.id == \"$TASK_ID\") | .type" "$TASKS_FILE" 2>/dev/null)
    TASK_FILES_CREATE=$(jq -r ".phases[].tasks[] | select(.id == \"$TASK_ID\") | .files_to_create[]?" "$TASKS_FILE" 2>/dev/null | tr '\n' ', ')
    TASK_FILES_MODIFY=$(jq -r ".phases[].tasks[] | select(.id == \"$TASK_ID\") | .files_to_modify[]?" "$TASKS_FILE" 2>/dev/null | tr '\n' ', ')
    
    echo "Título: $TASK_TITLE" >> "$TEMP_PROMPT"
    echo "Descripción: $TASK_DESC" >> "$TEMP_PROMPT"
    echo "Tipo: $TASK_TYPE" >> "$TEMP_PROMPT"
    echo "Archivos a crear: ${TASK_FILES_CREATE:-ninguno}" >> "$TEMP_PROMPT"
    echo "Archivos a modificar: ${TASK_FILES_MODIFY:-ninguno}" >> "$TEMP_PROMPT"
done

# Agregar instrucciones de output
cat >> "$TEMP_PROMPT" << 'PROMPT_EOF'

## Formato de Output OBLIGATORIO
Al terminar de implementar TODAS las tareas del batch, responde ÚNICAMENTE con este JSON:

{
  "batch_executed": NUMERO_DEL_BATCH,
  "tasks_completed": ["TASK-001", "TASK-002", ...],
  "files_created_or_modified": ["ruta/archivo1.ts", "ruta/archivo2.tsx", ...],
  "issues_found": "descripción de problemas encontrados o null si no hay",
  "confidence_score": NUMERO_DEL_1_AL_10
}

## Constraints
- Solo JSON válido en la respuesta final, sin markdown fences
- files_created_or_modified debe listar TODOS los archivos modificados/creados
- Si encontraste problemas, descríbelos en issues_found
- confidence_score: qué tan seguro estás de que el código funciona (1-10)
PROMPT_EOF

# ============================================================
# LANZAR OPENCOD EN BACKGROUND
# ============================================================

log "Lanzando OpenCode para implementar batch $BATCH..."
log "Timeout extendido: SIGINT @ 8min | SIGKILL @ 10min"

TEMP_OUTPUT=$(mktemp)

nohup opencode run "$(cat "$TEMP_PROMPT")" > "$TEMP_OUTPUT" 2>&1 &

OPENCOD_PID=$!
log "OpenCode PID: $OPENCOD_PID"
echo $OPENCOD_PID > "${LOG_DIR}/implementer_opencode.pid"
mark_started "$OPENCOD_PID"
rm -f "$TEMP_PROMPT"

# ============================================================
# TIMEOUT DUAL EXTENDIDO: SIGINT (8min) -> SIGKILL (10min)
# ============================================================

TIMEOUT_SOFT=480  # 8 minutos
TIMEOUT_HARD=600  # 10 minutos

log "Timeout soft: ${TIMEOUT_SOFT}s | Timeout hard: ${TIMEOUT_HARD}s"

ELAPSED=0
while kill -0 $OPENCOD_PID 2>/dev/null; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    
    # Timeout soft a los 8 minutos
    if [ $ELAPSED -eq $TIMEOUT_SOFT ]; then
        log "⏰ Timeout soft (8min) - enviando SIGINT"
        kill -INT $OPENCOD_PID 2>/dev/null
        sleep 5
    fi
    
    # Timeout hard a los 10 minutos
    if [ $ELAPSED -ge $TIMEOUT_HARD ]; then
        log_error "⏰ Timeout hard (10min) - forzando SIGKILL"
        kill -9 $OPENCOD_PID 2>/dev/null
        break
    fi
    
    # Log cada 30 segundos
    if [ $((ELAPSED % 30)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        log "Ejecutando... ${ELAPSED}s / ${TIMEOUT_HARD}s"
    fi
done

wait $OPENCOD_PID 2>/dev/null || true
rm -f "${LOG_DIR}/implementer_opencode.pid"

# ============================================================
# PROCESAR RESULTADO
# ============================================================

log "Procesando resultado..."

if [ ! -f "$TEMP_OUTPUT" ] || [ ! -s "$TEMP_OUTPUT" ]; then
    log_error "OpenCode no generó output"
    mark_failed "No output from OpenCode"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

# Extraer JSON con Python
JSON_OUTPUT=$(python3 -c "
import sys
import json
import re

content = sys.stdin.read()

# Buscar objeto JSON en el contenido
start = content.find('{')
end = content.rfind('}')

if start == -1 or end == -1 or start >= end:
    print('')
    sys.exit(1)

json_str = content[start:end+1]

# Intentar arreglar JSON incompleto
try:
    obj = json.loads(json_str)
    print(json.dumps(obj))
except json.JSONDecodeError as e:
    # Intentar completar el JSON
    # Agregar campos faltantes si es necesario
    lines = json_str.split('\n')
    fixed_lines = []
    for line in lines:
        line = line.rstrip()
        if not line.endswith(',') and not line.endswith('{') and not line.endswith('['):
            line = line.rstrip(',')
        fixed_lines.append(line)
    
    json_str = '\n'.join(fixed_lines)
    
    # Completar objetos abiertos
    open_braces = json_str.count('{') - json_str.count('}')
    open_brackets = json_str.count('[') - json_str.count(']')
    
    for _ in range(max(open_braces, 0)):
        json_str += '\n}'
    for _ in range(max(open_brackets, 0)):
        json_str += '\n]'
    
    try:
        obj = json.loads(json_str)
        print(json.dumps(obj))
    except:
        # Último intento: buscar el JSON parcial y marcar issues
        print('{\"batch_executed\": ' + str($BATCH) + ', \"tasks_completed\": [], \"files_created_or_modified\": [], \"issues_found\": \"JSON output truncated\", \"confidence_score\": 3}')
" 2>/dev/null < "$TEMP_OUTPUT")

if [ -z "$JSON_OUTPUT" ]; then
    log_error "No se pudo extraer JSON válido"
    head -c 2000 "$TEMP_OUTPUT"
    mark_failed "Invalid JSON output"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

# Extraer datos del resultado
BATCH_EXECUTED=$(echo "$JSON_OUTPUT" | jq -r '.batch_executed // 1')
TASKS_COMPLETED=$(echo "$JSON_OUTPUT" | jq -r '.tasks_completed // []')
FILES_MODIFIED=$(echo "$JSON_OUTPUT" | jq -r '.files_created_or_modified // []')
ISSUES=$(echo "$JSON_OUTPUT" | jq -r '.issues_found // null')
CONFIDENCE=$(echo "$JSON_OUTPUT" | jq -r '.confidence_score // 5')

log "Batch executed: $BATCH_EXECUTED"
log "Tasks completed: $TASKS_COMPLETED"
log "Files modified: $FILES_MODIFIED"
log "Confidence: $CONFIDENCE"

if [ "$ISSUES" != "null" ] && [ -n "$ISSUES" ]; then
    log_warn "Issues encontrados: $ISSUES"
fi

# Guardar resultado del batch
echo "$JSON_OUTPUT" | jq '.' > "$OUTPUT_FILE"

# Actualizar progress
PROGRESS_DATA=$(cat << EOF
{
  "change": "$CHANGE",
  "current_batch": $BATCH,
  "batch_results": {
    "$BATCH": $JSON_OUTPUT
  },
  "timestamp": "$TIMESTAMP"
}
EOF
)

echo "$PROGRESS_DATA" | jq '.' > "$PROGRESS_FILE"

# ============================================================
# FINALIZAR
# ============================================================

mark_completed "$CONFIDENCE"

log_ok "=========================================="
log_ok "Batch $BATCH completado"
log_ok "Output: $OUTPUT_FILE"
log_ok "Confidence: $CONFIDENCE/10"
log_ok "=========================================="

if [ "$CONFIDENCE" -lt 7 ]; then
    log_warn "⚠️  HITL recomendado - revisar implementación"
fi

if [ "$ISSUES" != "null" ] && [ -n "$ISSUES" ]; then
    log_warn "⚠️  Issues encontrados - revisar antes de continuar"
fi

if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_DIR}/../history/"
fi

rm -f "$TEMP_OUTPUT"
exit 0
