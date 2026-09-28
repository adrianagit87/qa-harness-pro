"""Gate post-edición: un cambio que rompe algo se detecta en el acto.

Checks rápidos y deterministas, sin opinión de estilo: que el Python parsee y
la suite siga verde, que el Bash tenga sintaxis válida, que el JSON sea JSON, y
que el baseline conserve la trazabilidad de cada regla (ver `baseline`).
Un `.md` sin la marca del baseline en su primera línea no se revisa.
"""

from __future__ import annotations

import ast
import os
import subprocess
from pathlib import Path
from typing import Any

from . import baseline, contract


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


def _es_el_baseline_configurado(ruta: Any, raiz_proyecto: Any, raiz_harness: Any) -> Path | None:
    """El archivo editado, si es exactamente el baseline configurado; si no, None."""
    configurado = baseline.ruta_configurada(raiz_harness)
    if configurado is None or not isinstance(ruta, str) or not ruta.strip():
        return None
    candidato = Path(ruta).expanduser()
    if not candidato.is_absolute():
        if not isinstance(raiz_proyecto, (str, Path)):
            return None
        candidato = Path(raiz_proyecto) / candidato
    try:
        destino = candidato.resolve()
    except (OSError, RuntimeError):
        return None
    return destino if destino == configurado else None


def revisar_archivo(
    ruta: Any, raiz_proyecto: Any, raiz_harness: Any = None, *, con_suite: bool = True
) -> contract.Verdict:
    """Revisa un archivo recién editado según su extensión.

    Un archivo fuera de la raíz o que ya no existe no es asunto de este gate:
    se abstiene y cada runtime decide (ver `contract`).

    Única excepción, y es angosta: el baseline configurado en la
    empresa activa (leída desde `raiz_harness`) se valida esté donde esté, porque
    `baseline.path` puede apuntar fuera del proyecto. Solo ese archivo exacto; los
    checks de .py/.sh/.json nunca salen de la raíz.

    `con_suite=False` deja el .py en el chequeo de sintaxis: lo usa
    `revisar_archivos`, que corre la suite una sola vez para todo el cambio.
    """
    del_baseline = _es_el_baseline_configurado(ruta, raiz_proyecto, raiz_harness)
    if del_baseline is not None:
        if not del_baseline.is_file():
            return contract.abstenerse(f"el archivo no existe después del cambio: {del_baseline}")
        return _revisar_baseline(del_baseline)

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
        if not con_suite:
            return contract.permitir()
        return _correr_suite(raiz, [destino.name])
    elif suffix == ".sh":
        ok, salida = ejecutar(["bash", "-n", str(destino)], raiz)
        etiqueta = "sintaxis Bash"
    elif suffix == ".json":
        ok, salida = ejecutar(["python3", "-m", "json.tool", str(destino)], raiz)
        etiqueta = "JSON"
    elif suffix == ".md":
        return _revisar_markdown(destino)
    else:
        return contract.permitir()

    return _veredicto_del_check(ok, salida, etiqueta, [destino.name])


def revisar_archivos(rutas: list[Any], raiz_proyecto: Any, raiz_harness: Any = None) -> list[contract.Verdict]:
    """Varios archivos de un mismo cambio, con la suite corriendo UNA sola vez.

    Cada archivo pasa por `revisar_archivo` sin suite; si entre ellos hubo algún
    .py gobernado y todos parsean, la suite corre al final, una vez para todos.
    Si alguno no parsea, la suite no corre: fallaría igual y es lo más caro.
    """
    veredictos: list[contract.Verdict] = []
    pythons: list[str] = []
    sintaxis_rota = False
    for ruta in rutas:
        veredicto = revisar_archivo(ruta, raiz_proyecto, raiz_harness, con_suite=False)
        veredictos.append(veredicto)
        ubicacion = _ubicar(ruta, raiz_proyecto)
        if ubicacion is None or ubicacion[1].suffix.lower() != ".py" or veredicto.se_abstiene:
            continue
        if veredicto.bloquea:
            sintaxis_rota = True
        else:
            pythons.append(ubicacion[1].name)
    if pythons and not sintaxis_rota:
        veredictos.append(_correr_suite(Path(raiz_proyecto).resolve(), pythons))
    return veredictos


def _correr_suite(raiz: Path, nombres: list[str]) -> contract.Verdict:
    ok, salida = ejecutar(
        ["python3", "-B", "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
        raiz,
    )
    return _veredicto_del_check(ok, salida, "tests Python", nombres)


def _veredicto_del_check(ok: bool, salida: str, etiqueta: str, nombres: list[str]) -> contract.Verdict:
    if ok:
        return contract.permitir()
    detalle = salida or "el comando terminó con error y no produjo salida"
    editados = ", ".join(nombres)
    return contract.bloquear(
        f"falló {etiqueta} después de editar {editados}. "
        f"Corrige el archivo antes de continuar.\n{detalle}"
    )


def _revisar_markdown(destino: Path) -> contract.Verdict:
    """Solo el baseline tiene estructura que cuidar; el resto del Markdown pasa."""
    try:
        texto = destino.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return contract.permitir()
    if not baseline.es_baseline(texto):
        return contract.permitir()
    return _revisar_baseline(destino, texto)


def _revisar_baseline(destino: Path, texto: str | None = None) -> contract.Verdict:
    """Valida el baseline. Si es el configurado, la marca también se exige."""
    if texto is None:
        try:
            texto = destino.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            return contract.bloquear(f"no pude leer el baseline {destino.name}: {exc}")

    problemas = baseline.motivo(texto)
    if problemas is None:
        return contract.permitir()
    return contract.bloquear(
        f"baseline inválido en {destino.name}. Corrige el formato antes de "
        f"continuar: cada regla necesita ID, estado, texto y trazabilidad "
        f"(ver templates/09-baseline.md).\n{problemas}"
    )
