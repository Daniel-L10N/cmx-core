#!/bin/bash
# =============================================================================
# CMX-CORE — File Locking for State Management
# v2.2.0
#
# Previene race conditions cuando múltiples procesos actualizan el mismo
# archivo de estado JSON simultáneamente.
#
# Uso:
#   source lib/state-lock.sh
#   state_lock_init "/path/to/state.json"
#   state_lock_update "change_name" '"mi-feature"'
#   state_lock_read "change_name"
#   state_lock_unlock
#
# Funciones exportadas:
#   state_lock_init <state_file>           — Inicializa el lock
#   state_lock_update <key> <value>        — Actualiza con lock
#   state_lock_read <key>                  — Lee con lock
#   state_lock_add_phase <phase>           — Agrega fase completada
#   state_lock_is_phase_done <phase>       — Check si fase está completa
#   state_lock_unlock                       — Libera el lock
# =============================================================================

STATE_LOCK_FILE=""
STATE_LOCK_FD=""
STATE_LOCK_PATH=""
STATE_LOCK_AVAILABLE=false

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

state_lock_init() {
    local state_file="$1"

    if [ -z "$state_file" ]; then
        echo "ERROR: state_lock_init requiere path del archivo de estado" >&2
        return 1
    fi

    STATE_LOCK_PATH="$state_file"

    # Crear archivo si no existe
    if [ ! -f "$state_file" ]; then
        mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
        cat > "$state_file" << 'EOF'
{
  "pipeline": "SDD",
  "version": "2.2.0",
  "change_name": null,
  "phases_completed": [],
  "approved_gates": {},
  "artifacts": {},
  "started_at": null,
  "current_phase": null
}
EOF
    fi

    # Verificar si flock está disponible
    if command -v flock >/dev/null 2>&1; then
        STATE_LOCK_AVAILABLE=true
    else
        STATE_LOCK_AVAILABLE=false
        # Fallback: usar mkdir como lock (atomic en POSIX)
        STATE_LOCK_DIR="${state_file}.lock"
    fi
}

# ============================================================================
# LOCK/UNLOCK
# ============================================================================

# Adquirir lock (uso interno)
_state_lock_acquire() {
    if [ "$STATE_LOCK_AVAILABLE" = true ]; then
        # Usar flock
        exec {STATE_LOCK_FD}>"${STATE_LOCK_PATH}.lock"
        flock -w 10 "$STATE_LOCK_FD" || {
            echo "ERROR: No se pudo adquirir lock en $STATE_LOCK_PATH" >&2
            return 1
        }
    else
        # Fallback: mkdir como lock atómico
        local max_attempts=20
        local attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if mkdir "$STATE_LOCK_DIR" 2>/dev/null; then
                return 0
            fi
            attempt=$((attempt + 1))
            sleep 0.1
        done
        echo "ERROR: Timeout esperando lock (mkdir fallback)" >&2
        return 1
    fi
}

# Liberar lock (uso interno)
_state_lock_release() {
    if [ "$STATE_LOCK_AVAILABLE" = true ]; then
        if [ -n "$STATE_LOCK_FD" ]; then
            flock -u "$STATE_LOCK_FD" 2>/dev/null || true
            exec {STATE_LOCK_FD}>&- 2>/dev/null || true
            STATE_LOCK_FD=""
        fi
    else
        # Fallback: remover directorio de lock
        rmdir "$STATE_LOCK_DIR" 2>/dev/null || true
    fi
}

# ============================================================================
# OPERACIONES ATÓMICAS
# ============================================================================

state_lock_update() {
    local key="$1"
    local value="$2"

    _state_lock_acquire || return 1

    local temp
    temp=$(mktemp)

    if [ "$value" == "null" ] || [ "$value" == "{}" ] || [ "$value" == "[]" ]; then
        jq ".$key = $value" "$STATE_LOCK_PATH" > "$temp" 2>/dev/null
    elif [[ "$value" =~ ^\[.*\]$ ]] || [[ "$value" =~ ^\{.*\}$ ]]; then
        jq ".$key = $value" "$STATE_LOCK_PATH" > "$temp" 2>/dev/null
    elif [[ "$value" =~ ^[0-9]+$ ]]; then
        jq ".$key = $value" "$STATE_LOCK_PATH" > "$temp" 2>/dev/null
    elif [ "$value" = "true" ] || [ "$value" = "false" ]; then
        jq ".$key = $value" "$STATE_LOCK_PATH" > "$temp" 2>/dev/null
    else
        jq ".$key = \"$value\"" "$STATE_LOCK_PATH" > "$temp" 2>/dev/null
    fi

    local jq_exit=$?
    if [ $jq_exit -eq 0 ] && [ -s "$temp" ]; then
        mv "$temp" "$STATE_LOCK_PATH"
    else
        rm -f "$temp"
        echo "ERROR: jq falló al actualizar $key" >&2
        _state_lock_release
        return 1
    fi

    _state_lock_release
    return 0
}

state_lock_read() {
    local key="$1"

    _state_lock_acquire || return 1

    local value
    value=$(jq -r ".$key // empty" "$STATE_LOCK_PATH" 2>/dev/null)

    _state_lock_release
    echo "$value"
}

state_lock_add_phase() {
    local phase="$1"

    _state_lock_acquire || return 1

    local temp
    temp=$(mktemp)
    jq ".phases_completed += [\"$phase\"] | .phases_completed |= unique" \
        "$STATE_LOCK_PATH" > "$temp" 2>/dev/null && mv "$temp" "$STATE_LOCK_PATH"

    local jq_exit=$?
    _state_lock_release
    return $jq_exit
}

state_lock_is_phase_done() {
    local phase="$1"

    _state_lock_acquire || return 1

    local result
    result=$(jq -e ".phases_completed | index(\"$phase\") != null" "$STATE_LOCK_PATH" 2>/dev/null)
    local exit_code=$?

    _state_lock_release

    if [ $exit_code -eq 0 ]; then
        return 0  # Phase is done
    else
        return 1  # Phase is not done
    fi
}

state_lock_set_current_phase() {
    local phase="$1"
    state_lock_update "current_phase" "$phase"
}

state_lock_set_change_name() {
    local name="$1"
    state_lock_update "change_name" "$name"
}

state_lock_mark_gate_approved() {
    local gate="$1"
    local temp
    temp=$(mktemp)

    _state_lock_acquire || return 1

    jq ".approved_gates.\"$gate\" = true" "$STATE_LOCK_PATH" > "$temp" 2>/dev/null && \
        mv "$temp" "$STATE_LOCK_PATH"

    local exit_code=$?
    _state_lock_release
    return $exit_code
}

state_lock_is_gate_approved() {
    local gate="$1"

    _state_lock_acquire || return 1

    local result
    result=$(jq -r ".approved_gates.\"$gate\" // false" "$STATE_LOCK_PATH" 2>/dev/null)
    local exit_code=$?

    _state_lock_release

    if [ "$result" = "true" ]; then
        return 0
    else
        return 1
    fi
}

state_lock_unlock() {
    _state_lock_release
}

# ============================================================================
# AT EXIT — asegurar que el lock se libera
# ============================================================================

_state_lock_at_exit() {
    _state_lock_release
}

trap _state_lock_at_exit EXIT
