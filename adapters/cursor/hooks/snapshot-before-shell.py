#!/usr/bin/env python3
"""preToolUse (Cursor, matcher "Shell"): foto del disco antes de un comando de shell.

No es un gate: nunca deniega ni dice nada (stdout vacio = Cursor sigue su flujo).
Guarda, por (conversation_id, tool_use_id), el estado de lo que gobierna
post-edicion, para que check-after-shell.py sepa exactamente que archivos
escribio ESE comando (ver core/gates/post_shell).

El deny de lo destructivo sigue en block-destructive-command.py
(beforeShellExecution): este hook no puede fallar hacia la persona.

Politica: todo es silencio. Sin tool_use_id, raiz que no es git, carpeta de
fotos inusable o stdin ilegible -> no hay foto, y el post se abstiene.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _cursor  # noqa: E402

from core.gates import post_shell  # noqa: E402


def main() -> int:
    payload = _cursor.read_payload()
    if payload.get("tool_name") != "Shell":
        return 0
    post_shell.fotografiar(
        _cursor.SNAPSHOT_DIR,
        post_shell.clave_de_llamada(payload.get("conversation_id"), payload.get("tool_use_id")),
        _cursor.project_root(),
        _cursor.HARNESS_ROOT,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:  # noqa: BLE001 — un registro nunca frena al agente
        raise SystemExit(0)
