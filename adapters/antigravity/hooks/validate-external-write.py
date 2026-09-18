#!/usr/bin/env python3
"""PreToolUse (Antigravity): gate de publicaciones externas (Jira/Confluence/Notion).

Hace DOS cosas que en Claude Code estaban separadas:

  1. Lo que hacia el bloque `permissions` de settings.json:
     - transitionJiraIssue  -> deny (nadie cambia estados de tickets)
     - escrituras externas  -> force_ask (confirmacion explicita SIEMPRE,
       ignorando el cache de "Always Allow")
  2. Lo que hacia el hook original: validar que el payload no lleve
     placeholders sin resolver.

La decision vive en core/gates/publicacion y el catalogo de herramientas en
core/gates/catalogo -- aca solo se traduce el contrato.

Matcher: "*". Por eso ABSTENERSE es silencio: solo intervenimos sobre las
herramientas que el catalogo reconoce como escritura externa.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _agy  # noqa: E402

from core.gates import publicacion  # noqa: E402
from core.texto import sin_acentos  # noqa: E402

# Nombres que rozan Atlassian/Notion: si no son ni escritura conocida ni
# lectura, se anotan para afinar el catalogo con datos reales.
ROZA_EXTERNO = re.compile(r"atlassian|jira|confluence|notion", re.IGNORECASE)


def denegar(motivo: str) -> None:
    _agy.decide("deny", f"Quality gate: {sin_acentos(motivo)}")


def main() -> int:
    name, args = _agy.read_call()
    if not name:
        return 0

    # Antigravity no tiene el permissions.deny de Claude Code: la prohibicion de
    # transicionar tickets la aplica este hook.
    transicion = publicacion.revisar_transicion(name)
    if transicion.bloquea:
        denegar(transicion.motivo)
        return 0

    veredicto = publicacion.revisar_publicacion(name, args)

    if veredicto.se_abstiene:
        if ROZA_EXTERNO.search(name) and not publicacion.es_lectura(name):
            _agy.note_unknown(name, "posible-escritura-externa")
        return 0

    if veredicto.bloquea:
        denegar(veredicto.motivo)
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
