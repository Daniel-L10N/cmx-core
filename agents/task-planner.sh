#!/bin/bash
# Cognitive Stack v2 — Agent: Task Planner
# Genera plan de tareas accionables usando OpenCode CLI
# Input: artifacts/specs/{CHANGE}.json + artifacts/designs/{CHANGE}.json
# Output: artifacts/tasks/{CHANGE}.json

set -e

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CHANGE="${1}"
BATCH="${2:-1}"

# ============================================================
# VALIDACIONES
# ============================================================

if [ -z "$CHANGE" ]; then
    echo "ERROR: Uso: task-planner.sh <change-name> [batch]"
    exit 1
fi

STATE_FILE="$WORKSPACE/orchestrator/agent_state.json"
LOG_DIR="$WORKSPACE/orchestrator/logs/active"
SPEC_FILE="$WORKSPACE/artifacts/specs/${CHANGE}.json"
DESIGN_FILE="$WORKSPACE/artifacts/designs/${CHANGE}.json"
TASKS_FILE="$WORKSPACE/artifacts/tasks/${CHANGE}.json"
CONTRACT_FILE="$WORKSPACE/artifacts/tasks/${CHANGE}.contract.json"
TIMESTAMP=$(date -Iseconds)

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[TASKS]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

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
    update_state "tasks" "status" "running"
    update_state "tasks" "pid" "$pid"
    update_state "tasks" "started_at" "$TIMESTAMP"
    update_state "tasks" "log_file" "$LOG_FILE"
}

mark_completed() {
    local confidence="$1"
    update_state "tasks" "status" "completed"
    update_state "tasks" "pid" "null"
    update_state "tasks" "completed_at" "$(date -Iseconds)"
    update_state "tasks" "confidence_score" "$confidence"
    update_state "tasks" "output_file" "$TASKS_FILE"
    
    if [ "$confidence" -lt 7 ]; then
        update_state "tasks" "requires_hitl" "true"
    fi
}

mark_failed() {
    local error_msg="${1:-Unknown error}"
    update_state "tasks" "status" "failed"
    update_state "tasks" "pid" "null"
    update_state "tasks" "completed_at" "$(date -Iseconds)"
    update_state "tasks" "error" "$error_msg"
}

# ============================================================
# PREPARAR LOG FILE
# ============================================================

LOG_FILE="${LOG_DIR}/tasks_${CHANGE}_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"
echo $$ > "${LOG_DIR}/tasks.pid"

log "Iniciando Task Planner para: $CHANGE"
log "Spec: $SPEC_FILE"
log "Design: $DESIGN_FILE"
log "Output: $TASKS_FILE"

# ============================================================
# VERIFICAR INPUTS
# ============================================================

if [ ! -f "$SPEC_FILE" ]; then
    log_error "Especificación no encontrada: $SPEC_FILE"
    mark_failed "Spec file not found"
    exit 1
fi

if [ ! -f "$DESIGN_FILE" ]; then
    log_error "Diseño no encontrado: $DESIGN_FILE"
    mark_failed "Design file not found"
    exit 1
fi

SPEC_CONTENT=$(cat "$SPEC_FILE")
DESIGN_CONTENT=$(cat "$DESIGN_FILE")

# ============================================================
# CONSTRUIR PROMPT PARA OPENCOD
# ============================================================

TEMP_PROMPT=$(mktemp)

cat > "$TEMP_PROMPT" << 'PROMPT_EOF'
# SDD Agent: Task Planner
# Task: Generar plan de micro-tareas accionables

## Instrucciones
Eres un agente SDD especializado en planificar implementaciones.
Debes analizar la especificación técnica y el diseño UI/UX y generar:
- Array de micro-tareas ordenadas topológicamente (dependencias)
- Cada tarea debe ser accionable por un implementador
- Estimación de tiempo realista
- Criterios de verificación claros

## Especificación Técnica:
PROMPT_EOF

echo "$SPEC_CONTENT" >> "$TEMP_PROMPT"

cat >> "$TEMP_PROMPT" << 'PROMPT_EOF'

## Diseño UI/UX:
PROMPT_EOF

echo "$DESIGN_CONTENT" >> "$TEMP_PROMPT"

cat >> "$TEMP_PROMPT" << 'PROMPT_EOF'

