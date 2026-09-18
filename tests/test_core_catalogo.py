#!/usr/bin/env python3
"""El catálogo es la fuente de verdad de las herramientas externas.

La lista vivía en cuatro lugares: el hook, el matcher de .claude/settings.json y
dos puntos de validate-config.sh. Ahora vive en core/gates/catalogo.py y estos
tests fallan si la configuración se desfasa de ella.
"""

from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ))

from core.gates import catalogo  # noqa: E402

SETTINGS = RAIZ / ".claude" / "settings.json"
VALIDATE = RAIZ / "validate-config.sh"


def matcher_del_hook(nombre_del_hook: str) -> str:
    """Matcher del grupo PreToolUse que engancha ese hook en settings.json."""
    hooks = json.loads(SETTINGS.read_text(encoding="utf-8"))["hooks"]["PreToolUse"]
    for grupo in hooks:
        for hook in grupo.get("hooks", []):
            if any(arg.endswith(f"adapters/claude/hooks/{nombre_del_hook}") for arg in hook.get("args", [])):
                return grupo["matcher"]
    raise AssertionError(f"'{nombre_del_hook}' no está enganchado en {SETTINGS}")


def variable_de_validate(nombre: str) -> str:
    """Valor de una variable literal de validate-config.sh."""
    encontrado = re.search(rf'^\s*{nombre}="([^"]*)"', VALIDATE.read_text(encoding="utf-8"), re.MULTILINE)
    if encontrado is None:
        raise AssertionError(f"'{nombre}' ya no existe en {VALIDATE}")
    return encontrado.group(1)


class CatalogoContraLaConfiguracion(unittest.TestCase):
    def test_el_matcher_de_settings_cubre_exactamente_el_catalogo(self) -> None:
        matcher = matcher_del_hook("validate-external-write.py")
        self.assertEqual(set(matcher.split("|")), set(catalogo.IDS_PUBLICACION))

    def test_validate_config_valida_exactamente_el_catalogo(self) -> None:
        # Línea ~538: toda escritura externa debe estar en ask o en deny.
        self.assertEqual(
            set(variable_de_validate("WRITE_TOOLS").split()),
            set(catalogo.IDS_PUBLICACION),
        )
        # Línea ~563: el matcher que validate-config exige en settings.json.
        self.assertEqual(
            set(variable_de_validate("EXTERNAL_WRITE_MATCHER").split("|")),
            set(catalogo.IDS_PUBLICACION),
        )

    def test_las_escrituras_del_catalogo_estan_gateadas_en_settings(self) -> None:
        permisos = json.loads(SETTINGS.read_text(encoding="utf-8"))["permissions"]
        gateadas = set(permisos.get("ask", [])) | set(permisos.get("deny", []))
        self.assertEqual(set(catalogo.IDS_PUBLICACION) - gateadas, set())

    def test_la_transicion_prohibida_esta_en_deny_y_en_validate_config(self) -> None:
        permisos = json.loads(SETTINGS.read_text(encoding="utf-8"))["permissions"]
        for identificador in catalogo.IDS_TRANSICION:
            with self.subTest(id=identificador):
                self.assertIn(identificador, permisos.get("deny", []))
                self.assertIn(identificador, VALIDATE.read_text(encoding="utf-8"))


class Normalizador(unittest.TestCase):
    def test_cada_id_canonico_se_reconoce_a_si_mismo(self) -> None:
        for entrada in catalogo.TRANSICIONES + catalogo.PUBLICACIONES:
            with self.subTest(id=entrada.id):
                self.assertEqual(catalogo.canonico(entrada.id), entrada.id)

    def test_reconoce_las_convenciones_de_los_tres_runtimes(self) -> None:
        casos = (
            ("mcp__atlassian__createJiraIssue", "mcp__atlassian__createJiraIssue"),
            ("mcp_atlassian_createJiraIssue", "mcp__atlassian__createJiraIssue"),
            ("atlassian.createJiraIssue", "mcp__atlassian__createJiraIssue"),
            ("atlassian_create_jira_issue", "mcp__atlassian__createJiraIssue"),
            ("jira-add-comment-to-issue", "mcp__atlassian__addCommentToJiraIssue"),
            ("mcp_atlassian_transitionJiraIssue", "mcp__atlassian__transitionJiraIssue"),
        )
        for nombre, esperado in casos:
            with self.subTest(nombre=nombre):
                self.assertEqual(catalogo.canonico(nombre), esperado)

    def test_no_reconoce_lo_que_el_harness_no_gobierna(self) -> None:
        for nombre in (
            "mcp__otro__write",
            "run_command",
            "mcp__atlassian__getJiraIssue",
            "mcp__atlassian__getTransitionsForJiraIssue",
            "mcp__atlassian__createConfluenceFooterComment",
            "mcp__atlassian__addWorklogToJiraIssue",
            "mcp__notion__notion-move-pages",
            "",
            None,
        ):
            with self.subTest(nombre=nombre):
                self.assertIsNone(catalogo.canonico(nombre))


if __name__ == "__main__":
    unittest.main(verbosity=2)
