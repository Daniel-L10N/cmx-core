#!/bin/bash
# Setup AI Providers - Configura API keys para los proveedores de IA
# Uso: setup-ai-providers.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ENV_FILE="$PROJECT_ROOT/.env"

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}[SETUP]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================="
echo "  CMX-CORE AI Providers Setup"
echo "========================================="
echo ""

# ============================================================================
# 1. OPENCODE (Modelos gratis incluidos)
# ============================================================================
log "Configurando OpenCode..."

if [ -f "$HOME/.local/share/opencode/auth.json" ]; then
    log_ok "OpenCode ya tiene configuración"
    OPENCODE_CREDS=$(cat "$HOME/.local/share/opencode/auth.json" | jq 'keys' 2>/dev/null || echo "[]")
    echo "  Proveedores configurados: $OPENCODE_CREDS"
else
    log_warn "OpenCode necesita login"
    echo ""
    echo "  Para configurar OpenCode:"
    echo "  1. Ve a https://opencode.ai/settings"
    echo "  2. Copia tu API key"
    echo "  3. Ejecuta: opencode providers login"
fi

echo ""
echo "  Modelos disponibles en OpenCode:"
opencode models 2>/dev/null | sed 's/^/    - /' || echo "    (no disponibles)"
echo ""

# ============================================================================
# 2. GEMINI CLI
# ============================================================================
log "Configurando Gemini CLI..."

# Verificar si hay API key en entorno
if [ -n "$GEMINI_API_KEY" ]; then
    log_ok "GEMINI_API_KEY configurada"
else
    log_warn "GEMINI_API_KEY no encontrada"
    echo ""
    echo "  Para obtener una API key de Gemini:"
    echo "  1. Ve a https://aistudio.google.com/app/apikey"
    echo "  2. Crea una nueva API key"
    echo "  3. Agrega: export GEMINI_API_KEY='tu-api-key'"
fi

# Verificar si gemini tiene sesión activa
if gemini --list-sessions 2>/dev/null | grep -q "No sessions"; then
    echo "  Estado: Sin sesiones activas (primera vez)"
else
    echo "  Estado: Gemini CLI listo"
fi

echo ""

# ============================================================================
# 3. OPENROUTER
# ============================================================================
log "Configurando OpenRouter..."

if [ -n "$OPENROUTER_API_KEY" ]; then
    log_ok "OPENROUTER_API_KEY configurada"
    echo "  Modelos gratuitos disponibles:"
    echo "    - deepseek/deepseek-chat"
    echo "    - meta-llama/llama-3.2-1b-instruct"
    echo "    - google/gemma-2-2b-it"
    echo "    - mistralai/mistral-7b-instruct"
else
    log_warn "OPENROUTER_API_KEY no encontrada"
    echo ""
    echo "  Para obtener una API key gratuita de OpenRouter:"
    echo "  1. Ve a https://openrouter.ai/settings"
    echo "  2. Crea una cuenta y genera API key"
    echo "  3. OpenRouter ofrece créditos gratuitos mensuales"
fi

echo ""

# ============================================================================
# CREAR .env si no existe
# ============================================================================
if [ ! -f "$ENV_FILE" ]; then
    log "Creando archivo .env..."
    cat > "$ENV_FILE" << 'EOF'
# CMX-CORE - Variables de Entorno
# ============================================

# OpenCode (incluye modelos gratuitos)
# No requiere API key adicional - los modelos gratis vienen con OpenCode

# Gemini CLI
# Obtén tu API key en: https://aistudio.google.com/app/apikey
# GEMINI_API_KEY=tu-api-key-aqui

# OpenRouter (modelos gratuitos disponibles)
# Obtén tu API key en: https://openrouter.ai/settings
# OPENROUTER_API_KEY=tu-api-key-aqui

# OLLAMA (local, sin internet)
# Instalar: https://ollama.ai/
# ollama pull llama3.2
EOF
    log_ok "Archivo .env creado: $ENV_FILE"
    echo ""
    echo "  Edita $ENV_FILE y agrega tus API keys"
else
    log_ok "Archivo .env ya existe"
fi

echo ""

# ============================================================================
# ACTUALIZAR AI-REGISTRY
# ============================================================================
log "Verificando ai-registry.json..."

REGISTRY="$PROJECT_ROOT/config/ai-registry.json"

# Verificar que existe
if [ -f "$REGISTRY" ]; then
    log_ok "ai-registry.json encontrado"
    echo ""
    echo "  Proveedores registrados:"
    jq -r '.ias | to_entries[] | "  - \(.key): \(.value.status)"' "$REGISTRY" 2>/dev/null
else
    log_error "ai-registry.json no encontrado"
fi

echo ""
echo "========================================="
echo "  Resumen de Configuración"
echo "========================================="
echo ""
echo "Proveedor      | Modelos Gratuitos | Estado"
echo "-------------- | ----------------- | ------"
echo "OpenCode       | 5 modelos         | $([ -f "$HOME/.local/share/opencode/auth.json" ] && echo 'Configurado' || echo 'Por configurar')"
echo "Gemini CLI     | Gemini 2.0        | $([ -n "$GEMINI_API_KEY" ] && echo 'Listo' || echo 'Por configurar')"
echo "OpenRouter     | 300+ modelos      | $([ -n "$OPENROUTER_API_KEY" ] && echo 'Listo' || echo 'Por configurar')"
echo ""

# ============================================================================
# PRUEBA DE CONECTIVIDAD
# ============================================================================
log "Probando conectividad..."

# Test 1: OpenCode
echo -n "  OpenCode: "
if timeout 3 opencode models >/dev/null 2>&1; then
    echo "✅ Conectado"
else
    echo "⚠️ Revisar credenciales"
fi

# Test 2: Gemini
echo -n "  Gemini: "
if timeout 3 gemini -p "test" 2>&1 | grep -q "error\|Error\|failed"; then
    echo "⚠️ Revisar API key"
else
    echo "✅ Listo"
fi

echo ""
log_ok "Setup completado!"
echo ""
echo "Próximos pasos:"
echo "  1. Agrega tus API keys en $ENV_FILE"
echo "  2. Ejecuta: source $ENV_FILE"
echo "  3. Prueba: ./cmx status"