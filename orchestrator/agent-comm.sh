#!/bin/bash
# =============================================================================
# Agent Communication Script - SDD Phase 1
# Proporciona funciones para comunicación entre agentes
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuración
# -----------------------------------------------------------------------------
AGENT_COMM_DIR="${CMX_ROOT:-/home/cmx/cmx-core}/artifacts/agent-comm"
AGENT_LOGS_DIR="${CMX_ROOT:-/home/cmx/cmx-core}/artifacts/agent-logs"
SCHEMA_DIR="${CMX_ROOT:-/home/cmx/cmx-core}/schemas"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

timestamp_dir() {
    date -u +"%Y%m%d_%H%M%S"
}

ensure_dir() {
    local dir="$1"
    mkdir -p "$dir"
}

json_escape() {
    local str="$1"
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g'
}

# -----------------------------------------------------------------------------
# create_agent_comm
# Inicializa la estructura de directorios para un agente y change
# -----------------------------------------------------------------------------
create_agent_comm() {
    local agent="${1:-}"
    local change="${2:-}"

    if [[ -z "$agent" || -z "$change" ]]; then
        echo "ERROR: create_agent_comm requiere agent y change" >&2
        return 1
    fi

    # Estructura: artifacts/agent-comm/{change}/
    local comm_dir="$AGENT_COMM_DIR/$change"
    ensure_dir "$comm_dir"

    # Estructura: artifacts/agent-logs/{change}/{agent}/{timestamp}/
    local ts=$(timestamp_dir)
    local logs_dir="$AGENT_LOGS_DIR/$change/$agent/$ts"
    ensure_dir "$logs_dir"

    echo "Agent communication structure created:"
    echo "  - Comm: $comm_dir"
    echo "  - Logs: $logs_dir"

    # Exportar rutas para uso en funciones subsecuentes
    export AGENT_COMM_PATH="$comm_dir"
    export AGENT_LOGS_PATH="$logs_dir"

    return 0
}

# -----------------------------------------------------------------------------
# write_status
# Escribe el estado del agente en status.json
# -----------------------------------------------------------------------------
write_status() {
    local agent="${1:-}"
    local change="${2:-}"
    local status="${3:-running}"
    local exit_code="${4:-}"
    local summary="${5:-}"
    local output_path="${6:-}"

    if [[ -z "$agent" || -z "$change" ]]; then
        echo "ERROR: write_status requiere agent y change" >&2
        return 1
    fi

    local status_file="$AGENT_COMM_DIR/$change/${agent}_status.json"

    # Si el archivo no existe, inicializar con started_at
    if [[ ! -f "$status_file" ]]; then
        cat > "$status_file" <<EOF
{
  "agent": "$agent",
  "change": "$change",
  "status": "$status",
  "started_at": "$(timestamp)",
  "completed_at": null,
  "exit_code": null,
  "summary": null,
  "output_path": null
}
EOF
    else
        # Actualizar campos existentes
        local tmp_file=$(mktemp)
        jq --arg status "$status" \
           --arg completed_at "$( [ "$status" != "running" ] && timestamp || echo "null" )" \
           --arg exit_code "$([ -n "$exit_code" ] && echo "$exit_code" || echo "null")" \
           --arg summary "$([ -n "$summary" ] && echo "\"$(json_escape "$summary")\"" || echo "null")" \
           --arg output_path "$([ -n "$output_path" ] && echo "\"$output_path\"" || echo "null")" \
           '.status = $status | .completed_at = (if $completed_at != "null" then $completed_at else .completed_at end) | .exit_code = (if $exit_code != "null" then ($exit_code | tonumber) else .exit_code end) | .summary = (if $summary != "null" then $summary else .summary end) | .output_path = (if $output_path != "null" then $output_path else .output_path end)' \
           "$status_file" > "$tmp_file" && mv "$tmp_file" "$status_file"
    fi

    echo "Status written to: $status_file"
    cat "$status_file"
    return 0
}

