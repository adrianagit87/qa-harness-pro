"""Unit tests de los hooks portados a Antigravity.

Verifican el contrato de Antigravity ({"decision": ..., "reason": ...}) y, sobre
todo, que el default sea NO OPINAR: estos hooks corren con matcher "*", así que
un default restrictivo bloquearía el agente entero.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOKS = ROOT / "antigravity" / "hooks"


def run_hook(script: str, payload: dict) -> str:
    result = subprocess.run(
        [sys.executable, str(HOOKS / script)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    )
    return result.stdout.strip()


def call(name: str, args: dict | None = None) -> dict:
    return {"toolCall": {"name": name, "args": args or {}}}


class BlockDestructiveCommand(unittest.TestCase):
    HOOK = "block-destructive-command.py"

    def test_bloquea_rm_recursivo_forzado(self):
        out = json.loads(run_hook(self.HOOK, call("run_command", {"CommandLine": "rm -rf /tmp/x"})))
        self.assertEqual(out["decision"], "deny")

    def test_bloquea_push_forzado(self):
        out = json.loads(run_hook(self.HOOK, call("run_command", {"CommandLine": "git push --force origin main"})))
        self.assertEqual(out["decision"], "deny")

    def test_no_opina_sobre_comando_inocuo(self):
        self.assertEqual(run_hook(self.HOOK, call("run_command", {"CommandLine": "ls -la"})), "")

    def test_no_opina_sobre_otra_herramienta(self):
        self.assertEqual(run_hook(self.HOOK, call("view_file", {"path": "a.txt"})), "")


class ValidateExternalWrite(unittest.TestCase):
    HOOK = "validate-external-write.py"

    def test_deniega_transicion_de_jira(self):
        out = json.loads(run_hook(self.HOOK, call("mcp__atlassian__transitionJiraIssue", {"issueIdOrKey": "US-1"})))
        self.assertEqual(out["decision"], "deny")

    def test_deniega_placeholder_sin_resolver(self):
        payload = call("mcp__atlassian__createJiraIssue",
                       {"summary": "CP-01", "description": "Tabla: PON-AQUI-EL-ID"})
        out = json.loads(run_hook(self.HOOK, payload))
        self.assertEqual(out["decision"], "deny")
        self.assertIn("placeholder", out["reason"])

    def test_pide_confirmacion_explicita_en_escritura_limpia(self):
        payload = call("mcp__atlassian__createJiraIssue",
                       {"summary": "[PROJ-123][QA] CP-01", "description": "## Objetivo. Validar."})
        out = json.loads(run_hook(self.HOOK, payload))
        self.assertEqual(out["decision"], "force_ask")

    def test_deniega_payload_sin_contenido_publicable(self):
        out = json.loads(run_hook(self.HOOK, call("mcp__atlassian__createJiraIssue", {"projectKey": "QA"})))
        self.assertEqual(out["decision"], "deny")

    def test_no_opina_sobre_lectura(self):
        self.assertEqual(run_hook(self.HOOK, call("mcp__atlassian__getJiraIssue", {"issueIdOrKey": "US-1"})), "")

    def test_no_opina_sobre_herramienta_ajena(self):
        self.assertEqual(run_hook(self.HOOK, call("run_command", {"CommandLine": "ls"})), "")

    def test_reconoce_nombres_de_tool_con_otras_convenciones(self):
        """El naming de las tools MCP en Antigravity no está documentado: el
        gate debe enganchar por patrón, no por igualdad exacta."""
        for name in ("atlassian.createJiraIssue",
                     "atlassian_create_jira_issue",
                     "jira-add-comment-to-issue"):
            with self.subTest(name=name):
                out = run_hook(self.HOOK, call(name, {"description": "contenido real y suficiente"}))
                self.assertNotEqual(out, "", f"el gate no enganchó '{name}'")


class SurfacePendingCheck(unittest.TestCase):
    """Este hook es el que le devuelve los dientes al gate post-edit: el
    PostToolUse de Antigravity no puede darle feedback al agente, así que la
    falla se guarda en una marca y se levanta acá."""

    HOOK = "surface-pending-check.py"

    def _run(self, marker: Path) -> str:
        result = subprocess.run(
            [sys.executable, str(HOOKS / self.HOOK)],
            input=json.dumps(call("run_command", {})),
            text=True,
            capture_output=True,
            check=False,
            env={**os.environ, "QA_HARNESS_PENDING_CHECK": str(marker)},
        )
        return result.stdout.strip()

    def test_no_opina_sin_marca_pendiente(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self._run(Path(tmp) / "no-existe.json"), "")

    def test_levanta_la_marca_como_ask(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "pending.json"
            marker.write_text(json.dumps({"reason": "fallo tests Python"}), encoding="utf-8")
            out = json.loads(self._run(marker))
            self.assertEqual(out["decision"], "ask")
            self.assertIn("fallo tests Python", out["reason"])

    def test_consume_la_marca_una_sola_vez(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "pending.json"
            marker.write_text(json.dumps({"reason": "algo se rompio"}), encoding="utf-8")
            self.assertNotEqual(self._run(marker), "")
            self.assertFalse(marker.exists(), "la marca debe borrarse tras levantarse")
            self.assertEqual(self._run(marker), "", "no debe repetir el aviso")


class CheckAfterEdit(unittest.TestCase):
    def test_respeta_el_contrato_vacio_de_posttooluse(self):
        out = run_hook("check-after-edit.py", call("view_file", {"path": "x"}))
        self.assertEqual(out, "{}")


if __name__ == "__main__":
    unittest.main()
