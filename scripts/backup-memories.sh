#!/bin/bash
# Backup script for cmx-memories SQLite database
# Uso: backup-memories.sh [--keep N]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$PROJECT_ROOT/backups"
DB_FILE="$PROJECT_ROOT/memories.db"

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${BLUE}[BACKUP]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }

# Número de backups a mantener (default: 5)
KEEP="${1:-5}"
if [ "$1" = "--keep" ]; then
    KEEP="${2:-5}"
fi

# Crear directorio de backups
mkdir -p "$BACKUP_DIR"

# Nombre del backup con timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/memories_${TIMESTAMP}.db"

# Verificar que la base de datos existe
if [ ! -f "$DB_FILE" ]; then
    echo "Base de datos no encontrada: $DB_FILE"
    exit 1
fi

# Crear backup (copia simple + vacuum)
log "Creando backup: $BACKUP_FILE"
cp "$DB_FILE" "$BACKUP_FILE"

# Verificar integridad
if sqlite3 "$BACKUP_FILE" "PRAGMA integrity_check;" | grep -q "ok"; then
    log_ok "Backup verificado: integrity_check passed"
else
    echo "ADVERTENCIA: El backup puede tener problemas de integridad"
fi

# Comprimir backup
log "Comprimiendo backup..."
gzip "$BACKUP_FILE"
BACKUP_FILE="${BACKUP_FILE}.gz"
log_ok "Backup压缩完成: $BACKUP_FILE"

# Limpiar backups antiguos
log "Limpiando backups antiguos (manteniendo los últimos $KEEP)..."

# Contar backups existentes
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/memories_*.db.gz 2>/dev/null | wc -l)

if [ "$BACKUP_COUNT" -gt "$KEEP" ]; then
    EXCESS=$((BACKUP_COUNT - KEEP))
    ls -1t "$BACKUP_DIR"/memories_*.db.gz | tail -n "$EXCESS" | xargs -r rm
    log_ok "$EXCESSe backups antiguos eliminados"
fi

# Mostrar resumen
echo ""
log "Resumen de backups:"
echo "  Total backups: $(ls -1 "$BACKUP_DIR"/memories_*.db.gz 2>/dev/null | wc -l)"
echo "  Último backup: $(ls -1t "$BACKUP_DIR"/memories_*.db.gz 2>/dev/null | head -1)"
echo "  Directorio: $BACKUP_DIR"
echo ""
echo "Para restaurar un backup:"
echo "  gunzip < backup file> && cp <backup.db> memories.db"