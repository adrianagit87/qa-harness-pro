#!/usr/bin/env python3
"""PreToolUse gate: validate Jira/Confluence/Notion write payloads.

Traduce el contrato de Claude Code; la decision vive en core/gates/publicacion.
El catalogo de herramientas cubiertas esta en core/gates/catalogo.py y es el
mismo que arma el matcher de .claude/settings.json.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _claude  # noqa: E402

from core.gates import publicacion  # noqa: E402


def denegar(motivo: str) -> None:
    _claude.denegar(f"Quality gate de publicación: {motivo}")


def main() -> int:
    payload = _claude.leer_payload()
    if payload is None:
        denegar("entrada inválida; no pude inspeccionar lo que iba a salir.")
        return 0

    veredicto = publicacion.revisar_publicacion(payload.get("tool_name"), payload.get("tool_input"))
    # Este hook se engancha por matcher: si llega otra herramienta, la config
    # esta rota. Abstenerse aca seria dejar pasar lo que no se sabe validar.
    if veredicto.bloquea or veredicto.se_abstiene:
        denegar(veredicto.motivo)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
