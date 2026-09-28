#!/usr/bin/env python3
"""Tests del gate post-shell: la foto de antes y después de un comando, sin runtime."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from core.gates import post_edicion, post_shell  # noqa: E402
from harness_temporal import BASELINE_ROTO, BASELINE_VALIDO, escribir_config  # noqa: E402

RAIZ_REAL = Path(__file__).resolve().parents[1]
SIN_GIT_AJENO = {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}


def git(raiz: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-C", str(raiz), "-c", "user.name=QA", "-c", "user.email=qa@example.com",
         "-c", "commit.gpgsign=false", *args],
        check=True, capture_output=True, env={**os.environ, **SIN_GIT_AJENO},
    )


def repo_temporal(caso: unittest.TestCase) -> Path:
    temporal = tempfile.TemporaryDirectory()
    caso.addCleanup(temporal.cleanup)
    raiz = Path(temporal.name).resolve()
    git(raiz, "init", "-q")
    return raiz


def escribir(ruta: Path, texto: str) -> None:
    """Escribe y corre el mtime hacia adelante: el diff no depende de la resolución del reloj."""
    ruta.write_text(texto, encoding="utf-8")
    futuro = time.time_ns() + 5_000_000_000
    os.utime(ruta, ns=(futuro, futuro))


class TomarFoto(unittest.TestCase):
    def setUp(self) -> None:
        self.raiz = repo_temporal(self)

    def test_fuera_de_un_repo_git_no_hay_foto(self) -> None:
        with tempfile.TemporaryDirectory() as suelto:
            self.assertIsNone(post_shell.tomar_foto(suelto))

    def test_raiz_ilegible_no_hay_foto(self) -> None:
        self.assertIsNone(post_shell.tomar_foto(None))

    def test_entran_los_no_trackeados_y_no_los_ignorados(self) -> None:
        (self.raiz / ".gitignore").write_text("*.log\n")
        (self.raiz / "nuevo.json").write_text("{}")
        (self.raiz / "ruido.log").write_text("x")
        archivos = post_shell.tomar_foto(self.raiz)["archivos"]
        self.assertIn(str(self.raiz / "nuevo.json"), archivos)
        self.assertNotIn(str(self.raiz / "ruido.log"), archivos)

    def test_un_trackeado_limpio_no_entra_y_uno_modificado_si(self) -> None:
        (self.raiz / "limpio.json").write_text("{}")
        (self.raiz / "sucio.json").write_text("{}")
        git(self.raiz, "add", ".")
        git(self.raiz, "commit", "-qm", "base")
        (self.raiz / "sucio.json").write_text('{"a": 1}')
        archivos = post_shell.tomar_foto(self.raiz)["archivos"]
        self.assertNotIn(str(self.raiz / "limpio.json"), archivos)
        self.assertIn(str(self.raiz / "sucio.json"), archivos)

    def test_el_baseline_configurado_entra_aunque_no_exista_todavia(self) -> None:
        with tempfile.TemporaryDirectory() as harness, tempfile.TemporaryDirectory() as afuera:
            baseline = Path(afuera).resolve() / "baseline.md"
            escribir_config(Path(harness), {"enabled": True, "path": str(baseline)})
            archivos = post_shell.tomar_foto(self.raiz, harness)["archivos"]
        self.assertIn(str(baseline), archivos)
        self.assertIsNone(archivos[str(baseline)])

    def test_es_rapida_sobre_este_repo(self) -> None:
        inicio = time.perf_counter()
        foto = post_shell.tomar_foto(RAIZ_REAL, RAIZ_REAL)
        self.assertLess(time.perf_counter() - inicio, 1.0)
        if foto is None:
            self.skipTest("la copia del repo no es un repo git")


class Cambios(unittest.TestCase):
    """El diff entre dos fotos: solo lo que ESE comando creó o modificó."""

    def setUp(self) -> None:
        self.raiz = repo_temporal(self)
        (self.raiz / "intacto.json").write_text("{")  # roto, pero de antes
        (self.raiz / "modificado.json").write_text("{}")
        (self.raiz / "borrado.json").write_text("{}")
        self.antes = post_shell.tomar_foto(self.raiz)

    def diff(self) -> list[str]:
        return post_shell.cambios(self.antes, post_shell.tomar_foto(self.raiz))

    def test_creado_y_modificado_entran_intacto_y_borrado_no(self) -> None:
        escribir(self.raiz / "creado.json", "{}")
        escribir(self.raiz / "modificado.json", '{"a": 1}')
        (self.raiz / "borrado.json").unlink()
        self.assertEqual(self.diff(), [str(self.raiz / "creado.json"), str(self.raiz / "modificado.json")])

    def test_sin_cambios_no_hay_nada(self) -> None:
        self.assertEqual(self.diff(), [])

    def test_un_mtime_restaurado_se_ve_igual_por_el_ctime(self) -> None:
        """`cp -p` / `touch -r` devuelven el mtime; el ctime no se puede fijar."""
        ruta = self.raiz / "modificado.json"
        previo = ruta.stat()
        time.sleep(0.01)
        ruta.write_text("[]", encoding="utf-8")  # mismo tamaño que "{}"
        os.utime(ruta, ns=(previo.st_atime_ns, previo.st_mtime_ns))
        self.assertEqual(self.diff(), [str(ruta)])


class RevisarCambios(unittest.TestCase):
    def setUp(self) -> None:
        self.raiz = repo_temporal(self)

    def test_json_roto_escrito_por_el_comando_bloquea(self) -> None:
        antes = post_shell.tomar_foto(self.raiz)
        escribir(self.raiz / "zz.json", '{"a": }')
        veredictos = post_shell.revisar_cambios(antes, self.raiz)
        self.assertEqual(len(veredictos), 1)
        self.assertTrue(veredictos[0].bloquea)
        self.assertIn("falló JSON después de editar zz.json", veredictos[0].motivo)

    def test_lo_roto_de_antes_no_se_le_carga_al_comando(self) -> None:
        (self.raiz / "viejo.json").write_text("{")
        antes = post_shell.tomar_foto(self.raiz)
        escribir(self.raiz / "nuevo.json", "{}")
        self.assertFalse(any(v.bloquea for v in post_shell.revisar_cambios(antes, self.raiz)))

    def test_varios_py_corren_la_suite_una_vez(self) -> None:
        antes = post_shell.tomar_foto(self.raiz)
        for nombre in ("a.py", "b.py", "c.py"):
            escribir(self.raiz / nombre, "X = 1\n")
        with mock.patch.object(post_edicion, "ejecutar", return_value=(True, "")) as ejecutar:
            post_shell.revisar_cambios(antes, self.raiz)
        self.assertEqual(ejecutar.call_count, 1)

    def test_sin_foto_de_antes_se_abstiene(self) -> None:
        escribir(self.raiz / "zz.json", "{")
        for antes in (None, {}, {"version": 99, "raiz": str(self.raiz), "archivos": {}}, "basura"):
            with self.subTest(antes=antes):
                self.assertIsNone(post_shell.revisar_cambios(antes, self.raiz))

    def test_una_foto_de_otra_raiz_se_abstiene(self) -> None:
        otra = repo_temporal(self)
        antes = post_shell.tomar_foto(otra)
        escribir(self.raiz / "zz.json", "{")
        self.assertIsNone(post_shell.revisar_cambios(antes, self.raiz))

    def test_si_la_raiz_deja_de_ser_git_se_abstiene(self) -> None:
        antes = post_shell.tomar_foto(self.raiz)
        import shutil
        shutil.rmtree(self.raiz / ".git")
        escribir(self.raiz / "zz.json", "{")
        self.assertIsNone(post_shell.revisar_cambios(antes, self.raiz))

    def test_el_baseline_de_afuera_escrito_por_el_comando_se_valida(self) -> None:
        with tempfile.TemporaryDirectory() as harness, tempfile.TemporaryDirectory() as afuera:
            baseline = Path(afuera).resolve() / "baseline.md"
            escribir_config(Path(harness), {"enabled": True, "path": str(baseline)})
            antes = post_shell.tomar_foto(self.raiz, harness)
            escribir(baseline, BASELINE_ROTO)
            veredictos = post_shell.revisar_cambios(antes, self.raiz, harness)
            self.assertTrue(any("baseline inválido" in v.motivo for v in veredictos if v.bloquea))

            antes = post_shell.tomar_foto(self.raiz, harness)
            escribir(baseline, BASELINE_VALIDO)
            self.assertFalse(any(v.bloquea for v in post_shell.revisar_cambios(antes, self.raiz, harness)))

    def test_otro_archivo_de_afuera_se_ignora(self) -> None:
        antes = post_shell.tomar_foto(self.raiz)
        with tempfile.TemporaryDirectory() as afuera:
            escribir(Path(afuera) / "otro.json", "{")
            self.assertEqual(post_shell.revisar_cambios(antes, self.raiz), [])


class FotoEnDisco(unittest.TestCase):
    def setUp(self) -> None:
        temporal = tempfile.TemporaryDirectory()
        self.addCleanup(temporal.cleanup)
        self.dir = Path(temporal.name)
        self.foto = {"version": post_shell.VERSION, "raiz": "/x", "archivos": {"/x/a": [1, 2, 3]}}

    def test_ida_y_vuelta_y_se_consume(self) -> None:
        self.assertTrue(post_shell.guardar_foto(self.dir, "s-1", "u-1", self.foto))
        self.assertEqual(post_shell.sacar_foto(self.dir, "s-1", "u-1"), self.foto)
        self.assertIsNone(post_shell.sacar_foto(self.dir, "s-1", "u-1"))
        self.assertEqual(list(self.dir.iterdir()), [])

    def test_la_clave_es_sesion_y_llamada(self) -> None:
        post_shell.guardar_foto(self.dir, "s-1", "u-1", self.foto)
        self.assertIsNone(post_shell.sacar_foto(self.dir, "s-2", "u-1"))
        self.assertIsNone(post_shell.sacar_foto(self.dir, "s-1", "u-2"))

    def test_una_foto_corrupta_se_descarta(self) -> None:
        post_shell.guardar_foto(self.dir, "s", "u", self.foto)
        (archivo,) = self.dir.iterdir()
        archivo.write_text("{a medias")
        self.assertIsNone(post_shell.sacar_foto(self.dir, "s", "u"))
        self.assertFalse(archivo.exists())

    def test_rutas_no_utf8_sobreviven_el_viaje(self) -> None:
        foto = {**self.foto, "archivos": {"/x/\udcff.json": [1, 2, 3]}}
        self.assertTrue(post_shell.guardar_foto(self.dir, "s", "u", foto))
        self.assertEqual(post_shell.sacar_foto(self.dir, "s", "u"), foto)

    def test_barre_solo_las_huerfanas_viejas(self) -> None:
        post_shell.guardar_foto(self.dir, "s", "vieja", self.foto)
        post_shell.guardar_foto(self.dir, "s", "nueva", self.foto)
        vieja = post_shell._archivo_de_foto(self.dir, "s", "vieja")
        hace_un_dia = time.time() - 24 * 3600
        os.utime(vieja, (hace_un_dia, hace_un_dia))
        (self.dir / "ajeno.txt").write_text("no es mío")
        self.assertEqual(post_shell.barrer_viejas(self.dir), 1)
        self.assertFalse(vieja.exists())
        self.assertIsNotNone(post_shell.sacar_foto(self.dir, "s", "nueva"))
        self.assertTrue((self.dir / "ajeno.txt").exists())

    def test_la_carpeta_es_privada(self) -> None:
        with mock.patch.object(post_shell.tempfile, "gettempdir", return_value=str(self.dir)):
            carpeta = post_shell.directorio_de_fotos("qa-harness-prueba")
        self.assertEqual(carpeta, self.dir / "qa-harness-prueba")
        self.assertEqual(stat.S_IMODE(carpeta.stat().st_mode), 0o700)

    def test_un_symlink_en_lugar_de_la_carpeta_no_se_usa(self) -> None:
        (self.dir / "destino").mkdir()
        (self.dir / "qa-harness-prueba").symlink_to(self.dir / "destino")
        with mock.patch.object(post_shell.tempfile, "gettempdir", return_value=str(self.dir)):
            self.assertIsNone(post_shell.directorio_de_fotos("qa-harness-prueba"))


class ParPreYPost(unittest.TestCase):
    """Lo que usan los adaptadores: fotografiar en el pre, fallas_de_la_llamada en el post."""

    CARPETA = "qa-harness-prueba"

    def setUp(self) -> None:
        self.raiz = repo_temporal(self)
        temporal = tempfile.TemporaryDirectory()
        self.addCleanup(temporal.cleanup)
        parche = mock.patch.object(post_shell.tempfile, "gettempdir", return_value=temporal.name)
        parche.start()
        self.addCleanup(parche.stop)
        self.clave = post_shell.clave_de_llamada("s-1", "u-1")

    def post(self, clave=None) -> list[str]:
        return post_shell.fallas_de_la_llamada(self.CARPETA, clave or self.clave, self.raiz)

    def test_la_clave_exige_el_id_de_la_llamada(self) -> None:
        self.assertEqual(post_shell.clave_de_llamada("s", "u"), ("s", "u"))
        self.assertEqual(post_shell.clave_de_llamada(None, "u"), ("", "u"))
        for llamada in (None, "", "  ", 7):
            with self.subTest(llamada=llamada):
                self.assertIsNone(post_shell.clave_de_llamada("s", llamada))

    def test_lo_roto_por_esa_llamada_vuelve_como_falla(self) -> None:
        post_shell.fotografiar(self.CARPETA, self.clave, self.raiz)
        escribir(self.raiz / "zz.json", "{")
        (falla,) = self.post()
        self.assertIn("falló JSON después de editar zz.json", falla)

    def test_sin_foto_o_sin_clave_no_hay_fallas(self) -> None:
        escribir(self.raiz / "zz.json", "{")
        self.assertEqual(self.post(), [])
        post_shell.fotografiar(self.CARPETA, None, self.raiz)
        self.assertEqual(post_shell.fallas_de_la_llamada(self.CARPETA, None, self.raiz), [])

    def test_la_foto_se_usa_una_sola_vez(self) -> None:
        post_shell.fotografiar(self.CARPETA, self.clave, self.raiz)
        escribir(self.raiz / "zz.json", "{")
        self.assertEqual(len(self.post()), 1)
        self.assertEqual(self.post(), [])

    def test_el_aviso_va_entero_y_el_detalle_se_recorta_por_la_cola(self) -> None:
        texto = post_shell.con_aviso(["x" * 5000 + "FIN"], 4000)
        self.assertTrue(texto.startswith(post_shell.AVISO_YA_ESCRITO))
        self.assertTrue(texto.endswith("FIN"))
        self.assertEqual(len(texto), 4000)


if __name__ == "__main__":
    unittest.main(verbosity=2)
