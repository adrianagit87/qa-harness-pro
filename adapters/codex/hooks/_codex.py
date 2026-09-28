"""Contrato de hooks de Codex CLI: leer stdin, proyectar el veredicto.

Contrato de Codex (docs oficiales + los esquemas JSON embebidos en los binarios
0.155.1 y 0.157.1, no adivinado):

    PreToolUse   in : {"session_id", "cwd", "hook_event_name", "tool_name",
                       "tool_input", "tool_use_id", ...}
                 out: {"hookSpecificOutput": {"hookEventName": "PreToolUse",
                       "permissionDecision": "deny",
                       "permissionDecisionReason": str}}
                 OJO: "ask" y "allow" NO estan soportados (el binario los
                 rechaza como "unsupported permissionDecision"). Solo "deny",
                 y con un motivo no vacio.

    PostToolUse  in : lo mismo + "tool_response"
                 out: {"decision": "block", "reason": str}
                 No deshace la edicion: Codex reemplaza el resultado de la
                 herramienta por el motivo y el modelo lo lee como feedback.

    tool_input   Bash y apply_patch traen el texto en `tool_input.command`
                 (en apply_patch, el patch completo). MCP trae los argumentos
                 de la tool tal cual, y el nombre es `mcp__<server>__<tool>`.

    tool_use_id  Obligatorio en PreToolUse y PostToolUse (esquemas de 0.157.1),
                 igual que session_id: es lo que une el pre con el post de una
                 misma llamada (ver la foto de check-after-shell).

ABSTENERSE se proyecta como silencio, como en Cursor y Antigravity: el matcher
de MCP es `mcp__.*`, o sea que este adaptador ve TODA llamada MCP (lecturas
incluidas), y un default restrictivo frenaria al agente entero.

Lo que no es silencio es la entrada ILEGIBLE: cada hook esta enganchado por
matcher a una herramienta que el harness gobierna, asi que un stdin que no se
puede leer es "herramienta gobernada con entrada ilegible" y falla cerrado
(ver core/gates/contract.py).
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

# Raiz del harness: se busca subiendo hasta la marca `core/gates/contract.py`, en
# vez de contar niveles. Este bootstrap esta inline a proposito: hace falta para
# poder importar `core`, asi que no puede depender de nada que viva ahi adentro.
def _raiz_bootstrap() -> Path:
    for candidato in Path(__file__).resolve().parents:
        if (candidato / "core" / "gates" / "contract.py").is_file():
            return candidato
    raise RuntimeError(f"no encuentro la raiz del harness desde {__file__}")


HARNESS_ROOT = _raiz_bootstrap()
if str(HARNESS_ROOT) not in sys.path:
    sys.path.insert(0, str(HARNESS_ROOT))

MAX_FEEDBACK = 4000

# Los nombres con los que Codex (o una version vieja) expone la terminal.
HERRAMIENTAS_DE_SHELL = {"Bash", "shell", "exec_command", "local_shell"}

# Donde espera la foto del disco entre el PreToolUse y el PostToolUse de un
# comando de shell: $TMPDIR/qa-harness-codex (ver core/gates/post_shell).
CARPETA_DE_FOTOS = "qa-harness-codex"

# El block de PostToolUse no deshace nada, pero "block" suena a rechazo y el
# modelo tiende a decir que la edicion "fue rechazada". Se lo dice explicito.
AVISO_YA_ESCRITO = (
    "Quality gate post-edit: el cambio YA QUEDÓ ESCRITO en disco; este aviso no lo "
    "deshizo ni lo rechazó.\n\n"
)


def leer_payload() -> dict[str, Any] | None:
    """Payload del hook, o None si la entrada es ilegible."""
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError, ValueError):
        return None
    return payload if isinstance(payload, dict) else None


def argumentos(payload: dict[str, Any]) -> dict[str, Any]:
    """tool_input como dict. Si llegara serializado (como en Cursor), se desanida."""
    crudo = payload.get("tool_input")
    if isinstance(crudo, dict):
        return crudo
    if isinstance(crudo, str):
        try:
            parseado = json.loads(crudo)
        except (json.JSONDecodeError, ValueError):
            return {}
        return parseado if isinstance(parseado, dict) else {}
    return {}


def comando(payload: dict[str, Any]) -> str | None:
    """`tool_input.command` como texto. Una lista (argv) se une con espacios."""
    valor = argumentos(payload).get("command")
    if isinstance(valor, str):
        return valor
    if isinstance(valor, list) and all(isinstance(parte, str) for parte in valor):
        return " ".join(valor)
    return None


_ENCABEZADOS = {
    "*** Add File:": "agregar",
    "*** Update File:": "actualizar",
    "*** Delete File:": "borrar",
    "*** Move to:": "mover",
}


def archivos_del_patch(patch: str) -> list[str]:
    """Rutas que quedan escritas despues de aplicar un patch de apply_patch.

    El formato de Codex encabeza cada archivo con una linea:

        *** Add File: <ruta>        -> se revisa <ruta>
        *** Update File: <ruta>     -> se revisa <ruta>...
        *** Move to: <nueva>        -> ...salvo que se mueva: entonces <nueva>
        *** Delete File: <ruta>     -> no queda nada que revisar

    Se buscan en cualquier linea (con o sin sangria, LF o CRLF) para tolerar el
    patch envuelto en un heredoc (`apply_patch <<'EOF' ... EOF`). Sin repetidos,
    en el orden del patch.
    """
    rutas: list[str] = []
    ultima: str | None = None  # accion del encabezado anterior
    for linea in patch.splitlines():
        limpia = linea.strip()
        for encabezado, accion in _ENCABEZADOS.items():
            if not limpia.startswith(encabezado):
                continue
            ruta = limpia[len(encabezado):].strip()
            if not ruta:
                break
            if accion == "mover" and ultima == "actualizar":
                # El destino reemplaza al origen del Update que lo encabeza.
                rutas[-1] = ruta
            elif accion == "mover":
                rutas.append(ruta)
            elif accion != "borrar":
                rutas.append(ruta)
            ultima = accion
            break
    vistas: set[str] = set()
    return [r for r in rutas if not (r in vistas or vistas.add(r))]


def es_patch(texto: str) -> bool:
    """¿Trae al menos un encabezado de archivo? (un patch que solo borra, tambien)."""
    return any(linea.strip().startswith(tuple(_ENCABEZADOS)) for linea in texto.splitlines())


def raiz_del_proyecto() -> Path:
    """Raiz contra la que corren los checks post-edicion.

    Los hooks de Codex son globales (~/.codex/hooks.json) y corren en cualquier
    proyecto, igual que en Cursor: por eso la raiz es la del harness (o la que
    fije QA_HARNESS_ROOT), y lo que quede afuera no es asunto de este gate.
    """
    return Path(os.environ.get("QA_HARNESS_ROOT") or HARNESS_ROOT).resolve()


def denegar(mensaje: str) -> None:
    """PreToolUse: deny. Codex exige un motivo no vacio."""
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": mensaje or "Quality gate: bloqueado.",
                }
            },
            ensure_ascii=False,
        )
    )


def frenar(mensaje: str) -> None:
    """PostToolUse: block, con el feedback que vuelve al modelo."""
    print(json.dumps({"decision": "block", "reason": mensaje[-MAX_FEEDBACK:]}, ensure_ascii=False))


def frenar_ya_escrito(fallas: list[str]) -> None:
    """PostToolUse: block sobre archivos que YA se escribieron.

    El aviso va siempre entero; si hay que recortar, se recorta el detalle (se
    queda la cola, que es donde suele estar el error).
    """
    detalle = "\n\n".join(fallas)
    frenar(AVISO_YA_ESCRITO + detalle[-(MAX_FEEDBACK - len(AVISO_YA_ESCRITO)):])


def sesion_y_llamada(payload: dict[str, Any]) -> tuple[str, str] | None:
    """(session_id, tool_use_id) de la llamada, o None si falta el tool_use_id."""
    llamada = payload.get("tool_use_id")
    if not isinstance(llamada, str) or not llamada.strip():
        return None
    sesion = payload.get("session_id")
    return (sesion if isinstance(sesion, str) else ""), llamada
