# QA Harness Pro — port a Cursor

Cursor soporta MCP, hooks y rules, así que el harness funciona casi completo.

## Instalación

```bash
./install.sh --agent cursor
```

Es el instalador único del harness, desde la raíz del repo: ya no hay un script por herramienta.

Fusiona en `~/.cursor/` sin pisar lo que ya tengas (backup con timestamp de todo lo que toca).
Después: reinicia Cursor, autentica el MCP de Atlassian, y **abre Cursor en la raíz de este repo**.

## Equivalencias

| Componente | Claude Code | Cursor |
|---|---|---|
| MCP | `.mcp.json` | `~/.cursor/mcp.json` |
| Hooks | `.claude/settings.json` | `~/.cursor/hooks.json` |
| Reglas | `AGENTS.md` (fuente única) importado desde `adapters/claude/CLAUDE.md` | `AGENTS.md`, que Cursor lee solo en la raíz del proyecto, + `<proyecto>/.cursor/rules/qa-harness.mdc` como red (scope de proyecto — Cursor NO lee `~/.cursor/rules/`) |
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

preToolUse            in : {"tool_name","tool_input","tool_use_id","conversation_id",…}
postToolUse           in : lo mismo + "tool_output"
                      out: {"additional_context":"…"}   ← no bloquea; el agente lo lee
postToolUseFailure    in : lo mismo + "error_message","failure_type"
                      out: {"additional_context":"…"}
                      matcher: regex contra tool_name; la terminal es "Shell"
