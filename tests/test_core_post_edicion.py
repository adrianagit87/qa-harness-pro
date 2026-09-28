#!/usr/bin/env python3
"""Tests del gate post-edición, sin runtime de por medio."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from core.gates import contract, post_edicion  # noqa: E402
from harness_temporal import BASELINE_ROTO, escribir_config  # noqa: E402


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


BASELINE_VALIDO = """<!-- qa-harness:baseline v1 -->
# Baseline

Texto libre de encabezado: no se interpreta.

```
### EJEMPLO — dentro de un bloque de código no se valida
```

## VEN-PED — Ventas › Pedidos

### VEN-PED-001 — Sin stock no se confirma
- Estado: reemplazada por VEN-PED-002
- Regla: Un pedido con un ítem sin stock no se puede confirmar.
- Verificado: TC-994-03 · US-994 · 2026-09-20 · PROD

### VEN-PED-002 — Sin stock queda pendiente
- Estado: vigente
- Regla: Un pedido con un ítem sin stock queda en estado Pendiente.
- Verificado: TC-1102-02 · US-1102 · 2026-10-05 · PROD
- Verificado: TC-1200-01 · US-1200 · 2026-11-02 · PROD
"""


class RevisarBaseline(unittest.TestCase):
    """El baseline se reconoce por su marca, y solo pasa si cada regla es trazable."""

    def setUp(self) -> None:
        temporal = tempfile.TemporaryDirectory()
        self.addCleanup(temporal.cleanup)
        self.raiz = Path(temporal.name)
        self.ruta = self.raiz / "baseline" / "baseline.md"
        self.ruta.parent.mkdir()

    def revisar(self, texto: str) -> contract.Verdict:
        self.ruta.write_text(texto, encoding="utf-8")
        return post_edicion.revisar_archivo(str(self.ruta), self.raiz)

    def assert_bloquea(self, texto: str, motivo: str) -> None:
        veredicto = self.revisar(texto)
        self.assertTrue(veredicto.bloquea, "el baseline mal formado debía bloquearse")
        self.assertIn("baseline inválido", veredicto.motivo)
        self.assertIn(motivo, veredicto.motivo)

    def test_un_baseline_valido_pasa(self) -> None:
        veredicto = self.revisar(BASELINE_VALIDO)
        self.assertEqual(veredicto.decision, contract.PERMITIR, veredicto.motivo)

    def test_el_template_del_repo_es_un_baseline_valido(self) -> None:
        template = Path(__file__).resolve().parents[1] / "templates" / "09-baseline.md"
        veredicto = self.revisar(template.read_text(encoding="utf-8"))
        self.assertEqual(veredicto.decision, contract.PERMITIR, veredicto.motivo)

    def test_un_markdown_sin_la_marca_no_se_revisa(self) -> None:
        """Aunque tenga forma de regla rota: sin marca no es el baseline."""
        roto = BASELINE_VALIDO.replace("<!-- qa-harness:baseline v1 -->\n", "")
        roto = roto.replace("- Verificado: TC-994-03 · US-994 · 2026-09-20 · PROD\n", "")
        self.assertEqual(self.revisar(roto).decision, contract.PERMITIR)

    def test_la_marca_fuera_de_la_primera_linea_no_lo_convierte_en_baseline(self) -> None:
        texto = "# Notas\n<!-- qa-harness:baseline v1 -->\n### cualquier cosa\n"
        self.assertEqual(self.revisar(texto).decision, contract.PERMITIR)

    def test_una_version_de_marca_desconocida_bloquea(self) -> None:
        self.assert_bloquea(
            BASELINE_VALIDO.replace("baseline v1", "baseline v9", 1),
            "la primera línea tiene que ser exactamente",
        )

    def test_una_regla_sin_verificado_bloquea(self) -> None:
        texto = BASELINE_VALIDO.replace(
            "- Verificado: TC-994-03 · US-994 · 2026-09-20 · PROD\n", ""
        )
        self.assert_bloquea(texto, "VEN-PED-001: falta al menos una línea '- Verificado:")

    def test_un_verificado_incompleto_bloquea(self) -> None:
        texto = BASELINE_VALIDO.replace(
            "TC-994-03 · US-994 · 2026-09-20 · PROD", "TC-994-03 · US-994 · 2026-09-20"
        )
        self.assert_bloquea(texto, "'Verificado' de VEN-PED-001 mal formado")

    def test_una_fecha_que_no_existe_bloquea(self) -> None:
        texto = BASELINE_VALIDO.replace("2026-09-20", "2026-02-30")
        self.assert_bloquea(texto, "fecha que no existe")

    def test_un_id_con_formato_invalido_bloquea(self) -> None:
        texto = BASELINE_VALIDO.replace("### VEN-PED-001 —", "### ven-ped-1 —")
        self.assert_bloquea(texto, "encabezado de regla mal formado")

    def test_una_regla_en_otro_modulo_bloquea(self) -> None:
        texto = BASELINE_VALIDO.replace("### VEN-PED-002 —", "### FAC-002 —").replace(
            "reemplazada por VEN-PED-002", "reemplazada por FAC-002"
        )
        self.assert_bloquea(texto, "su ID tiene que empezar con VEN-PED-")

    def test_un_id_repetido_bloquea(self) -> None:
        texto = BASELINE_VALIDO.replace("### VEN-PED-002 —", "### VEN-PED-001 —").replace(
            "reemplazada por VEN-PED-002", "vigente"
        )
        self.assert_bloquea(texto, "el ID VEN-PED-001 está repetido")

    def test_un_reemplazo_que_apunta_a_una_regla_inexistente_bloquea(self) -> None:
        texto = BASELINE_VALIDO.replace("reemplazada por VEN-PED-002", "reemplazada por VEN-PED-009")
        self.assert_bloquea(texto, "reemplazada por VEN-PED-009, que no existe")

    def test_una_cadena_de_reemplazos_circular_bloquea(self) -> None:
        texto = BASELINE_VALIDO.replace(
            "- Estado: vigente", "- Estado: reemplazada por VEN-PED-001"
        )
        self.assert_bloquea(texto, "vuelve sobre sí misma")

    def test_un_estado_desconocido_bloquea(self) -> None:
        texto = BASELINE_VALIDO.replace("- Estado: vigente", "- Estado: activa")
        self.assert_bloquea(texto, "'Estado' de VEN-PED-002 inválido")

    def test_una_regla_sin_texto_bloquea(self) -> None:
        texto = BASELINE_VALIDO.replace(
            "- Regla: Un pedido con un ítem sin stock queda en estado Pendiente.\n", ""
        )
        self.assert_bloquea(texto, "VEN-PED-002: falta la línea '- Regla:")

    def test_una_linea_inventada_dentro_de_una_regla_bloquea(self) -> None:
        """Nada de notas sueltas: lo que no es trazable no entra."""
        texto = BASELINE_VALIDO.replace(
            "- Estado: vigente\n", "- Estado: vigente\n- Nota: seguramente aplica a devoluciones\n"
        )
        self.assert_bloquea(texto, "línea no reconocida dentro de VEN-PED-002")


class BaselineConfigurado(unittest.TestCase):
    """`baseline.path` puede ser cualquier ruta: el configurado se valida esté donde esté.

    Tres directorios separados a propósito: la raíz del harness (la config), la
    raíz del proyecto abierto y un tercero, afuera de los dos, donde vive el baseline.
    """

    def setUp(self) -> None:
        dirs = [tempfile.TemporaryDirectory() for _ in range(3)]
        for temporal in dirs:
            self.addCleanup(temporal.cleanup)
        self.harness, self.proyecto, afuera = (Path(d.name) for d in dirs)
        self.afuera = afuera
        self.baseline = afuera / "conocimiento" / "baseline.md"
        self.baseline.parent.mkdir()
        self.encender(str(self.baseline))

    def encender(self, ruta: str, **extra: object) -> None:
        escribir_config(self.harness, {"enabled": True, "path": ruta, **extra})

    def revisar(self, ruta: Path) -> contract.Verdict:
        return post_edicion.revisar_archivo(str(ruta), self.proyecto, self.harness)

    def test_el_baseline_valido_fuera_de_la_raiz_pasa(self) -> None:
        self.baseline.write_text(BASELINE_VALIDO, encoding="utf-8")
        veredicto = self.revisar(self.baseline)
        self.assertEqual(veredicto.decision, contract.PERMITIR, veredicto.motivo)

    def test_el_baseline_roto_fuera_de_la_raiz_bloquea(self) -> None:
        self.baseline.write_text(BASELINE_ROTO, encoding="utf-8")
        veredicto = self.revisar(self.baseline)
        self.assertTrue(veredicto.bloquea)
        self.assertIn("baseline inválido", veredicto.motivo)

    def test_el_baseline_configurado_sin_marca_bloquea(self) -> None:
        """Siendo LA ruta configurada, borrarle la marca no lo saca del gate."""
        self.baseline.write_text(BASELINE_VALIDO.split("\n", 1)[1], encoding="utf-8")
        veredicto = self.revisar(self.baseline)
        self.assertTrue(veredicto.bloquea)
        self.assertIn("la primera línea tiene que ser exactamente", veredicto.motivo)

    def test_otros_archivos_fuera_de_la_raiz_siguen_ignorados(self) -> None:
        for nombre, contenido in (("otro.md", BASELINE_ROTO), ("roto.py", "def roto(:\n")):
            with self.subTest(nombre=nombre):
                ajeno = self.baseline.parent / nombre
                ajeno.write_text(contenido, encoding="utf-8")
                veredicto = self.revisar(ajeno)
                self.assertTrue(veredicto.se_abstiene)
                self.assertIn("fuera de la raíz", veredicto.motivo)

    def test_la_ruta_relativa_se_resuelve_contra_la_raiz_del_harness(self) -> None:
        self.encender("baseline/baseline.md")
        dentro_del_harness = self.harness / "baseline" / "baseline.md"
        dentro_del_harness.parent.mkdir()
        dentro_del_harness.write_text(BASELINE_ROTO, encoding="utf-8")
        self.assertTrue(self.revisar(dentro_del_harness).bloquea)

    def test_la_ruta_con_virgulilla_se_expande_al_home(self) -> None:
        self.baseline.write_text(BASELINE_ROTO, encoding="utf-8")
        self.encender("~/conocimiento/baseline.md")
        with mock.patch.dict(os.environ, {"HOME": str(self.afuera)}):
            self.assertTrue(self.revisar(self.baseline).bloquea)

    def test_sin_config_utilizable_vuelve_al_comportamiento_de_siempre(self) -> None:
        self.baseline.write_text(BASELINE_ROTO, encoding="utf-8")
        casos = {
            "bloque ausente": lambda: escribir_config(self.harness, None),
            "apagado": lambda: self.encender(str(self.baseline), enabled=False),
            "config rota": lambda: (self.harness / "companies" / "acme.json").write_text("{roto"),
            "sin perfil": lambda: (self.harness / "profile" / "profile.json").unlink(),
            "empresa inexistente": lambda: escribir_config(self.harness, None, empresa="otra")
            or (self.harness / "companies" / "otra.json").unlink(),
        }
        for caso, preparar in casos.items():
            with self.subTest(caso=caso):
                self.encender(str(self.baseline))
                preparar()
                self.assertTrue(self.revisar(self.baseline).se_abstiene)

    def test_sin_raiz_del_harness_no_busca_config(self) -> None:
        self.baseline.write_text(BASELINE_ROTO, encoding="utf-8")
        veredicto = post_edicion.revisar_archivo(str(self.baseline), self.proyecto)
        self.assertTrue(veredicto.se_abstiene)


class RevisarArchivos(unittest.TestCase):
    """Varios archivos de un mismo cambio: la suite corre una sola vez."""

    def setUp(self) -> None:
        temporal = tempfile.TemporaryDirectory()
        self.addCleanup(temporal.cleanup)
        self.raiz = Path(temporal.name)

    def escribir(self, nombre: str, texto: str) -> str:
        ruta = self.raiz / nombre
        ruta.write_text(texto, encoding="utf-8")
        return str(ruta)

    def test_varios_py_corren_la_suite_una_sola_vez(self) -> None:
        rutas = [self.escribir(f"m{i}.py", f"V = {i}\n") for i in range(3)]
        with mock.patch.object(post_edicion, "ejecutar", return_value=(True, "")) as ejecutar:
            veredictos = post_edicion.revisar_archivos(rutas, self.raiz)
        self.assertEqual(ejecutar.call_count, 1)
        self.assertIn("unittest", ejecutar.call_args.args[0])
        self.assertFalse(any(v.bloquea for v in veredictos))

    def test_la_suite_roja_nombra_todos_los_py_editados(self) -> None:
        rutas = [self.escribir("a.py", "A = 1\n"), self.escribir("b.py", "B = 2\n")]
        with mock.patch.object(post_edicion, "ejecutar", return_value=(False, "FAILED (failures=1)")):
            fallas = [v.motivo for v in post_edicion.revisar_archivos(rutas, self.raiz) if v.bloquea]
        self.assertEqual(len(fallas), 1)
        self.assertIn("falló tests Python después de editar a.py, b.py", fallas[0])

    def test_un_py_que_no_parsea_no_corre_la_suite(self) -> None:
        rutas = [self.escribir("sano.py", "X = 1\n"), self.escribir("roto.py", "def x(:\n")]
        with mock.patch.object(post_edicion, "ejecutar") as ejecutar:
            fallas = [v.motivo for v in post_edicion.revisar_archivos(rutas, self.raiz) if v.bloquea]
        ejecutar.assert_not_called()
        self.assertEqual(len(fallas), 1)
        self.assertIn("Python inválido en roto.py", fallas[0])

    def test_sin_py_no_hay_suite_y_cada_archivo_da_su_veredicto(self) -> None:
        rutas = [self.escribir("ok.json", "{}"), self.escribir("roto.json", "{")]
        veredictos = post_edicion.revisar_archivos(rutas, self.raiz)
        self.assertEqual([v.bloquea for v in veredictos], [False, True])

    def test_el_py_de_afuera_no_dispara_la_suite(self) -> None:
        with tempfile.NamedTemporaryFile(suffix=".py") as ajeno, \
                mock.patch.object(post_edicion, "ejecutar") as ejecutar:
            veredictos = post_edicion.revisar_archivos([ajeno.name], self.raiz)
        ejecutar.assert_not_called()
        self.assertTrue(veredictos[0].se_abstiene)

    def test_sin_archivos_no_hay_nada(self) -> None:
        self.assertEqual(post_edicion.revisar_archivos([], self.raiz), [])


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
