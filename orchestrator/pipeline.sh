#!/bin/bash
# DAG Engine — Ejecutor Dinámico de Pipeline SDD
# Lee pipeline.yaml y ejecuta el DAG definido

set -e

WORKSPACE="${WORKSPACE:-/home/cmx/cmx-core}"
DAG_FILE="${DAG_FILE:-$WORKSPACE/dag/pipeline.yaml}"
STATE_FILE="$WORKSPACE/orchestrator/state.json"
LOG_DIR="$WORKSPACE/orchestrator/logs"

# =============================================================================
# PHASE 2: AGENT COMMUNICATION - Configuración
# =============================================================================

# Cargar funciones de comunicación de agentes
AGENT_COMM_SCRIPT="$WORKSPACE/orchestrator/agent-comm.sh"
if [ -f "$AGENT_COMM_SCRIPT" ]; then
    source "$AGENT_COMM_SCRIPT"
fi

# =============================================================================
# STATE LOCKING (v2.2.0 — Previene race conditions en estado compartido)
# =============================================================================
STATE_LOCK_LIB="$WORKSPACE/lib/state-lock.sh"
if [ -f "$STATE_LOCK_LIB" ]; then
    source "$STATE_LOCK_LIB"
    PIPELINE_STATE_LOCK_ENABLED=true
else
    PIPELINE_STATE_LOCK_ENABLED=false
fi

# Timeout por defecto para agentes (en minutos)
AGENT_TIMEOUT_MINUTES="${AGENT_TIMEOUT_MINUTES:-30}"

# Directorio de comunicación entre agentes
AGENT_COMM_DIR="$WORKSPACE/artifacts/agent-comm"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# UTILIDADES
# =============================================================================

