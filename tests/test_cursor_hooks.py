"""Unit tests de los hooks portados a Cursor.

El contrato viene de leer el binario de Cursor.app:
  beforeShellExecution  in {"command","cwd"}          out {"permission":"deny"|"ask","user_message"}
  beforeMCPExecution    in {"tool_name","tool_input"} out {"permission":"deny","user_message"}
                        -- tool_input llega como STRING JSON
  afterFileEdit         in {"file_path","edits"}      no puede bloquear

Cada test corre los hooks con un HOME temporal propio: la marca pendiente cae en
ese sandbox, nunca en el ~/.cursor real de quien corre la suite.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness_temporal import BASELINE_ROTO, BASELINE_VALIDO, copiar_harness, escribir_config  # noqa: E402
HOOKS = ROOT / "adapters" / "cursor" / "hooks"

# Donde escriben los hooks cuando no hay override, relativo a HOME.
PENDING_DEFAULT = Path(".cursor") / "qa-harness-pending-check.json"


def base_env(home: Path) -> dict:
    """Entorno heredado, con HOME en el sandbox y sin rutas QA_HARNESS_* de afuera."""
    env = {key: value for key, value in os.environ.items() if not key.startswith("QA_HARNESS_")}
    env["HOME"] = str(home)
    return env


def fingerprint(path: Path) -> tuple:
    """Huella de un archivo del HOME real: si cambia, un hook escribió ahí."""
    try:
        info = path.stat()
    except FileNotFoundError:
        return (str(path), None)
    return (str(path), info.st_size, info.st_mtime_ns)


class HookTestCase(unittest.TestCase):
    """Base: HOME temporal por test y marca pendiente apuntando dentro de él."""

    def setUp(self):
        sandbox = tempfile.TemporaryDirectory()
        self.addCleanup(sandbox.cleanup)
        self.home = Path(sandbox.name)
        self.pending = self.home / "pending-check.json"

    def run_hook(self, script: str, payload: dict, env: dict | None = None) -> str:
        if env is None:
            env = {**base_env(self.home), "QA_HARNESS_PENDING_CHECK": str(self.pending)}
        result = subprocess.run(
            [sys.executable, str(HOOKS / script)],
            input=json.dumps(payload), text=True, capture_output=True, check=False, env=env,
        )
        return result.stdout.strip()


class BeforeShellExecution(HookTestCase):
    HOOK = "block-destructive-command.py"

    def _clean(self, payload):
        return self.run_hook(self.HOOK, payload)

    def test_bloquea_rm_recursivo_forzado(self):
        out = json.loads(self._clean({"command": "rm -rf /tmp/x", "cwd": "/tmp"}))
        self.assertEqual(out["permission"], "deny")

    def test_bloquea_reset_hard(self):
        out = json.loads(self._clean({"command": "git reset --hard origin/main", "cwd": "/tmp"}))
        self.assertEqual(out["permission"], "deny")

    def test_no_opina_sobre_comando_inocuo(self):
        self.assertEqual(self._clean({"command": "npm test", "cwd": "/tmp"}), "")

    def test_levanta_check_pendiente_como_ask(self):
        self.pending.write_text(json.dumps({"reason": "fallo tests Python"}), encoding="utf-8")
        out = json.loads(self.run_hook(self.HOOK, {"command": "npm test", "cwd": "/tmp"}))
        self.assertEqual(out["permission"], "ask")
        self.assertIn("fallo tests Python", out["user_message"])
        self.assertFalse(self.pending.exists(), "la marca debe consumirse")

    def test_el_comando_destructivo_gana_sobre_el_pendiente(self):
        self.pending.write_text(json.dumps({"reason": "algo"}), encoding="utf-8")
        out = json.loads(self.run_hook(self.HOOK, {"command": "rm -rf /", "cwd": "/tmp"}))
        self.assertEqual(out["permission"], "deny")


class BeforeMCPExecution(HookTestCase):
    HOOK = "validate-external-write.py"

    @staticmethod
    def call(name: str, args: dict) -> dict:
        # Cursor serializa tool_input como string JSON
        return {"tool_name": name, "tool_input": json.dumps(args)}

    def test_deniega_transicion_de_jira(self):
        out = json.loads(self.run_hook(self.HOOK, self.call("mcp_atlassian_transitionJiraIssue", {"issueIdOrKey": "US-1"})))
        self.assertEqual(out["permission"], "deny")

    def test_deniega_placeholder_sin_resolver(self):
        payload = self.call("mcp_atlassian_createJiraIssue",
                            {"summary": "CP-01", "description": "Tabla: PON-AQUI-EL-ID"})
        out = json.loads(self.run_hook(self.HOOK, payload))
        self.assertEqual(out["permission"], "deny")
        self.assertIn("placeholder", out["user_message"])

    def test_deja_pasar_contenido_limpio(self):
        """Cursor no soporta 'ask' en beforeMCPExecution: la confirmación la pone
        su propio allowlist de MCP. El hook solo valida el contenido."""
        payload = self.call("mcp_atlassian_createJiraIssue",
                            {"summary": "[PROJ-123][QA] CP-01", "description": "## Objetivo. Validar."})
        self.assertEqual(self.run_hook(self.HOOK, payload), "")

    def test_deniega_payload_sin_contenido_publicable(self):
        out = json.loads(self.run_hook(self.HOOK, self.call("mcp_atlassian_createJiraIssue", {"projectKey": "QA"})))
        self.assertEqual(out["permission"], "deny")

    def test_no_opina_sobre_lectura(self):
        self.assertEqual(self.run_hook(self.HOOK, self.call("mcp_atlassian_getJiraIssue", {"issueIdOrKey": "US-1"})), "")

    def test_no_opina_sobre_herramienta_ajena(self):
        """ABSTENERSE acá es silencio: este hook ve TODA llamada MCP. La
        contraparte en Claude Code (mismo veredicto, proyectado como deny) está
        en test_validate_external_write."""
        self.assertEqual(self.run_hook(self.HOOK, self.call("mcp__otro__write", {"content": "texto real"})), "")

    def test_parsea_tool_input_como_string_json(self):
        """Si el shim no desanidara el string, contenido_publicable no encontraría
        nada y el gate denegaría un payload perfectamente válido."""
        payload = self.call("mcp_atlassian_addCommentToJiraIssue", {"body": "Cierre STG. Pass rate 95%."})
        self.assertEqual(self.run_hook(self.HOOK, payload), "")


class AfterFileEdit(HookTestCase):
    HOOK = "check-after-edit.py"

    def test_no_bloquea_nunca(self):
        out = self.run_hook(self.HOOK, {"file_path": "README.md", "edits": []})
        self.assertEqual(out, "")

    def test_ignora_archivos_fuera_del_harness(self):
        self.run_hook(self.HOOK, {"file_path": "/etc/hosts", "edits": []})
        self.assertFalse(self.pending.exists())


class BaselineConfiguradoFueraDelHarness(HookTestCase):
    """El baseline configurado se valida esté donde esté; lo demás de afuera, no."""

    def setUp(self):
        super().setUp()
        dirs = [tempfile.TemporaryDirectory() for _ in range(2)]
        for temporal in dirs:
            self.addCleanup(temporal.cleanup)
        harness, afuera = (Path(d.name) for d in dirs)
        self.hook = copiar_harness(harness, "cursor") / "check-after-edit.py"
        self.baseline = afuera / "baseline.md"
        escribir_config(harness, {"enabled": True, "path": str(self.baseline)})

    def editar(self, path: Path) -> None:
        env = {**base_env(self.home), "QA_HARNESS_PENDING_CHECK": str(self.pending)}
        subprocess.run([sys.executable, str(self.hook)], input=json.dumps({"file_path": str(path), "edits": []}),
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


def _git(raiz: Path, *args: str) -> None:
    sin_ajeno = {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}
    subprocess.run(["git", "-C", str(raiz), *args], check=True, capture_output=True, env={**os.environ, **sin_ajeno})


def _escribir(ruta: Path, texto: str) -> None:
    """Escribe y adelanta el mtime: el diff no depende de la resolución del reloj."""
    ruta.write_text(texto, encoding="utf-8")
    futuro = time.time_ns() + 5_000_000_000
    os.utime(ruta, ns=(futuro, futuro))


class EscrituraPorShell(HookTestCase):
    """preToolUse + postToolUse (matcher "Shell"): lo que escribe la terminal.

    Contrato (docs de hooks de Cursor y el bundle cursor-agent-exec de 3.21.9):
      preToolUse          in {"tool_name":"Shell","tool_input","tool_use_id","conversation_id","cwd",...}
      postToolUse         in lo mismo + "tool_output"       out {"additional_context": str}
      postToolUseFailure  in lo mismo + "error_message"     out {"additional_context": str}
    """

    def setUp(self):
        super().setUp()
        proyecto = tempfile.TemporaryDirectory()
        self.addCleanup(proyecto.cleanup)
        self.raiz = Path(proyecto.name).resolve()
        _git(self.raiz, "init", "-q")
        self.tmp = self.home / "tmp"
        self.tmp.mkdir()
        self.fotos = self.tmp / "qa-harness-cursor"
        self.env = {**base_env(self.home), "QA_HARNESS_ROOT": str(self.raiz), "TMPDIR": str(self.tmp),
                    "QA_HARNESS_PENDING_CHECK": str(self.pending),
                    "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}

    def payload(self, evento: str, **extra) -> dict:
        datos = {"conversation_id": "c-1", "generation_id": "g-1", "hook_event_name": evento,
                 "tool_name": "Shell", "tool_input": {"command": "printf x > y"},
                 "tool_use_id": "call-1", "cwd": str(self.raiz)}
        if evento == "postToolUse":
            datos["tool_output"] = '{"exitCode":0,"stdout":""}'
        datos.update(extra)
        return {k: v for k, v in datos.items() if v is not None}

    def pre(self, **extra) -> str:
        return self.run_hook("snapshot-before-shell.py", self.payload("preToolUse", **extra), self.env)

    def post(self, evento: str = "postToolUse", **extra) -> str:
        return self.run_hook("check-after-shell.py", self.payload(evento, **extra), self.env)

    def test_json_invalido_escrito_por_la_terminal_vuelve_como_contexto(self):
        self.assertEqual(self.pre(), "")
        _escribir(self.raiz / "zz-prueba-cursor.json", '{"a": }')
        contexto = json.loads(self.post())["additional_context"]
        self.assertIn("YA QUEDO ESCRITO", contexto)
        self.assertIn("fallo JSON despues de editar zz-prueba-cursor.json", contexto)
        self.assertFalse(self.pending.exists(), "el aviso ya llegó: no hace falta la marca diferida")

    def test_un_comando_que_fallo_tambien_avisa(self):
        self.pre()
        _escribir(self.raiz / "roto.json", "{")
        self.assertIn("roto.json", json.loads(self.post("postToolUseFailure"))["additional_context"])

    def test_json_valido_no_dice_nada(self):
        self.pre()
        _escribir(self.raiz / "ok.json", "{}")
        self.assertEqual(self.post(), "")

    def test_lo_roto_de_antes_se_ignora(self):
        _escribir(self.raiz / "viejo.json", "{")
        self.pre()
        self.assertEqual(self.post(), "")

    def test_sin_foto_de_antes_se_abstiene(self):
        _escribir(self.raiz / "roto.json", "{")
        self.assertEqual(self.post(), "")

    def test_la_foto_es_de_esa_llamada_y_de_esa_conversacion(self):
        for otra in ({"tool_use_id": "call-otra"}, {"conversation_id": "c-otra"}):
            with self.subTest(otra=otra):
                self.pre(**otra)
                _escribir(self.raiz / "roto.json", "{")
                self.assertEqual(self.post(), "")
                (self.raiz / "roto.json").unlink()

    def test_sin_tool_use_id_no_hay_foto(self):
        self.pre(tool_use_id=None)
        self.assertFalse(self.fotos.exists() and any(self.fotos.iterdir()))

    def test_otra_herramienta_o_stdin_ilegible_es_silencio(self):
        self.assertEqual(self.pre(tool_name="Write"), "")
        self.assertFalse(self.fotos.exists() and any(self.fotos.iterdir()))
        self.assertEqual(self.post(tool_name="Write"), "")
        for script in ("snapshot-before-shell.py", "check-after-shell.py"):
            resultado = subprocess.run([sys.executable, str(HOOKS / script)], input="{no es json",
                                       text=True, capture_output=True, check=False, env=self.env)
            self.assertEqual((resultado.returncode, resultado.stdout.strip()), (0, ""))

    def test_la_foto_se_consume_y_vive_fuera_del_repo(self):
        self.pre()
        (foto,) = self.fotos.iterdir()
        self.assertNotIn(self.raiz, foto.parents)
        self.post()
        self.assertEqual(list(self.fotos.iterdir()), [])


class ConfiguracionDeCursor(unittest.TestCase):
    def test_el_par_del_shell_esta_enganchado_con_matcher_shell(self):
        hooks = json.loads((ROOT / "adapters" / "cursor" / "config" / "hooks.json").read_text(encoding="utf-8"))["hooks"]
        esperados = {
            "preToolUse": "snapshot-before-shell.py",
            "postToolUse": "check-after-shell.py",
            "postToolUseFailure": "check-after-shell.py",
        }
        for evento, script in esperados.items():
            with self.subTest(evento=evento):
                (entrada,) = hooks[evento]
                self.assertEqual(entrada["matcher"], "Shell")
                self.assertTrue(entrada["command"].endswith(f"/adapters/cursor/hooks/{script}"))
                self.assertTrue((HOOKS / script).is_file())


class AislamientoDelHome(HookTestCase):
    """Guardia de la suite: sin overrides, la marca pendiente cae bajo HOME. Con
    HOME en un sandbox, cae ahí y el ~/.cursor real queda intacto."""

    def test_la_marca_por_default_cae_en_el_home_del_sandbox(self):
        real = Path.home() / PENDING_DEFAULT
        before = fingerprint(real)

        with tempfile.TemporaryDirectory() as project:
            broken = Path(project) / "roto.json"
            broken.write_text('{"falta": }', encoding="utf-8")
            env = {**base_env(self.home), "QA_HARNESS_ROOT": project}

            # 1. afterFileEdit deja la marca tras una edicion que rompe el JSON
            self.run_hook("check-after-edit.py", {"file_path": str(broken), "edits": []}, env)
            self.assertTrue((self.home / PENDING_DEFAULT).is_file(), "la marca no cayó en el HOME del sandbox")
            # 2. beforeShellExecution la levanta y la consume desde el mismo HOME
            out = json.loads(self.run_hook("block-destructive-command.py", {"command": "npm test", "cwd": project}, env))
            self.assertEqual(out["permission"], "ask")

        written = [p for p in self.home.rglob("*") if p.is_file()]
        self.assertEqual(written, [], "la marca debía consumirse y no dejar nada más en HOME")
        self.assertEqual(fingerprint(real), before, "un hook escribió en el ~/.cursor real")


if __name__ == "__main__":
    unittest.main()
