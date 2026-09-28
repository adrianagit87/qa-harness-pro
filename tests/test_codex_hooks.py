"""Unit tests del adaptador de Codex CLI.

El contrato sale de las docs oficiales y de los esquemas JSON embebidos en el
binario de codex-cli 0.155.1:

  PreToolUse   in  {"tool_name","tool_input","cwd",...}
               out {"hookSpecificOutput":{"hookEventName":"PreToolUse",
                    "permissionDecision":"deny","permissionDecisionReason":...}}
               -- "ask" y "allow" no estan soportados; solo deny, con motivo
  PostToolUse  out {"decision":"block","reason":...}
  Bash y apply_patch traen el texto en tool_input.command (el patch entero).
  session_id y tool_use_id son obligatorios en pre y post (esquemas de 0.157.1):
  unen la foto del PreToolUse Bash con su PostToolUse.

Cada hook corre en un proceso aparte con HOME en un sandbox: nada de lo que
prueban toca el ~/.codex real de quien corre la suite.
"""

from __future__ import annotations

import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import tomllib
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
TESTS = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS))
sys.path.insert(0, str(ROOT))
from harness_temporal import BASELINE_ROTO, BASELINE_VALIDO, copiar_harness, escribir_config  # noqa: E402

from core.gates import catalogo  # noqa: E402

ADAPTADOR = ROOT / "adapters" / "codex"
HOOKS = ADAPTADOR / "hooks"
sys.path.insert(0, str(HOOKS))
sys.path.insert(0, str(ADAPTADOR))
import _codex  # noqa: E402
import bloque_gestionado  # noqa: E402


def entorno(home: Path, **extra: str) -> dict:
    """Entorno heredado, con HOME en el sandbox y sin rutas QA_HARNESS_*/CODEX_* de afuera."""
    env = {k: v for k, v in os.environ.items() if not k.startswith(("QA_HARNESS_", "CODEX_"))}
    env["HOME"] = str(home)
    env.update(extra)
    return env


class HookTestCase(unittest.TestCase):
    HOOK = ""

    def setUp(self):
        sandbox = tempfile.TemporaryDirectory()
        self.addCleanup(sandbox.cleanup)
        self.home = Path(sandbox.name)

    def correr(self, entrada, hook: Path | None = None, **env: str) -> str:
        texto = entrada if isinstance(entrada, str) else json.dumps(entrada)
        resultado = subprocess.run(
            [sys.executable, str(hook or HOOKS / self.HOOK)],
            input=texto, text=True, capture_output=True, check=False, env=entorno(self.home, **env),
        )
        self.assertEqual(resultado.returncode, 0, resultado.stderr)
        return resultado.stdout.strip()

    def assertDeniega(self, salida: str) -> str:
        self.assertTrue(salida, "esperaba un deny y el hook no dijo nada")
        especifico = json.loads(salida)["hookSpecificOutput"]
        self.assertEqual(especifico["hookEventName"], "PreToolUse")
        self.assertEqual(especifico["permissionDecision"], "deny")
        # Codex rechaza un deny sin motivo: "permissionDecision:deny without a
        # non-empty permissionDecisionReason".
        self.assertTrue(especifico["permissionDecisionReason"].strip())
        return especifico["permissionDecisionReason"]

    def assertFrena(self, salida: str) -> str:
        self.assertTrue(salida, "esperaba un block y el hook no dijo nada")
        cuerpo = json.loads(salida)
        self.assertEqual(cuerpo["decision"], "block")
        self.assertTrue(cuerpo["reason"].strip())
        return cuerpo["reason"]


def llamada(tool: str, tool_input, evento: str = "PreToolUse", cwd: str = "/tmp") -> dict:
    return {
        "session_id": "s-1", "turn_id": "t-1", "cwd": cwd, "hook_event_name": evento,
        "model": "gpt-test", "permission_mode": "default", "tool_name": tool,
        "tool_input": tool_input, "tool_use_id": "u-1", "transcript_path": None,
    }


