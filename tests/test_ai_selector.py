#!/usr/bin/env python3
"""
CMX-CORE — Tests para AI Selector (Python)
v2.3.0

Uso:
    python -m pytest tests/test_ai_selector.py -v
"""

import json
import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch, MagicMock

# Agregar lib al path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "lib"))

import ai_selector


# ============================================================================
# FIXTURES
# ============================================================================

def get_test_registry():
    """Registry de prueba para tests."""
    return {
        "ias": {
            "opencode": {
                "status": "available",
                "type": "cli",
                "command": "opencode",
                "cost_level": 2,
                "cost_description": "Gratis",
                "capabilities": ["coding", "implementation", "debugging"],
                "best_for": ["implementation", "coding"],
                "default_model": "opencode/big-pickle"
            },
            "gemini": {
                "status": "available",
                "type": "cli",
                "command": "gemini",
                "cost_level": 1,
                "cost_description": "Gratis",
                "capabilities": ["analysis", "summarization"],
                "best_for": ["trivial tasks", "analysis"],
                "default_model": "gemini-2.0-flash"
            },
            "openrouter": {
                "status": "available",
                "type": "api",
                "requires_env": "OPENROUTER_API_KEY",
                "cost_level": 1,
                "capabilities": ["synthesis", "fallback"],
                "best_for": ["synthesis", "fallback"],
                "default_model": "deepseek-chat"
            },
            "ollama": {
                "status": "offline",
                "type": "cli",
                "command": "ollama",
                "cost_level": 5,
                "capabilities": ["local", "privacy"],
                "best_for": ["offline", "privacy"],
                "default_model": "llama3.2"
            }
        },
        "selection_rules": {
            "coding": ["opencode", "openrouter"],
            "analysis": ["gemini", "opencode"],
            "research": ["openrouter", "gemini"],
            "trivial": ["gemini", "openrouter"],
            "general": ["opencode", "gemini", "openrouter"]
        },
        "cost_based_selection": {
            "trivial_task_keywords": [
                "resumir", "listar", "verificar", "check", "status",
                "simple", "trivial", "básico", "count"
            ]
        },
        "retry_config": {
            "max_retries": 2,
            "delay_seconds": 3
        }
    }


# ============================================================================
# TESTS: CLASIFICACIÓN DE TAREAS
# ============================================================================

class TestTaskClassification:
    def test_coding_task(self):
        assert ai_selector.classify_task("crear una API REST") == "coding"

    def test_coding_task_english(self):
        assert ai_selector.classify_task("build a new component") == "coding"

    def test_analysis_task(self):
        assert ai_selector.classify_task("analizar el código existente") == "analysis"

    def test_analysis_task_bug(self):
        assert ai_selector.classify_task("debug this error") == "analysis"

    def test_research_task(self):
        assert ai_selector.classify_task("buscar documentación del proyecto") == "research"

    def test_general_task(self):
        assert ai_selector.classify_task("hacer algo random") == "general"


# ============================================================================
# TESTS: TRIVIALIDAD
# ============================================================================

class TestTrivialDetection:
    def test_trivial_task(self):
        registry = get_test_registry()
        assert ai_selector.is_task_trivial("resumir el código", registry) is True

    def test_trivial_task_check(self):
        registry = get_test_registry()
        assert ai_selector.is_task_trivial("check status", registry) is True

    def test_non_trivial_task(self):
        registry = get_test_registry()
        assert ai_selector.is_task_trivial("implementar sistema de autenticación", registry) is False


# ============================================================================
# TESTS: DISPONIBILIDAD
# ============================================================================

