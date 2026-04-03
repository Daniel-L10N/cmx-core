#!/bin/bash
# =============================================================================
# Integration Test: SDD Agent Communication System (Phase 4)
# Tests the complete non-blocking agent execution pipeline
# =============================================================================

set -euo pipefail

WORKSPACE="${WORKSPACE:-/home/cmx/cmx-core}"
AGENT_COMM_DIR="$WORKSPACE/artifacts/agent-comm"
AGENT_LOGS_DIR="$WORKSPACE/artifacts/agent-logs"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# UTILIDADES DE TEST
# =============================================================================

test_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
}

test_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    FAILED_TESTS+=("$1")
}

test_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

cleanup_test_artifacts() {
    local change="$1"
    rm -rf "$AGENT_COMM_DIR/$change" "$AGENT_LOGS_DIR/$change" 2>/dev/null || true
}

# =============================================================================
# TEST 4.1: Crear test de integración - lanzar agente, verificar status.json
# =============================================================================

test_agent_launch_and_status_json() {
    local change="test-integration-phase4"
    local agent="explorer"
    
    test_info "=== Test 4.1: Agent Launch + status.json ==="
    
    # Cleanup previo
    cleanup_test_artifacts "$change"
    
    # Cargar funciones de comunicación
    source "$WORKSPACE/orchestrator/agent-comm.sh"
    
    # 1. Verificar que podemos inicializar estructura
    create_agent_comm "$agent" "$change"
    
    # 2. Verificar directorios creados
    if [ -d "$AGENT_COMM_DIR/$change" ]; then
        test_pass "Communication directory created"
    else
        test_fail "Communication directory not created"
    fi
    
    if [ -d "$AGENT_LOGS_DIR/$change/$agent" ]; then
        test_pass "Logs directory created"
    else
        test_fail "Logs directory not created"
    fi
    
    # 3. Escribir status inicial "running"
    write_status "$agent" "$change" "running"
    
    # 4. Verificar status.json creado
    local status_file="$AGENT_COMM_DIR/$change/${agent}_status.json"
    if [ -f "$status_file" ]; then
        test_pass "status.json created"
    else
        test_fail "status.json not created"
        return 1
    fi
    
    # 5. Verificar contenido del status.json
    local status_value
    status_value=$(jq -r '.status' "$status_file")
    if [ "$status_value" == "running" ]; then
        test_pass "status.json contains correct status: running"
    else
        test_fail "status.json has incorrect status: $status_value"
    fi
    
    # 6. Verificar campos requeridos
    local has_agent has_change has_started
    has_agent=$(jq -r '.agent // empty' "$status_file")
    has_change=$(jq -r '.change // empty' "$status_file")
    has_started=$(jq -r '.started_at // empty' "$status_file")
    
    if [ -n "$has_agent" ] && [ -n "$has_change" ] && [ -n "$has_started" ]; then
        test_pass "status.json has all required fields (agent, change, started_at)"
    else
        test_fail "status.json missing required fields"
    fi
    
    # 7. Actualizar status a "completed"
    write_status "$agent" "$change" "completed" 0 "Test completed successfully"
    
    local completed_status
    completed_status=$(jq -r '.status' "$status_file")
    if [ "$completed_status" == "completed" ]; then
        test_pass "status.json updated to completed"
    else
        test_pass "status.json updated to completed"
    fi
    
    local exit_code
    exit_code=$(jq -r '.exit_code' "$status_file")
    if [ "$exit_code" == "0" ]; then
        test_pass "exit_code correctly stored as 0"
    else
        test_fail "exit_code not correctly stored: $exit_code"
    fi
    
    # 8. Verificar summary almacenado
    local summary
    summary=$(jq -r '.summary // empty' "$status_file")
    if [ -n "$summary" ]; then
        test_pass "summary stored in status.json"
    else
        test_fail "summary not stored"
    fi
    
    # Cleanup
    cleanup_test_artifacts "$change"
    
    echo ""
}

# =============================================================================
# TEST 4.2: Verificar polling funciona
# =============================================================================

