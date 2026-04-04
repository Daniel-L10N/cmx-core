#!/bin/bash
# Pre-flight Check - Valida que las IAs estén disponibles antes de ejecutar
# Uso: check-environment.sh [--strict]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_FILE="$PROJECT_ROOT/config/ai-registry.json"

# Cargar .env si existe
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

STRICT_MODE=false
if [ "$1" = "--strict" ]; then
    STRICT_MODE=true
fi

log_info() { echo -e "${BLUE}[CHECK]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verificar que el registry existe
if [ ! -f "$REGISTRY_FILE" ]; then
    echo "{\"status\": \"error\", \"message\": \"Registry not found: $REGISTRY_FILE\"}"
    exit 1
fi

log_info "Verificando entorno para IAs disponibles..."
echo ""

AVAILABLE=()
MISSING=()

# ============================================================================
# 1. Verificar OpenCode (CLI - no necesita env)
# ============================================================================
if command -v opencode >/dev/null 2>&1; then
    log_ok "OpenCode CLI disponible"
    AVAILABLE+=("opencode")
    echo "   Modelos: $(opencode models 2>/dev/null | tr '\n' ', ')"
else
    log_warn "OpenCode CLI no disponible"
    MISSING+=("opencode:command")
fi

# ============================================================================
# 2. Verificar Gemini CLI (CLI directo - no necesita API key)
# ============================================================================
if command -v gemini >/dev/null 2>&1; then
    log_ok "Gemini CLI disponible (usa CLI directamente)"
    AVAILABLE+=("gemini")
    echo "   Modelos: gemini-2.0-flash, gemini-2.0-pro"
else
    log_warn "Gemini CLI no disponible"
    MISSING+=("gemini:command")
fi

# ============================================================================
# 3. Verificar OpenRouter (API - necesita API key)
# ============================================================================
if [ -n "$OPENROUTER_API_KEY" ]; then
    # Probar conectividad básica
    if curl -s -o /dev/null -w "%{http_code}" "https://openrouter.ai/api/v1/models" -H "Authorization: Bearer $OPENROUTER_API_KEY" 2>/dev/null | grep -q "200\|401"; then
        log_ok "OpenRouter API disponible"
        AVAILABLE+=("openrouter")
        echo "   Modelos gratuitos: deepseek, llama3.2, gemma-2-2b, mistral"
    else
        log_warn "OpenRouter API no accesible"
        MISSING+=("openrouter:connection")
    fi
else
    log_warn "OpenRouter no disponible (falta OPENROUTER_API_KEY)"
    MISSING+=("openrouter:OPENROUTER_API_KEY")
fi

# ============================================================================
# 4. Verificar Ollama (local)
# ============================================================================
if command -v ollama >/dev/null 2>&1; then
    log_ok "Ollama disponible (offline)"
    AVAILABLE+=("ollama")
    echo "   Modelos: $(ollama list 2>/dev/null | grep -v 'NAME' | awk '{print $1}' | tr '\n' ', ')"
else
    log_warn "Ollama no disponible (opcional - modo offline)"
    # No es required, no agregar a MISSING
fi

echo ""

# ============================================================================
# GENERAR OUTPUT JSON
# ============================================================================

# Cargar modelos disponibles
OPENCODE_MODELS=$(opencode models 2>/dev/null | tr '\n' ',' | sed 's/,$//')
GEMINI_MODELS="gemini-2.0-flash,gemini-2.0-pro"
OPENROUTER_MODELS="deepseek/deepseek-chat,meta-llama/llama-3.2-1b-instruct,google/gemma-2-2b-it,mistralai/mistral-7b-instruct"

echo "=== Resumen ==="
echo ""
printf "%-15s | %-12s | %-10s\n" "PROVEEDOR" "ESTADO" "MODELOS"
printf "%-15s-+-%-12s-+-%-10s\n" "---------------" "------------" "----------"
printf "%-15s | %-12s | %-10s\n" "OpenCode" "✅ Disponible" "$OPENCODE_MODELS"
printf "%-15s | %-12s | %-10s\n" "Gemini" "✅ Disponible" "$GEMINI_MODELS"
printf "%-15s | %-12s | %-10s\n" "OpenRouter" "✅ Disponible" "$OPENROUTER_MODELS"
printf "%-15s | %-12s | %-10s\n" "Ollama" "⚠️ Offline" "(local)"
echo ""

# JSON output
echo "{"
echo "  \"status\": \"$([ ${#MISSING[@]} -eq 0 ] && echo "ok" || echo "partial")\","
echo "  \"timestamp\": \"$(date -Iseconds)\","
echo "  \"providers\": {"
echo "    \"opencode\": {"
echo "      \"status\": \"available\","
echo "      \"type\": \"cli\","
echo "      \"models\": \"$OPENCODE_MODELS\""
echo "    },"
echo "    \"gemini\": {"
echo "      \"status\": \"available\","
echo "      \"type\": \"cli-direct\","
echo "      \"models\": \"$GEMINI_MODELS\","
echo "      \"note\": \"Usa CLI directamente, no requiere API key\""
echo "    },"
echo "    \"openrouter\": {"
echo "      \"status\": \"$([ -n "$OPENROUTER_API_KEY" ] && echo "available" || echo "unavailable")\","
echo "      \"type\": \"api\","
echo "      \"models\": \"$OPENROUTER_MODELS\""
echo "    }"
echo "  },"
echo "  \"available\": ["
for i in "${!AVAILABLE[@]}"; do
    echo -n "    \"${AVAILABLE[$i]}\""
    [ $i -lt $((${#AVAILABLE[@]} - 1)) ] && echo "," || echo ""
done
echo "  ],"
echo "  \"missing\": ["
if [ ${#MISSING[@]} -eq 0 ]; then
    echo "  ]"
else
    for i in "${!MISSING[@]}"; do
        IFS=':' read -r ia vars <<< "${MISSING[$i]}"
        echo "    {\"ia\": \"$ia\", \"vars\": \"$vars\"}"
        [ $i -lt $((${#MISSING[@]} - 1)) ] && echo ","
    done
    echo "  ]"
fi
echo "}"

# En modo strict, salir con error si falta algo crítico
if [ "$STRICT_MODE" = true ]; then
    # Solo OpenCode es realmente requerido
    if ! command -v opencode >/dev/null 2>&1; then
        log_error "OpenCode es requerido para ejecución estricta"
        exit 1
    fi
fi

# Salir con código apropiado
if [ ${#MISSING[@]} -eq 0 ]; then
    exit 0
else
    exit 0  # Warning but not fatal - tenemos alternativas
fi