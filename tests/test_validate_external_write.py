#!/usr/bin/env python3
"""Tests for the deterministic external-write PreToolUse gate."""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


HOOK = Path(__file__).resolve().parents[1] / "hooks" / "validate-external-write.py"


def run_hook(tool: str, tool_input: dict | None, *, raw: str | None = None) -> dict | None:
    if raw is None:
        raw = json.dumps(
            {
                "hook_event_name": "PreToolUse",
                "tool_name": tool,
                "tool_input": tool_input,
            }
        )
    result = subprocess.run(
        ["python3", "-B", str(HOOK)],
        input=raw,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"hook terminó con {result.returncode}: {result.stderr}")
    return json.loads(result.stdout) if result.stdout.strip() else None


class ExternalWriteGateTests(unittest.TestCase):
    def assert_blocked(self, output: dict | None, text: str) -> None:
        self.assertIsNotNone(output)
        decision = output["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "deny")
        self.assertIn(text, decision["permissionDecisionReason"])

    def test_allows_supported_complete_payloads(self) -> None:
        cases = (
            ("mcp__atlassian__addCommentToJiraIssue", {"issueIdOrKey": "QA-1", "commentBody": "Cierre QA aprobado."}),
            ("mcp__atlassian__createConfluencePage", {"spaceKey": "QA", "title": "QA-1", "body": "Análisis completo."}),
            ("mcp__notion__notion-create-pages", {"pages": [{"properties": {"title": "QA-1"}, "content": "Casos completos."}]}),
            ("mcp__notion__notion-update-page", {"command": "update_properties", "properties": {"title": "APROBADO"}}),
        )
        for tool, tool_input in cases:
            with self.subTest(tool=tool):
                self.assertIsNone(run_hook(tool, tool_input))

    def test_blocks_empty_or_unknown_payload(self) -> None:
        tool = "mcp__atlassian__addCommentToJiraIssue"
        self.assert_blocked(run_hook(tool, {}), "no encontré contenido")
        self.assert_blocked(run_hook(tool, {"issueIdOrKey": "QA-1"}), "no encontré contenido")

    def test_blocks_placeholders_recursively(self) -> None:
        tool = "mcp__notion__notion-create-pages"
        cases = (
            {"pages": [{"content": "Ticket <TICKET> pendiente"}]},
            {"pages": [{"content": "TODO: completar resultados"}]},
            {"pages": [{"content": "Responsable {{ nombre }}"}]},
            {"pages": [{"content": "https://tuempresa.atlassian.net"}]},
        )
        for tool_input in cases:
            with self.subTest(tool_input=tool_input):
                self.assert_blocked(run_hook(tool, tool_input), "placeholder")

    def test_fails_closed_on_invalid_input_or_tool(self) -> None:
        self.assert_blocked(
            run_hook("mcp__atlassian__addCommentToJiraIssue", None, raw="no es json"),
            "entrada inválida",
        )
        self.assert_blocked(run_hook("mcp__otro__write", {"content": "texto"}), "herramienta inesperada")


if __name__ == "__main__":
    unittest.main(verbosity=2)
