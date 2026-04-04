#!/bin/bash
# Pre-flight Check - Valida que las IAs estén disponibles antes de ejecutar
# Uso: check-environment.sh [--strict]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REGISTRY_FILE="$PROJECT_ROOT/config/ai-registry.json"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Leer el registry
IAS=$(jq -r '.ias | to_entries[] | select(.value.status == "available") | .key' "$REGISTRY_FILE" 2>/dev/null)

AVAILABLE=()
MISSING=()

log_info "Verificando entorno para IAs disponibles..."

# Por cada IA disponible, verificar sus variables de entorno
while IFS= read -r ia; do
    [ -z "$ia" ] && continue
    
    # Obtener las variables requeridas para esta IA
    requires_env=$(jq -r ".ias.\"$ia\".requires_env // [] | .[]" "$REGISTRY_FILE" 2>/dev/null || echo "")
    
    ia_available=true
    missing_vars=""
    
    if [ -n "$requires_env" ]; then
        while IFS= read -r var; do
            [ -z "$var" ] && continue
            if [ -z "${!var}" ]; then
                ia_available=false
                missing_vars="$missing_vars $var"
            fi
        done <<< "$requires_env"
    fi
    
    if [ "$ia_available" = true ]; then
        AVAILABLE+=("$ia")
        log_ok "$ia disponible"
    else
        MISSING+=("$ia:$missing_vars")
        log_warn "$ia no disponible (faltan:$missing_vars)"
    fi
done <<< "$IAS"

# Generar output JSON
echo "{"
echo "  \"status\": \"$([ ${#MISSING[@]} -eq 0 ] && echo "ok" || echo "partial")\","
echo "  \"timestamp\": \"$(date -Iseconds)\","
echo "  \"available\": ["
for i in "${!AVAILABLE[@]}"; do
    echo -n "    \"${AVAILABLE[$i]}\""
    [ $i -lt $((${#AVAILABLE[@]} - 1)) ] && echo "," || echo ""
done
echo "  ],"
echo "  \"missing\": ["
for i in "${!MISSING[@]}"; do
    IFS=':' read -r ia vars <<< "${MISSING[$i]}"
    echo "    {\"ia\": \"$ia\", \"vars\": \"$vars\"}"
    [ $i -lt $((${#MISSING[@]} - 1)) ] && echo ","
done
echo "  ]"
echo "}"

# En modo strict, salir con error si falta algo
if [ "$STRICT_MODE" = true ] && [ ${#MISSING[@]} -gt 0 ]; then
    log_error "Entorno no válido para ejecución estricta"
    exit 1
fi

# Salir con código apropiado
if [ ${#MISSING[@]} -eq 0 ]; then
    exit 0
else
    exit 0  # Warning but not fatal
fi