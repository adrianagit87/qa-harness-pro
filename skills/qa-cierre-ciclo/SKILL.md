---
name: qa-cierre-ciclo
description: >
  Cierre de ciclo de pruebas en CUALQUIER ambiente definido en la config, para un ticket: lee los
  casos desde el backend de documentación (los issues hijos en Jira, o la página en
  Confluence/Notion), confirma resultados, publica comentario estandarizado en Jira y actualiza la doc. Los ambientes NO están hardcodeados — salen
  de `environments` en `companies/<empresa>.json`.
  Trigger: Cuando el usuario escribe "Cierre AMBIENTE TICKET-ID" (ej. "Cierre STG US-1234",
  "Cierre DEV PROJ-1340"), o pide cerrar/registrar el ciclo de pruebas de un ticket.
license: MIT
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
(ver `AGENTS.md`):

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
3. **Antes de ejecutar este paso, leé `references/resolucion-ambiente.md`** (en la carpeta de esta skill: `skills/qa-cierre-ciclo/references/`, ruta relativa a la raíz del repo del harness): qué campo del ambiente se usa en cada parte del flujo, y el caso de un solo ambiente.

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

**Antes de ejecutar este paso, leé `references/lectura-casos.md`** (en la carpeta de esta skill: `skills/qa-cierre-ciclo/references/`, ruta relativa a la raíz del repo del harness): ahí está cómo leer los casos en cada backend.

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

**Leé `templates/07-comentario-cierre-ciclo.md`** (ruta relativa a la raíz del repo del harness,
no al proyecto donde estés trabajando): ahí está el formato literal del comentario —
encabezado, métricas, tabla de casos, bugs, observaciones y las líneas de `🔄 ESTADO DEL CICLO`,
con la variante de aprobación según el ambiente sea `final: false` o `final: true`. No improvises
el formato ni reordenes las secciones.

**Antes de ejecutar este paso, leé `references/metricas-aprobacion.md`** (en la carpeta de esta skill: `skills/qa-cierre-ciclo/references/`, ruta relativa a la raíz del repo del harness): ahí está el cálculo de las métricas y el criterio de aprobación, con la única excepción de alcance.

### Paso 4 — Publicar (tras aprobación)

1. **Jira:** `addCommentToJiraIssue` (con `tracker.cloudId`) con el comentario aprobado, sobre el ticket de desarrollo.

**Con `docs.backend = jira`, además — un comentario de ejecución por cada CP.** Cada issue hijo
recibe su propio registro; el comentario de cierre agregado va en el ticket de QA contenedor.
**Leé `templates/08-comentario-ejecucion-cp.md`** (ruta relativa a la raíz del repo del harness,
no al proyecto donde estés trabajando) y respeta ese formato, que es el que el equipo ya usa. Si no
lo encontrás, pedí la ruta del harness antes de improvisar el formato.

**Reglas (no romper):**

- **Solo escribís lo que el usuario confirmó.** La columna `Resultado` lleva el valor real
  observado; si el usuario no te lo dio, va el resultado que sí reportó y nada más. **Jamás
  inventes un `id`, un valor de BD o una evidencia.** Un comentario de ejecución con datos
  fabricados es peor que no tener comentario: alguien lo va a leer como evidencia real.
- A los CP marcados `⏸️ No ejecutado` **no les publiques comentario de ejecución** — no se ejecutaron.
- **Nunca** uses `transitionJiraIssue` para pasar los CP a Finalizada. Está en `deny`; lo hace el usuario.
- El comentario agregado del ciclo va sobre el **contenedor**, no sobre cada CP.
2. **Doc — registra el cierre del ciclo** (y, si el ambiente tiene `separateClosurePage: true`, la página de cierre separada). **Antes de ejecutar este paso, leé `references/publicacion-doc.md`** (en la carpeta de esta skill: `skills/qa-cierre-ciclo/references/`, ruta relativa a la raíz del repo del harness): ahí está el procedimiento por backend, el renombrado del título y la convención de naming de la página.

### Paso 5 — Respuesta al usuario (corta)

**Antes de ejecutar este paso, leé `references/respuesta-final.md`** (en la carpeta de esta skill: `skills/qa-cierre-ciclo/references/`, ruta relativa a la raíz del repo del harness): ahí está el formato literal.

### Paso 6 — Baseline (solo si aplica)

Si `baseline.enabled` es `true` **y** el ambiente tiene `final: true` **y** el cierre quedó
`✅ FUNCIONALIDAD APROBADA` (ya publicado), carga [[qa-baseline]] en modo **CONSOLIDAR**. Si falta
cualquiera de las tres, omite este paso sin mencionarlo. El camino Jira-only no consolida: la
skill lo avisa.

## Persistencia (opcional)

Si tienes memoria persistente (Engram u otra), guarda un resumen del cierre: pass rate, bugs, estado. **Sin memoria persistente: omite este paso** — no afecta el cierre ni la publicación.