class TestAvailability:
    @patch("ai_selector._command_exists")
    def test_cli_available(self, mock_cmd):
        mock_cmd.return_value = True
        config = {
            "status": "available",
            "type": "cli",
            "command": "opencode"
        }
        assert ai_selector.is_ia_available("opencode", config) is True

    @patch("ai_selector._command_exists")
    def test_cli_not_available_command(self, mock_cmd):
        mock_cmd.return_value = False
        config = {
            "status": "available",
            "type": "cli",
            "command": "nonexistent"
        }
        assert ai_selector.is_ia_available("opencode", config) is False

    def test_cli_status_unavailable(self):
        config = {
            "status": "offline",
            "type": "cli",
            "command": "ollama"
        }
        assert ai_selector.is_ia_available("ollama", config) is False

    def test_api_with_env(self):
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": "test-key"}):
            config = {
                "status": "available",
                "type": "api",
                "requires_env": "OPENROUTER_API_KEY"
            }
            assert ai_selector.is_ia_available("openrouter", config) is True

    def test_api_without_env(self):
        with patch.dict(os.environ, {"OPENROUTER_API_KEY": ""}, clear=False):
            # Remover la variable si existe
            env_copy = {k: v for k, v in os.environ.items() if k != "OPENROUTER_API_KEY"}
            with patch.dict(os.environ, env_copy, clear=True):
                config = {
                    "status": "available",
                    "type": "api",
                    "requires_env": "OPENROUTER_API_KEY"
                }
                assert ai_selector.is_ia_available("openrouter", config) is False


# ============================================================================
# TESTS: SELECCIÓN
# ============================================================================

class TestSelection:
    @patch("ai_selector._command_exists")
    @patch("ai_selector._count_previous_decisions")
    def test_select_coding(self, mock_decisions, mock_cmd):
        mock_cmd.return_value = True
        mock_decisions.return_value = 0

        registry = get_test_registry()
        result = ai_selector.select_ai("coding", "test-project", registry)

        assert result["status"] == "selected"
        assert result["ia"] == "opencode"
        assert result["task_type"] == "coding"
        assert result["cost_level"] == 2

    @patch("ai_selector._command_exists")
    @patch("ai_selector._count_previous_decisions")
    def test_select_trivial(self, mock_decisions, mock_cmd):
        mock_cmd.return_value = True
        mock_decisions.return_value = 0

        registry = get_test_registry()
        result = ai_selector.select_ai("trivial", "test-project", registry)

        assert result["status"] == "selected"
        assert result["ia"] == "gemini"
        assert result["task_type"] == "trivial"
        assert result["cost_level"] == 1

    @patch("ai_selector._command_exists")
    @patch("ai_selector._count_previous_decisions")
    def test_fallback_chain(self, mock_decisions, mock_cmd):
        # Solo gemini disponible, opencode no
        def mock_cmd_side_effect(cmd):
            return cmd == "gemini"

        mock_cmd.side_effect = mock_cmd_side_effect
        mock_decisions.return_value = 0

        registry = get_test_registry()
        result = ai_selector.select_ai("coding", "test-project", registry)

        assert result["status"] == "selected"
        assert result["ia"] == "gemini"  # opencode no disponible, gemini es fallback
        assert "opencode" in result["fallback_chain"]


# ============================================================================
# TESTS: INTEGRATION (CLI)
# ============================================================================

class TestCLI:
    def test_python_selector_runs(self):
        """Verifica que el script Python se ejecuta correctamente."""
        selector_path = PROJECT_ROOT / "lib" / "ai_selector.py"
        if not selector_path.exists():
            return  # Skip si no existe

        result = subprocess.run(
            [sys.executable, str(selector_path), "coding", "test-project"],
            capture_output=True,
            text=True,
            timeout=10
        )

        # Debería producir JSON válido
        try:
            output = json.loads(result.stdout)
            assert "ia" in output or "error" in output
        except json.JSONDecodeError:
            assert False, f"Output no es JSON válido: {result.stdout}"

    def test_wrapper_script(self):
        """Verifica que el wrapper bash delega a Python."""
        wrapper_path = PROJECT_ROOT / "scripts" / "ai-selector.sh"
        if not wrapper_path.exists():
            return

        result = subprocess.run(
            ["bash", str(wrapper_path), "coding", "test-project"],
            capture_output=True,
            text=True,
            timeout=10
        )

        # Debería producir JSON válido
        try:
            output = json.loads(result.stdout)
            assert "ia" in output or "error" in output
        except json.JSONDecodeError:
            assert False, f"Wrapper output no es JSON válido: {result.stdout}"
