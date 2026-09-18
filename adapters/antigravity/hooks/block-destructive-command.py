#!/usr/bin/env python3
"""PreToolUse (Antigravity): bloquea comandos de shell destructivos.

La decision vive en core/gates/destructivos -- no se duplica.
Matcher recomendado: "run_command" (documentado por Antigravity).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _agy  # noqa: E402

from core.gates import destructivos  # noqa: E402
from core.texto import sin_acentos  # noqa: E402

# Antigravity nombra la tool de shell "run_command"; se aceptan variantes por
# si cambia entre versiones.
SHELL_TOOLS = {"run_command", "run_terminal_command", "bash", "shell"}
# Claves donde puede venir la linea de comando.
COMMAND_KEYS = ("CommandLine", "command", "commandLine", "cmd")


def main() -> int:
    name, args = _agy.read_call()
    if not name:
        return 0  # entrada invalida: no opinamos, otro gate se encargara

    if name not in SHELL_TOOLS:
        return 0

    command = next(
        (args[k] for k in COMMAND_KEYS if isinstance(args.get(k), str) and args[k].strip()),
        None,
    )
    if command is None:
        _agy.note_unknown(f"{name}:sin-clave-de-comando", "shell")
        return 0

    veredicto = destructivos.revisar_comando(command)
    if veredicto.bloquea:
        _agy.decide("deny", f"Quality gate: {sin_acentos(veredicto.motivo)} bloqueado.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
