#!/bin/bash
# Cognitive Stack v2 — Agent: Designer
# Genera diseño UI/UX formal usando OpenCode CLI
# Input: artifacts/proposals/{CHANGE}.json
# Output: artifacts/designs/{CHANGE}.json

set -e

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CHANGE="${1}"
BATCH="${2:-1}"

# ============================================================
# VALIDACIONES
# ============================================================

if [ -z "$CHANGE" ]; then
    echo "ERROR: Uso: designer.sh <change-name> [batch]"
    exit 1
fi

STATE_FILE="$WORKSPACE/orchestrator/agent_state.json"
LOG_DIR="$WORKSPACE/orchestrator/logs/active"
PROPOSAL_FILE="$WORKSPACE/artifacts/proposals/${CHANGE}.json"
DESIGN_FILE="$WORKSPACE/artifacts/designs/${CHANGE}.json"
CONTRACT_FILE="$WORKSPACE/artifacts/designs/${CHANGE}.contract.json"
TIMESTAMP=$(date -Iseconds)

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[DESIGN]${NC} $1"; }
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
    update_state "design" "status" "running"
    update_state "design" "pid" "$pid"
    update_state "design" "started_at" "$TIMESTAMP"
    update_state "design" "log_file" "$LOG_FILE"
}

mark_completed() {
    local confidence="$1"
    update_state "design" "status" "completed"
    update_state "design" "pid" "null"
    update_state "design" "completed_at" "$(date -Iseconds)"
    update_state "design" "confidence_score" "$confidence"
    update_state "design" "output_file" "$DESIGN_FILE"
    
    if [ "$confidence" -lt 7 ]; then
        update_state "design" "requires_hitl" "true"
    fi
}

mark_failed() {
    local error_msg="${1:-Unknown error}"
    update_state "design" "status" "failed"
    update_state "design" "pid" "null"
    update_state "design" "completed_at" "$(date -Iseconds)"
    update_state "design" "error" "$error_msg"
}

# ============================================================
# PREPARAR LOG FILE
# ============================================================

LOG_FILE="${LOG_DIR}/design_${CHANGE}_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"
echo $$ > "${LOG_DIR}/design.pid"

log "Iniciando Designer para: $CHANGE"
log "Proposal: $PROPOSAL_FILE"
log "Output: $DESIGN_FILE"

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
# SDD Agent: Designer
# Task: Generar diseño UI/UX formal

## Instrucciones
Eres un agente SDD especializado en crear diseños de interfaz de usuario.
Debes analizar la propuesta y generar un diseño completo que incluya:
- Componentes React/Next.js necesarios con props y estados
- Flujo de pantallas/rutas
- Estados de componentes (loading, error, empty, success)
- Diseño visual ( Tailwind classes o descripción)
- Interacciones y eventos
- Responsividad

## Propuesta a diseñar:
PROMPT_EOF

echo "$PROPOSAL_CONTENT" >> "$TEMP_PROMPT"

cat >> "$TEMP_PROMPT" << 'PROMPT_EOF'

## Formato de Output OBLIGATORIO
Responde UNICAMENTE con JSON válido (sin markdown fences):
{
  "title": "título del diseño",
  "version": "1.0.0",
  "overview": "resumen del diseño de UI",
  "screen_flow": [
    {
      "route": "/ruta",
      "description": "descripción de la pantalla",
      "component": "ComponentName",
      "parent_route": "/parent"
    }
  ],
  "components": [
    {
      "name": "ComponentName",
      "type": "page|container|atomic|molecule|organism",
      "description": "propósito del componente",
      "props": [
        {"name": "propName", "type": "string|boolean|function|object", "required": true, "description": "descripción"}
      ],
      "states": ["loading", "error", "success", "empty"],
      "events": ["onClick", "onChange", "onSubmit"],
      "styles": "clases tailwind o descripción visual",
      "children": ["ChildComponent1", "ChildComponent2"],
      "file_path": "src/components/ComponentName.tsx"
    }
  ],
  "state_management": [
    {
      "context": "ContextName",
      "description": "propósito del contexto",
      "state": ["field1", "field2"],
      "actions": ["action1", "action2"],
      "file_path": "src/contexts/ContextName.tsx"
    }
  ],
  "routes": [
    {
      "path": "/ruta",
      "component": "PageComponent",
      "protected": true,
      "layout": "default|dashboard|auth",
      "middlewares": ["auth", "redirect"]
    }
  ],
  "visual_design": {
    "color_scheme": {
      "primary": "#color",
      "secondary": "#color",
      "background": "#color",
      "text": "#color"
    },
    "typography": {
      "headings": "font-size/weight",
      "body": "font-size/weight",
      "code": "font-family"
    },
    "spacing": "sistema de espaciado (4px, 8px, 16px...)",
    "responsive_breakpoints": ["sm:640px", "md:768px", "lg:1024px"]
  },
  "confidence_score": numero_del_1_al_10
}

## Constraints
- Solo JSON válido, sin texto adicional
- confidence_score DEBE ser un número del 1 al 10
- Todos los componentes deben tener file_path
- screen_flow debe representar el flujo completo de usuario
- Indicar qué componentes son existentes vs nuevos
PROMPT_EOF

# ============================================================
# LANZAR OPENCOD EN BACKGROUND
# ============================================================

log "Lanzando OpenCode..."

TEMP_OUTPUT=$(mktemp)

nohup opencode run "$(cat "$TEMP_PROMPT")" > "$TEMP_OUTPUT" 2>&1 &

OPENCOD_PID=$!
log "OpenCode PID: $OPENCOD_PID"
echo $OPENCOD_PID > "${LOG_DIR}/design_opencode.pid"
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
rm -f "${LOG_DIR}/design_opencode.pid"

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

# Guardar design
echo "$JSON_OUTPUT" | jq '.' > "$DESIGN_FILE"

# Generar contract
cat > "$CONTRACT_FILE" << EOF
{
  "type": "design_contract",
  "version": "2.0.0",
  "change": "$CHANGE",
  "agent": "design",
  "timestamp": "$TIMESTAMP",
  "status": "completed",
  "output_file": "$DESIGN_FILE",
  "confidence_score": $CONFIDENCE,
  "requires_hitl": $([ "$CONFIDENCE" -lt 7 ] && echo "true" || echo "false")
}
EOF

# ============================================================
# FINALIZAR
# ============================================================

mark_completed "$CONFIDENCE"

log_ok "Diseño generado: $DESIGN_FILE"
log_ok "Confidence: $CONFIDENCE/10"

if [ "$CONFIDENCE" -lt 7 ]; then
    log "⚠️  HITL requerido - revisar diseño antes de continuar"
fi

if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_DIR}/../history/"
fi

rm -f "$TEMP_OUTPUT"
exit 0
