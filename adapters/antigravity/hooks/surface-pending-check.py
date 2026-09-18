#!/usr/bin/env python3
"""PreToolUse (Antigravity): levanta la falla que dejo check-after-edit.py.

Existe porque el PostToolUse de Antigravity no puede devolverle feedback al
agente (solo acepta {}). Este hook lee la marca pendiente, la convierte en un
"ask" con el detalle, y la limpia.

Efecto: si una edicion rompio los tests o la sintaxis, la proxima accion del
agente se detiene y te muestra que fue. El gate llega un turno tarde, pero
llega.

Matcher: "*". Default: no opinar.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _agy  # noqa: E402

PENDING = Path(
    os.environ.get("QA_HARNESS_PENDING_CHECK", Path.home() / ".gemini" / "qa-harness-pending-check.json")
)


def main() -> int:
    if not PENDING.is_file():
        return 0

    try:
        reason = json.loads(PENDING.read_text(encoding="utf-8")).get("reason", "")
    except (OSError, json.JSONDecodeError, ValueError):
        reason = ""

    try:
        PENDING.unlink()  # se consume una sola vez
    except OSError:
        pass

    if not reason:
        return 0

    _agy.decide("ask", f"Quality gate post-edit: {reason}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
