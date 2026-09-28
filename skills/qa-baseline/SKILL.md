---
name: qa-baseline
description: >
  Baseline del proyecto: una base de conocimiento local (.md) que se llena ticket a
  ticket SOLO con comportamiento verificado por casos ✅ Pass en el ambiente final, con
  trazabilidad por regla y reemplazo con historial. Dos modos: CONSOLIDAR (al final de un cierre
  aprobado en el ambiente `final: true`) y CONSULTAR (antes de la Fase 1 del análisis).
  Trigger: Automáticamente desde [[qa-cierre-ciclo]] / [[qa-cierre-prod]] (CONSOLIDAR) y desde
  [[qa-analisis-ticket]] (CONSULTAR), solo si `baseline.enabled` es `true` en la config. También
  cuando el usuario pide "consolidar TICKET-ID en el baseline" o "qué dice el baseline de [módulo]".
license: MIT
metadata:
  author: qa-harness-pro
  version: "1.0"
---

## When to Use

> ## ⚠️ GUARD — comprobar ANTES de hacer nada
>
> Esta skill solo opera si `companies/<empresa>.json` tiene el bloque `baseline` con
> `"enabled": true`. **Si el bloque no existe o está apagado, vuelve a la skill que te llamó sin
> hacer nada y sin mencionarlo.** El harness tiene que comportarse exactamente igual que sin esta
> función.

- **CONSOLIDAR** — la invocan [[qa-cierre-ciclo]] o [[qa-cierre-prod]] como último paso, después
  de publicar el cierre.
- **CONSULTAR** — la invoca [[qa-analisis-ticket]] antes de la Fase 1.
- El usuario la pide explícitamente con uno de los triggers de arriba.

## Configuración (cargar al inicio)

| Variable que usa la skill | Origen |
|---|---|
| Encendida o no | `baseline.enabled` (`true` = encendida; ausente o `false` = apagada) |
| Ruta del baseline (fuente única) | `baseline.path` — cualquier ruta: relativa (a la raíz del repo del harness), absoluta o con `~` |
| Módulos conocidos | `baseline.modules[]` — `code` (prefija los IDs) y `name` |
| Espejo | `baseline.mirror.backend` (`none` · `notion` · `confluence`) y `baseline.mirror.pageId` |
| Ambientes | `environments.list[]` — el que tiene `final: true` |

**Abre el baseline por su ruta directa**, no lo busques listando directorios: puede estar fuera
del proyecto, y la ruta por defecto (`baseline/`) está en `.gitignore` (mismo motivo que
`companies/*.json`, ver `AGENTS.md`). Si el archivo no existe, el baseline está vacío: no es un
error. Esté donde esté, el gate post-edición lo valida: reconoce la ruta configurada de la
empresa activa, no solo la marca.

## El formato

**Lee `templates/09-baseline.md`** (ruta relativa a la raíz del repo del harness): ahí
está el formato literal. En corto:

- Primera línea: `<!-- qa-harness:baseline v1 -->`. Es lo que identifica al archivo ante el gate.
- Un módulo por sección `## <CÓDIGO> — <nombre>`; una regla por sección `### <CÓDIGO>-<NNN> — <título>`.
- Cada regla lleva **solo** estas líneas:
  - `- Estado: vigente` o `- Estado: reemplazada por <ID>`
  - `- Regla: <comportamiento observable, en una línea>`
  - `- Verificado: <caso> · <ticket> · <AAAA-MM-DD> · <ambiente>` (una o más)

El gate post-edición (`core/gates/post_edicion.py`) valida esa estructura en cada escritura y
bloquea con el motivo. **Si te bloquea, corrige el formato; no lo esquives.**

## Reglas críticas (NO romper)

1. **Solo entra lo verificado.** Cada regla sale de un caso ✅ Pass del cierre que se está
   consolidando. Nada inferido, nada de memoria, nada "que seguramente también aplica". Si no hay
   un caso Pass que lo respalde, no entra.
2. **Los IDs son permanentes.** Nunca se renumeran ni se reutilizan: el siguiente ID de un módulo
   es el mayor existente (vigente o reemplazado) + 1.
3. **Nunca borres una regla ni reescribas su texto.** Si el comportamiento cambió, se reemplaza
   (ver CONSOLIDAR, paso 3). El historial es parte del valor.
