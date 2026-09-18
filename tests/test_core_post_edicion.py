#!/usr/bin/env python3
"""Tests del gate post-edición, sin runtime de por medio."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core.gates import contract, post_edicion  # noqa: E402


class RevisarArchivo(unittest.TestCase):
    def setUp(self) -> None:
        temporal = tempfile.TemporaryDirectory()
        self.addCleanup(temporal.cleanup)
        self.raiz = Path(temporal.name)
        (self.raiz / "tests").mkdir()

    def suite_verde(self) -> None:
        (self.raiz / "tests" / "test_ok.py").write_text(
            "import unittest\nclass T(unittest.TestCase):\n    def test_ok(self): self.assertTrue(True)\n"
        )

    def assert_bloquea(self, ruta: Path, texto: str) -> None:
        veredicto = post_edicion.revisar_archivo(str(ruta), self.raiz)
        self.assertTrue(veredicto.bloquea, f"{ruta.name} debía bloquearse")
        self.assertIn(texto, veredicto.motivo)

    def assert_permite(self, ruta: Path) -> None:
        veredicto = post_edicion.revisar_archivo(str(ruta), self.raiz)
        self.assertEqual(veredicto.decision, contract.PERMITIR, veredicto.motivo)

    def test_el_python_valido_con_la_suite_verde_pasa(self) -> None:
        editado = self.raiz / "modulo.py"
        editado.write_text("VALOR = 1\n")
        self.suite_verde()
        self.assert_permite(editado)

    def test_el_python_con_error_de_sintaxis_bloquea(self) -> None:
        editado = self.raiz / "roto.py"
        editado.write_text("def roto(:\n")
        self.assert_bloquea(editado, "Python inválido")

    def test_el_test_que_falla_bloquea(self) -> None:
        editado = self.raiz / "modulo.py"
        editado.write_text("VALOR = 1\n")
        (self.raiz / "tests" / "test_falla.py").write_text(
            "import unittest\nclass T(unittest.TestCase):\n    def test_falla(self): self.fail('regresión')\n"
        )
        self.assert_bloquea(editado, "falló tests Python")

    def test_el_bash_y_el_json_rotos_bloquean(self) -> None:
        shell = self.raiz / "roto.sh"
        shell.write_text("if true; then\n")
        self.assert_bloquea(shell, "falló sintaxis Bash")

        config = self.raiz / "roto.json"
        config.write_text('{"falta": }')
        self.assert_bloquea(config, "falló JSON")

    def test_las_extensiones_sin_check_pasan(self) -> None:
        doc = self.raiz / "README.md"
        doc.write_text("texto\n")
        self.assert_permite(doc)

    def test_resuelve_las_rutas_relativas_contra_la_raiz(self) -> None:
        editado = self.raiz / "modulo.py"
        editado.write_text("VALOR = 1\n")
        self.suite_verde()
        self.assertEqual(
            post_edicion.revisar_archivo("modulo.py", self.raiz).decision,
            contract.PERMITIR,
        )

    def test_se_abstiene_fuera_de_la_raiz(self) -> None:
        """No es bloqueo: cada runtime decide qué hacer con la abstención."""
        with tempfile.NamedTemporaryFile(suffix=".py") as ajeno:
            veredicto = post_edicion.revisar_archivo(ajeno.name, self.raiz)
            self.assertTrue(veredicto.se_abstiene)
            self.assertIn("fuera de la raíz", veredicto.motivo)

    def test_se_abstiene_con_una_ruta_ilegible(self) -> None:
        for ruta in (None, "", "   ", 7):
            with self.subTest(ruta=ruta):
                veredicto = post_edicion.revisar_archivo(ruta, self.raiz)
                self.assertTrue(veredicto.se_abstiene)
                self.assertIn("fuera de la raíz", veredicto.motivo)

    def test_se_abstiene_sin_raiz_utilizable(self) -> None:
        self.assertTrue(post_edicion.revisar_archivo("modulo.py", None).se_abstiene)

    def test_se_abstiene_si_el_archivo_ya_no_existe(self) -> None:
        veredicto = post_edicion.revisar_archivo(str(self.raiz / "fantasma.py"), self.raiz)
        self.assertTrue(veredicto.se_abstiene)
        self.assertIn("no existe después del cambio", veredicto.motivo)


class Ejecutar(unittest.TestCase):
    def test_devuelve_si_paso_y_la_salida_combinada(self) -> None:
        raiz = Path(__file__).resolve().parents[1]
        ok, salida = post_edicion.ejecutar(["python3", "-c", "print('hola')"], raiz)
        self.assertTrue(ok)
        self.assertEqual(salida, "hola")

        ok, salida = post_edicion.ejecutar(["python3", "-c", "raise SystemExit(3)"], raiz)
        self.assertFalse(ok)


if __name__ == "__main__":
    unittest.main(verbosity=2)
