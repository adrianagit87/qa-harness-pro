#!/usr/bin/env python3
"""PreToolUse (Claude Code, matcher "Bash"): foto del disco antes de un comando de shell.

No es un gate: nunca deniega ni dice nada. Guarda, por (session_id, tool_use_id),
el estado de lo que gobierna post-edición, para que check-after-shell.py sepa
exactamente qué archivos escribió ESE comando (ver core/gates/post_shell).

Va en un hook aparte de block-destructive-command.py a propósito: aquel es un
gate que deniega; este es un registro que no puede fallar hacia la persona. Si
sacar la foto se traba (git lento, $TMPDIR lleno), no comparte proceso ni
timeout con el deny de lo destructivo.

Política: todo es silencio. Sin tool_use_id, raíz que no es git, carpeta de
fotos inusable o stdin ilegible -> no hay foto, y el post se abstiene. El deny
por entrada ilegible ya lo da block-destructive-command.py en el mismo evento.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _claude  # noqa: E402

from core.gates import post_shell  # noqa: E402


def main() -> int:
    payload = _claude.leer_payload()
    if payload is not None and _claude.lo_invoca_cursor(payload):
        _claude.ceder_a_cursor()
        return 0
    if payload is None or payload.get("tool_name") != "Bash":
        return 0
    post_shell.fotografiar(
        _claude.CARPETA_DE_FOTOS,
        post_shell.clave_de_llamada(payload.get("session_id"), payload.get("tool_use_id")),
        _claude.raiz_del_proyecto(payload),
        _claude.HARNESS_ROOT,
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:  # noqa: BLE001 — un registro nunca frena al agente
        raise SystemExit(0)
