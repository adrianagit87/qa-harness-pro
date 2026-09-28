# QA Harness Pro — port a Codex CLI

Codex CLI soporta hooks, MCP, skills nativas y `AGENTS.md`, así que el harness funciona completo, con
**un paso manual obligatorio** que no se puede automatizar: aprobar los hooks en `/hooks`.

Contrato leído de las docs oficiales y contrastado con `codex-cli` **0.155.1** (sus esquemas embebidos y
`codex mcp`) y **0.157.1** (en vivo: los tres gates, el deny de MCP incluido, en sesiones reales).
Qué está verificado y qué no, más abajo.

## Instalación

```bash
./install.sh --agent codex
```

Toca cuatro cosas, y ninguna la pisa entera:

| Qué | Dónde | Cómo |
|---|---|---|
| Hooks | `$CODEX_HOME/hooks.json` | fusión con `jq`: se agregan 5 grupos **al final** de cada evento; lo tuyo (Orca, gentle-ai…) queda igual y primero. Backup antes. |
| MCP de Atlassian + segunda capa | `$CODEX_HOME/config.toml` | bloque gestionado entre marcas `# >>> qa-harness-pro >>>` … `# <<< qa-harness-pro <<<`, agregado al final. Backup antes. |
| Reglas | `$CODEX_HOME/AGENTS.md` | bloque gestionado entre marcas `<!-- >>> qa-harness-pro >>> -->`, que apunta al `AGENTS.md` de este repo. Backup antes. |
| Skills | `~/.agents/skills/<skill>` | un symlink por skill, como en Claude Code: `references/` viaja con cada una. Si ya hay una skill tuya con el mismo nombre, no se instala nada hasta que corras con `--reemplazar-skills` (backup `<nombre>.bak-<fecha>`). |

`CODEX_HOME` es la variable que respeta el propio Codex (default `~/.codex`); el instalador y el
validador la respetan también. `CODEX_SKILLS_DIR` (default `~/.agents/skills`) existe para poder
probarlo en un sandbox. Si `CODEX_HOME` no existe, no se instala nada: Codex nunca corrió ahí.

Reinstalar es idempotente: los hooks del harness se reconocen por el sufijo
`adapters/codex/hooks/<script>` del command (no por la ruta absoluta, que cambia si mudás el repo),
y los bloques por sus marcas. Si nada cambió, `config.toml` y `AGENTS.md` ni se reescriben.

### Por qué bloques gestionados y no archivos propios

- **`config.toml`** es tuyo: tus servers, tus permisos, tus aprobaciones. Reescribirlo con un parser
  de TOML perdería tus comentarios y tu orden. El bloque se agrega o se reemplaza entre marcas, el
  resultado se vuelve a parsear **antes** de escribirlo, y si tu archivo ya no parseaba, no se toca.
- **Si ya tenés tu propio `[mcp_servers.atlassian]`**, el bloque NO se agrega: una tabla duplicada es
  TOML inválido y Codex no arranca. La instalación termina con exit 1 y te dice qué sumar a mano
  dentro de tu server (lo que trae [`config/mcp.toml`](./config/mcp.toml)). `validate-config.sh`
  valida la config **efectiva**, así que hecho a mano también cuenta.
- **`AGENTS.md`**: Codex no tiene imports como el `@ruta` de Claude Code, y tu `~/.codex/AGENTS.md`
  es personal (en macOS, `agents.md` y `AGENTS.md` son **el mismo archivo**: el bloque se agrega al
  que ya tenés, con el nombre que ya tiene). No se pega el método entero —150 líneas que quedarían
  viejas y duplicadas—: el bloque es corto y apunta al `AGENTS.md` del repo. En la raíz del repo
  Codex ya lo lee solo como instrucciones del proyecto (verificado); el bloque es la red para cuando
  trabajás desde otra carpeta.
- **Sin sidecar de estado** (a diferencia de Antigravity): todo lo que el harness deja afuera se
  reconoce solo —hooks por sufijo, bloques por marcas, skills por symlink— así que reinstalar desde
  otra ruta reemplaza sin tener que recordar nada.

## El paso obligatorio: `/hooks`

