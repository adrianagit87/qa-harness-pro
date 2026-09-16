#!/usr/bin/env python3
"""Tests for the deterministic PostToolUse edit gate."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


HOOK = Path(__file__).resolve().parents[1] / "hooks" / "check-after-edit.py"


class PostEditGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "tests").mkdir()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_hook(self, path: Path, *, tool: str = "Edit", raw: str | None = None) -> dict | None:
        if raw is None:
            raw = json.dumps(
                {
                    "hook_event_name": "PostToolUse",
                    "tool_name": tool,
                    "tool_input": {"file_path": str(path)},
                }
            )
        result = subprocess.run(
            ["python3", "-B", str(HOOK)],
            input=raw,
            text=True,
            capture_output=True,
            check=False,
            env={**os.environ, "CLAUDE_PROJECT_DIR": str(self.root)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def assert_blocked(self, output: dict | None, text: str) -> None:
        self.assertIsNotNone(output)
        self.assertEqual(output["decision"], "block")
        self.assertIn(text, output["reason"])

    def test_python_edit_runs_tests_and_allows_green(self) -> None:
        edited = self.root / "module.py"
        edited.write_text("VALUE = 1\n")
        (self.root / "tests" / "test_ok.py").write_text(
            "import unittest\nclass T(unittest.TestCase):\n    def test_ok(self): self.assertTrue(True)\n"
        )
        self.assertIsNone(self.run_hook(edited))

    def test_python_syntax_error_blocks(self) -> None:
        edited = self.root / "broken.py"
        edited.write_text("def broken(:\n")
        self.assert_blocked(self.run_hook(edited), "Python inválido")

    def test_failing_python_test_blocks(self) -> None:
        edited = self.root / "module.py"
        edited.write_text("VALUE = 1\n")
        (self.root / "tests" / "test_fail.py").write_text(
            "import unittest\nclass T(unittest.TestCase):\n    def test_fail(self): self.fail('regresión')\n"
        )
        self.assert_blocked(self.run_hook(edited), "falló tests Python")

    def test_shell_and_json_syntax(self) -> None:
        shell = self.root / "broken.sh"
        shell.write_text("if true; then\n")
        self.assert_blocked(self.run_hook(shell, tool="Write"), "sintaxis Bash")

        config = self.root / "broken.json"
        config.write_text('{"missing": }')
        self.assert_blocked(self.run_hook(config), "falló JSON")

    def test_ignores_documentation(self) -> None:
        doc = self.root / "README.md"
        doc.write_text("texto\n")
        self.assertIsNone(self.run_hook(doc))

    def test_fails_closed_on_invalid_or_external_file(self) -> None:
        self.assert_blocked(self.run_hook(self.root, raw="no es json"), "entrada inválida")
        with tempfile.NamedTemporaryFile(suffix=".py") as external:
            self.assert_blocked(self.run_hook(Path(external.name)), "fuera de la raíz")


if __name__ == "__main__":
    unittest.main(verbosity=2)
