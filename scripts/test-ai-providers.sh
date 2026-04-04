#!/bin/bash
# Test AI Providers - Prueba la conectividad de todos los proveedores
# Uso: test-ai-providers.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

# Cargar variables de entorno
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo "========================================="
echo "  CMX-CORE - Test de Proveedores AI"
echo "========================================="
echo ""

# ============================================================================
# TEST 1: OPENCODE
# ============================================================================
echo -e "${BLUE}[TEST]${NC} OpenCode..."
echo "  Modelos disponibles:"
opencode models 2>/dev/null | sed 's/^/    /' || echo "    (error)"

echo ""
echo "  Probando con mensaje simple..."
RESULT=$(timeout 10 opencode run "responde solo 'OK'" 2>&1 | tail -5)
if echo "$RESULT" | grep -qi "ok\|hello\|response"; then
    echo -e "  ${GREEN}✅ OpenCode funciona${NC}"
else
    echo -e "  ${YELLOW}⚠️ Revisar credenciales${NC}"
    echo "    $RESULT" | head -2
fi

echo ""

# ============================================================================
# TEST 2: GEMINI CLI
# ============================================================================
echo -e "${BLUE}[TEST]${NC} Gemini CLI..."
if [ -n "$GEMINI_API_KEY" ]; then
    echo "  API Key: configurada"
    RESULT=$(timeout 15 gemini -p "responde solo 'OK'" 2>&1 | tail -10)
    if echo "$RESULT" | grep -qi "ok\|hello"; then
        echo -e "  ${GREEN}✅ Gemini funciona${NC}"
    else
        echo -e "  ${YELLOW}⚠️ Revisar API key${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️ GEMINI_API_KEY no configurada${NC}"
    echo "    Agrega tu API key en .env"
fi

echo ""

# ============================================================================
# TEST 3: OPENROUTER
# ============================================================================
echo -e "${BLUE}[TEST]${NC} OpenRouter..."
if [ -n "$OPENROUTER_API_KEY" ]; then
    echo "  API Key: configurada"
    echo "  Probando modelo gratuito: deepseek/deepseek-chat"
    
    RESULT=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "Content-Type: application/json" \
        -d '{"model": "deepseek/deepseek-chat", "messages": [{"role": "user", "content": "responde solo OK"}]}' 2>&1 | jq -r '.choices[0].message.content' 2>/dev/null)
    
    if [ -n "$RESULT" ]; then
        echo -e "  ${GREEN}✅ OpenRouter funciona${NC}"
        echo "    Respuesta: $RESULT"
    else
        echo -e "  ${YELLOW}⚠️ Error en OpenRouter${NC}"
    fi
else
    echo -e "  ${YELLOW}⚠️ OPENROUTER_API_KEY no configurada${NC}"
    echo "    OpenRouter ofrece modelos gratuitos sin costo"
    echo "    Ve a https://openrouter.ai/settings para obtener API key"
fi

echo ""
echo "========================================="
echo "  Resumen"
echo "========================================="
echo ""
echo "Para usar un proveedor en cmx-core:"
echo "  1. Agrega la API key al archivo .env"
echo "  2. Ejecuta: source .env"
echo "  3. Prueba: ./cmx task 'tu tarea'"
echo ""
echo "Proveedores disponibles sin API key:"
echo "  - OpenCode: 5 modelos gratuitos incluidos"
echo "    (big-pickle, gpt-5-nano, minimax-m2.5-free, etc.)"