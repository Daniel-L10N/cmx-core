#!/bin/bash
# =============================================================================
# CMX-CORE — Metrics Collection & Reporting
# v2.2.0
#
# Uso:
#   source lib/metrics.sh
#   metrics_init "mi-proyecto"
#   metrics_record "ia_selection" "opencode" "cost_level=2"
#   metrics_record "task_duration" "45.2s" "type=coding"
#   metrics_report                              # Muestra resumen
#   metrics_report_json                          # Output JSON
#
# Los datos se guardan en:
#   logs/cmx-metrics-{fecha}.jsonl  (append, cada línea es un evento)
# =============================================================================

METRICS_DIR="${METRICS_DIR:-}"
METRICS_FILE=""
METRICS_PROJECT=""

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

metrics_init() {
    local project="${1:-cmx-core}"
    local log_dir="${2:-}"

    METRICS_PROJECT="$project"

    # Determinar directorio
    if [ -n "$log_dir" ]; then
        METRICS_DIR="$log_dir"
    elif [ -z "$METRICS_DIR" ]; then
        local search_dir="${SCRIPT_DIR:-.}"
        if [ -d "$search_dir/logs" ]; then
            METRICS_DIR="$search_dir/logs"
        elif [ -d "$search_dir/../logs" ]; then
            METRICS_DIR="$search_dir/../logs"
        else
            METRICS_DIR="$search_dir/logs"
        fi
    fi

    mkdir -p "$METRICS_DIR" 2>/dev/null || true

    local date_stamp
    date_stamp=$(date +%Y%m%d)
    METRICS_FILE="$METRICS_DIR/cmx-metrics-${date_stamp}.jsonl"
}

# ============================================================================
# REGISTRO DE MÉTRICA
# ============================================================================

metrics_record() {
    local metric_name="$1"
    local metric_value="$2"
    local extra="${3:-}"
    local component="${4:-}"

    if [ -z "$METRICS_FILE" ]; then
        metrics_init "${METRICS_PROJECT:-cmx-core}"
    fi

    local timestamp
    timestamp=$(date -Iseconds)

    # Construir JSON line
    local json_line
    json_line=$(printf '{"ts":"%s","project":"%s","metric":"%s","value":"%s","extra":"%s","component":"%s","pid":%d}' \
        "$timestamp" "$METRICS_PROJECT" "$metric_name" "$metric_value" "$extra" "${component:-system}" "$$")

    echo "$json_line" >> "$METRICS_FILE" 2>/dev/null || true
}

# ============================================================================
# HELPERS DE MÉTRICAS COMUNES
# =============================================================================

metrics_task_start() {
    local task_id="$1"
    local task_desc="$2"
    local project="${3:-cmx-core}"

    metrics_record "task_start" "$task_id" "desc=$task_desc" "brain"
}

metrics_task_end() {
    local task_id="$1"
    local status="$2"
    local duration="$3"
    local ia_used="${4:-}"

    metrics_record "task_end" "$status" "id=$task_id,duration=$duration,ia=$ia_used" "brain"
}

metrics_ia_selection() {
    local ia="$1"
    local task_type="$2"
    local cost_level="$3"
    local reason="${4:-}"

    metrics_record "ia_selection" "$ia" "type=$task_type,cost=$cost_level,reason=$reason" "ai-selector"
}

metrics_phase_duration() {
    local phase="$1"
    local duration="$2"
    local status="${3:-completed}"
    local change="${4:-}"

    metrics_record "phase_duration" "$duration" "phase=$phase,status=$status,change=$change" "pipeline"
}

metrics_error() {
    local component="$1"
    local error_msg="$2"
    local context="${3:-}"

    metrics_record "error" "$error_msg" "component=$component,context=$context" "$component"
}

# ============================================================================
# REPORTES
# =============================================================================

