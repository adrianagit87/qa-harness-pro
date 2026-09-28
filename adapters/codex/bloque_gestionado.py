#!/usr/bin/env python3
"""Un bloque gestionado dentro de un archivo que es del usuario.

`~/.codex/config.toml` y `~/.codex/AGENTS.md` no son del harness: el usuario ya
tiene ahí sus servers, sus permisos y sus instrucciones. Reescribirlos enteros
sería pisarle la config; fusionarlos clave por clave con un parser de TOML
perdería sus comentarios y su orden. Por eso lo del harness vive entre dos
marcas, y solo se toca lo que está entre ellas:

    # >>> qa-harness-pro >>> ...
    ...lo del harness...
    # <<< qa-harness-pro <<<

  - Si el bloque no existe, se agrega al final.
  - Si existe, se reemplaza en su lugar (idempotente: reinstalar no duplica).
  - Si el resultado es idéntico, no se escribe nada (ni backup).
  - Antes de escribir, backup `<archivo>.bak-<stamp>`.

Para TOML hay dos guardas más, porque un config.toml roto deja a Codex sin
arrancar:
  - si el archivo del usuario ya no parsea, no se toca;
  - si el usuario ya define alguna tabla que el bloque también define (por
    ejemplo su propio `[mcp_servers.atlassian]`), no se agrega: una tabla
    duplicada es un TOML inválido. Se avisa con exit 3 y se deja todo intacto.
  - el resultado se vuelve a parsear antes de escribirlo.

Uso: bloque_gestionado.py <destino> <fuente> <toml|md> <stamp>
Exit: 0 ok · 1 error (nada escrito) · 3 conflicto con la config del usuario (nada escrito)
"""

from __future__ import annotations

import os
import sys
import tempfile
import tomllib
from pathlib import Path

ETIQUETA = "qa-harness-pro"
AVISO = "gestionado por ./install.sh --agent codex; no edites entre estas marcas"

MARCAS = {
    "toml": (f"# >>> {ETIQUETA} >>> {AVISO}", f"# <<< {ETIQUETA} <<<"),
    "md": (f"<!-- >>> {ETIQUETA} >>> {AVISO} -->", f"<!-- <<< {ETIQUETA} <<< -->"),
}


class Conflicto(Exception):
    """La config del usuario ya define algo que el bloque también define."""


# La apertura se reconoce por su prefijo con la etiqueta: el aviso de después puede
# cambiar entre versiones del instalador sin dejar un bloque huérfano. Sin la
# etiqueta sería demasiado laxo (`# >>> conda initialize >>>` también "abre").
PREFIJOS = {
    "toml": f"# >>> {ETIQUETA} >>>",
    "md": f"<!-- >>> {ETIQUETA} >>>",
}


def _abre(linea: str, formato: str) -> bool:
    return linea.strip().startswith(PREFIJOS[formato])


def _cierra(linea: str, formato: str) -> bool:
    return linea.strip() == MARCAS[formato][1]


def partir(texto: str, formato: str) -> tuple[str, str | None, str]:
    """(antes, bloque o None, después). Marcas rotas o repetidas: ValueError."""
    lineas = texto.splitlines(keepends=True)
    aperturas = [i for i, linea in enumerate(lineas) if _abre(linea, formato)]
    cierres = [i for i, linea in enumerate(lineas) if _cierra(linea, formato)]
    if not aperturas and not cierres:
        return texto, None, ""
    if len(aperturas) != 1 or len(cierres) != 1 or cierres[0] < aperturas[0]:
        raise ValueError(
            f"las marcas de {ETIQUETA} están rotas o repetidas; arréglalas a mano "
            "(o borra el bloque entero) y vuelve a instalar."
        )
    inicio, fin = aperturas[0], cierres[0]
    return "".join(lineas[:inicio]), "".join(lineas[inicio:fin + 1]), "".join(lineas[fin + 1:])


def armar_bloque(contenido: str, formato: str) -> str:
    apertura, cierre = MARCAS[formato]
    return f"{apertura}\n{contenido.strip()}\n{cierre}\n"


def componer(actual: str, contenido: str, formato: str) -> str:
    """Texto final: el del usuario intacto, con el bloque agregado o reemplazado."""
    antes, bloque, despues = partir(actual, formato)
    nuevo = armar_bloque(contenido, formato)
    if bloque is not None:
        return antes + nuevo + despues
    if not antes:
        return nuevo
    separador = "" if antes.endswith("\n\n") else ("\n" if antes.endswith("\n") else "\n\n")
    return antes + separador + nuevo


