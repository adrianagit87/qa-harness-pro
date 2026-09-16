# QA Harness Pro — port a Cursor

Cursor soporta MCP, hooks y rules, así que el harness funciona casi completo.

## Instalación

```bash
./cursor/install-cursor.sh
```

Fusiona en `~/.cursor/` sin pisar lo que ya tengas (backup con timestamp de todo lo que toca).
Después: reiniciá Cursor, autenticá el MCP de Atlassian, y **abrí Cursor en la raíz de este repo**.

## Equivalencias

| Componente | Claude Code | Cursor |
|---|---|---|
| MCP | `.mcp.json` | `~/.cursor/mcp.json` |
| Hooks | `.claude/settings.json` | `~/.cursor/hooks.json` |
| Reglas | `CLAUDE.md` | `<proyecto>/.cursor/rules/qa-harness.mdc` (scope de proyecto — Cursor NO lee `~/.cursor/rules/`) |
| Skills | `~/.claude/skills/` | La rule apunta a `skills/` y el agente lee el `SKILL.md` que necesita |
| Permisos ask/deny | bloque `permissions` | Dentro del hook, vía `permission` |

## El contrato de los hooks

Verificado leyendo el binario de Cursor, no adivinado:

```
beforeShellExecution  in : {"command","cwd"}
                      out: {"permission":"deny"|"ask","user_message":"…"}

beforeMCPExecution    in : {"tool_name","tool_input"}   ← tool_input es STRING JSON
                      out: {"permission":"deny","user_message":"…"}

afterFileEdit         in : {"file_path","edits"}        ← no puede bloquear
```

Es el port más cercano a Claude Code de los tres: hasta los nombres `tool_name` y `tool_input`
coinciden. La única trampa es que `tool_input` llega serializado como string — si no lo desanidás,
el gate no encuentra contenido y bloquea payloads perfectamente válidos. Hay un test para eso.

## Las dos diferencias que importan

### 1. En MCP se puede denegar, no preguntar

`beforeMCPExecution` solo implementa `deny`. No hay `ask`.

Eso está bien, porque Cursor tiene su propio allowlist de herramientas MCP: la confirmación
interactiva la pone él. El hook aporta lo que Cursor no puede saber — **si el contenido que se va a
publicar está completo**. Un payload con un placeholder sin resolver se bloquea; uno limpio pasa a
la aprobación normal de Cursor.

> Al configurar el MCP de Atlassian, **no marques las herramientas de escritura como
> "siempre permitir"**. Si lo hacés, perdés la confirmación y el hook queda como única defensa.

### 2. El gate post-edit llega en el próximo comando

`afterFileEdit` no puede bloquear ni devolver feedback. Así que `check-after-edit.py` corre los
checks y deja una marca, y `block-destructive-command.py` (en `beforeShellExecution`) la levanta
como `ask` en el siguiente comando de shell.

En la práctica el agente casi siempre corre algo después de editar (tests, git), así que el aviso
llega. Si edita y no corre nada, la marca espera.

## Verificá que el gate muerde

Primero, que las reglas te lleguen: escribí `PING-HARNESS` en un chat nuevo. Debe responder
`PONG <empresa> <backend> <proyecto>` y nada más. Si contesta otra cosa, la rule no cargó — y el
análisis va a salir igual, sin las reglas. Es la falla que no se ve.

Después, que el gate muerda: pedile que publique un comentario en Jira que contenga `PON-AQUI-EL-ID`.
**Debe bloquearlo.** Si lo publica, el hook no está enganchando: revisá que `~/.cursor/hooks.json`
tenga el grupo con las rutas correctas y que Cursor se haya reiniciado.

Un gate desconectado no avisa que lo está. Simplemente deja pasar todo.
