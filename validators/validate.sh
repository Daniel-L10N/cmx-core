#!/bin/bash
# Schema Validator — Valida outputs contra JSON Schemas
# Uso: ./validate.sh <schema> <file>

set -e

SCHEMAS_DIR="/home/cmx/cmx-core/schemas"
WORKSPACE="/home/cmx/cmx-core"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

validate() {
    local schema_name="$1"
    local file="$2"
    
    local schema_file="$SCHEMAS_DIR/${schema_name}.schema.json"
    
    if [ ! -f "$schema_file" ]; then
        echo -e "${RED}Schema no encontrado: $schema_file${NC}"
        return 1
    fi
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}Archivo no encontrado: $file${NC}"
        return 1
    fi
    
    # Verificar JSON válido
    if ! jq empty "$file" 2>/dev/null; then
        echo -e "${RED}JSON inválido en: $file${NC}"
        return 1
    fi
    
    # Verificar campos requeridos
    echo -e "${YELLOW}Validando: $schema_name${NC}"
    echo "Archivo: $file"
    
    # Verificar con jq (validación básica)
    local required_fields=$(jq -r '.required[]?' "$schema_file" 2>/dev/null || echo "")
    
    if [ -n "$required_fields" ]; then
        echo "Campos requeridos:"
        while IFS= read -r field; do
            if jq -e "has(\"$field\")" "$file" > /dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} $field"
            else
                echo -e "  ${RED}✗${NC} $field (FALTANTE)"
                return 1
            fi
        done <<< "$required_fields"
    fi
    
    # Verificar tipos
    local schema_type=$(jq -r '.type' "$schema_file")
    local file_type=$(jq -r '.type' "$file")
    
    if [ "$schema_type" == "$file_type" ]; then
        echo -e "${GREEN}Tipo correcto: $schema_type${NC}"
    else
        echo -e "${YELLOW}Tipo: esperado=$schema_type, encontrado=$file_type${NC}"
    fi
    
    echo -e "${GREEN}✓ Validación pasada${NC}"
    return 0
}

show_schemas() {
    echo "Schemas disponibles:"
    ls -1 "$SCHEMAS_DIR"/*.json 2>/dev/null | sed 's|.*/||' | sed 's/.schema.json//' | while read schema; do
        echo "  - $schema"
    done
}

case "${1:-}" in
    "")
        show_schemas
        echo ""
        echo "Uso: $0 <schema-name> <file.json>"
        ;;
    list)
        show_schemas
        ;;
    *)
        validate "$1" "$2"
        ;;
esac
