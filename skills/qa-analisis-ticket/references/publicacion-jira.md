# Publicación con `docs.backend` = `jira` — `qa-analisis-ticket`

> Referencia de `skills/qa-analisis-ticket/SKILL.md` (sección "Documentación" → "Si `docs.backend` = `jira`"). Es texto del `SKILL.md`, movido sin cambios para que ese archivo entre en el límite de tamaño de Antigravity. Las secciones y reglas que se nombran acá viven en ese `SKILL.md`.

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

#### Plantilla de especificación de cada CP (descripción del issue hijo)

Respeta estos encabezados y su orden — es el formato que el equipo ya usa.

**Leé `templates/06-especificacion-caso.md`** (ruta relativa a la raíz del repo del harness, no
al proyecto donde estés trabajando): ahí está la estructura literal a copiar. Si no lo encontrás,
pedí la ruta del harness antes de improvisar el formato.

**Reglas de la plantilla (no romper):**

- Las secciones `Endpoint`, `Payload` y `Queries de validación` van **solo si el caso es de
  backend/API** y tenés el dato real. **Nunca inventes una URL, un payload o una tabla.** Si no lo
  sabés, deja el caso con `Objetivo / Precondiciones / Datos de entrada / Resultado esperado` y
  anota en `Precondiciones` qué falta averiguar. Un payload inventado que alguien copia y ejecuta
  es peor que una sección ausente.
- `Resultado obtenido` se deja vacío en el análisis: lo completa [[qa-cierre-ciclo]] al cerrar.
- La prioridad (🔴/🟡/🟢) y el tipo del caso van al final del `## Objetivo`, porque el issue hijo
  no tiene esas columnas.
