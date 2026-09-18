# 🧰 QA Harness Pro

**Convierte tu IA en un compañero de QA real: le das tus herramientas, tu método y tus reglas, y lo diriges.**

**Recurso gratuito y de código abierto para la comunidad QA.**

Esto no es un pack de prompts para copiar y pegar. Es un **harness**: el andamiaje que rodea al modelo y lo transforma de "un chat que responde suelto" en un agente que analiza tickets, diseña casos, cierra ciclos y documenta — con TU forma de trabajar, conectado a TUS herramientas.

Funciona con **Claude Code**, **Cursor** y **Antigravity (Gemini)**. Hay **un solo instalador** y
eliges la herramienta con `--agent`; las skills, la config de tu empresa y tu perfil son los mismos
archivos para los tres.

| Si usas… | Instalas con | Detalle |
| --- | --- | --- |
| Claude Code | `./install.sh --agent claude` | [`SETUP.md`](./SETUP.md) |
| Cursor | `./install.sh --agent cursor` | [`adapters/cursor/README.md`](./adapters/cursor/README.md) |
| Antigravity (Gemini) | `./install.sh --agent antigravity` | [`adapters/antigravity/README.md`](./adapters/antigravity/README.md) |
| Las tres a la vez | `./install.sh --agent all` | las tres guías de arriba |

> `--agent` es obligatorio y no tiene default: `./install.sh` a secas imprime la ayuda y sale con
> error. Instalar "para Claude" a quien vino por Cursor sería un éxito falso. `./install.sh --help`
> lista los valores válidos.

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

Ese mismo corte es el que permite los tres runtimes: lo que cambia entre Claude Code, Cursor y
Antigravity es la capa de adaptación (hooks y MCP), nunca el método.

---

## 🧩 El método: 5 skills