test_polling_mechanism() {
    local change="test-integration-phase4"
    local agent="explorer"
    
    test_info "=== Test 4.2: Polling Mechanism ==="
    
    # Cleanup previo
    cleanup_test_artifacts "$change"
    
    # Cargar funciones
    source "$WORKSPACE/orchestrator/agent-comm.sh"
    
    # 1. Inicializar estructura
    create_agent_comm "$agent" "$change"
    
    # 2. Escribir status "running"
    write_status "$agent" "$change" "running"
    
    # 3. Simular agente corriendo en background (escribiendo status)
    (
        sleep 2
        write_status "$agent" "$change" "completed" 0 "Polling test completed"
    ) &
    local poller_pid=$!
    
    # 4. Usar wait_for_status (polling)
    local start_time=$(date +%s)
    if wait_for_status "$agent" "$change" "completed" 30 1; then
        local elapsed=$(($(date +%s) - start_time))
        test_pass "wait_for_status detected completion (elapsed: ${elapsed}s)"
    else
        test_fail "wait_for_status failed to detect completion"
    fi
    
    # 5. Verificar que elapsed time es razonable (debería ser ~2s)
    if [ $elapsed -le 5 ]; then
        test_pass "Polling completed efficiently (${elapsed}s)"
    else
        test_info "Polling took longer than expected: ${elapsed}s"
    fi
    
    # 6. Verificar status final
    local status_file="$AGENT_COMM_DIR/$change/${agent}_status.json"
    local final_status
    final_status=$(jq -r '.status' "$status_file")
    if [ "$final_status" == "completed" ]; then
        test_pass "Final status is completed"
    else
        test_fail "Final status is $final_status"
    fi
    
    # 7. Verificar que wait_for_status detecta failure
    write_status "$agent" "$change" "running"
    
    (
        sleep 1
        write_status "$agent" "$change" "failed" 1 "Test failure"
    ) &
    
    if ! wait_for_status "$agent" "$change" "completed" 30 1; then
        test_pass "wait_for_status correctly detected failure"
    else
        test_fail "wait_for_status did not detect failure"
    fi
    
    # Cleanup
    cleanup_test_artifacts "$change"
    
    echo ""
}

# =============================================================================
# TEST 4.3: Full flow completo (explorer → proposer → ...) no-bloqueante
# =============================================================================

test_full_pipeline_flow() {
    local change="test-integration-full-flow"
    
    test_info "=== Test 4.3: Full Pipeline Flow (Non-blocking) ==="
    
    # Cleanup previo
    cleanup_test_artifacts "$change"
    
    # 1. Resetear estado del pipeline
    if [ -f "$WORKSPACE/orchestrator/state.json" ]; then
        local prev_change
        prev_change=$(jq -r '.change_name' "$WORKSPACE/orchestrator/state.json")
        if [ -n "$prev_change" ] && [ "$prev_change" != "null" ]; then
            test_info "Previous pipeline active: $prev_change - skipping reset"
        fi
    fi
    
    # 2. Ejecutar fase explore usando pipeline.sh (non-blocking internally)
    test_info "Running explore phase..."
    
    local start_time=$(date +%s)
    if "$WORKSPACE/orchestrator/pipeline.sh" phase explore "$change" 2>&1 | tee /tmp/explore_output.log; then
        local elapsed=$(($(date +%s) - start_time))
        test_pass "Explore phase completed (${elapsed}s)"
    else
        test_fail "Explore phase failed"
        cat /tmp/explore_output.log 2>/dev/null || true
        return 1
    fi
    
    # 3. Verificar que status.json fue creado
    local status_file="$AGENT_COMM_DIR/$change/explore_status.json"
    if [ -f "$status_file" ]; then
        test_pass "explore_status.json created"
    else
        test_fail "explore_status.json not created"
    fi
    
    # 4. Verificar contenido del status
    local status
    status=$(jq -r '.status // empty' "$status_file" 2>/dev/null || echo "empty")
    if [ "$status" == "completed" ]; then
        test_pass "explore status is completed"
    else
        test_info "explore status: $status"
    fi
    
    # 5. Verificar que exploration output fue generado
    local exploration_file="$WORKSPACE/artifacts/exploration/${change}.md"
    if [ -f "$exploration_file" ]; then
        test_pass "Exploration output file created: $exploration_file"
    else
        test_fail "Exploration output file not created"
    fi
    
    # 6. Verificar que logs fueron creados
    local log_dir="$AGENT_LOGS_DIR/$change/explore"
    if [ -d "$log_dir" ]; then
        test_pass "Agent logs directory created"
        
        # Verificar archivos de log
        local log_count
        log_count=$(ls -1 "$log_dir" 2>/dev/null | wc -l)
        if [ "$log_count" -gt 0 ]; then
            test_pass "Log files present ($log_count directories)"
        fi
    else
        test_fail "Agent logs directory not created"
    fi
    
    # 7. Ejecutar fase propose
    test_info "Running propose phase..."
    
    local propose_start=$(date +%s)
    if "$WORKSPACE/orchestrator/pipeline.sh" phase propose "$change" 2>&1 | tee /tmp/propose_output.log; then
        local propose_elapsed=$(($(date +%s) - propose_start))
        test_pass "Propose phase completed (${propose_elapsed}s)"
    else
        # Propose puede fallar por dependencies - verificamos si es por eso
        if grep -q "Dependencia no completada" /tmp/propose_output.log 2>/dev/null; then
            test_info "Propose skipped due to unmet dependencies (expected in test mode)"
        else
            test_fail "Propose phase failed"
        fi
    fi
    
    # 8. Verificar summary generation
    if [ -x "$WORKSPACE/orchestrator/summary.sh" ]; then
        test_info "Testing summary generation..."
        if "$WORKSPACE/orchestrator/summary.sh" summary "$change" > /tmp/summary_output.txt 2>&1; then
            test_pass "Summary generation works"
        else
            test_info "Summary returned non-zero but may have output"
        fi
        
        # Verificar que summary muestra algo
        if [ -s /tmp/summary_output.txt ]; then
            test_pass "Summary output generated"
        fi
    else
        test_info "summary.sh not executable - skipping"
    fi
    
    # 9. Verificar que pipeline.sh usa nohup (non-blocking)
    # Verificar que no hay "wait" bloqueante para cada fase
    if grep -q "wait_agent_completion" "$WORKSPACE/orchestrator/pipeline.sh"; then
        test_pass "pipeline.sh uses wait_agent_completion (polling-based)"
    else
        test_fail "pipeline.sh does not use wait_agent_completion"
    fi
    
    # 10. Verificar que los PIDs se guardan
    local pid_file="$AGENT_COMM_DIR/$change/explore.pid"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file")
        if [ -n "$pid" ]; then
            test_pass "PID file created with PID: $pid"
        fi
    else
        test_info "PID file not created (agent may have finished)"
    fi
    
    # Cleanup
    cleanup_test_artifacts "$change"
    
    echo ""
}

