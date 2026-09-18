#!/usr/bin/env python3
"""Tests del gate de comandos destructivos, sin runtime de por medio."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core.gates import contract, destructivos  # noqa: E402


class RevisarComando(unittest.TestCase):
    def assert_bloquea(self, comando: str, motivo: str) -> None:
        veredicto = destructivos.revisar_comando(comando)
        self.assertTrue(veredicto.bloquea, f"'{comando}' debía bloquearse")
        self.assertIn(motivo, veredicto.motivo)

    def assert_permite(self, comando: str) -> None:
        veredicto = destructivos.revisar_comando(comando)
        self.assertEqual(veredicto.decision, contract.PERMITIR, f"'{comando}' debía pasar")

    def test_bloquea_rm_recursivo_y_forzado(self) -> None:
        for comando in (
            "rm -rf /tmp/demo",
            "rm -fr /tmp/demo",
            "/bin/rm -r -f /tmp/demo",
            "echo $(rm -rf /tmp/demo)",
        ):
            with self.subTest(comando=comando):
                self.assert_bloquea(comando, "rm recursivo y forzado")

    def test_bloquea_los_git_destructivos(self) -> None:
        casos = (
            ("git reset --hard HEAD~1", "git reset --hard"),
            ("git clean -fd", "git clean forzado"),
            ("git clean -d -f", "git clean forzado"),
            ("git push origin main --force", "git push forzado"),
            ("git push -f origin main", "git push forzado"),
            ("npm test && git reset --hard", "git reset --hard"),
        )
        for comando, motivo in casos:
            with self.subTest(comando=comando):
                self.assert_bloquea(comando, motivo)

    def test_deja_pasar_lo_reversible(self) -> None:
        for comando in (
            "rm archivo.txt",
            "rm -r carpeta-temporal",
            "git reset --soft HEAD~1",
            "git clean -nfd",
            "git push origin main",
            "git status",
            "./tests/smoke.sh",
        ):
            with self.subTest(comando=comando):
                self.assert_permite(comando)

    def test_falla_cerrado_con_un_comando_ilegible(self) -> None:
        """Si no se puede leer, no se puede descartar que sea destructivo."""
        for comando in (None, "", "   ", 42, {"command": "rm -rf /"}):
            with self.subTest(comando=comando):
                veredicto = destructivos.revisar_comando(comando)
                self.assertTrue(veredicto.bloquea)
                self.assertIn("vacío o inválido", veredicto.motivo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
