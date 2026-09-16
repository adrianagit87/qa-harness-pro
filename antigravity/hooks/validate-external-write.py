#!/usr/bin/env python3
"""PreToolUse (Antigravity): gate de publicaciones externas (Jira/Confluence/Notion).

Hace DOS cosas que en Claude Code estaban separadas:

  1. Lo que hacia el bloque `permissions` de settings.json:
     - transitionJiraIssue  -> deny (nadie cambia estados de tickets)
     - escrituras externas  -> force_ask (confirmacion explicita SIEMPRE,
       ignorando el cache de "Always Allow")
  2. Lo que hacia el hook original: validar que el payload no lleve
     placeholders sin resolver.

Reusa PLACEHOLDERS, CONTENT_KEYS y publication_content() del hook original.

Matcher: "*". Por eso el default es NO OPINAR -- solo intervenimos sobre
herramientas que reconocemos como escritura externa.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _agy  # noqa: E402

_orig = _agy.load_original("validate-external-write.py")
PLACEHOLDERS = _orig.PLACEHOLDERS
publication_content = _orig.publication_content

# Los nombres de las tools MCP en Antigravity no estan documentados, asi que se
# reconocen por patron sobre el nombre completo -- no por igualdad exacta.
# Cubre mcp__atlassian__createJiraIssue, atlassian.createJiraIssue,
# atlassian_create_jira_issue y variantes.
def _rx(*parts: str) -> re.Pattern[str]:
    return re.compile("|".join(parts), re.IGNORECASE)

# Nunca, bajo ninguna circunstancia: cambiar el estado de un ticket.
FORBIDDEN = _rx(r"transition[_\-]?jira", r"jira.*transition")

# Escrituras que exigen confirmacion explicita del usuario.
EXTERNAL_WRITE = _rx(
    r"add[_\-]?comment.*jira", r"jira.*add[_\-]?comment",
    r"create[_\-]?jira[_\-]?issue", r"jira.*create.*issue",
    r"edit[_\-]?jira[_\-]?issue", r"jira.*edit.*issue", r"jira.*update.*issue",
    r"create[_\-]?confluence[_\-]?page", r"confluence.*create.*page",
    r"update[_\-]?confluence[_\-]?page", r"confluence.*update.*page",
    r"notion.*create", r"notion.*update", r"create.*notion", r"update.*notion",
)

# Cosas que rozan Jira/Confluence/Notion pero son LECTURA: no se tocan.
READ_ONLY = _rx(
    r"get[_\-]", r"search", r"fetch", r"list[_\-]", r"read[_\-]", r"view[_\-]", r"lookup",
)


def main() -> int:
    name, args = _agy.read_call()
    if not name:
        return 0

    if FORBIDDEN.search(name):
        _agy.decide(
            "deny",
            "Quality gate: cambiar el estado de un ticket de Jira esta prohibido en este harness. "
            "Eso lo hace la persona a mano, siempre.",
        )
        return 0

    if not EXTERNAL_WRITE.search(name):
        # Si huele a Atlassian/Notion pero no matcheo ningun patron de escritura
        # ni de lectura, lo anotamos para poder afinar con datos reales.
        if re.search(r"atlassian|jira|confluence|notion", name, re.IGNORECASE) and not READ_ONLY.search(name):
            _agy.note_unknown(name, "posible-escritura-externa")
        return 0

    pieces = [p.strip() for p in publication_content(args) if p.strip()]
    if not pieces:
        _agy.decide("deny", "Quality gate: no encontre contenido publicable en el payload; se bloquea por seguridad.")
        return 0

    combined = "\n".join(pieces)
    if len(combined) < 3:
        _agy.decide("deny", "Quality gate: el contenido esta vacio o es demasiado corto para verificarse.")
        return 0

    for pattern in PLACEHOLDERS:
        match = pattern.search(combined)
        if match:
            _agy.decide("deny", f"Quality gate: quedo un placeholder sin resolver ({match.group(0)!r}).")
            return 0

    # Payload limpio, pero igual se publica hacia afuera: confirmacion explicita.
    _agy.decide(
        "force_ask",
        f"Publicacion externa via {name}. Revisa el contenido antes de confirmar: "
        "una vez publicado en Jira/Confluence, deshacerlo es manual.",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
