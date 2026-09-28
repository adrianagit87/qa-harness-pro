#!/usr/bin/env python3
"""postToolUse / postToolUseFailure (Cursor, matcher "Shell"): checks sobre lo que escribio un comando.

afterFileEdit no se entera de lo que el agente escribe por la terminal
(`printf '{"a": }' > x.json`). Este hook compara la foto que dejo
snapshot-before-shell.py con el disco de ahora, y cada archivo creado o
modificado por ESE comando pasa por core/gates/post_edicion (ver
core/gates/post_shell). Si el comando cambio varios .py, la suite corre una vez.

Canal de vuelta: `additional_context`, que Cursor agrega a la conversacion
despues del resultado del comando. No bloquea (el comando ya corrio), pero el
agente lo lee en el mismo turno: no hace falta la marca diferida de
afterFileEdit. Se engancha tambien a postToolUseFailure porque un comando que
falla puede haber escrito antes de fallar.

Politica: como todo hook de este adaptador, abstenerse es silencio.
  - otra herramienta, stdin ilegible     -> silencio
  - sin tool_use_id o sin foto de antes  -> silencio (sin un antes confiable
    no se sabe que toco el comando)
  - archivos borrados, o nada cambio     -> silencio
  - algun archivo roto                   -> additional_context, avisando que
    YA quedo escrito
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _cursor  # noqa: E402

from core.gates import post_shell  # noqa: E402
from core.texto import sin_acentos  # noqa: E402

MAX_FEEDBACK = 4000


def main() -> int:
    payload = _cursor.read_payload()
    if payload.get("tool_name") != "Shell":
        return 0
    fallas = post_shell.fallas_de_la_llamada(
        _cursor.SNAPSHOT_DIR,
        post_shell.clave_de_llamada(payload.get("conversation_id"), payload.get("tool_use_id")),
        _cursor.project_root(),
        _cursor.HARNESS_ROOT,
    )
    if fallas:
        _cursor.add_context(sin_acentos(post_shell.con_aviso(fallas, MAX_FEEDBACK)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
