#!/bin/bash
# =============================================================================
# CMX-CORE — Plugin System
# v2.2.0
#
# Sistema de plugins extensible para agregar AI providers, agentes y hooks
# sin modificar el core.
#
# Uso:
#   source lib/plugins.sh
#   plugins_init "$PROJECT_ROOT"
#   plugins_load_all                    # Carga todos los plugins registrados
#   plugins_register "mi-plugin" "path/to/plugin.sh"
#   plugins_run_hook "pre_task" "$task" # Ejecuta hooks
#   plugins_list                        # Lista plugins activos
#
# Estructura de plugin:
#   - plugin.sh debe definir funciones con prefijo: plugin_<name>_<hook>()
#   - Hooks disponibles: pre_task, post_task, pre_phase, post_phase, on_error
# =============================================================================

PLUGINS_DIR=""
PLUGINS_REGISTRY=""
PLUGINS_LOADED=()
PLUGINS_HOOKS=("pre_task" "post_task" "pre_phase" "post_phase" "on_error" "on_ia_select" "on_cleanup")

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

plugins_init() {
    local project_root="${1:-.}"

    # Directorio de plugins
    PLUGINS_DIR="$project_root/plugins"
    PLUGINS_REGISTRY="$PLUGINS_DIR/registry.json"

    # Crear estructura si no existe
    if [ ! -d "$PLUGINS_DIR" ]; then
        mkdir -p "$PLUGINS_DIR" 2>/dev/null || true
    fi

    # Crear registry si no existe
    if [ ! -f "$PLUGINS_REGISTRY" ]; then
        echo '{"plugins":{}}' > "$PLUGINS_REGISTRY" 2>/dev/null || true
    fi
}

# ============================================================================
# REGISTRO DE PLUGINS
# ============================================================================

plugins_register() {
    local name="$1"
    local path="$2"
    local description="${3:-}"
    local enabled="${4:-true}"

    if [ -z "$name" ] || [ -z "$path" ]; then
        echo "ERROR: plugins_register requiere nombre y path" >&2
        return 1
    fi

    # Verificar que el archivo existe
    if [ ! -f "$path" ]; then
        echo "ERROR: Plugin file no encontrado: $path" >&2
        return 1
    fi

    # Registrar en JSON
    if [ -f "$PLUGINS_REGISTRY" ]; then
        local temp
        temp=$(mktemp)
        jq ".plugins.\"$name\" = {\"path\": \"$path\", \"description\": \"$description\", \"enabled\": $enabled, \"registered_at\": \"$(date -Iseconds)\"}" \
            "$PLUGINS_REGISTRY" > "$temp" 2>/dev/null && mv "$temp" "$PLUGINS_REGISTRY"
    fi
}

plugins_unregister() {
    local name="$1"

    if [ -f "$PLUGINS_REGISTRY" ]; then
        local temp
        temp=$(mktemp)
        jq "del(.plugins.\"$name\")" "$PLUGINS_REGISTRY" > "$temp" 2>/dev/null && mv "$temp" "$PLUGINS_REGISTRY"
    fi

    # Remover de loaded
    local new_loaded=()
    for p in "${PLUGINS_LOADED[@]}"; do
        if [ "$p" != "$name" ]; then
            new_loaded+=("$p")
        fi
    done
    PLUGINS_LOADED=("${new_loaded[@]}")
}

plugins_enable() {
    local name="$1"
    if [ -f "$PLUGINS_REGISTRY" ]; then
        local temp
        temp=$(mktemp)
        jq ".plugins.\"$name\".enabled = true" "$PLUGINS_REGISTRY" > "$temp" 2>/dev/null && mv "$temp" "$PLUGINS_REGISTRY"
    fi
}

plugins_disable() {
    local name="$1"
    if [ -f "$PLUGINS_REGISTRY" ]; then
        local temp
        temp=$(mktemp)
        jq ".plugins.\"$name\".enabled = false" "$PLUGINS_REGISTRY" > "$temp" 2>/dev/null && mv "$temp" "$PLUGINS_REGISTRY"
    fi
}

# ============================================================================
# CARGA DE PLUGINS
# ============================================================================

plugins_load() {
    local name="$1"

    # Verificar si ya está cargado
    for p in "${PLUGINS_LOADED[@]}"; do
        if [ "$p" = "$name" ]; then
            return 0  # Ya cargado
        fi
    done

    # Obtener path del registry
    local path
    path=$(jq -r ".plugins.\"$name\".path // empty" "$PLUGINS_REGISTRY" 2>/dev/null)
    local enabled
    enabled=$(jq -r ".plugins.\"$name\".enabled // true" "$PLUGINS_REGISTRY" 2>/dev/null)

    if [ "$enabled" != "true" ]; then
        return 0  # Plugin deshabilitado, skip
    fi

    if [ -z "$path" ] || [ ! -f "$path" ]; then
        echo "ERROR: Plugin '$name' no tiene path válido" >&2
        return 1
    fi

    # Cargar plugin
    source "$path" 2>/dev/null || {
        echo "ERROR: No se pudo cargar plugin '$name' desde $path" >&2
        return 1
    }

    PLUGINS_LOADED+=("$name")
    return 0
}

plugins_load_all() {
    if [ ! -f "$PLUGINS_REGISTRY" ]; then
        return 0
    fi

    local plugin_names
    plugin_names=$(jq -r '.plugins | keys[]' "$PLUGINS_REGISTRY" 2>/dev/null)

    for name in $plugin_names; do
        plugins_load "$name" 2>/dev/null || true
    done
}

# ============================================================================
# HOOKS
# ============================================================================

plugins_run_hook() {
    local hook_name="$1"
    shift
    local args="$*"

    # Verificar que el hook es válido
    local valid_hook=false
    for h in "${PLUGINS_HOOKS[@]}"; do
        if [ "$h" = "$hook_name" ]; then
            valid_hook=true
            break
        fi
    done

    if [ "$valid_hook" = false ]; then
        return 0  # Hook desconocido, no es error
    fi

    # Ejecutar hook en todos los plugins cargados
    for plugin_name in "${PLUGINS_LOADED[@]}"; do
        local hook_func="plugin_${plugin_name}_${hook_name}"
        if type "$hook_func" >/dev/null 2>&1; then
            "$hook_func" $args 2>/dev/null || true
        fi
    done
}

# ============================================================================
# LISTADO Y STATUS
# ============================================================================

plugins_list() {
    if [ ! -f "$PLUGINS_REGISTRY" ]; then
        echo "No hay plugins registrados."
        return 0
    fi

    echo "=== Plugins Registrados ==="
    jq -r '.plugins | to_entries[] | 
        "  \(.key): \(.value.enabled) | \(.value.description) | \(.value.path)"' \
        "$PLUGINS_REGISTRY" 2>/dev/null || echo "  (error leyendo registry)"

    echo ""
    echo "=== Plugins Cargados ==="
    if [ ${#PLUGINS_LOADED[@]} -eq 0 ]; then
        echo "  (ninguno)"
    else
        for p in "${PLUGINS_LOADED[@]}"; do
            echo "  ✓ $p"
        done
    fi
}

plugins_count() {
    if [ ! -f "$PLUGINS_REGISTRY" ]; then
        echo "0"
        return
    fi
    jq -r '.plugins | length' "$PLUGINS_REGISTRY" 2>/dev/null || echo "0"
}

plugins_loaded_count() {
    echo "${#PLUGINS_LOADED[@]}"
}
