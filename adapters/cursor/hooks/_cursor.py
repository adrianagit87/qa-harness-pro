"""Shim de compatibilidad Claude Code -> Cursor.

Contrato de Cursor (verificado leyendo el binario de Cursor.app, no adivinado):

    beforeShellExecution  in : {"command": str, "cwd": str, ...}
                          out: {"permission": "deny"|"ask", "user_message": str}

    beforeMCPExecution    in : {"tool_name": str, "tool_input": str-JSON, ...}
                          out: {"permission": "deny", "user_message": str}
                          OJO: aca "ask" NO esta implementado -- solo "deny".

    afterFileEdit         in : {"file_path": str, "edits": [...]}
                          out: ignorado (no puede bloquear)

    preToolUse            in : {"tool_name", "tool_input", "tool_use_id",
                                "conversation_id", "cwd", ...}
    postToolUse           in : lo mismo + "tool_output"
                          out: {"additional_context": str}
    postToolUseFailure    in : lo mismo + "error_message", "failure_type"
                          out: {"additional_context": str}
                          Matcher: regex contra tool_name; la terminal es
                          "Shell". tool_use_id sale del mismo toolCallId en
                          pre y post (Cursor 3.21.9, bundle cursor-agent-exec):
                          es lo que une la foto con su check.

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
# poder importar `core`, asi que no puede depender de nada que viva ahi adentro.
def _raiz_bootstrap() -> Path:
    for candidato in Path(__file__).resolve().parents:
        if (candidato / "core" / "gates" / "contract.py").is_file():
            return candidato
    raise RuntimeError(f"no encuentro la raiz del harness desde {__file__}")


HARNESS_ROOT = _raiz_bootstrap()
if str(HARNESS_ROOT) not in sys.path:
    sys.path.insert(0, str(HARNESS_ROOT))

# Donde espera la foto del disco entre el preToolUse y el postToolUse de un
# comando de shell: $TMPDIR/qa-harness-cursor (ver core/gates/post_shell).
SNAPSHOT_DIR = "qa-harness-cursor"

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


def add_context(message: str) -> None:
    """postToolUse / postToolUseFailure: texto que Cursor agrega a la conversacion,
    despues del resultado de la herramienta. No bloquea: la herramienta ya corrio."""
    print(json.dumps({"additional_context": message}, ensure_ascii=False))


def project_root() -> Path:
    """Raiz contra la que corren los checks post-edicion (la misma que afterFileEdit).

    Los hooks de ~/.cursor/hooks.json son globales: corren en cualquier proyecto.
    Por eso la raiz es la del harness (o la que fije QA_HARNESS_ROOT).
    """
    return Path(os.environ.get("QA_HARNESS_ROOT") or HARNESS_ROOT).resolve()


def abstain() -> None:
    """Sin opinion: stdout vacio. Cursor sigue con su flujo normal."""
    return None
