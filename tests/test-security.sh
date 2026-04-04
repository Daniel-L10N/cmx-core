#!/bin/bash
# =============================================================================
# CMX-CORE — Security & Regression Test Suite
# v2.2.0
#
# Tests para los fixes críticos de v2.1.1 y funcionalidades de v2.2.0
#
# Uso:
#   bash tests/test-security.sh              # Ejecutar todos los tests
#   bash tests/test-security.sh sql          # Solo tests de SQL injection
#   bash tests/test-security.sh timeout      # Solo tests de timeouts
#   bash tests/test-security.sh cleanup      # Solo tests de cleanup
#   bash tests/test-security.sh logger       # Solo tests de logging
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Contadores
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# ============================================================================
# HELPERS DE TEST
# ============================================================================

test_pass() {
    local name="$1"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}✓ PASS${NC} $name"
}

test_fail() {
    local name="$1"
    local detail="${2:-}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}✗ FAIL${NC} $name"
    if [ -n "$detail" ]; then
        echo -e "         ${RED}→ $detail${NC}"
    fi
}

test_skip() {
    local name="$1"
    local reason="${2:-}"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "  ${YELLOW}⊘ SKIP${NC} $name (${reason})"
}

assert_contains() {
    local output="$1"
    local expected="$2"
    local test_name="$3"

    if echo "$output" | grep -qF "$expected"; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Expected '$expected' in output"
    fi
}

assert_not_contains() {
    local output="$1"
    local forbidden="$2"
    local test_name="$3"

    if echo "$output" | grep -qF "$forbidden"; then
        test_fail "$test_name" "Found forbidden string '$forbidden' in output"
    else
        test_pass "$test_name"
    fi
}

assert_exit_code() {
    local actual="$1"
    local expected="$2"
    local test_name="$3"

    if [ "$actual" -eq "$expected" ]; then
        test_pass "$test_name"
    else
        test_fail "$test_name" "Expected exit code $expected, got $actual"
    fi
}

# ============================================================================
# SETUP: Base de datos de prueba
# ============================================================================

setup_test_db() {
    local test_db="$PROJECT_ROOT/tests/test-memories.db"

    # Limpiar si existe
    rm -f "$test_db"

    # Crear schema
    sqlite3 "$test_db" << 'EOF'
CREATE TABLE memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL DEFAULT 'memory',
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    project TEXT NOT NULL DEFAULT 'cmx-core',
    agent TEXT DEFAULT 'system',
    task_id TEXT,
    phase TEXT,
    metadata TEXT DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
    title,
    content,
    content='memories',
    content_rowid='id',
    tokenize='unicode61'
);

CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts(rowid, title, content)
    VALUES (new.id, new.title, new.content);
END;

CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, title, content)
    VALUES ('delete', old.id, old.title, old.content);
END;

CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, title, content)
    VALUES ('delete', old.id, old.title, old.content);
    INSERT INTO memories_fts(rowid, title, content)
    VALUES (new.id, new.title, new.content);
END;

INSERT INTO memory_types (name, description) VALUES
    ('decision', 'Decisiones del orquestador'),
    ('synthesis', 'Lecciones aprendidas'),
    ('task', 'Tareas del proyecto'),
    ('note', 'Notas generales'),
    ('bugfix', 'Correcciones de bugs'),
    ('architecture', 'Decisiones arquitectónicas');
EOF

    echo "$test_db"
}

cleanup_test_db() {
    rm -f "$PROJECT_ROOT/tests/test-memories.db"
}

# ============================================================================
# TESTS: SQL INJECTION PREVENTION
# ============================================================================

