"""Gate de comandos destructivos: lo irreversible no se ejecuta solo."""

from __future__ import annotations

import re
from typing import Any

from . import contract

REGLAS = (
    (re.compile(r"(?:^|[\s;&|(`])(?:/[^\s;&|]+/)?rm\s+(?=[^\n;&|]*\s-|-[A-Za-z]*[rf])(?=[^\n;&|]*(?:-[A-Za-z]*r|--recursive))(?=[^\n;&|]*(?:-[A-Za-z]*f|--force))"), "rm recursivo y forzado"),
    (re.compile(r"(?:^|[\s;&|(`])git\s+reset\s+--hard(?:\s|$)"), "git reset --hard"),
    (re.compile(r"(?:^|[\s;&|(`])git\s+clean\s+(?![^\n;&|]*(?:-[A-Za-z]*n|--dry-run))(?=[^\n;&|]*(?:-[A-Za-z]*f|--force))(?=[^\n;&|]*(?:-[A-Za-z]*d|--directories))"), "git clean forzado sobre directorios"),
    (re.compile(r"(?:^|[\s;&|(`])git\s+push(?:\s+[^\n;&|]+)*\s(?:--force(?:-with-lease|-if-includes)?|-f)(?:\s|$)"), "git push forzado"),
)


def revisar_comando(comando: Any) -> contract.Verdict:
    """Revisa una línea de shell que está por ejecutarse.

    Un comando ilegible bloquea: si no se puede leer, no se puede descartar que
    sea destructivo. El motivo viene sin punto final porque los adaptadores lo
    cierran con "bloqueado.".
    """
    if not isinstance(comando, str) or not comando.strip():
        return contract.bloquear("comando Bash vacío o inválido")

    for patron, motivo in REGLAS:
        if patron.search(comando):
            return contract.bloquear(motivo)

    return contract.permitir()
