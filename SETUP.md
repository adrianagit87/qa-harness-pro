# SETUP — de clonar a "funciona"

Seis pasos. No necesitas saber programar; sí tener instalada una de las cuatro herramientas
soportadas: **Claude Code**, **Cursor**, **Antigravity (Gemini)** o **Codex CLI**.

Los pasos 1 a 4 son iguales para las cuatro. En el paso 5 eliges cuál con `--agent`. Puedes instalar
más de una: comparten las mismas skills y la misma configuración.

**Necesitas también:** `python3` (los hooks son scripts de Python) y, si vas a instalar con
`--agent cursor`, `--agent antigravity`, `--agent codex` o `--agent all`, también `jq`: es lo que usa
el instalador para fusionar tu JSON sin pisarlo. Con `--agent claude` no hace falta, y el instalador
no te lo pide. `--agent codex` pide además `python3` 3.11 o más nuevo, para validar tu `config.toml`
antes de tocarlo.

## 1. Clona y entra

```bash
git clone https://github.com/adrianagit87/qa-harness-pro.git ~/Proyectos/qa-harness-pro
cd ~/Proyectos/qa-harness-pro
```

> Déjalo en un lugar **permanente**. La instalación crea enlaces y rutas absolutas que apuntan acá:
> si después mueves o borras la carpeta, el harness deja de funcionar.
>
> Si aun así lo mueves o lo vuelves a clonar, la reparación es reinstalar desde la ruta nueva: el
> instalador **reemplaza** las entradas de la instalación anterior en vez de sumarles otras. Y si te
> olvidas, `./validate-config.sh` te lo marca como error (paso 4).

## 2. Configura tu empresa

```bash
cp companies/_template.json companies/miempresa.json
```

Abre `companies/miempresa.json` y complétalo. Cada campo está explicado en
[`docs/CONFIG.md`](./docs/CONFIG.md). Lo mínimo:

- `tracker.host` y `tracker.cloudId` (tu Jira).
- `environments`: los ambientes en los que tu equipo cierra ciclos, con su `default`. No están
  hardcodeados en las skills — si solo pruebas en staging, declaras solo staging.
- `docs.backend`: `"jira"`, `"confluence"` o `"notion"`, y el bloque correspondiente.
  - `"jira"` → `docs.jira` (proyecto de QA, tipos de issue y patrones de título).
  - `"confluence"` → `docs.confluence` (`spaceKey` y `parentPageId`).
  - `"notion"` → `docs.notion.parents.casos`.
  - El bloque del backend que NO uses puede quedar tal cual vino en el template.
- `automation` es opcional: solo lo necesita la skill de automatización.

## 3. Configura tu perfil

```bash
cp profile/profile.example.json profile/profile.json
```

Pon tu nombre, rol y tono — tu nombre es el que firma los cierres — y en **`activeCompany`** el
nombre del archivo de empresa que creaste en el paso 2 (ej. `"miempresa"`).

Ni `companies/*.json` ni `profile/profile.json` se versionan: están en `.gitignore` para que los
datos de tu empresa no queden en el historial de git.

## 4. Valida tu configuración

```bash
./validate-config.sh
```

Te dice exactamente qué falta o qué quedó en placeholder, antes de que nada falle en uso real.
No mira solo el formato: valida que tu tracker sea coherente (v2 = Jira; `browseUrlPattern` con
tu host real) y que los archivos versionados sigan prometiendo lo que el README promete —
`.claude/settings.json` con el deny de `transitionJiraIssue`, las escrituras en `ask` y los hooks
que bloquean comandos destructivos, validan ediciones y revisan publicaciones externas, y
`.mcp.json` con los servers MCP oficiales. Si alguien los vació o los rompió, acá lo ves.

Vale correrlo de nuevo **después** del paso 5: también verifica que las skills quedaron enlazadas
de verdad (symlinks que resuelven a este repo, no rotos ni apuntando a otro lado).