metrics_report() {
    if [ -z "$METRICS_FILE" ] || [ ! -f "$METRICS_FILE" ]; then
        echo "No hay métricas disponibles."
        return 1
    fi

    local total_lines
    total_lines=$(wc -l < "$METRICS_FILE" 2>/dev/null || echo "0")

    echo ""
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║         📊 CMX-CORE — MÉTRICAS DEL DÍA               ║"
    echo "╠════════════════════════════════════════════════════════╣"
    echo "║  Archivo: $(basename "$METRICS_FILE")"
    echo "║  Eventos: $total_lines"
    echo "║  Fecha:   $(date +%Y-%m-%d)"
    echo "╚════════════════════════════════════════════════════════╝"
    echo ""

    # Contar métricas por tipo
    echo "=== Métricas por Tipo ==="
    jq -r '.metric' "$METRICS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | while read count metric; do
        printf "  %-25s %d\n" "$metric" "$count"
    done
    echo ""

    # IAs utilizadas
    echo "=== IAs Seleccionadas ==="
    jq -r 'select(.metric == "ia_selection") | .value' "$METRICS_FILE" 2>/dev/null | sort | uniq -c | sort -rn | while read count ia; do
        printf "  %-15s %d veces\n" "$ia" "$count"
    done
    echo ""

    # Errores
    local error_count
    error_count=$(jq -r 'select(.metric == "error") | .metric' "$METRICS_FILE" 2>/dev/null | wc -l)
    if [ "$error_count" -gt 0 ]; then
        echo "=== Errores ($error_count) ==="
        jq -r 'select(.metric == "error") | "  [\(.ts)] \(.component): \(.value)"' "$METRICS_FILE" 2>/dev/null | head -10
        echo ""
    fi

    # Tareas completadas
    local completed
    completed=$(jq -r 'select(.metric == "task_end" and .value == "success") | .value' "$METRICS_FILE" 2>/dev/null | wc -l)
    local failed
    failed=$(jq -r 'select(.metric == "task_end" and .value == "error") | .value' "$METRICS_FILE" 2>/dev/null | wc -l)
    local timeout_count
    timeout_count=$(jq -r 'select(.metric == "task_end" and .value == "timeout") | .value' "$METRICS_FILE" 2>/dev/null | wc -l)

    echo "=== Resumen de Tareas ==="
    printf "  %-15s %d\n" "Completadas:" "$completed"
    printf "  %-15s %d\n" "Fallidas:" "$failed"
    printf "  %-15s %d\n" "Timeouts:" "$timeout_count"
    echo ""
}

metrics_report_json() {
    if [ -z "$METRICS_FILE" ] || [ ! -f "$METRICS_FILE" ]; then
        echo '{"error": "No metrics file found"}'
        return 1
    fi

    # Convertir JSONL a JSON array
    echo "["
    local first=true
    while IFS= read -r line; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        echo "$line"
    done < "$METRICS_FILE"
    echo "]"
}

# ============================================================================
# LIMPIEZA DE MÉTRICAS ANTIGUAS
# =============================================================================

metrics_cleanup() {
    local keep_days="${1:-30}"
    local log_dir="${METRICS_DIR:-logs}"

    if [ ! -d "$log_dir" ]; then
        return 0
    fi

    local cutoff
    cutoff=$(date -d "-${keep_days} days" +%Y%m%d 2>/dev/null || echo "0")

    local deleted=0
    for f in "$log_dir"/cmx-metrics-*.jsonl; do
        [ -f "$f" ] || continue
        local file_date
        file_date=$(basename "$f" | sed 's/cmx-metrics-//; s/\.jsonl//')

        if [[ "$file_date" =~ ^[0-9]{8}$ ]] && [ "$file_date" -lt "$cutoff" ]; then
            rm -f "$f"
            deleted=$((deleted + 1))
        fi
    done

    if [ "$deleted" -gt 0 ]; then
        echo "Métricas antiguas eliminadas: $deleted"
    fi
}
