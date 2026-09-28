# Registrar el cierre en la doc — `qa-cierre-ciclo`

> Referencia de `skills/qa-cierre-ciclo/SKILL.md` (Paso 4, puntos 2 y 3). Es texto del `SKILL.md`, movido sin cambios para que ese archivo entre en el límite de tamaño de Antigravity. Las secciones y reglas que se nombran acá viven en ese `SKILL.md`.

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

## Convención de naming de la página de doc

`[STATUS_EMOJI] [TICKET_ID] - QA Analysis - [YYYY-MM-DD]`

Progresión de emoji: `⚠️` (en progreso) → `✅ APROBADO` (aprobado en un ambiente con `final: false`) → `✅ APROBADO VALIDADO EN [AMBIENTE]` (aprobado en el ambiente con `final: true`).

Con un solo ambiente `final: true` la progresión es directa. Por ejemplo, con solo `STG`: `⚠️` → `✅ APROBADO VALIDADO EN STG`.