> **Qué cubre.** La config de empresa y perfil las valida para cualquier herramienta. La capa de
> seguridad la inspecciona en **los cuatro runtimes**: `.claude/settings.json` y `.mcp.json` para
> Claude Code; `~/.cursor/hooks.json`, `~/.cursor/mcp.json` y la rule `.cursor/rules/qa-harness.mdc`
> de este repo para Cursor; `hooks.json` y `mcp_config.json` de `~/.gemini/config/` y
> las copias de `~/.gemini/config/skills/` (avisa si alguna quedó desactualizada) para Antigravity; y `~/.codex/hooks.json`, el server de Atlassian con su segunda capa en
> `~/.codex/config.toml`, el bloque de `~/.codex/AGENTS.md` y las skills de `~/.agents/skills` para
> Codex (más un aviso si los hooks todavía no pasaron por `/hooks`).
>
> **Y que lo instalado apunte acá.** Si algo que dejó el harness fuera del repo quedó apuntando a
> **otro clon** o a una **ruta que ya no existe**, lo reporta como error y te dice con qué comando
> repararlo. Un gate que corre desde otro clon valida las reglas de ese otro clon; uno que apunta a
> una ruta borrada no corre y no avisa.
>
> **Qué NO cubre.** Que las reglas efectivamente le lleguen al agente y que el gate muerda en vivo:
> eso son los pasos 6a y 6b de más abajo, y no los reemplaza ningún script.

`./validate-config.sh` también acepta `--agent`, con los mismos valores que el instalador:

```bash
./validate-config.sh --agent cursor    # solo Cursor
./validate-config.sh --agent all       # los cuatro, estén instalados o no
./validate-config.sh --help            # los valores válidos
```

Sin `--agent` valida lo portable (perfil y empresa) más Claude Code siempre, y suma Cursor,
Antigravity o Codex **solo si encuentra el harness instalado ahí**. Con un `--agent` explícito le estás
afirmando que ese runtime está instalado, así que no encontrarlo **sí** es un error.

## 5. Instala para tu herramienta

Hay **un solo instalador** y le dices para qué herramienta con `--agent`:

```bash
./install.sh --agent claude        # Claude Code
./install.sh --agent cursor        # Cursor
./install.sh --agent antigravity   # Antigravity (Gemini)
./install.sh --agent codex         # Codex CLI
./install.sh --agent all           # las cuatro, en ese orden
./install.sh --help                # la ayuda
```

`--agent` es **obligatorio**: `./install.sh` a secas imprime la ayuda y sale con error, a propósito.
Elegir Claude Code por default sería un éxito ambiguo — quien vino por Cursor vería un ✅ y se iría
sin reglas. Con `--agent all` se instalan las cuatro por separado: si una falla, las otras quedan
instaladas igual y el comando te dice cuál falló.

### 5a. Claude Code

```bash
./install.sh --agent claude
```

Enlaza las skills en `~/.claude/skills` y, si todavía no tienes uno, instala
`adapters/claude/CLAUDE.md` como `~/.claude/CLAUDE.md` resolviendo la ruta absoluta del repo en su
import de `AGENTS.md`. Si ya tienes el tuyo no lo toca: te imprime la línea exacta que tienes que
agregarle para que las reglas te lleguen igual. Los
servers MCP ya vienen definidos en **`.mcp.json`**, versionado en el repo: no contiene ningún
secreto, la autenticación es OAuth en el navegador. No hay nada que copiar.

Después, abre Claude Code **en la raíz de este repo**:

- La primera vez te pedirá **confiar en el workspace** (el diálogo de trust) y **aprobar los servers
  de `.mcp.json`** (`atlassian` y `notion`). Acepta ambos: sin el trust, Claude Code ignora los
  permisos `allow` de `.claude/settings.json` y el harness pierde parte de su configuración de
  seguridad. Después autentica en el navegador (Jira y Confluence vía Atlassian; Notion solo si tu
  `docs.backend` es `notion`). Sin pegar tokens.
