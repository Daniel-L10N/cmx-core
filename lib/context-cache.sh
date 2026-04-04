#!/bin/bash
# =============================================================================
# CMX-CORE — Context Cache
# v2.2.0
#
# Cachea las capas base y proyecto del inyector de contexto para evitar
# re-leer archivos estáticos en cada ejecución del brain.
#
# Uso:
#   source lib/context-cache.sh
#   context_cache_init "$PROJECT_ROOT"
#   LAYER1=$(context_cache_get_layer1)      # Base (prompts/base.txt)
#   LAYER2=$(context_cache_get_layer2)      # Proyecto (CONTEXT.md + AGENT.md)
#   context_cache_invalidate               # Forzar re-cache
#
# El cache se invalida automáticamente si los archivos fuente cambian.
# =============================================================================

CONTEXT_CACHE_DIR=""
CONTEXT_CACHE_LAYER1_FILE=""
CONTEXT_CACHE_LAYER2_FILE=""
CONTEXT_CACHE_HASH_FILE=""
CONTEXT_CACHE_TTL=3600  # 1 hora por defecto
CONTEXT_CACHE_PROJECT_ROOT=""

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

context_cache_init() {
    local project_root="${1:-.}"
    local cache_dir="${2:-}"

    CONTEXT_CACHE_PROJECT_ROOT="$project_root"

    # Directorio de cache
    if [ -n "$cache_dir" ]; then
        CONTEXT_CACHE_DIR="$cache_dir"
    else
        CONTEXT_CACHE_DIR="$project_root/.context-cache"
    fi

    mkdir -p "$CONTEXT_CACHE_DIR" 2>/dev/null || true

    CONTEXT_CACHE_LAYER1_FILE="$CONTEXT_CACHE_DIR/layer1.cache"
    CONTEXT_CACHE_LAYER2_FILE="$CONTEXT_CACHE_DIR/layer2.cache"
    CONTEXT_CACHE_HASH_FILE="$CONTEXT_CACHE_DIR/hashes.cache"
}

# ============================================================================
# HASH DE ARCHIVOS (para detectar cambios)
# ============================================================================

_context_cache_file_hash() {
    local file="$1"
    if [ -f "$file" ]; then
        # Usar md5sum si disponible, sino sha256sum, sino wc -c
        if command -v md5sum >/dev/null 2>&1; then
            md5sum "$file" 2>/dev/null | awk '{print $1}'
        elif command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$file" 2>/dev/null | awk '{print $1}'
        else
            # Fallback: tamaño + mtime
            stat -c '%s-%Y' "$file" 2>/dev/null || echo "unknown"
        fi
    else
        echo "missing"
    fi
}

_context_cache_check_stale() {
    local layer="$1"
    local hash_file="$CONTEXT_CACHE_HASH_FILE"

    if [ ! -f "$hash_file" ]; then
        return 0  # No hay hash, stale
    fi

    local cached_hash
    cached_hash=$(grep "^${layer}:" "$hash_file" 2>/dev/null | cut -d: -f2)

    # Determinar archivos de la capa
    local files=""
    case "$layer" in
        layer1)
            files="$CONTEXT_CACHE_PROJECT_ROOT/config/prompts/base.txt"
            ;;
        layer2)
            files="$CONTEXT_CACHE_PROJECT_ROOT/CONTEXT.md $CONTEXT_CACHE_PROJECT_ROOT/AGENT.md"
            ;;
    esac

    # Calcular hash combinado
    local current_hash=""
    for f in $files; do
        current_hash="${current_hash}$(_context_cache_file_hash "$f")"
    done

    if [ "$current_hash" != "$cached_hash" ]; then
        return 0  # Stale
    fi

    # Verificar TTL
    if [ -f "${CONTEXT_CACHE_DIR}/${layer}.cache" ]; then
        local cache_mtime
        cache_mtime=$(stat -c '%Y' "${CONTEXT_CACHE_DIR}/${layer}.cache" 2>/dev/null || echo "0")
        local now
        now=$(date +%s)
        local age=$((now - cache_mtime))

        if [ "$age" -gt "$CONTEXT_CACHE_TTL" ]; then
            return 0  # TTL expired
        fi
    fi

    return 1  # Not stale
}

# ============================================================================
# CAPA 1: BASE (prompts/base.txt)
# ============================================================================

