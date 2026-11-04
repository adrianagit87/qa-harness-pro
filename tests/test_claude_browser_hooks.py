#!/usr/bin/env python3
"""Hooks del navegador en Claude Code: el veredicto se proyecta bien.

Corren como procesos aparte sobre un harness temporal con su propia config, y
con un $TMPDIR propio (ahí vive la memoria de producción confirmada).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness_temporal import copiar_harness  # noqa: E402

CONFIG = {
    "company": {"name": "Acme", "key": "ACME"},
    "environments": {
        "default": "DEV",
        "list": [
            {"key": "DEV", "urls": ["https://dev.acme.test"], "production": False},
            {"key": "PROD", "urls": ["https://app.acme.test"], "production": True},
        ],
    },
}


class HooksDelNavegador(unittest.TestCase):
    def setUp(self) -> None:
        self._temporal = tempfile.TemporaryDirectory()
        raiz = Path(self._temporal.name)
        harness = raiz / "harness"
        self.hooks = copiar_harness(harness, "claude")
        (harness / "profile").mkdir()
        (harness / "companies").mkdir()
        (harness / "profile" / "profile.json").write_text(json.dumps({"activeCompany": "acme"}), encoding="utf-8")
        (harness / "companies" / "acme.json").write_text(json.dumps(CONFIG), encoding="utf-8")
        (harness / "profile" / "browser-secrets.env").write_text("QA_USER_PASSWORD=x\n", encoding="utf-8")
        self.tmpdir = raiz / "tmp"
        self.tmpdir.mkdir()

    def tearDown(self) -> None:
        self._temporal.cleanup()

    def correr(self, hook: str, payload: object, *, raw: str | None = None) -> dict | None:
        entorno = {**os.environ, "TMPDIR": str(self.tmpdir)}
        entorno.pop("CLAUDE_PROJECT_DIR", None)
        resultado = subprocess.run(
            [sys.executable, "-B", str(self.hooks / hook)],
            input=raw if raw is not None else json.dumps(payload),
            text=True,
            capture_output=True,
            check=False,
            env=entorno,
        )
        self.assertEqual(resultado.returncode, 0, resultado.stderr)
        return json.loads(resultado.stdout) if resultado.stdout.strip() else None

    def pre(self, tool: str, entrada: object) -> dict | None:
        return self.correr(
            "validate-browser-action.py",
            {"hook_event_name": "PreToolUse", "session_id": "s1", "tool_name": f"mcp__playwright__{tool}", "tool_input": entrada},
        )

    def post(self, tool: str, entrada: object, url: str) -> dict | None:
        respuesta = [{"type": "text", "text": f"### Page\n- Page URL: {url}\n- Page Title: X\n"}]
        return self.correr(
            "check-browser-page.py",
            {
                "hook_event_name": "PostToolUse",
                "session_id": "s1",
                "tool_name": f"mcp__playwright__{tool}",
                "tool_input": entrada,
                "tool_response": respuesta,
            },
        )

    def decision(self, salida: dict | None) -> str | None:
        return None if salida is None else salida["hookSpecificOutput"]["permissionDecision"]

    # ── PreToolUse ──────────────────────────────────────────────────────────
    def test_ambiente_configurado_pasa_en_silencio(self) -> None:
        self.assertIsNone(self.pre("browser_navigate", {"url": "https://dev.acme.test/login"}))
        self.assertIsNone(self.pre("browser_type", {"target": "#p", "element": "Contraseña", "text": "QA_USER_PASSWORD"}))

    def test_produccion_le_pregunta_a_la_persona(self) -> None:
        salida = self.pre("browser_navigate", {"url": "https://app.acme.test"})
        self.assertEqual(self.decision(salida), "ask")
        self.assertIn("PRODUCCIÓN", salida["hookSpecificOutput"]["permissionDecisionReason"])

    def test_fuera_de_alcance_tarjeta_y_javascript_se_deniegan(self) -> None:
        for tool, entrada in (
            ("browser_navigate", {"url": "https://evil.test"}),
            ("browser_type", {"target": "e1", "element": "Notas", "text": "4111111111111111"}),
            ("browser_type", {"target": "#p", "element": "Password", "text": "hunter2"}),
            ("browser_evaluate", {"function": "() => 1"}),
        ):
            with self.subTest(tool=tool, entrada=entrada):
                self.assertEqual(self.decision(self.pre(tool, entrada)), "deny")

    def test_entrada_ilegible_y_herramienta_ajena_se_deniegan(self) -> None:
        self.assertEqual(self.decision(self.correr("validate-browser-action.py", None, raw="no json")), "deny")
        ajena = {"hook_event_name": "PreToolUse", "tool_name": "mcp__atlassian__getJiraIssue", "tool_input": {}}
        self.assertEqual(self.decision(self.correr("validate-browser-action.py", ajena)), "deny")

    def test_sin_config_falla_cerrado(self) -> None:
        (self.hooks.parents[2] / "companies" / "acme.json").unlink()
        self.assertEqual(self.decision(self.pre("browser_navigate", {"url": "https://dev.acme.test"})), "deny")

    def test_bajo_cursor_cede(self) -> None:
        payload = {
            "hook_event_name": "preToolUse",
            "cursor_version": "3.21.9",
            "tool_name": "mcp__playwright__browser_navigate",
            "tool_input": {"url": "https://evil.test"},
        }
        self.assertEqual(self.correr("validate-browser-action.py", payload), {})

    # ── PostToolUse ─────────────────────────────────────────────────────────
    def test_redireccion_fuera_de_alcance_frena(self) -> None:
        salida = self.post("browser_click", {"target": "e3"}, "https://evil.test/x")
        self.assertEqual(salida["decision"], "block")
        self.assertIn("Bloqueado", salida["reason"])

    def test_dentro_de_alcance_pasa_en_silencio(self) -> None:
        self.assertIsNone(self.post("browser_click", {"target": "e3"}, "https://dev.acme.test/x"))

    def test_produccion_confirmada_queda_recordada_solo_para_esa_sesion(self) -> None:
        # Una redirección a producción que nadie pidió: se frena.
        self.assertEqual(self.post("browser_click", {"target": "e3"}, "https://app.acme.test/")["decision"], "block")
        # La persona confirmó el ask y la navegación se ejecutó: queda recordada.
        self.assertIsNone(self.post("browser_navigate", {"url": "https://app.acme.test"}, "https://app.acme.test/"))
        self.assertIsNone(self.post("browser_click", {"target": "e3"}, "https://app.acme.test/otra"))
        # Otra sesión no hereda la confirmación.
        otra = {
            "hook_event_name": "PostToolUse",
            "session_id": "s2",
            "tool_name": "mcp__playwright__browser_click",
            "tool_input": {"target": "e3"},
            "tool_response": [{"type": "text", "text": "- Page URL: https://app.acme.test/otra\n"}],
        }
        self.assertEqual(self.correr("check-browser-page.py", otra)["decision"], "block")


if __name__ == "__main__":
    unittest.main(verbosity=2)
