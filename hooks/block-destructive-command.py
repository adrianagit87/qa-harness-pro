#!/usr/bin/env python3
"""PreToolUse gate: block destructive Bash commands before execution."""

from __future__ import annotations

import json
import re
import sys


RULES = (
    (re.compile(r"(?:^|[\s;&|(`])(?:/[^\s;&|]+/)?rm\s+(?=[^\n;&|]*\s-|-[A-Za-z]*[rf])(?=[^\n;&|]*(?:-[A-Za-z]*r|--recursive))(?=[^\n;&|]*(?:-[A-Za-z]*f|--force))"), "rm recursivo y forzado"),
    (re.compile(r"(?:^|[\s;&|(`])git\s+reset\s+--hard(?:\s|$)"), "git reset --hard"),
    (re.compile(r"(?:^|[\s;&|(`])git\s+clean\s+(?![^\n;&|]*(?:-[A-Za-z]*n|--dry-run))(?=[^\n;&|]*(?:-[A-Za-z]*f|--force))(?=[^\n;&|]*(?:-[A-Za-z]*d|--directories))"), "git clean forzado sobre directorios"),
    (re.compile(r"(?:^|[\s;&|(`])git\s+push(?:\s+[^\n;&|]+)*\s(?:--force(?:-with-lease|-if-includes)?|-f)(?:\s|$)"), "git push forzado"),
)


def deny(reason: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"Quality gate: {reason} bloqueado.",
                }
            },
            ensure_ascii=False,
        )
    )


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError):
        deny("entrada inválida del hook")
        return 0

    if payload.get("tool_name") != "Bash":
        deny("herramienta inesperada")
        return 0

    tool_input = payload.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str) or not command.strip():
        deny("comando Bash vacío o inválido")
        return 0

    for pattern, reason in RULES:
        if pattern.search(command):
            deny(reason)
            return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
