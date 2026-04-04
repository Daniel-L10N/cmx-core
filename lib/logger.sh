#!/bin/bash
# =============================================================================
# CMX-CORE — Centralized Logging Library
# v2.2.0
#
# Uso:
#   source lib/logger.sh
#   log_init "mi-componente"                    # Inicializa logger
#   log_info "Mensaje informativo"
#   log_warn "Advertencia"
#   log_error "Error crítico"
#   log_debug "Detalle de debugging"
#   log_metric "ia_used" "opencode" "3.5s"       # Métrica clave-valor
#   log_flush                                     # Fuerza escritura a disco
#
# Logs se escriben a:
#   - stdout (coloreado, interactivo)
#   - archivo: logs/cmx-{fecha}.log (JSON lines, parseable)
#   - archivo: logs/cmx-{fecha}.jsonl (métricas estructuradas)
# =============================================================================

# ============================================================================
# CONFIGURACIÓN GLOBAL
# ============================================================================

# Nivel de log: 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
CMX_LOG_LEVEL="${CMX_LOG_LEVEL:-1}"
CMX_LOG_DIR="${CMX_LOG_DIR:-}"
CMX_LOG_COMPONENT="${CMX_LOG_COMPONENT:-system}"
CMX_LOG_FILE=""
CMX_METRICS_FILE=""
CMX_LOG_BUFFER=()
CMX_LOG_BUFFER_MAX=50
CMX_LOG_INITIALIZED=false

# ============================================================================
# COLORES (solo si stdout es terminal)
# ============================================================================

if [ -t 1 ]; then
    _LOG_RED='\033[0;31m'
    _LOG_GREEN='\033[0;32m'
    _LOG_YELLOW='\033[1;33m'
    _LOG_BLUE='\033[0;34m'
    _LOG_CYAN='\033[0;36m'
    _LOG_MAGENTA='\033[0;35m'
    _LOG_DIM='\033[2m'
    _LOG_NC='\033[0m'
else
    _LOG_RED=''
    _LOG_GREEN=''
    _LOG_YELLOW=''
    _LOG_BLUE=''
    _LOG_CYAN=''
    _LOG_MAGENTA=''
    _LOG_DIM=''
    _LOG_NC=''
fi

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

log_init() {
    local component="${1:-system}"
    local log_dir="${2:-}"

    CMX_LOG_COMPONENT="$component"
    CMX_LOG_INITIALIZED=true

    # Determinar directorio de logs
    if [ -n "$log_dir" ]; then
        CMX_LOG_DIR="$log_dir"
    elif [ -z "$CMX_LOG_DIR" ]; then
        # Auto-detectar desde SCRIPT_DIR o PROJECT_ROOT
        local search_dir="${SCRIPT_DIR:-.}"
        if [ -d "$search_dir/logs" ]; then
            CMX_LOG_DIR="$search_dir/logs"
        elif [ -d "$search_dir/../logs" ]; then
            CMX_LOG_DIR="$search_dir/../logs"
        else
            CMX_LOG_DIR="$search_dir/logs"
        fi
    fi

    # Crear directorio si no existe
    mkdir -p "$CMX_LOG_DIR" 2>/dev/null || true

    # Archivos de log con fecha
    local date_stamp
    date_stamp=$(date +%Y%m%d)
    CMX_LOG_FILE="$CMX_LOG_DIR/cmx-${date_stamp}.log"
    CMX_METRICS_FILE="$CMX_LOG_DIR/cmx-metrics-${date_stamp}.jsonl"

    # Rotación: si el archivo existe y tiene más de 10MB, archivar
    _log_rotate_if_needed "$CMX_LOG_FILE"
    _log_rotate_if_needed "$CMX_METRICS_FILE"

    # Header del log
    _log_write_raw "=== CMX-CORE Logger Started ==="
    _log_write_raw "Component: $component"
    _log_write_raw "PID: $$"
    _log_write_raw "Timestamp: $(date -Iseconds)"
    _log_write_raw "Log Level: $CMX_LOG_LEVEL (0=DEBUG, 1=INFO, 2=WARN, 3=ERROR)"
    _log_write_raw "Log File: $CMX_LOG_FILE"
    _log_write_raw "================================"
}

# Rotar archivo si excede tamaño
_log_rotate_if_needed() {
    local file="$1"
    local max_bytes="${CMX_LOG_MAX_BYTES:-10485760}"  # 10MB default

    if [ -f "$file" ]; then
        local size
        size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        if [ "$size" -gt "$max_bytes" ]; then
            local backup="${file}.$(date +%H%M%S).bak"
            mv "$file" "$backup" 2>/dev/null || true
            gzip "$backup" 2>/dev/null || true
        fi
    fi
}

# ============================================================================
# FUNCIONES DE LOG PÚBLICAS
# ============================================================================

log_debug() {
    _log_emit 0 "DEBUG" "$_LOG_DIM" "$@"
}

log_info() {
    _log_emit 1 "INFO" "$_LOG_BLUE" "$@"
}

log_ok() {
    _log_emit 1 "OK" "$_LOG_GREEN" "$@"
}

log_warn() {
    _log_emit 2 "WARN" "$_LOG_YELLOW" "$@"
}

log_error() {
    _log_emit 3 "ERROR" "$_LOG_RED" "$@"
}

log_fatal() {
    _log_emit 3 "FATAL" "$_LOG_RED" "$@"
    log_flush
    exit 1
}

# ============================================================================
# MÉTRICAS
# ============================================================================

