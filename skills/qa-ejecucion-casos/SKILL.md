---
name: qa-ejecucion-casos
description: >
  Ejecuta en el navegador los casos de prueba ya escritos de un ticket (Playwright MCP), en un
  ambiente configurado, y devuelve por caso qué hizo, qué esperaba, qué vio y una captura. NO
  publica nada: el informe es la propuesta que la persona revisa y confirma en qa-cierre-ciclo.
  Trigger: Cuando el usuario escribe "Ejecutar AMBIENTE TICKET-ID" (ej. "Ejecutar DEV US-1234"),
  o pide que la IA ejecute/corra en el navegador los casos de un ticket.
license: MIT
metadata:
  author: qa-harness-pro
  version: "1.0"
---

## When to Use

- El usuario escribe `Ejecutar [AMBIENTE] [TICKET-ID]` o pide ejecutar en el navegador los casos
  de un ticket.
- Los casos **ya existen** en la doc ([[qa-analisis-ticket]] los escribió) o, en tickets
  Jira-only, en un comentario del ticket que la persona confirma como fuente (Paso 2). Esta skill
  no escribe casos: si no hay, detente y ofrece el análisis.

Actúa como **"QA Test Executor"**. Ejecutas; no decides el resultado final ni publicas. El humano
dirige, la IA ejecuta.

## Configuración (cargar al inicio)

| Variable que usa la skill | Origen |
|---|---|
| Ambientes y sus URLs | `environments.list[]` (`key`, `label`, `urls`, `production`) |
| URLs de la suite | `automation.subprojects[].url` |
| Backend de la doc (para leer casos) | `docs.backend` y su bloque |
| Nombres de credenciales de prueba (opcional) | `profile/browser-secrets.env` — **solo los nombres** |
| Quien revisa | `profile.name` |

**Inicio de sesión: por defecto lo hace la persona** (ver "Login manual" en el Paso 4). Solo si
existe `profile/browser-secrets.env` y tiene el secreto que el caso necesita, puedes escribirlo tú
por nombre. **Nunca leas sus valores** (la lectura está en `deny`): para saber qué secretos
existen, corre `cut -d= -f1 profile/browser-secrets.env`, que muestra solo los nombres. Escribes
el NOMBRE (`QA_USER_PASSWORD`) y Playwright MCP pone el valor.

Si falta un valor → avisa antes de operar; no inventes URLs.

## Reglas críticas (NO romper)

1. **Solo URLs de los ambientes configurados.** Navegas únicamente a orígenes de
   `environments.list[].urls` y `automation.subprojects[].url`. El gate del navegador lo hace
   cumplir; tú no lo pones a prueba.
2. **Producción solo si la persona lo pide en este pedido**, con palabras explícitas. Un ambiente
   con `production: true` nunca se elige por defecto. Aunque lo pida, el runtime le vuelve a
   preguntar antes de navegar: eso no se esquiva.
3. **Solo datos de prueba.** Usas los "Datos de prueba" del caso tal cual. Nunca escribes
   contraseñas, tarjetas ni datos personales reales: credenciales solo por nombre de secreto.
4. **No inventas** (regla 3 de `AGENTS.md`). Paso ambiguo, dato que falta, elemento que no está →
   el caso queda ⏭️ Bloqueado con su motivo y una pregunta para la persona.
5. **Nunca Pass sin evidencia.** Un caso no ejecutado o ejecutado a medias nunca es ✅ Pass.
6. **Un bloqueo del gate no se esquiva.** Ni otra tool, ni otra URL, ni JavaScript. El caso queda
   ⏭️ Bloqueado (`FUERA_DE_ALCANCE`) y sigues con el siguiente.
7. **No publicas nada.** Ni Jira, ni Confluence, ni Notion. El informe se registra solo con
   [[qa-cierre-ciclo]], y ahí la persona confirma cada resultado.

## Flujo de ejecución

### Paso 0 — ¿Hay navegador con gate?

- Si no tienes las tools `browser_*` de Playwright MCP, **detente**: el MCP no está conectado.
  Indica `SETUP.md` → "Ejecución de casos en el navegador". No simules la ejecución.
