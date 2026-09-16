#!/usr/bin/env python3
"""afterFileEdit (Cursor): corre checks deterministicos despues de editar.

afterFileEdit no puede bloquear ni devolver feedback al agente, asi que la falla
se guarda en un archivo de marca. block-destructive-command.py
(beforeShellExecution) la levanta como "ask" en el proximo comando.

Limitacion honesta: si el agente edita y NO corre ningun comando despues, el
aviso queda esperando hasta que corra uno. En la practica casi siempre corre
algo (tests, git), pero no es instantaneo como en Claude Code.
"""

from __future__ import annotations

import ast
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import _cursor  # noqa: E402

run = _cursor.load_original("check-after-edit.py").run


def mark(reason: str) -> None:
    try:
        _cursor.PENDING.parent.mkdir(parents=True, exist_ok=True)
        _cursor.PENDING.write_text(json.dumps({"reason": reason}, ensure_ascii=False), encoding="utf-8")
    except OSError:
        pass


def main() -> int:
    payload = _cursor.read_payload()
    file_raw = payload.get("file_path")
    if not isinstance(file_raw, str) or not file_raw.strip():
        return 0

    root = Path(os.environ.get("QA_HARNESS_ROOT") or _cursor.HARNESS_ROOT).resolve()
    candidate = Path(file_raw)
    target = (candidate if candidate.is_absolute() else root / candidate).resolve()

    try:
        target.relative_to(root)
    except ValueError:
        return 0
    if not target.is_file():
        return 0

    suffix = target.suffix.lower()
    if suffix == ".py":
        try:
            ast.parse(target.read_text(encoding="utf-8"), filename=str(target))
        except (SyntaxError, UnicodeDecodeError) as exc:
            mark(f"Python invalido en {target.name}: {exc}")
            return 0
        ok, output = run(["python3", "-B", "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"], root)
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
        mark(f"fallo {label} despues de editar {target.name}. Corrige el archivo antes de continuar.\n{output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
