#!/usr/bin/env python3
"""Tests for the deterministic PostToolUse edit gate."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness_temporal import BASELINE_ROTO, BASELINE_VALIDO, copiar_harness, escribir_config  # noqa: E402


HOOK = Path(__file__).resolve().parents[1] / "adapters" / "claude" / "hooks" / "check-after-edit.py"


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
        for raw in ("no es json", "[]", "null"):
            with self.subTest(raw=raw):
                self.assert_blocked(self.run_hook(self.root, raw=raw), "entrada inválida")
        # ABSTENERSE acá se proyecta como block: este hook se engancha por
        # matcher, así que dar por bueno un cambio sin verificar sería mentir.
        # La contraparte silenciosa está en test_cursor_hooks y test_antigravity_hooks.
        with tempfile.NamedTemporaryFile(suffix=".py") as external:
            self.assert_blocked(self.run_hook(Path(external.name)), "fuera de la raíz")


class BaselineConfiguradoFueraDelProyecto(unittest.TestCase):
    """La excepción angosta al bloqueo por archivo externo: solo el baseline configurado."""

    def setUp(self) -> None:
        dirs = [tempfile.TemporaryDirectory() for _ in range(3)]
        for temporal in dirs:
            self.addCleanup(temporal.cleanup)
        harness, self.proyecto, afuera = (Path(d.name) for d in dirs)
        self.hook = copiar_harness(harness, "claude") / "check-after-edit.py"
        self.baseline = afuera / "baseline.md"
        escribir_config(harness, {"enabled": True, "path": str(self.baseline)})

    def run_hook(self, path: Path) -> dict | None:
        raw = json.dumps({"tool_name": "Write", "tool_input": {"file_path": str(path)}})
        result = subprocess.run(
            ["python3", "-B", str(self.hook)], input=raw, text=True, capture_output=True,
            check=False, env={**os.environ, "CLAUDE_PROJECT_DIR": str(self.proyecto)},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def test_el_baseline_valido_pasa_aunque_este_fuera_del_proyecto(self) -> None:
        self.baseline.write_text(BASELINE_VALIDO, encoding="utf-8")
        self.assertIsNone(self.run_hook(self.baseline))

    def test_el_baseline_roto_bloquea_con_el_motivo_del_baseline(self) -> None:
        self.baseline.write_text(BASELINE_ROTO, encoding="utf-8")
        salida = self.run_hook(self.baseline)
        self.assertEqual(salida["decision"], "block")
        self.assertIn("baseline inválido", salida["reason"])

    def test_otro_archivo_externo_sigue_frenado_como_siempre(self) -> None:
        ajeno = self.baseline.parent / "otro.md"
        ajeno.write_text("texto\n", encoding="utf-8")
        salida = self.run_hook(ajeno)
        self.assertEqual(salida["decision"], "block")
        self.assertIn("fuera de la raíz", salida["reason"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