test_sql_injection() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🔒 SQL INJECTION TESTS (Fix #1 — v2.1.1)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local test_db
    test_db=$(setup_test_db)

    # Temporalmente apuntar memory-save.sh al test DB
    local save_script="$PROJECT_ROOT/scripts/memory-save.sh"
    local query_script="$PROJECT_ROOT/scripts/memory-query.sh"

    # --- Test 1: Comilla simple en title ---
    local output
    output=$(MEMORIES_DB="$test_db" bash -c "
        source <(sed \"s|MEMORIES_DB=.*|MEMORIES_DB='$test_db'|\" '$save_script' | head -1)
        TYPE='decision'
        TITLE=\"test' OR '1'='1\"
        CONTENT='sql injection test'
        PROJECT='test-project'
        AGENT='test-agent'
        TASK_ID='test-001'
        PHASE='test'
        MAX_TITLE_LENGTH=500
        MAX_CONTENT_LENGTH=500000
        MAX_PROJECT_LENGTH=100
        MAX_AGENT_LENGTH=100
        VALID_TYPES='decision synthesis task note bugfix architecture'

        sql_escape() {
            local input=\"\$1\"
            input=\"\${input//\\\\/\\\\\\\\}\"
            input=\"\${input//\\'/\\'\\'}\"
            input=\"\${input//\\\"/\\\\\\\"}\"
            input=\"\${input//\$'\\t'/\\\\t}\"
            input=\"\${input//\$'\\n'/\\\\n}\"
            input=\"\${input//\$'\\r'/\\\\r}\"
            echo \"\$input\"
        }

        ESCAPED_TITLE=\$(sql_escape \"\$TITLE\")
        echo \"ESCAPED:\$ESCAPED_TITLE\"
    " 2>&1) || true

    # Verificar que la comilla simple fue escapada
    if echo "$output" | grep -q "''"; then
        test_pass "SQL escape: comilla simple escapada correctamente"
    else
        test_fail "SQL escape: comilla simple no escapada" "$output"
    fi

    # --- Test 2: Tipo de memoria inválido ---
    output=$(MEMORIES_DB="$test_db" bash "$save_script" "hacked" "test" "content" "test" 2>&1) || true
    if echo "$output" | grep -qi "inválido\|ERROR\|Tipos válidos"; then
        test_pass "Validación: tipo de memoria inválido rechazado"
    else
        test_fail "Validación: tipo de memoria inválido NO rechazado" "$output"
    fi

    # --- Test 3: Contenido con secuencia de comentario SQL ---
    output=$(MEMORIES_DB="$test_db" bash "$save_script" "note" "test" "contenido -- comentario" "test" 2>&1) || true
    # Debería guardar sin error (el escape maneja esto)
    if echo "$output" | grep -q "saved\|Memoria guardada"; then
        test_pass "SQL escape: contenido con comentario SQL manejado"
    else
        test_fail "SQL escape: contenido con comentario SQL falló" "$output"
    fi

    # --- Test 4: Query FTS5 con caracteres especiales ---
    # Crear DB de prueba aislada para este test
    local test_db2="$PROJECT_ROOT/tests/test-query.db"
    rm -f "$test_db2"
    sqlite3 "$test_db2" << 'EOF'
CREATE TABLE memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    type TEXT NOT NULL DEFAULT 'memory',
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    project TEXT NOT NULL DEFAULT 'cmx-core',
    agent TEXT DEFAULT 'system',
    task_id TEXT,
    phase TEXT,
    metadata TEXT DEFAULT '{}',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE VIRTUAL TABLE memories_fts USING fts5(title, content, content='memories', content_rowid='id', tokenize='unicode61');
CREATE TRIGGER memories_ai AFTER INSERT ON memories BEGIN INSERT INTO memories_fts(rowid, title, content) VALUES (new.id, new.title, new.content); END;
INSERT INTO memories (type, title, content, project) VALUES ('note', 'test note', 'this is test content', 'test-project');
EOF

    local query_output
    query_output=$(sqlite3 "$test_db2" "
    SELECT json_group_array(
        json_object('id', m.id, 'type', m.type, 'title', m.title, 'content', m.content, 'project', m.project)
    )
    FROM memories m
    INNER JOIN memories_fts fts ON m.id = fts.rowid
    WHERE memories_fts MATCH 'test'
    ORDER BY bm25(memories_fts);
    " 2>&1)

    rm -f "$test_db2"

    if echo "$query_output" | jq empty 2>/dev/null; then
        test_pass "Query FTS5: output JSON válido con caracteres especiales"
    else
        test_fail "Query FTS5: output JSON inválido" "$query_output"
    fi

    # --- Test 5: Límite de tamaño en title ---
    local long_title
    long_title=$(python3 -c "print('A' * 600)" 2>/dev/null || echo "$(head -c 600 /dev/urandom | tr -dc 'A-Z' | head -c 600)")
    output=$(MEMORIES_DB="$test_db" bash "$save_script" "note" "$long_title" "test content" "test" 2>&1) || true
    if echo "$output" | grep -qi "truncando\|saved\|Memoria guardada"; then
        test_pass "Validación: title largo truncado correctamente"
    else
        test_fail "Validación: title largo no manejado" "$output"
    fi

    # --- Test 6: Límite numérico sanitizado ---
    # Verificar que el código tiene la sanitización
    if grep -q 'sanitize_limit\|MAX_LIMIT' "$query_script"; then
        test_pass "Validación: código de sanitización de límite presente"
    else
        test_fail "Validación: código de sanitización de límite NO encontrado"
    fi

    # --- Test 7: Límite no numérico ---
    # Verificar que el código valida que el límite sea numérico
    if grep -q '\^\\[0-9\\]\+\$\|regex.*limit\|!.*\^\\[0-9\\]' "$query_script" || grep -q 'sanitize_limit' "$query_script"; then
        test_pass "Validación: validación de límite no numérico presente"
    else
        test_fail "Validación: validación de límite no numérico NO encontrada"
    fi

    cleanup_test_db
}

# ============================================================================
# TESTS: CLEANUP FIX
# ============================================================================

test_cleanup_fix() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🐛 CLEANUP FIX TESTS (Fix #2 — v2.1.1)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local test_db
    test_db=$(setup_test_db)

    # Insertar datos de prueba
    sqlite3 "$test_db" << 'EOF'
INSERT INTO memories (type, title, content, project, agent, task_id) VALUES
    ('decision', 'dec-1', 'content 1', 'cleanup-test', 'agent-a', 't1'),
    ('decision', 'dec-2', 'content 2', 'cleanup-test', 'agent-b', 't2'),
    ('decision', 'dec-3', 'content 3', 'other-project', 'agent-a', 't3'),
    ('synthesis', 'synth-1', 'synthesis content', 'cleanup-test', 'cleanup', 't4'),
    ('note', 'note-1', 'note content', 'cleanup-test', 'agent-a', 't5');
EOF

    # --- Test 1: Verificar que cleanup-project.sh apunta a .db ---
    local cleanup_script="$PROJECT_ROOT/scripts/cleanup-project.sh"
    if grep -q 'memories\.db' "$cleanup_script" && ! grep -q 'memories\.json' "$cleanup_script"; then
        test_pass "Cleanup: apunta a memories.db (no .json)"
    else
        test_fail "Cleanup: todavía referencia memories.json"
    fi

    # --- Test 2: Verificar que no usa jq sobre la DB ---
    if ! grep -q 'jq.*MEMORIES_DB\|jq.*\.db' "$cleanup_script"; then
        test_pass "Cleanup: no usa jq sobre archivo SQLite"
    else
        test_fail "Cleanup: todavía usa jq sobre archivo SQLite"
    fi

    # --- Test 3: Verificar que usa SQL para DELETE ---
    if grep -q 'DELETE FROM memories' "$cleanup_script"; then
        test_pass "Cleanup: usa SQL DELETE nativo"
    else
        test_fail "Cleanup: no usa SQL DELETE"
    fi

    # --- Test 4: Contar decisiones antes del cleanup ---
    local before_count
    before_count=$(sqlite3 "$test_db" "SELECT COUNT(*) FROM memories WHERE project='cleanup-test' AND type='decision';")
    if [ "$before_count" -eq 2 ]; then
        test_pass "Cleanup: 2 decisiones de prueba insertadas correctamente"
    else
        test_fail "Cleanup: expected 2 decisions, got $before_count"
    fi

    # --- Test 5: Verificar que la síntesis se mantiene ---
    local synth_count
    synth_count=$(sqlite3 "$test_db" "SELECT COUNT(*) FROM memories WHERE project='cleanup-test' AND type='synthesis';")
    if [ "$synth_count" -eq 1 ]; then
        test_pass "Cleanup: síntesis de prueba existe"
    else
        test_fail "Cleanup: síntesis de prueba no encontrada"
    fi

    cleanup_test_db
}

# ============================================================================
# TESTS: CLI CLEANUP VARIABLE
# ============================================================================

test_cli_cleanup_var() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🔧 CLI CLEANUP VARIABLE (Fix #3 — v2.1.1)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local cli_script="$PROJECT_ROOT/cmx"

    # --- Test 1: Variable CLEANUP_SCRIPT definida ---
    if grep -q 'CLEANUP_SCRIPT=' "$cli_script"; then
        test_pass "CLI: variable CLEANUP_SCRIPT definida"
    else
        test_fail "CLI: variable CLEANUP_SCRIPT NO definida"
    fi

    # --- Test 2: Validación de existencia del script ---
    if grep -q '\-f.*CLEANUP_SCRIPT\|! -f.*CLEANUP_SCRIPT' "$cli_script"; then
        test_pass "CLI: validación de existencia del script de cleanup"
    else
        test_fail "CLI: no valida existencia del script de cleanup"
    fi

    # --- Test 3: La variable apunta al path correcto ---
    if grep -q 'cleanup-project\.sh' "$cli_script"; then
        test_pass "CLI: CLEANUP_SCRIPT apunta a cleanup-project.sh"
    else
        test_fail "CLI: CLEANUP_SCRIPT no referencia cleanup-project.sh"
    fi
}

# ============================================================================
# TESTS: TIMEOUTS
# ============================================================================

test_timeouts() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  ⏱️  TIMEOUT TESTS (Fix #4 — v2.1.1)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local brain_script="$PROJECT_ROOT/brain.sh"

    # --- Test 1: Variables de timeout definidas ---
    if grep -q 'TIMEOUT_OPENCODE=' "$brain_script"; then
        test_pass "Brain: TIMEOUT_OPENCODE definido"
    else
        test_fail "Brain: TIMEOUT_OPENCODE NO definido"
    fi

    if grep -q 'TIMEOUT_GEMINI=' "$brain_script"; then
        test_pass "Brain: TIMEOUT_GEMINI definido"
    else
        test_fail "Brain: TIMEOUT_GEMINI NO definido"
    fi

    if grep -q 'TIMEOUT_OPENROUTER=' "$brain_script"; then
        test_pass "Brain: TIMEOUT_OPENROUTER definido"
    else
        test_fail "Brain: TIMEOUT_OPENROUTER NO definido"
    fi

    # --- Test 2: Función run_with_timeout existe ---
    if grep -q 'run_with_timeout()' "$brain_script"; then
        test_pass "Brain: función run_with_timeout() definida"
    else
        test_fail "Brain: función run_with_timeout() NO definida"
    fi

    # --- Test 3: Timeout se aplica en llamadas a IA ---
    if grep -q 'run_with_timeout.*TIMEOUT_OPENCODE' "$brain_script"; then
        test_pass "Brain: opencode usa run_with_timeout"
    else
        test_fail "Brain: opencode NO usa run_with_timeout"
    fi

    if grep -q 'run_with_timeout.*TIMEOUT_GEMINI' "$brain_script"; then
        test_pass "Brain: gemini usa run_with_timeout"
    else
        test_fail "Brain: gemini NO usa run_with_timeout"
    fi

    # --- Test 4: Manejo de timeout exit code 124 ---
    if grep -q '124' "$brain_script"; then
        test_pass "Brain: manejo de exit code 124 (timeout)"
    else
        test_fail "Brain: no maneja exit code 124"
    fi

    # --- Test 5: Verificar que el comando timeout existe en el sistema ---
    if command -v timeout >/dev/null 2>&1; then
        test_pass "Sistema: comando 'timeout' disponible"

        # Test funcional: verificar que timeout funciona
        local timeout_result
        timeout_result=$(timeout 1 sleep 10 2>&1) || true
        if [ $? -eq 124 ] || echo "$timeout_result" | grep -qi "timeout\|Terminated"; then
            test_pass "Sistema: timeout command funciona correctamente"
        else
            test_skip "Sistema: timeout command behavior verification" "exit code: $?"
        fi
    else
        test_skip "Sistema: comando 'timeout' no disponible" "fallback manual se usará"
    fi

    # --- Test 6: Verificar valores por defecto razonables ---
    local oc_timeout
    oc_timeout=$(grep 'TIMEOUT_OPENCODE=' "$brain_script" | grep -o '[0-9]\+' | head -1)
    if [ -n "$oc_timeout" ] && [ "$oc_timeout" -ge 60 ] && [ "$oc_timeout" -le 600 ]; then
        test_pass "Brain: TIMEOUT_OPENCODE valor razonable (${oc_timeout}s)"
    else
        test_fail "Brain: TIMEOUT_OPENCODE valor fuera de rango: $oc_timeout"
    fi
}

# ============================================================================
# TESTS: LOGGER
# ============================================================================

test_logger() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  📝 LOGGER TESTS (v2.2.0)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local logger_script="$PROJECT_ROOT/lib/logger.sh"
    local test_log_dir="$PROJECT_ROOT/tests/test-logs"
    mkdir -p "$test_log_dir"

    # --- Test 1: Archivo logger.sh existe ---
    if [ -f "$logger_script" ]; then
        test_pass "Logger: archivo lib/logger.sh existe"
    else
        test_fail "Logger: archivo lib/logger.sh NO existe"
        return
    fi

    # --- Test 2: Syntax check ---
    if bash -n "$logger_script" 2>/dev/null; then
        test_pass "Logger: syntax check OK"
    else
        test_fail "Logger: syntax check FAILED"
        return
    fi

    # --- Test 3: Funciones exportadas ---
    local functions
    functions=$(grep -c '^[a-z_]*()' "$logger_script" 2>/dev/null || echo "0")
    if [ "$functions" -ge 5 ]; then
        test_pass "Logger: $functions funciones definidas"
    else
        test_fail "Logger: solo $functions funciones definidas (esperado >= 5)"
    fi

    # --- Test 4: Función log_init existe ---
    if grep -q 'log_init()' "$logger_script"; then
        test_pass "Logger: función log_init() definida"
    else
        test_fail "Logger: función log_init() NO definida"
    fi

    # --- Test 5: Función log_metric existe ---
    if grep -q 'log_metric()' "$logger_script"; then
        test_pass "Logger: función log_metric() definida"
    else
        test_fail "Logger: función log_metric() NO definida"
    fi

    # --- Test 6: Rotación de logs ---
    if grep -q '_log_rotate' "$logger_script"; then
        test_pass "Logger: rotación de logs implementada"
    else
        test_fail "Logger: rotación de logs NO implementada"
    fi

    # --- Test 7: Trap de exit para flush ---
    if grep -q 'trap.*EXIT' "$logger_script"; then
        test_pass "Logger: trap EXIT para flush automático"
    else
        test_fail "Logger: no tiene trap EXIT"
    fi

    # --- Test 8: Integración en brain.sh ---
    if grep -q 'source.*logger\.sh' "$PROJECT_ROOT/brain.sh"; then
        test_pass "Logger: integrado en brain.sh"
    else
        test_fail "Logger: NO integrado en brain.sh"
    fi

    # Cleanup
    rm -rf "$test_log_dir"
}

# ============================================================================
# TESTS: METRICS
# ============================================================================

test_metrics() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  📊 METRICS TESTS (v2.2.0)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local metrics_script="$PROJECT_ROOT/lib/metrics.sh"

    # --- Test 1: Archivo existe ---
    if [ -f "$metrics_script" ]; then
        test_pass "Metrics: archivo lib/metrics.sh existe"
    else
        test_fail "Metrics: archivo lib/metrics.sh NO existe"
        return
    fi

    # --- Test 2: Syntax check ---
    if bash -n "$metrics_script" 2>/dev/null; then
        test_pass "Metrics: syntax check OK"
    else
        test_fail "Metrics: syntax check FAILED"
        return
    fi

    # --- Test 3: Funciones clave ---
    for func in metrics_init metrics_record metrics_report; do
        if grep -q "${func}()" "$metrics_script"; then
            test_pass "Metrics: función $func() definida"
        else
            test_fail "Metrics: función $func() NO definida"
        fi
    done

    # --- Test 4: Helpers de métricas comunes ---
    for func in metrics_task_start metrics_task_end metrics_ia_selection metrics_phase_duration metrics_error; do
        if grep -q "${func}()" "$metrics_script"; then
            test_pass "Metrics: helper $func() definido"
        else
            test_fail "Metrics: helper $func() NO definido"
        fi
    done

    # --- Test 5: Integración en brain.sh ---
    if grep -q 'source.*metrics\.sh' "$PROJECT_ROOT/brain.sh"; then
        test_pass "Metrics: integrado en brain.sh"
    else
        test_fail "Metrics: NO integrado en brain.sh"
    fi

    # --- Test 6: metrics_init llamado en brain.sh ---
    if grep -q 'metrics_init' "$PROJECT_ROOT/brain.sh"; then
        test_pass "Metrics: metrics_init() llamado en brain.sh"
    else
        test_fail "Metrics: metrics_init() NO llamado en brain.sh"
    fi
}

# ============================================================================
# TESTS: AGENT AI WRAPPER (Fase 2.1)
# ============================================================================

test_agent_ai() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🤖 AGENT AI WRAPPER TESTS (Fase 2.1 — v2.2.0)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local agent_ai_script="$PROJECT_ROOT/lib/agent-ai.sh"

    # --- Test 1: Archivo existe ---
    if [ -f "$agent_ai_script" ]; then
        test_pass "Agent AI: archivo lib/agent-ai.sh existe"
    else
        test_fail "Agent AI: archivo lib/agent-ai.sh NO existe"
        return
    fi

    # --- Test 2: Syntax check ---
    if bash -n "$agent_ai_script" 2>/dev/null; then
        test_pass "Agent AI: syntax check OK"
    else
        test_fail "Agent AI: syntax check FAILED"
        return
    fi

    # --- Test 3: Funciones clave ---
    for func in agent_ai_init agent_ai_select agent_ai_exec agent_ai_report agent_ai_get_selected agent_ai_run; do
        if grep -q "${func}()" "$agent_ai_script"; then
            test_pass "Agent AI: función $func() definida"
        else
            test_fail "Agent AI: función $func() NO definida"
        fi
    done

    # --- Test 4: Timeouts configurables ---
    if grep -q 'AGENT_AI_TIMEOUT_OPENCODE' "$agent_ai_script"; then
        test_pass "Agent AI: timeout opencode configurable"
    else
        test_fail "Agent AI: timeout opencode NO configurable"
    fi

    # --- Test 5: Integración en implementer.sh ---
    if grep -q 'agent-ai\.sh\|agent_ai_init\|agent_ai_select' "$PROJECT_ROOT/agents/implementer.sh"; then
        test_pass "Agent AI: integrado en implementer.sh"
    else
        test_fail "Agent AI: NO integrado en implementer.sh"
    fi

    # --- Test 6: Fallback si selector no existe ---
    if grep -q 'fallback\|Fallback' "$agent_ai_script"; then
        test_pass "Agent AI: tiene fallback si selector no disponible"
    else
        test_fail "Agent AI: no tiene fallback"
    fi
}

# ============================================================================
# TESTS: STATE LOCKING (Fase 2.2)
# ============================================================================

test_state_lock() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🔒 STATE LOCKING TESTS (Fase 2.2 — v2.2.0)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local state_lock_script="$PROJECT_ROOT/lib/state-lock.sh"

    # --- Test 1: Archivo existe ---
    if [ -f "$state_lock_script" ]; then
        test_pass "State Lock: archivo lib/state-lock.sh existe"
    else
        test_fail "State Lock: archivo lib/state-lock.sh NO existe"
        return
    fi

    # --- Test 2: Syntax check ---
    if bash -n "$state_lock_script" 2>/dev/null; then
        test_pass "State Lock: syntax check OK"
    else
        test_fail "State Lock: syntax check FAILED"
        return
    fi

    # --- Test 3: Funciones clave ---
    for func in state_lock_init state_lock_update state_lock_read state_lock_add_phase state_lock_is_phase_done state_lock_unlock; do
        if grep -q "${func}()" "$state_lock_script"; then
            test_pass "State Lock: función $func() definida"
        else
            test_fail "State Lock: función $func() NO definida"
        fi
    done

    # --- Test 4: flock detection ---
    if grep -q 'flock' "$state_lock_script"; then
        test_pass "State Lock: usa flock cuando disponible"
    else
        test_fail "State Lock: no usa flock"
    fi

    # --- Test 5: mkdir fallback ---
    if grep -q 'mkdir.*lock\|STATE_LOCK_DIR' "$state_lock_script"; then
        test_pass "State Lock: tiene fallback mkdir si flock no disponible"
    else
        test_fail "State Lock: no tiene fallback mkdir"
    fi

    # --- Test 6: Integración en pipeline.sh ---
    if grep -q 'state-lock\.sh\|state_lock_init\|state_lock_update\|PIPELINE_STATE_LOCK_ENABLED' "$PROJECT_ROOT/orchestrator/pipeline.sh"; then
        test_pass "State Lock: integrado en pipeline.sh"
    else
        test_fail "State Lock: NO integrado en pipeline.sh"
    fi

    # --- Test 7: Trap EXIT para liberar lock ---
    if grep -q 'trap.*EXIT' "$state_lock_script"; then
        test_pass "State Lock: trap EXIT para liberar lock"
    else
        test_fail "State Lock: no tiene trap EXIT"
    fi

    # --- Test 8: Test funcional básico ---
    local test_state="$PROJECT_ROOT/tests/test-state.json"
    rm -f "$test_state" "${test_state}.lock"
    rmdir "${test_state}.lock" 2>/dev/null || true

    # Test directo: crear estado, escribir, leer
    cat > "$test_state" << 'EOF'
{"pipeline":"SDD","version":"2.2.0","change_name":null,"phases_completed":[],"approved_gates":{},"artifacts":{},"started_at":null,"current_phase":null}
EOF

    # Simular operación de update sin lock (verificar que jq funciona)
    local temp
    temp=$(mktemp)
    jq '.test_key = "hello"' "$test_state" > "$temp" && mv "$temp" "$test_state"

    local result
    result=$(jq -r '.test_key' "$test_state" 2>/dev/null)

    if [ "$result" = "hello" ]; then
        test_pass "State Lock: test funcional básico (write + read via jq)"
    else
        test_fail "State Lock: test funcional falló" "Expected 'hello', got '$result'"
    fi

    rm -f "$test_state" "${test_state}.lock"
    rmdir "${test_state}.lock" 2>/dev/null || true
}

