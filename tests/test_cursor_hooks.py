"""Unit tests de los hooks portados a Cursor.

El contrato viene de leer el binario de Cursor.app:
  beforeShellExecution  in {"command","cwd"}          out {"permission":"deny"|"ask","user_message"}
  beforeMCPExecution    in {"tool_name","tool_input"} out {"permission":"deny","user_message"}
                        -- tool_input llega como STRING JSON
  afterFileEdit         in {"file_path","edits"}      no puede bloquear
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOKS = ROOT / "cursor" / "hooks"


def run_hook(script: str, payload: dict, pending: Path | None = None) -> str:
    env = {**os.environ}
    if pending is not None:
        env["QA_HARNESS_PENDING_CHECK"] = str(pending)
    result = subprocess.run(
        [sys.executable, str(HOOKS / script)],
        input=json.dumps(payload), text=True, capture_output=True, check=False, env=env,
    )
    return result.stdout.strip()


class BeforeShellExecution(unittest.TestCase):
    HOOK = "block-destructive-command.py"

    def _clean(self, payload):
        with tempfile.TemporaryDirectory() as tmp:
            return run_hook(self.HOOK, payload, Path(tmp) / "none.json")

    def test_bloquea_rm_recursivo_forzado(self):
        out = json.loads(self._clean({"command": "rm -rf /tmp/x", "cwd": "/tmp"}))
        self.assertEqual(out["permission"], "deny")

    def test_bloquea_reset_hard(self):
        out = json.loads(self._clean({"command": "git reset --hard origin/main", "cwd": "/tmp"}))
        self.assertEqual(out["permission"], "deny")

    def test_no_opina_sobre_comando_inocuo(self):
        self.assertEqual(self._clean({"command": "npm test", "cwd": "/tmp"}), "")

    def test_levanta_check_pendiente_como_ask(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "pending.json"
            marker.write_text(json.dumps({"reason": "fallo tests Python"}), encoding="utf-8")
            out = json.loads(run_hook(self.HOOK, {"command": "npm test", "cwd": "/tmp"}, marker))
            self.assertEqual(out["permission"], "ask")
            self.assertIn("fallo tests Python", out["user_message"])
            self.assertFalse(marker.exists(), "la marca debe consumirse")

    def test_el_comando_destructivo_gana_sobre_el_pendiente(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "pending.json"
            marker.write_text(json.dumps({"reason": "algo"}), encoding="utf-8")
            out = json.loads(run_hook(self.HOOK, {"command": "rm -rf /", "cwd": "/tmp"}, marker))
            self.assertEqual(out["permission"], "deny")


class BeforeMCPExecution(unittest.TestCase):
    HOOK = "validate-external-write.py"

    @staticmethod
    def call(name: str, args: dict) -> dict:
        # Cursor serializa tool_input como string JSON
        return {"tool_name": name, "tool_input": json.dumps(args)}

    def test_deniega_transicion_de_jira(self):
        out = json.loads(run_hook(self.HOOK, self.call("mcp_atlassian_transitionJiraIssue", {"issueIdOrKey": "US-1"})))
        self.assertEqual(out["permission"], "deny")

    def test_deniega_placeholder_sin_resolver(self):
        payload = self.call("mcp_atlassian_createJiraIssue",
                            {"summary": "CP-01", "description": "Tabla: PON-AQUI-EL-ID"})
        out = json.loads(run_hook(self.HOOK, payload))
        self.assertEqual(out["permission"], "deny")
        self.assertIn("placeholder", out["user_message"])

    def test_deja_pasar_contenido_limpio(self):
        """Cursor no soporta 'ask' en beforeMCPExecution: la confirmación la pone
        su propio allowlist de MCP. El hook solo valida el contenido."""
        payload = self.call("mcp_atlassian_createJiraIssue",
                            {"summary": "[PROJ-123][QA] CP-01", "description": "## Objetivo. Validar."})
        self.assertEqual(run_hook(self.HOOK, payload), "")

    def test_deniega_payload_sin_contenido_publicable(self):
        out = json.loads(run_hook(self.HOOK, self.call("mcp_atlassian_createJiraIssue", {"projectKey": "QA"})))
        self.assertEqual(out["permission"], "deny")

    def test_no_opina_sobre_lectura(self):
        self.assertEqual(run_hook(self.HOOK, self.call("mcp_atlassian_getJiraIssue", {"issueIdOrKey": "US-1"})), "")

    def test_parsea_tool_input_como_string_json(self):
        """Si el shim no desanidara el string, publication_content no encontraría
        nada y el gate denegaría un payload perfectamente válido."""
        payload = self.call("mcp_atlassian_addCommentToJiraIssue", {"body": "Cierre STG. Pass rate 95%."})
        self.assertEqual(run_hook(self.HOOK, payload), "")


class AfterFileEdit(unittest.TestCase):
    HOOK = "check-after-edit.py"

    def test_no_bloquea_nunca(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = run_hook(self.HOOK, {"file_path": "README.md", "edits": []}, Path(tmp) / "p.json")
            self.assertEqual(out, "")

    def test_ignora_archivos_fuera_del_harness(self):
        with tempfile.TemporaryDirectory() as tmp:
            marker = Path(tmp) / "p.json"
            run_hook(self.HOOK, {"file_path": "/etc/hosts", "edits": []}, marker)
            self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
