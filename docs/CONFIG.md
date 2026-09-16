# Configuración — campo por campo

Tu configuración vive en dos archivos que TÚ creas (no se versionan con datos reales):

- `companies/<empresa>.json` — los datos de tu empresa (copiado de `_template.json`).
- `profile/profile.json` — quién eres tú (copiado de `profile.example.json`).

La empresa activa se elige con el campo **`activeCompany`** de tu `profile.json` (ej.
`"activeCompany": "acme"` → el agente lee `companies/acme.json`).

Cuando termines: corre `./validate-config.sh` — chequea JSON válido, campos obligatorios campo por
campo (tracker completo + el bloque del backend de docs que uses) y placeholders sin completar.
El bloque del backend que NO uses puede quedar tal cual vino en el template: el validador lo ignora.

No valida solo formato, valida **contenido**:

- `tracker.type` debe ser `"jira"` (v1 solo soporta Jira — ver `docs/ADAPTAR-OTRO-STACK.md`).
- `ticketPrefixes` no puede tener entradas vacías.
- `tracker.host` debe ser un **hostname limpio**: sin `https://`, sin `/`, sin `@`, sin puerto, sin espacios.
- `browseUrlPattern` debe empezar con `https://`, contener `{KEY}` y su **hostname real** debe ser
  exactamente `tracker.host` — se parsea la URL, no se busca la subcadena
  (`https://tuhost.evil.example/...` o `https://tuhost@evil.example/...` son error, igual que un
  patrón con el host del template).
- `.claude/settings.json` debe seguir prometiendo la seguridad del harness: `permissions.allow/ask/deny`
  como **listas de strings** (otro formato lo ignora Claude Code), `transitionJiraIssue`
  en `deny` y todas las escrituras externas (Jira/Confluence/Notion) en `ask` o `deny`.
- `.mcp.json` debe declarar el server `atlassian` oficial (y `notion` si tu backend es notion).
- Las skills deben estar enlazadas con symlinks que **resuelven a este repo** — un symlink roto o
  apuntando a otro lado no cuenta como enlazada.

---

## `companies/<empresa>.json`

### `company`

| Campo  | Qué es                          | Ejemplo        |
| ------ | ------------------------------- | -------------- |
| `name` | Nombre visible de la empresa    | `"Acme Corp"`  |
| `key`  | Clave corta interna             | `"ACME"`       |

### `tracker` — dónde viven los tickets (v1: Jira)

| Campo               | Qué es                                                        | Cómo obtenerlo                                              |
| ------------------- | ------------------------------------------------------------- | ---------------------------------------------------------- |
| `type`              | Tipo de tracker. v1 solo `"jira"` (otro valor = error del validador) | Fijo                                                 |
| `host`              | Tu host de Jira — solo el hostname (sin `https://`, sin rutas, sin `@`) | `tuempresa.atlassian.net`                        |
| `cloudId`           | El cloudId de tu instancia de Jira                            | `GET https://tuempresa.atlassian.net/_edge/tenant_info`    |
| `ticketPrefixes`    | Prefijos de tus proyectos                                     | `["PROJ", "BUG"]`                                          |
| `browseUrlPattern`  | Patrón de URL de un ticket (`{KEY}` se reemplaza). Debe ser `https://` y su hostname real debe ser exactamente `tracker.host` | `https://tuempresa.atlassian.net/browse/{KEY}` |

### `environments` — en qué ambientes cierra ciclos tu equipo

Define los ambientes de prueba de tu equipo. Las skills de cierre **no tienen ambientes
hardcodeados**: leen esta lista. Si tu equipo prueba solo en staging, declaras solo staging — y la
documentación que se publica en Jira/Confluence nombra el ambiente real, no uno inventado.

| Campo     | Qué es                                                    |
| --------- | --------------------------------------------------------- |
| `default` | El `key` que se usa si el usuario no nombra ambiente       |
| `list`    | Los ambientes disponibles (uno o más)                      |

Cada entrada de `list`:

| Campo                 | Qué es                                                                              |
| --------------------- | ----------------------------------------------------------------------------------- |
| `key`                 | Lo que se escribe en el trigger: `Cierre STG US-1234`                                |
| `label`               | Nombre largo para el comentario: `CIERRE DE PRUEBAS — AMBIENTE STAGING`              |
| `emoji`               | Prefijo del comentario y de la sección en la doc                                     |
| `final`               | `true` = no hay ambiente siguiente. Cambia la etiqueta de aprobación y el título de la página |
| `tone`                | `"técnico"` o `"formal"` — registro de redacción del comentario                      |
| `separateClosurePage` | `true` = además crea una página de cierre separada                                   |

