#!/bin/bash
# Cognitive Stack v2 — Agent: Proposer
# Genera propuesta formal usando OpenCode CLI
# Input: artifacts/exploration/{CHANGE}.json
# Output: artifacts/proposals/{CHANGE}.json

set -e

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CHANGE="${1}"
BATCH="${2:-1}"

# ============================================================
# VALIDACIONES
# ============================================================

if [ -z "$CHANGE" ]; then
    echo "ERROR: Uso: proposer.sh <change-name> [batch]"
    exit 1
fi

STATE_FILE="$WORKSPACE/orchestrator/agent_state.json"
LOG_DIR="$WORKSPACE/orchestrator/logs/active"
EXPLORATION_FILE="$WORKSPACE/artifacts/exploration/${CHANGE}.json"
PROPOSAL_FILE="$WORKSPACE/artifacts/proposals/${CHANGE}.json"
CONTRACT_FILE="$WORKSPACE/artifacts/proposals/${CHANGE}.contract.json"
TIMESTAMP=$(date -Iseconds)

# Colores para logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[PROPOSER]${NC} $1"; }
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
    update_state "proposer" "status" "running"
    update_state "proposer" "pid" "$pid"
    update_state "proposer" "started_at" "$TIMESTAMP"
    update_state "proposer" "log_file" "$LOG_FILE"
}

mark_completed() {
    local confidence="$1"
    update_state "proposer" "status" "completed"
    update_state "proposer" "pid" "null"
    update_state "proposer" "completed_at" "$(date -Iseconds)"
    update_state "proposer" "confidence_score" "$confidence"
    update_state "proposer" "output_file" "$PROPOSAL_FILE"
    
    # Si confidence < 7, marcar HITL requerido
    if [ "$confidence" -lt 7 ]; then
        update_state "proposer" "requires_hitl" "true"
    fi
}

mark_failed() {
    local error_msg="${1:-Unknown error}"
    update_state "proposer" "status" "failed"
    update_state "proposer" "pid" "null"
    update_state "proposer" "completed_at" "$(date -Iseconds)"
    update_state "proposer" "error" "$error_msg"
}

# ============================================================
# PREPARAR LOG FILE
# ============================================================

LOG_FILE="${LOG_DIR}/proposer_${CHANGE}_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"

# Guardar PID del proceso padre
echo $$ > "${LOG_DIR}/proposer.pid"

log "Iniciando Proposer para: $CHANGE"
log "Exploration: $EXPLORATION_FILE"
log "Output: $PROPOSAL_FILE"
log "Log: $LOG_FILE"

# ============================================================
# VERIFICAR INPUT
# ============================================================

if [ ! -f "$EXPLORATION_FILE" ]; then
    log_error "Archivo de exploración no encontrado: $EXPLORATION_FILE"
    mark_failed "Exploration file not found"
    exit 1
fi

EXPLORATION_CONTENT=$(cat "$EXPLORATION_FILE")

# ============================================================
# CONSTRUIR PROMPT PARA OPENCOD
# ============================================================

PROMPT=$(cat << 'EOF'
# SDD Agent: Proposer
# Task: Generar propuesta formal de cambio

## Instrucciones
Eres un agente SDD especializado en crear propuestas técnicas formales.
Debes analizar el contexto de exploración proporcionado y generar una propuesta estructurada.

## Formato de Output OBLIGATORIO
Responde UNICAMENTE con JSON válido (sin markdown fences, sin explicaciones):
{
  "name": "nombre-del-cambio",
  "summary": "resumen ejecutivo en una línea",
  "approach": "descripción detallada del enfoque técnico (mínimo 100 palabras)",
  "scope": {
    "in_scope": ["item1", "item2", "item3"],
    "out_of_scope": ["item1", "item2"]
  },
  "risks": [
    {
      "description": "descripción del riesgo",
      "severity": "low|medium|high|critical",
      "mitigation": "cómo mitigar este riesgo"
    }
  ],
  "rollback_plan": "procedimiento de rollback detallado",
  "estimated_effort": {
    "hours": numero,
    "phases": numero
  },
  "confidence_score": numero_del_1_al_10,
  "alternatives_considered": [
    {
      "name": "nombre alternativa",
      "reason_rejected": "razón por la que se descartó"
    }
  ]
}

## Constraints
- Solo JSON válido, sin texto adicional
- confidence_score DEBE ser un número del 1 al 10
- Si no estás seguro de algo, usa confidence_score bajo (5 o menos)
- approach debe ser detallado y técnico
EOF
)