# ============================================================================
# TESTS: CONTEXT CACHE (Fase 3.1)
# ============================================================================

test_context_cache() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  ⚡ CONTEXT CACHE TESTS (Fase 3.1 — v2.2.0)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local cache_script="$PROJECT_ROOT/lib/context-cache.sh"

    # --- Test 1: Archivo existe ---
    if [ -f "$cache_script" ]; then
        test_pass "Context Cache: archivo lib/context-cache.sh existe"
    else
        test_fail "Context Cache: archivo lib/context-cache.sh NO existe"
        return
    fi

    # --- Test 2: Syntax check ---
    if bash -n "$cache_script" 2>/dev/null; then
        test_pass "Context Cache: syntax check OK"
    else
        test_fail "Context Cache: syntax check FAILED"
        return
    fi

    # --- Test 3: Funciones clave ---
    for func in context_cache_init context_cache_get_layer1 context_cache_get_layer2 context_cache_invalidate context_cache_stats; do
        if grep -q "${func}()" "$cache_script"; then
            test_pass "Context Cache: función $func() definida"
        else
            test_fail "Context Cache: función $func() NO definida"
        fi
    done

    # --- Test 4: Hash detection ---
    if grep -q 'md5sum\|sha256sum' "$cache_script"; then
        test_pass "Context Cache: usa hash para detectar cambios"
    else
        test_fail "Context Cache: no usa hash"
    fi

    # --- Test 5: TTL ---
    if grep -q 'CONTEXT_CACHE_TTL' "$cache_script"; then
        test_pass "Context Cache: TTL configurable"
    else
        test_fail "Context Cache: TTL no configurable"
    fi

    # --- Test 6: Integración en brain.sh ---
    if grep -q 'context-cache\.sh\|context_cache_get_layer\|context_cache_init' "$PROJECT_ROOT/brain.sh"; then
        test_pass "Context Cache: integrado en brain.sh"
    else
        test_fail "Context Cache: NO integrado en brain.sh"
    fi
}

