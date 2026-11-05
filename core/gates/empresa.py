"""La config de la empresa activa: profile/profile.json -> companies/<empresa>.json.

La leen los gates que dependen de los ambientes (navegador, SQL). Falla cerrado:
si algo no se puede leer, devuelve el motivo y ninguna config.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def leer_config_activa(raiz_harness: Any) -> tuple[dict | None, str]:
    """(config, "") o (None, motivo)."""
    if not isinstance(raiz_harness, (str, Path)):
        return None, "no sé dónde está la raíz del harness para leer la config."
    raiz = Path(raiz_harness)
    try:
        perfil = json.loads((raiz / "profile" / "profile.json").read_text(encoding="utf-8"))
        empresa = perfil.get("activeCompany") if isinstance(perfil, dict) else None
        if not isinstance(empresa, str) or not empresa.strip():
            return None, "profile.activeCompany está vacío: no sé qué ambientes son válidos."
        empresa = empresa.strip()
        if "/" in empresa or "\\" in empresa or empresa.startswith("."):
            return None, f"profile.activeCompany inválido ({empresa!r})."
        config = json.loads((raiz / "companies" / f"{empresa}.json").read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return None, f"no pude leer la config de la empresa activa ({error})."
    if not isinstance(config, dict):
        return None, "la config de la empresa activa no es un objeto JSON."
    return config, ""


def ambientes(config: Any) -> list[dict]:
    """Las entradas de `environments.list` que son objetos."""
    if not isinstance(config, dict):
        return []
    bloque = config.get("environments", {})
    lista = bloque.get("list", []) if isinstance(bloque, dict) else []
    return [a for a in lista if isinstance(a, dict)] if isinstance(lista, list) else []
