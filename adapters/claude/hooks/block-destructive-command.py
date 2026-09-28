#!/usr/bin/env python3
"""PreToolUse gate: block destructive Bash commands before execution.

Traduce el contrato de Claude Code; la decision vive en core/gates/destructivos.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _claude  # noqa: E402

from core.gates import destructivos  # noqa: E402


def denegar(motivo: str) -> None:
    _claude.denegar(f"Quality gate: {motivo} bloqueado.")


def main() -> int:
    payload = _claude.leer_payload()
    if payload is None:
        denegar("entrada inválida")
        return 0
    if _claude.lo_invoca_cursor(payload):
        _claude.ceder_a_cursor()
        return 0

    if payload.get("tool_name") != "Bash":
        denegar("herramienta inesperada")
        return 0

    tool_input = payload.get("tool_input")
    comando = tool_input.get("command") if isinstance(tool_input, dict) else None

    veredicto = destructivos.revisar_comando(comando)
    if veredicto.bloquea:
        denegar(veredicto.motivo)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
