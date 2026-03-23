#!/bin/bash
# Cognitive Stack v2 — Agent: Verifier (QA)
# Verifica implementación contra especificación usando OpenCode CLI
# Input: artifacts/implementation/{CHANGE}_batch_{BATCH}.json + artifacts/specs/{CHANGE}.json
# Output: artifacts/verification/{CHANGE}_batch_{BATCH}.json

set -e

WORKSPACE="${WORKSPACE:-$HOME/cmx-core}"
CHANGE="${1}"
BATCH="${2:-1}"

# ============================================================
# VALIDACIONES
# ============================================================

if [ -z "$CHANGE" ]; then
    echo "ERROR: Uso: verifier.sh <change-name> <batch-number>"
    exit 1
fi

STATE_FILE="$WORKSPACE/orchestrator/agent_state.json"
LOG_DIR="$WORKSPACE/orchestrator/logs/active"
IMPL_FILE="$WORKSPACE/artifacts/implementation/${CHANGE}_batch_${BATCH}.json"
SPEC_FILE="$WORKSPACE/artifacts/specs/${CHANGE}.json"
VERIF_DIR="$WORKSPACE/artifacts/verification"
OUTPUT_FILE="$VERIF_DIR/${CHANGE}_batch_${BATCH}.json"
TIMESTAMP=$(date -Iseconds)

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[VERIFIER:BATCH-${BATCH}]${NC} $1"; }
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
    update_state "verifier" "status" "running"
    update_state "verifier" "pid" "$pid"
    update_state "verifier" "started_at" "$TIMESTAMP"
    update_state "verifier" "log_file" "$LOG_FILE"
}

mark_completed() {
    local confidence="$1"
    local requires_hitl="$2"
    
    update_state "verifier" "status" "completed"
    update_state "verifier" "pid" "null"
    update_state "verifier" "completed_at" "$(date -Iseconds)"
    update_state "verifier" "confidence_score" "$confidence"
    update_state "verifier" "requires_hitl" "$requires_hitl"
}

mark_failed() {
    local error_msg="${1:-Unknown error}"
    update_state "verifier" "status" "failed"
    update_state "verifier" "pid" "null"
    update_state "verifier" "completed_at" "$(date -Iseconds)"
    update_state "verifier" "error" "$error_msg"
    update_state "verifier" "requires_hitl" "true"
}

# ============================================================
# PREPARAR LOG FILE
# ============================================================

LOG_FILE="${LOG_DIR}/verify_${CHANGE}_batch${BATCH}_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$LOG_DIR"
mkdir -p "$VERIF_DIR"
echo $$ > "${LOG_DIR}/verifier.pid"

log "=========================================="
log "Iniciando Verifier para: $CHANGE"
log "Batch: $BATCH"
log "Implementation: $IMPL_FILE"
log "Spec: $SPEC_FILE"
log "Output: $OUTPUT_FILE"
log "=========================================="

# ============================================================
# VERIFICAR INPUTS
# ============================================================

if [ ! -f "$IMPL_FILE" ]; then
    log_error "Implementation file no encontrado: $IMPL_FILE"
    mark_failed "Implementation file not found"
    exit 1
fi

if [ ! -f "$SPEC_FILE" ]; then
    log_error "Spec file no encontrado: $SPEC_FILE"
    mark_failed "Spec file not found"
    exit 1
fi

# Extraer archivos a verificar
log "Extrayendo información de implementación..."

FILES_TO_CHECK=$(jq -r '.files_created_or_modified[]?' "$IMPL_FILE" 2>/dev/null)
IMPL_BATCH=$(jq -r '.batch_executed // 1' "$IMPL_FILE")
TASKS_IN_BATCH=$(jq -r '.tasks_completed[]?' "$IMPL_FILE" 2>/dev/null | tr '\n' ',')

if [ -z "$FILES_TO_CHECK" ]; then
    log_error "No se encontraron archivos en $IMPL_FILE"
    mark_failed "No files to verify"
    exit 1
fi

log "Batch implementado: $IMPL_BATCH"
log "Tareas completadas: $TASKS_IN_BATCH"
log "Archivos a verificar:"
echo "$FILES_TO_CHECK" | while read file; do
    [ -n "$file" ] && echo "  - $file"
done

# ============================================================
# CONSTRUIR PROMPT DETALLADO PARA OPENCOD
# ============================================================

TEMP_PROMPT=$(mktemp)

# Header del prompt
cat > "$TEMP_PROMPT" << 'PROMPT_EOF'
# SDD Agent: Verifier (QA)
# Task: Verificar implementación contra especificación

## Instrucciones
Eres un Ingeniero de QA y Seguridad. Tu objetivo es REVISAR el código existente en el disco.
Debes:
1. Leer los archivos recién creados/modificados
2. Verificar que cumplan con la especificación técnica
3. Detectar vulnerabilidades de seguridad (tokens expuestos, inyecciones, etc.)
4. Verificar buenas prácticas de TypeScript/Clean Code
5. Reportar problemas encontrados

## IMPORTANTE
- USA HERRAMIENTAS DE LECTURA para leer los archivos
- Lee cada archivo en el disco antes de verificar
- SE HONESTO: reporta TODOS los problemas que encuentres
- Si no hay problemas, passed = true
- Si hay problemas high/medium severity, passed = false

## Workspace
PROMPT_EOF

echo "$WORKSPACE" >> "$TEMP_PROMPT"

cat >> "$TEMP_PROMPT" << 'PROMPT_EOF'

## Archivos a Verificar (del batch anterior)
PROMPT_EOF

echo "$FILES_TO_CHECK" | while read file; do
    [ -n "$file" ] && echo "- $file" >> "$TEMP_PROMPT"
done

