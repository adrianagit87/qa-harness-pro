"""Gate post-shell: lo que escribe un comando de shell también pasa por post-edición.

Un agente no solo edita con su herramienta de edición: también escribe con la
terminal (`printf ... > x.json`, `sed -i`, `python3 gen.py`). El comando no
dice qué archivos toca, y adivinarlo leyendo el texto del shell es frágil. Así
que no se adivina: se compara el disco antes y después.

    antes   (PreToolUse del shell)   foto = ruta -> (mtime_ns, ctime_ns, tamaño)
    después (PostToolUse del shell)  la misma foto, recalculada
    diff                             lo creado o modificado por ESE comando
                                     -> post_edicion.revisar_archivos

Qué entra en la foto: lo que el gate post-edición gobierna. Dentro de la raíz,
los archivos modificados respecto del índice y los no trackeados que no están
ignorados (`git ls-files -m -o --exclude-standard`); un archivo trackeado y
limpio no aparece antes, y si el comando lo cambia aparece después: el diff lo
agarra igual. Afuera de la raíz, solo el baseline configurado, como en
post-edición.

Por qué también ctime: un `cp -p` o un `touch -r` restauran el mtime, pero el
ctime lo pone el kernel y no se puede fijar desde afuera.

Política (la proyección al runtime la decide cada adaptador):
  - sin foto de antes (el pre no corrió, la raíz no es un repo git, la foto no
    se pudo leer) -> None: ABSTENERSE, nunca validar el repo entero a ciegas
  - archivo borrado por el comando                -> nada que revisar
  - archivo creado o modificado                   -> revisar_archivos

Si dos comandos corren a la vez, el diff de uno puede incluir lo del otro: se
revisa de más, nunca de menos.

Lo que el diff no ve: lo que un comando mandado a segundo plano escribe DESPUÉS
de que el runtime da la llamada por terminada (el post ya corrió).

El par pre/post se une por (sesión, id de la llamada): Codex y Claude Code
mandan `tool_use_id`, Cursor lo manda en `preToolUse`/`postToolUse`. Un runtime
sin id por llamada (Antigravity) no se enchufa acá: adivinar el par sería
revisar lo de otro comando.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any

from . import baseline, contract, post_edicion

VERSION = 1
# Una foto sin su post (comando rechazado por el usuario, denegado por otro hook,
# sesión cortada) queda huérfana. Se barren las más viejas que esto.
EDAD_MAXIMA_SEG = 12 * 3600
TIMEOUT_GIT_SEG = 10

Estado = list[int]  # [mtime_ns, ctime_ns, tamaño]


# ── La foto ─────────────────────────────────────────────────────────
def _estado(ruta: Path) -> Estado | None:
    try:
        info = ruta.stat()
    except OSError:
        return None
    return [info.st_mtime_ns, info.st_ctime_ns, info.st_size]


def _entorno_git() -> dict[str, str]:
    """Sin GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE heredados: la raíz manda."""
    return {k: v for k, v in os.environ.items() if k not in {"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"}}


def _gobernados_por_git(raiz: Path) -> list[str] | None:
    try:
        resultado = subprocess.run(
            ["git", "-C", str(raiz), "ls-files", "-m", "-o", "--exclude-standard", "-z"],
            capture_output=True,
            check=False,
            timeout=TIMEOUT_GIT_SEG,
            env=_entorno_git(),
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if resultado.returncode != 0:
        return None
    return [parte for parte in resultado.stdout.decode("utf-8", "surrogateescape").split("\0") if parte]


def tomar_foto(raiz_proyecto: Any, raiz_harness: Any = None) -> dict[str, Any] | None:
    """Foto de lo que gobierna post-edición, o None si no se puede sacar (no es git)."""
    if not isinstance(raiz_proyecto, (str, Path)):
        return None
    try:
        raiz = Path(raiz_proyecto).resolve()
    except (OSError, RuntimeError):
        return None
    relativas = _gobernados_por_git(raiz)
    if relativas is None:
        return None

    archivos: dict[str, Estado | None] = {}
    for relativa in relativas:
        ruta = raiz / relativa
        archivos[str(ruta)] = _estado(ruta)

    configurado = baseline.ruta_configurada(raiz_harness)
    if configurado is not None:
        # Aunque no exista todavía: si el comando lo crea, el diff lo ve.
        archivos[str(configurado)] = _estado(configurado)
    return {"version": VERSION, "raiz": str(raiz), "archivos": archivos}


def cambios(antes: dict[str, Any], despues: dict[str, Any]) -> list[str]:
    """Rutas que el comando creó o modificó, en orden. Lo borrado no deja nada."""
    previos = antes.get("archivos") or {}
    actuales = despues.get("archivos") or {}
    return sorted(
        ruta for ruta, estado in actuales.items() if estado is not None and previos.get(ruta) != estado
    )


def revisar_cambios(antes: Any, raiz_proyecto: Any, raiz_harness: Any = None) -> list[contract.Verdict] | None:
    """Veredictos sobre lo que cambió desde la foto `antes`, o None para abstenerse.

    Abstenerse (None) si no hay foto utilizable, si la de ahora no se puede
    sacar, o si las dos no son de la misma raíz: sin un antes confiable, no hay
    forma honesta de saber qué tocó el comando.
    """
    if not _es_foto(antes):
        return None
    despues = tomar_foto(raiz_proyecto, raiz_harness)
    if despues is None or despues["raiz"] != antes["raiz"]:
        return None
    return post_edicion.revisar_archivos(cambios(antes, despues), despues["raiz"], raiz_harness)


def _es_foto(foto: Any) -> bool:
    return (
        isinstance(foto, dict)
        and foto.get("version") == VERSION
        and isinstance(foto.get("raiz"), str)
        and isinstance(foto.get("archivos"), dict)
    )


# ── Dónde vive la foto entre el pre y el post ───────────────────────
def directorio_de_fotos(nombre: str) -> Path | None:
    """`$TMPDIR/<nombre>`, privado (0700) y nuestro; None si no se puede usar.

    Afuera del repo a propósito: adentro sería un archivo no trackeado más, y
    el diff lo vería. Afuera del home del runtime también: ese es del usuario.
    """
    directorio = Path(tempfile.gettempdir()) / nombre
    try:
        directorio.mkdir(mode=0o700, exist_ok=True)
        info = directorio.lstat()
    except OSError:
        return None
    # Otro usuario (en un /tmp compartido) o un symlink puesto de antemano: no se usa.
    if directorio.is_symlink() or not directorio.is_dir():
        return None
    if hasattr(os, "getuid") and info.st_uid != os.getuid():
        return None
    return directorio


def _archivo_de_foto(directorio: Path, sesion: str, llamada: str) -> Path:
    clave = hashlib.sha256(f"{sesion}\0{llamada}".encode("utf-8")).hexdigest()[:40]
    return directorio / f"{clave}.json"


def guardar_foto(directorio: Path, sesion: str, llamada: str, foto: dict[str, Any]) -> bool:
    """Escritura atómica: el post nunca lee una foto a medias."""
    destino = _archivo_de_foto(directorio, sesion, llamada)
    try:
        descriptor, temporal = tempfile.mkstemp(dir=directorio, prefix=".foto-", suffix=".tmp")
        with os.fdopen(descriptor, "w", encoding="utf-8") as archivo:
            json.dump(foto, archivo)
        os.replace(temporal, destino)
    except (OSError, ValueError):
        return False
    return True


def sacar_foto(directorio: Path, sesion: str, llamada: str) -> Any:
    """Lee la foto y la borra (se usa una sola vez). None si no está o no se lee."""
    origen = _archivo_de_foto(directorio, sesion, llamada)
    try:
        with open(origen, encoding="utf-8") as archivo:
            foto = json.load(archivo)
    except (OSError, ValueError):
        return None
    finally:
        try:
            origen.unlink()
        except OSError:
            pass
    return foto


# ── El par pre/post entero, para los adaptadores ────────────────────
# El aviso va delante de toda falla: el comando ya corrió y lo escrito quedó en
# disco, pero "block" suena a rechazo y el modelo tiende a decir que la
# escritura "fue rechazada".
AVISO_YA_ESCRITO = (
    "Quality gate post-edit: el cambio YA QUEDÓ ESCRITO en disco; este aviso no lo "
    "deshizo ni lo rechazó.\n\n"
)


def clave_de_llamada(sesion: Any, llamada: Any) -> tuple[str, str] | None:
    """(sesión, llamada) que une el pre con el post, o None si falta el id de la llamada.

    El id de la llamada es lo único que distingue dos comandos de la misma
    sesión: sin él no hay par confiable y el post se abstiene. La sesión es
    opcional (acota, no identifica).
    """
    if not isinstance(llamada, str) or not llamada.strip():
        return None
    return (sesion if isinstance(sesion, str) else ""), llamada


def fotografiar(carpeta: str, clave: tuple[str, str] | None, raiz_proyecto: Any, raiz_harness: Any = None) -> None:
    """El lado pre: barre huérfanas y guarda la foto. Nunca falla hacia afuera."""
    directorio = directorio_de_fotos(carpeta)
    if clave is None or directorio is None:
        return
    barrer_viejas(directorio)
    foto = tomar_foto(raiz_proyecto, raiz_harness)
    if foto is not None:
        guardar_foto(directorio, *clave, foto)


def fallas_de_la_llamada(
    carpeta: str, clave: tuple[str, str] | None, raiz_proyecto: Any, raiz_harness: Any = None
) -> list[str]:
    """El lado post: los motivos de lo que ese comando dejó roto. Vacío = nada que decir.

    Vacío también cuando hay que abstenerse (sin clave, sin foto, otra raíz):
    cada adaptador decide si la entrada ILEGIBLE merece otra cosa.
    """
    directorio = directorio_de_fotos(carpeta)
    if clave is None or directorio is None:
        return []
    antes = sacar_foto(directorio, *clave)
    if antes is None:
        return []
    veredictos = revisar_cambios(antes, raiz_proyecto, raiz_harness)
    return [v.motivo for v in veredictos or [] if v.bloquea]


def con_aviso(fallas: list[str], maximo: int) -> str:
    """El aviso entero y el detalle recortado por la cola (donde suele estar el error)."""
    detalle = "\n\n".join(fallas)
    return AVISO_YA_ESCRITO + detalle[-max(0, maximo - len(AVISO_YA_ESCRITO)):]


def barrer_viejas(directorio: Path, edad_maxima: float = EDAD_MAXIMA_SEG, ahora: float | None = None) -> int:
    """Borra las fotos huérfanas más viejas que `edad_maxima`. Devuelve cuántas."""
    limite = (time.time() if ahora is None else ahora) - edad_maxima
    borradas = 0
    try:
        candidatas = list(directorio.iterdir())
    except OSError:
        return 0
    for candidata in candidatas:
        if candidata.suffix not in {".json", ".tmp"}:
            continue
        try:
            if candidata.lstat().st_mtime < limite:
                candidata.unlink()
                borradas += 1
        except OSError:
            continue
    return borradas
