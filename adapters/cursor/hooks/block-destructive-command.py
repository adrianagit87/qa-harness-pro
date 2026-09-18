#!/usr/bin/env python3
"""beforeShellExecution (Cursor): bloquea comandos destructivos.

Ademas levanta la falla que haya dejado check-after-edit.py, porque
afterFileEdit no puede darle feedback al agente.

La decision vive en core/gates/destructivos; aca solo se traduce el contrato.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _cursor  # noqa: E402

from core.gates import destructivos  # noqa: E402
from core.texto import sin_acentos  # noqa: E402


def surface_pending() -> bool:
    """Devuelve True si emitio una decision por un check pendiente."""
    if not _cursor.PENDING.is_file():
        return False
    try:
        reason = json.loads(_cursor.PENDING.read_text(encoding="utf-8")).get("reason", "")
    except (OSError, json.JSONDecodeError, ValueError):
        reason = ""
    try:
        _cursor.PENDING.unlink()
    except OSError:
        pass
    if not reason:
        return False
    _cursor.decide("ask", f"Quality gate post-edit: {reason}")
    return True


def main() -> int:
    payload = _cursor.read_payload()
    command = payload.get("command")

    # Sin comando legible no hay nada que revisar: Cursor ya lo rechazara por su
    # cuenta y el aviso pendiente sigue siendo util.
    if isinstance(command, str) and command.strip():
        veredicto = destructivos.revisar_comando(command)
        if veredicto.bloquea:
            _cursor.decide("deny", f"Quality gate: {sin_acentos(veredicto.motivo)} bloqueado.")
            return 0

    surface_pending()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
