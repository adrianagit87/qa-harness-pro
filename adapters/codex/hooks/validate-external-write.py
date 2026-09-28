#!/usr/bin/env python3
"""PreToolUse (Codex, matcher "mcp__.*"): gate de publicaciones externas.

Codex solo implementa "deny" en PreToolUse -- "ask" lo rechaza como
unsupported. La confirmacion interactiva la pone la segunda capa, en
config.toml: `approval_mode = "prompt"` por cada tool de escritura del server
atlassian, y la transicion fuera de la lista de tools (`disabled_tools`). Este
hook aporta lo que Codex no puede saber: si el CONTENIDO esta completo.

Politica:
  - stdin ilegible                    -> deny (el matcher garantiza que es MCP)
  - transiciones de Jira              -> deny siempre
  - escritura externa con placeholder -> deny
  - escritura externa limpia          -> silencio (Codex pide su aprobacion)
  - lectura u otra herramienta        -> silencio

La decision vive en core/gates/publicacion y el catalogo en core/gates/catalogo;
aca solo se traduce el contrato.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _codex  # noqa: E402

from core.gates import publicacion  # noqa: E402


def denegar(motivo: str) -> None:
    _codex.denegar(f"Quality gate de publicación: {motivo}")


def main() -> int:
    payload = _codex.leer_payload()
    if payload is None:
        denegar("entrada inválida; no pude inspeccionar lo que iba a salir.")
        return 0

    nombre = payload.get("tool_name")
    if not isinstance(nombre, str) or not nombre:
        return 0

    # Codex no tiene el permissions.deny de Claude Code: la prohibicion la
    # aplica este hook, y de respaldo `disabled_tools` en config.toml.
    transicion = publicacion.revisar_transicion(nombre)
    if transicion.bloquea:
        denegar(transicion.motivo)
        return 0

    veredicto = publicacion.revisar_publicacion(nombre, _codex.argumentos(payload))
    if veredicto.bloquea:
        denegar(veredicto.motivo)
    # Abstenerse (otra herramienta) y permitir (contenido limpio) son silencio:
    # este hook corre sobre TODA llamada MCP.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
