"""Los tres adaptadores tienen que encontrar la misma raíz del harness.

Cada shim arranca con un bootstrap inline que sube buscando la marca
`core/gates/contract.py`. Está duplicado a propósito y no se puede evitar: para
importar cualquier cosa de `core` hace falta tener la raíz en `sys.path`, así
que el localizador no puede vivir en `core` sin morderse la cola.

Lo que sí se puede evitar es que esa duplicación se desincronice en silencio.
Estos tests son el seguro: si alguien mueve un adaptador de lugar o vuelve a
contar niveles con `.parent.parent`, acá se rompe y se ve.
"""

from __future__ import annotations

import subprocess
import sys
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]

SHIMS = {
    "claude": RAIZ / "adapters" / "claude" / "hooks" / "_claude.py",
    "cursor": RAIZ / "adapters" / "cursor" / "hooks" / "_cursor.py",
    "antigravity": RAIZ / "adapters" / "antigravity" / "hooks" / "_agy.py",
}


def raiz_segun(shim: Path) -> str:
    """Importa el shim en un proceso aparte y devuelve su HARNESS_ROOT."""
    codigo = (
        "import sys;"
        f"sys.path.insert(0, {str(shim.parent)!r});"
        f"import {shim.stem} as shim;"
        "print(shim.HARNESS_ROOT)"
    )
    resultado = subprocess.run(
        [sys.executable, "-B", "-c", codigo],
        text=True,
        capture_output=True,
        check=False,
    )
    if resultado.returncode != 0:
        raise AssertionError(f"{shim.name} no se pudo importar:\n{resultado.stderr}")
    return resultado.stdout.strip()


class TestRaizDeLosAdaptadores(unittest.TestCase):
    def test_los_shims_existen_donde_los_buscamos(self):
        for runtime, shim in SHIMS.items():
            with self.subTest(runtime=runtime):
                self.assertTrue(shim.is_file(), f"falta el shim de {runtime}: {shim}")

    def test_cada_shim_resuelve_la_raiz_del_repo(self):
        for runtime, shim in SHIMS.items():
            with self.subTest(runtime=runtime):
                self.assertEqual(raiz_segun(shim), str(RAIZ))

    def test_los_tres_coinciden(self):
        raices = {runtime: raiz_segun(shim) for runtime, shim in SHIMS.items()}
        self.assertEqual(
            len(set(raices.values())),
            1,
            f"los adaptadores no coinciden en la raíz: {raices}",
        )

    def test_ningun_shim_cuenta_niveles(self):
        """`.parent.parent` es el número mágico que la fase 3 vino a borrar."""
        for runtime, shim in SHIMS.items():
            with self.subTest(runtime=runtime):
                self.assertNotIn(
                    "parent.parent",
                    shim.read_text(encoding="utf-8"),
                    f"{runtime} volvió a contar niveles en vez de buscar la marca",
                )

    def test_la_marca_es_la_que_buscan_los_shims(self):
        marca = RAIZ / "core" / "gates" / "contract.py"
        self.assertTrue(marca.is_file(), "la marca que usan los bootstraps no existe")
        for runtime, shim in SHIMS.items():
            with self.subTest(runtime=runtime):
                self.assertIn(
                    '"core" / "gates" / "contract.py"',
                    shim.read_text(encoding="utf-8"),
                    f"{runtime} busca una marca distinta a la de los demás",
                )


if __name__ == "__main__":
    unittest.main()