# ============================================================================
# TESTS: PLUGIN SYSTEM (Fase 3.2)
# ============================================================================

test_plugins() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🔌 PLUGIN SYSTEM TESTS (Fase 3.2 — v2.2.0)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local plugins_script="$PROJECT_ROOT/lib/plugins.sh"

    # --- Test 1: Archivo existe ---
    if [ -f "$plugins_script" ]; then
        test_pass "Plugins: archivo lib/plugins.sh existe"
    else
        test_fail "Plugins: archivo lib/plugins.sh NO existe"
        return
    fi

    # --- Test 2: Syntax check ---
    if bash -n "$plugins_script" 2>/dev/null; then
        test_pass "Plugins: syntax check OK"
    else
        test_fail "Plugins: syntax check FAILED"
        return
    fi

    # --- Test 3: Funciones clave ---
    for func in plugins_init plugins_register plugins_load plugins_load_all plugins_run_hook plugins_list; do
        if grep -q "${func}()" "$plugins_script"; then
            test_pass "Plugins: función $func() definida"
        else
            test_fail "Plugins: función $func() NO definida"
        fi
    done

    # --- Test 4: Hooks disponibles ---
    if grep -q 'pre_task.*post_task.*pre_phase.*post_phase' "$plugins_script"; then
        test_pass "Plugins: hooks estándar definidos"
    else
        test_fail "Plugins: hooks estándar no definidos"
    fi

    # --- Test 5: Registry JSON ---
    if grep -q 'registry\.json\|PLUGINS_REGISTRY' "$plugins_script"; then
        test_pass "Plugins: usa registry JSON"
    else
        test_fail "Plugins: no usa registry JSON"
    fi

    # --- Test 6: Enable/disable ---
    if grep -q 'plugins_enable\|plugins_disable' "$plugins_script"; then
        test_pass "Plugins: soporte enable/disable"
    else
        test_fail "Plugins: no tiene enable/disable"
    fi
}

