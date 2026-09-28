#!/usr/bin/env python3
"""Tests del gate de publicación externa, sin runtime de por medio."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core.gates import catalogo, contract, publicacion  # noqa: E402


class RevisarTransicion(unittest.TestCase):
    """Cambiar el estado de un ticket no se negocia en ningún runtime."""

    def test_bloquea_la_transicion_en_cualquier_convencion(self) -> None:
        for nombre in (
            "mcp__atlassian__transitionJiraIssue",
            "mcp_atlassian_transitionJiraIssue",
            "atlassian.transitionJiraIssue",
            "jira_transition_issue",
        ):
            with self.subTest(nombre=nombre):
                veredicto = publicacion.revisar_transicion(nombre)
                self.assertTrue(veredicto.bloquea)
                self.assertIn("prohibido en este harness", veredicto.motivo)

    def test_se_abstiene_sobre_cualquier_otra_cosa(self) -> None:
        for nombre in ("mcp__atlassian__getTransitionsForJiraIssue", "run_command", ""):
            with self.subTest(nombre=nombre):
                self.assertTrue(publicacion.revisar_transicion(nombre).se_abstiene)


class RevisarPublicacion(unittest.TestCase):
    def assert_bloquea(self, herramienta: str, payload: object, texto: str) -> None:
        veredicto = publicacion.revisar_publicacion(herramienta, payload)
        self.assertTrue(veredicto.bloquea, f"'{herramienta}' debía bloquearse")
        self.assertIn(texto, veredicto.motivo)

    def test_deja_pasar_los_payloads_completos(self) -> None:
        casos = (
            ("mcp__atlassian__addCommentToJiraIssue", {"issueIdOrKey": "QA-1", "commentBody": "Cierre QA aprobado."}),
            ("mcp__atlassian__createConfluencePage", {"spaceKey": "QA", "title": "QA-1", "body": "Análisis completo."}),
            ("mcp__notion__notion-create-pages", {"pages": [{"properties": {"title": "QA-1"}, "content": "Casos completos."}]}),
            ("mcp__notion__notion-update-page", {"command": "update_properties", "properties": {"title": "APROBADO"}}),
        )
        for herramienta, payload in casos:
            with self.subTest(herramienta=herramienta):
                self.assertEqual(
                    publicacion.revisar_publicacion(herramienta, payload).decision,
                    contract.PERMITIR,
                )

    def test_bloquea_el_payload_sin_contenido_publicable(self) -> None:
        herramienta = "mcp__atlassian__addCommentToJiraIssue"
        self.assert_bloquea(herramienta, {}, "no encontré contenido")
        self.assert_bloquea(herramienta, {"issueIdOrKey": "QA-1"}, "no encontré contenido")

    def test_bloquea_el_contenido_demasiado_corto(self) -> None:
        self.assert_bloquea("mcp__atlassian__createJiraIssue", {"summary": "ok"}, "demasiado corto")

    def test_bloquea_el_payload_que_ni_siquiera_es_un_objeto(self) -> None:
        for payload in (None, "texto suelto", ["a"]):
            with self.subTest(payload=payload):
                self.assert_bloquea("mcp__atlassian__createJiraIssue", payload, "payload vacío o inválido")

    def test_bloquea_los_placeholders_a_cualquier_profundidad(self) -> None:
        herramienta = "mcp__notion__notion-create-pages"
        casos = (
            {"pages": [{"content": "Ticket <TICKET> pendiente"}]},
            {"pages": [{"content": "TODO: completar resultados"}]},
            {"pages": [{"content": "Responsable {{ nombre }}"}]},
            {"pages": [{"content": "https://tuempresa.atlassian.net"}]},
            {"pages": [{"content": "Pon el id en PON-AQUI"}]},
            {"pages": [{"content": "Token YOUR_API_KEY sin resolver"}]},
        )
        for payload in casos:
            with self.subTest(payload=payload):
                self.assert_bloquea(herramienta, payload, "placeholder")

    def test_se_abstiene_sobre_una_herramienta_que_no_gobierna(self) -> None:
        """No es bloqueo: cada runtime decide qué hacer con la abstención."""
        for herramienta in ("mcp__otro__write", "run_command", "mcp__atlassian__getJiraIssue", None):
            with self.subTest(herramienta=herramienta):
                veredicto = publicacion.revisar_publicacion(herramienta, {"content": "texto"})
                self.assertTrue(veredicto.se_abstiene)
                self.assertIn("herramienta inesperada", veredicto.motivo)


class ClasificadorDeLecturas(unittest.TestCase):
    """Una lectura mal clasificada como escritura ensucia el log de Antigravity;
    una escritura clasificada como lectura desaparece sin que nadie se entere."""

    def test_las_lecturas_son_lecturas_en_cualquier_convencion(self) -> None:
        for nombre in (
            "mcp__atlassian__getJiraIssue",
            "atlassian.getJiraIssue",
            "atlassian_get_jira_issue",
            "mcp__atlassian__searchConfluenceUsingCql",
            "mcp__notion__notion-search",
            "mcp__notion__notion-fetch",
            "notion-get-comments",
            "mcp__atlassian__getTransitionsForJiraIssue",
        ):
            with self.subTest(nombre=nombre):
                self.assertTrue(publicacion.es_lectura(nombre), f"'{nombre}' es lectura")

    def test_ninguna_escritura_cae_en_el_balde_de_lectura(self) -> None:
        """Incluye escrituras que traen un verbo de lectura (notion-update-view)."""
        escrituras = list(catalogo.IDS_PUBLICACION) + list(catalogo.IDS_TRANSICION) + [
            "mcp__atlassian__createConfluenceFooterComment",
            "mcp__atlassian__addWorklogToJiraIssue",
            "mcp__notion__notion-move-pages",
            "mcp__notion__notion-create-view",
            "mcp__notion__notion-update-view",
        ]
        for nombre in escrituras:
            with self.subTest(nombre=nombre):
                self.assertFalse(publicacion.es_lectura(nombre), f"'{nombre}' es escritura")

    def test_separa_las_palabras_de_cualquier_naming(self) -> None:
        self.assertEqual(
            publicacion.palabras("mcp__atlassian__getJiraIssue"),
            {"mcp", "atlassian", "get", "jira", "issue"},
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
