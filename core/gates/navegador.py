"""Gate del navegador: la IA ejecuta casos, pero solo donde debe y con lo que debe.

Tres reglas, en este orden:

1. **Dónde.** Solo se navega a orígenes de los ambientes de la empresa activa
   (`environments.list[].urls` y `automation.subprojects[].url`). Un origen de
   un ambiente con `production: true` no se bloquea ni se permite: se PREGUNTA,
   porque solo la persona puede autorizarlo, y en ese momento. Cualquier otro
   origen se bloquea, y la config ilegible también (falla cerrado).

2. **Con qué.** Nunca se escribe un número de tarjeta, y en un campo de
   contraseña, PIN o tarjeta solo se escribe el NOMBRE de un secreto de
   `profile/browser-secrets.env`: Playwright MCP lo sustituye por el valor, y
   el valor real nunca pasa por el modelo.

3. **Dónde terminó.** `--allowed-origins` de Playwright MCP "no es una barrera
   de seguridad y no afecta redirecciones" (su propia doc). Por eso, después de
   cada acción, se lee la `Page URL` que devuelve la respuesta: si un link o una
   redirección dejó al navegador fuera de alcance, se frena ahí.

El gate no sabe en qué runtime corre: devuelve un veredicto (`contract`), y el
adaptador lo proyecta. La memoria de "producción ya confirmada en esta sesión"
la guarda el adaptador; acá solo entra como parámetro.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlsplit

from . import contract, empresa
from .catalogo import NAVEGADOR_CON_ARCHIVOS, NAVEGADOR_PROHIBIDAS, canonico_navegador

# Relativa a la raíz del harness. Está en .gitignore: tiene valores reales.
RUTA_SECRETOS = Path("profile") / "browser-secrets.env"

PUERTOS_POR_DEFECTO = {"http": 80, "https": 443}
URLS_INOCUAS = frozenset({"about:blank"})

# Campos donde nunca se escribe un valor literal, solo el nombre de un secreto.
CAMPO_SENSIBLE = re.compile(
    r"pass(?:word)?|passwd|pwd|contrase[nñ]a|\bclave\b|\bpin\b|cvv|cvc|card|tarjeta|secret|token",
    re.IGNORECASE,
)

# Secuencias de 13 a 19 dígitos, con espacios o guiones entre grupos.
POSIBLE_TARJETA = re.compile(r"(?<!\d)(?:\d[ -]?){12,18}\d(?!\d)")

PAGE_URL = re.compile(r"Page URL:\s*(\S+)")
PESTANA = re.compile(r"^- \d+:.*\]\((\S+)\)\s*$", re.MULTILINE)

MOTIVO_PROHIBIDA = (
    "ejecutar JavaScript o código Playwright arbitrario está prohibido: con eso se navega o se "
    "escribe sin pasar por el gate. Usa las tools de interacción (click, type, snapshot)."
)


@dataclass(frozen=True)
class Alcance:
    """Lo que la empresa activa permite: orígenes y nombres de secretos."""

    permitidos: frozenset[str] = frozenset()
    produccion: frozenset[str] = frozenset()
    secretos: frozenset[str] = frozenset()
    error: str = ""


# ── URLs ────────────────────────────────────────────────────────────────────

def normalizar_url(url: str) -> str:
    """Como lo hace Playwright MCP: sin esquema, `http://` para localhost y `https://` para el resto."""
    url = url.strip()
    if "://" in url or url.lower().startswith(("about:", "data:", "file:", "javascript:", "blob:", "chrome:")):
        return url
    return ("http://" if url.lower().startswith("localhost") else "https://") + url


def origen(url: Any) -> str | None:
    """`esquema://host:puerto` en minúscula, o None si no es una URL http(s) legible.

    Usa el hostname REAL según urllib (`https://dev.acme.com@evil.com` es evil.com).
    """
    if not isinstance(url, str) or not url.strip():
        return None
    try:
        partes = urlsplit(normalizar_url(url))
        esquema = partes.scheme.lower()
        host = (partes.hostname or "").lower().rstrip(".")
        puerto = partes.port or PUERTOS_POR_DEFECTO.get(esquema)
    except ValueError:
        return None
    if esquema not in PUERTOS_POR_DEFECTO or not host or "*" in host:
        return None
    return f"{esquema}://{host}:{puerto}"


# Comodín para previews por rama/ticket (Cloud Run: `<tag>---<servicio>-<hash>.a.run.app`).
# Acotado a propósito: el `*` va solo al inicio del host, reemplaza un pedazo de UNA etiqueta
# (nunca cruza un punto) y lo que sigue tiene que identificar al servicio: al menos 8
# caracteres fijos en esa etiqueta y dos etiquetas más. `*.a.run.app` o `*.com` no valen.
_HOST_CON_COMODIN = re.compile(r"\*([a-z0-9-]{8,}(?:\.[a-z0-9-]+){2,})")


def origen_configurado(url: Any) -> str | None:
    """Lo que vale como entrada de `urls` en la config: un origen, o un patrón con comodín.

    El patrón se devuelve como `esquema://*sufijo:puerto`. None si la entrada no sirve.
    """
    if not isinstance(url, str) or "*" not in url:
        return origen(url)
    try:
        partes = urlsplit(normalizar_url(url))
        esquema = partes.scheme.lower()
        host = (partes.hostname or "").lower().rstrip(".")
        puerto = partes.port or PUERTOS_POR_DEFECTO.get(esquema)
    except ValueError:
        return None
    if esquema not in PUERTOS_POR_DEFECTO or partes.username or partes.password:
        return None
    if not _HOST_CON_COMODIN.fullmatch(host):
        return None
    return f"{esquema}://{host}:{puerto}"


def _en(destino: str, origenes: Iterable[str]) -> bool:
    """¿El origen concreto está declarado, literal o por un patrón con comodín?"""
    for declarado in origenes:
        if declarado == destino:
            return True
        if "*" in declarado:
            antes, despues = declarado.split("*", 1)
            if re.fullmatch(re.escape(antes) + r"[a-z0-9-]+" + re.escape(despues), destino):
                return True
    return False


def revisar_url(url: Any, alcance: Alcance, produccion_confirmada: Iterable[str] = ()) -> contract.Verdict:
    """¿Puede el navegador estar en esta URL?"""
    if alcance.error:
        return contract.bloquear(alcance.error)
    if isinstance(url, str) and url.strip().lower() in URLS_INOCUAS:
        return contract.permitir()
    destino = origen(url)
    if destino is None:
        return contract.bloquear(
            f"URL ilegible o fuera de http/https ({url!r}). Solo se navega a los ambientes configurados."
        )
    if _en(destino, alcance.produccion):
        if destino in set(produccion_confirmada):
            return contract.permitir()
        return contract.preguntar(
            f"{destino} es PRODUCCIÓN. Solo se ejecuta ahí si la persona lo pide explícitamente ahora."
        )
    if _en(destino, alcance.permitidos):
        return contract.permitir()
    return contract.bloquear(
        f"{destino} no es de ningún ambiente de la empresa activa (environments.list[].urls, "
        "automation.subprojects[].url). No se navega fuera de esos orígenes."
    )


# ── Datos que se escriben ───────────────────────────────────────────────────

def luhn_valido(digitos: str) -> bool:
    total = 0
    for posicion, caracter in enumerate(reversed(digitos)):
        valor = int(caracter)
        if posicion % 2 == 1:
            valor *= 2
            if valor > 9:
                valor -= 9
        total += valor
    return total % 10 == 0


def tiene_tarjeta(texto: str) -> bool:
    """¿Hay un número de 13–19 dígitos que pasa el control de Luhn?"""
    for candidato in POSIBLE_TARJETA.findall(texto):
        digitos = re.sub(r"\D", "", candidato)
        if 13 <= len(digitos) <= 19 and luhn_valido(digitos):
            return True
    return False


def _texto(valor: Any) -> str:
    return valor if isinstance(valor, str) else ""


def _escrituras(herramienta: str, entrada: dict[str, Any]) -> list[tuple[str, str, bool]]:
    """(descripción del campo, valor, ¿admite secretos?) de lo que la tool va a escribir."""
    if herramienta.endswith("browser_type"):
        campo = f"{_texto(entrada.get('target'))} {_texto(entrada.get('element'))}"
        return [(campo, _texto(entrada.get("text")), True)]
    if herramienta.endswith("browser_fill_form"):
        resultado = []
        for campo in entrada.get("fields") or []:
            if isinstance(campo, dict):
                descripcion = " ".join(_texto(campo.get(k)) for k in ("name", "element", "target"))
                resultado.append((descripcion, _texto(campo.get("value")), False))
        return resultado
    if herramienta.endswith("browser_select_option"):
        campo = f"{_texto(entrada.get('target'))} {_texto(entrada.get('element'))}"
        valores = entrada.get("values") or []
        return [(campo, _texto(valor), False) for valor in valores]
    if herramienta.endswith("browser_handle_dialog"):
        return [("diálogo", _texto(entrada.get("promptText")), False)]
    if herramienta.endswith("browser_press_sequentially"):
        return [("teclado", _texto(entrada.get("text")), True)]
    return []


def revisar_escritura(herramienta: str, entrada: dict[str, Any], alcance: Alcance) -> contract.Verdict:
    """Ni tarjetas ni contraseñas literales: solo datos de prueba y nombres de secretos."""
    for campo, valor, admite_secretos in _escrituras(herramienta, entrada):
        limpio = valor.strip()
        if not limpio:
            continue
        if admite_secretos and limpio in alcance.secretos:
            continue
        if tiene_tarjeta(valor):
            return contract.bloquear(
                "el texto trae un número de tarjeta (pasa el control de Luhn). Nunca se escriben datos "
                "de tarjeta: si el caso necesita una de prueba, va como secreto en profile/browser-secrets.env."
            )
        if CAMPO_SENSIBLE.search(campo):
            if not admite_secretos:
                return contract.bloquear(
                    f"'{campo.strip()}' es un campo de contraseña, PIN o tarjeta. Llénalo con browser_type "
                    "y el NOMBRE de un secreto de profile/browser-secrets.env, nunca con un valor literal."
                )
            return contract.bloquear(
                f"'{campo.strip()}' es un campo de contraseña, PIN o tarjeta, y '{limpio}' no es el nombre "
                "de ningún secreto de profile/browser-secrets.env. Pide a la persona que lo agregue ahí; "
                "el valor real nunca se escribe en el chat."
            )
    return contract.permitir()


# ── Los dos momentos: antes y después de la acción ──────────────────────────

def revisar_accion(herramienta: Any, entrada: Any, alcance: Alcance) -> contract.Verdict:
    """Antes de la acción (PreToolUse)."""
    canonica = canonico_navegador(herramienta)
    if canonica is None:
        return contract.abstenerse("herramienta inesperada; no es del navegador.")
    if canonica in NAVEGADOR_PROHIBIDAS:
        return contract.bloquear(MOTIVO_PROHIBIDA)
    if not isinstance(entrada, dict):
        return contract.bloquear("entrada vacía o inválida; no pude revisar la acción del navegador.")

    if "url" in entrada and entrada.get("url") not in (None, ""):
        veredicto = revisar_url(entrada.get("url"), alcance)
        if veredicto.decision != contract.PERMITIR:
            return veredicto

    veredicto = revisar_escritura(canonica, entrada, alcance)
    if veredicto.bloquea:
        return veredicto

    if canonica in NAVEGADOR_CON_ARCHIVOS:
        return contract.preguntar("esta acción sube archivos del disco a la aplicación; confírmalo.")
    return contract.permitir()


def produccion_pedida(herramienta: Any, entrada: Any, alcance: Alcance) -> set[str]:
    """Orígenes de producción a los que esta acción navegó A PROPÓSITO.

    Si la acción llegó a ejecutarse, la persona ya confirmó esa pregunta: el
    adaptador lo recuerda para no frenar cada acción siguiente en ese origen.
    """
    if canonico_navegador(herramienta) is None or not isinstance(entrada, dict):
        return set()
    destino = origen(entrada.get("url"))
    return {destino} if _en(destino, alcance.produccion) else set()


def urls_de_la_respuesta(respuesta: Any) -> list[str]:
    """Las URLs donde quedó el navegador, según la respuesta de Playwright MCP."""
    texto = "\n".join(_textos(respuesta))
    return PAGE_URL.findall(texto) + PESTANA.findall(texto)


def revisar_pagina(
    herramienta: Any, respuesta: Any, alcance: Alcance, produccion_confirmada: Iterable[str] = ()
) -> contract.Verdict:
    """Después de la acción (PostToolUse): ¿dónde terminó el navegador?"""
    if canonico_navegador(herramienta) is None:
        return contract.abstenerse("herramienta inesperada; no es del navegador.")
    confirmada = set(produccion_confirmada)
    for url in urls_de_la_respuesta(respuesta):
        veredicto = revisar_url(url, alcance, confirmada)
        if veredicto.decision != contract.PERMITIR:
            return contract.bloquear(
                f"el navegador terminó en {url} (un link o una redirección) y eso no está permitido: "
                f"{veredicto.motivo} Detente: cierra con browser_close, marca el caso ⏭️ Bloqueado "
                "(URL fuera de alcance) y avísale a la persona."
            )
    return contract.permitir()


def _textos(valor: Any) -> list[str]:
    if isinstance(valor, str):
        return [valor]
    if isinstance(valor, list):
        return [texto for elemento in valor for texto in _textos(elemento)]
    if isinstance(valor, dict):
        return [texto for elemento in valor.values() for texto in _textos(elemento)]
    return []


# ── Config de la empresa activa ─────────────────────────────────────────────

def _urls(valor: Any) -> list[str]:
    if isinstance(valor, str):
        return [valor]
    if isinstance(valor, list):
        return [url for url in valor if isinstance(url, str)]
    return []


def alcance_de_config(config: Any, secretos: Iterable[str] = ()) -> Alcance:
    """Orígenes permitidos y de producción a partir de `companies/<empresa>.json`."""
    if not isinstance(config, dict):
        return Alcance(error="la config de la empresa activa no es un objeto JSON.")
    permitidos: set[str] = set()
    produccion: set[str] = set()

    ambientes = config.get("environments", {})
    lista = ambientes.get("list", []) if isinstance(ambientes, dict) else []
    for ambiente in lista if isinstance(lista, list) else []:
        if not isinstance(ambiente, dict):
            continue
        destino = produccion if ambiente.get("production") is True else permitidos
        destino.update(o for o in map(origen_configurado, _urls(ambiente.get("urls"))) if o)

    automatizacion = config.get("automation", {})
    subproyectos = automatizacion.get("subprojects", []) if isinstance(automatizacion, dict) else []
    for subproyecto in subproyectos if isinstance(subproyectos, list) else []:
        if isinstance(subproyecto, dict):
            destino_origen = origen(subproyecto.get("url"))
            if destino_origen:
                permitidos.add(destino_origen)

    # Un origen declarado en producción es producción, aunque además figure en
    # otro lado: ante la duda, se pregunta.
    permitidos -= produccion
    if not permitidos and not produccion:
        return Alcance(
            error="la empresa activa no declara ninguna URL (environments.list[].urls o "
            "automation.subprojects[].url): no hay dónde ejecutar. Corre ./validate-config.sh.",
            secretos=frozenset(secretos),
        )
    return Alcance(frozenset(permitidos), frozenset(produccion), frozenset(secretos))


def nombres_de_secretos(ruta: Path) -> frozenset[str]:
    """Solo los NOMBRES del archivo dotenv; los valores no se leen ni se guardan."""
    try:
        lineas = ruta.read_text(encoding="utf-8").splitlines()
    except OSError:
        return frozenset()
    nombres = set()
    for linea in lineas:
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        nombre = linea.split("=", 1)[0].strip()
        if nombre.startswith("export "):
            nombre = nombre[len("export "):].strip()
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", nombre):
            nombres.add(nombre)
    return frozenset(nombres)


def cargar_alcance(raiz_harness: Any) -> Alcance:
    """profile/profile.json -> activeCompany -> companies/<empresa>.json. Falla cerrado."""
    config, error = empresa.leer_config_activa(raiz_harness)
    if config is None:
        return Alcance(error=error)
    return alcance_de_config(config, nombres_de_secretos(Path(raiz_harness) / RUTA_SECRETOS))


# ── Producción confirmada en esta sesión ────────────────────────────────────
# Vive en la carpeta privada de `post_shell.directorio_de_fotos`. Solo guarda
# orígenes que la persona confirmó con el diálogo del runtime; si no se puede
# leer, vale vacío: el peor caso es volver a frenar, nunca dejar pasar.

def _archivo_de_sesion(directorio: Path, sesion: str) -> Path:
    clave = hashlib.sha256(f"navegador\0{sesion}".encode("utf-8")).hexdigest()[:40]
    return directorio / f"navegador-{clave}.json"


def produccion_confirmada(directorio: Path | None, sesion: Any) -> set[str]:
    if directorio is None or not isinstance(sesion, str) or not sesion:
        return set()
    try:
        datos = json.loads(_archivo_de_sesion(directorio, sesion).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return set()
    return {o for o in datos if isinstance(o, str)} if isinstance(datos, list) else set()


def recordar_produccion(directorio: Path | None, sesion: Any, origenes: Iterable[str]) -> None:
    nuevos = set(origenes)
    if directorio is None or not isinstance(sesion, str) or not sesion or not nuevos:
        return
    todos = sorted(produccion_confirmada(directorio, sesion) | nuevos)
    try:
        descriptor, temporal = tempfile.mkstemp(dir=directorio, prefix=".nav-", suffix=".tmp")
        with os.fdopen(descriptor, "w", encoding="utf-8") as archivo:
            json.dump(todos, archivo)
        os.replace(temporal, _archivo_de_sesion(directorio, sesion))
    except (OSError, ValueError):
        return
