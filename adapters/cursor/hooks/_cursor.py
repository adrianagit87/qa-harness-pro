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

Como en los otros ports, la LOGICA vive en core/gates y aca solo se traduce el
contrato. Estos hooks corren sobre TODA llamada, asi que ABSTENERSE se proyecta
como silencio (ver core/gates/contract.py).
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

# Raiz del harness: se busca subiendo hasta la marca `core/gates/contract.py`, en
# vez de contar niveles. Este bootstrap esta inline a proposito: hace falta para
# poder importar `core` (incluido `core.raiz`), asi que no puede depender de el.
def _raiz_bootstrap() -> Path:
    for candidato in Path(__file__).resolve().parents:
        if (candidato / "core" / "gates" / "contract.py").is_file():
            return candidato
    raise RuntimeError(f"no encuentro la raiz del harness desde {__file__}")


HARNESS_ROOT = _raiz_bootstrap()
if str(HARNESS_ROOT) not in sys.path:
    sys.path.insert(0, str(HARNESS_ROOT))

PENDING = Path(
    os.environ.get("QA_HARNESS_PENDING_CHECK", Path.home() / ".cursor" / "qa-harness-pending-check.json")
)


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
