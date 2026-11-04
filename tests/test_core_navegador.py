#!/usr/bin/env python3
"""Gate del navegador: dónde se navega, qué se escribe y dónde termina la página."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ))

from core.gates import contract, navegador  # noqa: E402

CONFIG = {
    "environments": {
        "default": "DEV",
        "list": [
            {"key": "DEV", "urls": ["https://dev.acme.test"], "production": False},
            {"key": "STG", "urls": ["https://stg.acme.test:8443/app"]},
            {"key": "PROD", "urls": ["https://app.acme.test"], "production": True},
        ],
    },
    "automation": {"subprojects": [{"name": "web", "service": "web", "url": "http://localhost:3000/app"}]},
}

ALCANCE = navegador.alcance_de_config(CONFIG, {"QA_USER_PASSWORD"})
PROD = "https://app.acme.test:443"


def accion(tool: str, entrada: object) -> contract.Verdict:
    return navegador.revisar_accion(f"mcp__playwright__{tool}", entrada, ALCANCE)


def pagina(texto: str, confirmada: set[str] | None = None) -> contract.Verdict:
    respuesta = [{"type": "text", "text": texto}]
    return navegador.revisar_pagina("mcp__playwright__browser_click", respuesta, ALCANCE, confirmada or set())


class Origenes(unittest.TestCase):
    def test_normaliza_esquema_host_y_puerto(self) -> None:
        casos = {
            "https://Dev.Acme.test/login?x=1": "https://dev.acme.test:443",
            "dev.acme.test/login": "https://dev.acme.test:443",
            "localhost:3000/x": "http://localhost:3000",
            "http://dev.acme.test.": "http://dev.acme.test:80",
        }
        for url, esperado in casos.items():
            with self.subTest(url=url):
                self.assertEqual(navegador.origen(url), esperado)

    def test_lo_que_no_es_http_no_tiene_origen(self) -> None:
        for url in ("javascript:alert(1)", "file:///etc/passwd", "data:text/html,hola", "https://", "", None, 42,
                    "https://dev.acme.test:99999"):
            with self.subTest(url=url):
                self.assertIsNone(navegador.origen(url))

    def test_el_host_real_es_el_que_va_despues_de_la_arroba(self) -> None:
        self.assertEqual(navegador.origen("https://dev.acme.test@evil.test/"), "https://evil.test:443")


class ComodinDePreviews(unittest.TestCase):
    PATRON = "https://*---web-abc123xyz-uc.a.run.app"

    def alcance(self, urls: list[str], produccion: bool = False) -> navegador.Alcance:
        config = {"environments": {"list": [{"key": "DEV", "urls": urls, "production": produccion}]}}
        return navegador.alcance_de_config(config)

    def test_acepta_un_comodin_acotado_al_servicio(self) -> None:
        self.assertEqual(
            navegador.origen_configurado(self.PATRON), "https://*---web-abc123xyz-uc.a.run.app:443"
        )

    def test_rechaza_comodines_que_abren_de_mas(self) -> None:
        for url in ("https://*.a.run.app", "https://*.com", "https://*", "https://a*---web-abc123xyz-uc.a.run.app",
                    "https://*---web-abc123xyz-uc.*.run.app", "https://*-uc.a.run.app",
                    "https://*---web-abc123xyz-uc", "ftp://*---web-abc123xyz-uc.a.run.app",
                    "https://user@*---web-abc123xyz-uc.a.run.app"):
            with self.subTest(url=url):
                self.assertIsNone(navegador.origen_configurado(url))

    def test_permite_cualquier_tag_del_mismo_servicio(self) -> None:
        alcance = self.alcance([self.PATRON])
        for url in ("https://us1234---web-abc123xyz-uc.a.run.app/en/auth/login",
                    "https://us-2100---web-abc123xyz-uc.a.run.app"):
            with self.subTest(url=url):
                self.assertEqual(navegador.revisar_url(url, alcance).decision, contract.PERMITIR)

    def test_no_se_escapa_a_otro_dominio_ni_a_otro_servicio(self) -> None:
        alcance = self.alcance([self.PATRON])
        for url in ("https://evil.com/---web-abc123xyz-uc.a.run.app",
                    "https://x.evil---web-abc123xyz-uc.a.run.app",
                    "https://us1234---web-abc123xyz-uc.a.run.app.evil.com",
                    "https://---web-abc123xyz-uc.a.run.app",
                    "https://us1234---otro-servicio-uc.a.run.app",
                    "http://us1234---web-abc123xyz-uc.a.run.app",
                    "https://*---web-abc123xyz-uc.a.run.app"):
            with self.subTest(url=url):
                self.assertEqual(navegador.revisar_url(url, alcance).decision, contract.BLOQUEAR)

    def test_un_comodin_de_produccion_pregunta(self) -> None:
        alcance = self.alcance([self.PATRON], produccion=True)
        url = "https://us1234---web-abc123xyz-uc.a.run.app"
        self.assertEqual(navegador.revisar_url(url, alcance).decision, contract.PREGUNTAR)
        self.assertEqual(
            navegador.produccion_pedida("mcp__playwright__browser_navigate", {"url": url}, alcance),
            {"https://us1234---web-abc123xyz-uc.a.run.app:443"},
        )


class AlcanceDeLaConfig(unittest.TestCase):
    def test_ambientes_y_subproyectos_dan_los_origenes(self) -> None:
        self.assertEqual(
            ALCANCE.permitidos,
            {"https://dev.acme.test:443", "https://stg.acme.test:8443", "http://localhost:3000"},
        )
        self.assertEqual(ALCANCE.produccion, {PROD})

    def test_un_origen_de_produccion_es_produccion_aunque_figure_en_otro_lado(self) -> None:
        config = json.loads(json.dumps(CONFIG))
        config["automation"]["subprojects"].append({"name": "prod", "url": "https://app.acme.test/x"})
        alcance = navegador.alcance_de_config(config)
        self.assertNotIn(PROD, alcance.permitidos)
        self.assertIn(PROD, alcance.produccion)

    def test_sin_ninguna_url_no_hay_donde_ejecutar(self) -> None:
        alcance = navegador.alcance_de_config({"environments": {"list": [{"key": "DEV"}]}})
        self.assertTrue(alcance.error)
        self.assertTrue(navegador.revisar_url("https://dev.acme.test", alcance).bloquea)

    def test_config_que_no_es_objeto_falla_cerrado(self) -> None:
        self.assertTrue(navegador.alcance_de_config([]).error)


class Navegacion(unittest.TestCase):
    def test_ambiente_configurado_se_permite(self) -> None:
        for url in ("https://dev.acme.test/login", "dev.acme.test", "https://stg.acme.test:8443/otra", "localhost:3000"):
            with self.subTest(url=url):
                self.assertEqual(accion("browser_navigate", {"url": url}).decision, contract.PERMITIR)

    def test_produccion_se_pregunta_nunca_se_permite_sola(self) -> None:
        veredicto = accion("browser_navigate", {"url": "https://app.acme.test/home"})
        self.assertTrue(veredicto.pregunta)
        self.assertIn("PRODUCCIÓN", veredicto.motivo)

    def test_fuera_de_los_ambientes_se_bloquea(self) -> None:
        for url in (
            "https://evil.test",
            "https://dev.acme.test@evil.test/",
            "https://dev.acme.test.evil.test",
            "https://stg.acme.test/app",  # mismo host, otro puerto
            "http://dev.acme.test",  # mismo host, otro esquema
            "javascript:location='https://evil.test'",
            "file:///etc/hosts",
        ):
            with self.subTest(url=url):
                self.assertTrue(accion("browser_navigate", {"url": url}).bloquea)

    def test_una_pestana_nueva_tambien_pasa_por_el_gate(self) -> None:
        self.assertTrue(accion("browser_tabs", {"action": "new", "url": "https://evil.test"}).bloquea)
        self.assertEqual(accion("browser_tabs", {"action": "list"}).decision, contract.PERMITIR)

    def test_about_blank_es_inocuo(self) -> None:
        self.assertEqual(accion("browser_navigate", {"url": "about:blank"}).decision, contract.PERMITIR)


class Escritura(unittest.TestCase):
    def test_contrasena_solo_por_nombre_de_secreto(self) -> None:
        campo = {"target": "#password", "element": "Contraseña"}
        self.assertEqual(accion("browser_type", {**campo, "text": "QA_USER_PASSWORD"}).decision, contract.PERMITIR)
        self.assertTrue(accion("browser_type", {**campo, "text": "hunter2"}).bloquea)
        self.assertTrue(accion("browser_type", {**campo, "text": "OTRO_SECRETO"}).bloquea)

    def test_campos_sensibles_por_nombre(self) -> None:
        for descripcion in ("Password", "Contraseña", "contrasena", "PIN", "CVV", "Número de tarjeta", "card-number"):
            with self.subTest(campo=descripcion):
                self.assertTrue(accion("browser_type", {"target": "e1", "element": descripcion, "text": "1234"}).bloquea)

    def test_fill_form_no_llena_campos_sensibles_ni_con_secreto(self) -> None:
        # browser_fill_form no sustituye secretos: escribiría el nombre literal.
        entrada = {"fields": [{"name": "Password", "type": "textbox", "value": "QA_USER_PASSWORD", "target": "#p"}]}
        self.assertTrue(accion("browser_fill_form", entrada).bloquea)

    def test_fill_form_con_datos_de_prueba_pasa(self) -> None:
        entrada = {"fields": [
            {"name": "Nombre", "type": "textbox", "value": "Cliente Prueba", "target": "#n"},
            {"name": "Acepta", "type": "checkbox", "value": "true", "target": "#a"},
        ]}
        self.assertEqual(accion("browser_fill_form", entrada).decision, contract.PERMITIR)

    def test_numero_de_tarjeta_se_bloquea_en_cualquier_campo(self) -> None:
        for texto in ("4111111111111111", "4111 1111 1111 1111", "pago con 5555-5555-5555-4444 hoy"):
            with self.subTest(texto=texto):
                self.assertTrue(accion("browser_type", {"target": "e1", "element": "Notas", "text": texto}).bloquea)

    def test_numeros_largos_que_no_pasan_luhn_no_son_tarjeta(self) -> None:
        self.assertFalse(navegador.tiene_tarjeta("4111111111111112"))
        self.assertFalse(navegador.tiene_tarjeta("pedido 123456"))

    def test_tarjeta_en_un_dialogo_o_un_select_tambien(self) -> None:
        self.assertTrue(accion("browser_handle_dialog", {"accept": True, "promptText": "4111111111111111"}).bloquea)
        self.assertTrue(accion("browser_select_option", {"target": "e1", "values": ["4111111111111111"]}).bloquea)


class ToolsConReglaPropia(unittest.TestCase):
    def test_javascript_arbitrario_prohibido(self) -> None:
        for tool in ("browser_evaluate", "browser_run_code_unsafe"):
            with self.subTest(tool=tool):
                self.assertTrue(accion(tool, {"function": "() => location.href = 'https://evil.test'"}).bloquea)

    def test_subir_archivos_se_pregunta(self) -> None:
        self.assertTrue(accion("browser_file_upload", {"paths": ["/tmp/x.pdf"]}).pregunta)

    def test_otra_herramienta_se_abstiene_y_entrada_ilegible_bloquea(self) -> None:
        self.assertTrue(navegador.revisar_accion("mcp__atlassian__getJiraIssue", {}, ALCANCE).se_abstiene)
        self.assertTrue(accion("browser_click", None).bloquea)


class DondeTerminoLaPagina(unittest.TestCase):
    def test_una_redireccion_fuera_de_alcance_se_frena(self) -> None:
        veredicto = pagina("### Page\n- Page URL: https://evil.test/x\n- Page Title: X\n")
        self.assertTrue(veredicto.bloquea)
        self.assertIn("Bloqueado", veredicto.motivo)

    def test_una_pestana_abierta_fuera_de_alcance_tambien(self) -> None:
        texto = "### Open tabs\n- 0: (current) [A](https://dev.acme.test/a)\n- 1: [B](https://evil.test/b)\n"
        self.assertTrue(pagina(texto).bloquea)

    def test_dentro_de_los_ambientes_pasa(self) -> None:
        texto = "### Open tabs\n- 0: [](about:blank)\n- 1: (current) [A](https://dev.acme.test/a)\n### Page\n- Page URL: https://dev.acme.test/a\n"
        self.assertEqual(pagina(texto).decision, contract.PERMITIR)

    def test_produccion_sin_confirmar_se_frena_y_confirmada_pasa(self) -> None:
        texto = "### Page\n- Page URL: https://app.acme.test/home\n"
        self.assertTrue(pagina(texto).bloquea)
        self.assertEqual(pagina(texto, {PROD}).decision, contract.PERMITIR)

    def test_respuesta_sin_url_no_opina(self) -> None:
        self.assertEqual(pagina("### Result\n22\n").decision, contract.PERMITIR)

    def test_solo_cuenta_como_confirmada_la_produccion_pedida_a_proposito(self) -> None:
        pedida = navegador.produccion_pedida("mcp__playwright__browser_navigate", {"url": "https://app.acme.test"}, ALCANCE)
        self.assertEqual(pedida, {PROD})
        self.assertEqual(
            navegador.produccion_pedida("mcp__playwright__browser_navigate", {"url": "https://dev.acme.test"}, ALCANCE),
            set(),
        )


class Persistencia(unittest.TestCase):
    def test_secretos_solo_nombres_y_produccion_por_sesion(self) -> None:
        with tempfile.TemporaryDirectory() as temporal:
            carpeta = Path(temporal)
            secretos = carpeta / "s.env"
            secretos.write_text("# comentario\nQA_A=valor\nexport QA_B = otro\nmal nombre=x\n\n", encoding="utf-8")
            self.assertEqual(navegador.nombres_de_secretos(secretos), {"QA_A", "QA_B"})
            self.assertEqual(navegador.nombres_de_secretos(carpeta / "no-existe.env"), frozenset())

            navegador.recordar_produccion(carpeta, "s1", {PROD})
            self.assertEqual(navegador.produccion_confirmada(carpeta, "s1"), {PROD})
            self.assertEqual(navegador.produccion_confirmada(carpeta, "otra-sesion"), set())
            self.assertEqual(navegador.produccion_confirmada(None, "s1"), set())

    def test_cargar_alcance_lee_perfil_empresa_y_secretos(self) -> None:
        with tempfile.TemporaryDirectory() as temporal:
            raiz = Path(temporal)
            self.assertTrue(navegador.cargar_alcance(raiz).error)
            (raiz / "profile").mkdir()
            (raiz / "companies").mkdir()
            (raiz / "profile" / "profile.json").write_text(json.dumps({"activeCompany": "acme"}), encoding="utf-8")
            (raiz / "companies" / "acme.json").write_text(json.dumps(CONFIG), encoding="utf-8")
            (raiz / "profile" / "browser-secrets.env").write_text("QA_USER_PASSWORD=x\n", encoding="utf-8")
            alcance = navegador.cargar_alcance(raiz)
            self.assertEqual(alcance.error, "")
            self.assertEqual(alcance.secretos, {"QA_USER_PASSWORD"})

            (raiz / "profile" / "profile.json").write_text(json.dumps({"activeCompany": "../x"}), encoding="utf-8")
            self.assertTrue(navegador.cargar_alcance(raiz).error)


if __name__ == "__main__":
    unittest.main(verbosity=2)
