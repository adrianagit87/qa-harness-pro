#!/usr/bin/env python3
"""PreToolUse (Claude Code, matcher "mcp__playwright__.*"): gate del navegador.

Traduce el contrato de Claude Code; la decisión vive en core/gates/navegador.
  - bloquear  -> deny (URL fuera de los ambientes, tarjeta, contraseña literal,
                 JavaScript arbitrario)
  - preguntar -> ask  (producción, subir archivos): la persona confirma AHORA
  - permitir  -> silencio

Se engancha por matcher: si llega una herramienta que no es del navegador, la
config está rota y se deniega (ver core/gates/contract.py).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _claude  # noqa: E402

from core.gates import navegador  # noqa: E402

PREFIJO = "Gate del navegador: "


def main() -> int:
    payload = _claude.leer_payload()
    if payload is None:
        _claude.denegar(PREFIJO + "entrada inválida; no pude revisar la acción del navegador.")
        return 0
    if _claude.lo_invoca_cursor(payload):
        _claude.ceder_a_cursor()
        return 0

    alcance = navegador.cargar_alcance(_claude.HARNESS_ROOT)
    veredicto = navegador.revisar_accion(payload.get("tool_name"), payload.get("tool_input"), alcance)
    if veredicto.bloquea or veredicto.se_abstiene:
        _claude.denegar(PREFIJO + (veredicto.motivo or "herramienta inesperada."))
    elif veredicto.pregunta:
        _claude.preguntar(PREFIJO + veredicto.motivo)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
