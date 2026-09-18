"""Gate post-edición: un cambio que rompe algo se detecta en el acto.

Checks rápidos y deterministas, sin opinión de estilo: que el Python parsee y
la suite siga verde, que el Bash tenga sintaxis válida, que el JSON sea JSON.
"""

from __future__ import annotations

import ast
import os
import subprocess
from pathlib import Path
from typing import Any

from . import contract


def ejecutar(comando: list[str], cwd: Path) -> tuple[bool, str]:
    """Corre un check y devuelve (pasó, salida combinada)."""
    resultado = subprocess.run(
        comando,
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    salida = "\n".join(
        parte.strip() for parte in (resultado.stdout, resultado.stderr) if parte.strip()
    )
    return resultado.returncode == 0, salida


def _ubicar(ruta: Any, raiz_proyecto: Any) -> tuple[Path, Path] | None:
    """Resuelve el archivo editado dentro de la raíz, o None si queda afuera."""
    if not isinstance(raiz_proyecto, (str, Path)):
        return None
    if not isinstance(ruta, str) or not ruta.strip():
        return None

    raiz = Path(raiz_proyecto).resolve()
    candidato = Path(ruta)
    if not candidato.is_absolute():
        candidato = raiz / candidato
    destino = candidato.resolve()
    try:
        destino.relative_to(raiz)
    except ValueError:
        return None
    return raiz, destino


def revisar_archivo(ruta: Any, raiz_proyecto: Any) -> contract.Verdict:
    """Revisa un archivo recién editado según su extensión.

    Un archivo fuera de la raíz o que ya no existe no es asunto de este gate:
    se abstiene y cada runtime decide (ver `contract`).
    """
    ubicacion = _ubicar(ruta, raiz_proyecto)
    if ubicacion is None:
        return contract.abstenerse("archivo vacío o fuera de la raíz del proyecto.")
    raiz, destino = ubicacion

    if not destino.is_file():
        return contract.abstenerse(f"el archivo no existe después del cambio: {destino}")

    suffix = destino.suffix.lower()
    if suffix == ".py":
        try:
            ast.parse(destino.read_text(encoding="utf-8"), filename=str(destino))
        except (SyntaxError, UnicodeDecodeError) as exc:
            return contract.bloquear(f"Python inválido en {destino.name}:\n{exc}")
        ok, salida = ejecutar(
            ["python3", "-B", "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
            raiz,
        )
        etiqueta = "tests Python"
    elif suffix == ".sh":
        ok, salida = ejecutar(["bash", "-n", str(destino)], raiz)
        etiqueta = "sintaxis Bash"
    elif suffix == ".json":
        ok, salida = ejecutar(["python3", "-m", "json.tool", str(destino)], raiz)
        etiqueta = "JSON"
    else:
        return contract.permitir()

    if ok:
        return contract.permitir()

    detalle = salida or "el comando terminó con error y no produjo salida"
    return contract.bloquear(
        f"falló {etiqueta} después de editar {destino.name}. "
        f"Corrige el archivo antes de continuar.\n{detalle}"
    )