# ── PreToolUse Bash ─────────────────────────────────────────────────
class ComandoDestructivo(HookTestCase):
    HOOK = "block-destructive-command.py"

    def test_deniega_rm_recursivo_forzado(self):
        motivo = self.assertDeniega(self.correr(llamada("Bash", {"command": "rm -rf build/"})))
        self.assertIn("rm recursivo y forzado", motivo)

    def test_deniega_push_forzado(self):
        self.assertDeniega(self.correr(llamada("Bash", {"command": "git push origin main --force"})))

    def test_deniega_reset_hard_dentro_de_una_cadena(self):
        self.assertDeniega(self.correr(llamada("Bash", {"command": "cd repo && git reset --hard HEAD~1"})))

    def test_deja_pasar_un_comando_inocuo(self):
        self.assertEqual(self.correr(llamada("Bash", {"command": "python3 -m unittest"})), "")

    def test_acepta_el_comando_como_argv(self):
        """Si una version de Codex mandara argv en vez de texto, el gate no se ciega."""
        self.assertDeniega(self.correr(llamada("Bash", {"command": ["bash", "-lc", "rm -rf /"]})))

    def test_bash_sin_comando_falla_cerrado(self):
        self.assertDeniega(self.correr(llamada("Bash", {})))

    def test_otra_herramienta_se_abstiene_en_silencio(self):
        self.assertEqual(self.correr(llamada("mcp__otro__run", {"command": "rm -rf /"})), "")

    def test_stdin_ilegible_falla_cerrado(self):
        """El matcher "Bash" garantiza que es shell: si no se puede leer, no se descarta que sea destructivo."""
        self.assertIn("entrada inválida", self.assertDeniega(self.correr("{no es json")))


# ── Lectura del patch ───────────────────────────────────────────────
class ArchivosDelPatch(unittest.TestCase):
    def test_update_y_add(self):
        patch = (
            "*** Begin Patch\n"
            "*** Update File: core/a.py\n@@\n-x\n+y\n"
            "*** Add File: docs/nuevo.md\n+# hola\n"
            "*** End Patch\n"
        )
        self.assertEqual(_codex.archivos_del_patch(patch), ["core/a.py", "docs/nuevo.md"])

    def test_delete_no_deja_nada_que_revisar(self):
        patch = "*** Begin Patch\n*** Delete File: viejo.py\n*** End Patch\n"
        self.assertEqual(_codex.archivos_del_patch(patch), [])
        self.assertTrue(_codex.es_patch(patch))

    def test_move_revisa_el_destino_y_no_el_origen(self):
        patch = (
            "*** Begin Patch\n"
            "*** Update File: src/viejo.py\n*** Move to: src/nuevo.py\n@@\n-a\n+b\n"
            "*** End Patch\n"
        )
        self.assertEqual(_codex.archivos_del_patch(patch), ["src/nuevo.py"])

    def test_varios_archivos_en_orden_y_sin_repetidos(self):
        patch = (
            "*** Begin Patch\n"
            "*** Update File: a.json\n@@\n-1\n+2\n"
            "*** Delete File: b.py\n"
            "*** Update File: c.sh\n*** Move to: d.sh\n"
            "*** Add File: e.py\n+x = 1\n"
            "*** Update File: a.json\n@@\n-2\n+3\n"
            "*** End Patch\n"
        )
        self.assertEqual(_codex.archivos_del_patch(patch), ["a.json", "d.sh", "e.py"])

    def test_tolera_heredoc_sangria_y_crlf(self):
        patch = "apply_patch <<'EOF'\r\n*** Begin Patch\r\n  *** Update File: con espacios/x.py  \r\n@@\r\n*** End Patch\r\nEOF\r\n"
        self.assertEqual(_codex.archivos_del_patch(patch), ["con espacios/x.py"])

    def test_una_linea_de_contenido_que_cita_un_encabezado_no_se_confunde(self):
        """Dentro del patch, el contenido va prefijado con +, - o espacio."""
        patch = "*** Begin Patch\n*** Add File: notas.md\n+*** Update File: trampa.py\n*** End Patch\n"
        self.assertEqual(_codex.archivos_del_patch(patch), ["notas.md"])

    def test_texto_sin_encabezados(self):
        self.assertEqual(_codex.archivos_del_patch("hola"), [])
        self.assertFalse(_codex.es_patch("hola"))


