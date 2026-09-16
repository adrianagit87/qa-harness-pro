# SETUP — de clonar a "funciona"

Seis pasos. No necesitas saber programar; sí tener instalada una de las tres herramientas
soportadas: **Claude Code**, **Cursor** o **Antigravity (Gemini)**.

Los pasos 1 a 4 son iguales para las tres. El paso 5 cambia según cuál uses. Puedes instalar más de
una: comparten las mismas skills y la misma configuración.

**Necesitas también:** `python3` (los hooks son scripts de Python) y, si vas a instalar para Cursor
o Antigravity, `jq` (los instaladores fusionan JSON con él).

## 1. Clona y entra

```bash
git clone https://github.com/adrianagit87/qa-harness-pro.git ~/Proyectos/qa-harness-pro
cd ~/Proyectos/qa-harness-pro
```

> Déjalo en un lugar **permanente**. La instalación crea enlaces y rutas absolutas que apuntan acá:
> si después mueves o borras la carpeta, el harness deja de funcionar.

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
No mira solo el formato: valida que tu tracker sea coherente (v1 = Jira; `browseUrlPattern` con
tu host real) y que los archivos versionados sigan prometiendo lo que el README promete —
`.claude/settings.json` con el deny de `transitionJiraIssue`, las escrituras en `ask` y los hooks
que bloquean comandos destructivos, validan ediciones y revisan publicaciones externas, y
`.mcp.json` con los servers MCP oficiales. Si alguien los vació o los rompió, acá lo ves.

Vale correrlo de nuevo **después** del paso 5: también verifica que las skills quedaron enlazadas
de verdad (symlinks que resuelven a este repo, no rotos ni apuntando a otro lado).

> **Qué cubre y qué no.** La config de empresa y perfil las valida para cualquier herramienta. La
> capa de seguridad que inspecciona es la de **Claude Code** (`.claude/settings.json` y `.mcp.json`).
> Para Cursor y Antigravity, la verificación equivalente son los pasos 6a y 6b de más abajo: ahí se
> comprueba, en vivo, que las reglas llegan y que el gate muerde.

## 5. Instala para tu herramienta

### 5a. Claude Code

```bash
./install.sh
```

Enlaza las skills en `~/.claude/skills` y, si todavía no tienes uno, copia `claude/CLAUDE.md` como
`~/.claude/CLAUDE.md` (si ya tienes el tuyo, no lo toca). Los servers MCP ya vienen definidos en
**`.mcp.json`**, versionado en el repo: no contiene ningún secreto, la autenticación es OAuth en el
navegador. No hay nada que copiar.

Después, abre Claude Code **en la raíz de este repo**:

- La primera vez te pedirá **confiar en el workspace** (el diálogo de trust) y **aprobar los servers
  de `.mcp.json`** (`atlassian` y `notion`). Acepta ambos: sin el trust, Claude Code ignora los
  permisos `allow` de `.claude/settings.json` y el harness pierde parte de su configuración de
  seguridad. Después autentica en el navegador (Jira y Confluence vía Atlassian; Notion solo si tu
  `docs.backend` es `notion`). Sin pegar tokens.
- ¿Ya tienes skills con estos mismos nombres de otra instalación en `~/.claude/skills`?
  `install.sh` las respalda con timestamp antes de enlazar (no pierde nada), pero si quieres
  probar el harness sin tocar tu setup, usa `CLAUDE_DIR=/otra/ruta ./install.sh` y abre Claude
  Code con `CLAUDE_CONFIG_DIR=/otra/ruta`.
- Los permisos del harness viven en **`.claude/settings.json`** (también versionado): lectura de
  Jira/Confluence/Notion permitida, escritura hacia afuera siempre pregunta, y cambiar estados de
  Jira (`transitionJiraIssue`) **denegado**.
- En ese mismo archivo viven los tres hooks deterministas: antes de `Bash` se bloquean los comandos
  destructivos; después de cada `Edit` o `Write` se valida el archivo modificado (sintaxis y unit
  tests para Python, `bash -n` para shell, `json.tool` para JSON) y el error vuelve al agente como
  feedback; y antes de escribir en Jira, Confluence o Notion se rechazan los payloads vacíos,
  demasiado cortos o con placeholders. Solo se activan en sesiones abiertas desde esta raíz, porque
  apuntan a los scripts versionados en `hooks/`.

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
./cursor/install-cursor.sh
```

Fusiona los hooks en `~/.cursor/hooks.json` y los servers MCP en `~/.cursor/mcp.json` sin pisar lo
que ya tengas (hace backup con timestamp de todo lo que toca), y sincroniza la rule en
`.cursor/rules/qa-harness.mdc` **dentro de este repo**: Cursor lee las rules del proyecto, no de
`~/.cursor/rules/`. Por eso hay que abrir Cursor en la raíz de este repo.

Después: reinicia Cursor, autentica el MCP de Atlassian y ábrelo en la raíz del repo.

Dos diferencias respecto a Claude Code, explicadas en detalle en
[`cursor/README.md`](./cursor/README.md):

- El hook de MCP solo puede **denegar**, no preguntar. La confirmación interactiva la pone el
  allowlist de herramientas MCP de Cursor: **no marques las herramientas de escritura como "siempre
  permitir"**, o el hook queda como única defensa.
- El chequeo post-edición no puede bloquear: deja una marca y la levanta como `ask` en el siguiente
  comando de shell.

### 5c. Antigravity (Gemini)

```bash
./antigravity/install-antigravity.sh
```

Fusiona hooks, servers MCP y el registro de skills en `~/.gemini/config/` sin pisar lo que ya tengas
(backup con timestamp). Las skills son **las mismas**: `skills.json` apunta al directorio `skills/`
de este repo, así que una edición se ve desde las tres herramientas.

Después: reinicia Antigravity y autentica el MCP de Atlassian.

Tres diferencias, explicadas en detalle en [`antigravity/README.md`](./antigravity/README.md):

- No hay bloque de permisos: el hook devuelve `deny` para las transiciones de Jira y `force_ask`
  para toda escritura externa. `force_ask` ignora el "siempre permitir", así que cada publicación se
  confirma.
- El chequeo post-edición avisa un turno después, vía un segundo hook.
- **Los nombres de las tools MCP no están documentados.** Los hooks las reconocen por patrón y
  anotan en `~/.gemini/qa-harness-unknown-tools.log` cualquier tool que huela a Atlassian o Notion y
  no haya matcheado. Este paso hay que cerrarlo a mano la primera vez: pide una lectura y un
  comentario en Jira, mira el log, y ajusta los patrones de
  `antigravity/hooks/validate-external-write.py` si aparece algo.

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
