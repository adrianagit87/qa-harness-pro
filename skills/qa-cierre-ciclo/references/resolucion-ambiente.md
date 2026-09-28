# Resolución del ambiente — `qa-cierre-ciclo`

> Referencia de `skills/qa-cierre-ciclo/SKILL.md` ("Resolución del ambiente", punto 3). Es texto del `SKILL.md`, movido sin cambios para que ese archivo entre en el límite de tamaño de Antigravity. Las secciones y reglas que se nombran acá viven en ese `SKILL.md`.

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