# ── PostToolUse apply_patch ─────────────────────────────────────────
class PostEdicion(HookTestCase):
    HOOK = "check-after-edit.py"

    def setUp(self):
        super().setUp()
        proyecto = tempfile.TemporaryDirectory()
        self.addCleanup(proyecto.cleanup)
        self.raiz = Path(proyecto.name).resolve()

    def editar(self, patch: str, cwd: Path | None = None, tool: str = "apply_patch") -> str:
        payload = llamada(tool, {"command": patch}, "PostToolUse", str(cwd or self.raiz))
        payload["tool_response"] = {"output": "Success"}
        return self.correr(payload, QA_HARNESS_ROOT=str(self.raiz))

    def test_python_roto_frena_con_feedback(self):
        (self.raiz / "roto.py").write_text("def x(:\n", encoding="utf-8")
        motivo = self.assertFrena(self.editar("*** Begin Patch\n*** Add File: roto.py\n+def x(:\n*** End Patch"))
        self.assertIn("Python inválido en roto.py", motivo)

    def test_el_feedback_dice_que_el_archivo_ya_quedo_escrito(self):
        """El block no deshace nada: el modelo no tiene que creer que la edición se rechazó."""
        (self.raiz / "roto.json").write_text("{", encoding="utf-8")
        motivo = self.assertFrena(self.editar("*** Begin Patch\n*** Update File: roto.json\n*** End Patch"))
        self.assertTrue(motivo.startswith("Quality gate post-edit: el cambio YA QUEDÓ ESCRITO en disco"), motivo)
        self.assertIn("no lo deshizo ni lo rechazó", motivo)
        self.assertIn("falló JSON después de editar roto.json", motivo)

    def test_un_detalle_enorme_se_recorta_sin_perder_el_aviso(self):
        with mock.patch.object(sys, "stdout", new_callable=io.StringIO) as salida:
            _codex.frenar_ya_escrito(["x" * 10000])
        motivo = json.loads(salida.getvalue())["reason"]
        self.assertLessEqual(len(motivo), _codex.MAX_FEEDBACK)
        self.assertTrue(motivo.startswith(_codex.AVISO_YA_ESCRITO))

    def test_json_roto_frena(self):
        (self.raiz / "config.json").write_text('{"a": }', encoding="utf-8")
        motivo = self.assertFrena(self.editar("*** Begin Patch\n*** Update File: config.json\n*** End Patch"))
        self.assertIn("JSON", motivo)

    def test_revisa_todos_los_archivos_del_patch(self):
        """El roto va segundo: si solo se mirara el primero, pasaria."""
        (self.raiz / "sano.json").write_text('{"a": 1}', encoding="utf-8")
        (self.raiz / "roto.json").write_text("{", encoding="utf-8")
        motivo = self.assertFrena(self.editar(
            "*** Begin Patch\n*** Update File: sano.json\n*** Update File: roto.json\n*** End Patch"
        ))
        self.assertIn("roto.json", motivo)
        self.assertNotIn("sano.json", motivo)

    def test_move_revisa_el_archivo_movido(self):
        (self.raiz / "nuevo.json").write_text("[", encoding="utf-8")
        self.assertFrena(self.editar(
            "*** Begin Patch\n*** Update File: viejo.json\n*** Move to: nuevo.json\n*** End Patch"
        ))

    def test_archivos_sanos_no_dicen_nada(self):
        (self.raiz / "ok.json").write_text('{"ok": true}', encoding="utf-8")
        self.assertEqual(self.editar("*** Begin Patch\n*** Update File: ok.json\n*** End Patch"), "")

    def test_ruta_absoluta_tambien_se_revisa(self):
        roto = self.raiz / "abs.json"
        roto.write_text("nope", encoding="utf-8")
        self.assertFrena(self.editar(f"*** Begin Patch\n*** Update File: {roto}\n*** End Patch", cwd=self.home))

    def test_la_ruta_relativa_se_resuelve_contra_el_cwd_de_la_sesion(self):
        sub = self.raiz / "sub"
        sub.mkdir()
        (sub / "x.json").write_text("{", encoding="utf-8")
        self.assertFrena(self.editar("*** Begin Patch\n*** Update File: x.json\n*** End Patch", cwd=sub))

    def test_fuera_de_la_raiz_se_abstiene_en_silencio(self):
        afuera = self.home / "otro.json"
        afuera.write_text("{", encoding="utf-8")
        self.assertEqual(self.editar(f"*** Begin Patch\n*** Update File: {afuera}\n*** End Patch"), "")

    def test_patch_que_solo_borra_no_dice_nada(self):
        self.assertEqual(self.editar("*** Begin Patch\n*** Delete File: x.py\n*** End Patch"), "")

    def test_patch_sin_encabezados_falla_cerrado(self):
        self.assertIn("no pude verificar", self.assertFrena(self.editar("esto no es un patch")))

    def test_otra_herramienta_se_abstiene(self):
        payload = llamada("Bash", {"command": "echo hola"}, "PostToolUse")
        self.assertEqual(self.correr(payload, QA_HARNESS_ROOT=str(self.raiz)), "")

    def test_stdin_ilegible_falla_cerrado(self):
        self.assertIn("entrada inválida", self.assertFrena(self.correr("[]")))


