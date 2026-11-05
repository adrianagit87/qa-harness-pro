#!/usr/bin/env python3
"""PreToolUse (Claude Code, matcher "mcp__.*__pg_.*"): gate de SQL.

Traduce el contrato de Claude Code; la decisión vive en core/gates/sql.
  - bloquear  -> deny (base de producción o no declarada, tool que no es de
                 lectura, connectionString, consulta que no es un SELECT)
  - permitir  -> silencio

Se engancha por matcher: si llega una herramienta que no es de un MCP de
Postgres, la config está rota y se deniega (ver core/gates/contract.py).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _claude  # noqa: E402

from core.gates import contract, sql  # noqa: E402

PREFIJO = "Gate de SQL: "


def main() -> int:
    payload = _claude.leer_payload()
    if payload is None:
        _claude.denegar(PREFIJO + "entrada inválida; no pude revisar la consulta.")
        return 0
    if _claude.lo_invoca_cursor(payload):
        _claude.ceder_a_cursor()
        return 0

    bases = sql.cargar_bases(_claude.HARNESS_ROOT)
    veredicto = sql.revisar_accion(payload.get("tool_name"), payload.get("tool_input"), bases)
    if veredicto.decision != contract.PERMITIR:  # este gate no pregunta: o lee, o no
        _claude.denegar(PREFIJO + (veredicto.motivo or "herramienta inesperada."))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
