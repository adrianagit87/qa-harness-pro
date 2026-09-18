#!/usr/bin/env python3
"""PostToolUse gate: run fast deterministic checks after Edit or Write.

Traduce el contrato de Claude Code; la decision vive en core/gates/post_edicion.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _claude  # noqa: E402

from core.gates import post_edicion  # noqa: E402


def frenar(motivo: str) -> None:
    _claude.frenar(f"Quality gate post-edit: {motivo}")


def main() -> int:
    payload = _claude.leer_payload()
    if payload is None:
        frenar("entrada inválida; no pude verificar el cambio.")
        return 0

    if payload.get("tool_name") not in {"Edit", "Write"}:
        frenar("herramienta inesperada; no pude verificar el cambio.")
        return 0

    tool_input = payload.get("tool_input")
    ruta = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    raiz = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd")

    veredicto = post_edicion.revisar_archivo(ruta, raiz)
    # Este hook se engancha por matcher: abstenerse aca seria dar por bueno un
    # cambio que no se pudo verificar.
    if veredicto.bloquea or veredicto.se_abstiene:
        frenar(veredicto.motivo)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