class BaselineConfiguradoFueraDelHarness(HookTestCase):
    """El baseline configurado se valida esté donde esté; lo demás de afuera, no."""

    def setUp(self):
        super().setUp()
        dirs = [tempfile.TemporaryDirectory() for _ in range(2)]
        for temporal in dirs:
            self.addCleanup(temporal.cleanup)
        harness, afuera = (Path(d.name).resolve() for d in dirs)
        self.hook = copiar_harness(harness, "codex") / "check-after-edit.py"
        self.afuera = afuera
        self.baseline = afuera / "baseline.md"
        escribir_config(harness, {"enabled": True, "path": str(self.baseline)})

    def editar(self, ruta: str) -> str:
        payload = llamada("apply_patch", {"command": f"*** Begin Patch\n*** Update File: {ruta}\n*** End Patch"},
                          "PostToolUse", str(self.afuera))
        return self.correr(payload, hook=self.hook)

    def test_el_baseline_roto_frena(self):
        self.baseline.write_text(BASELINE_ROTO, encoding="utf-8")
        self.assertIn("baseline inválido", self.assertFrena(self.editar(str(self.baseline))))

    def test_el_baseline_roto_con_ruta_relativa_al_cwd_frena(self):
        self.baseline.write_text(BASELINE_ROTO, encoding="utf-8")
        self.assertFrena(self.editar("baseline.md"))

    def test_el_baseline_valido_no_dice_nada(self):
        self.baseline.write_text(BASELINE_VALIDO, encoding="utf-8")
        self.assertEqual(self.editar(str(self.baseline)), "")

    def test_otro_markdown_de_afuera_sigue_ignorado(self):
        ajeno = self.afuera / "otro.md"
        ajeno.write_text(BASELINE_ROTO, encoding="utf-8")
        self.assertEqual(self.editar(str(ajeno)), "")


# ── PreToolUse + PostToolUse Bash: lo que escribe la terminal ───────
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


