# 🧰 QA Harness Pro

**Convierte tu IA en un compañero de QA real: le das tus herramientas, tu método y tus reglas, y lo diriges.**

**Recurso gratuito y de código abierto para la comunidad QA.**

Esto no es un pack de prompts para copiar y pegar. Es un **harness**: el andamiaje que rodea al modelo y lo transforma de "un chat que responde suelto" en un agente que analiza tickets, diseña casos, cierra ciclos y documenta — con TU forma de trabajar, conectado a TUS herramientas.

Funciona con **Claude Code**, **Cursor**, **Antigravity (Gemini)** y **Codex CLI**. Hay **un solo
instalador** y eliges la herramienta con `--agent`; las skills, la config de tu empresa y tu perfil
son los mismos archivos para los cuatro.

---

## 🚀 Empezar

**1. Clona el repo** y déjalo en un lugar permanente (la instalación crea enlaces que apuntan acá):

```bash
git clone https://github.com/adrianagit87/qa-harness-pro.git
cd qa-harness-pro
```

**2. Configura tu empresa y tu perfil.** Cada campo está explicado en [`docs/CONFIG.md`](./docs/CONFIG.md).

```bash
cp companies/_template.json companies/<tu-empresa>.json   # y complétalo
cp profile/profile.example.json profile/profile.json      # tu nombre, tu rol y tu activeCompany
```

**3. Valida la config** antes de que nada falle en uso real:

```bash
./validate-config.sh
```

**4. Instala para tu herramienta**, reiníciala y ábrela **en la raíz de este repo**:

| Si usas… | Instalas con | Detalle |
| --- | --- | --- |
| Claude Code | `./install.sh --agent claude` | [`SETUP.md`](./SETUP.md) |
| Cursor | `./install.sh --agent cursor` | [`adapters/cursor/README.md`](./adapters/cursor/README.md) |
| Antigravity (Gemini) | `./install.sh --agent antigravity` | [`adapters/antigravity/README.md`](./adapters/antigravity/README.md) |
| Codex CLI | `./install.sh --agent codex` | [`adapters/codex/README.md`](./adapters/codex/README.md) — **después, `/hooks` en Codex es obligatorio** |
| Las cuatro a la vez | `./install.sh --agent all` | las cuatro guías de arriba |

> `--agent` es obligatorio y no tiene default: `./install.sh` a secas imprime la ayuda y sale con
> error. Instalar "para Claude" a quien vino por Cursor sería un éxito falso. `./install.sh --help`
> lista los valores válidos.

**5. Pruébalo sin tocar nada real.** En un chat nuevo:

```
Analiza el ticket de demo/ticket-ejemplo.md
```

El ticket de demo está incompleto a propósito: deberías ver un gate ⚠️ con observaciones y unos 20
casos de prueba. No publica nada en ningún lado. Con tu config lista, el día a día es
`Analiza PROJ-1234` o `Cierre STG PROJ-1234`.

> Si moviste el repo o lo clonaste de nuevo, vuelve a correr el instalador desde la ruta nueva:
> **reemplaza** las entradas de la instalación anterior en vez de acumularlas. Y `validate-config.sh`
> te avisa con un error si algo instalado quedó apuntando a otro clon o a una ruta que ya no existe.

> 📚 **Antes de usarlo en serio, revisa la documentación.** [`SETUP.md`](./SETUP.md) tiene el paso a
> paso completo: la autenticación de los MCP y las verificaciones de que las reglas y los gates
> quedaron enganchados. [`ONBOARDING.md`](./ONBOARDING.md) es la guía de ~15 minutos para sumar a
> otro QA, y [`docs/`](./docs/) explica el método y la config en detalle.

---

## 🧠 Loop, goal y harness — el modelo detrás

Tres conceptos que no inventó la IA: los inventó el testing. Este recurso los pone a trabajar para ti.

