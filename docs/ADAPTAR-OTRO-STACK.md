# Adaptar el harness a otro stack

El alcance v1 es **Jira** como tracker y **Jira, Confluence o Notion** como documentación. Si tu
equipo usa otras herramientas, esta guía te dice exactamente qué tocar y cuánto cuesta.

---

## Lo fácil: cambiar de backend de documentación

Cero cambios en las skills. Es un campo de config:

```json
"docs": { "backend": "confluence" }   →   "docs": { "backend": "notion" }   →   "docs": { "backend": "jira" }
```

Completa el bloque del backend elegido (`docs/CONFIG.md`) y listo. Las skills ya traen las tres ramas.

## Lo medio: otro espacio de documentación (Google Docs, SharePoint, wiki propia)

Las skills documentan en pasos concretos y aislados (la sección "Documentación" de cada SKILL.md).
Para otro destino:

1. Necesitas un MCP server de esa herramienta (busca en el registry de MCP; existen para Google
   Drive, SharePoint y varias wikis).
2. En cada skill que documenta (`qa-analisis-ticket`, `qa-cierre-ciclo`, `qa-cierre-prod`), agrega
   una rama nueva en la sección "Documentación" siguiendo el patrón de las existentes: buscar
   si la página existe → crear bajo un parent → actualizar agregando secciones.
3. Agrega el bloque de config en `companies/_template.json` (ej. `docs.gdocs.folderId`).

Esfuerzo: un rato de edición cuidadosa. El método no cambia; cambia dónde se guarda.

## Lo grande: otro tracker (Azure DevOps, Linear, GitLab Issues)

Acá el cambio es real, porque el tracker está más entretejido: las skills leen el ticket
(`getJiraIssue`), tratan los comentarios de devs como autoritativos, y publican comentarios de
cierre (`addCommentToJiraIssue`).

Qué implica:

1. **MCP del tracker nuevo.** Azure DevOps, Linear y GitLab tienen MCP servers disponibles.
2. **Reemplazar las llamadas de lectura/escritura** en las 4 skills que tocan el tracker:
   - leer ticket con comentarios → el equivalente del tracker
   - comentar → el equivalente
3. **Ajustar la config:** en `tracker`, cambia `type` y los campos específicos (cloudId es de
   Jira; Azure usa organización/proyecto, Linear usa team).
4. **Revisar los triggers:** `Cierre DEV [TICKET-ID]` funciona igual; solo cambia el patrón de IDs.

Esfuerzo: una tarde de trabajo con calma, skill por skill. El flujo (gate → casos → cierre) y los
formatos de comentario quedan idénticos — eso es lo que compraste, y es portable.

## Lo que NO hay que tocar nunca

- El método (gate, tipos de escenarios, tabla de casos, métricas de cierre, matriz de riesgos).
- Los templates y assets — son agnósticos de herramienta.
- `qa-generacion-casos` — no toca ningún tracker; funciona igual en cualquier stack.
- Tu perfil y la regla de oro (borrador antes de publicar).

## Regla general

Cuando adaptes, **cambia la capa de herramienta, no el método**. Si te encuentras editando el gate
o el formato de los casos para acomodar una herramienta, algo va mal: esas piezas son la parte que
no depende de nada.
