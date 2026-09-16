---
name: qa-cierre-prod
description: >
  Cierre de ciclo de pruebas en ambiente PRODUCCIÓN para un ticket: lee los casos desde la página
  de documentación (Confluence o Notion), confirma resultados, publica comentario formal en Jira,
  actualiza la página existente y crea una entrada de cierre PROD separada.
  Trigger: Cuando el usuario escribe "Cierre PROD TICKET-ID" (ej. "Cierre PROD PROJ-1338"), o pide
  cerrar/validar pruebas en producción de un ticket.
license: Apache-2.0
metadata:
  author: qa-harness-pro
  version: "1.0"
---

## When to Use

> ## ⚠️ GUARD — comprobar ANTES de hacer nada
>
> Esta skill solo aplica si `environments` (en `companies/<empresa>.json`) define un ambiente
> `final: true` **distinto** del ambiente de prueba habitual — es decir, un flujo real de dos o más
> etapas (DEV → PROD).
>
> **Si `environments.list` tiene un solo ambiente** (por ejemplo, únicamente `STG`, marcado
> `final: true`), esta skill **NO se usa**: no hay una "producción" separada que validar. Usa
> [[qa-cierre-ciclo]], que ya aplica el tratamiento de ambiente final. No fuerces este flujo ni
> publiques un comentario que declare "AMBIENTE PRODUCCIÓN" sobre pruebas que no se corrieron ahí.

- El usuario escribe `Cierre PROD [TICKET-ID]` (ej. `Cierre PROD PROJ-1338`; el prefijo sale de `tracker.ticketPrefixes`), **y** la config define un ambiente final separado (ver GUARD arriba).
- Pide registrar la validación/cierre del ciclo de pruebas en producción.

Actúa como **"QA Test Closure Analyst"**. Ejecuta el flujo completo sin preguntar si ejecutarlo. Mismo flujo que [[qa-cierre-ciclo]] con las diferencias de abajo.

## Configuración (cargar al inicio)

Igual que [[qa-cierre-ciclo]]: config de empresa (`tracker.cloudId`, `tracker.ticketPrefixes`, `docs.backend` y su destino) + perfil (`profile.name`). Si falta un valor → **avisa antes de operar; no inventes IDs**.

## Reglas críticas (NO romper)

1. **NUNCA** incluir `⚠️ Nota: El cambio de estado a Done debe realizarse manualmente` en el comentario de Jira. Va SOLO en el chat.
2. **NUNCA** cambiar el estado del ticket a Done en Jira — siempre manual, lo hace el usuario.
3. **Siempre** mostrar borrador para aprobación antes de publicar. El usuario confirma con "si", "si adelante", "publicar".
4. **Lee los casos SIEMPRE desde la página de documentación** — nunca los inventes.
5. **Formato idéntico** en todos los tickets del mismo ciclo.
6. **Los casos de prueba (CP) SIEMPRE van en tabla** (columnas ID | Caso | Resultado), nunca como lista de bullets.

## Diferencias respecto al cierre de un ambiente no final

| Aspecto | DEV | PROD |
|---|---|---|
| Tono del comentario | Técnico | Formal / ejecutivo |
| Estado final Jira | Sin cambio | Manual (el usuario lo pasa a Done) |
| Doc | Agrega sección a página existente | Actualiza página + crea entrada de cierre separada |
| Sección de cierre | `## 🏁 Cierre DEV` | `## 🚀 Cierre PROD` |
| Emoji de título final | `✅ APROBADO` | `✅ APROBADO VALIDADO EN PROD` |

## Flujo de ejecución

### Paso 1 — Leer casos desde la doc

Igual que [[qa-cierre-ciclo]] Paso 1 (búsqueda según `docs.backend`, extrae la tabla de casos), con el mismo criterio de búsqueda: **"cero resultados" NO es lo mismo que "búsqueda fallida"**.

- **Búsqueda ejecutada OK con cero resultados** → no hay página → pregunta si el ticket fue **Jira-only**. Si confirma: pide los resultados en el chat y publica SOLO el comentario formal en Jira (omite actualizar la doc y NO crees la página de cierre separada).
- **Búsqueda que FALLA técnicamente** (error del MCP, auth, red) → reintenta UNA vez. Si vuelve a fallar, DETENTE: informa el error al usuario y no sigas con el cierre. NO asumas que la página no existe ni crees o publiques nada (riesgo de duplicados).

### Paso 2 — Confirmar resultados

Igual que DEV: presenta la tabla de casos y pide Pass/Fail/Bloqueado/No ejecutado + bugs + observaciones.

**Aplica la misma regla de resultados que [[qa-cierre-ciclo]]: el silencio nunca se convierte en
✅ Pass.** El usuario puede reportar solo los casos que fallaron ÚNICAMENTE si además confirma con
una frase explícita que "el resto se ejecutó y pasó" (o equivalente inequívoco). **Equivalente
inequívoco** = una afirmación explícita del usuario de que todos los casos restantes se ejecutaron
con resultado Pass (ej. "todo lo demás pasó", "los 12 restantes ok"). NO cuentan como confirmación:
el silencio, "listo", "cierra nomás".

Sin esa confirmación, todo caso no reportado se marca `⏸️ No ejecutado` en la tabla y en las
métricas (la plantilla del Paso 3 no se altera: esas son las únicas cuatro etiquetas válidas), y en
`📋 OBSERVACIONES FINALES` se anota que esos casos quedaron **sin confirmar por el usuario**. El
comentario formal de PROD lo refleja tal cual.

### Paso 3 — Comentario estandarizado PROD (borrador para aprobar)