- ¿Ya tienes skills propias con estos mismos nombres en `~/.claude/skills`? `install.sh` se frena
  antes de tocar nada y te las lista. Para reemplazarlas por las del harness, vuelve a correrlo con
  `--reemplazar-skills`: cada una se mueve a `<nombre>.bak-<fecha>` (no pierdes nada). Si prefieres
  probar el harness sin tocar tu setup, usa `CLAUDE_DIR=/otra/ruta ./install.sh --agent claude` y
  abre Claude Code con `CLAUDE_CONFIG_DIR=/otra/ruta`. Si además tienes otras skills `qa-*`, el
  instalador te avisa: sus triggers pueden pisarse con los del harness.
- Los permisos del harness viven en **`.claude/settings.json`** (también versionado): lectura de
  Jira/Confluence/Notion permitida, escritura hacia afuera siempre pregunta, y cambiar estados de
  Jira (`transitionJiraIssue`) **denegado**.
- En ese mismo archivo viven los tres hooks deterministas: antes de `Bash` se bloquean los comandos
  destructivos; después de cada `Edit` o `Write` se valida el archivo modificado (sintaxis y unit
  tests para Python, `bash -n` para shell, `json.tool` para JSON) y el error vuelve al agente como
  feedback — y lo mismo con lo que un comando de `Bash` escribe en disco (una foto antes del
  comando y otra después; ver `core/gates/post_shell.py`); y antes de escribir en Jira, Confluence o Notion se rechazan los payloads vacíos,
  demasiado cortos o con placeholders. Solo se activan en sesiones abiertas desde esta raíz, porque
  apuntan a los scripts versionados en `adapters/claude/hooks/`.

> **Dónde aplican los permisos y hooks.** El método asume que trabajas desde la raíz del harness (así lo
> pide también `demo/README.md`). `.claude/settings.json` aplica en toda sesión de Claude Code
> abierta desde esta carpeta. Si vas a trabajar desde OTRA carpeta, los permisos se pueden fusionar
> a mano en tu `~/.claude/settings.json`, pero el hook del recurso no se copia tal cual: su ruta
> usa `${CLAUDE_PROJECT_DIR}` y está diseñada para esta raíz.
>
> ```json
> {
>   "permissions": {
>     "deny": ["mcp__atlassian__transitionJiraIssue"],
>     "ask": [
>       "mcp__atlassian__addCommentToJiraIssue",
>       "mcp__atlassian__createJiraIssue",
>       "mcp__atlassian__editJiraIssue",
>       "mcp__atlassian__createConfluencePage",
>       "mcp__atlassian__updateConfluencePage",
>       "mcp__notion__notion-create-pages",
>       "mcp__notion__notion-update-page"
>     ]
>   }
> }
> ```
>
> Los nombres de las tools asumen servers llamados `atlassian` y `notion` (como en `.mcp.json`).
> Si los renombras, ajusta los prefijos `mcp__<server>__*` en `.claude/settings.json`.

### 5b. Cursor

```bash
./install.sh --agent cursor
```

Fusiona los hooks en `~/.cursor/hooks.json` y los servers MCP en `~/.cursor/mcp.json` sin pisar lo
que ya tengas (hace backup con timestamp de todo lo que toca), y sincroniza la rule en
`.cursor/rules/qa-harness.mdc` **dentro de este repo**: Cursor lee las rules del proyecto, no de
`~/.cursor/rules/`. Por eso hay que abrir Cursor en la raíz de este repo.

Después: reinicia Cursor, autentica el MCP de Atlassian y ábrelo en la raíz del repo.

Dos diferencias respecto a Claude Code, explicadas en detalle en
[`adapters/cursor/README.md`](./adapters/cursor/README.md):

- El hook de MCP solo puede **denegar**, no preguntar. La confirmación interactiva la pone el
  allowlist de herramientas MCP de Cursor: **no marques las herramientas de escritura como "siempre
  permitir"**, o el hook queda como única defensa.