**Un solo ambiente** (el equipo prueba únicamente en staging):

```json
"environments": {
  "default": "STG",
  "list": [
    { "key": "STG", "label": "STAGING", "emoji": "🏁", "final": true, "tone": "técnico", "separateClosurePage": false }
  ]
}
```

Con esta config, `qa-cierre-ciclo` maneja todo el flujo y `qa-cierre-prod` no se usa.

**Dos ambientes** (flujo clásico DEV → PROD):

```json
"environments": {
  "default": "DEV",
  "list": [
    { "key": "DEV",  "label": "DESARROLLO", "emoji": "🏁", "final": false, "tone": "técnico", "separateClosurePage": false },
    { "key": "PROD", "label": "PRODUCCIÓN", "emoji": "🚀", "final": true,  "tone": "formal",  "separateClosurePage": true }
  ]
}
```

> Si pides un cierre con un `key` que no está en `list`, la skill **se detiene** y te muestra los
> válidos. No cae al default en silencio: cerrar declarando un ambiente equivocado es peor que no
> cerrar.

### `docs` — dónde se documentan análisis y casos

| Campo     | Qué es                                          | Valores               |
| --------- | ----------------------------------------------- | --------------------- |
| `backend` | Qué herramienta de documentación usa tu equipo  | `"jira"`, `"confluence"` o `"notion"` |

**Si `backend` = `"jira"`** (tu equipo documenta en tickets, no en páginas): el análisis va a la
descripción de un ticket de QA contenedor, y cada caso de prueba es un issue hijo con su
especificación completa.

| Campo                    | Qué es                                                              | Ejemplo                                  |
| ------------------------ | ------------------------------------------------------------------- | ---------------------------------------- |
| `qaProject`              | Proyecto donde se crean los tickets de QA                           | `"QA"`                                   |
| `containerIssueType`     | Tipo del ticket contenedor que agrupa los CP                        | `"Epic"`                                 |
| `caseIssueType`          | Tipo de cada caso de prueba hijo                                    | `"Tarea"`                                |
| `containerTitlePattern`  | Patrón del título del contenedor                                    | `"Pruebas QA - [{service}] - {feature}"` |
| `caseTitlePattern`       | Patrón del título de cada CP. **Debe incluir `{CP_ID}`** — sin él, el cierre no puede identificar los casos | `"[{DEV_TICKET}][QA] {CP_ID} — {title}"` |

> Este backend necesita `createJiraIssue` y `editJiraIssue` en `permissions.ask` y cubiertos por el
> hook de publicaciones externas. Ya vienen así en `.claude/settings.json`; `validate-config.sh` lo
> verifica. `transitionJiraIssue` sigue en `deny`: el harness documenta, no mueve estados.

**Si `backend` = `"confluence"`** (recomendado si tu equipo es Atlassian puro — mismo MCP que Jira):

| Campo                   | Qué es                                    |
| ----------------------- | ----------------------------------------- |
| `confluence.spaceKey`   | La space de Confluence donde va la doc    |
| `confluence.parentPageId` | La página padre bajo la que se crea todo |

**Si `backend` = `"notion"`:**

| Campo                   | Qué es                                        |
| ----------------------- | --------------------------------------------- |
| `notion.parents.casos`  | El ID de la página padre de Notion para casos |

> Solo necesitas completar el bloque del backend que uses. El otro puede quedar como está.

### `automation` — opcional, para la skill de automatización

| Campo           | Qué es                                             |
| --------------- | -------------------------------------------------- |
| `framework`     | Tu framework de tests (ej. `"Playwright + TS"`)    |
| `workspacePath` | Ruta local a tu suite de automatización            |
| `subprojects`   | Sub-proyectos de tu suite (nombre / servicio / url) |

---

## `profile/profile.json`

| Campo           | Qué es                                                        |
| --------------- | ------------------------------------------------------------- |
| `name`          | Tu nombre. Aparece en los comentarios de cierre que se publican |
| `role`          | Tu rol (ej. `"QA Senior"`)                                    |
| `activeCompany` | Qué empresa de `companies/` usar (ej. `"acme"` → `companies/acme.json`) |
| `language`      | Idioma de trabajo (`"es"` / `"en"`)                           |
| `tone`          | Cómo quieres que suene el agente                              |
| `signature`     | Cómo firmas los cierres                                       |
