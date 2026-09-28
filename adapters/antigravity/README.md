# QA Harness Pro — port a Antigravity (Gemini)

Port del harness completo a **Antigravity**. **No se pierde casi nada**: Antigravity soporta MCP,
skills y hooks.

## Instalación

```bash
./install.sh --agent antigravity
```

Es el instalador único del harness, desde la raíz del repo: ya no hay un script por herramienta.

Fusiona la config en `~/.gemini/config/` sin pisar lo que ya tengas (hace backup con timestamp de
todo lo que toca).

Una instalación de Antigravity deja fuera del repo **tres archivos y una copia por skill**: los dos
de `~/.gemini/config/` (`hooks.json`, `mcp_config.json`), un sidecar propio del harness
(`~/.gemini/qa-harness-state.json`) y, en `~/.gemini/config/skills/<skill>/`, una **copia real** de
cada skill de este repo (la carpeta entera, `references/` incluida) con una marca
`.qa-harness-copia.json` adentro: de qué repo vino, el hash del contenido y cuándo se instaló. Por qué
copias y no `skills.json` ni symlinks: ver [Cómo llegan las skills](#cómo-llegan-las-skills).

`~/.gemini/config/skills/` es una carpeta **compartida**: otras herramientas dejan ahí las suyas
(gentle-ai, por ejemplo). Por eso el instalador no respalda ni pisa nada ajeno, a diferencia de lo
que hace con `~/.claude/skills/`: si con el nombre de una skill del harness ya hay una carpeta sin
nuestra marca o un symlink que apunta a otro lado, **avisa y la saltea**. Solo reemplaza lo que puede
probar que es suyo: carpetas con la marca, y los symlinks que dejaba la versión anterior del
instalador (los que apuntan a `skills/<nombre>` de este repo, del clon que anotó el sidecar aunque
ya no exista, o de otro clon del harness). Dentro de una copia nuestra el espejo es exacto: lo que
borras en el repo desaparece de la copia, y una skill que sale del repo se retira. La copia nueva se
arma aparte y recién después reemplaza a la vieja: nunca queda una a medias. La lógica vive en
`adapters/antigravity/copias_skills.py`.

El sidecar existe porque el schema de `skills.json` es de Antigravity, así que no podemos marcar
nada como nuestro sin meterle campos inventados a tu config. Anotamos aparte **qué `skills/` instaló
la última vez y qué skills copió**; con eso se reconocen los restos de un clon mudado y la entrada
vieja de `skills.json` que dejaban las versiones anteriores del instalador, que ahora se retira
(solo esa: tus otras entradas no se tocan, y si no hay nada nuestro el archivo ni se reescribe).
Puedes mover el sidecar con la variable `QA_HARNESS_STATE`.

## Qué se comparte con Claude Code

**Las skills son las mismas, pero en Antigravity van copiadas.** La fuente es el `skills/` de este
repo, el mismo que Claude Code y Codex usan por symlink. La diferencia: si editas una skill, Claude
Code y Codex la ven al instante, y Antigravity **recién cuando reinstalas** (`./install.sh --agent
antigravity`). Ver [El costo de copiar](#el-costo-de-copiar-copias-viejas).

Lo mismo con `companies/*.json` y `profile/profile.json`: son archivos, los lee cualquiera.

## Cómo llegan las skills

Antigravity tiene **dos mecanismos** distintos, y las pruebas en vivo mostraron que no son
equivalentes:

- **El registro (`skills.json`) hace que las CONOZCA.** Una entrada `{"path": ".../skills"}` en
  `~/.gemini/config/skills.json` le suma el directorio a su descubrimiento: el agente lista las skills
  por nombre y descripción.
- **Las carpetas estándar son de donde las LEE.** Cuando va a abrir un `SKILL.md`, el agente busca en
  las rutas que su propio sistema le enseña: `<workspace>/.agents/skills/<nombre>/SKILL.md`, la legacy
  `<workspace>/.agent/skills/<nombre>/SKILL.md` y la global `~/.gemini/config/skills/<nombre>/SKILL.md`.

**Lo observado, el 2026-09-28** (Antigravity, chat nuevo, workspace ajeno al harness):

1. **Solo el registro** (la versión vieja del instalador): el agente listó `qa-analisis-ticket`,
   `qa-baseline` y las demás, pero al ir a leer un `SKILL.md` lo buscó en esas tres rutas. Ninguna
   tenía las del harness, así que cayó a buscar con `find` por todo el HOME — y ahí puede agarrar
   **cualquier copia** del método (una carpeta vieja en el Escritorio, un clon de prueba).
2. **Symlinks en la carpeta global**: el descubrimiento **funcionó** — resolvió
   `~/.gemini/config/skills/qa-analisis-ticket` sin `find`, y notó que era un symlink al repo. Pero la
   **lectura falló**: *"Permission denied — Matches default system policy"*. Antigravity resuelve el
   symlink y aplica su política de workspace sobre la ruta **real**, que queda fuera del workspace
   abierto. Ni el `SKILL.md` ni `references/` se pueden leer así.
3. **Control**: en la misma sesión, leer un archivo **real** de la carpeta global
   (`~/.gemini/config/skills/branch-pr/SKILL.md`, de otra herramienta) **funcionó**.

**Qué hace ahora el instalador.** Una copia real por skill en `~/.gemini/config/skills/`, y
**retira** del `skills.json` la entrada del harness. Por qué no dejar también el registro: el mismo
contenido descubierto por dos caminos tiende a listar cada skill dos veces. La evidencia:

- La ruta global es la **documentada** para skills: *"Global skills:
  `~/.gemini/config/skills/<skill-folder>/`"* ([docs de skills](https://gweb-jetski.appspot.com/docs/skills)),
  y la misma referencia embebida en `agy` las nombra como destino (*"`<workspace>/.agents/skills/<name>/`
  or `~/.gemini/config/skills/<name>/`"*).
- `skills.json` está pensado para lo que vive **fuera** de esas rutas. La referencia embebida en `agy`
  lo dice así: *"JSON configuration files allow you to explicitly register and manage customizations
  that are stored outside the default discovery locations"*.
- La documentación **no dice** qué pasa si una skill aparece por los dos caminos. Lo más cercano es
  otro instalador ([jpolvora/workflow-skills#335](https://github.com/jpolvora/workflow-skills/pull/335)):
  su revisión advierte que dejar restos en `~/.gemini/config/skills/` junto a la entrada de
  `skills.json` provoca *descubrimiento duplicado*. Es un indicio de terceros, no un contrato; alcanza
  para no arriesgarlo.

### El costo de copiar: copias viejas

Una copia es una foto: si editas `skills/` y no reinstalas, Antigravity sigue leyendo la versión
anterior, y no avisa. Cómo se detecta:

- **`./validate-config.sh --agent antigravity`** compara el contenido de cada copia con el de su
  skill en el repo (hash de todo el árbol, sin la marca) y avisa *"copia desactualizada: corre
  ./install.sh --agent antigravity"*. También avisa si una copia vino de otro clon, si falta, o si
  en su lugar hay un symlink o una carpeta ajena.
- **Reinstalar es la reparación**, y es barato: lo que ya está al día no se reescribe.

**Lo que NO se hizo, y por qué.** Avisar la deriva en plena sesión desde un hook de Antigravity: su
`PreToolUse` solo puede devolver `allow`/`deny`/`ask`, así que el aviso sería un `ask` en cada
llamada a una tool mientras la copia siga vieja — ruido que termina en "aprobar todo". Y recordarlo
desde el gate post-edición de Claude Code o Codex cuando cambia algo en `skills/`: ese gate hoy solo
sabe permitir, bloquear o abstenerse (`core/gates/contract.py`); un recordatorio sería un bloqueo
falso en cada edición de una skill, o un canal nuevo en los cuatro runtimes. Ninguno de los dos es
barato ni silencioso; el validador sí.

### Prueba en vivo

Después de reinstalar y reiniciar Antigravity, en un **chat nuevo abierto fuera del repo del
harness**:

> Carga la skill qa-analisis-ticket usando tu mecanismo de skills, sin buscar en el disco… ¿qué ruta
> te indica? lee references/publicacion-jira.md relativo a esa carpeta y cítame su primera línea

Esperado: la ruta es `~/.gemini/config/skills/qa-analisis-ticket` (no la del repo: ya no hay
symlink que resolver), lee el archivo **sin** "Permission denied" y cita su primera línea, que
empieza con `# Publicación con`. Si no la encuentra, si corre `find` o si la lectura falla, avisa:
el mecanismo hay que revisarlo.

### Dos trampas fuera del harness

- **Copias viejas del método en tu HOME.** Un agente que cae a buscar por el disco agarra la primera
  que encuentra, y puede ser una copia vieja (una carpeta en el Escritorio, un clon de prueba) con
  reglas y referencias desactualizadas. Si tienes copias que ya no usas, bórralas o sácalas de tu HOME.
  `./validate-config.sh --agent antigravity` avisa si en `~/.gemini/config/skills/` hay una carpeta
  con el nombre de una skill del harness que no es copia nuestra (el instalador no la pisa).
- **El `AGENTS.md` de otros proyectos.** Algunos repos le dicen a Antigravity que sus skills viven en
  `.agent/skills/` (la ruta legacy). Si abres uno de esos, el agente puede buscar las del harness ahí,
  no encontrarlas y caer a buscar por el disco. No es algo que el harness pueda arreglar desde acá:
  si pasa, pídele explícitamente que use su mecanismo de skills.

## Cómo llegan las reglas

Copiar las skills **no alcanza**: el agente las ve listadas, pero las reglas del método —que no
publique sin mostrarte el borrador, que no toque estados de Jira, que no invente IDs— viven en
`AGENTS.md`.

**Lo medido, el 2026-09-18.** Con Antigravity IDE abierto en la raíz de este repo, `AGENTS.md`
aparece en *Customizations → Rules* como regla de proyecto **por sí solo**: Antigravity lo levanta
sin que nadie se lo pida. En el CLI (`agy 1.2.6`) las reglas también llegan — `PING-HARNESS`
devuelve el contrato correcto y el agente arranca cargando la config, que es lo que `AGENTS.md`
manda.

**Lo que NO pudimos aislar.** En el CLI no sabemos por cuál de los dos caminos llegan: `agy -p`
resuelve su propio workspace y no el directorio desde donde lo lanzas, así que la prueba terminó
corriendo contra un repo que tenía los dos. Y en el IDE pasa lo contrario de lo esperable: la rule
de `.agents/rules/` **no** aparece en el panel, ni siquiera reiniciando.

**Por qué el instalador la deja igual.** Que `AGENTS.md` se levante solo no está en la
documentación oficial; lo que **sí** está documentado es que Antigravity lee las reglas del
workspace desde `<workspace>/.agents/rules/`. Depender solo del camino no documentado es frágil:
si una versión futura deja de hacerlo, no te enterarías —las skills seguirían registradas y el
análisis seguiría saliendo, sin las reglas—. Por eso el instalador copia
`adapters/antigravity/rules/qa-harness.md` a `.agents/rules/qa-harness.md` de este repo, el mismo
mecanismo que usa Cursor con `.cursor/rules/`. La rule es un puntero: importa `AGENTS.md` y no
repite nada. Si los dos caminos cargan, lees lo mismo dos veces y no pasa nada.

**La importación es `@/AGENTS.md`, no una ruta relativa.** Antigravity resuelve un `@` relativo
contra la ubicación del archivo de reglas, y un `@/ruta` absoluto lo intenta primero como ruta real
del sistema y, si no existe, lo resuelve contra la raíz del workspace. La forma absoluta sobrevive a
que el archivo se mueva de carpeta; la relativa se rompe en silencio, que es la falla que menos se
nota. (El caso patológico sería que existiera un `/AGENTS.md` en la raíz del sistema de archivos:
ahí ganaría ese. No es un escenario realista.)

**El modo de activación hay que confirmarlo en la UI.** Antigravity documenta cuatro modos (manual
por `@mención`, *Always on*, decisión del modelo y glob), pero **no pudimos verificar la sintaxis
para fijarlo desde el archivo**. Por eso la rule va en markdown pelado, sin frontmatter inventado:
antes que adivinar un contrato y que el archivo se rechace entero, se deja el archivo válido y se te
avisa. Después de instalar, comprueba en la UI de Antigravity que `qa-harness` quede en **Always on**.
El `PING-HARNESS` de `SETUP.md` es el que te dice si de verdad cargó.

**El instalador no toca `~/.gemini/GEMINI.md`.** Antigravity también admite reglas globales ahí, pero
ese archivo es tuyo y puede tener años de contenido personal: pisarlo no tiene vuelta atrás. Si
quieres las reglas del harness en todas tus sesiones, agrega tú la línea `@/ruta/absoluta/AGENTS.md`
a tu `~/.gemini/GEMINI.md`.

## Equivalencias

| Componente | Claude Code | Antigravity |
|---|---|---|
| Skills | `~/.claude/skills/` (symlinks) | `~/.gemini/config/skills/` (copias sincronizadas por el instalador; `skills.json` ya no se usa) |
| MCP | `.mcp.json` del repo | `~/.gemini/config/mcp_config.json` |
| Hooks | `.claude/settings.json` → `hooks` | `~/.gemini/config/hooks.json` |
| Permisos ask/deny | bloque `permissions` | **Dentro del hook**, vía `decision` |
| Memoria de lo instalado | no hace falta: un symlink se ve y se reemplaza solo | `~/.gemini/qa-harness-state.json` (sidecar del harness: qué `skills/` y qué skills copió; `QA_HARNESS_STATE` lo mueve) |
| Tamaño de las skills | sin límite conocido | límite documentado de 12.000 caracteres por archivo de reglas — todas las skills quedan por debajo; ver la limitación conocida más abajo |
| Reglas del agente | `AGENTS.md` (fuente única), importado desde `adapters/claude/CLAUDE.md` | el mismo `AGENTS.md`, importado desde `<workspace>/.agents/rules/qa-harness.md` (scope de proyecto — Antigravity NO lee `~/.gemini/GEMINI.md` por workspace) |

## Las tres diferencias que importan

### 1. Los permisos viven en el hook

Antigravity no tiene un bloque `permissions`. En su lugar, un `PreToolUse` devuelve
`allow` / `deny` / `ask` / `force_ask`.

`validate-external-write.py` hace las dos cosas de una: deniega las transiciones de Jira y pide
`force_ask` en toda escritura externa. `force_ask` ignora el cache de "Always Allow" — o sea que
**cada publicación se confirma**, aunque hayas apretado "siempre permitir" antes. Es más estricto
que el original.

### 2. El gate post-edit llega un turno tarde

El `PostToolUse` de Antigravity solo puede devolver `{}`: no hay canal de feedback al modelo.

La solución son dos hooks: `check-after-edit.py` corre los checks y deja una marca si falla;
`surface-pending-check.py` la levanta en la siguiente llamada y la convierte en un `ask`. El gate
existe, pero avisa un paso después.

#### Limitación conocida: lo que escribe la terminal no pasa por este gate

`check-after-edit.py` solo mira las tools de edición: un `run_command` que escribe un archivo
(`printf '{"a": }' > x.json`, `sed -i`, un script que genera archivos) no se revisa. En Claude
Code, Cursor y Codex ese camino sí está cubierto (`core/gates/post_shell.py`): foto del disco en
el `PreToolUse` del comando, diff en el `PostToolUse`, y cada archivo que **ese** comando creó o
modificó pasa por post-edición. Acá no se implementó, y no por falta del canal de vuelta — la
marca diferida alcanzaría —, sino por el **par**:

- **No hay un id por llamada.** El payload de `PreToolUse` y `PostToolUse` trae `toolCall`
  (`name`, `args`), `stepIdx` y los campos comunes (`conversationId`, `workspacePaths`,
  `transcriptPath`, `artifactDirectoryPath`, `modelName`); `PostToolUse` suma `error` si falló.
  Nada equivalente al `tool_use_id` de los otros tres runtimes.
- **`stepIdx` no alcanza como clave, según lo documentado.** En `PreToolUse` es "el índice del
  paso actual de la trayectoria"; en `PostToolUse`, "el índice del paso completado". Que sea el
  mismo número para las dos mitades de una llamada no está dicho en ningún lado.
- **Una clave adivinada (`conversationId` + `CommandLine`) no es segura.** Dos comandos iguales
  seguidos o en paralelo se pisan la foto, y `run_command` puede seguir corriendo en segundo plano
  después de `WaitMsBeforeAsync`: el `PostToolUse` llega antes de que termine de escribir.

Emparejar mal no daría falsos positivos (un post sin foto se abstiene), pero sí un gate que parece
puesto y en la práctica casi nunca revisa nada. Preferimos decirlo.

Fuentes: la [referencia de hooks de Antigravity](https://gweb-jetski.appspot.com/docs/hooks)
(contratos de `PreToolUse` y `PostToolUse`, y los campos comunes) y la misma referencia embebida
en el binario de `agy` 1.2.6 (*"`PostToolUse` Contract … Expects an empty JSON object `{}`"*).

**Cómo cerrarlo:** en una sesión real, registrar a un log el `stepIdx` y el `conversationId` que
reciben el `PreToolUse` y el `PostToolUse` de un mismo `run_command` (varias veces, con comandos
repetidos y con uno que pase a segundo plano). Si el `stepIdx` coincide siempre, la clave
`(conversationId, stepIdx)` más la marca diferida de este README alcanzan para portar el gate.

### 3. Los nombres de las tools no están documentados

**Este es el punto que hay que cerrar a mano.**

En Claude Code las tools MCP se llaman `mcp__atlassian__createJiraIssue`. En Antigravity, la
documentación no especifica el formato. Por eso los hooks:

- Corren con `matcher: "*"` (sobre toda llamada), no sobre un nombre adivinado
- Reconocen las tools **por patrón** sobre el nombre (`jira.*create.*issue`, etc.), no por igualdad
- Anotan en `~/.gemini/qa-harness-unknown-tools.log` cualquier tool que huela a Atlassian/Notion y
  no haya matcheado

### Cómo cerrarlo

1. Instala y reinicia Antigravity.
2. Autentica el MCP de Atlassian.
3. Pídele que **lea** un ticket (`getJiraIssue`) y que **comente** en uno.
4. Mira el log:

   ```bash
   bat ~/.gemini/qa-harness-unknown-tools.log
   ```

5. Si aparece algo, agrega la herramienta al catálogo en `core/gates/catalogo.py`.
   Es el único lugar: los tres runtimes la heredan.

6. **Verifica que el gate tiene dientes**: pídele que publique un comentario que contenga
   `PON-AQUI-EL-ID`. Debe bloquearlo. Si lo publica, el matcher no está enganchando y hay que
   volver al paso 4.

> No saltees el paso 6. Un gate desconectado no avisa que está desconectado: simplemente deja pasar
> todo, y tú crees que estás protegida.

## Limitación conocida: las skills grandes pueden no cargar

**Esto no está en las tres diferencias de arriba porque no es una diferencia de diseño: es un techo
del runtime, y puede dejarte trabajando sin método sin que nadie te avise.**

### Lo que está medido

Antigravity documenta un límite de **12.000 caracteres por archivo de reglas**. Estos son los
tamaños reales de las seis skills. **`wc -c` cuenta bytes, no caracteres**, y estos archivos están
llenos de emojis y acentos: por eso las dos columnas no coinciden. El límite está expresado en
caracteres, así que la columna que manda es la primera:

| Skill | Caracteres | Bytes (`wc -c`) | ¿Supera los 12.000? |
|---|---:|---:|---|
| `skills/qa-cierre-prod/SKILL.md` | 10.154 | 10.952 | no |
| `skills/qa-analisis-ticket/SKILL.md` | 9.989 | 10.216 | no (antes: 13.547) |
| `skills/qa-cierre-ciclo/SKILL.md` | 9.970 | 10.387 | no (antes: 14.322) |
| `skills/qa-baseline/SKILL.md` | 9.564 | 9.804 | no |
| `skills/qa-automatizacion/SKILL.md` | 5.053 | 5.155 | no |
| `skills/qa-generacion-casos/SKILL.md` | 3.159 | 3.453 | no |

Las dos que lo superaban son las dos más importantes del método: el análisis de ticket —el corazón
del harness— y el cierre de ciclo. `tests/test_skills_tamano.py` falla si cualquier `SKILL.md`
vuelve a pasar los 12.000 caracteres (contados con `len()` sobre el texto decodificado, no en
bytes).

### Qué se hizo

**Primer paso: plantillas afuera.** Las dos skills grandes tenían plantillas de salida pegadas en
línea, duplicando lo que ya vive en `templates/`. Se movieron a
`templates/06-especificacion-caso.md`, `templates/07-comentario-cierre-ciclo.md` y
`templates/08-comentario-ejecucion-cp.md`, y en la skill quedó un puntero a la ruta exacta. No
alcanzó: las plantillas en línea eran apenas ~600 y ~2.200 caracteres. El volumen de estas skills no
son plantillas, es método — las reglas de publicación, el criterio de aprobación, la resolución de
ambiente. Recortar eso para entrar en el número sería cambiar el método por un número, que es justo
el humo que este harness existe para evitar.

**Segundo paso: divulgación progresiva, sin recortar nada.** El `SKILL.md` queda como punto de
entrada —cuándo usarla, la carga de config, la lista ordenada de pasos y las reglas que tienen que
estar **siempre** en contexto— y el detalle de cada paso se movió **textual** a
`skills/<skill>/references/`, dentro de la carpeta de la skill. En el paso quedó un puntero
imperativo: *"Antes de ejecutar este paso, lee `references/<tema>.md`"*.

| Skill | Referencia | Qué se movió |
|---|---|---|
| `qa-analisis-ticket` | `references/publicacion-jira.md` | Publicación con `docs.backend = jira`: buscar el contenedor, reusarlo o crearlo, un hijo por CP, y la plantilla de especificación |
| `qa-analisis-ticket` | `references/publicacion-confluence-notion.md` | Publicación en Confluence y en Notion |
| `qa-analisis-ticket` | `references/respuesta-final.md` | El formato de la respuesta final |
| `qa-cierre-ciclo` | `references/resolucion-ambiente.md` | Qué campo del ambiente se usa dónde, y el caso de un solo ambiente |
| `qa-cierre-ciclo` | `references/lectura-casos.md` | Cómo leer los casos en cada backend |
| `qa-cierre-ciclo` | `references/metricas-aprobacion.md` | Cálculo de métricas, criterio de aprobación y excepción de alcance |
| `qa-cierre-ciclo` | `references/publicacion-doc.md` | Registrar el cierre en la doc por backend, página separada y naming |
| `qa-cierre-ciclo` | `references/respuesta-final.md` | El formato de la respuesta al usuario |

**Qué NO se movió, a propósito:** lo que tiene que valer aunque el agente no abra ninguna
referencia. Mostrar el borrador antes de publicar, no transicionar tickets nunca, el silencio nunca
es Pass, "cero resultados" no es "búsqueda fallida", detenerse ante un ambiente que no existe, no
inventar URLs, payloads, `id` ni evidencias, y todas las "Reglas críticas". Esas siguen en el
`SKILL.md`. Lo que se movió son procedimientos: una guarda que protege una acción viaja junto a la
acción que describe.

Ninguna línea del método se perdió: cada línea no vacía de los `SKILL.md` anteriores existe, igual,
en el `SKILL.md` nuevo o en una de sus referencias. Solo se agregaron los punteros y un encabezado
por referencia.

### Lo que se observó (antes del cambio)

Probado contra una instalación real de Antigravity el **2026-09-16**, abriendo Antigravity **fuera**
del repo del harness:

- Listó **las cinco skills por su nombre**. O sea que el registro de `skills.json` funcionaba: las veía.
- **No pudo cargar `qa-analisis-ticket`**, y reportó por sí mismo que había quedado excluida por un
  límite de contexto.

### Qué significa en la práctica

En Antigravity, una skill por encima del límite puede quedar **anunciada pero no cargada**. Y ese es
exactamente el modo de falla que el harness existe para evitar: el agente sabe que la skill existe,
dice que la va a usar, y después trabaja **de memoria** en vez de seguir el método. El resultado sale
igual, y sale plausible. Lo que se pierde en silencio es el gate de calidad, el formato de los casos
y las reglas de publicación.

La partición ataca eso, pero trae su propio modo de falla: un agente que carga el `SKILL.md` y **no
abre la referencia** que el paso le pide. Por eso las reglas que no pueden faltar quedaron en el
`SKILL.md`, y por eso los punteros son imperativos y no un "ver también".

### Qué NO está probado

**La partición no está verificada en una instalación real de Antigravity.** Los tamaños están
medidos y el test los cuida; que Antigravity cargue ahora las dos skills, y que su agente abra las
referencias cuando el paso se lo pide, no. Tres motivos concretos:

1. El límite de 12.000 caracteres está documentado para **archivos de reglas**, no explícitamente
   para skills. Que aplique a `SKILL.md` es lo más razonable dados los tamaños, pero es inferencia.
2. Que un modelo diga por qué falló **no es autoritativo**. La autoexplicación de un LLM sobre su
   propio contexto es un indicio, no evidencia.
3. Que Antigravity resuelva `references/<tema>.md` contra la carpeta de la skill cuando trabajas
   **fuera** del repo del harness tampoco está probado. La copia es de la carpeta entera, así que
   los archivos están ahí; lo que no sabemos es si el agente conoce la ruta de la carpeta de la
   skill que cargó. Es la misma incertidumbre que ya tienen los punteros a `templates/`: si no
   encuentra una referencia, pásale la ruta absoluta del repo.
4. **Que Antigravity lea las copias no está verificado en vivo con este instalador.** Lo que sí
   se vio el 2026-09-28: con symlinks el descubrimiento funciona y la lectura falla por la política
   de workspace, y un archivo real de otra herramienta en la misma carpeta se lee. Que las copias se
   comporten como ese archivo real es lo esperable, pero falta verlo: la
   [prueba en vivo](#prueba-en-vivo) lo cierra.

### El experimento que lo confirmaría

Si quieres cerrarlo de verdad:

1. Reinicia Antigravity, para que relea las skills con los tamaños nuevos.
2. Pídele un análisis de ticket **desde fuera del repo del harness**, igual que en la observación.
3. Mira dos cosas: que cargue `qa-analisis-ticket` (y no la reporte excluida), y que al llegar a la
   documentación **lea `references/publicacion-jira.md`** (o la de tu backend) en vez de improvisar
   el procedimiento. Repítelo con un `Cierre [AMBIENTE] [TICKET-ID]` para `qa-cierre-ciclo`.

Si ahora carga y antes no, el límite era la causa y la partición lo resuelve. Si sigue sin cargar,
la causa es otra y esta sección hay que reescribirla. Si carga pero no abre las referencias, el
problema pasó a ser la ruta, no el tamaño.

### Claude Code y Cursor no están afectados

En Claude Code las skills llegan por symlink en `~/.claude/skills/` y no pasan por ese límite; en
Cursor la rule apunta a `skills/` y el agente lee el `SKILL.md` que necesita como archivo. El techo
es de Antigravity. Las referencias llegan igual a los tres: en Claude Code el symlink es de la
**carpeta** de la skill, no del archivo, así que `references/` viaja con ella; en Cursor se leen
como cualquier archivo del repo; en Antigravity la copia también es de la carpeta entera.
`tests/smoke.sh` verifica que `references/` llegue en Claude Code (symlink) y en Antigravity (copia).

## Las tres opciones que tienes ahora

| Entorno | Qué usar | Automatización |
|---|---|---|
| Claude Code | el harness original | Completa |
| Antigravity | este port | Completa, con las 3 diferencias de arriba (la post-edición **no cubre lo que escribe la terminal**) **y la limitación conocida de las skills grandes** (mitigada con `references/`, sin verificar en una instalación real) |
| Cursor | `adapters/cursor/` | Ver `adapters/cursor/README.md` |