| Concepto    | Qué es                                                            | Acá lo usas para…                                        |
| ----------- | ----------------------------------------------------------------- | -------------------------------------------------------- |
| **Harness** | El arnés que rodea al que ejecuta (tu agente) y lo hace rendir    | Envolver a tu IA con tus tools, tu método y tus reglas   |
| **Goal**    | El criterio verificable de "terminó y lo hizo bien" (el oráculo)  | Que el agente sepa cuándo un análisis/cierre está completo |
| **Loop**    | Percibir → razonar → actuar → observar → repetir                  | Que el agente itere hasta cumplir, y tú supervises        |

Tú das el objetivo y diriges. La IA ejecuta dentro del harness. El humano siempre lidera.

---

## 🏗️ La decisión de diseño: MÉTODO vs CONFIG

Lo que hace que este harness sea TUYO sin atarte a una empresa:

```
MÉTODO  (skills/)              →  cómo trabajas como QA. Portable. No cambia de empresa.
CONFIG  (companies/<empresa>)  →  los datos de tu empresa. Intercambiable en un archivo.
PERFIL  (profile/)             →  quién eres tú (nombre, rol, tono). Tu identidad.
```

**El día que cambies de empresa:** copias `companies/_template.json`, lo completas, cambias `activeCompany` en tu perfil — y no tocas ni una skill. Tu método te sigue toda la carrera.

Ese mismo corte es el que permite los cuatro runtimes: lo que cambia entre Claude Code, Cursor,
Antigravity y Codex es la capa de adaptación (hooks y MCP), nunca el método.

---

## 🧩 El método: 6 skills

| Skill | Qué hace |
| --- | --- |
| `qa-generacion-casos` | Casos de prueba desde un requerimiento o documento, sin ticket. QA antes de la historia. |
| `qa-analisis-ticket` | **El corazón.** Gate de calidad del ticket → casos + matriz de riesgos → documentación. |
| `qa-automatizacion` | Fase opcional: veredicto "¿vale la pena?" + código integrado a tu suite. |
| `qa-cierre-ciclo` | Cierre de ciclo en **cualquier** ambiente de tu config: métricas + comentario en Jira + doc actualizada. |
| `qa-cierre-prod` | Cierre formal del ambiente final, con página de cierre separada. |
| `qa-baseline` | Opcional: baseline del proyecto, alimentado solo por casos ✅ Pass del ambiente final, con trazabilidad por regla. Apagado por defecto. |

Los ambientes no están hardcodeados: salen de `environments` en tu `companies/<empresa>.json`. Si tu
equipo prueba solo en staging, declaras solo staging. El flujo completo, en
[`docs/METODO.md`](./docs/METODO.md).

---

## 📂 Estructura

