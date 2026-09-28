"""Gate de comandos destructivos: lo irreversible no se ejecuta solo."""

from __future__ import annotations

import re
from typing import Any

from . import contract

# Una opción empieza un token: el guion va al principio del comando o después
# de un espacio. Sin esto, el `-pr` de `zz-prueba` pasaba por `-r` y el `-name`
# de `some-name` por `-n`, que convertía un git clean real en una simulación.
_EN_ALGUN_TOKEN = r"(?:[^\n;&|]*\s)?(?:{})"


def _con_opcion(opcion: str) -> str:
    return "(?=" + _EN_ALGUN_TOKEN.format(opcion) + ")"


def _sin_opcion(opcion: str) -> str:
    return "(?!" + _EN_ALGUN_TOKEN.format(opcion) + ")"


REGLAS = (
    (re.compile(r"(?:^|[\s;&|(`])(?:/[^\s;&|]+/)?rm\s+" + _con_opcion(r"-[A-Za-z]*r|--recursive") + _con_opcion(r"-[A-Za-z]*f|--force")), "rm recursivo y forzado"),
    (re.compile(r"(?:^|[\s;&|(`])git\s+reset\s+--hard(?:\s|$)"), "git reset --hard"),
    (re.compile(r"(?:^|[\s;&|(`])git\s+clean\s+" + _sin_opcion(r"-[A-Za-z]*n|--dry-run") + _con_opcion(r"-[A-Za-z]*f|--force") + _con_opcion(r"-[A-Za-z]*d|--directories")), "git clean forzado sobre directorios"),
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
