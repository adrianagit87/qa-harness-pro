#!/usr/bin/env python3
"""PostToolUse (Codex, matcher "Bash"): checks sobre lo que escribio un comando de shell.

Codex escribe seguido por la terminal (`printf '%s' '{"a": }' > x.json`) y eso
no pasa por apply_patch: check-after-edit.py no se entera. Este hook compara la
foto que dejo snapshot-before-shell.py con el disco de ahora, y cada archivo
creado o modificado por ESE comando pasa por core/gates/post_edicion (ver
core/gates/post_shell). Si el comando cambio varios .py, la suite corre una vez.

Politica:
  - stdin ilegible                       -> block ("no pude verificar")
  - otra herramienta                     -> silencio
  - sin tool_use_id o sin foto de antes  -> silencio (abstenerse: sin un antes
    confiable no se sabe que toco el comando, y validar el repo entero seria
    frenar por cosas ajenas)
  - archivos borrados, o nada cambio     -> silencio
  - algun archivo roto                   -> block, avisando que YA quedo escrito
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _codex  # noqa: E402

from core.gates import post_shell  # noqa: E402


def main() -> int:
    payload = _codex.leer_payload()
    if payload is None:
        _codex.frenar("Quality gate post-edit: entrada inválida; no pude verificar el comando.")
        return 0
    if payload.get("tool_name") not in _codex.HERRAMIENTAS_DE_SHELL:
        return 0

    clave = _codex.sesion_y_llamada(payload)
    directorio = post_shell.directorio_de_fotos(_codex.CARPETA_DE_FOTOS)
    if clave is None or directorio is None:
        return 0
    antes = post_shell.sacar_foto(directorio, *clave)
    if antes is None:
        return 0

    veredictos = post_shell.revisar_cambios(antes, _codex.raiz_del_proyecto(), _codex.HARNESS_ROOT)
    fallas = [v.motivo for v in veredictos or [] if v.bloquea]
    if fallas:
        _codex.frenar_ya_escrito(fallas)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