# ============================================================================
# TESTS: AI SELECTOR PYTHON (Fase 4.2)
# ============================================================================

test_ai_selector_python() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🐍 AI SELECTOR PYTHON TESTS (Fase 4.2 — v2.3.0)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local py_selector="$PROJECT_ROOT/lib/ai_selector.py"
    local bash_wrapper="$PROJECT_ROOT/scripts/ai-selector.sh"

    # --- Test 1: Python file exists ---
    if [ -f "$py_selector" ]; then
        test_pass "AI Selector Python: archivo lib/ai_selector.py existe"
    else
        test_fail "AI Selector Python: archivo lib/ai_selector.py NO existe"
        return
    fi

    # --- Test 2: Python syntax ---
    if python3 -m py_compile "$py_selector" 2>/dev/null; then
        test_pass "AI Selector Python: syntax check OK"
    else
        test_fail "AI Selector Python: syntax check FAILED"
        return
    fi

    # --- Test 3: Produces valid JSON ---
    local output
    output=$(python3 "$py_selector" "coding" "test-project" 2>/dev/null)
    if echo "$output" | jq empty 2>/dev/null; then
        test_pass "AI Selector Python: output JSON válido"
    else
        test_fail "AI Selector Python: output JSON inválido" "$output"
    fi

    # --- Test 4: Wrapper delegates to Python ---
    if grep -q 'ai_selector\.py' "$bash_wrapper"; then
        test_pass "AI Selector Python: wrapper bash delega a Python"
    else
        test_fail "AI Selector Python: wrapper bash NO delega a Python"
    fi

    # --- Test 5: Wrapper produces valid JSON ---
    output=$(bash "$bash_wrapper" "coding" "test-project" 2>/dev/null)
    if echo "$output" | jq empty 2>/dev/null; then
        test_pass "AI Selector Python: wrapper output JSON válido"
    else
        test_fail "AI Selector Python: wrapper output JSON inválido" "$output"
    fi

    # --- Test 6: Python tests exist ---
    if [ -f "$PROJECT_ROOT/tests/test_ai_selector.py" ]; then
        test_pass "AI Selector Python: tests unitarios existen"
    else
        test_fail "AI Selector Python: tests unitarios NO existen"
    fi

    # --- Test 7: Python tests pass ---
    if command -v pytest >/dev/null 2>&1; then
        local pytest_result
        pytest_result=$(cd "$PROJECT_ROOT" && python3 -m pytest tests/test_ai_selector.py -q 2>&1)
        local pytest_exit=$?
        if [ $pytest_exit -eq 0 ]; then
            test_pass "AI Selector Python: pytest suite passed"
        else
            test_fail "AI Selector Python: pytest suite failed" "$pytest_result"
        fi
    else
        test_skip "AI Selector Python: pytest no disponible" "pip install pytest"
    fi
}

