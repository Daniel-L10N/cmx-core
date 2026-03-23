#!/bin/bash
# Agent: Explorer — Explora codebase y analiza requerimentos
# EJECUTA COMO PROCESO INDEPENDIENTE

set -e

WORKSPACE="$1"
CHANGE="$2"
BATCH="${3:-1}"

if [ -z "$WORKSPACE" ] || [ -z "$CHANGE" ]; then
    echo "ERROR: Uso: explorer.sh <workspace> <change-name> [batch]"
    exit 1
fi

OUTPUT_DIR="$WORKSPACE/artifacts/exploration"
mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="$OUTPUT_DIR/${CHANGE}.md"
CONTRACT_FILE="$OUTPUT_DIR/${CHANGE}.contract.json"

echo "=== EXPLORER AGENT (PID: $$) ==="
echo "Workspace: $WORKSPACE"
echo "Change: $CHANGE"

# =============================================================================
# EXPLORAR ESTRUCTURA DEL PROYECTO
# =============================================================================

echo "Explorando estructura..."

STRUCTURE=""
if [ -d "$WORKSPACE" ]; then
    STRUCTURE=$(find "$WORKSPACE" -maxdepth 3 -type f \( -name "*.json" -o -name "*.yaml" -o -name "*.yml" -o -name "*.ts" -o -name "*.tsx" -o -name "*.py" -o -name "*.sh" \) 2>/dev/null | head -80 | sed "s|$WORKSPACE|.|" | sort)
fi

PACKAGE_NAME="N/A"
PACKAGE_VERSION="N/A"
PACKAGE_DEPS=""

if [ -f "$WORKSPACE/package.json" ]; then
    PACKAGE_NAME=$(jq -r '.name // "N/A"' "$WORKSPACE/package.json" 2>/dev/null || echo "N/A")
    PACKAGE_VERSION=$(jq -r '.version // "N/A"' "$WORKSPACE/package.json" 2>/dev/null || echo "N/A")
    PACKAGE_DEPS=$(jq -r '.dependencies | keys[]?' "$WORKSPACE/package.json" 2>/dev/null | head -10 | tr '\n' ', ' || echo "")
fi

PYTHON_DEPS=""
if [ -f "$WORKSPACE/requirements.txt" ]; then
    PYTHON_DEPS=$(cat "$WORKSPACE/requirements.txt" 2>/dev/null | grep -v '^#' | head -10 | tr '\n' ', ')
fi

# =============================================================================
# DETECTAR TIPO DE CAMBIO
# =============================================================================

TOPIC_DESC="Feature general"
case "$CHANGE" in
    *auth*|*login*|*logout*|*jwt*|*oauth*) 
        TOPIC_DESC="Sistema de autenticación y autorización (JWT, OAuth, sessions)"
        ;;
    *api*|*rest*|*endpoint*|*graphql*)
        TOPIC_DESC="API REST/GraphQL endpoints"
        ;;
    *ui*|*frontend*|*react*|*vue*|*component*)
        TOPIC_DESC="Componentes de interfaz de usuario (React/Vue)"
        ;;
    *db*|*database*|*model*|*migration*)
        TOPIC_DESC="Modelos de base de datos y migrations"
        ;;
    *test*|*coverage*|*unit*|*e2e*)
        TOPIC_DESC="Tests unitarios, integración y e2e"
        ;;
    *perf*|*optim*|*cache*|*speed*)
        TOPIC_DESC="Optimización de rendimiento y caching"
        ;;
    *sec*|*security*|*vuln*)
        TOPIC_DESC="Seguridad y vulnerabilidades"
        ;;
    *deploy*|*ci*|*cd*|*pipeline*)
        TOPIC_DESC="CI/CD y deployment"
        ;;
    *mobile*|*ios*|*android*|*react-native*)
        TOPIC_DESC="Aplicación móvil"
        ;;
esac

# =============================================================================
# ENCONTRAR ARCHIVOS RELEVANTES
# =============================================================================

RELEVANT_FILES=""
if [ -d "$WORKSPACE/src" ]; then
    RELEVANT_FILES=$(find "$WORKSPACE/src" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.py" \) 2>/dev/null | head -30 | sed "s|$WORKSPACE|.|")
elif [ -d "$WORKSPACE" ]; then
    RELEVANT_FILES=$(find "$WORKSPACE" -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.py" -o -name "*.js" \) 2>/dev/null | grep -v node_modules | grep -v __pycache__ | head -30 | sed "s|$WORKSPACE|.|")
fi

# =============================================================================
# DETECTAR CONFIGURACIONES
# =============================================================================

CONFIG_FILES=""
if [ -d "$WORKSPACE" ]; then
    CONFIG_FILES=$(find "$WORKSPACE" -maxdepth 2 -type f \( -name "*.config.*" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) 2>/dev/null | grep -v node_modules | sed "s|$WORKSPACE|.|" | head -20)
fi

# =============================================================================
# GENERAR OUTPUT MARKDOWN
# =============================================================================

cat > "$OUTPUT_FILE" << EOF
# Exploración: $CHANGE

## Metadata
| Campo | Valor |
|-------|-------|
| **Fecha** | $(date -Iseconds) |
| **Agent** | explorer |
| **PID** | $$ |
| **Workspace** | $WORKSPACE |

## Resumen
Exploración del codebase para implementar: **$CHANGE**

## Tipo de Cambio Detectado
$TOPIC_DESC

## Stack Tecnológico
- **Package**: $PACKAGE_NAME @ $PACKAGE_VERSION
- **Dependencies**: ${PACKAGE_DEPS:-Ninguna detectada}
- **Python deps**: ${PYTHON_DEPS:-Ninguna detectada}

## Estructura del Proyecto
\`\`\`
$STRUCTURE
\`\`\`

## Archivos Relevantes
\`\`\`
$RELEVANT_FILES
\`\`\`

## Configuraciones
\`\`\`
$CONFIG_FILES
\`\`\`

## Áreas de Impacto Potencial
1. Core domain logic
2. API / endpoints
3. Data models
4. Frontend components
5. Tests

## Dependencias Externas
- NPM packages instalados
- Python packages en requirements.txt
- Servicios externos (API keys, DB, etc)

## Constraints Identificados
- Compatibilidad con versiones existentes
- Requerimientos de rendimiento
- Consideraciones de seguridad

## Próximos Pasos
1. Analizar dependencias del cambio
2. Identificar archivos a modificar
3. Crear propuesta formal (proposer)

## Notas
- Exploración generada automáticamente
- Requiere revisión manual antes de proceder
EOF

# =============================================================================
# GENERAR CONTRATO JSON (para validación)
# =============================================================================

cat > "$CONTRACT_FILE" << EOF
{
  "type": "exploration_contract",
  "version": "1.0.0",
  "change": "$CHANGE",
  "agent": "explorer",
  "pid": $$,
  "timestamp": "$(date -Iseconds)",
  "status": "completed",
  "output": {
    "exploration": "$OUTPUT_FILE",
    "contract": "$CONTRACT_FILE"
  },
  "schema": {
    "required": ["type", "version", "change", "agent", "status"],
    "output_fields": ["exploration", "contract"]
  }
}
EOF

# =============================================================================
# VERIFICAR OUTPUT
# =============================================================================

if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    echo "✓ Exploración completada: $OUTPUT_FILE"
    echo "✓ Contrato generado: $CONTRACT_FILE"
    echo "Lines: $(wc -l < "$OUTPUT_FILE")"
    exit 0
else
    echo "✗ Error: Output no generado"
    exit 1
fi
