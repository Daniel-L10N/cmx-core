#!/usr/bin/env python3
"""
CMX-CORE — AI Selector (Python)
v2.3.0

Selecciona la mejor IA basada en tipo de tarea, costo y disponibilidad.
Reemplazo del ai-selector.sh con mejor manejo de JSON, regex y errores.

Uso:
    python3 lib/ai_selector.py <task-type> [project] [--json]
    python3 lib/ai_selector.py coding cmx-core
    python3 lib/ai_selector.py analysis --json

Salida: JSON estructurado con la IA seleccionada, fallback chain y razón.
"""

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


# ============================================================================
# CONFIGURACIÓN
# ============================================================================

def get_project_root() -> Path:
    """Detecta el project root desde la ubicación de este script."""
    return Path(__file__).resolve().parent.parent


def load_registry(project_root: Path) -> dict:
    """Carga el registro de IAs desde config/ai-registry.json."""
    registry_file = project_root / "config" / "ai-registry.json"
    if not registry_file.exists():
        return {"error": "Registry not found", "ias": {}}

    with open(registry_file, "r") as f:
        return json.load(f)


def load_env(project_root: Path) -> None:
    """Carga variables de entorno desde .env si existe."""
    env_file = project_root / ".env"
    if not env_file.exists():
        return

    with open(env_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key not in os.environ:
                os.environ[key] = value


# ============================================================================
# VERIFICACIÓN DE DISPONIBILIDAD
# ============================================================================

def is_ia_available(ia_name: str, ia_config: dict) -> bool:
    """Verifica si una IA está disponible (comando o API key)."""
    status = ia_config.get("status", "unavailable")
    if status != "available":
        return False

    ia_type = ia_config.get("type", "cli")

    if ia_type in ("cli", "cli-direct"):
        command = ia_config.get("command", "")
        if not command:
            return False
        # Verificar que el comando existe en PATH
        return _command_exists(command)

    elif ia_type == "api":
        requires_env = ia_config.get("requires_env", "")
        if requires_env:
            return bool(os.environ.get(requires_env, ""))
        return False

    return False


def _command_exists(command: str) -> bool:
    """Verifica si un comando existe en PATH."""
    # Para comandos con subcomandos (ej: "opencode run"), verificar solo el binario
    binary = command.split()[0]
    result = subprocess.run(
        ["which", binary],
        capture_output=True,
        text=True
    )
    return result.returncode == 0


# ============================================================================
# ANÁLISIS DE TAREA
# ============================================================================

def is_task_trivial(task_type: str, registry: dict) -> bool:
    """Detecta si una tarea es trivial basada en keywords del registry."""
    keywords = registry.get("cost_based_selection", {}).get("trivial_task_keywords", [])
    if not keywords:
        return False

    pattern = "|".join(re.escape(kw) for kw in keywords)
    return bool(re.search(pattern, task_type, re.IGNORECASE))


def classify_task(task_input: str) -> str:
    """Clasifica la tarea por tipo basado en contenido."""
    task_lower = task_input.lower()

    coding_patterns = [
        r"(crear|implementar|escribir|codificar|build|make|add|new|function|api|endpoint|component)"
    ]
    analysis_patterns = [
        r"(analizar|revisar|debug|error|bug|investigar|examinar|review)"
    ]
    research_patterns = [
        r"(buscar|investigar|research|document|explorar)"
    ]

    for pattern in coding_patterns:
        if re.search(pattern, task_lower):
            return "coding"

    for pattern in analysis_patterns:
        if re.search(pattern, task_lower):
            return "analysis"

    for pattern in research_patterns:
        if re.search(pattern, task_lower):
            return "research"

    return "general"


# ============================================================================
# SELECCIÓN
# ============================================================================

def select_ai(task_type: str, project: str, registry: dict) -> dict:
    """Selecciona la mejor IA para el tipo de tarea."""
    original_task = task_type
    task_type_normalized = task_type

    # Detectar trivialidad
    is_trivial = is_task_trivial(task_type, registry)
    if is_trivial:
        task_type_normalized = "trivial"

    # Obtener reglas de selección
    selection_rules = registry.get("selection_rules", {})
    preferred_ias = selection_rules.get(task_type_normalized, selection_rules.get("general", []))

    # Intentar cada IA en orden de prioridad
    selected_ia = None
    fallback_chain = []
    reason = ""
    model = ""
    cost_level = 3
    capabilities = "general"
    best_for = "general"

    for ia_name in preferred_ias:
        ia_config = registry.get("ias", {}).get(ia_name, {})

        if is_ia_available(ia_name, ia_config):
            selected_ia = ia_name
            capabilities = ", ".join(ia_config.get("capabilities", ["general"]))
            best_for = ", ".join(ia_config.get("best_for", ["general"]))
            cost_level = ia_config.get("cost_level", 3)
            cost_desc = ia_config.get("cost_description", "")
            model = ia_config.get("default_model", "")

            if is_trivial:
                reason = (
                    f"Tarea trivial - seleccionado {ia_name} por eficiencia "
                    f"(cost level {cost_level})"
                )
            else:
                reason = (
                    f"Seleccionado {ia_name} para tarea '{original_task}' - "
                    f"óptimo para: {best_for}"
                )

            if cost_desc:
                reason += f". Costo: {cost_desc}"

            break
        else:
            fallback_chain.append(ia_name)

    # Fallback de emergencia
    if not selected_ia:
        if _command_exists("opencode"):
            selected_ia = "opencode"
            model = registry.get("ias", {}).get("opencode", {}).get("default_model", "opencode/big-pickle")
            reason = "Fallback de emergencia - usando OpenCode"
        elif _command_exists("gemini"):
            selected_ia = "gemini"
            model = registry.get("ias", {}).get("gemini", {}).get("default_model", "gemini-2.0-flash")
            reason = "Fallback de emergencia - usando Gemini CLI"
        else:
            return {
                "status": "error",
                "error": "No hay proveedores AI disponibles",
                "ia": None,
                "fallback": None,
                "timestamp": datetime.now(timezone.utc).isoformat()
            }

        cost_level = registry.get("ias", {}).get(selected_ia, {}).get("cost_level", 3)
        capabilities = ", ".join(
            registry.get("ias", {}).get(selected_ia, {}).get("capabilities", ["general"])
        )
        best_for = ", ".join(
            registry.get("ias", {}).get(selected_ia, {}).get("best_for", ["general"])
        )

    # Contar decisiones previas (si la DB existe)
    previous_decisions = _count_previous_decisions(project)
    if previous_decisions > 0:
        reason += f" (proyecto tiene {previous_decisions} decisiones previas)"

    return {
        "status": "selected",
        "task_type": task_type_normalized,
        "original_task": original_task,
        "ia": selected_ia,
        "model": model,
        "cost_level": cost_level,
        "reason": reason,
        "capabilities": capabilities,
        "best_for": best_for,
        "fallback_chain": fallback_chain,
        "project": project,
        "previous_decisions": previous_decisions,
        "timestamp": datetime.now(timezone.utc).isoformat()
    }


def _count_previous_decisions(project: str) -> int:
    """Cuenta decisiones previas del proyecto en la DB SQLite."""
    project_root = get_project_root()
    db_file = project_root / "memories.db"

    if not db_file.exists():
        return 0

    try:
        import sqlite3
        conn = sqlite3.connect(str(db_file))
        cursor = conn.cursor()
        cursor.execute(
            "SELECT COUNT(*) FROM memories WHERE project = ? AND type = 'decision'",
            (project,)
        )
        count = cursor.fetchone()[0]
        conn.close()
        return count
    except Exception:
        return 0


# ============================================================================
# MAIN
# ============================================================================

def main():
    args = sys.argv[1:]

    if not args:
        print(json.dumps({
            "error": "Uso: ai_selector.py <task-type> [project]",
            "ia": None
        }, indent=2))
        sys.exit(1)

    task_type = args[0]
    project = args[1] if len(args) > 1 else "cmx-core"

    project_root = get_project_root()
    load_env(project_root)
    registry = load_registry(project_root)

    if "error" in registry:
        print(json.dumps(registry, indent=2))
        sys.exit(1)

    result = select_ai(task_type, project, registry)
    print(json.dumps(result, indent=2, ensure_ascii=False))

    if result.get("status") == "error":
        sys.exit(1)


if __name__ == "__main__":
    main()
