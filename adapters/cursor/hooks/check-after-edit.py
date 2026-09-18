#!/usr/bin/env python3
"""afterFileEdit (Cursor): corre checks deterministicos despues de editar.

afterFileEdit no puede bloquear ni devolver feedback al agente, asi que la falla
se guarda en un archivo de marca. block-destructive-command.py
(beforeShellExecution) la levanta como "ask" en el proximo comando.

Limitacion honesta: si el agente edita y NO corre ningun comando despues, el
aviso queda esperando hasta que corra uno. En la practica casi siempre corre
algo (tests, git), pero no es instantaneo como en Claude Code.

La decision vive en core/gates/post_edicion; aca solo se traduce el contrato.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _cursor  # noqa: E402

from core.gates import post_edicion  # noqa: E402
from core.texto import sin_acentos  # noqa: E402


def mark(reason: str) -> None:
    try:
        _cursor.PENDING.parent.mkdir(parents=True, exist_ok=True)
        _cursor.PENDING.write_text(json.dumps({"reason": reason}, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass


def main() -> int:
    payload = _cursor.read_payload()
    file_raw = payload.get("file_path")
    if not isinstance(file_raw, str) or not file_raw.strip():
        return 0

    root = Path(os.environ.get("QA_HARNESS_ROOT") or _cursor.HARNESS_ROOT).resolve()
    veredicto = post_edicion.revisar_archivo(file_raw, root)
    # Abstenerse (archivo fuera del harness o inexistente) es silencio: este
    # hook corre sobre toda edicion, tambien fuera del proyecto.
    if veredicto.bloquea:
        mark(sin_acentos(veredicto.motivo))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