class EscrituraPorShell(HookTestCase):
    """El gap de 0.157.1: `printf '%s' '{"a": }' > x.json` por la terminal no pasaba por ningún gate."""

    PRE = HOOKS / "snapshot-before-shell.py"
    POST = HOOKS / "check-after-shell.py"

    def setUp(self):
        super().setUp()
        proyecto = tempfile.TemporaryDirectory()
        self.addCleanup(proyecto.cleanup)
        self.raiz = Path(proyecto.name).resolve()
        git(self.raiz, "init", "-q")
        self.tmp = self.home / "tmp"
        self.tmp.mkdir()
        self.fotos = self.tmp / _codex.CARPETA_DE_FOTOS
        self.env = {"QA_HARNESS_ROOT": str(self.raiz), "TMPDIR": str(self.tmp), **SIN_GIT_AJENO}

    def payload(self, evento: str, comando="printf x > y", **extra) -> dict:
        datos = llamada("Bash", {"command": comando}, evento, str(self.raiz))
        if evento == "PostToolUse":
            datos["tool_response"] = {"output": "", "exit_code": 0}
        datos.update(extra)
        return datos

    def pre(self, **extra) -> str:
        return self.correr(self.payload("PreToolUse", **extra), hook=self.PRE, **self.env)

    def post(self, **extra) -> str:
        return self.correr(self.payload("PostToolUse", **extra), hook=self.POST, **self.env)

    def test_json_invalido_escrito_por_la_terminal_frena(self):
        self.assertEqual(self.pre(), "")
        escribir(self.raiz / "zz-prueba-codex.json", '{"a": }')
        motivo = self.assertFrena(self.post())
        self.assertIn("YA QUEDÓ ESCRITO", motivo)
        self.assertIn("falló JSON después de editar zz-prueba-codex.json", motivo)

    def test_json_valido_no_dice_nada(self):
        self.pre()
        escribir(self.raiz / "ok.json", '{"a": 1}')
        self.assertEqual(self.post(), "")

    def test_un_trackeado_modificado_por_la_terminal_frena(self):
        escribir(self.raiz / "config.json", "{}")
        git(self.raiz, "add", ".")
        git(self.raiz, "commit", "-qm", "base")
        self.pre()
        escribir(self.raiz / "config.json", "{roto")
        self.assertIn("config.json", self.assertFrena(self.post()))

    def test_lo_roto_de_antes_que_el_comando_no_toco_se_ignora(self):
        escribir(self.raiz / "viejo.json", "{")
        self.pre()
        escribir(self.raiz / "nuevo.json", "{}")
        self.assertEqual(self.post(), "")

    def test_un_archivo_borrado_no_deja_nada_que_revisar(self):
        escribir(self.raiz / "roto.json", "{")
        self.pre()
        (self.raiz / "roto.json").unlink()
        self.assertEqual(self.post(), "")

    def test_fuera_de_la_raiz_se_ignora(self):
        self.pre()
        escribir(self.home / "afuera.json", "{")
        self.assertEqual(self.post(), "")

    def test_sin_foto_de_antes_se_abstiene(self):
        """El pre no corrió (hook sin aprobar, por ejemplo): nunca se valida el repo entero."""
        escribir(self.raiz / "roto.json", "{")
        self.assertEqual(self.post(), "")

    def test_una_raiz_que_no_es_git_se_abstiene(self):
        shutil.rmtree(self.raiz / ".git")
        self.assertEqual(self.pre(), "")
        escribir(self.raiz / "roto.json", "{")
        self.assertEqual(self.post(), "")

    def test_la_foto_es_de_esa_llamada(self):
        self.pre(tool_use_id="u-otra")
        escribir(self.raiz / "roto.json", "{")
        self.assertEqual(self.post(tool_use_id="u-1"), "")

    def test_la_foto_es_de_esa_sesion(self):
        self.pre(session_id="s-otra")
        escribir(self.raiz / "roto.json", "{")
        self.assertEqual(self.post(session_id="s-1"), "")

    def test_la_foto_se_consume_y_vive_fuera_del_repo(self):
        self.pre()
        fotos = list(self.fotos.iterdir())
        self.assertEqual(len(fotos), 1)
        self.assertFalse(any(self.raiz in f.parents for f in fotos))
        self.post()
        self.assertEqual(list(self.fotos.iterdir()), [])

    def test_el_pre_barre_fotos_huerfanas_viejas(self):
        self.pre(tool_use_id="u-huerfana")
        (huerfana,) = self.fotos.iterdir()
        hace_un_dia = time.time() - 24 * 3600
        os.utime(huerfana, (hace_un_dia, hace_un_dia))
        self.pre(tool_use_id="u-nueva")
        self.assertFalse(huerfana.exists())
        self.assertEqual(len(list(self.fotos.iterdir())), 1)

    def test_sin_tool_use_id_se_abstiene(self):
        self.pre(tool_use_id=None)
        self.assertFalse(self.fotos.exists() and any(self.fotos.iterdir()))
        escribir(self.raiz / "roto.json", "{")
        self.assertEqual(self.post(tool_use_id=None), "")

    def test_el_comando_como_argv_tambien_se_sigue(self):
        self.pre(tool_input={"command": ["bash", "-lc", "printf x > y"]})
        escribir(self.raiz / "roto.json", "{")
        self.assertFrena(self.post(tool_input={"command": ["bash", "-lc", "printf x > y"]}))

    def test_el_pre_nunca_dice_nada(self):
        """No es un gate: el deny de lo destructivo es de block-destructive-command.py."""
        for entrada in ("{no es json", json.dumps(self.payload("PreToolUse", "rm -rf /"))):
            with self.subTest(entrada=entrada[:20]):
                self.assertEqual(self.correr(entrada, hook=self.PRE, **self.env), "")

    def test_el_post_con_stdin_ilegible_falla_cerrado(self):
        self.assertIn("no pude verificar", self.assertFrena(self.correr("[]", hook=self.POST, **self.env)))

    def test_otra_herramienta_se_abstiene(self):
        for hook, evento in ((self.PRE, "PreToolUse"), (self.POST, "PostToolUse")):
            with self.subTest(hook=hook.name):
                entrada = llamada("apply_patch", {"command": "*** Begin Patch"}, evento, str(self.raiz))
                self.assertEqual(self.correr(entrada, hook=hook, **self.env), "")
        self.assertFalse(self.fotos.exists() and any(self.fotos.iterdir()))


