# Adaptar el harness a otro stack

El alcance v1 es **Jira** como tracker, **Jira, Confluence o Notion** como documentación y
**Claude Code, Cursor o Antigravity** como runtime. Si tu equipo usa otras herramientas, esta guía
te dice exactamente qué tocar y cuánto cuesta.

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

## Lo otro grande: un cuarto runtime (registrar un `--agent` nuevo)

Los tres runtimes soportados (`claude`, `cursor`, `antigravity`) no están cableados en el método:
son tres adaptadores más un nombre de agente que el instalador y el validador conocen. Sumar un
cuarto es agregar el adaptador y **registrar su valor de `--agent` en los dos scripts**. Si lo
registras en uno solo, el harness se instala y nadie lo valida — o al revés.

1. **Crea `adapters/<nuevo>/`** siguiendo el patrón de los tres existentes: un shim (`_<nuevo>.py`)
   que pone `core/` en el `sys.path`, los tres gates que llaman a `core/gates/`, y la config que ese
   runtime lea. **La lógica de los gates no se duplica**: vive una sola vez en `core/gates/`, y el
   adaptador solo traduce el formato de entrada y salida de los hooks de esa herramienta.
2. **Dale su archivo de reglas** y haz que **importe `AGENTS.md`**, como hacen
   `adapters/claude/CLAUDE.md` y `adapters/antigravity/GEMINI.md`. `AGENTS.md` es la fuente única:
   no se copia, se importa.
3. **Regístralo en `install.sh`:**
   - agrégalo a la variable `AGENTES` (es la lista que valida el valor de `--agent` y la que recorre
     `--agent all`);
   - escribe una función `install_<nuevo>()` — el despacho la busca por nombre, no hay una tabla
     aparte que mantener;
   - súmalo a la ayuda de `usage()`, que es lo que ve quien corre `./install.sh --help`.
4. **Regístralo en `validate-config.sh`:**
   - la misma variable `AGENTES` y la misma línea en `usage()`;
   - una función `validar_<nuevo>()`, y su llamada `en_scope <nuevo> && validar_<nuevo>`;
   - una función `hay_footprint_<nuevo>()`: es lo que decide si el runtime entra en la validación
     **sin** `--agent`. Sin ella, tu runtime solo se valida cuando lo piden por nombre.
5. **Usa la misma regla de identidad en los dos scripts.** El instalador tiene que poder reconocer
   lo suyo para reemplazarlo al reinstalar, y el validador tiene que reconocerlo igual para poder
   decir "esto es mío y está apuntando a otro clon". Si las dos reglas divergen, el validador miente.
   Los tres precedentes: Cursor se identifica por el **nombre del script** del hook (no por la ruta,
   que cambia si mueves el repo), Antigravity por el **grupo `qa-harness-pro`** y un sidecar propio,
   y Claude Code por la **forma del import** `@<algo>/AGENTS.md` y por los symlinks de `skills/`.
6. **Agrega tests.** `tests/test_*_hooks.py` para los gates del adaptador nuevo, y los asserts que
   correspondan en `tests/smoke.sh` para la instalación y la validación.

Esfuerzo: comparable a un tracker nuevo, pero más acotado, porque el método y los gates ya están
escritos. Lo que estás portando es el puente, no el harness.

## Lo que NO hay que tocar nunca

- El método (gate, tipos de escenarios, tabla de casos, métricas de cierre, matriz de riesgos).
- Los templates y assets — son agnósticos de herramienta.
- `qa-generacion-casos` — no toca ningún tracker; funciona igual en cualquier stack.
- Tu perfil y la regla de oro (borrador antes de publicar).

## Regla general

Cuando adaptes, **cambia la capa de herramienta, no el método**. Si te encuentras editando el gate
o el formato de los casos para acomodar una herramienta, algo va mal: esas piezas son la parte que
no depende de nada.
