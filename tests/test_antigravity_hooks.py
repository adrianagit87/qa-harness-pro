"""Unit tests de los hooks portados a Antigravity.

Verifican el contrato de Antigravity ({"decision": ..., "reason": ...}) y, sobre
todo, que el default sea NO OPINAR: estos hooks corren con matcher "*", así que
un default restrictivo bloquearía el agente entero.

Cada test corre los hooks con un HOME temporal propio: el log de tools
desconocidas y la marca pendiente caen en ese sandbox, nunca en el ~/.gemini
real de quien corre la suite.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness_temporal import BASELINE_ROTO, BASELINE_VALIDO, copiar_harness, escribir_config  # noqa: E402
HOOKS = ROOT / "adapters" / "antigravity" / "hooks"
SETTINGS = ROOT / ".claude" / "settings.json"

# Donde escriben los hooks cuando no hay override, relativo a HOME.
UNKNOWN_LOG_DEFAULT = Path(".gemini") / "qa-harness-unknown-tools.log"
PENDING_DEFAULT = Path(".gemini") / "qa-harness-pending-check.json"


def base_env(home: Path) -> dict:
    """Entorno heredado, con HOME en el sandbox y sin rutas QA_HARNESS_* de afuera."""
    env = {key: value for key, value in os.environ.items() if not key.startswith("QA_HARNESS_")}
    env["HOME"] = str(home)
    return env


def call(name: str, args: dict | None = None) -> dict:
    return {"toolCall": {"name": name, "args": args or {}}}


def settings_tools(block: str) -> list:
    """Tools MCP de un bloque de permissions de .claude/settings.json: la fuente
    de verdad de qué lee (allow) y qué escribe (ask, deny) el harness."""
    permissions = json.loads(SETTINGS.read_text(encoding="utf-8"))["permissions"]
    return [tool for tool in permissions[block] if tool.startswith("mcp__")]


def name_forms(tool: str) -> tuple:
    """La misma tool en las convenciones de nombre que el gate debe reconocer:
    mcp__atlassian__getJiraIssue, atlassian.getJiraIssue, atlassian_get_jira_issue."""
    _, server, action = tool.split("__")
    snake = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", action).replace("-", "_").lower()
    return tool, f"{server}.{action}", f"{server}_{snake}"


def fingerprint(path: Path) -> tuple:
    """Huella de un archivo del HOME real: si cambia, un hook escribió ahí."""
    try:
        info = path.stat()
    except FileNotFoundError:
        return (str(path), None)
    return (str(path), info.st_size, info.st_mtime_ns)


class HookTestCase(unittest.TestCase):
    """Base: HOME temporal por test y rutas de estado apuntando dentro de él."""

    def setUp(self):
        sandbox = tempfile.TemporaryDirectory()
        self.addCleanup(sandbox.cleanup)
        self.home = Path(sandbox.name)
        self.unknown_log = self.home / "unknown-tools.log"
        self.pending = self.home / "pending-check.json"

    def run_hook(self, script: str, payload: dict, env: dict | None = None) -> str:
        if env is None:
            env = {
                **base_env(self.home),
                "QA_HARNESS_UNKNOWN_TOOLS_LOG": str(self.unknown_log),
                "QA_HARNESS_PENDING_CHECK": str(self.pending),
            }
        result = subprocess.run(
            [sys.executable, str(HOOKS / script)],
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            check=False,
            env=env,
        )
        return result.stdout.strip()

    def logged(self) -> str:
        """Lo que los hooks anotaron como tool desconocida durante este test."""
        return self.unknown_log.read_text(encoding="utf-8") if self.unknown_log.exists() else ""


class BlockDestructiveCommand(HookTestCase):
    HOOK = "block-destructive-command.py"

    def test_bloquea_rm_recursivo_forzado(self):
        out = json.loads(self.run_hook(self.HOOK, call("run_command", {"CommandLine": "rm -rf /tmp/x"})))
        self.assertEqual(out["decision"], "deny")

    def test_bloquea_push_forzado(self):
        out = json.loads(self.run_hook(self.HOOK, call("run_command", {"CommandLine": "git push --force origin main"})))
        self.assertEqual(out["decision"], "deny")

    def test_no_opina_sobre_comando_inocuo(self):
        self.assertEqual(self.run_hook(self.HOOK, call("run_command", {"CommandLine": "ls -la"})), "")

    def test_no_opina_sobre_otra_herramienta(self):
        self.assertEqual(self.run_hook(self.HOOK, call("view_file", {"path": "a.txt"})), "")


class ValidateExternalWrite(HookTestCase):
    HOOK = "validate-external-write.py"

    def test_deniega_transicion_de_jira(self):
        out = json.loads(self.run_hook(self.HOOK, call("mcp__atlassian__transitionJiraIssue", {"issueIdOrKey": "US-1"})))
        self.assertEqual(out["decision"], "deny")

    def test_deniega_placeholder_sin_resolver(self):
        payload = call("mcp__atlassian__createJiraIssue",
                       {"summary": "CP-01", "description": "Tabla: PON-AQUI-EL-ID"})
        out = json.loads(self.run_hook(self.HOOK, payload))
        self.assertEqual(out["decision"], "deny")
        self.assertIn("placeholder", out["reason"])

    def test_pide_confirmacion_explicita_en_escritura_limpia(self):
        payload = call("mcp__atlassian__createJiraIssue",
                       {"summary": "[PROJ-123][QA] CP-01", "description": "## Objetivo. Validar."})
        out = json.loads(self.run_hook(self.HOOK, payload))
        self.assertEqual(out["decision"], "force_ask")

    def test_deniega_payload_sin_contenido_publicable(self):
        out = json.loads(self.run_hook(self.HOOK, call("mcp__atlassian__createJiraIssue", {"projectKey": "QA"})))
        self.assertEqual(out["decision"], "deny")

    def test_no_opina_ni_anota_las_lecturas(self):
        """Regresión: el patrón de lectura exigía get_/get-, así que getJiraIssue
        (camelCase) se anotaba en el log como posible escritura externa."""
        # getTransitionsForJiraIssue: leer las transiciones no es transicionar.
        reads = settings_tools("allow") + ["mcp__atlassian__getTransitionsForJiraIssue"]
        for tool in reads:
            for name in name_forms(tool):
                with self.subTest(name=name):
                    self.assertEqual(self.run_hook(self.HOOK, call(name, {"issueIdOrKey": "US-1"})), "")
                    self.assertNotIn(name, self.logged(), f"'{name}' es lectura y se anotó como escritura")

    def test_anota_la_escritura_que_no_reconoce(self):
        """Una escritura que el gate no cubre no se bloquea, pero tampoco pasa en
        silencio: queda en el log para afinar los patrones con datos reales."""
        for name in ("mcp__atlassian__createConfluenceFooterComment",
                     "mcp__atlassian__addWorklogToJiraIssue",
                     "mcp__notion__notion-move-pages"):
            with self.subTest(name=name):
                self.assertEqual(self.run_hook(self.HOOK, call(name, {"body": "texto"})), "")
                self.assertIn(name, self.logged())

    def test_no_opina_sobre_herramienta_ajena(self):
        """ABSTENERSE acá es silencio: el matcher es '*' y bloquear por default
        frenaría al agente entero. La contraparte en Claude Code (mismo
        veredicto, proyectado como deny) está en test_validate_external_write."""
        self.assertEqual(self.run_hook(self.HOOK, call("run_command", {"CommandLine": "ls"})), "")

    def test_reconoce_nombres_de_tool_con_otras_convenciones(self):
        """El naming de las tools MCP en Antigravity no está documentado: el
        gate debe enganchar por patrón, no por igualdad exacta."""
        for name in ("atlassian.createJiraIssue",
                     "atlassian_create_jira_issue",
                     "jira-add-comment-to-issue"):
            with self.subTest(name=name):
                out = self.run_hook(self.HOOK, call(name, {"description": "contenido real y suficiente"}))
                self.assertNotEqual(out, "", f"el gate no enganchó '{name}'")


class SurfacePendingCheck(HookTestCase):
    """Este hook es el que le devuelve los dientes al gate post-edit: el
    PostToolUse de Antigravity no puede darle feedback al agente, así que la
    falla se guarda en una marca y se levanta acá."""

    HOOK = "surface-pending-check.py"

    def _run(self) -> str:
        return self.run_hook(self.HOOK, call("run_command", {}))

    def test_no_opina_sin_marca_pendiente(self):
        self.assertEqual(self._run(), "")

    def test_levanta_la_marca_como_ask(self):
        self.pending.write_text(json.dumps({"reason": "fallo tests Python"}), encoding="utf-8")
        out = json.loads(self._run())
        self.assertEqual(out["decision"], "ask")
        self.assertIn("fallo tests Python", out["reason"])

    def test_consume_la_marca_una_sola_vez(self):
        self.pending.write_text(json.dumps({"reason": "algo se rompio"}), encoding="utf-8")
        self.assertNotEqual(self._run(), "")
        self.assertFalse(self.pending.exists(), "la marca debe borrarse tras levantarse")
        self.assertEqual(self._run(), "", "no debe repetir el aviso")


class CheckAfterEdit(HookTestCase):
    HOOK = "check-after-edit.py"

    def test_respeta_el_contrato_vacio_de_posttooluse(self):
        out = self.run_hook(self.HOOK, call("view_file", {"path": "x"}))
        self.assertEqual(out, "{}")

    def test_ignora_los_archivos_fuera_del_harness(self):
        """ABSTENERSE acá es silencio: no deja marca pendiente."""
        self.run_hook(self.HOOK, call("write_to_file", {"TargetFile": "/etc/hosts"}))
        self.assertFalse(self.pending.exists())


class BaselineConfiguradoFueraDelHarness(HookTestCase):
    """El baseline configurado se valida esté donde esté; lo demás de afuera, no."""

    def setUp(self):
        super().setUp()
        dirs = [tempfile.TemporaryDirectory() for _ in range(2)]
        for temporal in dirs:
            self.addCleanup(temporal.cleanup)
        harness, afuera = (Path(d.name) for d in dirs)
        self.hook = copiar_harness(harness, "antigravity") / "check-after-edit.py"
        self.baseline = afuera / "baseline.md"
        escribir_config(harness, {"enabled": True, "path": str(self.baseline)})

    def editar(self, path: Path) -> None:
        env = {
            **base_env(self.home),
            "QA_HARNESS_UNKNOWN_TOOLS_LOG": str(self.unknown_log),
            "QA_HARNESS_PENDING_CHECK": str(self.pending),
        }
        subprocess.run([sys.executable, str(self.hook)],
                       input=json.dumps(call("write_to_file", {"TargetFile": str(path)})),
                       text=True, capture_output=True, check=False, env=env)

    def test_el_baseline_roto_deja_la_marca(self):
        self.baseline.write_text(BASELINE_ROTO, encoding="utf-8")
        self.editar(self.baseline)
        self.assertIn("baseline invalido", self.pending.read_text(encoding="utf-8"))

    def test_el_baseline_valido_no_deja_marca(self):
        self.baseline.write_text(BASELINE_VALIDO, encoding="utf-8")
        self.editar(self.baseline)
        self.assertFalse(self.pending.exists())

    def test_otro_markdown_de_afuera_sigue_ignorado(self):
        ajeno = self.baseline.parent / "otro.md"
        ajeno.write_text(BASELINE_ROTO, encoding="utf-8")
        self.editar(ajeno)
        self.assertFalse(self.pending.exists())


class AislamientoDelHome(HookTestCase):
    """Guardia de la suite: sin overrides, los hooks escriben bajo HOME. Con HOME
    en un sandbox, todo cae ahí y el ~/.gemini real queda intacto."""

    def test_el_estado_por_default_cae_en_el_home_del_sandbox(self):
        real = [Path.home() / UNKNOWN_LOG_DEFAULT, Path.home() / PENDING_DEFAULT]
        before = [fingerprint(path) for path in real]

        with tempfile.TemporaryDirectory() as project:
            broken = Path(project) / "roto.json"
            broken.write_text('{"falta": }', encoding="utf-8")
            env = {**base_env(self.home), "QA_HARNESS_ROOT": project}

            # 1. log de tools desconocidas
            self.run_hook("validate-external-write.py",
                          call("mcp__atlassian__createConfluenceFooterComment", {"body": "texto"}), env)
            # 2. marca pendiente tras una edicion que rompe el JSON
            self.run_hook("check-after-edit.py", call("write_to_file", {"TargetFile": str(broken)}), env)
            self.assertTrue((self.home / PENDING_DEFAULT).is_file(), "la marca no cayó en el HOME del sandbox")
            # 3. la marca se levanta y se consume desde el mismo HOME
            out = json.loads(self.run_hook("surface-pending-check.py", call("run_command", {}), env))
            self.assertEqual(out["decision"], "ask")

        self.assertIn("createConfluenceFooterComment",
                      (self.home / UNKNOWN_LOG_DEFAULT).read_text(encoding="utf-8"))
        written = sorted(str(p.relative_to(self.home)) for p in self.home.rglob("*") if p.is_file())
        self.assertEqual(written, [str(UNKNOWN_LOG_DEFAULT)], "los hooks escribieron fuera de lo esperado")
        self.assertEqual([fingerprint(path) for path in real], before, "un hook escribió en el ~/.gemini real")


if __name__ == "__main__":
    unittest.main()
