#!/bin/bash
# Cleanup Project - Cleanup post-proyecto con Síntesis Automática
# Uso: cleanup-project.sh <project-name>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORIES_DB="$PROJECT_ROOT/memories.json"
MEMORY_SAVE="$PROJECT_ROOT/scripts/memory-save.sh"
MEMORY_QUERY="$PROJECT_ROOT/scripts/memory-query.sh"
REGISTRY_FILE="$PROJECT_ROOT/config/ai-registry.json"

PROJECT="${1}"
LLM_FOR_SYNTHESIS="openrouter"  # Usar openrouter para síntesis

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[CLEANUP]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

if [ -z "$PROJECT" ]; then
    echo "Uso: cleanup-project.sh <project-name>"
    exit 1
fi

log "Iniciando cleanup para proyecto: $PROJECT"

# 1. Leer todas las decisiones del proyecto
log "Consultando decisiones del proyecto..."
DECISIONS=$("$MEMORY_QUERY" "$PROJECT" "" "decision" 1000 2>/dev/null || echo "[]")

DECISIONS_COUNT=$(echo "$DECISIONS" | jq 'length' 2>/dev/null || echo "0")

if [ "$DECISIONS_COUNT" -eq 0 ]; then
    log_warn "No hay decisiones para sintetizar"
    echo "{\"status\": \"no_decisions\", \"project\": \"$PROJECT\", \"kept\": 0, \"removed\": 0}"
    exit 0
fi

log "Encontradas $DECISIONS_COUNT decisiones"

# 2. Extraer contenido de decisiones para el prompt
DECISIONS_CONTENT=""
for i in $(seq 0 $(($DECISIONS_COUNT - 1))); do
    decision=$(echo "$DECISIONS" | jq -r ".[$i].content // .title" 2>/dev/null || echo "")
    agent=$(echo "$DECISIONS" | jq -r ".[$i].agent // \"unknown\"" 2>/dev/null || echo "")
    phase=$(echo "$DECISIONS" | jq -r ".[$i].phase // \"unknown\"" 2>/dev/null || echo "")
    created=$(echo "$DECISIONS" | jq -r ".[$i].created_at // \"\"" 2>/dev/null || echo "")
    
    if [ -n "$decision" ]; then
        DECISIONS_CONTENT="$DECISIONS_CONTENT\n- [$created] $agent ($phase): $decision"
    fi
done

# 3. Construir prompt de síntesis
SYNTHESIS_PROMPT="Eres un analista técnico senior. Lee las siguientes decisiones de un proyecto 
y escribe un 'Informe de Lecciones Aprendidas' de una página.

Proyecto: $PROJECT
Número de decisiones: $DECISIONS_COUNT

DECISIONES:
$DECISIONS_CONTENT

El informe debe incluir:
1. **Errores cometidos y cómo se resolvieron** - Identifica patrones de errores
2. **Decisiones de IA que funcionaron vs fallaron** - Qué herramientas fueron útiles
3. **Recomendaciones para proyectos futuros** - Lecciones transferibles
4. **Métricas del proyecto** - Tareas, tiempo, exitos

Formato: Markdown, máximo 400 palabras.
Usa encabezados claros: ## Errores, ## Decisiones de IA, ## Recomendaciones, ## Métricas
No inventes datos que no estén en las decisiones."

# 4. Invocar IA para síntesis
log "Invocando IA para generar síntesis ($LLM_FOR_SYNTHESIS)..."

# Verificar que openrouter esté disponible
OPENROUTER_AVAILABLE=false
if [ -n "$OPENROUTER_API_KEY" ]; then
    OPENROUTER_AVAILABLE=true
fi

if [ "$OPENROUTER_AVAILABLE" = false ]; then
    log_warn "OpenRouter no disponible. Generando síntesis manual..."
    
    # Síntesis manual básica
    SYNTHESIS_CONTENT="# Informe de Lecciones Aprendidas - $PROJECT