| Skill | Qué hace |
| --- | --- |
| `qa-generacion-casos` | Casos de prueba desde un requerimiento o documento, sin ticket. QA antes de la historia. |
| `qa-analisis-ticket` | **El corazón.** Gate de calidad del ticket → casos + matriz de riesgos → documentación. |
| `qa-automatizacion` | Fase opcional: veredicto "¿vale la pena?" + código integrado a tu suite. |
| `qa-cierre-ciclo` | Cierre de ciclo en **cualquier** ambiente de tu config: métricas + comentario en Jira + doc actualizada. |
| `qa-cierre-prod` | Cierre formal del ambiente final, con página de cierre separada. |

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
├── install.sh                ← el único instalador: --agent <claude|cursor|antigravity|all>
├── validate-config.sh        ← el gate del harness: chequea tu config y los 3 runtimes (--agent)
├── .gitignore
├── .mcp.json                 ← herramientas: Jira/Confluence + Notion — MCP remotos, sin secretos
├── .claude/
│   └── settings.json         ← permisos + hooks (aplican al abrir Claude Code en esta carpeta)
├── .cursor/
│   └── rules/qa-harness.mdc  ← la rule en scope de proyecto (Cursor solo lee esta ruta)
├── .github/
│   └── workflows/ci.yml      ← los unit tests de los hooks en cada push
├── core/                     ← la lógica de los 3 gates, escrita una sola vez
│   ├── gates/                ← contract.py · catalogo.py · destructivos.py · post_edicion.py · publicacion.py
│   └── texto.py              ← normalización de texto compartida por los gates
├── adapters/                 ← lo único que cambia entre herramientas: el puente a cada runtime
│   ├── claude/               ← adaptador de Claude Code
│   │   ├── CLAUDE.md         ← importa AGENTS.md + lo específico de Claude Code
│   │   └── hooks/            ← _claude.py + los 3 gates
│   │       ├── block-destructive-command.py ← PreToolUse: frena comandos destructivos
│   │       ├── check-after-edit.py          ← PostToolUse: valida archivos editados
│   │       └── validate-external-write.py   ← PreToolUse: revisa payloads antes de publicar
│   ├── cursor/               ← adaptador de Cursor
│   │   ├── README.md
│   │   ├── config/           ← hooks.json · mcp.json
│   │   ├── hooks/            ← _cursor.py + los 3 gates
│   │   └── rules/qa-harness.mdc ← fuente de la rule que se copia a .cursor/rules/
│   └── antigravity/          ← adaptador de Antigravity (Gemini)
│       ├── README.md · GEMINI.md
│       ├── config/           ← hooks.json · mcp_config.json · skills.json
│       └── hooks/            ← _agy.py + los 3 gates + surface-pending-check.py
├── skills/                   ← el MÉTODO (las 5 skills + README)
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
└── tests/                    ← smoke.sh + unit tests de los hooks de los tres runtimes
```

> `companies/*.json` y `profile/profile.json` están en `.gitignore`: los datos de tu empresa nunca
> entran al historial de git. Lo que se versiona es el template.

> Cada adaptador tiene un shim (`_claude.py`, `_cursor.py`, `_agy.py`) que pone `core/` en el
> `sys.path` de los hooks. La raíz del harness no se calcula contando niveles de directorio: se
> busca subiendo hasta la marca `core/gates/contract.py`. Por eso un archivo se puede mover de
> carpeta sin que los hooks dejen de encontrar el núcleo en silencio.

---

## 🛑 Quality gates deterministas

Las reglas escritas orientan al agente. Los hooks ponen límites que no dependen de que el modelo
recuerde obedecerlos. Son tres, y existen en los tres runtimes (`adapters/claude/hooks/`,
`adapters/cursor/hooks/`, `adapters/antigravity/hooks/`), con unit tests para cada uno.

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

**3. Validación de publicaciones.** Corre antes de escribir en Jira, Confluence o Notion. Rechaza
publicaciones vacías, demasiado cortas o con placeholders de alta confianza (`PON-AQUI`, `{{...}}`,
`<TICKET>`, etc.). Este gate no reemplaza la decisión humana: comprueba **si el payload está listo**
para publicarse, no **si autorizas** la escritura.

### Qué cambia según la herramienta

| | Claude Code | Cursor | Antigravity |
| --- | --- | --- | --- |
| Permisos | bloque `permissions` en `.claude/settings.json`: lectura en `allow`, escrituras externas en `ask`, `transitionJiraIssue` en `deny` | el hook de MCP solo puede `deny`; la confirmación interactiva la pone el allowlist de MCP de Cursor | no hay bloque de permisos: el hook devuelve `deny` / `force_ask` (`force_ask` ignora el "siempre permitir") |
| Gate post-edición | devuelve el error al agente en el momento | el hook `afterFileEdit` no puede bloquear: deja una marca que se levanta como `ask` en el siguiente comando de shell | el `PostToolUse` no tiene canal de feedback: un segundo hook levanta la marca en la llamada siguiente |
| Nombres de tools MCP | conocidos y fijos (`mcp__atlassian__*`, `mcp__notion__*`) | conocidos (`tool_name` / `tool_input`) | sin documentar: se reconocen por patrón y las no reconocidas se anotan en un log para cerrarlas a mano |
| Tamaño de las skills | sin límite conocido | sin límite conocido | **limitación conocida:** hay un límite documentado de 12.000 caracteres por archivo de reglas, y las dos skills más grandes lo superan — pueden aparecer listadas y no llegar a cargarse. Sacar las plantillas de salida a `templates/` las achicó, pero **siguen por encima del límite**: lo que queda es método, no formato. Medición, alcance e incertidumbre en [`adapters/antigravity/README.md`](./adapters/antigravity/README.md) |

El detalle de cada adaptador, con las diferencias exactas y cómo verificarlas, está en
[`adapters/cursor/README.md`](./adapters/cursor/README.md) y
[`adapters/antigravity/README.md`](./adapters/antigravity/README.md).

### Limitación conocida: las plantillas no viajan con las skills

Las skills se registran por ruta **absoluta** (`{{HARNESS}}/skills`) justamente para que funcionen
con la herramienta abierta en otra carpeta. Los punteros a `templates/` que hay adentro de
`qa-analisis-ticket` y `qa-cierre-ciclo`, en cambio, son **relativos a la raíz de este repo**.

O sea: trabajando fuera del harness, la skill carga y la plantilla no. El agente lee el método
completo pero no encuentra el formato literal de salida.

No lo resolvimos de forma automática a propósito. Renderizar la ruta absoluta adentro del `SKILL.md`
al instalar volvería a esas dos skills archivos generados —hoy se editan y se versionan a mano— y en
Antigravity las empujaría todavía más arriba del límite de 12.000 caracteres que ya superan. Volver
a pegar las plantillas en línea es lo que acabamos de deshacer, por lo mismo.

Mientras tanto los punteros dicen explícitamente que la ruta es relativa al repo del harness, y las
skills piden la ruta antes que improvisar el formato. **Si trabajás fuera del harness y el agente no
encuentra una plantilla, pasale la ruta absoluta del repo.**

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
- **Runtimes:** Claude Code, Cursor y Antigravity (Gemini).
- ¿Tu equipo usa otras herramientas, o quieres sumar un cuarto runtime? [`docs/ADAPTAR-OTRO-STACK.md`](./docs/ADAPTAR-OTRO-STACK.md) te dice exactamente qué tocar y cuánto cuesta.
- El harness **documenta, no mueve estados**: las transiciones de Jira las haces tú, a mano.

---

## 🚀 Empezar

1. Clona el repo y déjalo en un lugar permanente (la instalación crea enlaces que apuntan acá).
2. `cp companies/_template.json companies/<tu-empresa>.json` y complétalo — cada campo está en
   [`docs/CONFIG.md`](./docs/CONFIG.md).
3. `cp profile/profile.example.json profile/profile.json` y pon tu nombre, tu rol y tu `activeCompany`.
4. `./validate-config.sh` — te dice qué falta antes de que nada falle en uso real.
5. Instala para tu herramienta con `./install.sh --agent <claude|cursor|antigravity|all>`,
   reiníciala y ábrela **en la raíz de este repo**.

> Si moviste el repo o lo clonaste de nuevo, vuelve a correr el instalador desde la ruta nueva:
> **reemplaza** las entradas de la instalación anterior en vez de acumularlas. Y `validate-config.sh`
> te avisa con un error si algo instalado quedó apuntando a otro clon o a una ruta que ya no existe.

El paso a paso completo, con la autenticación de los MCP y las verificaciones, está en
[`SETUP.md`](./SETUP.md). Si vas a sumar a otro QA al harness,
[`ONBOARDING.md`](./ONBOARDING.md) es la guía de ~15 minutos.

---

## 🤝 Usar, adaptar y compartir

Puedes usar, modificar y redistribuir QA Harness Pro bajo la [licencia MIT](./LICENSE).
Si encuentras un problema o quieres proponer una mejora, abre un issue o un pull request en
[GitHub](https://github.com/adrianagit87/qa-harness-pro).
