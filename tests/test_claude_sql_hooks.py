#!/usr/bin/env python3
"""Hook de SQL en Claude Code: el veredicto se proyecta bien.

Corre como proceso aparte sobre un harness temporal con su propia config.
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
            {"key": "DEV", "database": "postgres-dev", "production": False},
            {"key": "PROD", "database": "postgres-prod", "production": True},
        ],
    },
}


class HookDeSql(unittest.TestCase):
    def setUp(self) -> None:
        self._temporal = tempfile.TemporaryDirectory()
        self.harness = Path(self._temporal.name) / "harness"
        self.hooks = copiar_harness(self.harness, "claude")
        (self.harness / "profile").mkdir()
        (self.harness / "companies").mkdir()
        (self.harness / "profile" / "profile.json").write_text(json.dumps({"activeCompany": "acme"}), encoding="utf-8")
        (self.harness / "companies" / "acme.json").write_text(json.dumps(CONFIG), encoding="utf-8")

    def tearDown(self) -> None:
        self._temporal.cleanup()

    def pre(self, tool: str, entrada: object, *, raw: str | None = None) -> dict | None:
        entorno = {**os.environ}
        entorno.pop("CLAUDE_PROJECT_DIR", None)
        payload = {"hook_event_name": "PreToolUse", "session_id": "s1", "tool_name": tool, "tool_input": entrada}
        resultado = subprocess.run(
            [sys.executable, "-B", str(self.hooks / "validate-sql-query.py")],
            input=raw if raw is not None else json.dumps(payload),
            text=True,
            capture_output=True,
            check=False,
            env=entorno,
        )
        self.assertEqual(resultado.returncode, 0, resultado.stderr)
        return json.loads(resultado.stdout) if resultado.stdout.strip() else None

    def decision(self, salida: dict | None) -> str | None:
        return None if salida is None else salida["hookSpecificOutput"]["permissionDecision"]

    def test_un_select_en_dev_pasa_en_silencio(self) -> None:
        entrada = {"operation": "select", "query": "SELECT id FROM botones WHERE nombre = 'x'"}
        self.assertIsNone(self.pre("mcp__postgres-dev__pg_execute_query", entrada))

    def test_produccion_escritura_y_connection_string_se_deniegan(self) -> None:
        for tool, entrada in (
            ("mcp__postgres-prod__pg_execute_query", {"operation": "select", "query": "SELECT 1"}),
            ("mcp__postgres-dev__pg_execute_mutation", {"operation": "delete", "table": "t"}),
            ("mcp__postgres-dev__pg_execute_sql", {"sql": "SELECT 1"}),
            ("mcp__postgres-dev__pg_execute_query", {"operation": "select", "query": "DELETE FROM t"}),
            ("mcp__postgres-dev__pg_execute_query",
             {"operation": "select", "query": "SELECT 1", "connectionString": "postgresql://x@prod/db"}),
        ):
            with self.subTest(tool=tool, entrada=entrada):
                salida = self.pre(tool, entrada)
                self.assertEqual(self.decision(salida), "deny")
                self.assertIn("Gate de SQL", salida["hookSpecificOutput"]["permissionDecisionReason"])

    def test_herramienta_inesperada_o_payload_roto_se_deniegan(self) -> None:
        self.assertEqual(self.decision(self.pre("mcp__playwright__browser_click", {})), "deny")
        self.assertEqual(self.decision(self.pre("x", {}, raw="no es json")), "deny")

    def test_sin_config_falla_cerrado(self) -> None:
        (self.harness / "companies" / "acme.json").unlink()
        salida = self.pre("mcp__postgres-dev__pg_execute_query", {"operation": "select", "query": "SELECT 1"})
        self.assertEqual(self.decision(salida), "deny")


if __name__ == "__main__":
    unittest.main(verbosity=2)