Codex **no corre un hook que no aprobaste**, y no avisa: el gate simplemente no existe. Después de
instalar (y después de cada reinstalación desde otra ruta, porque cambia el command y con él el
hash):

1. Abrí Codex (`codex`).
2. Corré `/hooks`.
3. Revisá los cinco hooks del harness y confiá en ellos.

**Si actualizaste el harness** (por ejemplo, a la versión que agrega el gate de la terminal),
reinstalá con `./install.sh --agent codex` y volvé a `/hooks`: te va a mostrar **solo los hooks
nuevos** para aprobar (`snapshot-before-shell.py` y `check-after-shell.py`). Los que ya aprobaste
no se mueven de lugar ni cambian de command, así que su aprobación sigue valiendo. Aprobá **los dos**:
son un par, y con uno solo el gate de la terminal se abstiene en silencio (`validate-config.sh` lo avisa).

Codex guarda la aprobación en `config.toml` como `[hooks.state."<hooks.json>:<evento>:<grupo>:<hook>"]`
con un `trusted_hash`. `validate-config.sh --agent codex` mira si **hay** una aprobación registrada
en la posición de cada hook del harness. Lo que **no** puede saber es si ese hash corresponde a la
versión actual del command: lo calcula Codex y no está documentado. Por eso la presencia es solo
informativa (ℹ️) y la ausencia es un aviso. La única prueba real es la prueba en vivo de abajo.

Por eso también los grupos del harness van **al final** de cada evento: la aprobación está atada al
índice, y agregar adelante correría de lugar los hooks que ya aprobaste.

## Equivalencias

| Componente | Claude Code | Codex CLI |
|---|---|---|
| MCP | `.mcp.json` del repo | `[mcp_servers.atlassian]` en `~/.codex/config.toml` (auth: `codex mcp login atlassian`) |
| Hooks | `.claude/settings.json` | `~/.codex/hooks.json` (nivel usuario: el `.codex/` de un proyecto solo se lee si es *trusted*) |
| Reglas | `AGENTS.md` importado desde `~/.claude/CLAUDE.md` | `AGENTS.md` del repo, nativo en su raíz + bloque en `~/.codex/AGENTS.md` como red |
| Skills | `~/.claude/skills/` | `~/.agents/skills/` (nativo, symlinks) |
| Deny de transiciones | `permissions.deny` | hook `deny` + `disabled_tools` (la tool ni se le ofrece al modelo) |
| Confirmar escrituras | `permissions.ask` | `approval_mode = "prompt"` por tool (el hook no puede pedir confirmación) |

## El contrato de los hooks

De las docs oficiales y de los esquemas JSON embebidos en los binarios 0.155.1 y 0.157.1:

```
PreToolUse   in : {"tool_name","tool_input","cwd","session_id","tool_use_id",...}
             out: {"hookSpecificOutput":{"hookEventName":"PreToolUse",
                   "permissionDecision":"deny","permissionDecisionReason":"…"}}
             ← solo "deny"; el binario rechaza "ask" y "allow" como unsupported,
               y un deny sin motivo tampoco lo acepta
PostToolUse  in : lo mismo + "tool_response"
             out: {"decision":"block","reason":"…"}
             ← no deshace la edición: reemplaza el resultado de la tool por el motivo
tool_input   Bash y apply_patch: el texto en tool_input.command (el patch entero)
             MCP: los argumentos tal cual; el nombre es mcp__<server>__<tool>
tool_use_id  obligatorio en pre y post (esquemas de 0.157.1), igual que session_id:
             une el PreToolUse de un comando con su PostToolUse
```

| Hook | Evento · matcher | Qué hace |
|---|---|---|
| `block-destructive-command.py` | PreToolUse · `Bash` | `core/gates/destructivos` sobre `tool_input.command` |
| `check-after-edit.py` | PostToolUse · `apply_patch\|Edit\|Write` | extrae **cada** archivo del patch (`*** Add File:`, `*** Update File:`, `*** Move to:`; los `*** Delete File:` no dejan nada que revisar) y corre `core/gates/post_edicion` sobre todos |
| `validate-external-write.py` | PreToolUse · `mcp__.*` | transición → deny siempre; escritura del catálogo con placeholder o sin contenido → deny; el resto, silencio |
| `snapshot-before-shell.py` | PreToolUse · `Bash` (grupo aparte, al final) | no es un gate: saca la foto del disco antes del comando (ver abajo). Nunca dice nada |
| `check-after-shell.py` | PostToolUse · `Bash` | compara con la foto y corre `core/gates/post_edicion` sobre lo que **ese** comando creó o modificó |

