#!/usr/bin/env python3
"""PreToolUse (Codex, matcher "Bash"): bloquea comandos de shell destructivos.

La decision vive en core/gates/destructivos; aca solo se traduce el contrato.

Politica:
  - stdin ilegible                 -> deny (el matcher garantiza que es shell)
  - otra herramienta               -> silencio (no es asunto de este gate)
  - Bash sin comando legible       -> deny (core: "comando Bash vacio o invalido")
  - Bash destructivo               -> deny
  - Bash inocuo                    -> silencio
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _codex  # noqa: E402

from core.gates import destructivos  # noqa: E402

HERRAMIENTAS_DE_SHELL = {"Bash", "shell", "exec_command", "local_shell"}


def denegar(motivo: str) -> None:
    _codex.denegar(f"Quality gate: {motivo} bloqueado.")


def main() -> int:
    payload = _codex.leer_payload()
    if payload is None:
        denegar("entrada inválida")
        return 0

    if payload.get("tool_name") not in HERRAMIENTAS_DE_SHELL:
        return 0

    veredicto = destructivos.revisar_comando(_codex.comando(payload))
    if veredicto.bloquea:
        denegar(veredicto.motivo)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
