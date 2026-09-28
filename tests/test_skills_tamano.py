#!/usr/bin/env python3
"""Las skills entran en el límite de Antigravity y sus referencias existen.

Antigravity documenta un límite de 12.000 caracteres, y se observó que no cargaba
`qa-analisis-ticket` cuando lo superaba. Las dos skills grandes se partieron: el
`SKILL.md` queda como punto de entrada y el detalle de cada paso vive en
`references/` dentro de la carpeta de la skill. Estos tests fallan si una skill
vuelve a crecer por encima del límite, o si un `SKILL.md` apunta a una referencia
que no existe — un puntero roto deja al agente sin el paso, en silencio.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
SKILLS = RAIZ / "skills"

# El límite es en CARACTERES, no en bytes: estos archivos tienen emojis y acentos.
LIMITE_CARACTERES = 12_000

PUNTERO_A_REFERENCIA = re.compile(r"references/[\w.-]+\.md")


def skills_md() -> list[Path]:
    encontrados = sorted(SKILLS.glob("*/SKILL.md"))
    if not encontrados:
        raise AssertionError(f"No hay ningún SKILL.md en {SKILLS}")
    return encontrados


class SkillsDentroDelLimite(unittest.TestCase):
    def test_cada_skill_tiene_menos_de_doce_mil_caracteres(self) -> None:
        for skill in skills_md():
            with self.subTest(skill=skill.parent.name):
                caracteres = len(skill.read_text(encoding="utf-8"))
                self.assertLess(
                    caracteres,
                    LIMITE_CARACTERES,
                    f"{skill.relative_to(RAIZ)} tiene {caracteres} caracteres: movele detalle a "
                    f"references/ en vez de recortar método",
                )


class ReferenciasDeLasSkills(unittest.TestCase):
    def test_cada_referencia_nombrada_en_un_skill_md_existe(self) -> None:
        for skill in skills_md():
            for referencia in sorted(set(PUNTERO_A_REFERENCIA.findall(skill.read_text(encoding="utf-8")))):
                with self.subTest(skill=skill.parent.name, referencia=referencia):
                    self.assertTrue(
                        (skill.parent / referencia).is_file(),
                        f"{skill.relative_to(RAIZ)} apunta a {referencia}, que no existe en la carpeta de la skill",
                    )

    def test_las_skills_partidas_apuntan_a_sus_referencias(self) -> None:
        # Si alguien borra los punteros, la skill queda liviana pero sin el detalle.
        for nombre in ("qa-analisis-ticket", "qa-cierre-ciclo"):
            with self.subTest(skill=nombre):
                texto = (SKILLS / nombre / "SKILL.md").read_text(encoding="utf-8")
                nombradas = set(PUNTERO_A_REFERENCIA.findall(texto))
                en_disco = {f"references/{p.name}" for p in (SKILLS / nombre / "references").glob("*.md")}
                self.assertTrue(en_disco, f"{nombre} no tiene references/")
                self.assertEqual(nombradas, en_disco)


if __name__ == "__main__":
    unittest.main()
