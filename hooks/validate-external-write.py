#!/usr/bin/env python3
"""PreToolUse gate: validate Jira/Confluence/Notion write payloads.

Cubre tambien la creacion/edicion de issues de Jira (backend docs.backend=jira),
donde el contenido publicable viaja en `summary` y `description`.
"""

from __future__ import annotations

import json
import re
import sys
from typing import Any


SUPPORTED_TOOLS = {
    "mcp__atlassian__addCommentToJiraIssue",
    "mcp__atlassian__createJiraIssue",
    "mcp__atlassian__editJiraIssue",
    "mcp__atlassian__createConfluencePage",
    "mcp__atlassian__updateConfluencePage",
    "mcp__notion__notion-create-pages",
    "mcp__notion__notion-update-page",
}

CONTENT_KEYS = {
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
}

PLACEHOLDERS = (
    re.compile(r"\bPON[-_ ]?AQU[IÍ]\b", re.IGNORECASE),
    re.compile(r"\bREEMPLAZ(?:A|AR)[-_ ]?AQU[IÍ]\b", re.IGNORECASE),
    re.compile(r"\b(?:TODO|TBD)\s*:", re.IGNORECASE),
    re.compile(r"\{\{[^{}]+\}\}"),
    re.compile(r"<(?:TICKET|ID|NOMBRE|FECHA|URL|EMPRESA)>", re.IGNORECASE),
    re.compile(r"\bYOUR_[A-Z0-9_]+\b"),
    re.compile(r"\btuempresa\.atlassian\.net\b", re.IGNORECASE),
)


def deny(reason: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"Quality gate de publicación: {reason}",
                }
            },
            ensure_ascii=False,
        )
    )


def strings(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        result: list[str] = []
        for item in value:
            result.extend(strings(item))
        return result
    if isinstance(value, dict):
        result = []
        for item in value.values():
            result.extend(strings(item))
        return result
    return []


def publication_content(value: Any) -> list[str]:
    if not isinstance(value, dict):
        return []
    result: list[str] = []
    for key, item in value.items():
        if str(key).lower() in CONTENT_KEYS:
            result.extend(strings(item))
        elif isinstance(item, (dict, list)):
            result.extend(publication_content(item))
    return result


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError):
        deny("entrada inválida; no pude inspeccionar lo que iba a salir.")
        return 0

    tool_name = payload.get("tool_name")
    if tool_name not in SUPPORTED_TOOLS:
        deny("herramienta inesperada; el gate no tiene un contrato para validarla.")
        return 0

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        deny("payload vacío o inválido.")
        return 0

    pieces = [piece.strip() for piece in publication_content(tool_input) if piece.strip()]
    if not pieces:
        deny("no encontré contenido publicable en el payload; se bloquea por seguridad.")
        return 0

    combined = "\n".join(pieces)
    if len(combined) < 3:
        deny("el contenido está vacío o es demasiado corto para verificarse.")
        return 0

    for pattern in PLACEHOLDERS:
        match = pattern.search(combined)
        if match:
            deny(f"quedó un placeholder sin resolver ({match.group(0)!r}).")
            return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
