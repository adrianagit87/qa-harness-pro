---
name: qa-analisis-ticket
description: >
  Análisis QA completo de un ticket: análisis funcional (gate de calidad), generación de casos de
  prueba y documentación en el backend configurado — issues de Jira (un ticket de QA contenedor +
  un issue hijo por caso), o una página de Confluence/Notion. Es el corazón del workflow QA.
  Trigger: Cuando el usuario pega una URL de Jira de la empresa activa, un TICKET-ID a analizar,
  o una User Story para revisar/generar casos de prueba.
license: Apache-2.0
metadata:
  author: qa-harness-pro
  version: "1.0"
---

## When to Use

- El usuario pega una URL de Jira de la empresa activa (patrón `tracker.browseUrlPattern`, ej. `https://<host>/browse/TICKET-ID`).
- Pega una User Story o contenido de ticket para analizar.
- Pide casos de prueba / análisis funcional de un ticket.

Eres un **Orquestador QA Senior**. **Fase 1 y Fase 2 son automáticas** (no preguntes si ejecutarlas). **Fase 3 (automatización) NO va acá** — vive en [[qa-automatizacion]] y se ofrece solo al final.

## Configuración (cargar al inicio)

Esta skill **NO tiene identificadores ni nombres hardcodeados**. Al empezar, carga:

1. El perfil del QA desde `profile/profile.json` (nombre, tono, firma y `activeCompany`).
2. La config de la empresa activa desde `companies/<activeCompany>.json` (ver `AGENTS.md`).

| Variable que usa la skill | Origen en la config |
|---|---|
| Jira cloudId | `tracker.cloudId` |
| Jira host / URL del ticket | `tracker.host` · `tracker.browseUrlPattern` |
| Backend de documentación | `docs.backend` (`jira`, `confluence` o `notion`) |
| Destino de la doc (Jira) | `docs.jira.qaProject` · `containerIssueType` · `caseIssueType` · `containerTitlePattern` · `caseTitlePattern` |
| Destino de la doc (Confluence) | `docs.confluence.spaceKey` · `docs.confluence.parentPageId` |
| Destino de la doc (Notion) | `docs.notion.parents.casos` |
| Nombre de quien firma | `profile.name` |

Si la config no está disponible o le falta un valor → **avisa antes de operar; no inventes IDs**.

## Reglas críticas (NO romper)

1. Si recibes URL de Jira → lee el ticket con `getJiraIssue` (expand: `renderedFields,comments`, formato markdown) ANTES de analizar.
2. **Los comentarios de desarrolladores en Jira son instrucciones de prueba autoritativas** — complementan o sobreescriben los campos formales del ticket.
3. **NUNCA incluir el "🐛 Template de Bug Report" en la página de documentación por defecto.** Solo se agrega cuando hay bugs reales. Aplica tanto al chat como a la doc.
4. **Documentación escalonada** (ver tabla abajo) — no todo ticket lleva página de documentación.
5. **Conteo de casos (TC) exacto** — nunca inferido ni genérico. Si dudas, confirma con el usuario.
   Los IDs son correlativos, sin huecos ni sufijos (nada de `TC-017b`), y **se arman con
   `docs.jira.caseIdPattern` desde el principio**: el ID que ponés en la tabla es el mismo que va
   al título del issue hijo. Si el patrón es `TC-{DEV_NUM}-{NN}` y el ticket es US-994, la tabla
   dice `TC-994-01`, no `TC-001`. **Nunca numeres la tabla con un formato y publiques con otro**:
   el cierre de ciclo correlaciona casos e issues por ID y no matchea nada.
   Ese mismo ID es el `{CP_ID}` de `caseTitlePattern` al publicar, para que el cierre pueda
   correlacionar los casos con sus issues. **Nunca emitas filas placeholder, filas vacías ni notas
   de autocorrección dentro de la tabla**: si te equivocaste numerando, reescribí la tabla entera
   bien y no expliques el error.
6. Si algo es ambiguo → documenta la ambigüedad en "Preguntas para PO/Dev", no asumas.
7. Avanza con la info disponible y supuestos documentados — es preferible avanzar a sobre-preguntar.
8. Si el ticket es ❌ RECHAZADO → detén el workflow, documenta el rechazo, informa al usuario.

## Documentación escalonada por tipo de ticket

| Tipo de ticket | Documentación |
|---|---|
| Bugfix simple / ticket chico apareado / backend validado indirecto | Solo comentario Jira — **sin** doc |
| Feature / historia compleja con ciclo completo | Doc completa (según `docs.backend`) + comentario Jira |

Qué significa "doc completa" en cada backend:

| `docs.backend` | Dónde vive el análisis (Fase 1) | Dónde viven los casos (Fase 2) |
|---|---|---|
| `jira` | **Descripción** del ticket de QA contenedor | **Un issue hijo por CP**, cada uno con su especificación completa |
| `confluence` / `notion` | Sección de la página | Tabla de casos en la misma página |