- El chequeo post-edición no puede bloquear: deja una marca y la levanta como `ask` en el siguiente
  comando de shell. Lo que el agente escribe **por la terminal** se revisa aparte, y el error le
  llega en el mismo turno como contexto (`additional_context`), sin bloquear.

### 5c. Antigravity (Gemini)

```bash
.Fusiona hooks y servers MCP en `~/.gemini/config/` sin pisar lo que ya tengas (backup con
timestamp) y **copia** cada skill en `~/.gemini/config/skills/`, la carpeta global de donde
Antigravity lee las skills (a través de un symlink no puede: su política de workspace se lo niega).
La fuente es la misma `skills/` de este repo, pero la copia es una foto: **si editás una skill,
volvé a correr `./install.sh --agent antigravity`**; `./validate-config.sh` avisa si alguna copia
quedó desactualizada. Lo ajeno que ya haya en esa carpeta no se toca (ver
`adapters/antigravity/README.md`, *Cómo llegan las skills*, con la prueba en vivo).

as skills*, con la prueba en vivo).

Y sincroniza la rule en `.agents/rules/qa-harness.md` **dentro de este repo**: igual que Cursor,
Antigravity lee las reglas del workspace, no de tu HOME. Por eso hay que abrir Antigravity en la
raíz de este repo. **Tu `~/.gemini/GEMINI.md` no se toca**: es tuyo, y pisarlo no tiene vuelta
atrás. Después de reiniciar, comprueba en la UI que la rule quede activa (*Always on*): la sintaxis
para fijar el modo de activación desde el archivo no está documentada, así que el harness no la
adivina.

Deja además un archivo propio en tu HOME: `~/.gemini/qa-harness-state.json` (puedes cambiar la ruta
con la variable `QA_HARNESS_STATE`). Ahí el harness anota qué ruta de skills registró, para poder
retirar **esa misma** entrada cuando reinstales desde otro lugar en vez de dejar dos. Es el cuarto
archivo que una instalación de Antigravity deja fuera del repo, junto con los tres de
`~/.gemini/config/`.

Después: reinicia Antigravity y autentica el MCP de Atlassian.

Tres diferencias, explicadas en detalle en
[`adapters/antigravity/README.md`](./adapters/antigravity/README.md):

- No hay bloque de permisos: el hook devuelve `deny` para las transiciones de Jira y `force_ask`
  para toda escritura externa. `force_ask` ignora el "siempre permitir", así que cada publicación se
  confirma.
- El chequeo post-edición avisa un turno después, vía un segundo hook. Y **no cubre lo que el
  agente escribe por la terminal** (`run_command`): el hook no trae un id por llamada que una el
  antes con el después del comando.
- **Los nombres de las tools MCP no están documentados.** Los hooks las reconocen por patrón y
  anotan en `~/.gemini/qa-harness-unknown-tools.log` cualquier tool que huela a Atlassian o Notion y
  no haya matcheado. Este paso hay que cerrarlo a mano la primera vez: pide una lectura y un
  comentario en Jira, mira el log y, si aparece algo, agrega esa tool al catálogo en
  **`core/gates/catalogo.py`**. Es el único lugar donde se tocan: el catálogo es compartido, así que
  todos los runtimes heredan el cambio. No edites los hooks de `adapters/`.

> **Limitación conocida de Antigravity.** Hay un límite documentado de 12.000 caracteres por archivo
> de reglas, y las dos skills más grandes del método lo superaban: se observó una listada por nombre
> que no llegó a cargarse. Ahora quedan por debajo —el detalle de cada paso vive en `references/`,
> dentro de la carpeta de la skill—, pero eso todavía no está verificado en una instalación real. La
> medición, lo que está y lo que no está probado, y el experimento que lo confirmaría, en [`adapters/antigravity/README.md`](./adapters/antigravity/README.md). Claude Code,
> Cursor y Codex no están afectados.

### 5d. Codex CLI

```bash
./install.sh --agent codex
```

Respeta `CODEX_HOME` (la misma variable que usa Codex; default `~/.codex`) y no toca nada que no sea
suyo, con backup con timestamp de cada archivo que cambia:

- **Hooks** en `~/.codex/hooks.json`: agrega los tres del harness **al final** de cada evento; los
  tuyos quedan iguales y primero.
- **`~/.codex/config.toml`**: un bloque entre marcas `# >>> qa-harness-pro >>>` con el server MCP de
  Atlassian, la transición de estados fuera de la lista de tools y aprobación obligatoria en cada
  escritura. Tu TOML no se reescribe: el bloque se agrega o se reemplaza, y el resultado se valida
  antes de escribirlo. Si ya tienes tu propio `[mcp_servers.atlassian]`, no se agrega (duplicarlo
  rompería el TOML): te dice qué sumar a mano y sale con error.