- **Hoy el gate del navegador existe solo en Claude Code, abierto en la raíz del harness.** En
  Cursor, Antigravity o Codex, **detente aunque tengas tools `browser_*`**: ahí nada frena una URL
  de producción ni una contraseña literal. Explica que falta el gate de ese runtime (sección
  "Pendiente: navegador" de su `adapters/<runtime>/README.md`).

### Paso 1 — Resolver el ambiente

1. Toma el ambiente del pedido. Si no lo nombró, usa `environments.default` y dilo en el plan.
2. Búscalo en `environments.list`. Si no existe → DETENTE y muestra los `key` válidos.
3. Si no tiene `urls` → DETENTE: sin URL declarada no hay dónde ejecutar. Explica cómo agregarla
   (`docs/CONFIG.md`).
4. Si tiene `production: true` y la persona no pidió producción con palabras explícitas en este
   pedido → DETENTE y pregunta.

### Paso 2 — Leer los casos

Igual que el Paso 1 de [[qa-cierre-ciclo]] (su referencia `lectura-casos.md`, en la carpeta
`skills/qa-cierre-ciclo/references`): los casos salen **siempre** de la doc, con sus pasos, datos
de prueba y resultado esperado completos. Nunca de memoria ni del análisis original. Mismo
criterio de "cero resultados" vs "búsqueda fallida".

**Camino Jira-only** (la búsqueda en la doc funcionó y trajo cero resultados):

1. Lee el ticket en Jira (`getJiraIssue` con `tracker.cloudId`, incluyendo comentarios) y busca
   un comentario que contenga los casos: tabla con ID y título, y por caso sus pasos, datos de
   prueba y resultado esperado (típicamente el comentario del análisis o de una ejecución
   anterior).
2. Si lo hay, **no lo uses todavía**: muestra la fuente y pide confirmación, PARA y espera:
   ```
   📄 No hay página de casos en [docs.backend]. Encontré los casos en Jira:
   comentario [id] de [autor], [fecha] — [n] casos ([IDs]).
   ¿Uso este comentario como fuente de los casos?
   ```
3. Con el "sí", ese comentario es la doc para esta corrida: aplica las mismas reglas (casos
   completos, nada de memoria). Un caso del comentario sin pasos o sin resultado esperado queda
   ⏭️ Bloqueado (`DATO_FALTANTE` o `PASO_AMBIGUO`) con su pregunta. En el informe, anota la
   fuente: «Casos: comentario de Jira [id] ([fecha])».
4. Si hay varios comentarios con casos (ej. análisis y una ronda posterior), muéstralos todos y
   pregunta cuál usar: nunca los mezcles por tu cuenta.
5. Si no hay ninguno, **detente** y ofrece el análisis ([[qa-analisis-ticket]]).

### Paso 3 — Plan de la corrida (aprobación por corrida)

Antes de abrir el navegador, muestra y **espera el "sí"**:

```
🧪 PLAN DE EJECUCIÓN — [TICKET-ID] — [AMBIENTE]
URL base: [origen] · Producción: no / SÍ (pedido explícito)
| ID | Caso | ¿Se ejecuta? | Necesita |
|---|---|---|---|
| CP-01 | ... | Sí | login manual (usuario de [cliente]) |
| CP-05 | ... | No — NO_ES_DE_NAVEGADOR (pasos SQL) | — |
| CP-06 | ... | Sí, parcial — queda fuera: [lo que no se ve en la página] | — |
| CP-07 | ... | Sí — falta dato | nombre del botón nuevo |

📝 DATOS QUE NECESITO ANTES DE ARRANCAR
- CP-07: nombre para el botón nuevo (queda creado en [ambiente] y no se puede borrar)
- ...

¿Ejecuto los [n] casos marcados "Sí"? Si me pasas los datos de arriba, van con la corrida.
```

- Marca de entrada lo que no es de navegador y lo que ya sabes que va a bloquear.
- **Pide todos los datos en el plan, en un solo bloque.** Recorre cada caso marcado "Sí" y anota
  todo valor que el caso no trae y que vas a necesitar para escribir: nombres de lo que se crea,
  IDs, tokens, montos, cuentas. Que un dato falte a mitad de la corrida es un costo que el plan
  podía evitar. Si la persona no lo da, el caso queda ⏭️ Bloqueado (`DATO_FALTANTE`): nunca lo
  inventas.