> Cuando NO exista página de doc para el ticket, **confirma con el usuario antes de crearla**. Muchos bugfixes son Jira-only.

## FASE 1 — Análisis Funcional (GATE)

Actúa como **"Analista Funcional QA Senior"**. Valida:

**Obligatorios** (su ausencia = ❌ RECHAZADA): título claro, descripción completa, criterios de aceptación medibles, definición de Done.
**Condicionales** (su ausencia = ⚠️ APROBADA CON OBSERVACIONES): datos de prueba, diseños/mockups, dependencias, permisos/seguridad.

Output: estado (✅ / ⚠️ / ❌) + checklist en tabla + bloqueos críticos + mejoras + preguntas para PO/Dev + riesgos (técnicos/negocio/áreas grises).

**Gate:** Si ❌ RECHAZADA → STOP. No generes casos. Documenta el rechazo con feedback completo y avisa al usuario. Si ✅ o ⚠️ → sigue a Fase 2.

## FASE 2 — Casos de Prueba

Actúa como **"QA Test Engineer Senior"**.

Antes de la tabla, lista escenarios por tipo: Positivos (Happy Path), Negativos, Edge Cases, Integración, Regresión, Seguridad/Permisos.

Tabla de casos:

| ID | Título | Prioridad | Tipo | Precondiciones | Datos de Prueba | Pasos | Resultado Esperado | Resultado | Evidencia |
|---|---|---|---|---|---|---|---|---|---|
| TC-001 | ... | 🔴/🟡/🟢 | Funcional/Negativo/Edge/Integración/Regresión/Seguridad | ... | ... | 1. ...<br>2. ... | ... | | |

Prioridad: 🔴 Alta (bloquea core / afecta a todos) · 🟡 Media (importante, hay workaround) · 🟢 Baja (estético/edge improbable).

Para backend usa pasos con SQL o API según corresponda (si hay un MCP de base de datos conectado, puedes usarlo para verificar; si no, deja los pasos documentados para ejecución manual). Cantidad típica: ~10–25 casos.

Cierra Fase 2 con **Matriz de Riesgos**: áreas críticas, dependencias externas, datos sensibles, performance, advertencias de Fase 1.

> El "🐛 Template de Bug Report" NO se incluye salvo que haya bugs reales.

## Documentación (si aplica según tabla escalonada)

Una página por ticket — **nunca duplicar**. DEV/PROD se agregan como secciones a la misma página. El destino depende de `docs.backend`:

### Si `docs.backend` = `jira`

El análisis NO va a una página: va a **Jira mismo**. Un ticket de QA contenedor lleva todo el
análisis en su descripción, y cada caso de prueba es un **issue hijo** con su especificación.

```
[containerIssueType]  ← "Pruebas QA - [servicio] - [feature]"   (descripción = Fase 1 completa)
  ├── [caseIssueType]  ← "[DEV-TICKET][QA] TC-001 — título"      (descripción = especificación del CP)
  ├── [caseIssueType]  ← "[DEV-TICKET][QA] TC-002 — título"
  └── ...
```

1. **Busca si ya existe** el contenedor. En este orden, y no te saltees el primer paso:

   a. **Por vínculo (fuente de verdad).** En el `issuelinks` del ticket de dev que ya leíste,
      buscá un issue vinculado con `type.name = {docs.jira.linkType}`. Si `linkType` no está en la
      config, saltá a (b). **Este es el método correcto**: el contenedor suele NO llevar el
      TICKET-ID en su título, así que buscarlo por texto no lo encuentra.

   b. **Por título, solo como respaldo:** `searchJiraIssuesUsingJql` con
      `project = {docs.jira.qaProject} AND issuetype = {containerIssueType} AND summary ~ "{TICKET-ID}"`.

   Aplica el criterio de búsqueda de "En todos los backends". **Un contenedor encontrado por
   vínculo manda sobre cualquier resultado de la búsqueda por título.**

2. **Si YA existe** (lo normal cuando el equipo abre la tarea de QA al planificar):
   **NO crees otro.** Escribí el análisis de Fase 1 en su descripción con `editJiraIssue` y colgá
   de él los casos como hijos. Si su descripción ya tenía contenido, mostrá el diff al usuario
   antes de pisarla. Crear un contenedor paralelo al que el equipo ya abrió es un duplicado, y es
   justo lo que este paso existe para evitar.

3. **Si no existe y el ticket amerita doc** → confirma con el usuario, luego `createJiraIssue` en
   `docs.jira.qaProject` con `issuetype = containerIssueType`, título según `containerTitlePattern`
   y **descripción = el análisis de Fase 1 completo** (gate, checklist, bloqueos, preguntas para
   PO/Dev, matriz de riesgos). Vinculalo al ticket de dev con `{docs.jira.linkType}`.
