"""Catálogo único de las herramientas externas que el harness gobierna.

Los tres runtimes nombran la misma herramienta de formas distintas
(`mcp__atlassian__createJiraIssue`, `atlassian.createJiraIssue`,
`atlassian_create_jira_issue`) y el naming de las tools MCP en Antigravity ni
siquiera está documentado. Por eso cada entrada se reconoce por patrón y se
responde con un id canónico: el nombre que usa Claude Code, que es el que viaja
a `.claude/settings.json` y a `validate-config.sh`.

Esta es la fuente de verdad. Agregar una herramienta acá la habilita en los tres
runtimes, y `tests/test_core_catalogo.py` falla si la configuración se desfasa.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass(frozen=True)
class Herramienta:
    """Una herramienta externa: su id canónico y cómo reconocerla."""

    id: str
    patron: re.Pattern[str]


def _herramienta(identificador: str, *variantes: str) -> Herramienta:
    return Herramienta(identificador, re.compile("|".join(variantes), re.IGNORECASE))


# Cambiar el estado de un ticket: prohibido siempre, en cualquier runtime.
TRANSICIONES: tuple[Herramienta, ...] = (
    _herramienta(
        "mcp__atlassian__transitionJiraIssue",
        r"transition[_\-]?jira", r"jira.*transition",
    ),
)

# Escrituras hacia afuera: exigen contenido completo y confirmación explícita.
PUBLICACIONES: tuple[Herramienta, ...] = (
    _herramienta(
        "mcp__atlassian__addCommentToJiraIssue",
        r"add[_\-]?comment.*jira", r"jira.*add[_\-]?comment",
    ),
    _herramienta(
        "mcp__atlassian__createJiraIssue",
        r"create[_\-]?jira[_\-]?issue", r"jira.*create.*issue",
    ),
    _herramienta(
        "mcp__atlassian__editJiraIssue",
        r"edit[_\-]?jira[_\-]?issue", r"jira.*edit.*issue", r"jira.*update.*issue",
    ),
    _herramienta(
        "mcp__atlassian__createConfluencePage",
        r"create[_\-]?confluence[_\-]?page", r"confluence.*create.*page",
    ),
    _herramienta(
        "mcp__atlassian__updateConfluencePage",
        r"update[_\-]?confluence[_\-]?page", r"confluence.*update.*page",
    ),
    _herramienta(
        "mcp__notion__notion-create-pages",
        r"notion.*create", r"create.*notion",
    ),
    _herramienta(
        "mcp__notion__notion-update-page",
        r"notion.*update", r"update.*notion",
    ),
)

IDS_TRANSICION: tuple[str, ...] = tuple(entrada.id for entrada in TRANSICIONES)
IDS_PUBLICACION: tuple[str, ...] = tuple(entrada.id for entrada in PUBLICACIONES)


def canonico(nombre: object) -> str | None:
    """Id canónico de la herramienta, o None si el harness no la gobierna."""
    if not isinstance(nombre, str) or not nombre:
        return None
    for entrada in TRANSICIONES + PUBLICACIONES:
        if entrada.patron.search(nombre):
            return entrada.id
    return None


def es_transicion(nombre: object) -> bool:
    """¿Es un cambio de estado de ticket, lo único prohibido sin excepción?"""
    return canonico(nombre) in IDS_TRANSICION


def es_publicacion(nombre: object) -> bool:
    """¿Es una escritura hacia afuera que este harness sabe validar?"""
    return canonico(nombre) in IDS_PUBLICACION
