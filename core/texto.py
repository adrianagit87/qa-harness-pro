"""Ayudas de texto compartidas por los adaptadores."""

from __future__ import annotations

import unicodedata


def sin_acentos(texto: str) -> str:
    """Quita las tildes y conserva la eñe.

    Los hooks de Cursor y Antigravity escriben en español sin tildes. El motivo
    canónico vive una sola vez en `core/gates`; cada adaptador lo proyecta a la
    ortografía que ya usaba, sin duplicar el mensaje.
    """
    protegido = texto.replace("ñ", "\0n").replace("Ñ", "\0N")
    plano = "".join(
        letra
        for letra in unicodedata.normalize("NFD", protegido)
        if not unicodedata.combining(letra)
    )
    return plano.replace("\0n", "ñ").replace("\0N", "Ñ")
