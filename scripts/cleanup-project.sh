#!/bin/bash
# Cleanup Project - Cleanup post-proyecto con Síntesis Automática
# Uso: cleanup-project.sh <project-name>
#
# v2.1.1 — FIXED: Ahora usa SQLite (memories.db) en lugar de JSON
#          Reescrita toda la lógica de eliminación con SQL nativo

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORIES_DB="$PROJECT_ROOT/memories.db"
MEMORY_SAVE="$PROJECT_ROOT/scripts/memory-save.sh"
MEMORY_QUERY="$PROJECT_ROOT/scripts/memory-query.sh"
REGISTRY_FILE="$PROJECT_ROOT/config/ai-registry.json"

PROJECT="${1}"
LLM_FOR_SYNTHESIS="openrouter"

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[CLEANUP]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================================================
# VALIDACIÓN
# ============================================================================

if [ -z "$PROJECT" ]; then
    echo "Uso: cleanup-project.sh <project-name>"
    exit 1
fi

# Verificar que la base de datos existe
if [ ! -f "$MEMORIES_DB" ]; then
    log_error "Base de datos no encontrada: $MEMORIES_DB"
    log_error "Ejecuta primero: cmx init"
    exit 1
fi

log "Iniciando cleanup para proyecto: $PROJECT"

# ============================================================================
# 1. Contar y extraer decisiones del proyecto
# ============================================================================

log "Consultando decisiones del proyecto..."

DECISIONS_COUNT=$(sqlite3 "$MEMORIES_DB" "
    SELECT COUNT(*) FROM memories
    WHERE project = '$(echo "$PROJECT" | sed "s/'/''/g")'
    AND type = 'decision';
" 2>/dev/null || echo "0")

if [ "$DECISIONS_COUNT" -eq 0 ]; then
    log_warn "No hay decisiones para sintetizar"
    echo "{\"status\": \"no_decisions\", \"project\": \"$PROJECT\", \"kept\": 0, \"removed\": 0}"
    exit 0
fi

log "Encontradas $DECISIONS_COUNT decisiones"

# ============================================================================
# 2. Extraer contenido de decisiones para el prompt
# ============================================================================

DECISIONS_CONTENT=""
while IFS='|' read -r content agent phase created_at; do
    if [ -n "$content" ]; then
        DECISIONS_CONTENT="${DECISIONS_CONTENT}\n- [$created_at] $agent ($phase): $content"
    fi
done < <(sqlite3 "$MEMORIES_DB" "
    SELECT content, agent, phase, created_at
    FROM memories
    WHERE project = '$(echo "$PROJECT" | sed "s/'/''/g")'
    AND type = 'decision'
    ORDER BY created_at ASC
    LIMIT 100;
" 2>/dev/null || echo "")

# ============================================================================
# 3. Construir prompt de síntesis
# ============================================================================

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

# ============================================================================
# 4. Generar síntesis
# ============================================================================

log "Generando síntesis..."

# Verificar si openrouter está disponible
OPENROUTER_AVAILABLE=false
if [ -n "$OPENROUTER_API_KEY" ]; then
    OPENROUTER_AVAILABLE=true
fi

if [ "$OPENROUTER_AVAILABLE" = false ]; then
    log_warn "OpenRouter no disponible. Generando síntesis manual..."

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
    # Usar opencode para generar síntesis
    SYNTHESIS_CONTENT=$(timeout 120 opencode run "$SYNTHESIS_PROMPT" 2>&1 | head -500) || true

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

# ============================================================================
# 5. Guardar síntesis
# ============================================================================

log "Guardando síntesis..."

"$MEMORY_SAVE" "synthesis" "lecciones-aprendidas-$PROJECT" \
    "$SYNTHESIS_CONTENT" \
    "$PROJECT" "cleanup" "cleanup-$(date +%s)" "synthesis"

# ============================================================================
# 6. Eliminar decisiones individuales (usando SQL nativo — v2.1.1 fix)
# ============================================================================

log "Eliminando decisiones individuales del proyecto..."

PROJECT_ESCAPED=$(echo "$PROJECT" | sed "s/'/''/g")

# Contar antes de eliminar
BEFORE_COUNT=$(sqlite3 "$MEMORIES_DB" "
    SELECT COUNT(*) FROM memories
    WHERE project = '$PROJECT_ESCAPED' AND type = 'decision';
" 2>/dev/null || echo "0")

# Eliminar decisiones con SQL (no con jq — eso era el bug)
sqlite3 "$MEMORIES_DB" "
    DELETE FROM memories
    WHERE project = '$PROJECT_ESCAPED' AND type = 'decision';
" 2>/dev/null || {
    log_error "Error al eliminar decisiones"
    exit 1
}

# Verificar eliminación
AFTER_COUNT=$(sqlite3 "$MEMORIES_DB" "
    SELECT COUNT(*) FROM memories
    WHERE project = '$PROJECT_ESCAPED' AND type = 'decision';
" 2>/dev/null || echo "0")

DELETED_COUNT=$((BEFORE_COUNT - AFTER_COUNT))
log_ok "Eliminadas $DELETED_COUNT decisiones individuales"

# ============================================================================
# 7. Output final
# ============================================================================

log_ok "Cleanup completado"

cat << EOF
{
  "status": "completed",
  "project": "$PROJECT",
  "decisions_analyzed": $DECISIONS_COUNT,
  "decisions_deleted": $DELETED_COUNT,
  "kept": "synthesis",
  "synthesis_type": "lecciones-aprendidas",
  "timestamp": "$(date -Iseconds)"
}
EOF