# -----------------------------------------------------------------------------
# read_status
# Lee el estado de un agente desde status.json
# -----------------------------------------------------------------------------
read_status() {
    local agent="${1:-}"
    local change="${2:-}"

    if [[ -z "$agent" || -z "$change" ]]; then
        echo "ERROR: read_status requiere agent y change" >&2
        return 1
    fi

    local status_file="$AGENT_COMM_DIR/$change/${agent}_status.json"

    if [[ ! -f "$status_file" ]]; then
        echo "ERROR: Status file not found: $status_file" >&2
        return 1
    fi

    if [[ "${3:-}" == "--json" ]]; then
        cat "$status_file"
    else
        echo "=== Status: $agent ($change) ==="
        jq -r '
            "Status:    " + .status +
            "\nStarted:   " + .started_at +
            "\nCompleted: " + (.completed_at // "null") +
            "\nExit Code: " + (.exit_code | tostring) +
            "\nSummary:   " + (.summary // "null") +
            "\nOutput:    " + (.output_path // "null")
        ' "$status_file"
    fi

    return 0
}

# -----------------------------------------------------------------------------
# wait_for_status
# Espera a que un agente alcance un estado específico
# -----------------------------------------------------------------------------
wait_for_status() {
    local agent="${1:-}"
    local change="${2:-}"
    local target_status="${3:-completed}"
    local timeout="${4:-300}"
    local poll_interval="${5:-2}"

    if [[ -z "$agent" || -z "$change" ]]; then
        echo "ERROR: wait_for_status requiere agent, change y target_status" >&2
        return 1
    fi

    local status_file="$AGENT_COMM_DIR/$change/${agent}_status.json"
    local elapsed=0

    echo "Waiting for $agent to reach status: $target_status (timeout: ${timeout}s)"

    while [[ $elapsed -lt $timeout ]]; do
        if [[ ! -f "$status_file" ]]; then
            sleep "$poll_interval"
            elapsed=$((elapsed + poll_interval))
            continue
        fi

        local current_status=$(jq -r '.status' "$status_file" 2>/dev/null || echo "pending")

        if [[ "$current_status" == "$target_status" ]]; then
            echo "Agent $agent reached status: $target_status"
            return 0
        elif [[ "$current_status" == "failed" ]]; then
            echo "ERROR: Agent $agent failed while waiting" >&2
            return 1
        fi

        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
    done

    echo "ERROR: Timeout waiting for $agent to reach $target_status" >&2
    return 1
}

# -----------------------------------------------------------------------------
# log_output
# Guarda output del agente a un archivo de log
# -----------------------------------------------------------------------------
log_output() {
    local agent="${1:-}"
    local change="${2:-}"
    local output="${3:-}"

    if [[ -z "$agent" || -z "$change" ]]; then
        echo "ERROR: log_output requiere agent, change y output" >&2
        return 1
    fi

    local ts=$(timestamp_dir)
    local log_file="$AGENT_LOGS_DIR/$change/$agent/$ts/output.log"

    ensure_dir "$(dirname "$log_file")"
    echo "$output" >> "$log_file"

    echo "Output logged to: $log_file"
    return 0
}

# -----------------------------------------------------------------------------
# get_log_path
# Retorna la ruta del directorio de logs para un agente
# -----------------------------------------------------------------------------
get_log_path() {
    local agent="${1:-}"
    local change="${2:-}"

    if [[ -z "$agent" || -z "$change" ]]; then
        echo "ERROR: get_log_path requiere agent y change" >&2
        return 1
    fi

    local ts=$(timestamp_dir)
    echo "$AGENT_LOGS_DIR/$change/$agent/$ts"
}

# -----------------------------------------------------------------------------
# Main - Mostrar ayuda si no hay argumentos
# -----------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
    echo "Agent Communication Script - SDD Phase 1"
    echo ""
    echo "Usage:"
    echo "  source agent-comm.sh                    # Cargar funciones"
    echo "  create_agent_comm <agent> <change>      # Inicializar estructura"
    echo "  write_status <agent> <change> <status> [exit_code] [summary] [output_path]"
    echo "  read_status <agent> <change> [--json]  # Ver estado"
    echo "  wait_for_status <agent> <change> <target_status> [timeout] [poll_interval]"
    echo "  log_output <agent> <change> <output>   # Guardar output"
    echo "  get_log_path <agent> <change>           # Ver ruta de logs"
    echo ""
    echo "Examples:"
    echo "  create_agent_comm implementer my-change"
    echo "  write_status implementer my-change completed 0 \"All tasks done\""
    echo "  read_status implementer my-change"
    echo "  wait_for_status implementer my-change completed 60 5"
fi