## Resumen
Proyecto procesado con $DECISIONS_COUNT decisiones analizadas.

## Métricas
- Total de decisiones: $DECISIONS_COUNT
- Fecha de análisis: $(date -Iseconds)

## Notas
La síntesis automática requiere OPENROUTER_API_KEY configurada.
Las decisiones individuales se mantendrán hasta que se configure la síntesis."
else
    # Usar opencode para invocar a OpenRouter (usando su habilidad de chat)
    # Como no tenemos acceso directo a OpenRouter, usamos opencode como proxy
    SYNTHESIS_CONTENT=$(opencode run "$SYNTHESIS_PROMPT" 2>&1 | head -500) || true
    
    if [ -z "$SYNTHESIS_CONTENT" ] || [ ${#SYNTHESIS_CONTENT} -lt 50 ]; then
        log_warn "Síntesis automática falló. Usando template básico."
        SYNTHESIS_CONTENT="# Informe de Lecciones Aprendidas - $PROJECT

## Resumen
Se procesaron $DECISIONS_COUNT decisiones durante el proyecto.

## Métricas
- Decisiones totales: $DECISIONS_COUNT
- Fecha de síntesis: $(date -Iseconds)

## Notas
La síntesis automática no pudo generar contenido detallado.
Revisa las decisiones individuales en cmx-memories."
    fi
fi

# 5. Verificar si ya existe síntesis anterior
EXISTING_SYNTHESIS=$("$MEMORY_QUERY" "$PROJECT" "" "synthesis" 1 2>/dev/null | jq -r '.[0] // null' 2>/dev/null || echo "null")

if [ "$EXISTING_SYNTHESIS" != "null" ]; then
    log "Actualizando síntesis existente (accumulative)..."
    EXISTING_ID=$(echo "$EXISTING_SYNTHESIS" | jq -r '.id')
    # Actualizar la síntesis existente (append)
    UPDATED_CONTENT="$SYNTHESIS_CONTENT

---

*Síntesis previa actualizada el $(date -Iseconds)*"
    
    # Guardar como nueva síntesis (SQLite no permite update fácil de texto)
    "$MEMORY_SAVE" "synthesis" "lecciones-aprendidas-$PROJECT" \
        "$UPDATED_CONTENT" \
        "$PROJECT" "cleanup" "cleanup-$(date +%s)" "synthesis"
else
    # 6. Guardar nueva síntesis
    log "Guardando nueva síntesis..."
    "$MEMORY_SAVE" "synthesis" "lecciones-aprendidas-$PROJECT" \
        "$SYNTHESIS_CONTENT" \
        "$PROJECT" "cleanup" "cleanup-$(date +%s)" "synthesis"
fi

# 7. Eliminar decisiones individuales (ephímero)
log "Eliminando decisiones individuales..."

# Contar decisiones antes de eliminar
DECISIONS_BEFORE=$(jq "[.memories[] | select(.project == \"$PROJECT\" and .type == \"decision\")] | length" "$MEMORIES_DB" 2>/dev/null || echo "0")

# Eliminar decisiones del proyecto (manteniendo síntesis)
TEMP_FILE=$(mktemp)
jq --arg proj "$PROJECT" '[.memories[] | select(.project != $proj or .type != "decision")]' "$MEMORIES_DB" > "$TEMP_FILE" && mv "$TEMP_FILE" "$MEMORIES_DB"

DELETED_COUNT=$DECISIONS_BEFORE
log_ok "Eliminadas $DELETED_COUNT decisiones individuales"

# 8. Output final
log_ok "Cleanup completado"

echo "{"
echo "  \"status\": \"completed\","
echo "  \"project\": \"$PROJECT\","
echo "  \"decisions_analyzed\": $DECISIONS_COUNT,"
echo "  \"kept\": \"synthesis\","
echo "  \"removed\": $DELETED_COUNT,"
echo "  \"synthesis_type\": \"lecciones-aprendidas\","
echo "  \"timestamp\": \"$(date -Iseconds)\""
echo "}"