## Formato de Output OBLIGATORIO
Responde UNICAMENTE con JSON válido (sin markdown fences):
{
  "title": "plan de implementación",
  "version": "1.0.0",
  "total_estimated_hours": numero,
  "phases": [
    {
      "name": "nombre de fase",
      "description": "descripción de la fase",
      "order": 1,
      "tasks": [
        {
          "id": "TASK-001",
          "title": "título de la tarea",
          "description": "descripción detallada de qué hacer",
          "type": "backend|frontend|config|test|docs",
          "priority": "high|medium|low",
          "estimated_minutes": numero,
          "dependencies": ["TASK-000"],
          "files_to_create": ["src/file.tsx"],
          "files_to_modify": ["src/existing.tsx"],
          "verification": {
            "test_command": "npm test -- test.spec.ts",
            "manual_check": "verificar que el componente renderiza correctamente",
            "acceptance_criteria": ["criterio 1", "criterio 2"]
          }
        }
      ]
    }
  ],
  "batch_recommendations": [
    {"batch": 1, "tasks": ["TASK-001", "TASK-002"], "description": "setup inicial"},
    {"batch": 2, "tasks": ["TASK-003", "TASK-004"], "description": "funcionalidad core"},
    {"batch": 3, "tasks": ["TASK-005"], "description": "tests y polish"}
  ],
  "confidence_score": numero_del_1_al_10
}

## Constraints
- Solo JSON válido, sin texto adicional
- confidence_score DEBE ser un número del 1 al 10
- Cada tarea debe tener verification.test_command o verification.manual_check
- dependencies debe listar IDs de tareas que deben completarse primero
- BATCH REQUERIDO: Definir cómo dividir en batches para HITL
PROMPT_EOF

# ============================================================
# LANZAR OPENCOD EN BACKGROUND
# ============================================================

log "Lanzando OpenCode..."

TEMP_OUTPUT=$(mktemp)

nohup opencode run "$(cat "$TEMP_PROMPT")" > "$TEMP_OUTPUT" 2>&1 &

OPENCOD_PID=$!
log "OpenCode PID: $OPENCOD_PID"
echo $OPENCOD_PID > "${LOG_DIR}/tasks_opencode.pid"
mark_started "$OPENCOD_PID"
rm -f "$TEMP_PROMPT"

# ============================================================
# TIMEOUT DUAL: SIGINT (4min) -> SIGKILL (5min)
# ============================================================

TIMEOUT_SOFT=240
TIMEOUT_HARD=300

log "Timeout soft: ${TIMEOUT_SOFT}s | Timeout hard: ${TIMEOUT_HARD}s"

ELAPSED=0
while kill -0 $OPENCOD_PID 2>/dev/null; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    
    if [ $ELAPSED -eq $TIMEOUT_SOFT ]; then
        log "⏰ Timeout soft - enviando SIGINT"
        kill -INT $OPENCOD_PID 2>/dev/null
        sleep 2
    fi
    
    if [ $ELAPSED -ge $TIMEOUT_HARD ]; then
        log_error "⏰ Timeout hard - forzando SIGKILL"
        kill -9 $OPENCOD_PID 2>/dev/null
        break
    fi
done

wait $OPENCOD_PID 2>/dev/null || true
rm -f "${LOG_DIR}/tasks_opencode.pid"

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

content = sys.stdin.read()
start = content.find('{')
end = content.rfind('}')

if start == -1 or end == -1 or start >= end:
    print('')
    sys.exit(1)

json_str = content[start:end+1]
obj = json.loads(json_str)
print(json.dumps(obj))
" 2>/dev/null)

if [ -z "$JSON_OUTPUT" ]; then
    log_error "No se pudo extraer JSON válido"
    head -c 1500 "$TEMP_OUTPUT"
    mark_failed "Invalid JSON output"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

CONFIDENCE=$(echo "$JSON_OUTPUT" | jq -r '.confidence_score // 7')
log "Confidence score: $CONFIDENCE"

# Guardar tasks
echo "$JSON_OUTPUT" | jq '.' > "$TASKS_FILE"

# Generar contract
cat > "$CONTRACT_FILE" << EOF
{
  "type": "tasks_contract",
  "version": "2.0.0",
  "change": "$CHANGE",
  "agent": "tasks",
  "timestamp": "$TIMESTAMP",
  "status": "completed",
  "output_file": "$TASKS_FILE",
  "confidence_score": $CONFIDENCE,
  "requires_hitl": $([ "$CONFIDENCE" -lt 7 ] && echo "true" || echo "false"),
  "batch_count": $(echo "$JSON_OUTPUT" | jq -r '.batch_recommendations | length // 1')
}
EOF

# ============================================================
# FINALIZAR
# ============================================================

mark_completed "$CONFIDENCE"

log_ok "Plan de tareas generado: $TASKS_FILE"
log_ok "Confidence: $CONFIDENCE/10"

# Mostrar batch recommendations
BATCH_COUNT=$(echo "$JSON_OUTPUT" | jq -r '.batch_recommendations | length // 1')
log "Batches recomendados: $BATCH_COUNT"

if [ "$CONFIDENCE" -lt 7 ]; then
    log "⚠️  HITL requerido - revisar plan antes de continuar"
fi

if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_DIR}/../history/"
fi

rm -f "$TEMP_OUTPUT"
exit 0
