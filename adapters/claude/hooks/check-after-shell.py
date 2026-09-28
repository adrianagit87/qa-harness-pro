#!/usr/bin/env python3
"""PostToolUse / PostToolUseFailure (Claude Code, matcher "Bash"): checks sobre lo que escribió un comando.

El agente no solo edita con Edit/Write: también escribe por la terminal
(`printf '{"a": }' > x.json`, `sed -i`, un script que genera archivos), y eso
no pasa por check-after-edit.py. Este hook compara la foto que dejó
snapshot-before-shell.py con el disco de ahora, y cada archivo creado o
modificado por ESE comando pasa por core/gates/post_edicion (ver
core/gates/post_shell). Si el comando cambió varios .py, la suite corre una vez.

Se engancha a los dos eventos porque un comando que termina con exit != 0 no
dispara PostToolUse sino PostToolUseFailure, y lo que escribió antes de fallar
queda escrito igual. En PostToolUse la falla vuelve como block; en
PostToolUseFailure no hay block (la herramienta ya falló) y va como contexto.

Política:
  - stdin ilegible                       -> block ("no pude verificar")
  - otra herramienta                     -> block (el matcher es "Bash": la
    config está rota, como en los otros hooks de este adaptador)
  - sin tool_use_id o sin foto de antes  -> SILENCIO
  - archivos borrados, o nada cambió     -> silencio
  - algún archivo roto                   -> block, avisando que YA quedó escrito

Por qué acá abstenerse es silencio y en check-after-edit.py es block: en Edit/
Write, abstenerse quiere decir "hubo una edición gobernada que no pude
verificar". Acá quiere decir "no tengo un antes confiable" (el pre no corrió,
la raíz no es un repo git, la raíz cambió entre el pre y el post), y eso no se
distingue de "el comando no escribió nada", que es lo que pasa en casi todo
`ls`, `git status` o `pytest`. Frenar ahí sería frenar cada comando de la
sesión por algo que no es una edición; y validar el repo entero a ciegas sería
frenar por cosas ajenas. Lo que sí falla cerrado es lo que el matcher
garantiza: la entrada ilegible.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _claude  # noqa: E402

from core.gates import post_shell  # noqa: E402

FALLA = "PostToolUseFailure"


def avisar(evento: object, mensaje: str) -> None:
    if evento == FALLA:
        _claude.agregar_contexto(FALLA, mensaje)
    else:
        _claude.frenar(mensaje)


def main() -> int:
    payload = _claude.leer_payload()
    if payload is None:
        _claude.frenar("Quality gate post-edit: entrada inválida; no pude verificar el comando.")
        return 0
    if _claude.lo_invoca_cursor(payload):
        _claude.ceder_a_cursor()
        return 0
    evento = payload.get("hook_event_name")
    if payload.get("tool_name") != "Bash":
        avisar(evento, "Quality gate post-edit: herramienta inesperada; no pude verificar el comando.")
        return 0

    fallas = post_shell.fallas_de_la_llamada(
        _claude.CARPETA_DE_FOTOS,
        post_shell.clave_de_llamada(payload.get("session_id"), payload.get("tool_use_id")),
        _claude.raiz_del_proyecto(payload),
        _claude.HARNESS_ROOT,
    )
    if fallas:
        avisar(evento, post_shell.con_aviso(fallas, _claude.MAX_FEEDBACK))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
