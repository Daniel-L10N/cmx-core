#!/bin/bash
# Restore script for cmx-memories SQLite database
# Uso: restore-memories.sh <backup-file>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DB_FILE="$PROJECT_ROOT/memories.db"
BACKUP_DIR="$PROJECT_ROOT/backups"

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[RESTORE]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

BACKUP_FILE="${1:-}"

if [ -z "$BACKUP_FILE" ]; then
    echo "Uso: $0 <archivo-backup>"
    echo ""
    echo "Backups disponibles:"
    ls -1t "$BACKUP_DIR"/memories_*.db.gz 2>/dev/null | head -10 || echo "  No hay backups"
    exit 1
fi

# Verificar que el archivo existe
if [ ! -f "$BACKUP_FILE" ]; then
    log_error "Backup no encontrado: $BACKUP_FILE"
    exit 1
fi

# Crear backup del estado actual antes de restaurar
if [ -f "$DB_FILE" ]; then
    log "Creando backup de seguridad del estado actual..."
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp "$DB_FILE" "$BACKUP_DIR/memories_pre_restore_${TIMESTAMP}.db"
    log_ok "Backup de seguridad creado"
fi

# Descomprimir si es .gz
if [[ "$BACKUP_FILE" == *.gz ]]; then
    TEMP_DB=$(mktemp)
    gunzip -c "$BACKUP_FILE" > "$TEMP_DB"
    TEMP_DB_CPY="$TEMP_DB"
else
    TEMP_DB_CPY="$BACKUP_FILE"
fi

# Verificar integridad antes de restaurar
log "Verificando integridad del backup..."
if sqlite3 "$TEMP_DB_CPY" "PRAGMA integrity_check;" | grep -q "ok"; then
    log_ok "Backup verificado"
else
    log_error "El backup tiene problemas de integridad"
    rm -f "$TEMP_DB"
    exit 1
fi

# Restaurar
log "Restaurando base de datos..."
cp "$TEMP_DB_CPY" "$DB_FILE"

# Limpiar temp
rm -f "$TEMP_DB"

# Verificar que la restauración fue exitosa
if [ -f "$DB_FILE" ]; then
    log_ok "Base de datos restaurada: $DB_FILE"
    
    # Verificar FTS5
    FTS_COUNT=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM memories_fts;" 2>/dev/null || echo "0")
    log "Índices FTS5: $FTS_COUNT"
    
    echo ""
    log_ok "Restauración completada exitosamente"
else
    log_error "Error al restaurar la base de datos"
    exit 1
fi