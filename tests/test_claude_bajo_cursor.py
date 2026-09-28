#!/usr/bin/env python3
"""Los hooks de Claude Code, disparados por Cursor.

Cursor 3.21.9, con "Include Third-Party Plugins, Skills, and Other Configs"
prendido (el default), carga los hooks de `.claude/settings.json` y los corre
con SU payload (leído del bundle, ver adapters/cursor/README.md):

    {"hook_event_name": "preToolUse", "tool_name": "Shell",
     "cursor_version": "3.21.9", "workspace_roots": [...], ...}

Ese runtime ya lo gobiernan los hooks de adapters/cursor/: el adaptador de
Claude se hace a un lado con `{}`. Para Claude Code nada cambia: un payload
suyo con una herramienta inesperada sigue frenando.

Cada hook corre en un proceso aparte con HOME y TMPDIR en un sandbox.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
HOOKS = RAIZ / "adapters" / "claude" / "hooks"
sys.path.insert(0, str(HOOKS))
import _claude  # noqa: E402

DESTRUCTIVO = "rm -rf /tmp/demo"


def payload_de_cursor(evento: str, tool_name: str, tool_input: dict, **extra: object) -> dict:
    """Lo que arma el ejecutor de hooks de Cursor: el request + estos campos."""
    return {
        "conversation_id": "conv-1",
        "generation_id": "gen-1",
        "tool_name": tool_name,
        "tool_input": tool_input,
        "tool_use_id": "tool-1",
        "session_id": "conv-1",
        "hook_event_name": evento,
        "cursor_version": "3.21.9",
        "workspace_roots": [str(RAIZ)],
        "user_email": None,
        "transcript_path": None,
        **extra,
    }


class HooksBajoCursor(unittest.TestCase):
    def setUp(self) -> None:
        temporal = tempfile.TemporaryDirectory()
        self.addCleanup(temporal.cleanup)
        self.home = Path(temporal.name).resolve()
        self.tmp = self.home / "tmp"
        self.tmp.mkdir()

    def correr(self, hook: str, payload: dict | None = None, *, crudo: str | None = None,
               entorno: dict[str, str] | None = None) -> str:
        env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE_", "CURSOR_"))}
        env.update({"HOME": str(self.home), "TMPDIR": str(self.tmp), **(entorno or {})})
        resultado = subprocess.run(
            ["python3", str(HOOKS / hook)],
            input=crudo if crudo is not None else json.dumps(payload),
            text=True, capture_output=True, check=False, env=env,
        )
        self.assertEqual(resultado.returncode, 0, resultado.stderr)
        return resultado.stdout.strip()

    # ── Cursor: se hace a un lado ────────────────────────────────────────

    def test_bajo_cursor_cada_hook_responde_vacio(self) -> None:
        casos = (
            ("block-destructive-command.py", payload_de_cursor("preToolUse", "Shell", {"command": DESTRUCTIVO})),
            ("snapshot-before-shell.py", payload_de_cursor("preToolUse", "Shell", {"command": "ls"})),
            ("check-after-shell.py", payload_de_cursor("postToolUse", "Shell", {"command": "ls"})),
            ("check-after-shell.py", payload_de_cursor("postToolUseFailure", "Shell", {"command": "false"})),
            ("check-after-edit.py", payload_de_cursor("postToolUse", "Write", {"file_path": "x.json"})),
            ("validate-external-write.py",
             payload_de_cursor("preToolUse", "MCP:addCommentToJiraIssue", {"body": "PON-AQUI-EL-ID"})),
        )
        for hook, payload in casos:
            with self.subTest(hook=hook, evento=payload["hook_event_name"]):
                self.assertEqual(self.correr(hook, payload), "{}")

    def test_bajo_cursor_no_saca_foto(self) -> None:
        self.correr("snapshot-before-shell.py", payload_de_cursor("preToolUse", "Shell", {"command": "ls"}))
        self.assertFalse((self.tmp / _claude.CARPETA_DE_FOTOS).exists())

    def test_bajo_cursor_no_depende_del_entorno(self) -> None:
        # La marca es el payload: con o sin CURSOR_* / CLAUDE_PROJECT_DIR, igual.
        payload = payload_de_cursor("preToolUse", "Shell", {"command": DESTRUCTIVO})
        entorno = {"CURSOR_VERSION": "3.21.9", "CURSOR_PROJECT_DIR": str(RAIZ), "CLAUDE_PROJECT_DIR": str(RAIZ)}
        self.assertEqual(self.correr("block-destructive-command.py", payload, entorno=entorno), "{}")

    # ── Claude Code: nada cambia ─────────────────────────────────────────

    def assert_deniega(self, salida: str, motivo: str) -> None:
        decision = json.loads(salida)["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "deny")
        self.assertIn(motivo, decision["permissionDecisionReason"])

    def test_payload_de_claude_con_shell_sigue_frenando(self) -> None:
        payload = {"hook_event_name": "PreToolUse", "tool_name": "Shell", "tool_input": {"command": "ls"}}
        self.assert_deniega(self.correr("block-destructive-command.py", payload), "herramienta inesperada")

    def test_payload_de_claude_destructivo_sigue_frenando(self) -> None:
        payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": DESTRUCTIVO}}
        self.assert_deniega(self.correr("block-destructive-command.py", payload), "rm recursivo y forzado")

    def test_una_sola_marca_no_alcanza(self) -> None:
        # cursor_version con un evento de Claude Code, o un evento camelCase sin
        # cursor_version: no es Cursor, y el gate evalúa como siempre.
        casos = (
            {"hook_event_name": "PreToolUse", "cursor_version": "3.21.9"},
            {"hook_event_name": "preToolUse"},
            {"hook_event_name": "preToolUse", "cursor_version": 3},
        )
        for marcas in casos:
            with self.subTest(marcas=marcas):
                payload = {"tool_name": "Bash", "tool_input": {"command": DESTRUCTIVO}, **marcas}
                self.assert_deniega(self.correr("block-destructive-command.py", payload), "rm recursivo y forzado")

    def test_payload_de_claude_en_post_edit_con_herramienta_rara_frena(self) -> None:
        payload = {"hook_event_name": "PostToolUse", "tool_name": "Shell", "tool_input": {}}
        salida = json.loads(self.correr("check-after-edit.py", payload))
        self.assertEqual(salida["decision"], "block")
        self.assertIn("herramienta inesperada", salida["reason"])

    def test_entrada_ilegible_sigue_frenando(self) -> None:
        self.assert_deniega(self.correr("block-destructive-command.py", crudo="no es json"), "entrada inválida")


class MarcaDeCursor(unittest.TestCase):
    def test_reconoce_el_payload_de_cursor(self) -> None:
        for evento in ("preToolUse", "postToolUse", "postToolUseFailure"):
            with self.subTest(evento=evento):
                self.assertTrue(_claude.lo_invoca_cursor(payload_de_cursor(evento, "Shell", {})))

    def test_no_confunde_el_payload_de_claude(self) -> None:
        for evento in ("PreToolUse", "PostToolUse", "PostToolUseFailure"):
            with self.subTest(evento=evento):
                self.assertFalse(_claude.lo_invoca_cursor({"hook_event_name": evento, "tool_name": "Bash"}))

    def test_tool_name_shell_solo_no_es_cursor(self) -> None:
        self.assertFalse(_claude.lo_invoca_cursor({"hook_event_name": "PreToolUse", "tool_name": "Shell"}))


if __name__ == "__main__":
    unittest.main()