**Abstenerse es silencio.** El matcher `mcp__.*` ve toda llamada MCP, lecturas incluidas, y los hooks
son globales: corren en cualquier proyecto. Un default restrictivo frenaría al agente entero.
**La entrada ilegible falla cerrado**: el matcher garantiza que la herramienta es una que el gate
gobierna, así que un stdin que no se puede leer se deniega (o se frena, en post-edición).

**El post-edit revisa solo lo que está dentro del harness** (o de `QA_HARNESS_ROOT`), igual que en
Cursor: los hooks corren en todos tus proyectos y no es asunto del harness validar el JSON de otro
repo. La única excepción es el baseline configurado (`baseline.path`), que se valida esté donde esté.
Las rutas del patch se resuelven contra el `cwd` de la sesión.

**Lo que se escribe por la terminal también pasa por post-edición.** Codex escribe seguido con el
shell (`printf '%s' '{"a": }' > x.json`, `sed -i`, un script que genera archivos), y eso no es un
`apply_patch`: en la prueba en vivo con 0.157.1, un JSON inválido quedó escrito sin que ningún gate
se enterara. Leer el comando para adivinar qué toca es frágil, así que no se adivina: se compara el
disco antes y después (`core/gates/post_shell`).

- **Antes** (`snapshot-before-shell.py`, PreToolUse `Bash`): una foto `ruta → (mtime, ctime, tamaño)`
  de lo que gobierna post-edición: dentro de la raíz, lo modificado y lo no trackeado que no está
  ignorado (`git ls-files -m -o --exclude-standard`), más el baseline configurado esté donde esté.
  Tarda ~0,15 s en este repo.
- **Después** (`check-after-shell.py`, PostToolUse `Bash`): la misma foto otra vez; lo creado o
  modificado por **ese** comando pasa por post-edición. Si cambió varios `.py`, la suite corre **una**
  vez, no una por archivo. Lo borrado no deja nada que revisar; lo roto de antes que el comando no
  tocó no se le carga.
- **La foto** vive en `$TMPDIR/qa-harness-codex/` (carpeta 0700, del usuario), con nombre por
  `session_id` + `tool_use_id`. Afuera del repo a propósito —adentro sería un no trackeado más y el
  diff lo vería— y afuera de `~/.codex`, que es tuyo. El post la consume y la borra; las huérfanas
  (comando rechazado, sesión cortada) las barre el pre cuando pasan 12 h.
- **Sin foto, se abstiene**: si el pre no corrió (no lo aprobaste en `/hooks`), si la raíz no es un
  repo git o si falta el `tool_use_id`, el post no dice nada. Nunca valida el repo entero a ciegas.

Por qué un hook **aparte** para la foto y no dentro de `block-destructive-command.py`: aquel es un
gate que deniega; la foto es un registro que no puede frenar al usuario, y mezclarlos haría que un
`git` lento comparta proceso y timeout con el deny de lo destructivo. Y la confianza de `/hooks` es
por posición: un grupo nuevo al final pide aprobar solo ese hook y no toca los que ya aprobaste.

## Qué se aplica nativo y qué es segunda capa

| Regla | Primera capa | Segunda capa |
|---|---|---|
| Nada destructivo en shell | hook PreToolUse `Bash` | — (el sandbox y la aprobación de Codex, que no son nuestros) |
| Un cambio que rompe algo se entera en el acto | hook PostToolUse (`apply_patch` y también lo que escribe el shell) → el modelo lee el motivo y corrige | — |
| Nunca cambiar el estado de un ticket | `disabled_tools = ["transitionJiraIssue"]`: el modelo ni ve la tool | hook PreToolUse `mcp__.*` → deny |
| Nada sale a medio hacer | hook PreToolUse `mcp__.*` → deny con placeholder o vacío | `approval_mode = "prompt"` en cada escritura del catálogo: siempre te pregunta |