class BaselineEscritoPorShell(HookTestCase):
    """El baseline configurado fuera de la raíz también se ve si lo escribe la terminal."""

    def setUp(self):
        super().setUp()
        dirs = [tempfile.TemporaryDirectory() for _ in range(3)]
        for temporal in dirs:
            self.addCleanup(temporal.cleanup)
        harness, afuera, proyecto = (Path(d.name).resolve() for d in dirs)
        self.hooks = copiar_harness(harness, "codex")
        git(proyecto, "init", "-q")
        self.baseline = afuera / "baseline.md"
        escribir_config(harness, {"enabled": True, "path": str(self.baseline)})
        tmp = self.home / "tmp"
        tmp.mkdir()
        self.env = {"QA_HARNESS_ROOT": str(proyecto), "TMPDIR": str(tmp), **SIN_GIT_AJENO}
        self.cwd = str(proyecto)

    def comando(self, texto: str) -> str:
        pre = llamada("Bash", {"command": "cat > baseline.md"}, "PreToolUse", self.cwd)
        self.assertEqual(self.correr(pre, hook=self.hooks / "snapshot-before-shell.py", **self.env), "")
        escribir(self.baseline, texto)
        post = llamada("Bash", {"command": "cat > baseline.md"}, "PostToolUse", self.cwd)
        post["tool_response"] = {"output": ""}
        return self.correr(post, hook=self.hooks / "check-after-shell.py", **self.env)

    def test_el_baseline_roto_frena(self):
        self.assertIn("baseline inválido", self.assertFrena(self.comando(BASELINE_ROTO)))

    def test_el_baseline_valido_no_dice_nada(self):
        self.assertEqual(self.comando(BASELINE_VALIDO), "")


# ── PreToolUse mcp__.* ──────────────────────────────────────────────
class PublicacionExterna(HookTestCase):
    HOOK = "validate-external-write.py"

    def test_deniega_la_transicion_siempre(self):
        motivo = self.assertDeniega(self.correr(llamada(
            "mcp__atlassian__transitionJiraIssue", {"issueIdOrKey": "US-1", "transition": {"id": "31"}}
        )))
        self.assertIn("estado de un ticket", motivo)

    def test_deniega_un_comentario_con_placeholder(self):
        motivo = self.assertDeniega(self.correr(llamada(
            "mcp__atlassian__addCommentToJiraIssue",
            {"cloudId": "x", "issueIdOrKey": "US-1", "commentBody": "Cierre DEV. Evidencia: PON-AQUI-EL-LINK"},
        )))
        self.assertIn("placeholder", motivo)

    def test_deniega_una_escritura_sin_contenido(self):
        self.assertDeniega(self.correr(llamada("mcp__atlassian__createJiraIssue", {"projectKey": "QA"})))

    def test_contenido_limpio_pasa_a_la_aprobacion_de_codex(self):
        """Codex no soporta "ask" en PreToolUse: la confirmacion la pone approval_mode = "prompt"."""
        self.assertEqual(self.correr(llamada(
            "mcp__atlassian__addCommentToJiraIssue", {"issueIdOrKey": "US-1", "commentBody": "Cierre DEV: 12/12 Pass."}
        )), "")

    def test_la_lectura_se_abstiene(self):
        self.assertEqual(self.correr(llamada("mcp__atlassian__getJiraIssue", {"issueIdOrKey": "US-1"})), "")

    def test_otra_herramienta_mcp_se_abstiene(self):
        self.assertEqual(self.correr(llamada("mcp__playwright__browser_close", {})), "")

    def test_tool_input_serializado_se_desanida(self):
        entrada = json.dumps({"commentBody": "YOUR_TOKEN"})
        self.assertDeniega(self.correr(llamada("mcp__atlassian__addCommentToJiraIssue", entrada)))

    def test_stdin_ilegible_falla_cerrado(self):
        self.assertDeniega(self.correr(""))


