#!/bin/bash
# cmx-memories Init - Inicializa la estructura de memoria para el proyecto
# Uso: cmx-memories-init.sh <project-name>
#
# Backend: SQLite3 con FTS5 para búsqueda full-text

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORIES_DIR="$PROJECT_ROOT/artifacts/memories"
MEMORIES_DB="$PROJECT_ROOT/memories.db"

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_NAME="${1:-cmx-core}"

log() { echo -e "${BLUE}[MEMORY]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verificar si sqlite3 está disponible
if ! command -v sqlite3 &> /dev/null; then
    log_error "SQLite3 no está instalado. Ejecuta: sudo yum install sqlite"
    exit 1
fi

# Crear directorio de memorias
mkdir -p "$MEMORIES_DIR"

log "Inicializando cmx-memories para proyecto: $PROJECT_NAME"

# Crear base de datos SQLite con schema
sqlite3 "$MEMORIES_DB" << 'EOF'
-- Tabla principal de memorias
CREATE TABLE IF NOT EXISTS memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL DEFAULT 'memory',
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    project TEXT NOT NULL DEFAULT 'cmx-core',
    agent TEXT DEFAULT 'system',
    task_id TEXT,
    phase TEXT,
    metadata TEXT DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Tabla de tipos de memoria
CREATE TABLE IF NOT EXISTS memory_types (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    schema TEXT DEFAULT '{}',
    description TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Tabla de metadatos adicionales
CREATE TABLE IF NOT EXISTS memory_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    memory_id INTEGER NOT NULL,
    key TEXT NOT NULL,
    value TEXT,
    FOREIGN KEY (memory_id) REFERENCES memories(id) ON DELETE CASCADE
);

-- Índice para búsquedas por proyecto
CREATE INDEX IF NOT EXISTS idx_memories_project ON memories(project);

-- Índice para búsquedas por tipo
CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(type);

-- Índice para búsquedas por agent
CREATE INDEX IF NOT EXISTS idx_memories_agent ON memories(agent);

-- Índice para búsquedas por task_id
CREATE INDEX IF NOT EXISTS idx_memories_task_id ON memories(task_id);

-- FTS5 virtual table para búsqueda full-text
-- Usa tokenizer unicode61 para mejor soporte de caracteres internacionales
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    title,
    content,
    content='memories',
    content_rowid='id',
    tokenize='unicode61'
);

-- Trigger para mantener FTS5 sincronizado con la tabla principal
-- On INSERT
CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts(rowid, title, content) 
    VALUES (new.id, new.title, new.content);
END;

-- On DELETE
CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, title, content) 
    VALUES ('delete', old.id, old.title, old.content);
END;

-- On UPDATE
CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, title, content) 
    VALUES ('delete', old.id, old.title, old.content);
    INSERT INTO memories_fts(rowid, title, content) 
    VALUES (new.id, new.title, new.content);
END;

-- Insertar tipos de memoria por defecto si no existen
INSERT OR IGNORE INTO memory_types (name, description) VALUES 
    ('decision', 'Decisiones del orquestador/selectores'),
    ('synthesis', 'Informes de lecciones aprendidas'),
    ('task', 'Tareas del proyecto'),
    ('note', 'Notas generales'),
    ('bugfix', 'Correcciones de bugs'),
    ('architecture', 'Decisiones arquitectónicas');
EOF

log_ok "Base de datos creada: $MEMORIES_DB"

# Crear archivo de metadata del proyecto
cat > "$MEMORIES_DIR/$PROJECT_NAME.json" <<EOF
{
  "project": "$PROJECT_NAME",
  "initialized_at": "$(date -Iseconds)",
  "memory_types": ["decision", "synthesis", "task", "note", "bugfix", "architecture"],
  "schema_version": "2.0.0",
  "backend": "sqlite",
  "db_path": "$MEMORIES_DB"
}
EOF

log_ok "Proyecto '$PROJECT_NAME' inicializado en cmx-memories"

# Mostrar estructura
echo ""
echo "Estructura de memorias:"
echo "  Backend: SQLite3 + FTS5"
echo "  Archivo: $MEMORIES_DB"
echo ""
echo "Tipos de memoria disponibles:"
echo "  - decision: decisiones del orquestador/selectores"
echo "  - synthesis: informes de lecciones aprendidas"
echo "  - task: tareas del proyecto"
echo "  - note: notas generales"
echo "  - bugfix: correcciones de bugs"
echo "  - architecture: decisiones arquitectónicas"
echo ""
echo "Comandos disponibles:"
echo "  memory-save.sh <type> <title> <content> [project] [agent] [task_id] [phase]"
echo "  memory-query.sh [project] [agent] [type] [limit]"
echo "  memory-search.sh <query> [project] [type] [limit]"