def _tablas(documento: dict, prefijo: tuple[str, ...] = ()) -> set[tuple[str, ...]]:
    encontradas: set[tuple[str, ...]] = set()
    for clave, valor in documento.items():
        if isinstance(valor, dict):
            ruta = prefijo + (clave,)
            encontradas.add(ruta)
            encontradas |= _tablas(valor, ruta)
    return encontradas


def revisar_toml(actual: str, contenido: str, final: str) -> None:
    """Las tres guardas de TOML. Lanza ValueError o Conflicto; no escribe nada."""
    antes, _, despues = partir(actual, "toml")
    try:
        del_usuario = tomllib.loads(antes + despues)
    except tomllib.TOMLDecodeError as exc:
        raise ValueError(f"tu config.toml ya no parsea como TOML ({exc}); no lo toco.") from exc
    propias = tomllib.loads(contenido)
    # Las tablas contenedoras (mcp_servers, mcp_servers.atlassian.tools) pueden
    # existir en los dos lados; lo que no puede repetirse es una tabla que el
    # bloque define con claves propias.
    definidas = {
        ruta for ruta in _tablas(propias)
        if any(not isinstance(v, dict) for v in _en(propias, ruta).values())
    }
    repetidas = sorted(".".join(r) for r in definidas & _tablas(del_usuario))
    if repetidas:
        raise Conflicto(
            "tu config.toml ya define " + ", ".join(f"[{r}]" for r in repetidas)
            + ". No agrego el bloque del harness para no duplicar tablas (Codex no arrancaría)."
        )
    try:
        tomllib.loads(final)
    except tomllib.TOMLDecodeError as exc:  # pragma: no cover - red de seguridad
        raise ValueError(f"el resultado no parsea como TOML ({exc}); no escribo nada.") from exc


def _en(documento: dict, ruta: tuple[str, ...]) -> dict:
    for clave in ruta:
        documento = documento[clave]
    return documento


def destino_real(destino: Path) -> Path:
    """El archivo que de verdad se escribe.

    - Un symlink (dotfiles) se sigue: se escribe el archivo al que apunta.
    - En un disco que no distingue mayúsculas (macOS), `AGENTS.md` y `agents.md`
      son el mismo archivo: se escribe con el nombre que ya tiene, sin renombrarlo.
    """
    if destino.exists():
        destino = destino.resolve()
        try:
            for entrada in os.listdir(destino.parent):
                if entrada.lower() == destino.name.lower():
                    return destino.parent / entrada
        except OSError:
            pass
    return destino


def instalar(destino: Path, contenido: str, formato: str, stamp: str) -> str:
    """Aplica el bloque. Devuelve 'creado', 'agregado', 'actualizado' o 'sin cambios'."""
    destino = destino_real(destino)
    existia = destino.is_file()
    actual = destino.read_text(encoding="utf-8") if existia else ""
    final = componer(actual, contenido, formato)
    if formato == "toml":
        revisar_toml(actual, contenido, final)
    if final == actual:
        return "sin cambios"

    estado = "creado"
    if existia:
        _, bloque, _ = partir(actual, formato)
        estado = "actualizado" if bloque is not None else "agregado"
        respaldo = destino.with_name(f"{destino.name}.bak-{stamp}")
        respaldo.write_bytes(destino.read_bytes())

    destino.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporal = tempfile.mkstemp(dir=destino.parent, prefix=f".{destino.name}.")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as archivo:
            archivo.write(final)
        if existia:
            os.chmod(temporal, destino.stat().st_mode & 0o777)
        os.replace(temporal, destino)
    except BaseException:
        Path(temporal).unlink(missing_ok=True)
        raise
    return estado


def main(argv: list[str]) -> int:
    if len(argv) != 5 or argv[3] not in MARCAS:
        print("uso: bloque_gestionado.py <destino> <fuente> <toml|md> <stamp>", file=sys.stderr)
        return 1
    destino, fuente, formato, stamp = Path(argv[1]), Path(argv[2]), argv[3], argv[4]
    try:
        estado = instalar(destino, fuente.read_text(encoding="utf-8"), formato, stamp)
    except Conflicto as exc:
        print(str(exc))
        return 3
    except (OSError, ValueError, tomllib.TOMLDecodeError) as exc:
        print(str(exc))
        return 1
    print(estado)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