```
qa-harness-pro/
├── README.md                 ← esto
├── SETUP.md                  ← de clonar a "funciona", paso a paso
├── ONBOARDING.md             ← sumar a otro QA al harness en ~15 minutos
├── AGENTS.md                 ← las reglas del agente, en formato neutral
├── LICENSE                   ← MIT
├── install.sh                ← el único instalador: --agent <claude|cursor|antigravity|codex|all>
├── validate-config.sh        ← el gate del harness: chequea tu config y los 4 runtimes (--agent)
├── .gitignore
├── .mcp.json                 ← herramientas: Jira/Confluence + Notion — MCP remotos, sin secretos
├── .claude/
│   └── settings.json         ← permisos + hooks (aplican al abrir Claude Code en esta carpeta)
├── .cursor/
│   └── rules/qa-harness.mdc  ← la rule en scope de proyecto (Cursor solo lee esta ruta)
├── .github/
│   └── workflows/ci.yml      ← los unit tests de los hooks en cada push
├── core/                     ← la lógica de los 3 gates, escrita una sola vez
│   ├── gates/                ← contract.py · catalogo.py · destructivos.py · post_edicion.py · post_shell.py · publicacion.py
│   └── texto.py              ← normalización de texto compartida por los gates
├── adapters/                 ← lo único que cambia entre herramientas: el puente a cada runtime
│   ├── claude/               ← adaptador de Claude Code
│   │   ├── CLAUDE.md         ← importa AGENTS.md + lo específico de Claude Code
│   │   └── hooks/            ← _claude.py + los 3 gates (post-edit también por shell)
│   │       ├── block-destructive-command.py ← PreToolUse: frena comandos destructivos
│   │       ├── check-after-edit.py          ← PostToolUse: valida archivos editados
│   │       ├── snapshot-before-shell.py     ← PreToolUse Bash: foto del disco antes del comando
│   │       ├── check-after-shell.py         ← PostToolUse(Failure) Bash: valida lo que escribió el comando
│   │       └── validate-external-write.py   ← PreToolUse: revisa payloads antes de publicar
│   ├── cursor/               ← adaptador de Cursor
│   │   ├── README.md
│   │   ├── config/           ← hooks.json · mcp.json
│   │   ├── hooks/            ← _cursor.py + los 3 gates (post-edit también por shell)
│   │   └── rules/qa-harness.mdc ← fuente de la rule que se copia a .cursor/rules/
│   ├── antigravity/          ← adaptador de Antigravity (Gemini)
│   │   ├── README.md · GEMINI.md
│   │   ├── config/           ← hooks.json · mcp_config.json
│   │   ├── copias_skills.py  ← copia las skills a ~/.gemini/config/skills y detecta copias viejas
│   │   └── hooks/            ← _agy.py + los 3 gates + surface-pending-check.py
│   └── codex/                ← adaptador de Codex CLI
│       ├── README.md · AGENTS.md ← AGENTS.md: el bloque que apunta al AGENTS.md del repo
│       ├── bloque_gestionado.py  ← agrega/reemplaza un bloque entre marcas en config.toml y AGENTS.md
│       ├── config/           ← hooks.json · mcp.toml (server atlassian + aprobación por tool)
│       └── hooks/            ← _codex.py + los 3 gates (post-edit también por shell)
├── skills/                   ← el MÉTODO (las 6 skills + README)
├── profile/
│   └── profile.example.json  ← tu identidad: nombre, rol, tono
├── companies/
│   └── _template.json        ← config de tu empresa (tracker + ambientes + docs + automatización)
├── templates/                ← test plan · bug report · análisis · cierre · matriz de riesgos · los 3 formatos de salida que usan las skills
├── assets/                   ← cheat sheet · 5 errores con IA · gate de calidad · árbol automatizar/no · antes y después
├── demo/                     ← un ticket de ejemplo para verlo funcionar el día 1
├── docs/
│   ├── CONFIG.md             ← cada campo de configuración, explicado
│   ├── METODO.md             ← el flujo completo y los principios detrás
│   └── ADAPTAR-OTRO-STACK.md ← qué tocar si tu stack (o tu runtime) no es el soportado
└── tests/                    ← smoke.sh + unit tests de los hooks de los cuatro runtimes
```

> `companies/*.json` y `profile/profile.json` están en `.gitignore`: los datos de tu empresa nunca
> entran al historial de git. Lo que se versiona es el template.

> Cada adaptador tiene un shim (`_claude.py`, `_cursor.py`, `_agy.py`, `_codex.py`) que pone `core/` en el
> `sys.path` de los hooks. La raíz del harness no se calcula contando niveles de directorio: se
> busca subiendo hasta la marca `core/gates/contract.py`. Por eso un archivo se puede mover de
> carpeta sin que los hooks dejen de encontrar el núcleo en silencio.

---

## 🛑 Quality gates deterministas

Las reglas escritas orientan al agente. Los hooks ponen límites que no dependen de que el modelo
recuerde obedecerlos. Son tres, y existen en los cuatro runtimes (`adapters/claude/hooks/`,
`adapters/cursor/hooks/`, `adapters/antigravity/hooks/`, `adapters/codex/hooks/`), con unit tests
para cada uno.

**1. Comandos destructivos.** Corre antes de cada ejecución de shell e inspecciona el comando
completo. Son cuatro reglas, y las banderas importan — el detalle exacto vive en
`core/gates/destructivos.py`:

| Bloquea | Condición exacta |
|---|---|
| `rm` | recursivo **y** forzado a la vez (`-rf`, `-r -f`, `--recursive --force`…). `rm -r` solo, o `rm -f` solo, pasa. |
| `git reset --hard` | siempre |
| `git clean` | forzado **y** sobre directorios (hacen falta `-f` **y** `-d`), salvo que lleve `-n` / `--dry-run` |
| `git push` forzado | `--force`, `--force-with-lease`, `--force-if-includes` o `-f` |

Un comando seguro no recibe aprobación automática: sigue el flujo normal de permisos de la
herramienta. El gate falla cerrado si recibe una entrada vacía o inválida, y se prueba sin ejecutar
ninguno de los comandos peligrosos: las pruebas solo le pasan strings al hook.

**2. Chequeo post-edición.** Corre después de cada edición de archivo y aplica el chequeo rápido que
corresponde: sintaxis + unit tests para Python, `bash -n` para shell y `json.tool` para JSON.
Markdown y otros archivos sin un verificador determinista se ignoran.

Un agente también escribe por la terminal (`printf '{"a": }' > x.json`, `sed -i`, un script que
genera archivos), y eso no pasa por la herramienta de edición. En Claude Code, Cursor y Codex el
gate cubre también ese camino: antes de cada comando se saca una foto de lo que el gate gobierna
(`git ls-files -m -o --exclude-standard` en la raíz, más el baseline configurado) y después se
revisa cada archivo que **ese** comando creó o modificó (`core/gates/post_shell.py`). Sin foto de
antes (raíz que no es un repo git, hook que no corrió), se abstiene en silencio: nunca valida el
repo entero a ciegas. Lo que un comando mandado a segundo plano escribe después de que el runtime
lo da por terminado no se ve. En **Antigravity** este camino **no está cubierto** (ver la tabla).

**3. Validación de publicaciones.** Corre antes de escribir en Jira, Confluence o Notion. Rechaza
publicaciones vacías, demasiado cortas o con placeholders de alta confianza (`PON-AQUI`, `{{...}}`,
`<TICKET>`, etc.). Este gate no reemplaza la decisión humana: comprueba **si el payload está listo**
para publicarse, no **si autorizas** la escritura.

### Qué cambia según la herramienta