```
🚀 CIERRE DE PRUEBAS — AMBIENTE PRODUCCIÓN
────────────────────────────────────────────
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

🧪 CASOS VALIDADOS EN PRODUCCIÓN
| ID | Caso | Resultado |
| --- | --- | --- |
| TC-001 | [título/descripción del caso] | ✅ Pass / ❌ Fail / ⏭️ Bloqueado / ⏸️ No ejecutado |
[... una fila por caso ...]

🐛 INCIDENCIAS EN PRODUCCIÓN
[Si hay bugs:]
• [BUG-ID o descripción] — Severidad: 🔴/🟠/🟡/🟢 — Estado: Abierto/Resuelto
[Si no hay:]
• Sin incidencias registradas en producción ✅

📋 OBSERVACIONES FINALES
[Observaciones del usuario o "Sin observaciones adicionales"]
[Si se cierra con cobertura < 100% aceptada: "⚠️ Alcance reducido aceptado por [nombre]: [motivo]"]

✅ RESULTADO FINAL
[Caso 🔴 crítico en Fail, o incidencia 🔴 crítica abierta]                 → 🔴 REQUIERE ATENCIÓN INMEDIATA
[Caso 🔴 crítico Bloqueado o No ejecutado]                                 → ⚠️ REVISIÓN REQUERIDA
[Cobertura < 100% sin excepción explícita declarada]                       → ⚠️ REVISIÓN REQUERIDA
[Sin críticos, Pass Rate ≥ 80%, sin incidencias abiertas, cobertura 100% (o excepción registrada)] → ✅ FUNCIONALIDAD APROBADA EN PRODUCCIÓN
[Sin críticos pendientes, pero Pass Rate < 80% o hay incidencias abiertas] → ⚠️ REVISIÓN REQUERIDA
────────────────────────────────────────────
📝 Documentación completa: [link a la página de doc]
```

**Cómo se calculan las métricas (no improvises los denominadores):**

- **Ejecutados = Pass + Fail.** Un caso Bloqueado o No ejecutado NO cuenta como ejecutado.
- **Cobertura de ejecución = ejecutados / planificados.** No es solo informativa: la aprobación
  exige cobertura del 100% del alcance comprometido, o una excepción explícita registrada.
- **Pass Rate = Pass / ejecutados.** Si ejecutados = 0, el Pass Rate es N/A — y la funcionalidad no se aprueba.
- **Criterio de aprobación:** si existe algún caso de prioridad 🔴 crítica en Fail, Bloqueado o
  No ejecutado, la funcionalidad NO se aprueba en producción — sin importar el Pass Rate (un
  crítico en Fail o una incidencia 🔴 abierta es además atención inmediata). Con eso limpio,
  aplica el umbral: Pass Rate ≥ 80% (calculado sobre ejecutados), sin incidencias abiertas y
  cobertura de ejecución del 100% del alcance comprometido.
- **Excepción de alcance (la única salida al 100% de cobertura):** si el usuario decide cerrar
  con cobertura menor, debe declararlo explícitamente, y el comentario de cierre lo registra como
  `⚠️ Alcance reducido aceptado por [nombre]: [motivo]` en `📋 OBSERVACIONES FINALES` — nunca de
  forma silenciosa. Mismo espíritu que la regla de resultados del Paso 2 (la de [[qa-cierre-ciclo]]):
  el silencio o un "cierra nomás" NO cuentan como excepción. Sin excepción declarada y con
  cobertura < 100%, el resultado es ⚠️ REVISIÓN REQUERIDA, no aprobado. Y la excepción NO
  sustituye el veto de críticos: un caso 🔴 en Fail, Bloqueado o No ejecutado veta la aprobación
  aunque haya excepción firmada.
- ¿Por qué la cobertura? Porque un Pass Rate sobre ejecutados puede dar 100% con la mitad de la
  suite sin correr. La cobertura deja ese hueco a la vista.

### Paso 4 — Publicar (tras aprobación)

1. **Jira:** `addCommentToJiraIssue` con el comentario aprobado.
2. **Doc — actualiza la página existente** agregando la sección `## 🚀 Cierre PROD` al final, y renombra el título con prefijo `✅ APROBADO VALIDADO EN PROD`:
   - **confluence:** `getConfluencePage` → `updateConfluencePage`.
   - **notion:** `notion-fetch` → `notion-update-page` (`insert_content`, end) → `update_properties`.
3. **Doc — crea página de cierre separada:**
   - **confluence:** `createConfluencePage` bajo `docs.confluence.parentPageId`.
   - **notion:** `notion-create-pages` bajo `docs.notion.parents.casos`.
   - Título: `[TICKET-ID] - Cierre PROD - [YYYY-MM-DD]`
   - Contenido: comentario completo + tabla de resultados + link a la página de análisis original.

### Paso 5 — Respuesta al usuario (corta)

```
╔══════════════════════════════════════════════════╗
║  ✅ CIERRE PROD REGISTRADO — [TICKET-ID]        ║
╚══════════════════════════════════════════════════╝

📊 Pass Rate: [X]% ([n] Pass de [n] ejecutados) · Cobertura: [X]% ([n] de [N] planificados)
🐛 Incidencias: [n encontradas / ninguna]
📈 Resultado: ✅ Aprobado / ⚠️ Revisión / 🔴 Atención inmediata

💬 Comentario publicado en Jira ✅
📝 Documentación actualizada ✅
📄 Página de cierre creada ✅

⚠️ Recuerda: cambia el estado a Done manualmente en Jira.
```

## Persistencia (opcional)

Si tienes memoria persistente (Engram u otra), guarda un resumen del cierre PROD (pass rate, incidencias, resultado final). **Sin memoria persistente: omite este paso** — no afecta el cierre ni la publicación.
