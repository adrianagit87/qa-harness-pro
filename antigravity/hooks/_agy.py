"""Shim de compatibilidad Claude Code -> Antigravity.

Antigravity y Claude Code tienen contratos de hook distintos:

    Claude Code                        Antigravity
    payload["tool_name"]               payload["toolCall"]["name"]
    payload["tool_input"]              payload["toolCall"]["args"]
    {"hookSpecificOutput": {...}}      {"decision": ..., "reason": ...}

Este modulo traduce entre los dos y carga la LOGICA de los hooks originales
(hooks/*.py del harness) sin duplicarla: los patrones, las reglas y las claves
de contenido viven en un solo lugar. Si manana se agrega un placeholder al hook
original, este lo hereda sin tocar nada.

REGLA CRITICA: los hooks de Antigravity corren con matcher "*", o sea sobre
TODA llamada a herramienta. Por eso el default es NO OPINAR (stdout vacio).
Solo se emite una decision sobre las herramientas que este harness reconoce.
Un default restrictivo aca bloquearia el agente entero.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
from pathlib import Path
from typing import Any

# Raiz del harness: antigravity/hooks/_agy.py -> antigravity/ -> raiz
HARNESS_ROOT = Path(__file__).resolve().parent.parent.parent
ORIGINAL_HOOKS = HARNESS_ROOT / "hooks"

# Donde se anotan los nombres de herramienta que no reconocimos, para poder
# afinar los patrones sin adivinar.
UNKNOWN_LOG = Path(
    os.environ.get("QA_HARNESS_UNKNOWN_TOOLS_LOG", Path.home() / ".gemini" / "qa-harness-unknown-tools.log")
)


def load_original(filename: str):
    """Carga un hook original del harness como modulo (nombre con guiones)."""
    path = ORIGINAL_HOOKS / filename
    spec = importlib.util.spec_from_file_location(f"_orig_{filename.replace('-', '_')[:-3]}", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"no pude cargar {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_call() -> tuple[str, dict[str, Any]]:
    """Devuelve (nombre_de_tool, args). Ante entrada invalida, ('', {})."""
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError, ValueError):
        return "", {}
    call = payload.get("toolCall")
    if not isinstance(call, dict):
        return "", {}
    name = call.get("name")
    args = call.get("args")
    return (name if isinstance(name, str) else ""), (args if isinstance(args, dict) else {})


def decide(decision: str, reason: str) -> None:
    """Emite una decision. decision: allow | deny | ask | force_ask."""
    print(json.dumps({"decision": decision, "reason": reason}, ensure_ascii=False))


def abstain() -> None:
    """No opinar: stdout vacio. Es el default con matcher '*'."""
    return None


def note_unknown(tool_name: str, bucket: str) -> None:
    """Registra una herramienta que parecia relevante pero no matcheo ningun patron.

    Sirve para descubrir los nombres reales de las tools de Antigravity sin
    adivinar: se lee el log y se ajustan los patrones con datos, no con
    suposiciones.
    """
    if not tool_name:
        return
    try:
        UNKNOWN_LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(UNKNOWN_LOG, "a", encoding="utf-8") as handle:
            handle.write(f"{bucket}\t{tool_name}\n")
    except OSError:
        pass  # nunca romper el agente por no poder loguear