4. **Un issue hijo por caso de prueba**, con `issuetype = caseIssueType`, `parent` = el contenedor,
   título según `caseTitlePattern`, y descripción con la plantilla de especificación de abajo.
   El `{CP_ID}` se arma con `docs.jira.caseIdPattern` — `{DEV_NUM}` es el número del ticket de dev
   (de `US-994`, `994`) y `{NN}` el correlativo de dos dígitos del TC en la tabla.
5. Para actualizar el análisis después: `editJiraIssue` sobre el contenedor.

> **Nunca uses `transitionJiraIssue`.** Está en `deny`. Los CP los pasa a Finalizada el usuario, a
> mano. El harness documenta; no mueve estados.

#### Plantilla de especificación de cada CP (descripción del issue hijo)

Respeta estos encabezados y su orden — es el formato que el equipo ya usa.

**Leé `templates/06-especificacion-caso.md`**: ahí está la estructura literal a copiar.

**Reglas de la plantilla (no romper):**

- Las secciones `Endpoint`, `Payload` y `Queries de validación` van **solo si el caso es de
  backend/API** y tenés el dato real. **Nunca inventes una URL, un payload o una tabla.** Si no lo
  sabés, deja el caso con `Objetivo / Precondiciones / Datos de entrada / Resultado esperado` y
  anota en `Precondiciones` qué falta averiguar. Un payload inventado que alguien copia y ejecuta
  es peor que una sección ausente.
- `Resultado obtenido` se deja vacío en el análisis: lo completa [[qa-cierre-ciclo]] al cerrar.
- La prioridad (🔴/🟡/🟢) y el tipo del caso van al final del `## Objetivo`, porque el issue hijo
  no tiene esas columnas.

### Si `docs.backend` = `confluence`

1. Busca si ya existe: `searchConfluenceUsingCql` con `title ~ "[TICKET-ID] QA Analysis"` en `docs.confluence.spaceKey` (aplica el criterio de búsqueda de "En ambos backends").
2. Si la búsqueda se ejecutó OK, no hay resultados y el ticket amerita página → confirma con el usuario, luego `createConfluencePage` bajo `docs.confluence.parentPageId`.
3. Para actualizar (DEV/PROD después): `updateConfluencePage` sobre la misma página.

### Si `docs.backend` = `notion`

1. Busca si ya existe: `notion-search` query `[TICKET-ID] QA Analysis`, `query_type: internal` (aplica el criterio de búsqueda de "En ambos backends").
2. Si la búsqueda se ejecutó OK, no hay resultados y el ticket amerita página → confirma con el usuario, luego `notion-create-pages` bajo `docs.notion.parents.casos`.
3. Para actualizar: `notion-update-page` sobre la misma página.

### En todos los backends

- **Criterio de búsqueda — "cero resultados" NO es lo mismo que "búsqueda fallida":**
  - Búsqueda ejecutada OK con **cero resultados** → la página no existe; puedes crearla (previa confirmación del usuario, según la tabla escalonada).
  - Búsqueda que **FALLA técnicamente** (error del MCP, auth, red) → reintenta UNA vez. Si vuelve a fallar, DETENTE: informa el error al usuario y NO crees páginas — asumir "no existe" sobre un error técnico produce duplicados.
- Estructura: encabezado (ticket, fecha, estado, link Jira) → Fase 1 → Fase 2 (tabla + matriz de riesgos) → Resumen ejecutivo.
- **Naming:** `[STATUS_EMOJI] [TICKET-ID] - QA Analysis - [YYYY-MM-DD]`. Emoji inicial: `⚠️` (en progreso/con observaciones).
- **Muestra el borrador antes de crear o actualizar cualquier página o issue** (regla de oro del harness). Con `docs.backend = jira` eso incluye el contenedor **y** la lista completa de CP que vas a crear: título de cada uno y cuántos son. Crear 20 issues en Jira sin que el usuario los haya visto es exactamente lo que este harness existe para evitar.

## Respuesta final al usuario (corta)

```
╔══════════════════════════════════════════════════╗
║  ✅ WORKFLOW QA COMPLETADO — [TICKET-ID]        ║
╚══════════════════════════════════════════════════╝

📊 Resumen:
• Estado análisis: ✅/⚠️/❌
• Casos de prueba: [N] (🔴 n / 🟡 n / 🟢 n)
• Documentación: [link a Confluence/Notion / "Jira-only, sin página"]

🤖 ¿Quieres que evalúe automatización? (Fase 3) → Sí / No
```

Si el usuario responde "Sí" a Fase 3 → carga la skill [[qa-automatizacion]].

## Persistencia (opcional)

Si tienes memoria persistente disponible (Engram u otra), guarda el resultado del análisis: estado del gate, cantidad de casos, decisiones no obvias, ambigüedades detectadas. **Sin memoria persistente: omite este paso** — no afecta el análisis ni la documentación.