context_cache_get_layer1() {
    local base_file="$CONTEXT_CACHE_PROJECT_ROOT/config/prompts/base.txt"

    # Verificar si el cache está stale
    if _context_cache_check_stale "layer1"; then
        # Rebuild cache
        if [ -f "$base_file" ]; then
            cat "$base_file" > "$CONTEXT_CACHE_LAYER1_FILE" 2>/dev/null || true
        else
            echo "# Sistema Base\nEres cmx-core." > "$CONTEXT_CACHE_LAYER1_FILE"
        fi

        # Actualizar hash
        local hash
        hash=$(_context_cache_file_hash "$base_file")
        mkdir -p "$CONTEXT_CACHE_DIR"
        echo "layer1:$hash" > "$CONTEXT_CACHE_HASH_FILE"
    fi

    if [ -f "$CONTEXT_CACHE_LAYER1_FILE" ]; then
        cat "$CONTEXT_CACHE_LAYER1_FILE"
    else
        echo "# Sistema Base\nEres cmx-core."
    fi
}

# ============================================================================
# CAPA 2: PROYECTO (CONTEXT.md + AGENT.md)
# ============================================================================

context_cache_get_layer2() {
    local context_file="$CONTEXT_CACHE_PROJECT_ROOT/CONTEXT.md"
    local agent_file="$CONTEXT_CACHE_PROJECT_ROOT/AGENT.md"

    # Verificar si el cache está stale
    if _context_cache_check_stale "layer2"; then
        # Rebuild cache
        local content=""
        if [ -f "$context_file" ]; then
            content=$(cat "$context_file")
        fi
        if [ -f "$agent_file" ]; then
            if [ -n "$content" ]; then
                content="$content

---

$(cat "$agent_file")"
            else
                content=$(cat "$agent_file")
            fi
        fi

        if [ -z "$content" ]; then
            content="# Proyecto\nSin contexto específico."
        fi

        echo "$content" > "$CONTEXT_CACHE_LAYER2_FILE" 2>/dev/null || true

        # Actualizar hash combinado
        local hash
        hash="$(_context_cache_file_hash "$context_file")$(_context_cache_file_hash "$agent_file")"
        mkdir -p "$CONTEXT_CACHE_DIR"
        echo "layer2:$hash" >> "$CONTEXT_CACHE_HASH_FILE"
    fi

    if [ -f "$CONTEXT_CACHE_LAYER2_FILE" ]; then
        cat "$CONTEXT_CACHE_LAYER2_FILE"
    else
        echo "# Proyecto\nSin contexto específico."
    fi
}

# ============================================================================
# INVALIDACIÓN
# ============================================================================

context_cache_invalidate() {
    rm -f "$CONTEXT_CACHE_LAYER1_FILE" "$CONTEXT_CACHE_LAYER2_FILE" "$CONTEXT_CACHE_HASH_FILE" 2>/dev/null || true
}

context_cache_invalidate_layer() {
    local layer="$1"
    case "$layer" in
        layer1|base)
            rm -f "$CONTEXT_CACHE_LAYER1_FILE" 2>/dev/null || true
            # Remover hash de layer1
            if [ -f "$CONTEXT_CACHE_HASH_FILE" ]; then
                grep -v "^layer1:" "$CONTEXT_CACHE_HASH_FILE" > "${CONTEXT_CACHE_HASH_FILE}.tmp" 2>/dev/null || true
                mv "${CONTEXT_CACHE_HASH_FILE}.tmp" "$CONTEXT_CACHE_HASH_FILE" 2>/dev/null || true
            fi
            ;;
        layer2|project)
            rm -f "$CONTEXT_CACHE_LAYER2_FILE" 2>/dev/null || true
            if [ -f "$CONTEXT_CACHE_HASH_FILE" ]; then
                grep -v "^layer2:" "$CONTEXT_CACHE_HASH_FILE" > "${CONTEXT_CACHE_HASH_FILE}.tmp" 2>/dev/null || true
                mv "${CONTEXT_CACHE_HASH_FILE}.tmp" "$CONTEXT_CACHE_HASH_FILE" 2>/dev/null || true
            fi
            ;;
        *)
            context_cache_invalidate
            ;;
    esac
}

# ============================================================================
# STATS
# ============================================================================

context_cache_stats() {
    echo "=== Context Cache Stats ==="
    echo "  Directory: $CONTEXT_CACHE_DIR"
    echo "  TTL: ${CONTEXT_CACHE_TTL}s"

    for layer in layer1 layer2; do
        local cache_file="$CONTEXT_CACHE_DIR/${layer}.cache"
        if [ -f "$cache_file" ]; then
            local size
            size=$(stat -c '%s' "$cache_file" 2>/dev/null || echo "0")
            local mtime
            mtime=$(stat -c '%Y' "$cache_file" 2>/dev/null || echo "0")
            local now
            now=$(date +%s)
            local age=$((now - mtime))
            echo "  $layer: ${size} bytes, ${age}s old"
        else
            echo "  $layer: not cached"
        fi
    done
}
