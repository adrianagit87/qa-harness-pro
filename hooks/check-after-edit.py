#!/usr/bin/env python3
"""PostToolUse gate: run fast deterministic checks after Edit or Write."""

from __future__ import annotations

import ast
import json
import os
import subprocess
import sys
from pathlib import Path


MAX_FEEDBACK = 4000


def block(reason: str) -> None:
    print(json.dumps({"decision": "block", "reason": reason[-MAX_FEEDBACK:]}, ensure_ascii=False))


def run(command: list[str], cwd: Path) -> tuple[bool, str]:
    result = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        capture_output=True,
        check=False,
        env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
    )
    output = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
    return result.returncode == 0, output


def project_file(payload: dict) -> tuple[Path, Path] | None:
    root_raw = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd")
    tool_input = payload.get("tool_input")
    file_raw = tool_input.get("file_path") if isinstance(tool_input, dict) else None
    if not isinstance(root_raw, str) or not isinstance(file_raw, str) or not file_raw.strip():
        return None

    root = Path(root_raw).resolve()
    candidate = Path(file_raw)
    if not candidate.is_absolute():
        candidate = root / candidate
    target = candidate.resolve()
    try:
        target.relative_to(root)
    except ValueError:
        return None
    return root, target


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, TypeError):
        block("Quality gate post-edit: entrada inválida; no pude verificar el cambio.")
        return 0

    if payload.get("tool_name") not in {"Edit", "Write"}:
        block("Quality gate post-edit: herramienta inesperada; no pude verificar el cambio.")
        return 0

    resolved = project_file(payload)
    if resolved is None:
        block("Quality gate post-edit: archivo vacío o fuera de la raíz del proyecto.")
        return 0
    root, target = resolved

    if not target.is_file():
        block(f"Quality gate post-edit: el archivo no existe después del cambio: {target}")
        return 0

    suffix = target.suffix.lower()
    if suffix == ".py":
        try:
            ast.parse(target.read_text(encoding="utf-8"), filename=str(target))
        except (SyntaxError, UnicodeDecodeError) as exc:
            block(f"Quality gate post-edit: Python inválido en {target.name}:\n{exc}")
            return 0
        ok, output = run(
            ["python3", "-B", "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
            root,
        )
        label = "tests Python"
    elif suffix == ".sh":
        ok, output = run(["bash", "-n", str(target)], root)
        label = "sintaxis Bash"
    elif suffix == ".json":
        ok, output = run(["python3", "-m", "json.tool", str(target)], root)
        label = "JSON"
    else:
        return 0

    if not ok:
        detail = output or "el comando terminó con error y no produjo salida"
        block(
            f"Quality gate post-edit: falló {label} después de editar {target.name}. "
            f"Corrige el archivo antes de continuar.\n{detail}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
