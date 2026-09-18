"""Contrato de hooks de Claude Code: leer stdin, proyectar el veredicto.

    PreToolUse   in : {"tool_name": str, "tool_input": dict, "cwd": str}
                 out: {"hookSpecificOutput": {"permissionDecision": "deny", ...}}

    PostToolUse  in : {"tool_name": str, "tool_input": dict}
                 out: {"decision": "block", "reason": str}

Claude Code engancha cada hook por matcher en `.claude/settings.json`, así que
acá ABSTENERSE se proyecta como bloqueo: una herramienta inesperada solo puede
venir de una configuración rota (ver `core/gates/contract.py`).

Este módulo también pone la raíz del harness en `sys.path` para que los hooks
corran como scripts sueltos, sin paso de instalación.
"""

from __future__ import annotations

import json
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

MAX_FEEDBACK = 4000


def leer_payload() -> dict[str, Any] | None:
    """Payload del hook, o None si la entrada es ilegible."""
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError, ValueError):
        return None
    return payload if isinstance(payload, dict) else None


def denegar(mensaje: str) -> None:
    """PreToolUse: deny con el motivo visible para la persona."""
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": mensaje,
                }
            },
            ensure_ascii=False,
        )
    )


def frenar(mensaje: str) -> None:
    """PostToolUse: block, con el feedback que vuelve al modelo."""
    print(json.dumps({"decision": "block", "reason": mensaje[-MAX_FEEDBACK:]}, ensure_ascii=False))