log() { echo -e "${BLUE}[DAG]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_phase() { echo -e "${CYAN}[PHASE]${NC} $1"; }

# =============================================================================
# INICIALIZACIÓN
# =============================================================================

init() {
    mkdir -p "$LOG_DIR"
    mkdir -p "$WORKSPACE/artifacts"/{exploration,proposals,specs,designs,tasks,implementation,progress,verification,archive}
    
    if [ ! -f "$STATE_FILE" ]; then
        cat > "$STATE_FILE" << 'EOF'
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

    # Inicializar state locking si está disponible
    if [ "$PIPELINE_STATE_LOCK_ENABLED" = true ]; then
        state_lock_init "$STATE_FILE" 2>/dev/null || true
    fi
}

# =============================================================================
# ESTADO (persistente en JSON con file locking — v2.2.0)
# =============================================================================

get_state() { cat "$STATE_FILE"; }

update_state() {
    local key="$1"
    local value="$2"

    # Usar state_lock si está disponible
    if [ "$PIPELINE_STATE_LOCK_ENABLED" = true ] && type state_lock_update >/dev/null 2>&1; then
        state_lock_update "$key" "$value" 2>/dev/null && return 0
        # Fallback si el lock falla
    fi

    # Fallback: método original sin lock
    local temp=$(mktemp)
    if [ "$value" == "null" ] || [ "$value" == "{}" ] || [ "$value" == "[]" ]; then
        jq ".$key = $value" "$STATE_FILE" > "$temp" && mv "$temp" "$STATE_FILE"
    elif [[ "$value" =~ ^\[.*\]$ ]] || [[ "$value" =~ ^\{.*\}$ ]]; then
        jq ".$key = $value" "$STATE_FILE" > "$temp" && mv "$temp" "$STATE_FILE"
    elif [[ "$value" =~ ^[0-9]+$ ]]; then
        jq ".$key = $value" "$STATE_FILE" > "$temp" && mv "$temp" "$STATE_FILE"
    elif [ "$value" = "true" ] || [ "$value" = "false" ]; then
        jq ".$key = $value" "$STATE_FILE" > "$temp" && mv "$temp" "$STATE_FILE"
    else
        jq ".$key = \"$value\"" "$STATE_FILE" > "$temp" && mv "$temp" "$STATE_FILE"
    fi
}

add_completed_phase() {
    local phase="$1"

    if [ "$PIPELINE_STATE_LOCK_ENABLED" = true ] && type state_lock_add_phase >/dev/null 2>&1; then
        state_lock_add_phase "$phase" 2>/dev/null && return 0
    fi

    local temp=$(mktemp)
    jq ".phases_completed += [\"$phase\"] | .phases_completed |= unique" "$STATE_FILE" > "$temp" && mv "$temp" "$STATE_FILE"
}

is_phase_completed() {
    local phase="$1"

    if [ "$PIPELINE_STATE_LOCK_ENABLED" = true ] && type state_lock_is_phase_done >/dev/null 2>&1; then
        state_lock_is_phase_done "$phase" 2>/dev/null && return 0
        return 1
    fi

    jq -e ".phases_completed | index(\"$phase\") != null" "$STATE_FILE" > /dev/null 2>&1
}

mark_phase_started() {
    local phase="$1"
    update_state "current_phase" "$phase"
}

# =============================================================================
# PARSEO DEL DAG (lee pipeline.yaml dinámicamente)
# =============================================================================

YQ="/home/cmx/bin/yq"
get_phase_ids() {
    $YQ eval '.phases | keys | .[]' "$DAG_FILE" 2>/dev/null || $YQ eval '.phases | keys' "$DAG_FILE" 2>/dev/null
}

get_phase_config() {
    local phase="$1"
    $YQ eval ".phases.$phase" "$DAG_FILE" 2>/dev/null
}

get_phase_script() {
    local phase="$1"
    $YQ eval ".phases.$phase.script" "$DAG_FILE" | grep -v "null" || true
}

get_phase_agent() {
    local phase="$1"
    $YQ eval ".phases.$phase.agent" "$DAG_FILE" | grep -v "null" || true
}

get_phase_dependencies() {
    local phase="$1"
    $YQ eval ".phases.$phase.dependencies[].phase" "$DAG_FILE" | grep -v "null" || true
}

get_phase_requires_approval() {
    local phase="$1"
    $YQ eval ".phases.$phase.execution.requires_approval" "$DAG_FILE" | grep -v "null" || echo "false"
}

get_phase_approval_gate() {
    local phase="$1"
    $YQ eval ".phases.$phase.execution.approval_gate" "$DAG_FILE" | grep -v "null" || true
}

get_phase_output_file() {
    local phase="$1"
    local change="$2"
    $YQ eval ".phases.$phase.output.artifacts[0].file" "$DAG_FILE" | grep -v "null" | sed "s/{CHANGE_NAME}/$change/g" || true
}

get_phase_mode() {
    local phase="$1"
    $YQ eval ".phases.$phase.execution.mode" "$DAG_FILE" | grep -v "null" || echo "sequential"
}

get_phase_parallel_with() {
    local phase="$1"
    $YQ eval ".phases.$phase.parallel_with[]" "$DAG_FILE" | grep -v "null" || true
}

get_pipeline_flow() {
    $YQ eval '.pipeline.flow' "$DAG_FILE" 2>/dev/null
}

# =============================================================================
# VALIDACIÓN DE CONTRATOS (schema validation real)
# =============================================================================

validate_phase_output() {
    local phase="$1"
    local change="$2"
    
    local schema_name=""
    local output_file=""
    
    case "$phase" in
        explore)
            schema_name="explore"; 
            output_file="$WORKSPACE/artifacts/exploration/${change}.md"
            ;;
        propose)
            schema_name="proposal"
            output_file="$WORKSPACE/artifacts/proposals/${change}.md"
            ;;
        spec)
            schema_name="spec"
            output_file="$WORKSPACE/artifacts/specs/${change}.md"
            ;;
        design)
            schema_name="design"
            output_file="$WORKSPACE/artifacts/designs/${change}.md"
            ;;
        tasks)
            schema_name="tasks"
            output_file="$WORKSPACE/artifacts/tasks/${change}.md"
            ;;
        apply)
            schema_name="apply"
            output_file="$WORKSPACE/artifacts/implementation/${change}-batch-1.md"
            ;;
        verify)
            schema_name="verify"
            output_file="$WORKSPACE/artifacts/verification/${change}.md"
            ;;
        archive)
            schema_name="archive"
            output_file="$WORKSPACE/artifacts/archive/${change}-$(date +%Y%m%d).md"
            ;;
    esac
    
    local schema_file="$WORKSPACE/schemas/${schema_name}.schema.json"
    
    if [ ! -f "$schema_file" ]; then
        log_warn "Schema no encontrado: $schema_file"
        return 0
    fi
    
    if [ ! -f "$output_file" ]; then
        log_error "Output no encontrado: $output_file"
        return 1
    fi
    
    # Validación con ajv si está disponible, si no jq básico
    if command -v ajv &> /dev/null; then
        if ajv validate -s "$schema_file" -d "$output_file" --all-errors 2>/dev/null; then
            log_ok "Schema validation OK: $phase"
            return 0
        else
            log_error "Schema validation FAILED: $phase"
            return 1
        fi
    else
        # Fallback: validación básica con jq
        local required=$(jq -r '.required[]?' "$schema_file" 2>/dev/null || echo "")
        if [ -z "$required" ]; then
            return 0
        fi
        
        local missing=""
        while IFS= read -r field; do
            [ -z "$field" ] && continue
            if ! jq -e "has(\"$field\")" "$output_file" > /dev/null 2>&1; then
                missing="$missing $field"
            fi
        done <<< "$required"
        
        if [ -n "$missing" ]; then
            log_warn "Campos faltantes:$missing"
        else
            log_ok "Validación básica OK: $phase"
        fi
        return 0
    fi
}

