#!/bin/bash
# cmx-memories Init - Inicializa la estructura de memoria para el proyecto
# Uso: cmx-memories-init.sh <project-name>
#
# Nota: Usa JSON como fallback si SQLite no está disponible

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORIES_DIR="$PROJECT_ROOT/artifacts/memories"
MEMORIES_DB="$PROJECT_ROOT/memories.json"

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_NAME="${1:-cmx-core}"

log() { echo -e "${BLUE}[MEMORY]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Crear directorio de memorias
mkdir -p "$MEMORIES_DIR"

log "Inicializando cmx-memories para proyecto: $PROJECT_NAME"

# Verificar si sqlite3 está disponible
if command -v sqlite3 &> /dev/null; then
    log "Usando SQLite como backend"
    # (código SQLite original - ver más abajo si se necesita)
else
    log_warn "SQLite no disponible. Usando JSON como backend."
    
    # Crear estructura JSON si no existe
    if [ ! -f "$MEMORIES_DB" ]; then
        cat > "$MEMORIES_DB" << 'EOF'
{
  "version": "1.0.0",
  "type": "memories",
  "memories": []
}
EOF
    fi
fi

# Crear archivo de metadata del proyecto
cat > "$MEMORIES_DIR/$PROJECT_NAME.json" <<EOF
{
  "project": "$PROJECT_NAME",
  "initialized_at": "$(date -Iseconds)",
  "memory_types": ["decision", "synthesis", "task", "note"],
  "schema_version": "1.0.0",
  "backend": "$(command -v sqlite3 &> /dev/null && echo 'sqlite' || echo 'json')"
}
EOF

log_ok "Proyecto '$PROJECT_NAME' inicializado en cmx-memories"

# Mostrar estructura
echo ""
echo "Estructura de memorias:"
echo "  Backend: $(command -v sqlite3 &> /dev/null && echo 'SQLite' || echo 'JSON')"
echo "  Archivo: $MEMORIES_DB"
echo ""
echo "Tipos de memoria disponibles:"
echo "  - decision: decisiones del orquestador/selectores"
echo "  - synthesis: informes de lecciones aprendidas"
echo "  - task: tareas del proyecto"
echo "  - note: notas generales"