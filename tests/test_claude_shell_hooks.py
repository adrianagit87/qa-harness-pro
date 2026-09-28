#!/usr/bin/env python3
"""Tests del gate post-edición sobre lo que escribe la terminal, en Claude Code.

Contrato (docs de hooks de Claude Code):
  PreToolUse          in  {"session_id","cwd","tool_name","tool_input","tool_use_id",...}
  PostToolUse         in  lo mismo + "tool_response"   out {"decision":"block","reason":...}
  PostToolUseFailure  in  lo mismo + "error"            out {"hookSpecificOutput":
                                                            {"hookEventName","additionalContext"}}
  (session_id, tool_use_id) une la foto del PreToolUse Bash con su post.

Cada hook corre en un proceso aparte con HOME y TMPDIR en un sandbox: nada de lo
que prueban toca el ~/.claude real ni el $TMPDIR de quien corre la suite.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness_temporal import BASELINE_ROTO, BASELINE_VALIDO, copiar_harness, escribir_config  # noqa: E402

HOOKS = RAIZ / "adapters" / "claude" / "hooks"
SETTINGS = RAIZ / ".claude" / "settings.json"
SIN_GIT_AJENO = {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1"}


def git(raiz: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-C", str(raiz), "-c", "user.name=QA", "-c", "user.email=qa@example.com",
         "-c", "commit.gpgsign=false", *args],
        check=True, capture_output=True, env={**os.environ, **SIN_GIT_AJENO},
    )


def escribir(ruta: Path, texto: str) -> None:
    """Escribe y adelanta el mtime: el diff no depende de la resolución del reloj."""
    ruta.write_text(texto, encoding="utf-8")
    futuro = time.time_ns() + 5_000_000_000
    os.utime(ruta, ns=(futuro, futuro))


class EscrituraPorShell(unittest.TestCase):
    """`printf '{"a": }' > x.json` por la terminal no pasaba por ningún gate en Claude Code."""

    def setUp(self) -> None:
        dirs = [tempfile.TemporaryDirectory() for _ in range(2)]
        for temporal in dirs:
            self.addCleanup(temporal.cleanup)
        self.raiz, self.home = (Path(d.name).resolve() for d in dirs)
        git(self.raiz, "init", "-q")
        self.tmp = self.home / "tmp"
        self.tmp.mkdir()
        self.fotos = self.tmp / "qa-harness-claude"
        self.hooks = HOOKS

    def correr(self, hook: str, entrada, **env: str) -> str:
        texto = entrada if isinstance(entrada, str) else json.dumps(entrada)
        base = {k: v for k, v in os.environ.items() if not k.startswith(("QA_HARNESS_", "CLAUDE_"))}
        base.update({"HOME": str(self.home), "TMPDIR": str(self.tmp), "CLAUDE_PROJECT_DIR": str(self.raiz),
                     **SIN_GIT_AJENO, **env})
        resultado = subprocess.run(
            [sys.executable, "-B", str(self.hooks / hook)],
            input=texto, text=True, capture_output=True, check=False, env=base,
        )
        self.assertEqual(resultado.returncode, 0, resultado.stderr)
        return resultado.stdout.strip()

    def payload(self, evento: str, **extra) -> dict:
        datos = {
            "session_id": "s-1", "cwd": str(self.raiz), "hook_event_name": evento,
            "permission_mode": "default", "tool_name": "Bash", "tool_use_id": "toolu_1",
            "tool_input": {"command": "printf x > y", "description": "", "run_in_background": False},
        }
        if evento == "PostToolUse":
            datos["tool_response"] = {"stdout": "", "stderr": "", "interrupted": False}
        if evento == "PostToolUseFailure":
            datos["error"] = "Exit code 1"
        datos.update(extra)
        return {k: v for k, v in datos.items() if v is not None}

    def pre(self, **extra) -> str:
        return self.correr("snapshot-before-shell.py", self.payload("PreToolUse", **extra))

    def post(self, evento: str = "PostToolUse", **extra) -> str:
        return self.correr("check-after-shell.py", self.payload(evento, **extra))

    def assertFrena(self, salida: str) -> str:
        self.assertTrue(salida, "esperaba un block y el hook no dijo nada")
        cuerpo = json.loads(salida)
        self.assertEqual(cuerpo["decision"], "block")
        return cuerpo["reason"]

    def test_json_invalido_escrito_por_la_terminal_frena(self) -> None:
        self.assertEqual(self.pre(), "")
        escribir(self.raiz / "zz-prueba-claude.json", '{"a": }')
        motivo = self.assertFrena(self.post())
        self.assertIn("YA QUEDÓ ESCRITO", motivo)
        self.assertIn("falló JSON después de editar zz-prueba-claude.json", motivo)

    def test_un_comando_que_falla_igual_avisa_lo_que_escribio(self) -> None:
        """Exit != 0 dispara PostToolUseFailure: no hay block, va como contexto."""
        self.pre()
        escribir(self.raiz / "roto.json", "{")
        cuerpo = json.loads(self.post("PostToolUseFailure"))["hookSpecificOutput"]
        self.assertEqual(cuerpo["hookEventName"], "PostToolUseFailure")
        self.assertIn("falló JSON después de editar roto.json", cuerpo["additionalContext"])

    def test_json_valido_no_dice_nada(self) -> None:
        self.pre()
        escribir(self.raiz / "ok.json", '{"a": 1}')
        self.assertEqual(self.post(), "")

    def test_un_trackeado_modificado_por_la_terminal_frena(self) -> None:
        escribir(self.raiz / "config.json", "{}")
        git(self.raiz, "add", ".")
        git(self.raiz, "commit", "-qm", "base")
        self.pre()
        escribir(self.raiz / "config.json", "{roto")
        self.assertIn("config.json", self.assertFrena(self.post()))

    def test_python_roto_frena_sin_correr_la_suite(self) -> None:
        self.pre()
        escribir(self.raiz / "roto.py", "def f(:\n")
        self.assertIn("Python inválido", self.assertFrena(self.post()))

    def test_lo_roto_de_antes_que_el_comando_no_toco_se_ignora(self) -> None:
        escribir(self.raiz / "viejo.json", "{")
        self.pre()
        escribir(self.raiz / "nuevo.json", "{}")
        self.assertEqual(self.post(), "")

    def test_fuera_de_la_raiz_se_ignora(self) -> None:
        self.pre()
        escribir(self.home / "afuera.json", "{")
        self.assertEqual(self.post(), "")

    def test_sin_foto_de_antes_es_silencio_no_block(self) -> None:
        """A diferencia de check-after-edit: sin un antes confiable, 'no escribió nada' y
        'no sé qué escribió' no se distinguen, y frenar pararía cada `ls` de la sesión."""
        escribir(self.raiz / "roto.json", "{")
        self.assertEqual(self.post(), "")
        self.assertEqual(self.post("PostToolUseFailure"), "")

    def test_una_raiz_que_no_es_git_es_silencio(self) -> None:
        shutil.rmtree(self.raiz / ".git")
        self.assertEqual(self.pre(), "")
        escribir(self.raiz / "roto.json", "{")
        self.assertEqual(self.post(), "")

    def test_la_foto_es_de_esa_llamada_y_de_esa_sesion(self) -> None:
        for otra in ({"tool_use_id": "toolu_otra"}, {"session_id": "s-otra"}):
            with self.subTest(otra=otra):
                self.pre(**otra)
                escribir(self.raiz / "roto.json", "{")
                self.assertEqual(self.post(), "")
                (self.raiz / "roto.json").unlink()

    def test_sin_tool_use_id_no_hay_foto_y_se_abstiene(self) -> None:
        self.pre(tool_use_id=None)
        self.assertFalse(self.fotos.exists() and any(self.fotos.iterdir()))
        escribir(self.raiz / "roto.json", "{")
        self.assertEqual(self.post(tool_use_id=None), "")

    def test_la_foto_se_consume_y_vive_fuera_del_repo(self) -> None:
        self.pre()
        fotos = list(self.fotos.iterdir())
        self.assertEqual(len(fotos), 1)
        self.assertFalse(any(self.raiz in f.parents for f in fotos))
        self.post()
        self.assertEqual(list(self.fotos.iterdir()), [])

    def test_sin_claude_project_dir_usa_el_cwd(self) -> None:
        self.assertEqual(self.pre(), "")
        escribir(self.raiz / "roto.json", "{")
        self.assertFrena(self.correr("check-after-shell.py", self.payload("PostToolUse"), CLAUDE_PROJECT_DIR=""))

    def test_el_pre_nunca_dice_nada(self) -> None:
        """No es un gate: el deny de lo destructivo es de block-destructive-command.py."""
        for entrada in ("{no es json", json.dumps(self.payload("PreToolUse", tool_input={"command": "rm -rf /"}))):
            with self.subTest(entrada=entrada[:20]):
                self.assertEqual(self.correr("snapshot-before-shell.py", entrada), "")

    def test_el_post_con_stdin_ilegible_falla_cerrado(self) -> None:
        for crudo in ("[]", "no es json"):
            with self.subTest(crudo=crudo):
                self.assertIn("no pude verificar", self.assertFrena(self.correr("check-after-shell.py", crudo)))

    def test_otra_herramienta_en_el_post_es_config_rota(self) -> None:
        """Mismo criterio que los otros hooks de Claude: el matcher es "Bash"."""
        motivo = self.assertFrena(self.post(tool_name="Edit"))
        self.assertIn("herramienta inesperada", motivo)
        self.assertEqual(self.pre(tool_name="Edit"), "")


class BaselineEscritoPorShell(unittest.TestCase):
    """El baseline configurado fuera de la raíz también se ve si lo escribe la terminal."""

    def setUp(self) -> None:
        dirs = [tempfile.TemporaryDirectory() for _ in range(4)]
        for temporal in dirs:
            self.addCleanup(temporal.cleanup)
        harness, afuera, self.proyecto, self.home = (Path(d.name).resolve() for d in dirs)
        self.hooks = copiar_harness(harness, "claude")
        git(self.proyecto, "init", "-q")
        self.baseline = afuera / "baseline.md"
        escribir_config(harness, {"enabled": True, "path": str(self.baseline)})

    def comando(self, texto: str) -> str:
        env = {k: v for k, v in os.environ.items() if not k.startswith(("QA_HARNESS_", "CLAUDE_"))}
        env.update(HOME=str(self.home), TMPDIR=str(self.home), CLAUDE_PROJECT_DIR=str(self.proyecto),
                   **SIN_GIT_AJENO)
        salidas = []
        for hook, evento in (("snapshot-before-shell.py", "PreToolUse"), ("check-after-shell.py", "PostToolUse")):
            if evento == "PostToolUse":
                escribir(self.baseline, texto)
            entrada = {"session_id": "s", "tool_use_id": "u", "hook_event_name": evento,
                       "tool_name": "Bash", "tool_input": {"command": "cat > baseline.md"}}
            resultado = subprocess.run([sys.executable, "-B", str(self.hooks / hook)], input=json.dumps(entrada),
                                       text=True, capture_output=True, check=False, env=env)
            self.assertEqual(resultado.returncode, 0, resultado.stderr)
            salidas.append(resultado.stdout.strip())
        self.assertEqual(salidas[0], "")
        return salidas[1]

    def test_el_baseline_roto_frena(self) -> None:
        self.assertIn("baseline inválido", json.loads(self.comando(BASELINE_ROTO))["reason"])

    def test_el_baseline_valido_no_dice_nada(self) -> None:
        self.assertEqual(self.comando(BASELINE_VALIDO), "")


class ConfiguracionDeClaude(unittest.TestCase):
    """.claude/settings.json engancha el par: sin la foto, el check se abstiene siempre."""

    def setUp(self) -> None:
        self.hooks = json.loads(SETTINGS.read_text(encoding="utf-8"))["hooks"]

    def grupos(self, evento: str) -> list[tuple[str, str]]:
        return [
            (grupo["matcher"], Path(hook["args"][-1]).name)
            for grupo in self.hooks.get(evento, [])
            for hook in grupo["hooks"]
        ]

    def test_la_foto_va_antes_de_cada_bash(self) -> None:
        self.assertIn(("Bash", "snapshot-before-shell.py"), self.grupos("PreToolUse"))

    def test_el_check_va_despues_de_cada_bash_haya_fallado_o_no(self) -> None:
        for evento in ("PostToolUse", "PostToolUseFailure"):
            with self.subTest(evento=evento):
                self.assertIn(("Bash", "check-after-shell.py"), self.grupos(evento))

    def test_los_gates_de_antes_siguen_en_su_lugar(self) -> None:
        self.assertEqual(self.grupos("PreToolUse")[0], ("Bash", "block-destructive-command.py"))
        self.assertIn(("Edit|Write", "check-after-edit.py"), self.grupos("PostToolUse"))

    def test_cada_script_enganchado_existe(self) -> None:
        for grupos in self.hooks.values():
            for grupo in grupos:
                for hook in grupo["hooks"]:
                    with self.subTest(script=hook["args"][-1]):
                        self.assertTrue((HOOKS / Path(hook["args"][-1]).name).is_file())


if __name__ == "__main__":
    unittest.main(verbosity=2)
