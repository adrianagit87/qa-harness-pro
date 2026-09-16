---
name: qa-cierre-ciclo
description: >
  Cierre de ciclo de pruebas en CUALQUIER ambiente definido en la config, para un ticket: lee los
  casos desde el backend de documentación (los issues hijos en Jira, o la página en
  Confluence/Notion), confirma resultados, publica comentario estandarizado en Jira y actualiza la doc. Los ambientes NO están hardcodeados — salen
  de `environments` en `companies/<empresa>.json`.
  Trigger: Cuando el usuario escribe "Cierre AMBIENTE TICKET-ID" (ej. "Cierre STG US-1234",
  "Cierre DEV PROJ-1340"), o pide cerrar/registrar el ciclo de pruebas de un ticket.
license: Apache-2.0
metadata:
  author: qa-harness-pro
  version: "1.0"
---

## When to Use

- El usuario escribe `Cierre [AMBIENTE] [TICKET-ID]` (ej. `Cierre STG US-1234`). El ambiente sale de `environments.list[].key`; el prefijo del ticket, de `tracker.ticketPrefixes`.
- Pide registrar el cierre del ciclo de pruebas de un ticket en alguno de los ambientes configurados.
- Si el usuario NO nombra ambiente, usa `environments.default` y **dilo explícitamente en el borrador** — nunca cierres en un ambiente que el usuario no vio escrito.

Actúa como **"QA Test Closure Analyst"**. Ejecuta el flujo completo sin preguntar si ejecutarlo.

## Configuración (cargar al inicio)

Esta skill **NO tiene identificadores ni nombres hardcodeados**. Al empezar, carga el perfil desde
`profile/profile.json` y la config de la empresa activa desde `companies/<activeCompany>.json`
(ver `CLAUDE.md`):

| Variable que usa la skill | Origen |
|---|---|
| Jira cloudId | `tracker.cloudId` |
| Prefijos de ticket | `tracker.ticketPrefixes` |
| Backend de documentación | `docs.backend` (`jira`, `confluence` o `notion`) |
| Destino de la doc | `docs.jira.*`, `docs.confluence.*` o `docs.notion.parents.casos` |
| Nombre de quien firma | `profile.name` |
| Ambientes disponibles | `environments.list[]` — cada uno con `key`, `label`, `emoji`, `final`, `tone`, `separateClosurePage` |
| Ambiente por defecto | `environments.default` |

Si la config no está disponible o le falta un valor → **avisa antes de operar; no inventes IDs**.

### Resolución del ambiente (hacer ANTES del Paso 1)

1. Toma el ambiente del trigger del usuario (`Cierre STG US-1234` → `STG`). Si no lo nombró, usa `environments.default`.
2. Busca ese `key` en `environments.list`. **Si no existe → DETENTE** y muestra los `key` válidos. No inventes un ambiente ni caigas al default en silencio: cerrar un ciclo declarando un ambiente equivocado es exactamente el humo que este harness existe para evitar.
3. De ese ambiente salen, para todo el resto del flujo:

| Campo | Se usa en |
|---|---|
| `key` | Trigger, encabezados, `## Cierre [key]`, título `✅ APROBADO VALIDADO EN [key]` |
| `label` | Línea `CIERRE DE PRUEBAS — AMBIENTE [label]` del comentario Jira |
| `emoji` | Prefijo del comentario y de la sección en la doc |
| `final` | `true` = no hay ambiente siguiente; cambia la etiqueta de aprobación y el título de la página |
| `tone` | `técnico` o `formal` — registro de redacción del comentario |
| `separateClosurePage` | `true` = además crea una página de cierre separada (Paso 4.3) |

> **Config de un solo ambiente.** Si `environments.list` tiene un único ambiente marcado `final: true` (ej. solo `STG`), ese ambiente es a la vez el de prueba y el de validación final: aplica el tratamiento de `final` sin buscar un ambiente previo, y [[qa-cierre-prod]] NO se usa.

## Reglas críticas (NO romper)

1. **NUNCA** incluir la línea `⚠️ Nota: El cambio de estado a Done debe realizarse manualmente` en el comentario de Jira. Ese recordatorio va SOLO en el chat.
2. **NUNCA** cambiar el estado del ticket en Jira (transiciones a Done/Tested). Eso lo hace el usuario manualmente.
3. **Siempre** mostrar el comentario como borrador para aprobación ANTES de publicar. El usuario confirma con "si", "si adelante", "publicar".
4. **Lee los casos SIEMPRE desde la página de documentación** — nunca los inventes ni los pidas de memoria.
5. **El formato del comentario debe ser idéntico** en todos los tickets del mismo ciclo — nunca improvises el formato.
6. Las imágenes/screenshots NO se adjuntan por API — el usuario las sube manualmente en Jira.
7. **Los casos de prueba (CP) SIEMPRE van en tabla** (columnas ID | Caso | Resultado), nunca como lista de bullets — para máxima legibilidad en Jira y en la doc.

