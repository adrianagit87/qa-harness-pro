"""Contrato neutral de los gates: un veredicto, y nada más.

Un gate decide; no sabe en qué runtime corre ni cómo se imprime la respuesta.
Cada adaptador traduce el veredicto al contrato de su runtime.

Política de decisión:
  - comando o herramienta que este gate no gobierna  -> ABSTENERSE
  - herramienta que sí gobierna, con entrada ilegible -> BLOQUEAR (falla cerrado)

ABSTENERSE se proyecta distinto en cada runtime, y esa diferencia es real:

  - Claude Code engancha cada hook por matcher en `.claude/settings.json`. Si
    llega una herramienta inesperada, la configuración está rota: el adaptador
    lo proyecta como bloqueo, porque dejar pasar lo que no se sabe validar sería
    prometer un gate que no existe.

    Una excepción, y es de significado, no de runtime: el post de la terminal
    (`post_shell`) se abstiene cuando no tiene un antes confiable, y eso no se
    distingue de "el comando no escribió nada". Frenar ahí frenaría cada `ls`
    de la sesión; en todo runtime que lo usa, esa abstención es silencio.

  - Cursor y Antigravity corren sus hooks sobre TODA llamada a herramienta. Ahí
    abstenerse tiene que ser silencio: un default restrictivo frenaría al agente
    entero por cosas que no son asunto de este harness.

  - Codex engancha por matcher, pero con matchers amplios (`mcp__.*` ve toda
    llamada MCP, lecturas incluidas) y sus hooks son globales: corren en
    cualquier proyecto. Ahí también abstenerse es silencio. Lo que sí falla
    cerrado es la entrada ilegible, porque el matcher garantiza que la
    herramienta es una que el gate gobierna.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final

PERMITIR: Final = "permitir"
BLOQUEAR: Final = "bloquear"
ABSTENERSE: Final = "abstenerse"


@dataclass(frozen=True)
class Verdict:
    """Decisión de un gate, con el motivo en texto plano para la persona."""

    decision: str
    motivo: str = ""

    @property
    def bloquea(self) -> bool:
        return self.decision == BLOQUEAR

    @property
    def se_abstiene(self) -> bool:
        return self.decision == ABSTENERSE


def permitir() -> Verdict:
    """El gate miró y no tiene nada que objetar."""
    return Verdict(PERMITIR)


def bloquear(motivo: str) -> Verdict:
    """El gate gobierna esto y lo frena."""
    return Verdict(BLOQUEAR, motivo)


def abstenerse(motivo: str = "") -> Verdict:
    """Esto no es asunto de este gate; el motivo queda por si el runtime lo usa."""
    return Verdict(ABSTENERSE, motivo)