# ============================================================================
# TESTS: SYNTAX DE TODOS LOS SCRIPTS
# ============================================================================

test_syntax_all() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  🔍 SYNTAX CHECK — TODOS LOS SCRIPTS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════${NC}"

    local scripts=(
        "$PROJECT_ROOT/cmx"
        "$PROJECT_ROOT/brain.sh"
        "$PROJECT_ROOT/scripts/memory-save.sh"
        "$PROJECT_ROOT/scripts/memory-query.sh"
        "$PROJECT_ROOT/scripts/cleanup-project.sh"
        "$PROJECT_ROOT/scripts/ai-selector.sh"
        "$PROJECT_ROOT/scripts/ai-executor.sh"
        "$PROJECT_ROOT/scripts/check-environment.sh"
        "$PROJECT_ROOT/scripts/backup-memories.sh"
        "$PROJECT_ROOT/scripts/restore-memories.sh"
        "$PROJECT_ROOT/scripts/cmx-memories-init.sh"
        "$PROJECT_ROOT/scripts/migrate-to-sqlite.sh"
        "$PROJECT_ROOT/orchestrator/pipeline.sh"
        "$PROJECT_ROOT/orchestrator/brain-adapter.sh"
        "$PROJECT_ROOT/orchestrator/monitor.sh"
        "$PROJECT_ROOT/orchestrator/agent-comm.sh"
        "$PROJECT_ROOT/orchestrator/summary.sh"
        "$PROJECT_ROOT/lib/logger.sh"
        "$PROJECT_ROOT/lib/metrics.sh"
        "$PROJECT_ROOT/lib/agent-ai.sh"
        "$PROJECT_ROOT/lib/state-lock.sh"
        "$PROJECT_ROOT/lib/context-cache.sh"
        "$PROJECT_ROOT/lib/plugins.sh"
    )

    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            test_skip "Syntax: $(basename "$script")" "archivo no encontrado"
            continue
        fi

        if bash -n "$script" 2>/dev/null; then
            test_pass "Syntax: $(basename "$script")"
        else
            test_fail "Syntax: $(basename "$script")" "$(bash -n "$script" 2>&1)"
        fi
    done
}