4. **El módulo lo confirma el QA.** Propones; nunca asignas ni creas un módulo en silencio.
5. **Borrador antes de escribir.** Muestras el diff y esperas aprobación explícita ("si", "si
   adelante", "publicar"). El silencio, "listo" o "dale nomás" no son aprobación.
6. **El `.md` es la fuente única.** El espejo se publica desde él y nunca se lee de vuelta.
7. **Una pregunta a la vez.** Después de preguntar, PARA y espera.

## Modo CONSULTAR (desde qa-analisis-ticket, antes de la Fase 1)

1. **Módulo.** Propón el módulo del ticket a partir de su título, componente y descripción, entre
   los de `baseline.modules`, y pide confirmación en una línea. Si ninguno encaja, dilo y pregunta
   cuál es; **no lo agregues a la config en este modo** (eso se hace al consolidar).
2. **Lee el baseline** y toma las reglas `vigente` de ese módulo. Las reemplazadas solo sirven de
   contexto histórico.
3. **Compara con el ticket.** Para cada regla vigente que el ticket contradice, anota una
   desviación. **Manda el ticket** (mismo criterio que la memoria previa en `AGENTS.md`): el
   análisis se hace contra el ticket, y la desviación se reporta, no se resuelve a favor del
   baseline.
4. **Devuelve a [[qa-analisis-ticket]]:**
   - las reglas vigentes relevantes (como contexto, marcadas como salidas del baseline), y
   - si hay contradicciones, la sección `Desviaciones del baseline`:

   | Regla del baseline | Qué dice el baseline | Qué dice el ticket | Qué pasa al cerrar |
   |---|---|---|---|
   | VEN-PED-001 | [texto de la regla] | [lo que pide el ticket] | Si el cierre final aprueba el caso que lo verifica, VEN-PED-001 se reemplaza |

5. **Este modo nunca escribe el baseline.**

Si el baseline no existe o el módulo no tiene reglas, devuelve "sin reglas previas" y sigue.

## Modo CONSOLIDAR (desde el cierre, después de publicar)

### Paso 0 — Condiciones (todas, o no se consolida)

- `baseline.enabled` es `true` (GUARD).
- El ambiente cerrado tiene `final: true`.
- El cierre **aprobó**: `✅ FUNCIONALIDAD APROBADA` (o `✅ FUNCIONALIDAD APROBADA EN PRODUCCIÓN`),
  es decir, el título pasa a `✅ APROBADO VALIDADO EN [AMBIENTE]`. Con ⚠️ o 🔴 no se consolida.
- El cierre ya se publicó (esta skill corre después del Paso 4 del cierre, nunca antes).
- **Los casos salieron de la documentación.** El camino **Jira-only** (sin casos documentados,
  resultados escritos en el chat) queda **excluido**: sin un caso documentado no hay de dónde
  tomar el comportamiento verificado. Dilo en una línea y termina.

Si falla alguna, no consolidas; en el Jira-only, avisas por qué. En los demás casos, vuelves sin
ruido.

### Paso 1 — Módulo

Propón el módulo como en CONSULTAR y espera confirmación. Si el módulo no existe en
`baseline.modules`, propón agregarlo con su `code` (mayúsculas y guiones, ej. `VEN-PED`) y `name`,
y pregunta. Con el sí, agrégalo a `companies/<activeCompany>.json` mostrando antes el cambio.

### Paso 2 — Reglas candidatas

- Parte **solo** de los casos marcados ✅ Pass en este cierre. Fail, Bloqueado y No ejecutado no
  entran nunca.
- Cada regla es el comportamiento observable que el caso verificó (su resultado esperado, que
  pasó). No generalices más allá del caso.
- Varios casos pueden respaldar la misma regla: una línea `Verificado` por caso.
- Un caso Pass que no describe una regla de negocio estable (ej. un smoke técnico) puede quedar
  afuera: lístalo en el borrador como "no consolidado" con el motivo.

### Paso 3 — Comparar con el baseline

Para cada candidata, contra las reglas **vigentes** del módulo:

| Situación | Qué haces |
|---|---|
| Comportamiento nuevo | Regla nueva, `- Estado: vigente`, con el siguiente ID del módulo |
| Ya existe una vigente que dice lo mismo | Agregas una línea `Verificado` a esa regla. Nada más |
| Contradice una vigente (incluye lo que el análisis marcó en `Desviaciones del baseline`) | **Reemplazo:** regla nueva vigente con ID nuevo, y la vieja pasa a `- Estado: reemplazada por <ID nuevo>`. Su `Regla` y sus `Verificado` quedan intactos |

`Verificado` se arma así: `<CP_ID del caso> · <TICKET-ID> · <fecha del cierre, AAAA-MM-DD> · <key del ambiente final>`.

### Paso 4 — Borrador (esperar aprobación)

```
📚 BASELINE — [TICKET-ID] → [CÓDIGO] [nombre del módulo]

➕ Reglas nuevas
[bloques ### completos, tal cual se van a escribir]

🔁 Reemplazos
[ID viejo] → [ID nuevo]: [por qué — qué caso lo verificó]

✔️ Re-verificadas
[ID]: + Verificado: [línea]

⏭️ Casos Pass no consolidados
[CP_ID]: [motivo]

📤 Espejo: [no configurado / se reemplazará la página [pageId] en Notion|Confluence con el baseline completo]

¿Escribo el baseline? (si / no / ajustar)
```

### Paso 5 — Escribir

1. Si el archivo no existe, créalo copiando `templates/09-baseline.md`.
2. Aplica exactamente lo aprobado. El gate post-edición valida el resultado; si bloquea, corrige
   el formato sin cambiar el contenido aprobado. Si para corregirlo hace falta cambiar contenido,
   muestra el nuevo borrador y vuelve a pedir aprobación.

### Paso 6 — Espejo (solo si `baseline.mirror.backend` no es `none`)

Se publica **después** de escribir el `.md`, con su contenido completo, reemplazando la página
entera (el espejo no se edita por partes ni se lee para mezclar):

- **notion:** `notion-update-page` sobre `baseline.mirror.pageId`, reemplazando el contenido.
- **confluence:** `getConfluencePage` (solo para la versión) → `updateConfluencePage` sobre
  `baseline.mirror.pageId`.

Pasa por el gate de publicación y por la confirmación del runtime como cualquier otra
publicación. Si falla: reintenta UNA vez; si vuelve a fallar, avisa. El `.md` ya es la verdad y la
próxima consolidación vuelve a publicar la página completa.

### Paso 7 — Respuesta (corta)

```
📚 Baseline actualizado — [TICKET-ID] → [CÓDIGO]
➕ [n] nuevas · 🔁 [n] reemplazadas · ✔️ [n] re-verificadas
📤 Espejo: [publicado / no configurado / falló: motivo]
```