## Flujo de ejecución

### Paso 1 — Leer casos desde la doc

Según `docs.backend`:

- **jira:** localiza el ticket de QA contenedor con `searchJiraIssuesUsingJql`
  (`project = {docs.jira.qaProject} AND issuetype = {containerIssueType} AND summary ~ "{TICKET-ID}"`),
  y luego lee **sus issues hijos** — los CP — con `parent = {QA-TICKET}`. De cada hijo tomás la key,
  el `CP_ID` y el título del summary. Ese es tu listado de casos: **no lo reconstruyas de memoria ni
  del análisis original.** Si un CP fue agregado o borrado a mano después del análisis, la verdad
  está en los hijos, no en el plan.
- **confluence:** busca con `searchConfluenceUsingCql` (`title ~ "[TICKET-ID] QA Analysis"` en `docs.confluence.spaceKey`) → `getConfluencePage` y extrae la tabla de casos (ID, Título, Prioridad, Tipo).
- **notion:** busca con `notion-search`, query `[TICKET-ID] QA Analysis`, `query_type: internal` → `notion-fetch` y extrae la tabla de casos.

**Criterio de búsqueda (no romper) — "cero resultados" NO es lo mismo que "búsqueda fallida":**

- **Búsqueda ejecutada OK con cero resultados** → no hay página → pregunta al usuario si el ticket fue **Jira-only** (muchos bugfixes simples lo son). Si confirma:
  - Pide la lista de casos ejecutados con sus resultados directamente en el chat (o "fue validación puntual, sin casos formales" — también vale: el comentario lleva la validación descrita en vez de la tabla).
  - Sigue el flujo normal **omitiendo todo lo de doc**: en el Paso 3 quita la línea `📝 Documentación completa`, y en el Paso 4 publica SOLO el comentario en Jira.
- **Búsqueda que FALLA técnicamente** (error del MCP, auth, red) → reintenta UNA vez. Si vuelve a fallar, DETENTE: informa el error al usuario y no sigas con el cierre. NO asumas que la página no existe ni crees o publiques nada — asumir "no existe" sobre un error técnico produce duplicados.

### Paso 2 — Confirmar resultados con el usuario

Presenta la tabla y pide resultados:

```
═══════════════════════════════════════════════════
[emoji] CIERRE [AMBIENTE] — [TICKET-ID]
═══════════════════════════════════════════════════

Leí [N] casos de prueba desde la documentación. Por favor confirma:

| ID | Título | Resultado |
|---|---|---|
| TC-001 | [título] | ✅ Pass / ❌ Fail / ⏭️ Bloqueado / ⏸️ No ejecutado |
[...]

Bugs encontrados (opcional): [IDs o descripción breve]
Observaciones adicionales: [texto libre]

Puedes responder con la tabla completa, o indicar solo los que NO pasaron
SI ADEMÁS me confirmas explícitamente: "el resto se ejecutó y pasó".
```

