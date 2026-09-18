#!/usr/bin/env python3
"""beforeMCPExecution (Cursor): gate de publicaciones externas.

Cursor solo implementa "deny" en este evento -- no hay "ask". La confirmacion
interactiva la pone el propio allowlist de MCP de Cursor. Este hook aporta lo
que Cursor no puede saber: si el CONTENIDO que se va a publicar esta completo.

Politica:
  - transiciones de Jira              -> deny siempre
  - escritura externa con placeholder -> deny
  - escritura externa limpia          -> pasa (Cursor pide su propia aprobacion)

La decision vive en core/gates/publicacion; aca solo se traduce el contrato.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _cursor  # noqa: E402

from core.gates import publicacion  # noqa: E402
from core.texto import sin_acentos  # noqa: E402


def denegar(motivo: str) -> None:
    _cursor.decide("deny", f"Quality gate: {sin_acentos(motivo)}")


def main() -> int:
    payload = _cursor.read_payload()
    name = payload.get("tool_name")
    if not isinstance(name, str) or not name:
        return 0

    # Cursor no tiene el permissions.deny de Claude Code: la prohibicion de
    # transicionar tickets la aplica este hook.
    transicion = publicacion.revisar_transicion(name)
    if transicion.bloquea:
        denegar(transicion.motivo)
        return 0

    veredicto = publicacion.revisar_publicacion(name, _cursor.tool_args(payload))
    if veredicto.bloquea:
        denegar(veredicto.motivo)
    # Abstenerse (otra herramienta) y permitir (contenido limpio) son silencio:
    # este hook corre sobre TODA llamada MCP.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