```

Es el port más cercano a Claude Code de los tres: hasta los nombres `tool_name` y `tool_input`
coinciden. La única trampa es que `tool_input` llega serializado como string — si no lo desanidas,
el gate no encuentra contenido y bloquea payloads perfectamente válidos. Hay un test para eso.

## Las tres diferencias que importan

### 1. En MCP se puede denegar, no preguntar

`beforeMCPExecution` solo implementa `deny`. No hay `ask`.

Eso está bien, porque Cursor tiene su propio allowlist de herramientas MCP: la confirmación
interactiva la pone él. El hook aporta lo que Cursor no puede saber — **si el contenido que se va a
publicar está completo**. Un payload con un placeholder sin resolver se bloquea; uno limpio pasa a
la aprobación normal de Cursor.

> Al configurar el MCP de Atlassian, **no marques las herramientas de escritura como
> "siempre permitir"**. Si lo haces, pierdes la confirmación y el hook queda como única defensa.

### 2. El gate post-edit llega en el próximo comando

`afterFileEdit` no puede bloquear ni devolver feedback. Así que `check-after-edit.py` corre los
checks y deja una marca, y `block-destructive-command.py` (en `beforeShellExecution`) la levanta
como `ask` en el siguiente comando de shell.

En la práctica el agente casi siempre corre algo después de editar (tests, git), así que el aviso
llega. Si edita y no corre nada, la marca espera.

### 3. Lo que escribe la terminal se revisa aparte, y avisa en el mismo turno

`afterFileEdit` no se entera de lo que el agente escribe por la terminal
(`printf '{"a": }' > x.json`, `sed -i`, un script que genera archivos). Para ese camino hay un par
de hooks enganchados con `matcher: "Shell"`:

- `snapshot-before-shell.py` (`preToolUse`) saca una foto de lo que el gate post-edición gobierna
  en la raíz del harness y la guarda en `$TMPDIR/qa-harness-cursor/`, con clave
  `(conversation_id, tool_use_id)`. Nunca dice nada.
- `check-after-shell.py` (`postToolUse` y `postToolUseFailure`, porque un comando que falla puede
  haber escrito antes de fallar) compara con el disco y pasa por `core/gates/post_edicion` cada
  archivo que **ese** comando creó o modificó. Si algo quedó roto, lo devuelve como
  `additional_context`: Cursor lo agrega a la conversación después del resultado del comando. No
  bloquea (el comando ya corrió), pero el agente lo lee en el mismo turno — no hace falta la marca
  diferida de `afterFileEdit`.

Sin foto de antes (la raíz no es un repo git, el `preToolUse` no corrió, falta el `tool_use_id`),
el check se abstiene en silencio: nunca valida el repo entero a ciegas.

**De dónde sale el contrato, y qué falta.** Los eventos, el `matcher`, el `tool_use_id` y
`additional_context` están en la [referencia de hooks de Cursor](https://cursor.com/docs/agent/hooks)
(secciones *preToolUse*, *postToolUse* y *postToolUseFailure*). Que el par se une bien está leído
del bundle de Cursor 3.21.9 (`extensions/cursor-agent-exec/dist/main.js`): `preToolUse` y
`postToolUse` mandan el mismo `toolCallId` como `tool_use_id`, el `matcher` se evalúa como regex
contra `tool_name`, y el nombre de la terminal es `Shell`. Lo que **todavía no está probado** es
una sesión real de punta a punta. Para verificarlo: pídele al agente que escriba por la terminal
un JSON roto (`printf '{"a": }' > zz-prueba.json`) y fíjate que en el mismo turno diga que falló
JSON. Después borra el archivo.

## Si Cursor carga los hooks de Claude Code

Cursor puede correr también los hooks de **Claude Code**. Lo controla Cursor Settings → Chat →
**"Include Third-Party Plugins, Skills, and Other Configs"**, y viene **prendido**. Leído del bundle
de Cursor 3.21.9 (`out/vs/workbench/workbench.desktop.main.js` y
`extensions/cursor-agent-host/dist/agent-host-daemon/dist/bin/daemon.cjs`):

- El toggle se guarda como `thirdPartyExtensibilityEnabled`, y
  `isClaudeCodeHooksEnabled(){return this.thirdPartyExtensibilityObservable.get()??!0}`: sin elegir,
  queda en `true`.
- Carga `~/.claude/settings.json`, `<workspace>/.claude/settings.json` y
  `<workspace>/.claude/settings.local.json`.
- Traduce `PreToolUse` → `preToolUse` y `PostToolUse` → `postToolUse`; `PostToolUseFailure` no
  existe en su tabla y se descarta. El matcher `Bash` pasa a `Shell`, y `Edit`/`Write` a `Write`.
- El hook recibe el payload **de Cursor**, sin traducir: `tool_name: "Shell"`,
  `hook_event_name: "preToolUse"`, más `cursor_version` y `workspace_roots`. En el entorno pone
  `CURSOR_PROJECT_DIR`, `CURSOR_VERSION` y, "for Claude compatibility", `CLAUDE_PROJECT_DIR`.
- A la salida sí la traduce: un `hookSpecificOutput.permissionDecision: "deny"` de Claude Code se
  vuelve un `deny` de Cursor.

Con eso, un hook de `adapters/claude/hooks/` corriendo bajo Cursor vería una herramienta que no es
`Bash` y, como falla cerrado, **denegaría cada comando de shell** — encima de los hooks de este
adaptador, que ya gobiernan ese runtime. Por eso los hooks de Claude se hacen a un lado cuando los
dispara Cursor: responden `{}` (allow sin opinión) y no sacan foto. La marca es el payload, no el
entorno ni el `tool_name`: hace falta `cursor_version` **y** un evento en camelCase, las dos cosas
que pone el ejecutor de Cursor y que Claude Code nunca manda (ver `lo_invoca_cursor` en
`adapters/claude/hooks/_claude.py`). Un payload de Claude Code con `tool_name: "Shell"` sigue
frenando: para Claude Code eso es una config rota.

**Hoy, con el `.claude/settings.json` de este repo, los scripts ni siquiera llegan a correr.**
Nuestras entradas usan `"command": "python3"` + `"args": [...]`, y la traducción de Cursor 3.21.9 se
queda solo con `command` (el `args` se pierde). Cursor ejecuta un `python3` pelado con el JSON por
stdin, que termina con exit 1 (`NameError: name 'null' is not defined`): Cursor lo registra como hook
fallido y no bloquea. El paso al costado es para cuando eso cambie — una versión que respete `args`,
o hooks copiados a mano con la ruta dentro de `command` (por ejemplo en tu `~/.claude/settings.json`).

Si no usas plugins ni skills de otras herramientas en Cursor, lo más limpio es **apagar ese
toggle**: Cursor deja de cargar los hooks de `.claude/` y en sus logs de hooks desaparecen esos `python3` fallidos.
No lo detectamos desde `validate-config.sh`: vive en la base de estado interna de Cursor, no en un
archivo de config.

## Verifica que el gate muerde

Primero, que las reglas te lleguen: escribe `PING-HARNESS` en un chat nuevo. Debe responder
`PONG <empresa> <backend> <destino>` y nada más — el destino sale del backend que tengas
configurado. Si contesta otra cosa, la rule no cargó — y el
análisis va a salir igual, sin las reglas. Es la falla que no se ve.

Después, que el gate muerda: pídele que publique un comentario en Jira que contenga `PON-AQUI-EL-ID`.
**Debe bloquearlo.** Si lo publica, el hook no está enganchando: revisa que `~/.cursor/hooks.json`
tenga el grupo con las rutas correctas y que Cursor se haya reiniciado.

Un gate desconectado no avisa que lo está. Simplemente deja pasar todo.

### Si moviste el repo o lo clonaste de nuevo

Es la falla más silenciosa de todas: `~/.cursor/hooks.json` vive fuera del repo, así que sobrevive a
la mudanza apuntando a la ruta vieja. Si esa ruta desapareció, el hook no corre y Cursor no te avisa;
si todavía existe porque es otro clon, el hook corre — pero son los gates de ese otro clon, con sus
reglas y sus skills, no las tuyas.

`./validate-config.sh` caza las dos, y las distingue: una dice que la ruta **ya no existe**, la otra
que apunta a **otro clon del harness**, y cada mensaje trae el comando de reparación. La reparación
es la misma en los dos casos:

```bash
./install.sh --agent cursor
```

Reinstalar desde la ruta nueva **reemplaza** la entrada vieja en vez de sumarle otra: los hooks del
harness se identifican por el nombre del script, no por su ruta, así que reinstalar desde otro lugar
no te deja hooks duplicados apuntando a un script que ya no existe.
