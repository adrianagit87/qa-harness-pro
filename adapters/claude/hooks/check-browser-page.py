#!/usr/bin/env python3
"""PostToolUse (Claude Code, matcher "mcp__playwright__.*"): ¿dónde quedó el navegador?

Lee la `Page URL` de la respuesta de Playwright MCP. Si un link o una
redirección dejó al navegador fuera de los ambientes configurados, frena con
feedback al modelo (la acción ya pasó: PostToolUse no la deshace, pero corta el
caso ahí). La lógica vive en core/gates/navegador.

Si la acción navegó a producción y llegó a ejecutarse, es porque la persona
confirmó el `ask` del PreToolUse: ese origen se recuerda para esta sesión, así
las acciones siguientes en él no se frenan. Una redirección a producción que
nadie pidió sí se frena.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _claude  # noqa: E402

from core.gates import navegador, post_shell  # noqa: E402


def main() -> int:
    payload = _claude.leer_payload()
    if payload is None:
        _claude.frenar("Gate del navegador: entrada inválida; no pude ver dónde quedó el navegador.")
        return 0
    if _claude.lo_invoca_cursor(payload):
        _claude.ceder_a_cursor()
        return 0

    herramienta = payload.get("tool_name")
    alcance = navegador.cargar_alcance(_claude.HARNESS_ROOT)
    directorio = post_shell.directorio_de_fotos(_claude.CARPETA_DE_FOTOS)
    sesion = payload.get("session_id")

    navegador.recordar_produccion(
        directorio, sesion, navegador.produccion_pedida(herramienta, payload.get("tool_input"), alcance)
    )
    veredicto = navegador.revisar_pagina(
        herramienta,
        payload.get("tool_response"),
        alcance,
        navegador.produccion_confirmada(directorio, sesion),
    )
    if veredicto.bloquea or veredicto.se_abstiene:
        _claude.frenar("Gate del navegador: " + (veredicto.motivo or "herramienta inesperada."))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