# ── Configuración del adaptador contra el catálogo ─────────────────
class ConfiguracionContraElCatalogo(unittest.TestCase):
    def setUp(self):
        self.mcp = tomllib.loads((ADAPTADOR / "config" / "mcp.toml").read_text(encoding="utf-8"))
        self.atlassian = self.mcp["mcp_servers"]["atlassian"]

    @staticmethod
    def de_atlassian(ids):
        prefijo = "mcp__atlassian__"
        return {i[len(prefijo):] for i in ids if i.startswith(prefijo)}

    def test_cada_escritura_de_atlassian_pide_aprobacion_siempre(self):
        tools = self.atlassian.get("tools", {})
        for tool in self.de_atlassian(catalogo.IDS_PUBLICACION):
            with self.subTest(tool=tool):
                self.assertEqual(tools.get(tool, {}).get("approval_mode"), "prompt")

    def test_la_transicion_queda_fuera_de_la_lista_de_tools(self):
        self.assertEqual(set(self.atlassian["disabled_tools"]), self.de_atlassian(catalogo.IDS_TRANSICION))

    def test_el_server_es_el_oficial(self):
        self.assertEqual(self.atlassian["url"], "https://mcp.atlassian.com/v1/mcp/authv2")

    def test_los_nombres_de_codex_se_reconocen_en_el_catalogo(self):
        """Codex nombra las tools MCP mcp__<server>__<tool>: el mismo id canónico de Claude Code."""
        for identificador in catalogo.IDS_PUBLICACION + catalogo.IDS_TRANSICION:
            with self.subTest(id=identificador):
                self.assertEqual(catalogo.canonico(identificador), identificador)

    def test_los_hooks_del_template_existen_y_tienen_su_matcher(self):
        """En orden: la confianza de /hooks va por posición, y lo nuevo va siempre al final."""
        hooks = json.loads((ADAPTADOR / "config" / "hooks.json").read_text(encoding="utf-8"))["hooks"]
        esperados = {
            "PreToolUse": [
                ("Bash", "block-destructive-command.py", 15),
                ("mcp__.*", "validate-external-write.py", 15),
                ("Bash", "snapshot-before-shell.py", 15),
            ],
            "PostToolUse": [
                ("apply_patch|Edit|Write", "check-after-edit.py", 120),
                ("Bash", "check-after-shell.py", 120),
            ],
        }
        encontrados = {
            evento: [(grupo["matcher"], hook["command"].rsplit("/", 1)[-1], hook["timeout"])
                     for grupo in grupos for hook in grupo["hooks"]]
            for evento, grupos in hooks.items()
        }
        self.assertEqual(encontrados, esperados)
        for grupos in esperados.values():
            for _, script, _ in grupos:
                self.assertTrue((HOOKS / script).is_file(), script)