# =============================================================================
# HITL REAL (bloquea hasta aprobación)
# =============================================================================

require_approval() {
    local gate="$1"
    local phase="$2"
    local artifact="$3"
    
    log_warn "🔒 APPROVAL GATE: $gate"
    echo ""
    
    # Obtener change_name del estado
    local change=$(jq -r '.change_name // empty' "$STATE_FILE" 2>/dev/null || echo "")
    
    # Intentar obtener resumen de summary.sh, fallback a head -10 del artifact
    if [ -n "$change" ]; then
        local summary_output
        summary_output=$("$WORKSPACE/orchestrator/summary.sh" hitl "$change" 2>/dev/null || echo "")
        if [ -n "$summary_output" ]; then
            echo "$summary_output"
        else
            # Fallback: usar head -10 del artifact
            if [ -f "$artifact" ]; then
                echo "=== RESUMEN (fallback: artifact) ==="
                head -10 "$artifact"
                echo ""
            fi
        fi
    else
        # Fallback: sin change_name, usar head -10 del artifact
        if [ -f "$artifact" ]; then
            echo "=== ARTIFACT ($artifact) ==="
            head -10 "$artifact"
            echo ""
        fi
    fi
    
    echo "================================"
    echo ""
    
    # Check approval gate con locking si disponible
    local approved="false"
    if [ "$PIPELINE_STATE_LOCK_ENABLED" = true ] && type state_lock_is_gate_approved >/dev/null 2>&1; then
        if state_lock_is_gate_approved "$gate" 2>/dev/null; then
            approved="true"
        fi
    else
        approved=$(jq -r ".approved_gates.\"$gate\" // false" "$STATE_FILE")
    fi
    
    if [ "$approved" == "true" ]; then
        log_ok "Gate ya aprobado: $gate"
        return 0
    fi
    
    while true; do
        echo -n "¿Aprobar para continuar? [y/n]: "
        read -r response < /dev/tty
        
        if [[ "$response" =~ ^[Yy]$ ]]; then
            if [ "$PIPELINE_STATE_LOCK_ENABLED" = true ] && type state_lock_mark_gate_approved >/dev/null 2>&1; then
                state_lock_mark_gate_approved "$gate" 2>/dev/null || {
                    local temp=$(mktemp)
                    jq ".approved_gates.\"$gate\" = true" "$STATE_FILE" > "$temp" && mv "$temp" "$STATE_FILE"
                }
            else
                local temp=$(mktemp)
                jq ".approved_gates.\"$gate\" = true" "$STATE_FILE" > "$temp" && mv "$temp" "$STATE_FILE"
            fi
            log_ok "APROBADO: $gate"
            return 0
        elif [[ "$response" =~ ^[Nn]$ ]]; then
            log_error "RECHAZADO: $gate - Pipeline detenido"
            return 1
        else
            echo "Respuesta inválida. Use y o n."
        fi
    done
}

