#!/usr/bin/env python3
"""PreToolUse (Codex, matcher "Bash"): foto del disco antes de un comando de shell.

No es un gate: nunca deniega ni dice nada. Guarda, por (session_id, tool_use_id),
el estado de lo que gobierna post-edicion, para que check-after-shell.py sepa
exactamente que archivos escribio ESE comando (ver core/gates/post_shell).

Por que un hook aparte y no dentro de block-destructive-command.py:
  - aquel es un gate que deniega; este es un registro que no puede fallar hacia
    el usuario. Mezclarlos haria que un problema sacando la foto (git lento,
    $TMPDIR lleno) comparta proceso y timeout con el deny de lo destructivo.
  - la confianza de /hooks es por posicion: un grupo NUEVO al final pide
    aprobar solo este hook; los ya aprobados no se mueven.

Politica: todo es silencio. Sin tool_use_id, raiz que no es git, carpeta de
fotos inusable o stdin ilegible -> no hay foto, y el post se abstiene. El deny
por entrada ilegible ya lo da block-destructive-command.py en el mismo evento.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _codex  # noqa: E402

from core.gates import post_shell  # noqa: E402


def main() -> int:
    payload = _codex.leer_payload()
    if payload is None or payload.get("tool_name") not in _codex.HERRAMIENTAS_DE_SHELL:
        return 0
    clave = _codex.sesion_y_llamada(payload)
    directorio = post_shell.directorio_de_fotos(_codex.CARPETA_DE_FOTOS)
    if clave is None or directorio is None:
        return 0

    post_shell.barrer_viejas(directorio)
    foto = post_shell.tomar_foto(_codex.raiz_del_proyecto(), _codex.HARNESS_ROOT)
    if foto is not None:
        post_shell.guardar_foto(directorio, *clave, foto)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:  # noqa: BLE001 — un registro nunca frena al agente
        raise SystemExit(0)