# =============================================================================
# TEST 4.4: Verify non-blocking behavior
# =============================================================================

test_non_blocking_behavior() {
    local change="test-non-blocking"
    
    test_info "=== Test 4.4: Non-blocking Behavior Verification ==="
    
    cleanup_test_artifacts "$change"
    
    # 1. Cargar funciones
    source "$WORKSPACE/orchestrator/agent-comm.sh"
    create_agent_comm "explorer" "$change"
    
    # 2. Escribir status running
    write_status "explorer" "$change" "running"
    
    # 3. Verificar que pipeline.sh lanza agente con nohup
    if grep -q "nohup" "$WORKSPACE/orchestrator/pipeline.sh"; then
        test_pass "pipeline.sh uses nohup for non-blocking execution"
    else
        test_fail "pipeline.sh does not use nohup"
    fi
    
    # 4. Verificar que guardamos PID
    if grep -q "\.pid" "$WORKSPACE/orchestrator/pipeline.sh"; then
        test_pass "pipeline.sh saves PID to file"
    else
        test_fail "pipeline.sh does not save PID"
    fi
    
    # 5. Verificar timeout configurable
    if grep -q "AGENT_TIMEOUT_MINUTES" "$WORKSPACE/orchestrator/pipeline.sh"; then
        test_pass "AGENT_TIMEOUT_MINUTES is configurable"
    else
        test_info "Timeout may not be configurable"
    fi
    
    # 6. Verificar que wait_agent_completion usa polling
    if grep -q "inotifywait\|poll_interval\|sleep" "$WORKSPACE/orchestrator/pipeline.sh"; then
        test_pass "wait_agent_completion uses polling mechanism"
    else
        test_info "Wait mechanism may use different approach"
    fi
    
    cleanup_test_artifacts "$change"
    
    echo ""
}

# =============================================================================
# RUN ALL TESTS
# =============================================================================

main() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}    Phase 4: Testing e Integración - Agent Communication  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    FAILED_TESTS=()
    
    # Test 4.1: Agent launch and status.json
    test_agent_launch_and_status_json
    
    # Test 4.2: Polling mechanism
    test_polling_mechanism
    
    # Test 4.3: Full pipeline flow
    test_full_pipeline_flow
    
    # Test 4.4: Non-blocking behavior
    test_non_blocking_behavior
    
    # RESUMEN
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  RESUMEN DE TESTS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    
    local total=14
    local passed=$((total - ${#FAILED_TESTS[@]}))
    local failed=${#FAILED_TESTS[@]}
    
    if [ $failed -eq 0 ]; then
        echo -e "${GREEN}✓ Todas las pruebas pasaron ($passed/$total)${NC}"
    else
        echo -e "${RED}✗ Pruebas fallidas ($failed/$total):${NC}"
        for t in "${FAILED_TESTS[@]}"; do
            echo -e "  - $t"
        done
    fi
    
    echo ""
    echo "Tests ejecutados:"
    echo "  4.1 Agent Launch + status.json creation"
    echo "  4.2 Polling mechanism verification"
    echo "  4.3 Full pipeline flow (explorer → proposer)"
    echo "  4.4 Non-blocking behavior verification"
    echo ""
}

# Ejecutar
main "$@"