# ============================================================
# LANZAR OPENCOD EN BACKGROUND CON TIMEOUT DUAL
# ============================================================

log "Lanzando OpenCode..."

# Archivo temporal para el output
TEMP_OUTPUT=$(mktemp)
TEMP_PROMPT=$(mktemp)

# Escribir el prompt a un archivo temporal
cat > "$TEMP_PROMPT" << 'PROMPT_EOF'
# SDD Agent: Proposer
# Task: Generar propuesta formal de cambio

## Instrucciones
Eres un agente SDD especializado en crear propuestas técnicas formales.
Debes analizar el contexto de exploración proporcionado y generar una propuesta estructurada.

## Contexto de Exploración:
PROMPT_EOF

# Agregar el contexto de exploración
echo "$EXPLORATION_CONTENT" >> "$TEMP_PROMPT"

# Agregar el resto del prompt
cat >> "$TEMP_PROMPT" << 'PROMPT_EOF'

## Formato de Output OBLIGATORIO
Responde UNICAMENTE con JSON válido (sin markdown fences, sin explicaciones):
{
  "name": "nombre-del-cambio",
  "summary": "resumen ejecutivo en una línea",
  "approach": "descripción detallada del enfoque técnico (mínimo 100 palabras)",
  "scope": {
    "in_scope": ["item1", "item2", "item3"],
    "out_of_scope": ["item1", "item2"]
  },
  "risks": [
    {
      "description": "descripción del riesgo",
      "severity": "low|medium|high|critical",
      "mitigation": "cómo mitigar este riesgo"
    }
  ],
  "rollback_plan": "procedimiento de rollback detallado",
  "estimated_effort": {
    "hours": numero,
    "phases": numero
  },
  "confidence_score": numero_del_1_al_10,
  "alternatives_considered": [
    {
      "name": "nombre alternativa",
      "reason_rejected": "razón por la que se descartó"
    }
  ]
}

## Constraints
- Solo JSON válido, sin texto adicional
- confidence_score DEBE ser un número del 1 al 10
- Si no estás seguro de algo, usa confidence_score bajo (5 o menos)
- approach debe ser detallado y técnico
PROMPT_EOF

# Comando OpenCode con run
nohup opencode run "$(cat "$TEMP_PROMPT")" > "$TEMP_OUTPUT" 2>&1 &

OPENCOD_PID=$!
log "OpenCode PID: $OPENCOD_PID"

# Guardar PID para monitor
echo $OPENCOD_PID > "${LOG_DIR}/proposer_opencode.pid"

# Marcar como running
mark_started "$OPENCOD_PID"

# Limpiar prompt temporal
rm -f "$TEMP_PROMPT"

# ============================================================
# TIMEOUT DUAL: SIGINT (4min) -> SIGKILL (5min)
# ============================================================

TIMEOUT_SOFT=240  # 4 minutos
TIMEOUT_HARD=300  # 5 minutos

log "Timeout soft: ${TIMEOUT_SOFT}s | Timeout hard: ${TIMEOUT_HARD}s"

# Esperar proceso
ELAPSED=0
while kill -0 $OPENCOD_PID 2>/dev/null; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    
    # Timeout soft a los 4 minutos
    if [ $ELAPSED -eq $TIMEOUT_SOFT ]; then
        log "⏰ Timeout soft alcanzado - enviando SIGINT"
        kill -INT $OPENCOD_PID 2>/dev/null
        sleep 2
    fi
    
    # Timeout hard a los 5 minutos
    if [ $ELAPSED -ge $TIMEOUT_HARD ]; then
        log_error "⏰ Timeout hard alcanzado - forzando SIGKILL"
        kill -9 $OPENCOD_PID 2>/dev/null
        break
    fi
done

wait $OPENCOD_PID 2>/dev/null || true

# Limpiar PID file
rm -f "${LOG_DIR}/proposer_opencode.pid"

# ============================================================
# PROCESAR RESULTADO
# ============================================================

log "Procesando resultado..."

if [ ! -f "$TEMP_OUTPUT" ] || [ ! -s "$TEMP_OUTPUT" ]; then
    log_error "OpenCode no generó output"
    cat "$LOG_FILE" | tail -20
    mark_failed "No output from OpenCode"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