| | Claude Code | Cursor | Antigravity | Codex CLI |
| --- | --- | --- | --- | --- |
| Permisos | bloque `permissions` en `.claude/settings.json`: lectura en `allow`, escrituras externas en `ask`, `transitionJiraIssue` en `deny` | el hook de MCP solo puede `deny`; la confirmación interactiva la pone el allowlist de MCP de Cursor | no hay bloque de permisos: el hook devuelve `deny` / `force_ask` (`force_ask` ignora el "siempre permitir") | el hook solo puede `deny`; en `config.toml`, `disabled_tools` saca la transición y `approval_mode = "prompt"` pide confirmación en cada escritura. Los hooks corren solo después de aprobarlos en `/hooks` |
| Gate post-edición | devuelve el error al agente en el momento | el hook `afterFileEdit` no puede bloquear: deja una marca que se levanta como `ask` en el siguiente comando de shell | el `PostToolUse` no tiene canal de feedback: un segundo hook levanta la marca en la llamada siguiente | `PostToolUse` devuelve el error al agente en el momento, por cada archivo del patch (no puede impedir la edición: openai/codex#27833) |
| Post-edición de lo que escribe la terminal | `PreToolUse`/`PostToolUse` sobre `Bash`: el error vuelve como `block`; si el comando falló (exit ≠ 0), como contexto en `PostToolUseFailure` | `preToolUse`/`postToolUse`/`postToolUseFailure` con matcher `Shell`: el error vuelve como `additional_context` en el mismo turno (no bloquea). Enganchado según las docs y el bundle de Cursor 3.21.9; **sin probar todavía en una sesión real** | **no cubierto**: el hook no trae un id por llamada que una el antes con el después, y el `PostToolUse` no tiene canal de vuelta. Detalle en [`adapters/antigravity/README.md`](./adapters/antigravity/README.md) | `PreToolUse`/`PostToolUse` sobre `Bash`: el error vuelve como `block` |
| Nombres de tools MCP | conocidos y fijos (`mcp__atlassian__*`, `mcp__notion__*`) | conocidos (`tool_name` / `tool_input`) | sin documentar: se reconocen por patrón y las no reconocidas se anotan en un log para cerrarlas a mano | `mcp__<server>__<tool>`, igual que Claude Code |
| Tamaño de las skills | sin límite conocido | sin límite conocido | **limitación conocida:** hay un límite documentado de 12.000 caracteres por archivo de reglas, y las dos skills más grandes lo superaban — se observó una listada que no llegó a cargarse. Ahora quedan por debajo: el detalle de cada paso se movió textual a `references/` dentro de la carpeta de la skill, sin recortar método. **Todavía no está verificado en una instalación real.** Medición, alcance e incertidumbre en [`adapters/antigravity/README.md`](./adapters/antigravity/README.md) | sin límite conocido; las skills se leen nativas desde `~/.agents/skills` |

El detalle de cada adaptador, con las diferencias exactas y cómo verificarlas, está en
[`adapters/cursor/README.md`](./adapters/cursor/README.md),
[`adapters/antigravity/README.md`](./adapters/antigravity/README.md) y
[`adapters/codex/README.md`](./adapters/codex/README.md).

### Limitación conocida: las plantillas no viajan con las skills

Las skills se registran por ruta **absoluta** (`{{HARNESS}}/skills`) justamente para que funcionen
con la herramienta abierta en otra carpeta. Los punteros a `templates/` que hay adentro de
`qa-analisis-ticket` y `qa-cierre-ciclo`, en cambio, son **relativos a la raíz de este repo**.

O sea: trabajando fuera del harness, la skill carga y la plantilla no. El agente lee el método
completo pero no encuentra el formato literal de salida.

No lo resolvimos de forma automática a propósito. Renderizar la ruta absoluta adentro del `SKILL.md`
al instalar volvería a esas dos skills archivos generados —hoy se editan y se versionan a mano— y en
Antigravity les comería el margen que tienen bajo el límite de 12.000 caracteres. Volver a pegar las
plantillas en línea es lo que acabamos de deshacer, por lo mismo.

Mientras tanto los punteros dicen explícitamente que la ruta es relativa al repo del harness, y las
skills piden la ruta antes que improvisar el formato. **Si trabajas fuera del harness y el agente no
encuentra una plantilla, pásale la ruta absoluta del repo.**

> **Verifica que el gate muerde.** Pídele al agente que publique un comentario en Jira que contenga
> `PON-AQUI-EL-ID`: tiene que bloquearlo. Un gate desconectado no avisa que lo está; simplemente
> deja pasar todo.

---

## 🎯 Alcance (v2)

- **Tracker:** Jira. `validate-config.sh` rechaza cualquier otro `tracker.type`.
- **Documentación:** eliges el backend en tu config con `docs.backend`:
  - `"jira"` — el análisis va a la descripción de un ticket de QA contenedor y cada caso es un issue hijo.
  - `"confluence"` — recomendado si tu equipo es Atlassian puro: viene en el mismo MCP que Jira, así que necesitas un solo conector.
  - `"notion"` — requiere además el MCP de Notion.
- **Ambientes:** los que declares en `environments`. Uno solo, o los que uses.
- **Runtimes:** Claude Code, Cursor, Antigravity (Gemini) y Codex CLI.
- ¿Tu equipo usa otras herramientas, o quieres sumar otro runtime? [`docs/ADAPTAR-OTRO-STACK.md`](./docs/ADAPTAR-OTRO-STACK.md) te dice exactamente qué tocar y cuánto cuesta.
- El harness **documenta, no mueve estados**: las transiciones de Jira las haces tú, a mano.

---

## 🤝 Usar, adaptar y compartir

Puedes usar, modificar y redistribuir QA Harness Pro bajo la [licencia MIT](./LICENSE).
Si encuentras un problema o quieres proponer una mejora, abre un issue o un pull request en
[GitHub](https://github.com/adrianagit87/qa-harness-pro).
