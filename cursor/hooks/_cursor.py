"""Shim de compatibilidad Claude Code -> Cursor.

Contrato de Cursor (verificado leyendo el binario de Cursor.app, no adivinado):

    beforeShellExecution  in : {"command": str, "cwd": str, ...}
                          out: {"permission": "deny"|"ask", "user_message": str}

    beforeMCPExecution    in : {"tool_name": str, "tool_input": str-JSON, ...}
                          out: {"permission": "deny", "user_message": str}
                          OJO: aca "ask" NO esta implementado -- solo "deny".

    afterFileEdit         in : {"file_path": str, "edits": [...]}
                          out: ignorado (no puede bloquear)

Diferencias con Claude Code que importan:
  - tool_input llega como STRING JSON, no como objeto.
  - la respuesta usa "permission"/"user_message", no hookSpecificOutput.
  - no hay un evento que pueda pedir confirmacion sobre MCP.

Como en los otros ports, la LOGICA vive en los hooks originales del harness
(hooks/*.py) y aca solo se traduce el contrato.
"""

from __future__ import annotations

import importlib.util
import json
import os
import sys
from pathlib import Path
from typing import Any

HARNESS_ROOT = Path(__file__).resolve().parent.parent.parent
ORIGINAL_HOOKS = HARNESS_ROOT / "hooks"

PENDING = Path(
    os.environ.get("QA_HARNESS_PENDING_CHECK", Path.home() / ".cursor" / "qa-harness-pending-check.json")
)


def load_original(filename: str):
    path = ORIGINAL_HOOKS / filename
    spec = importlib.util.spec_from_file_location(f"_orig_{filename.replace('-', '_')[:-3]}", path)
    if spec is None or spec.loader is None:
        raise ImportError(f"no pude cargar {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_payload() -> dict[str, Any]:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def tool_args(payload: dict[str, Any]) -> dict[str, Any]:
    """tool_input viene como string JSON en beforeMCPExecution."""
    raw = payload.get("tool_input")
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
        except (json.JSONDecodeError, ValueError):
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}


def decide(permission: str, message: str) -> None:
    """permission: deny | ask  (ask solo lo respeta beforeShellExecution)."""
    print(json.dumps({"permission": permission, "user_message": message}, ensure_ascii=False))


def abstain() -> None:
    """Sin opinion: stdout vacio. Cursor sigue con su flujo normal."""
    return None
