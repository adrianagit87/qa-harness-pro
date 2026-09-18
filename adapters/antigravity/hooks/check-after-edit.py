#!/usr/bin/env python3
"""PostToolUse (Antigravity): corre checks deterministicos despues de editar.

DIFERENCIA IMPORTANTE CON CLAUDE CODE
-------------------------------------
En Claude Code, PostToolUse puede devolver {"decision":"block","reason":...} y
ese texto vuelve al modelo como feedback: el agente se entera de que rompio algo
y lo corrige en el acto.

En Antigravity, PostToolUse **solo puede devolver {}**. No hay canal de vuelta.

Para no perder el gate, este hook escribe la falla en un archivo de marca, y
surface-pending-check.py (PreToolUse, matcher "*") la levanta en la siguiente
llamada a herramienta y la convierte en un "ask". El gate sigue existiendo, con
un turno de retraso.

La decision vive en core/gates/post_edicion; aca solo se traduce el contrato.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _agy  # noqa: E402

from core.gates import post_edicion  # noqa: E402
from core.texto import sin_acentos  # noqa: E402

PENDING = Path(
    os.environ.get("QA_HARNESS_PENDING_CHECK", Path.home() / ".gemini" / "qa-harness-pending-check.json")
)

# Los nombres de las tools de edicion en Antigravity no estan documentados.
# Se detecta por nombre O por la presencia de una clave de ruta de archivo.
EDIT_HINTS = ("edit", "write", "create_file", "replace", "patch", "apply_diff")
PATH_KEYS = ("file_path", "filePath", "path", "TargetFile", "target_file", "AbsolutePath")


def mark(reason: str) -> None:
    try:
        PENDING.parent.mkdir(parents=True, exist_ok=True)
        PENDING.write_text(json.dumps({"reason": reason}, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass


def main() -> int:
    name, args = _agy.read_call()
    print("{}")  # el contrato de PostToolUse espera exactamente esto

    if not name:
        return 0
    if not any(h in name.lower() for h in EDIT_HINTS):
        return 0

    file_raw = next((args[k] for k in PATH_KEYS if isinstance(args.get(k), str) and args[k].strip()), None)
    if file_raw is None:
        _agy.note_unknown(f"{name}:sin-clave-de-ruta", "edicion")
        return 0

    root = Path(os.environ.get("QA_HARNESS_ROOT") or _agy.HARNESS_ROOT).resolve()
    veredicto = post_edicion.revisar_archivo(file_raw, root)
    # Abstenerse (archivo fuera del harness o inexistente) es silencio: no es
    # asunto de este gate.
    if veredicto.bloquea:
        mark(sin_acentos(veredicto.motivo))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