# =============================================================================
# CHECK DEPENDENCIAS
# =============================================================================

check_dependencies() {
    local phase="$1"
    local deps=$(get_phase_dependencies "$phase")
    
    if [ -z "$deps" ]; then
        return 0
    fi
    
    while IFS= read -r dep; do
        [ -z "$dep" ] && continue
        if ! is_phase_completed "$dep"; then
            log_error "Dependencia no completada: $dep -> $phase"
            return 1
        fi
        log "  ✓ Dependencia satisfecha: $dep"
    done <<< "$deps"
    
    return 0
}

# =============================================================================
# PHASE 2: AGENT COMMUNICATION - Helper Functions
# =============================================================================

# Inicializa archivos de comunicación antes de ejecutar un agente
init_agent_comm() {
    local phase="$1"
    local change="$2"
    
    local comm_dir="$AGENT_COMM_DIR/$change"
    mkdir -p "$comm_dir"
    
    # Determinar nombre del agente
    local agent_name="$phase"
    if [ -z "$agent_name" ]; then
        agent_name=$(get_phase_agent "$phase")
    fi
    
    # Inicializar estructura de comunicación
    if type create_agent_comm >/dev/null 2>&1; then
        create_agent_comm "$agent_name" "$change"
    fi
    
    # Escribir estado inicial "running" en status.json
    local status_file="$comm_dir/${agent_name}_status.json"
    cat > "$status_file" << EOF
{
  "agent": "$agent_name",
  "change": "$change",
  "status": "running",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "completed_at": null,
  "exit_code": null,
  "summary": null,
  "output_path": null
}
EOF
    
    log "Comm initialized: $status_file"
}

# Actualiza el estado del agente al finalizar
update_agent_status() {
    local phase="$1"
    local change="$2"
    local exit_code="$3"
    local summary="$4"
    
    local agent_name="$phase"
    if [ -z "$agent_name" ]; then
        agent_name=$(get_phase_agent "$phase")
    fi
    
    local status_file="$AGENT_COMM_DIR/$change/${agent_name}_status.json"
    
    if [ -f "$status_file" ]; then
        local status="completed"
        if [ "$exit_code" -ne 0 ]; then
            status="failed"
        fi
        
        local completed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        
        # Usar jq para actualizar el archivo de estado
        local tmp_file=$(mktemp)
        jq --arg status "$status" \
           --arg completed_at "$completed_at" \
           --arg exit_code "$exit_code" \
           --arg summary "$summary" \
           '.status = $status | .completed_at = $completed_at | .exit_code = ($exit_code | tonumber) | .summary = $summary' \
           "$status_file" > "$tmp_file" && mv "$tmp_file" "$status_file"
        
        log "Status updated: $status_file"
    fi
}