# Extraer solo el JSON usando python (maneja multi-line mejor)
JSON_OUTPUT=$(python3 -c "
import sys
import json
import re

content = sys.stdin.read()

# Buscar objeto JSON en el contenido
# Primero buscar todo el bloque entre { y }
start = content.find('{')
end = content.rfind('}')

if start == -1 or end == -1 or start >= end:
    print('')
    sys.exit(1)

json_str = content[start:end+1]

# Intentar parsear y verificar
try:
    obj = json.loads(json_str)
    print(json.dumps(obj))
except json.JSONDecodeError as e:
    # Intentar arreglar JSON incompleto
    # Buscar donde falla y completar
    lines = json_str.split('\n')
    fixed = []
    for line in lines:
        line = line.rstrip()
        if not line.endswith(',') and not line.endswith('{') and not line.endswith('['):
            line = line.rstrip(',')
        fixed.append(line)
    
    # Forzar cierre de objetos
    json_str = '\n'.join(fixed)
    
    # Agregar cierres faltantes
    open_braces = json_str.count('{') - json_str.count('}')
    open_brackets = json_str.count('[') - json_str.count(']')
    
    for _ in range(open_braces):
        json_str += '\n}'
    for _ in range(open_brackets):
        json_str += '\n]'
    
    try:
        obj = json.loads(json_str)
        print(json.dumps(obj))
    except:
        print('')
" 2>/dev/null)

if [ -z "$JSON_OUTPUT" ]; then
    log_error "No se pudo extraer JSON válido"
    echo "--- Raw output (primeros 50 chars) ---"
    head -c 2000 "$TEMP_OUTPUT"
    echo ""
    mark_failed "Invalid JSON output"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

# Extraer solo el JSON (por si hay texto adicional)
# Buscar desde la primera { hasta la última }
JSON_OUTPUT=$(cat "$TEMP_OUTPUT" | sed -n '/{/,/}/p' | tr '\n' ' ')

if [ -z "$JSON_OUTPUT" ]; then
    log_error "No se pudo extraer JSON válido"
    echo "--- Raw output ---"
    cat "$TEMP_OUTPUT" | head -50
    mark_failed "Invalid JSON output"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

# Verificar que sea JSON válido
if ! echo "$JSON_OUTPUT" | jq empty 2>/dev/null; then
    log_error "JSON inválido - intentando修复..."
    # Intentar encontrar el bloque JSON completo
    FIRST_BRACE=$(echo "$JSON_OUTPUT" | grep -o '{' | wc -l)
    LAST_BRACE=$(echo "$JSON_OUTPUT" | grep -o '}' | wc -l)
    
    if [ "$FIRST_BRACE" -gt "$LAST_BRACE" ]; then
        log_warn "JSON incompleto: $FIRST_BRACE '{' vs $LAST_BRACE '}'"
    fi
fi

# Validar JSON
if ! echo "$JSON_OUTPUT" | jq empty 2>/dev/null; then
    log_error "JSON inválido"
    echo "$JSON_OUTPUT" | head -5
    mark_failed "Invalid JSON structure"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

# Extraer confidence_score (valor por defecto 7 si no existe)
CONFIDENCE=$(echo "$JSON_OUTPUT" | jq -r '.confidence_score // 7')
log "Confidence score: $CONFIDENCE"

# Guardar propuesta
echo "$JSON_OUTPUT" | jq '.' > "$PROPOSAL_FILE"

# Generar contract file
cat > "$CONTRACT_FILE" << EOF
{
  "type": "proposal_contract",
  "version": "2.0.0",
  "change": "$CHANGE",
  "agent": "proposer",
  "timestamp": "$TIMESTAMP",
  "status": "completed",
  "output_file": "$PROPOSAL_FILE",
  "confidence_score": $CONFIDENCE,
  "requires_hitl": $([ "$CONFIDENCE" -lt 7 ] && echo "true" || echo "false"),
  "log_file": "$LOG_FILE"
}
EOF

# ============================================================
# FINALIZAR
# ============================================================

mark_completed "$CONFIDENCE"

log_ok "Propuesta generada: $PROPOSAL_FILE"
log_ok "Confidence: $CONFIDENCE/10"

if [ "$CONFIDENCE" -lt 7 ]; then
    log "⚠️  HITL requerido - revisar propuesta antes de continuar"
fi

# Mover log a history
if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_DIR}/../history/"
fi

rm -f "$TEMP_OUTPUT"
exit 0