log_metric() {
    local key="$1"
    local value="$2"
    local unit="${3:-}"
    local component="${4:-$CMX_LOG_COMPONENT}"

    if [ ! "$CMX_LOG_INITIALIZED" = true ]; then
        log_init "system"
    fi

    local timestamp
    timestamp=$(date -Iseconds)

    # JSON line para métricas
    local metric_line
    metric_line=$(printf '{"timestamp":"%s","component":"%s","metric":"%s","value":"%s","unit":"%s","pid":%d}' \
        "$timestamp" "$component" "$key" "$value" "$unit" "$$")

    # Escribir a archivo de métricas
    if [ -n "$CMX_METRICS_FILE" ]; then
        echo "$metric_line" >> "$CMX_METRICS_FILE" 2>/dev/null || true
    fi

    # También al buffer
    CMX_LOG_BUFFER+=("METRIC $metric_line")
    _log_flush_if_full
}

# Registrar inicio de una operación (para medir duración)
log_metric_start() {
    local operation="$1"
    local epoch
    epoch=$(date +%s%N 2>/dev/null || date +%s000000000)

    # Guardar en variable de entorno para acceso posterior
    export "CMX_METRIC_START_${operation}=$epoch"

    log_metric "operation_start" "$operation" "event"
}

# Registrar fin de operación con duración calculada
log_metric_end() {
    local operation="$1"
    local status="${2:-success}"
    local details="${3:-}"

    local start_var="CMX_METRIC_START_${operation}"
    local start_epoch="${!start_var:-0}"

    if [ "$start_epoch" = "0" ]; then
        log_warn "No hay métrica de inicio para: $operation"
        return
    fi

    local end_epoch
    end_epoch=$(date +%s%N 2>/dev/null || date +%s000000000)

    # Calcular duración en milisegundos
    local duration_ns=$((end_epoch - start_epoch))
    local duration_ms=$((duration_ns / 1000000))
    local duration_s
    duration_s=$(awk "BEGIN {printf \"%.3f\", $duration_ns / 1000000000}")

    log_metric "operation_duration" "${duration_s}s" "seconds"
    log_metric "operation_duration_ms" "$duration_ms" "milliseconds"
    log_metric "operation_status" "$status" "event"

    if [ -n "$details" ]; then
        log_metric "operation_details" "$details" "string"
    fi

    # Limpiar variable
    unset "$start_var"
}

# ============================================================================
# FLUSH Y LIMPIEZA
# ============================================================================

log_flush() {
    if [ ${#CMX_LOG_BUFFER[@]} -gt 0 ]; then
        for entry in "${CMX_LOG_BUFFER[@]}"; do
            _log_write_raw "$entry"
        done
        CMX_LOG_BUFFER=()
    fi
}

_log_flush_if_full() {
    if [ ${#CMX_LOG_BUFFER[@]} -ge "$CMX_LOG_BUFFER_MAX" ]; then
        log_flush
    fi
}

# ============================================================================
# FUNCIONES INTERNAS
# ============================================================================

_log_emit() {
    local level_num="$1"
    local level_name="$2"
    local color="$3"
    shift 3
    local message="$*"

    # Verificar nivel
    if [ "$level_num" -lt "$CMX_LOG_LEVEL" ]; then
        return
    fi

    local timestamp
    timestamp=$(date +%H:%M:%S)

    # Output a stdout (coloreado)
    if [ -t 1 ]; then
        printf "${color}[%s]${_LOG_NC} ${color}[%-5s]${_LOG_NC} ${color}[%-12s]${_LOG_NC} %s\n" \
            "$timestamp" "$level_name" "$CMX_LOG_COMPONENT" "$message" >&2
    else
        printf "[%s] [%-5s] [%-12s] %s\n" \
            "$timestamp" "$level_name" "$CMX_LOG_COMPONENT" "$message" >&2
    fi

    # Output a archivo (JSON line)
    _log_write_json "$level_name" "$message"
}

_log_write_json() {
    local level="$1"
    local message="$2"

    if [ -z "$CMX_LOG_FILE" ]; then
        return
    fi

    # Escapar para JSON
    local escaped_message
    escaped_message=$(echo "$message" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | head -c 2000)

    local timestamp
    timestamp=$(date -Iseconds)

    # JSON line
    local json_line
    json_line=$(printf '{"ts":"%s","level":"%s","component":"%s","pid":%d,"msg":"%s"}' \
        "$timestamp" "$level" "$CMX_LOG_COMPONENT" "$$" "$escaped_message")

    echo "$json_line" >> "$CMX_LOG_FILE" 2>/dev/null || true

    # Buffer
    CMX_LOG_BUFFER+=("$json_line")
    _log_flush_if_full
}

_log_write_raw() {
    local message="$1"

    if [ -n "$CMX_LOG_FILE" ]; then
        echo "$message" >> "$CMX_LOG_FILE" 2>/dev/null || true
    fi
}

# ============================================================================
# AT EXIT — flush automático
# ============================================================================

_log_at_exit() {
    log_flush
}

# Registrar cleanup al cargar la librería
trap _log_at_exit EXIT

# ============================================================================
# ALIAS DE COMPATIBILIDAD (para scripts existentes)
# ============================================================================

# Estos alias permiten que scripts existentes que usan log() sigan funcionando
# después de sourcear esta librería

# log() genérico → log_info()
if ! type log >/dev/null 2>&1; then
    log() { log_info "$@"; }
fi
