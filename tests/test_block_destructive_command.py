#!/usr/bin/env python3
"""Smoke tests for the destructive-command PreToolUse gate."""

from __future__ import annotations

import json
import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HOOK = REPO_ROOT / "adapters" / "claude" / "hooks" / "block-destructive-command.py"


def run_hook(command: str | None, *, raw: str | None = None) -> dict | None:
    if raw is None:
        payload = {
            "hook_event_name": "PreToolUse",
            "tool_name": "Bash",
            "tool_input": {"command": command},
        }
        raw = json.dumps(payload)

    result = subprocess.run(
        ["python3", str(HOOK)],
        input=raw,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise AssertionError(f"hook terminó con {result.returncode}: {result.stderr}")
    return json.loads(result.stdout) if result.stdout.strip() else None


class DestructiveCommandGateTests(unittest.TestCase):
    def assert_blocked(self, command: str, reason: str) -> None:
        output = run_hook(command)
        self.assertIsNotNone(output)
        decision = output["hookSpecificOutput"]
        self.assertEqual(decision["hookEventName"], "PreToolUse")
        self.assertEqual(decision["permissionDecision"], "deny")
        self.assertIn(reason, decision["permissionDecisionReason"])

    def assert_allowed(self, command: str) -> None:
        self.assertIsNone(run_hook(command))

    def test_blocks_rm_rf_variants(self) -> None:
        for command in (
            "rm -rf /tmp/demo",
            "rm -fr /tmp/demo",
            "/bin/rm -r -f /tmp/demo",
            "echo $(rm -rf /tmp/demo)",
        ):
            with self.subTest(command=command):
                self.assert_blocked(command, "rm recursivo y forzado")

    def test_blocks_destructive_git_commands(self) -> None:
        cases = (
            ("git reset --hard HEAD~1", "git reset --hard"),
            ("git clean -fd", "git clean forzado"),
            ("git clean -d -f", "git clean forzado"),
            ("git push origin main --force", "git push forzado"),
            ("git push -f origin main", "git push forzado"),
            ("npm test && git reset --hard", "git reset --hard"),
        )
        for command, reason in cases:
            with self.subTest(command=command):
                self.assert_blocked(command, reason)

    def test_allows_non_destructive_commands(self) -> None:
        for command in (
            "rm archivo.txt",
            "rm -r carpeta-temporal",
            "git reset --soft HEAD~1",
            "git clean -nfd",
            "git push origin main",
            "git status",
            "./tests/smoke.sh",
        ):
            with self.subTest(command=command):
                self.assert_allowed(command)

    def test_fails_closed_on_invalid_input(self) -> None:
        for raw in ("no es json", "[]", '"solo un string"', "null"):
            with self.subTest(raw=raw):
                malformed = run_hook(None, raw=raw)
                self.assertEqual(
                    malformed["hookSpecificOutput"]["permissionDecision"], "deny"
                )
        self.assert_blocked("", "vacío o inválido")


if __name__ == "__main__":
    unittest.main(verbosity=2)