- **Avisa los efectos que no se deshacen** (datos que se crean y no se pueden borrar, correos que
  se envían) al lado del caso que los produce.
- **Casos parciales:** si solo una parte del caso se puede hacer en el navegador, márcalo
  "Sí, parcial" y di qué queda fuera. Un caso parcial **nunca** termina en ✅ Pass (ver
  `references/clasificacion-resultados.md`).
- Si la persona saca casos, quedan ⏸️ No ejecutado (`NO_SELECCIONADO`). Sin "sí" explícito, no
  ejecutas.

### Paso 4 — Ejecutar caso por caso

Carpeta de evidencia: `ejecuciones/[TICKET-ID]-[AMBIENTE]-[YYYYMMDD-HHMM]/`.

Por cada caso, en orden:

1. Navega a la URL del ambiente y toma un `browser_snapshot` para ubicarte.
2. Ejecuta **cada paso tal cual está escrito**. Ubica los elementos por lo que el snapshot
   muestra (rol, texto, label). Si el paso nombra algo que no está → Bloqueado (`PASO_AMBIGUO`).
3. Credenciales — **login manual** (por defecto): cuando el caso pide iniciar sesión, navega a
   la pantalla de login, **no escribas nada** en usuario ni contraseña y detente con:
   `🔑 Inicia sesión con el usuario de [cliente/rol del caso] en la ventana de Chrome y escribe «listo».`
   PARA y espera. Con «listo», toma un `browser_snapshot`: si la sesión entró, sigue con el
   caso; si la persona dice que no pudo entrar, el caso queda ⏭️ Bloqueado (`PRECONDICION`).
   - La sesión dura mientras la ventana siga abierta: no vuelvas a pedir login para otro caso
     del mismo cliente/rol. Para cambiar de cliente, pide a la persona que cierre sesión e
     inicie con el otro, con el mismo «listo».
   - Si el caso **prueba el login mismo** (ej. contraseña incorrecta), la persona hace ese paso
     con los datos del caso y tú solo verificas el resultado.
   - En "Qué hice" del informe: «Inicio de sesión: lo hizo [profile.name]».
   - Solo si existe el secreto por nombre (ver Configuración): `browser_type` con el **nombre**
     del secreto. Nunca `browser_fill_form` en un campo de contraseña (no sustituye secretos).
4. En el momento de verificar el resultado esperado: `browser_take_screenshot` con
   `filename: "ejecuciones/.../[CP_ID].png"`. Si falla: también `[CP_ID]-fallo.png`.
5. Compara lo observado con el esperado **completo** y clasifica.

**Antes de clasificar, lee `references/clasificacion-resultados.md`** (en la carpeta de esta
skill: `skills/qa-ejecucion-casos/references/`): las cuatro etiquetas, los códigos de motivo y
cuándo un caso es Fail y cuándo Bloqueado.

Un caso bloqueado no detiene la corrida: anota la pregunta y sigue con el siguiente. Si el
ambiente se cae (`AMBIENTE_CAIDO`) en dos casos seguidos, detén la corrida: el resto queda
⏸️ No ejecutado (`CORRIDA_INTERRUMPIDA`). Al terminar: `browser_close`.

### Paso 5 — Informe

**Lee `templates/10-informe-ejecucion.md`** (ruta relativa a la raíz del repo del harness) y
respeta ese formato literal. Guárdalo como `informe.md` en la carpeta de evidencia y muéstralo en
el chat.

Después, las preguntas pendientes **de a una** (regla de `AGENTS.md`): pregunta, PARA y espera.
Con la respuesta, re-ejecuta ese caso y actualiza el informe. Nunca completes un resultado sin
re-ejecutar.

Cierra con:

```
Esto es una propuesta: nada se publicó.
Para registrarlo: «Cierre [AMBIENTE] [TICKET-ID]» — ahí revisas y confirmas cada resultado.
Las capturas están en ejecuciones/...; en Jira se suben a mano.
```

## Persistencia (opcional)

Si tienes memoria persistente (Engram u otra), guarda **cómo** se llegó a ejecutar (qué secreto,
qué precondición, qué bloqueó), nunca resultados como verdad: el resultado vale cuando la persona
lo confirma en el cierre. Sin memoria persistente: omite este paso.