**Regla de resultados (no romper): el silencio nunca se convierte en ✅ Pass.** Solo puedes marcar
como Pass los casos no mencionados si el usuario lo confirma con una frase explícita ("el resto se
ejecutó y pasó" o equivalente inequívoco). **Equivalente inequívoco** = una afirmación explícita del
usuario de que todos los casos restantes se ejecutaron con resultado Pass (ej. "todo lo demás pasó",
"los 12 restantes ok"). NO cuentan como confirmación: el silencio, "listo", "cierra nomás".

Sin esa confirmación, todo caso no reportado se marca `⏸️ No ejecutado` en la tabla y en las
métricas (la plantilla del Paso 3 no se altera: esas son las únicas cuatro etiquetas válidas), y en
`📋 OBSERVACIONES` se anota que esos casos quedaron **sin confirmar por el usuario** (ej.
"TC-003–TC-007 sin confirmación de ejecución"). El comentario de cierre (métricas, tabla y estado
del ciclo) lo refleja tal cual. Reportar como ejecutado lo que nadie confirmó es exactamente el
humo que este harness existe para evitar.

### Paso 3 — Generar comentario estandarizado (borrador para aprobar)

```
[emoji] CIERRE DE PRUEBAS — AMBIENTE [label]
────────────────────────────────────────
📅 Fecha: [fecha actual]
👤 QA: [profile.name]
🎯 Ticket: [TICKET-ID] — [Título]

📊 MÉTRICAS
• Total planificados: [N]
• Total ejecutados:   [n] (Pass + Fail)
• ✅ Pass:            [n]
• ❌ Fail:            [n]
• ⏭️ Bloqueados:      [n]
• ⏸️ No ejecutados:   [n]
• 📐 Cobertura de ejecución: [X]% (ejecutados / planificados)
• 📈 Pass Rate:              [X]% (Pass / ejecutados)

🧪 CASOS VALIDADOS
| ID | Caso | Resultado |
| --- | --- | --- |
| TC-001 | [título/descripción del caso] | ✅ Pass / ❌ Fail / ⏭️ Bloqueado / ⏸️ No ejecutado |
[... una fila por caso ...]

🐛 BUGS ENCONTRADOS
[Si hay bugs:]
• [BUG-ID o descripción] — Severidad: 🔴/🟠/🟡/🟢
[Si no hay bugs:]
• Sin bugs reportados en este ciclo ✅

📋 OBSERVACIONES
[Observaciones del usuario o "Sin observaciones adicionales"]
[Si se cierra con cobertura < 100% aceptada: "⚠️ Alcance reducido aceptado por [nombre]: [motivo]"]

🔄 ESTADO DEL CICLO [AMBIENTE]
[Algún caso 🔴 crítico en Fail, Bloqueado o No ejecutado]                          → ⚠️ REQUIERE CORRECCIONES ANTES DE AVANZAR
[Cobertura < 100% sin excepción explícita declarada]                               → ⚠️ REQUIERE CORRECCIONES ANTES DE AVANZAR
[Sin críticos, Pass Rate ≥ 80%, sin bugs, cobertura 100% (o excepción registrada)] → ✅ APROBADO PARA SIGUIENTE AMBIENTE  ← si el ambiente tiene `final: false`
                                                                                   → ✅ FUNCIONALIDAD APROBADA            ← si tiene `final: true` (no hay ambiente siguiente)
[Sin críticos pendientes, pero Pass Rate < 80% o hay bugs]                         → ⚠️ REQUIERE CORRECCIONES ANTES DE AVANZAR
────────────────────────────────────────
📝 Documentación completa: [link a la página de doc]
```

**Cómo se calculan las métricas (no improvises los denominadores):**

- **Ejecutados = Pass + Fail.** Un caso Bloqueado o No ejecutado NO cuenta como ejecutado.
- **Cobertura de ejecución = ejecutados / planificados.** No es solo informativa: la aprobación
  exige cobertura del 100% del alcance comprometido, o una excepción explícita registrada.
- **Pass Rate = Pass / ejecutados.** Si ejecutados = 0, el Pass Rate es N/A — y el ciclo no se aprueba.
- **Criterio de aprobación:** si existe algún caso de prioridad 🔴 crítica en Fail, Bloqueado o
  No ejecutado, el ciclo NO se aprueba — sin importar el Pass Rate. Con eso limpio, aplica el
  umbral: Pass Rate ≥ 80% (calculado sobre ejecutados), sin bugs abiertos y cobertura de
  ejecución del 100% del alcance comprometido.
- **Excepción de alcance (la única salida al 100% de cobertura):** si el usuario decide cerrar
  con cobertura menor, debe declararlo explícitamente, y el comentario de cierre lo registra como
  `⚠️ Alcance reducido aceptado por [nombre]: [motivo]` en `📋 OBSERVACIONES` — nunca de forma
  silenciosa. Mismo espíritu que la regla de resultados del Paso 2: el silencio o un "cierra
  nomás" NO cuentan como excepción. Sin excepción declarada y con cobertura < 100%, el estado del
  ciclo es ⚠️ REQUIERE CORRECCIONES ANTES DE AVANZAR, no aprobado. Y la excepción NO sustituye el
  veto de críticos: un caso 🔴 en Fail, Bloqueado o No ejecutado veta la aprobación aunque haya
  excepción firmada.
- ¿Por qué la cobertura? Porque un Pass Rate sobre ejecutados puede dar 100% con la mitad de la
  suite sin correr. La cobertura deja ese hueco a la vista.

### Paso 4 — Publicar (tras aprobación)

1. **Jira:** `addCommentToJiraIssue` (con `tracker.cloudId`) con el comentario aprobado, sobre el ticket de desarrollo.

**Con `docs.backend = jira`, además — un comentario de ejecución por cada CP.** Cada issue hijo
recibe su propio registro; el comentario de cierre agregado va en el ticket de QA contenedor.
Respeta este formato, que es el que el equipo ya usa:

```markdown
## Ejecución [CP_ID] — [YYYY-MM-DD]

**Resultado: ✅ PASS / ❌ FAIL / ⏭️ Bloqueado / ⏸️ No ejecutado**

### Pasos ejecutados
1. [paso]

### Validaciones
| # | Capa | Query | Resultado |
| --- | --- | --- | --- |
| 1 | [capa] | `[query o endpoint]` | [resultado real observado] ✅ |

### Observaciones
* [Hallazgo, o "Sin observaciones"]

### Conclusión
[Una o dos frases.]
```

**Reglas (no romper):**

- **Solo escribís lo que el usuario confirmó.** La columna `Resultado` lleva el valor real
  observado; si el usuario no te lo dio, va el resultado que sí reportó y nada más. **Jamás
  inventes un `id`, un valor de BD o una evidencia.** Un comentario de ejecución con datos
  fabricados es peor que no tener comentario: alguien lo va a leer como evidencia real.
- A los CP marcados `⏸️ No ejecutado` **no les publiques comentario de ejecución** — no se ejecutaron.
- **Nunca** uses `transitionJiraIssue` para pasar los CP a Finalizada. Está en `deny`; lo hace el usuario.
- El comentario agregado del ciclo va sobre el **contenedor**, no sobre cada CP.
2. **Doc — registra el cierre del ciclo:**

   - **jira:** `addCommentToJiraIssue` sobre el **ticket de QA contenedor** con el comentario de
     cierre completo. Si el cierre aprueba, `editJiraIssue` sobre el contenedor para prefijar su
     summary igual que un título de página: `✅ APROBADO` (ambiente `final: false`) o
     `✅ APROBADO VALIDADO EN [AMBIENTE]` (ambiente `final: true`). No toques la descripción: ahí
     vive el análisis de Fase 1 y se conserva como quedó.
   - **confluence / notion — agrega la sección `## [emoji] Cierre [AMBIENTE]` al final de la página existente:**
   - **confluence:** `getConfluencePage` primero, luego `updateConfluencePage` agregando la sección al final.
   - **notion:** `notion-fetch` primero (Notion renderiza URLs como `[url](url)`), luego `notion-update-page` con `insert_content` (position: end).
   - Si el cierre aprueba, renombra el título: prefijo `✅ APROBADO` si el ambiente tiene `final: false`, o `✅ APROBADO VALIDADO EN [AMBIENTE]` si tiene `final: true`. En Notion el renombrado va por `update_properties`.

3. **Doc — página de cierre separada (SOLO si el ambiente tiene `separateClosurePage: true`):**
   - **confluence:** `createConfluencePage` bajo `docs.confluence.parentPageId`.
   - **notion:** `notion-create-pages` bajo `docs.notion.parents.casos`.
   - Título: `[TICKET-ID] - Cierre [AMBIENTE] - [YYYY-MM-DD]`
   - Contenido: comentario completo + tabla de resultados + link a la página de análisis original.
   - Con `separateClosurePage: false` este paso se omite: una sola página por ticket.

### Paso 5 — Respuesta al usuario (corta)

```
╔══════════════════════════════════════════════════╗
║  ✅ CIERRE [AMBIENTE] REGISTRADO — [TICKET-ID]   ║
╚══════════════════════════════════════════════════╝

📊 Pass Rate: [X]% ([n] Pass de [n] ejecutados) · Cobertura: [X]% ([n] de [N] planificados)
🐛 Bugs: [n encontrados / ninguno]
📈 Estado: ✅ Aprobado / ⚠️ Requiere correcciones

💬 Comentario publicado en Jira ✅
📝 Documentación actualizada ✅
```

## Convención de naming de la página de doc

`[STATUS_EMOJI] [TICKET_ID] - QA Analysis - [YYYY-MM-DD]`

Progresión de emoji: `⚠️` (en progreso) → `✅ APROBADO` (aprobado en un ambiente con `final: false`) → `✅ APROBADO VALIDADO EN [AMBIENTE]` (aprobado en el ambiente con `final: true`).

Con un solo ambiente `final: true` la progresión es directa. Por ejemplo, con solo `STG`: `⚠️` → `✅ APROBADO VALIDADO EN STG`.

## Persistencia (opcional)

Si tienes memoria persistente (Engram u otra), guarda un resumen del cierre: pass rate, bugs, estado. **Sin memoria persistente: omite este paso** — no afecta el cierre ni la publicación.