- **`~/.codex/AGENTS.md`**: otro bloque entre marcas, corto, que apunta al `AGENTS.md` de este repo.
  Tu contenido queda intacto.
- **Skills**: un symlink por skill en `~/.agents/skills`, donde Codex las lee de forma nativa.

Después, **un paso que no se puede saltar**: abre Codex, corre `/hooks` y confía en los tres hooks
del harness. Codex no corre un hook que no aprobaste, y no avisa: sin ese paso no hay gate. Luego
`codex mcp login atlassian` y abre Codex **en la raíz de este repo**.

Dos diferencias, explicadas en detalle en [`adapters/codex/README.md`](./adapters/codex/README.md),
junto con una prueba en vivo de los tres gates con objetivos inofensivos:

- El hook no puede pedir confirmación, solo denegar. La confirmación la pone `config.toml`
  (`approval_mode = "prompt"` en cada escritura), y la transición ni se le ofrece al modelo.
- El chequeo post-edición avisa en el momento, pero no puede impedir la edición (un deny previo
  sobre `apply_patch` no se respeta en Codex: openai/codex#27833).

---

## 6. Verifica que quedó vivo

### 6a. Que las reglas te llegan

**Este paso no es opcional.** Escribe en un chat nuevo, como única palabra:

```
PING-HARNESS
```

Tiene que responder `PONG <empresa> <backend> <destino>` con los valores de tu config, y nada más.

Si contesta cualquier otra cosa, el método te llegó pero **las reglas no**. Es la falla más
traicionera del harness, porque el análisis igual sale — y sale bien. Lo que se pierde en silencio
es que te muestre el borrador antes de publicar, que no toque estados de Jira y que no invente
datos. Revisa que hayas reiniciado la herramienta y que la abriste en la raíz del repo.

### 6b. Que el gate muerde

Pídele que publique un comentario en Jira que contenga el texto `PON-AQUI-EL-ID`. Tiene que
**bloquearlo**.

Si lo publica, el hook no está enganchado: los hooks se leen al arrancar, así que reinicia la
herramienta y vuelve a probar. Un gate desconectado no avisa que lo está. Simplemente deja pasar
todo.

### 6c. Que el método funciona

Abre el ticket de ejemplo en [`demo/`](./demo/) y pídele al agente que lo analice. Está incompleto a
propósito: deberías ver un gate ⚠️ con observaciones y una tanda de casos de prueba. No publica nada
en ningún lado.

> Regla del harness: nada se publica sin tu confirmación. El agente propone; tú decides.

---

## Siguiente paso

- ¿Vas a sumar a otro QA? [`ONBOARDING.md`](./ONBOARDING.md) es la guía de ~15 minutos.
- ¿Quieres entender el flujo completo? [`docs/METODO.md`](./docs/METODO.md).
- ¿Tu equipo no usa Jira/Confluence/Notion? [`docs/ADAPTAR-OTRO-STACK.md`](./docs/ADAPTAR-OTRO-STACK.md).
