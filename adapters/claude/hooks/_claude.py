"""Contrato de hooks de Claude Code: leer stdin, proyectar el veredicto.

    PreToolUse   in : {"tool_name": str, "tool_input": dict, "cwd": str}
                 out: {"hookSpecificOutput": {"permissionDecision": "deny", ...}}

    PostToolUse  in : {"tool_name": str, "tool_input": dict}
                 out: {"decision": "block", "reason": str}

    PostToolUseFailure  in : lo mismo + "error"   (la herramienta falló: en
                             Bash, por ejemplo, un exit != 0)
                        out: {"hookSpecificOutput": {"hookEventName": ...,
                              "additionalContext": str}}   (no hay block)

    Los tres traen "session_id" y "tool_use_id": es lo que une la foto del
    PreToolUse Bash con su post (ver check-after-shell.py).

Claude Code engancha cada hook por matcher en `.claude/settings.json`, así que
acá ABSTENERSE se proyecta como bloqueo: una herramienta inesperada solo puede
venir de una configuración rota (ver `core/gates/contract.py`). La excepción es
el gate de la terminal: ahí abstenerse es "no hay un antes confiable", que no
se distingue de "el comando no escribió nada" (ver check-after-shell.py).

Cursor también puede correr estos hooks: con "Include Third-Party Plugins,
Skills, and Other Configs" prendido (viene prendido), carga los hooks de
`.claude/settings.json` (del proyecto y de ~/.claude) y los dispara con SU
payload: `hook_event_name` en camelCase, `tool_name: "Shell"` y un
`cursor_version` que Claude Code nunca manda. Ahí este adaptador se hace a un
lado (ver `lo_invoca_cursor`): ese runtime ya lo gobiernan los hooks de
`adapters/cursor/`, y el fail-closed de acá frenaría cada comando de shell.

Este módulo también pone la raíz del harness en `sys.path` para que los hooks
corran como scripts sueltos, sin paso de instalación.
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

MAX_FEEDBACK = 4000

# Donde espera la foto del disco entre el PreToolUse y el post de un comando de
# shell: $TMPDIR/qa-harness-claude (ver core/gates/post_shell).
CARPETA_DE_FOTOS = "qa-harness-claude"


def leer_payload() -> dict[str, Any] | None:
    """Payload del hook, o None si la entrada es ilegible."""
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError, ValueError):
        return None
    return payload if isinstance(payload, dict) else None


# Los eventos con los que Cursor dispara un hook de Claude Code: PreToolUse y
# PostToolUse se traducen a preToolUse y postToolUse (PostToolUseFailure Cursor
# no lo traduce hoy, pero su evento propio se llama así). Leído del bundle de
# Cursor 3.21.9 (ver adapters/cursor/README.md, "Si Cursor carga los hooks de
# Claude Code").
EVENTOS_DE_CURSOR = frozenset({"preToolUse", "postToolUse", "postToolUseFailure"})


def lo_invoca_cursor(payload: dict[str, Any]) -> bool:
    """¿Este hook lo disparó Cursor y no Claude Code?

    Hacen falta las dos marcas, las dos puestas por el ejecutor de hooks de
    Cursor en el payload mismo: `cursor_version` (Claude Code no lo manda) y el
    evento en camelCase (Claude Code manda PreToolUse). No se mira el entorno:
    CURSOR_VERSION también lo pone Cursor, pero una variable se hereda (un
    Claude Code lanzado desde una terminal de Cursor), y equivocarse acá es
    abrir un gate. Tampoco alcanza `tool_name` solo: "Shell" en un payload de
    Claude Code es una config rota, y eso tiene que seguir frenando.
    """
    return isinstance(payload.get("cursor_version"), str) and payload.get("hook_event_name") in EVENTOS_DE_CURSOR


def ceder_a_cursor() -> None:
    """Bajo Cursor, allow sin opinión: `{}` es una respuesta válida y vacía para
    Cursor (un stdout vacío lo registra como hook fallido)."""
    print("{}")


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


def agregar_contexto(evento: str, mensaje: str) -> None:
    """PostToolUseFailure: no hay block (la herramienta ya falló); el texto va como contexto."""
    print(
        json.dumps(
            {"hookSpecificOutput": {"hookEventName": evento, "additionalContext": mensaje[-MAX_FEEDBACK:]}},
            ensure_ascii=False,
        )
    )


def raiz_del_proyecto(payload: dict[str, Any]) -> Any:
    """La raíz abierta: CLAUDE_PROJECT_DIR, o el cwd del payload si no está."""
    return os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd")
