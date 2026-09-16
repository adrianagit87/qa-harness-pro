#!/usr/bin/env python3
"""beforeMCPExecution (Cursor): gate de publicaciones externas.

Cursor solo implementa "deny" en este evento -- no hay "ask". La confirmacion
interactiva la pone el propio allowlist de MCP de Cursor. Este hook aporta lo
que Cursor no puede saber: si el CONTENIDO que se va a publicar esta completo.

Politica:
  - transiciones de Jira            -> deny siempre
  - escritura externa con placeholder -> deny
  - escritura externa limpia          -> pasa (Cursor pide su propia aprobacion)

Reusa PLACEHOLDERS y publication_content() del hook original del harness.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _cursor  # noqa: E402

_orig = _cursor.load_original("validate-external-write.py")
PLACEHOLDERS = _orig.PLACEHOLDERS
publication_content = _orig.publication_content


def _rx(*parts: str) -> re.Pattern[str]:
    return re.compile("|".join(parts), re.IGNORECASE)


FORBIDDEN = _rx(r"transition[_\-]?jira", r"jira.*transition")

EXTERNAL_WRITE = _rx(
    r"add[_\-]?comment.*jira", r"jira.*add[_\-]?comment",
    r"create[_\-]?jira[_\-]?issue", r"jira.*create.*issue",
    r"edit[_\-]?jira[_\-]?issue", r"jira.*edit.*issue", r"jira.*update.*issue",
    r"create[_\-]?confluence[_\-]?page", r"confluence.*create.*page",
    r"update[_\-]?confluence[_\-]?page", r"confluence.*update.*page",
    r"notion.*create", r"notion.*update", r"create.*notion", r"update.*notion",
)


def main() -> int:
    payload = _cursor.read_payload()
    name = payload.get("tool_name")
    if not isinstance(name, str) or not name:
        return 0

    if FORBIDDEN.search(name):
        _cursor.decide(
            "deny",
            "Quality gate: cambiar el estado de un ticket de Jira esta prohibido en este harness. "
            "Eso lo hace la persona a mano, siempre.",
        )
        return 0

    if not EXTERNAL_WRITE.search(name):
        return 0

    args = _cursor.tool_args(payload)
    pieces = [p.strip() for p in publication_content(args) if p.strip()]
    if not pieces:
        _cursor.decide("deny", "Quality gate: no encontre contenido publicable en el payload; se bloquea por seguridad.")
        return 0

    combined = "\n".join(pieces)
    if len(combined) < 3:
        _cursor.decide("deny", "Quality gate: el contenido esta vacio o es demasiado corto para verificarse.")
        return 0

    for pattern in PLACEHOLDERS:
        match = pattern.search(combined)
        if match:
            _cursor.decide("deny", f"Quality gate: quedo un placeholder sin resolver ({match.group(0)!r}).")
            return 0

    return 0  # contenido limpio: Cursor pide su propia aprobacion


if __name__ == "__main__":
    raise SystemExit(main())
