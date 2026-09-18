"""Shim de compatibilidad Claude Code -> Antigravity.

Antigravity y Claude Code tienen contratos de hook distintos:

    Claude Code                        Antigravity
    payload["tool_name"]               payload["toolCall"]["name"]
    payload["tool_input"]              payload["toolCall"]["args"]
    {"hookSpecificOutput": {...}}      {"decision": ..., "reason": ...}

Este modulo traduce entre los dos. La LOGICA vive en core/gates: los patrones,
las reglas y las claves de contenido estan en un solo lugar, asi que si manana
se agrega un placeholder al catalogo, este port lo hereda sin tocar nada.

REGLA CRITICA: los hooks de Antigravity corren con matcher "*", o sea sobre
TODA llamada a herramienta. Por eso ABSTENERSE se proyecta como silencio
(stdout vacio). Un default restrictivo aca bloquearia el agente entero.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

# Raiz del harness: se busca subiendo hasta la marca `core/gates/contract.py`, en
# vez de contar niveles. Este bootstrap esta inline a proposito: hace falta para
# poder importar `core` (incluido `core.raiz`), asi que no puede depender de el.
def _raiz_bootstrap() -> Path:
    for candidato in Path(__file__).resolve().parents:
        if (candidato / "core" / "gates" / "contract.py").is_file():
            return candidato
    raise RuntimeError(f"no encuentro la raiz del harness desde {__file__}")


HARNESS_ROOT = _raiz_bootstrap()
if str(HARNESS_ROOT) not in sys.path:
    sys.path.insert(0, str(HARNESS_ROOT))

# Donde se anotan los nombres de herramienta que no reconocimos, para poder
# afinar el catalogo sin adivinar.
UNKNOWN_LOG = Path(
    os.environ.get("QA_HARNESS_UNKNOWN_TOOLS_LOG", Path.home() / ".gemini" / "qa-harness-unknown-tools.log")
)


def read_call() -> tuple[str, dict[str, Any]]:
    """Devuelve (nombre_de_tool, args). Ante entrada invalida, ('', {})."""
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError, ValueError):
        return "", {}
    if not isinstance(payload, dict):
        return "", {}
    call = payload.get("toolCall")
    if not isinstance(call, dict):
        return "", {}
    name = call.get("name")
    args = call.get("args")
    return (name if isinstance(name, str) else ""), (args if isinstance(args, dict) else {})


def decide(decision: str, reason: str) -> None:
    """Emite una decision. decision: allow | deny | ask | force_ask."""
    print(json.dumps({"decision": decision, "reason": reason}, ensure_ascii=False))


def abstain() -> None:
    """No opinar: stdout vacio. Es el default con matcher '*'."""
    return None


def note_unknown(tool_name: str, bucket: str) -> None:
    """Registra una herramienta que parecia relevante pero no esta en el catalogo.

    Sirve para descubrir los nombres reales de las tools de Antigravity sin
    adivinar: se lee el log y se ajusta el catalogo con datos, no con
    suposiciones.
    """
    if not tool_name:
        return
    try:
        UNKNOWN_LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(UNKNOWN_LOG, "a", encoding="utf-8") as handle:
            handle.write(f"{bucket}\t{tool_name}\n")
    except OSError:
        pass  # nunca romper el agente por no poder loguear
