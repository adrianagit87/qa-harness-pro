# Publicación con `docs.backend` = `confluence` o `notion` — `qa-analisis-ticket`

> Referencia de `skills/qa-analisis-ticket/SKILL.md` (sección "Documentación"). Es texto del `SKILL.md`, movido sin cambios para que ese archivo entre en el límite de tamaño de Antigravity. Las secciones y reglas que se nombran acá viven en ese `SKILL.md`.

### Si `docs.backend` = `confluence`

1. Busca si ya existe: `searchConfluenceUsingCql` con `title ~ "[TICKET-ID] QA Analysis"` en `docs.confluence.spaceKey` (aplica el criterio de búsqueda de "En ambos backends").
2. Si la búsqueda se ejecutó OK, no hay resultados y el ticket amerita página → confirma con el usuario, luego `createConfluencePage` bajo `docs.confluence.parentPageId`.
3. Para actualizar (DEV/PROD después): `updateConfluencePage` sobre la misma página.

### Si `docs.backend` = `notion`

1. Busca si ya existe: `notion-search` query `[TICKET-ID] QA Analysis`, `query_type: internal` (aplica el criterio de búsqueda de "En ambos backends").
2. Si la búsqueda se ejecutó OK, no hay resultados y el ticket amerita página → confirma con el usuario, luego `notion-create-pages` bajo `docs.notion.parents.casos`.
3. Para actualizar: `notion-update-page` sobre la misma página.
