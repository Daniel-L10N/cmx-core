#!/bin/bash
# Cognitive Stack v2 — Agent: Spec Writer
# Genera especificación técnica formal usando OpenCode CLI
# Input: artifacts/proposals/{CHANGE}.json
# Output: artifacts/specs/{CHANGE}.json

set -e

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CHANGE="${1}"
BATCH="${2:-1}"

# ============================================================
# VALIDACIONES
# ============================================================

if [ -z "$CHANGE" ]; then
    echo "ERROR: Uso: spec-writer.sh <change-name> [batch]"
    exit 1
fi

STATE_FILE="$WORKSPACE/orchestrator/agent_state.json"
LOG_DIR="$WORKSPACE/orchestrator/logs/active"
PROPOSAL_FILE="$WORKSPACE/artifacts/proposals/${CHANGE}.json"
SPEC_FILE="$WORKSPACE/artifacts/specs/${CHANGE}.json"
CONTRACT_FILE="$WORKSPACE/artifacts/specs/${CHANGE}.contract.json"
TIMESTAMP=$(date -Iseconds)

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[SPEC]${NC} $1"; }
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
    update_state "spec" "status" "running"
    update_state "spec" "pid" "$pid"
    update_state "spec" "started_at" "$TIMESTAMP"
    update_state "spec" "log_file" "$LOG_FILE"
}

mark_completed() {
    local confidence="$1"
    update_state "spec" "status" "completed"
    update_state "spec" "pid" "null"
    update_state "spec" "completed_at" "$(date -Iseconds)"
    update_state "spec" "confidence_score" "$confidence"
    update_state "spec" "output_file" "$SPEC_FILE"
    
    if [ "$confidence" -lt 7 ]; then
        update_state "spec" "requires_hitl" "true"
    fi
}

mark_failed() {
    local error_msg="${1:-Unknown error}"
    update_state "spec" "status" "failed"
    update_state "spec" "pid" "null"
    update_state "spec" "completed_at" "$(date -Iseconds)"
    update_state "spec" "error" "$error_msg"
}

# ============================================================
# PREPARAR LOG FILE
# ============================================================

LOG_FILE="${LOG_DIR}/spec_${CHANGE}_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"
echo $$ > "${LOG_DIR}/spec.pid"

log "Iniciando Spec Writer para: $CHANGE"
log "Proposal: $PROPOSAL_FILE"
log "Output: $SPEC_FILE"

# ============================================================
# VERIFICAR INPUT
# ============================================================

if [ ! -f "$PROPOSAL_FILE" ]; then
    log_error "Propuesta no encontrada: $PROPOSAL_FILE"
    mark_failed "Proposal file not found"
    exit 1
fi

PROPOSAL_CONTENT=$(cat "$PROPOSAL_FILE")

# ============================================================
# CONSTRUIR PROMPT PARA OPENCOD
# ============================================================

TEMP_PROMPT=$(mktemp)

cat > "$TEMP_PROMPT" << 'PROMPT_EOF'
# SDD Agent: Spec Writer
# Task: Generar especificación técnica formal

## Instrucciones
Eres un agente SDD especializado en crear especificaciones técnicas detalladas.
Debes analizar la propuesta proporcionada y generar una especificación completa con:
- Endpoints API exactos con method, path, request/response schemas
- Esquemas de base de datos (tablas, campos, relaciones)
- Interfaces TypeScript
- Casos de prueba esenciales
- Criterios de aceptación medibles

## Propuesta a especificar:
PROMPT_EOF

echo "$PROPOSAL_CONTENT" >> "$TEMP_PROMPT"

cat >> "$TEMP_PROMPT" << 'PROMPT_EOF'

## Formato de Output OBLIGATORIO
Responde UNICAMENTE con JSON válido (sin markdown fences):
{
  "title": "título de la especificación",
  "version": "1.0.0",
  "overview": "resumen del sistema a implementar",
  "api_endpoints": [
    {
      "method": "GET|POST|PUT|DELETE",
      "path": "/api/route",
      "description": "descripción del endpoint",
      "request": {
        "headers": {},
        "body": {},
        "query": {}
      },
      "response": {
        "status": 200,
        "body": {},
        "errors": [400, 401, 500]
      }
    }
  ],
  "database_schemas": [
    {
      "table": "nombre_tabla",
      "description": "propósito de la tabla",
      "fields": [
        {"name": "campo", "type": "varchar", "constraints": "PK|FK|NOT NULL|DEFAULT", "references": "table.column"}
      ],
      "indexes": ["campo1", "campo2"]
    }
  ],
  "typescript_interfaces": [
    {
      "name": "InterfaceName",
      "properties": [
        {"name": "field", "type": "string", "required": true, "description": "descripción"}
      ]
    }
  ],
  "test_cases": [
    {
      "id": "TC-001",
      "description": "descripción del caso de prueba",
      "steps": ["paso1", "paso2"],
      "expected": "resultado esperado",
      "priority": "high|medium|low"
    }
  ],
  "acceptance_criteria": [
    {"criterion": "criterio medible 1", "testable": true},
    {"criterion": "criterio medible 2", "testable": true}
  ],
  "confidence_score": numero_del_1_al_10
}

## Constraints
- Solo JSON válido, sin texto adicional
- confidence_score DEBE ser un número del 1 al 10
- Todos los endpoints deben tener method, path, request y response
- acceptance_criteria deben ser medibles y testables
PROMPT_EOF

# ============================================================
# LANZAR OPENCOD EN BACKGROUND
# ============================================================

log "Lanzando OpenCode..."

TEMP_OUTPUT=$(mktemp)

nohup opencode run "$(cat "$TEMP_PROMPT")" > "$TEMP_OUTPUT" 2>&1 &

OPENCOD_PID=$!
log "OpenCode PID: $OPENCOD_PID"
echo $OPENCOD_PID > "${LOG_DIR}/spec_opencode.pid"
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
rm -f "${LOG_DIR}/spec_opencode.pid"

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

# Guardar spec
echo "$JSON_OUTPUT" | jq '.' > "$SPEC_FILE"

# Generar contract
cat > "$CONTRACT_FILE" << EOF
{
  "type": "spec_contract",
  "version": "2.0.0",
  "change": "$CHANGE",
  "agent": "spec",
  "timestamp": "$TIMESTAMP",
  "status": "completed",
  "output_file": "$SPEC_FILE",
  "confidence_score": $CONFIDENCE,
  "requires_hitl": $([ "$CONFIDENCE" -lt 7 ] && echo "true" || echo "false")
}
EOF

# ============================================================
# FINALIZAR
# ============================================================

mark_completed "$CONFIDENCE"

log_ok "Especificación generada: $SPEC_FILE"
log_ok "Confidence: $CONFIDENCE/10"

if [ "$CONFIDENCE" -lt 7 ]; then
    log "⚠️  HITL requerido - revisar spec antes de continuar"
fi

if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_DIR}/../history/"
fi

rm -f "$TEMP_OUTPUT"
exit 0