cat >> "$TEMP_PROMPT" << 'PROMPT_EOF'

## Especificación Técnica (Reglas de Negocio)
PROMPT_EOF

cat "$SPEC_FILE" >> "$TEMP_PROMPT" 2>/dev/null || echo "Spec no disponible" >> "$TEMP_PROMPT"

cat >> "$TEMP_PROMPT" << 'PROMPT_EOF'

## Formato de Output OBLIGATORIO
Al terminar de verificar TODOS los archivos, responde ÚNICAMENTE con este JSON:

{
  "batch_verified": NUMERO_DEL_BATCH,
  "files_checked": ["archivo1.ts", "archivo2.tsx", ...],
  "passed": true_o_false,
  "issues_found": [
    {
      "file": "nombre_del_archivo",
      "issue": "descripción del problema encontrado",
      "severity": "high|medium|low",
      "fix_suggestion": "cómo arreglarlo"
    }
  ],
  "confidence_score": NUMERO_DEL_1_AL_10
}

## Constraints
- Solo JSON válido en la respuesta final, sin markdown fences
- files_checked debe listar TODOS los archivos leídos
- Si no hay issues, usa: "issues_found": []
- passed = true SOLO si no hay issues o son todos "low" severity
- Si hay issues "high" o "medium", passed = false
- confidence_score: qué tan seguro estás de tu análisis (1-10)
PROMPT_EOF

# ============================================================
# LANZAR OPENCOD EN BACKGROUND
# ============================================================

log "Lanzando OpenCode para verificar batch $BATCH..."

TEMP_OUTPUT=$(mktemp)

nohup opencode run "$(cat "$TEMP_PROMPT")" > "$TEMP_OUTPUT" 2>&1 &

OPENCOD_PID=$!
log "OpenCode PID: $OPENCOD_PID"
echo $OPENCOD_PID > "${LOG_DIR}/verifier_opencode.pid"
mark_started "$OPENCOD_PID"
rm -f "$TEMP_PROMPT"

# ============================================================
# TIMEOUT DUAL: SIGINT (4min) -> SIGKILL (5min)
# ============================================================

TIMEOUT_SOFT=240  # 4 minutos
TIMEOUT_HARD=300  # 5 minutos

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
    
    if [ $((ELAPSED % 30)) -eq 0 ] && [ $ELAPSED -gt 0 ]; then
        log "Verificando... ${ELAPSED}s / ${TIMEOUT_HARD}s"
    fi
done

wait $OPENCOD_PID 2>/dev/null || true
rm -f "${LOG_DIR}/verifier_opencode.pid"

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
    head -c 2000 "$TEMP_OUTPUT"
    mark_failed "Invalid JSON output"
    rm -f "$TEMP_OUTPUT"
    exit 1
fi

# Extraer datos del resultado
VERIF_BATCH=$(echo "$JSON_OUTPUT" | jq -r '.batch_verified // 1')
FILES_CHECKED=$(echo "$JSON_OUTPUT" | jq -r '.files_checked // []')
PASSED=$(echo "$JSON_OUTPUT" | jq -r '.passed // false')
ISSUES=$(echo "$JSON_OUTPUT" | jq -r '.issues_found // []')
CONFIDENCE=$(echo "$JSON_OUTPUT" | jq -r '.confidence_score // 5')

log "Batch verificado: $VERIF_BATCH"
log "Archivos revisados: $FILES_CHECKED"
log "Passed: $PASSED"
log "Issues encontrados: $(echo "$ISSUES" | jq -r 'length')"
log "Confidence: $CONFIDENCE"

# Contar issues por severity
HIGH_ISSUES=$(echo "$ISSUES" | jq '[.[] | select(.severity == "high")] | length')
MEDIUM_ISSUES=$(echo "$ISSUES" | jq '[.[] | select(.severity == "medium")] | length')

if [ "$HIGH_ISSUES" -gt 0 ]; then
    log_error "⚠️  Issues HIGH encontrados: $HIGH_ISSUES"
fi

if [ "$MEDIUM_ISSUES" -gt 0 ]; then
    log_warn "⚠️  Issues MEDIUM encontrados: $MEDIUM_ISSUES"
fi

# Guardar resultado de verificación
echo "$JSON_OUTPUT" | jq '.' > "$OUTPUT_FILE"

# ============================================================
# DETERMINAR HITL
# ============================================================

# Forzar HITL si:
# - passed = false
# - confidence < 8
# - Hay issues high severity

REQUIRE_HITL="false"

if [ "$PASSED" == "false" ]; then
    log_warn "⚠️  Verificación FALLIDA - HITL requerido"
    REQUIRE_HITL="true"
fi

if [ "$CONFIDENCE" -lt 8 ]; then
    log_warn "⚠️  Confidence bajo ($CONFIDENCE < 8) - HITL recomendado"
    REQUIRE_HITL="true"
fi

if [ "$HIGH_ISSUES" -gt 0 ]; then
    log_error "⚠️  Issues HIGH severity - HITL OBLIGATORIO"
    REQUIRE_HITL="true"
fi

# ============================================================
# FINALIZAR
# ============================================================

mark_completed "$CONFIDENCE" "$REQUIRE_HITL"

log_ok "=========================================="
log_ok "Verificación completada"
log_ok "Output: $OUTPUT_FILE"
log_ok "Confidence: $CONFIDENCE/10"
log_ok "Passed: $PASSED"
log_ok "=========================================="

if [ "$REQUIRE_HITL" == "true" ]; then
    log_warn "🚨 PIPELINE BLOQUEADO - Revisión humana requerida"
fi

if [ -f "$LOG_FILE" ]; then
    mv "$LOG_FILE" "${LOG_DIR}/../history/"
fi

rm -f "$TEMP_OUTPUT"
exit 0
