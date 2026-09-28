"""Gate de publicación: nada sale hacia Jira/Confluence/Notion a medio hacer.

Cubre también la creación/edición de issues de Jira (backend docs.backend=jira),
donde el contenido publicable viaja en `summary` y `description`.
"""

from __future__ import annotations

import re
from typing import Any

from . import contract
from .catalogo import es_publicacion, es_transicion

CLAVES_DE_CONTENIDO = frozenset({
    "body",
    "comment",
    "commentbody",
    "content",
    "description",
    "insert_content",
    "markdown",
    "new_str",
    "pages",
    "properties",
    "summary",
    "text",
})

PLACEHOLDERS = (
    re.compile(r"\bPON[-_ ]?AQU[IÍ]\b", re.IGNORECASE),
    re.compile(r"\bREEMPLAZ(?:A|AR)[-_ ]?AQU[IÍ]\b", re.IGNORECASE),
    re.compile(r"\b(?:TODO|TBD)\s*:", re.IGNORECASE),
    re.compile(r"\{\{[^{}]+\}\}"),
    re.compile(r"<(?:TICKET|ID|NOMBRE|FECHA|URL|EMPRESA)>", re.IGNORECASE),
    re.compile(r"\bYOUR_[A-Z0-9_]+\b"),
    re.compile(r"\btuempresa\.atlassian\.net\b", re.IGNORECASE),
)

MOTIVO_TRANSICION = (
    "cambiar el estado de un ticket de Jira está prohibido en este harness. "
    "Eso lo hace la persona a mano, siempre."
)

# Clasificador de lecturas: se compara por palabra completa, no por subcadena, y
# en cualquier convención de nombre. getJiraIssue, atlassian_get_jira_issue y
# notion-get-comments son lecturas y no se tocan.
VERBOS_DE_LECTURA = frozenset({"get", "search", "fetch", "list", "read", "view", "lookup"})

# Si el nombre trae cualquiera de estos verbos NO es lectura, aunque también
# traiga uno de lectura (notion-update-view). Ante la duda, no es lectura.
VERBOS_DE_ESCRITURA = frozenset({
    "add", "append", "archive", "assign", "convert", "create", "delete", "duplicate",
    "edit", "insert", "move", "patch", "post", "publish", "put", "remove", "replace",
    "send", "set", "spawn", "stop", "transition", "update", "upload", "write",
})


def palabras(nombre: str) -> set[str]:
    """Palabras del nombre en minúscula: mcp__atlassian__getJiraIssue ->
    {"mcp", "atlassian", "get", "jira", "issue"}."""
    espaciado = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", " ", nombre)
    return {palabra.lower() for palabra in re.split(r"[^A-Za-z0-9]+", espaciado) if palabra}


def es_lectura(nombre: str) -> bool:
    """Una tool es lectura si trae un verbo de lectura y ninguno de escritura."""
    encontradas = palabras(nombre)
    return bool(encontradas & VERBOS_DE_LECTURA) and not (encontradas & VERBOS_DE_ESCRITURA)


def textos(valor: Any) -> list[str]:
    """Todos los strings que cuelgan de un valor, a cualquier profundidad."""
    if isinstance(valor, str):
        return [valor]
    if isinstance(valor, list):
        resultado: list[str] = []
        for elemento in valor:
            resultado.extend(textos(elemento))
        return resultado
    if isinstance(valor, dict):
        resultado = []
        for elemento in valor.values():
            resultado.extend(textos(elemento))
        return resultado
    return []


def contenido_publicable(valor: Any) -> list[str]:
    """Lo que realmente se va a publicar, buscando por claves de contenido."""
    if not isinstance(valor, dict):
        return []
    resultado: list[str] = []
    for clave, elemento in valor.items():
        if str(clave).lower() in CLAVES_DE_CONTENIDO:
            resultado.extend(textos(elemento))
        elif isinstance(elemento, (dict, list)):
            resultado.extend(contenido_publicable(elemento))
    return resultado


def revisar_transicion(herramienta: Any) -> contract.Verdict:
    """Regla aparte porque no todos los runtimes la consultan.

    En Claude Code la prohibición vive en `permissions.deny` de
    `.claude/settings.json`, así que el hook nunca ve estas llamadas. Cursor,
    Antigravity y Codex no tienen ese allowlist: sus adaptadores preguntan acá
    primero (Codex, además, saca la tool de la lista con `disabled_tools`).
    """
    if es_transicion(herramienta):
        return contract.bloquear(MOTIVO_TRANSICION)
    return contract.abstenerse()


def revisar_publicacion(herramienta: Any, payload: Any) -> contract.Verdict:
    """Revisa lo que está por publicarse hacia afuera.

    Una herramienta que el catálogo no reconoce no es asunto de este gate; cada
    runtime decide qué hacer con esa abstención (ver `contract`).
    """
    if not es_publicacion(herramienta):
        return contract.abstenerse("herramienta inesperada; el gate no tiene un contrato para validarla.")

    if not isinstance(payload, dict):
        return contract.bloquear("payload vacío o inválido.")

    piezas = [pieza.strip() for pieza in contenido_publicable(payload) if pieza.strip()]
    if not piezas:
        return contract.bloquear("no encontré contenido publicable en el payload; se bloquea por seguridad.")

    combinado = "\n".join(piezas)
    if len(combinado) < 3:
        return contract.bloquear("el contenido está vacío o es demasiado corto para verificarse.")

    for patron in PLACEHOLDERS:
        encontrado = patron.search(combinado)
        if encontrado:
            return contract.bloquear(f"quedó un placeholder sin resolver ({encontrado.group(0)!r}).")

    return contract.permitir()