# Espera a que el agente termine usando polling de status.json
wait_agent_completion() {
    local phase="$1"
    local change="$2"
    local pid_file="$3"
    
    local agent_name="$phase"
    if [ -z "$agent_name" ]; then
        agent_name=$(get_phase_agent "$phase")
    fi
    
    local status_file="$AGENT_COMM_DIR/$change/${agent_name}_status.json"
    
    # Timeout configurable
    local timeout_min="${AGENT_TIMEOUT_MINUTES:-30}"
    local timeout_sec=$((timeout_min * 60))
    local poll_interval=5
    local elapsed=0
    
    log "Waiting for $agent_name to complete (timeout: ${timeout_min} min)"
    
    # Verificar si inotifywait está disponible
    local use_inotify=false
    if command -v inotifywait >/dev/null 2>&1; then
        use_inotify=true
    fi
    
    while true; do
        # Verificar si el proceso sigue corriendo
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file" 2>/dev/null)
            if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
                # Proceso terminó
                break
            fi
        fi
        
        # Verificar timeout
        if [ $elapsed -ge $timeout_sec ]; then
            log_error "Timeout: $agent_name (${timeout_min} min)"
            if [ -f "$pid_file" ]; then
                local pid=$(cat "$pid_file" 2>/dev/null)
                [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
            fi
            return 124  # Timeout exit code
        fi
        
        # Polling del status.json
        if [ -f "$status_file" ]; then
            local current_status=$(jq -r '.status' "$status_file" 2>/dev/null || echo "running")
            
            if [ "$current_status" == "completed" ] || [ "$current_status" == "failed" ]; then
                log "Agent $agent_name finished with status: $current_status"
                break
            fi
        fi
        
        # Usar inotifywait si está disponible (más eficiente)
        if [ "$use_inotify" == "true" ]; then
            inotifywait -t 2 -q -e close_write "$status_file" 2>/dev/null || true
        else
            sleep "$poll_interval"
            elapsed=$((elapsed + poll_interval))
        fi
        
        echo -ne "\r    Transcurrido: ${elapsed}s / ${timeout_sec}s "
    done
    
    echo ""
    return 0
}

# =============================================================================
# EJECUCIÓN DE FASE (aisla cada agente en subshell/proceso)
# =============================================================================

run_phase() {
    local phase="$1"
    local change="$2"
    local batch="${3:-1}"
    
    log_phase "=== EJECUTANDO: $phase (batch=$batch) ==="
    
    mark_phase_started "$phase"
    
    local script=$(get_phase_script "$phase")
    local agent=$(get_phase_agent "$phase")
    
    # Determinar nombre de agente
    local agent_name="${agent:-$phase}"
    
    if [ -z "$script" ] && [ -z "$agent" ]; then
        log_error "No hay script ni agent definido para: $phase"
        return 1
    fi
    
    if [ -n "$script" ]; then
        script="$WORKSPACE/$script"
        if [ ! -f "$script" ]; then
            log_error "Script no encontrado: $script"
            return 1
        fi
    fi
    
    # 2.4: Inicializar archivos de comunicación antes de ejecutar
    init_agent_comm "$phase" "$change"
    
    # Estructura de directorios para logs
    local ts=$(date -u +"%Y%m%d_%H%M%S")
    local log_dir="$WORKSPACE/artifacts/agent-logs/$change/$agent_name/$ts"
    mkdir -p "$log_dir"
    
    local stdout_log="$log_dir/stdout.log"
    local stderr_log="$log_dir/stderr.log"
    local pid_file="$AGENT_COMM_DIR/$change/${agent_name}.pid"
    
    # 2.1: Ejecución no-bloqueante con nohup + guardar PID
    log "Launching $agent_name in background (non-blocking)..."
    
    nohup bash -c "
        if [ -n \"$script\" ]; then
            exec \"$script\" \"$WORKSPACE\" \"$change\" \"$batch\"
        else
            exec \"$WORKSPACE/agents/${agent}.sh\" \"$WORKSPACE\" \"$change\" \"$batch\"
        fi
    " > "$stdout_log" 2>"$stderr_log" &
    
    local pid=$!
    echo "$pid" > "$pid_file"
    
    log "Agent $agent_name started with PID: $pid"
    log "Logs: stdout=$stdout_log, stderr=$stderr_log"
    log "PID file: $pid_file"
    
    # 2.2: Polling del status.json para detectar fin de agente
    # 2.3: Timeout configurable con AGENT_TIMEOUT_MINUTES
    if ! wait_agent_completion "$phase" "$change" "$pid_file"; then
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "Timeout: $phase exceeded ${AGENT_TIMEOUT_MINUTES} minutes"
        else
            log_error "Agent $phase failed"
        fi
        
        # Actualizar status a failed
        update_agent_status "$phase" "$change" 1 "Timeout or error"
        
        log "Logs: $stdout_log"
        tail -20 "$stdout_log" 2>/dev/null || true
        return 1
    fi
    
    # Obtener exit code del proceso
    wait "$pid" 2>/dev/null
    local exit_code=$?
    
    echo ""
    
    # Generar summary simple
    local summary=""
    if [ -f "$stdout_log" ]; then
        summary=$(head -5 "$stdout_log" 2>/dev/null | tr '\n' ' ' | cut -c1-200)
    fi
    
    # 2.4: Actualizar estado del agente al finalizar
    update_agent_status "$phase" "$change" "$exit_code" "$summary"
    
    if [ $exit_code -eq 0 ]; then
        log_ok "Fase completada: $phase"
        add_completed_phase "$phase"
        
        if validate_phase_output "$phase" "$change"; then
            log_ok "Contrato validado: $phase"
        else
            log_warn "Contrato inválido - revisar: $phase"
        fi
        return 0
    else
        log_error "Fase falló (exit=$exit_code): $phase"
        log "Logs: $stdout_log"
        tail -20 "$stdout_log" 2>/dev/null || true
        return 1
    fi
}

# =============================================================================
# PIPELINE DINÁMICO (ejecuta YAML, no hardcode)
# =============================================================================

run_pipeline() {
    local change="$1"
    local start_phase="${2:-explore}"
    
    if [ -z "$change" ]; then
        log_error "Uso: $0 run <change-name> [start-phase]"
        return 1
    fi
    
    if [ ! -f "$DAG_FILE" ]; then
        log_error "DAG no encontrado: $DAG_FILE"
        return 1
    fi
    
    log "=== PIPELINE DINÁMICO ==="
    log "Change: $change"
    log "Start: $start_phase"
    log "DAG: $DAG_FILE"
    
    update_state "change_name" "$change"
    update_state "started_at" "$(date -Iseconds)"
    
    # Leer flujo del YAML
    local flow=$(get_pipeline_flow)
    local in_flow=false
    local parallel_queue=()
    
    while IFS= read -r item; do
        [ -z "$item" ] && continue
        
        # Detectar inicio
        if [ "$in_flow" == "false" ]; then
            if [ "$item" == "$start_phase" ] || [ "$item" == "  - $start_phase" ]; then
                in_flow=true
            fi
        fi
        
        # Skip hasta llegar al start
        if [ "$in_flow" == "false" ]; then
            continue
        fi
        
        # Parsear item
        local clean_item=$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Si es paralelo
        if [ "$clean_item" == "parallel:" ]; then
            parallel_queue=()
            continue
        fi
        
        # Si es un item dentro de paralelo
        if [[ "$clean_item" =~ ^- ]]; then
            local phase_name=$(echo "$clean_item" | sed 's/^-[[:space:]]*//')
            if [ -n "$phase_name" ]; then
                parallel_queue+=("$phase_name")
            fi
            continue
        fi
        
        # Ejecutar paralelo si hay queue
        if [ ${#parallel_queue[@]} -gt 0 ]; then
            run_parallel_phases "${parallel_queue[@]}" "$change"
            parallel_queue=()
        fi
        
        # Ejecutar fase individual
        if [ -n "$clean_item" ] && [ "$clean_item" != "parallel:" ]; then
            execute_phase "$clean_item" "$change"
        fi
        
    done <<< "$flow"
    
    # Ejecutar parallel final si quedó
    if [ ${#parallel_queue[@]} -gt 0 ]; then
        run_parallel_phases "${parallel_queue[@]}" "$change"
    fi
    
    log_ok "=== PIPELINE DINÁMICO COMPLETADO ==="
    status
}

run_parallel_phases() {
    local phases=("$@")
    
    log_phase "=== PARALELO: ${phases[*]} ==="
    
    local pids=()
    
    for phase in "${phases[@]}"; do
        (
            run_phase "$phase" "$change" 1
        ) &
        pids+=($!)
    done
    
    # Esperar todos
    local failed=0
    for pid in "${pids[@]}"; do
        wait "$pid" || failed=$((failed + 1))
    done
    
    if [ $failed -gt 0 ]; then
        log_error "$failed fases paralelas fallaron"
        return 1
    fi
    
    log_ok "Todas las fases paralelas completadas"
    return 0
}

execute_phase() {
    local phase="$1"
    local change="$2"
    
    log_phase "Procesando fase: $phase"
    
    # Check dependencias
    if ! check_dependencies "$phase"; then
        log_error "Dependencias no satisfechas para: $phase"
        return 1
    fi
    
    # Skip si ya completada
    if is_phase_completed "$phase"; then
        log_ok "Ya completada: $phase (skip)"
        return 0
    fi
    
    # Ejecutar fase
    if ! run_phase "$phase" "$change" 1; then
        return 1
    fi
    
    # Approval gate si requiere
    local requires_approval=$(get_phase_requires_approval "$phase")
    if [ "$requires_approval" == "true" ]; then
        local gate=$(get_phase_approval_gate "$phase")
        local output_file=$(get_phase_output_file "$phase" "$change")
        if ! require_approval "$gate" "$phase" "$output_file"; then
            log_error "Approval denegado: $gate"
            return 1
        fi
    fi
    
    return 0
}

# =============================================================================
# RESUME (continuar desde donde se detuvo)
# =============================================================================

resume_pipeline() {
    local change=$(jq -r '.change_name' "$STATE_FILE")
    local last_phase=$(jq -r '.current_phase' "$STATE_FILE")
    
    if [ -z "$change" ] || [ "$change" == "null" ]; then
        log_error "No hay pipeline activo para continuar"
        return 1
    fi
    
    log "=== RESUMIENDO PIPELINE ==="
    log "Change: $change"
    log "Última fase: $last_phase"
    
    # Encontrar siguiente fase
    local next_phase=""
    local found=false
    local flow=$(get_pipeline_flow)
    
    while IFS= read -r item; do
        [ -z "$item" ] && continue
        local clean=$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ "$clean" == "parallel:" ]; then
            continue
        fi
        
        if [[ "$clean" =~ ^- ]]; then
            continue
        fi
        
        if [ "$found" == "true" ]; then
            next_phase="$clean"
            break
        fi
        
        if [ "$clean" == "$last_phase" ]; then
            found=true
        fi
    done <<< "$flow"
    
    if [ -z "$next_phase" ]; then
        log_ok "Pipeline ya completado"
        return 0
    fi
    
    log "Continuando desde: $next_phase"
    run_pipeline "$change" "$next_phase"
}

# =============================================================================
# COMANDOS
# =============================================================================

status() {
    log "=== ESTADO DEL PIPELINE ==="
    cat "$STATE_FILE" | jq .
}

reset() {
    log "Reseteando estado..."
    rm -f "$STATE_FILE"
    init
    log_ok "Estado reseteado"
}

show_dag() {
    log "=== DAG DEFINIDO EN YAML ==="
    yq eval '.phases | keys | .[]' "$DAG_FILE" 2>/dev/null || cat "$DAG_FILE"
}

show_help() {
    cat << 'EOF'
DAG Engine v2 — Ejecutor Dinámico de Pipeline SDD
=================================================

Uso: pipeline.sh <comando> [opciones]

COMANDOS:
  run <change> [start-phase]    Ejecutar pipeline desde YAML
  resume                        Continuar pipeline detenido
  status                        Mostrar estado actual
  reset                         Resetear estado
  phase <name> [change]         Ejecutar fase específica
  dag                           Mostrar fases del DAG
  help                          Este mensaje

EJEMPLOS:
  ./pipeline.sh run mi-feature
  ./pipeline.sh run mi-feature propose
  ./pipeline.sh resume
  ./pipeline.sh phase explore test
EOF
}

# =============================================================================
# MAIN
# =============================================================================

COMMAND="${1:-help}"
shift 2>/dev/null || true

case "$COMMAND" in
    run)
        init
        run_pipeline "$1" "$2"
        ;;
    resume)
        init
        resume_pipeline
        ;;
    status)
        init
        status
        ;;
    init)
        init
        log_ok "Entorno inicializado correctamente"
        ;;
    reset)
        reset
        ;;
    phase)
        init
        PHASE="$1"; CHANGE="${2:-test}"
        run_phase "$PHASE" "$CHANGE"
        ;;
    dag)
        show_dag
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Comando: $COMMAND"
        show_help
        exit 1
        ;;
esac