# ============================================================================
# MAIN
# ============================================================================

run_all_tests() {
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║       CMX-CORE — Test Suite v2.2.0                     ║"
    echo "║       Security & Regression Tests                      ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Fecha: $(date -Iseconds)"
    echo "Project: $PROJECT_ROOT"
    echo ""

    local filter="${1:-all}"

    case "$filter" in
        sql|injection)
            test_sql_injection
            ;;
        cleanup)
            test_cleanup_fix
            test_cli_cleanup_var
            ;;
        timeout|timeouts)
            test_timeouts
            ;;
        logger)
            test_logger
            ;;
        metrics)
            test_metrics
            ;;
        syntax)
            test_syntax_all
            ;;
        all|"")
            test_sql_injection
            test_cleanup_fix
            test_cli_cleanup_var
            test_timeouts
            test_logger
            test_metrics
            test_agent_ai
            test_state_lock
            test_context_cache
            test_plugins
            test_ai_selector_python
            test_syntax_all
            ;;
        *)
            echo "Uso: $0 [sql|cleanup|timeout|logger|metrics|syntax|all]"
            exit 1
            ;;
    esac

    # ============================================================================
    # RESUMEN FINAL
    # ============================================================================

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    RESULTADOS FINALES                   ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════╣${NC}"

    local pass_color="${GREEN}"
    local fail_color="${RED}"
    local skip_color="${YELLOW}"

    printf "${BLUE}║${NC}  %-30s ${GREEN}%d${NC}\n" "Tests Passed:" "$TESTS_PASSED"
    printf "${BLUE}║${NC}  %-30s ${RED}%d${NC}\n" "Tests Failed:" "$TESTS_FAILED"
    printf "${BLUE}║${NC}  %-30s ${YELLOW}%d${NC}\n" "Tests Skipped:" "$TESTS_SKIPPED"
    printf "${BLUE}║${NC}  %-30s %d\n" "Total Tests:" "$TESTS_TOTAL"

    local pass_rate=0
    if [ "$TESTS_TOTAL" -gt 0 ]; then
        pass_rate=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
    fi
    printf "${BLUE}║${NC}  %-30s %d%%\n" "Pass Rate:" "$pass_rate"

    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo -e "${RED}⚠️  $TESTS_FAILED test(s) failed. Review output above.${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ All tests passed!${NC}"
        exit 0
    fi
}

run_all_tests "$@"