# ── Bloque gestionado (config.toml y AGENTS.md) ────────────────────
class BloqueGestionado(unittest.TestCase):
    CONTENIDO = '[mcp_servers.atlassian]\nurl = "https://x"\n\n[mcp_servers.atlassian.tools.a]\napproval_mode = "prompt"\n'

    def setUp(self):
        sandbox = tempfile.TemporaryDirectory()
        self.addCleanup(sandbox.cleanup)
        self.dir = Path(sandbox.name)
        self.config = self.dir / "config.toml"

    def instalar(self, contenido: str | None = None, destino: Path | None = None, formato: str = "toml") -> str:
        return bloque_gestionado.instalar(destino or self.config, contenido or self.CONTENIDO, formato, "STAMP")

    def test_agrega_al_final_sin_tocar_lo_del_usuario(self):
        propio = 'model = "x"\n\n# mi comentario\n[mcp_servers.playwright]\ncommand = "npx"\n'
        self.config.write_text(propio, encoding="utf-8")
        self.assertEqual(self.instalar(), "agregado")
        final = self.config.read_text(encoding="utf-8")
        self.assertTrue(final.startswith(propio), "lo del usuario tiene que quedar byte a byte")
        self.assertEqual(tomllib.loads(final)["mcp_servers"]["atlassian"]["url"], "https://x")
        self.assertEqual((self.dir / "config.toml.bak-STAMP").read_text(encoding="utf-8"), propio)

    def test_es_idempotente(self):
        self.config.write_text('model = "x"\n', encoding="utf-8")
        self.instalar()
        primera = self.config.read_text(encoding="utf-8")
        self.assertEqual(self.instalar(), "sin cambios")
        self.assertEqual(self.config.read_text(encoding="utf-8"), primera)
        self.assertEqual(primera.count("# >>> qa-harness-pro >>>"), 1)

    def test_reemplaza_el_bloque_en_su_lugar(self):
        self.config.write_text('model = "x"\n', encoding="utf-8")
        self.instalar()
        with self.config.open("a", encoding="utf-8") as archivo:
            archivo.write('\n[otra]\nclave = 1\n')
        self.assertEqual(self.instalar(self.CONTENIDO.replace("https://x", "https://y")), "actualizado")
        final = self.config.read_text(encoding="utf-8")
        self.assertIn("https://y", final)
        self.assertNotIn("https://x", final)
        self.assertTrue(final.rstrip().endswith("clave = 1"), "lo agregado después del bloque sigue en su lugar")

    def test_no_duplica_una_tabla_que_el_usuario_ya_define(self):
        propio = '[mcp_servers.atlassian]\nurl = "https://mio"\n'
        self.config.write_text(propio, encoding="utf-8")
        with self.assertRaises(bloque_gestionado.Conflicto):
            self.instalar()
        self.assertEqual(self.config.read_text(encoding="utf-8"), propio)
        self.assertFalse((self.dir / "config.toml.bak-STAMP").exists())

    def test_un_toml_del_usuario_roto_no_se_toca(self):
        self.config.write_text("esto = = roto\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.instalar()
        self.assertEqual(self.config.read_text(encoding="utf-8"), "esto = = roto\n")

    def test_marcas_rotas_no_se_adivinan(self):
        self.config.write_text("# >>> qa-harness-pro >>> viejo\nx = 1\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.instalar()

    def test_no_confunde_el_bloque_de_otra_herramienta(self):
        ajeno = "# >>> conda initialize >>>\n# <<< conda initialize <<<\n"
        self.config.write_text(ajeno, encoding="utf-8")
        self.instalar()
        self.assertTrue(self.config.read_text(encoding="utf-8").startswith(ajeno))

    def test_crea_el_archivo_si_no_existe(self):
        self.assertEqual(self.instalar(), "creado")
        tomllib.loads(self.config.read_text(encoding="utf-8"))

    def test_sigue_el_symlink_en_vez_de_reemplazarlo(self):
        real = self.dir / "dotfiles.toml"
        real.write_text('model = "x"\n', encoding="utf-8")
        self.config.symlink_to(real)
        self.instalar()
        self.assertTrue(self.config.is_symlink(), "el symlink del usuario tiene que sobrevivir")
        self.assertIn("qa-harness-pro", real.read_text(encoding="utf-8"))

    def test_markdown_conserva_el_nombre_del_archivo_existente(self):
        """En macOS, ~/.codex/agents.md y AGENTS.md son el mismo archivo."""
        propio = self.dir / "agents.md"
        propio.write_text("# mis reglas\n", encoding="utf-8")
        if not (self.dir / "AGENTS.md").exists():
            self.skipTest("este disco distingue mayúsculas: ahí son dos archivos distintos")
        self.instalar("## QA Harness Pro\n", self.dir / "AGENTS.md", "md")
        self.assertEqual(sorted(p.name for p in self.dir.iterdir() if not p.name.endswith("STAMP")), ["agents.md"])
        texto = propio.read_text(encoding="utf-8")
        self.assertTrue(texto.startswith("# mis reglas\n"))
        self.assertIn("<!-- >>> qa-harness-pro >>>", texto)


if __name__ == "__main__":
    unittest.main()
