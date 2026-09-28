#!/usr/bin/env python3
"""PostToolUse (Codex, matcher "apply_patch|Edit|Write"): checks despues de editar.

Codex edita con `apply_patch`: un solo llamado puede tocar varios archivos, y
las rutas no vienen en un campo sino dentro del texto del patch. Se extraen de
los encabezados (`*** Update File:`, `*** Add File:`, `*** Move to:`) y cada
archivo que quedo escrito pasa por core/gates/post_edicion.

Por que PostToolUse y no PreToolUse: el gate mira el archivo YA escrito (que el
Python parsee, que la suite siga verde). Y ademas, openai/codex#27833: un deny
de PreToolUse sobre apply_patch no se respeta. Aca no dependemos de eso.

`{"decision":"block"}` no deshace la edicion: Codex reemplaza el resultado de
la herramienta por el motivo y el modelo lo lee y corrige. Es el mismo feedback
inmediato que en Claude Code, sin la marca diferida de Cursor/Antigravity.

Politica:
  - stdin ilegible, o patch sin encabezados  -> block ("no pude verificar")
  - patch que solo borra archivos            -> silencio (no queda nada escrito)
  - otra herramienta                         -> silencio
  - archivo fuera de la raiz o borrado       -> silencio (salvo el baseline
    configurado, que el core valida este donde este)
  - algun archivo roto                       -> block con el detalle de todos,
    avisando que el archivo YA quedo escrito (el block no deshace nada)

Lo que Codex escribe por la terminal (`printf ... > x.json`) no pasa por aca:
eso lo cubre check-after-shell.py, con una foto del disco antes y despues.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _codex  # noqa: E402

from core.gates import post_edicion  # noqa: E402

HERRAMIENTAS_DE_EDICION = {"apply_patch", "Edit", "Write"}


def frenar(motivo: str) -> None:
    _codex.frenar(f"Quality gate post-edit: {motivo}")


def rutas_editadas(payload: dict) -> list[str]:
    """Rutas escritas: las del patch, o `file_path` si la tool lo trajera suelto."""
    texto = _codex.comando(payload)
    if texto:
        return _codex.archivos_del_patch(texto)
    suelta = _codex.argumentos(payload).get("file_path")
    return [suelta] if isinstance(suelta, str) and suelta.strip() else []


def absoluta(ruta: str, cwd: object) -> str:
    """Las rutas del patch son relativas al cwd de la sesion, no a la raiz del harness."""
    candidato = Path(ruta).expanduser()
    if not candidato.is_absolute() and isinstance(cwd, str) and cwd:
        candidato = Path(cwd) / candidato
    return str(candidato)


def main() -> int:
    payload = _codex.leer_payload()
    if payload is None:
        frenar("entrada inválida; no pude verificar el cambio.")
        return 0

    if payload.get("tool_name") not in HERRAMIENTAS_DE_EDICION:
        return 0

    rutas = rutas_editadas(payload)
    if not rutas:
        # Un patch que solo borra archivos no deja nada que revisar. Uno sin ningun
        # encabezado es ilegible: la herramienta es nuestra, asi que falla cerrado.
        if not _codex.es_patch(_codex.comando(payload) or ""):
            frenar("no encontré ningún archivo en el patch; no pude verificar el cambio.")
        return 0

    raiz = _codex.raiz_del_proyecto()
    absolutas = [absoluta(ruta, payload.get("cwd")) for ruta in rutas]
    # Un patch que toca varios .py corre la suite una sola vez (revisar_archivos).
    # Abstenerse (fuera de la raiz o borrado) es silencio: este hook corre en
    # cualquier proyecto. El baseline configurado no llega aca como abstencion:
    # el core lo valida (ver post_edicion).
    fallas = [v.motivo for v in post_edicion.revisar_archivos(absolutas, raiz, _codex.HARNESS_ROOT) if v.bloquea]
    if fallas:
        _codex.frenar_ya_escrito(fallas)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
