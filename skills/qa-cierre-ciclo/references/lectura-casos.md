# Leer casos desde la doc — `qa-cierre-ciclo`

> Referencia de `skills/qa-cierre-ciclo/SKILL.md` (Paso 1). Es texto del `SKILL.md`, movido sin cambios para que ese archivo entre en el límite de tamaño de Antigravity. Las secciones y reglas que se nombran acá viven en ese `SKILL.md`.

Según `docs.backend`:

- **jira:** localiza el ticket de QA contenedor con `searchJiraIssuesUsingJql`
  (`project = {docs.jira.qaProject} AND issuetype = {containerIssueType} AND summary ~ "{TICKET-ID}"`),
  y luego lee **sus issues hijos** — los CP — con `parent = {QA-TICKET}`. De cada hijo tomás la key,
  el `CP_ID` y el título del summary. Ese es tu listado de casos: **no lo reconstruyas de memoria ni
  del análisis original.** Si un CP fue agregado o borrado a mano después del análisis, la verdad
  está en los hijos, no en el plan.
- **confluence:** busca con `searchConfluenceUsingCql` (`title ~ "[TICKET-ID] QA Analysis"` en `docs.confluence.spaceKey`) → `getConfluencePage` y extrae la tabla de casos (ID, Título, Prioridad, Tipo).
- **notion:** busca con `notion-search`, query `[TICKET-ID] QA Analysis`, `query_type: internal` → `notion-fetch` y extrae la tabla de casos.