## Limitaciones conocidas

- **openai/codex#27833: un deny de PreToolUse sobre `apply_patch` no se respeta.** Por eso el gate de
  edición es PostToolUse y mira el archivo ya escrito, que es lo que el diseño quería igual. No se
  puede impedir una edición antes de que ocurra; sí que el modelo siga sin enterarse de que rompió algo.
- **El deny de un hook sobre una tool MCP está verificado en vivo con 0.157.1**: Codex corta la llamada
  antes del diálogo de aprobación con `Tool call blocked by PreToolUse hook: Quality gate de
  publicación: quedó un placeholder sin resolver ('PON-AQUI').. Tool: mcp__atlassian__addCommentToJiraIssue`.
  La segunda capa de `config.toml` sigue igual: no depende del hook, y #27833 muestra que un deny que
  Codex respeta en una tool puede no respetarse en otra.
- **El gate de la terminal ve el disco, no el comando.** Lo que escribe un comando fuera de la raíz
  (salvo el baseline configurado) o en un directorio que no es un repo git no se revisa. Si dos
  comandos corren a la vez, el diff de uno puede incluir lo del otro: se revisa de más, nunca de menos.
  Un archivo ignorado por `.gitignore` tampoco entra, igual que no le importa al resto del harness.
- **El feedback de post-edición dice que el archivo YA quedó escrito.** `{"decision":"block"}` suena a
  rechazo y el modelo tendía a contar que la edición "fue rechazada" cuando el archivo sí estaba en disco.
  El motivo que ve Codex ahora empieza por `el cambio YA QUEDÓ ESCRITO en disco; este aviso no lo
  deshizo ni lo rechazó`.
- **La confianza de `/hooks` no se puede confirmar desde afuera** (ver arriba).
- **Solo Atlassian lleva segunda capa.** El server de Notion no se agrega al bloque: muchos ya tienen
  su propio `[mcp_servers.notion]` y duplicarlo rompería el TOML. El hook igual revisa el contenido de
  `notion-create-pages` / `notion-update-page` si tu server se llama `notion`; la aprobación por tool
  la configurás vos.
- **Las escrituras de Atlassian que no están en el catálogo** (`createConfluenceFooterComment`,
  `addWorklogToJiraIssue`, `createIssueLink`…) no llevan `approval_mode = "prompt"`: siguen la
  política de aprobación general de tu Codex. Se agregan en `core/gates/catalogo.py` y en
  `config/mcp.toml`; `tests/test_codex_hooks.py` falla si los dos se desfasan.
- **La lectura del patch** busca los encabezados en cualquier línea (tolera sangría, CRLF y un heredoc
  alrededor). Una línea de contexto que cite literalmente `*** Update File: x` se leería como un
  archivo más; el costo es revisar un archivo de más, nunca uno de menos.

## Prueba en vivo — que los tres gates muerden

Todo lo de abajo usa objetivos inofensivos: una ruta que no existe, un archivo de prueba y un ticket
inexistente (`ZZZ-0`). Ninguna escritura real llega a Jira aunque un gate falle.

**0. Preparación.**

```bash
./validate-config.sh --agent codex      # sin ❌; el aviso de /hooks es esperable la primera vez
codex mcp login atlassian               # OAuth en el navegador
cd <raíz-del-repo> && codex
```

En Codex: `/hooks` → confiá en los cinco del harness. Después `/mcp` → el server `atlassian` tiene que
figurar conectado.

**1. Las reglas llegan.** Escribí `PING-HARNESS`.
Esperado: `PONG <empresa> <backend> <destino>` y nada más.

**2. Comando destructivo.** Pedile:
`Corré exactamente este comando y nada más: rm -rf /tmp/qa-harness-prueba-que-no-existe`
Esperado: el comando **no** corre y Codex muestra `Quality gate: rm recursivo y forzado bloqueado.`
(Si corriera, borra una carpeta que no existe: inofensivo, pero el gate está desconectado.)

**3. Post-edición.** Pedile:
`Creá el archivo zz-prueba-codex.json en la raíz del repo con este contenido exacto: {"a": }`
Esperado: el archivo se crea (el gate no lo impide, ver #27833) y el modelo recibe
`Quality gate post-edit: el cambio YA QUEDÓ ESCRITO en disco; … falló JSON después de editar
zz-prueba-codex.json…`; lo dice (sin contar que "se rechazó") y propone arreglarlo. Después:
`rm zz-prueba-codex.json`.

**3b. Post-edición por la terminal.** Pedile:
`Usando la terminal y no apply_patch, corré exactamente: printf '%s' '{"a": }' > zz-prueba-codex.json`
Esperado: el comando corre y el modelo recibe el mismo `Quality gate post-edit: el cambio YA QUEDÓ
ESCRITO en disco; … falló JSON después de editar zz-prueba-codex.json…`. Si no dice nada, el par
`snapshot-before-shell.py` / `check-after-shell.py` no está aprobado en `/hooks` (hacen falta los dos).
Después: `rm zz-prueba-codex.json`.

**4. Publicación con placeholder.** Dentro del repo esto **no** prueba el hook: el modelo se niega
solo a llamar a Jira, porque el `AGENTS.md` del harness le exige perfil y borrador primero. Es la regla
funcionando, no el gate. Para ejercitar el hook, corré Codex desde una carpeta vacía, sin sesión que
guardar y en solo lectura:

```bash
mkdir -p /tmp/qa-harness-vacia
codex exec --skip-git-repo-check --ephemeral -s read-only -C /tmp/qa-harness-vacia \
  "Cargá la tool addCommentToJiraIssue del server atlassian con tu mecanismo de búsqueda de tools \
   (las tools MCP están diferidas) y después llamala con issueIdOrKey ZZZ-0 y el texto exacto \
   'Prueba del harness: PON-AQUI-EL-ID'."
```

Las tools MCP llegan diferidas: si el prompt no le pide cargarla primero, el modelo dice que no la
tiene y el hook nunca se ejercita. Esperado (verificado con 0.157.1):
`Tool call blocked by PreToolUse hook: Quality gate de publicación: quedó un placeholder sin resolver ('PON-AQUI').. Tool: mcp__atlassian__addCommentToJiraIssue`.
Si en cambio aparece el diálogo de aprobación de Codex, el hook de MCP **no** mordió: **rechazá** y
anotalo. La segunda capa funcionó, la primera no. (Aunque aprobaras por error, `ZZZ-0` no existe.)

**5. Transición — segunda capa.** Pedile:
`¿Tenés disponible la tool transitionJiraIssue del server atlassian? No la llames: solo decime sí o no.`
Esperado: no. `disabled_tools` la sacó de la lista.

**6. Transición — primera capa (el hook).** Para probar el hook hay que levantar la segunda capa **solo
en esa sesión**, y a la vez obligar a que pregunte, por si el hook no muerde:

```bash
codex -c 'mcp_servers.atlassian.disabled_tools=[]' \
      -c 'mcp_servers.atlassian.tools.transitionJiraIssue.approval_mode="prompt"'
```

Pedile: `Pasá el ticket ZZZ-0 a "Done".`
Esperado: deny del hook con `cambiar el estado de un ticket de Jira está prohibido en este harness`.
Si aparece el diálogo de aprobación, el hook no mordió: **rechazá**. Salí de esa sesión: los `-c` no
se guardan en tu `config.toml`.

Un gate desconectado no avisa que lo está. Simplemente deja pasar todo.

## Si moviste el repo o lo clonaste de nuevo

`~/.codex/hooks.json` y el bloque de `AGENTS.md` viven fuera del repo y sobreviven a la mudanza
apuntando a la ruta vieja. `./validate-config.sh --agent codex` lo caza (ruta que **ya no existe** u
**otro clon**) y nombra la reparación:

```bash
./install.sh --agent codex
```

Reinstalar desde la ruta nueva **reemplaza** los hooks y el bloque en vez de sumar otros. Como el
command cambió, **volvé a pasar por `/hooks`**.
