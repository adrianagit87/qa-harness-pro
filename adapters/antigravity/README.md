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

Una instalación de Antigravity deja **cuatro** archivos fuera del repo: los tres de
`~/.gemini/config/` (`hooks.json`, `mcp_config.json`, `skills.json`) y un sidecar propio del harness,
`~/.gemini/qa-harness-state.json`. Ese sidecar existe porque el schema de `skills.json` es de
Antigravity —una entrada es `{path}` y nada más—, así que no podemos marcarla como nuestra sin
meterle campos inventados a tu config. En vez de eso anotamos aparte **qué ruta de skills
registramos**, y en la próxima instalación retiramos exactamente esa: por eso reinstalar desde otro
clon reemplaza la entrada en lugar de dejarte dos, una de ellas apuntando a un directorio que ya no
existe. Podés moverlo con la variable `QA_HARNESS_STATE`. Si el sidecar falta o no se puede leer, no
se borra nada: jamás retiramos una entrada que no podamos probar que es nuestra.

## Qué se comparte con Claude Code

**Las skills son las mismas.** `skills.json` apunta al directorio `skills/` de este repo — el mismo
que Claude Code usa por symlink. Editás una skill una vez y las dos herramientas la ven.

Lo mismo con `companies/*.json` y `profile/profile.json`: son archivos, los lee cualquiera.

## Equivalencias

| Componente | Claude Code | Antigravity |
|---|---|---|
| Skills | `~/.claude/skills/` (symlinks) | `~/.gemini/config/skills.json` → `entries[].path` |
| MCP | `.mcp.json` del repo | `~/.gemini/config/mcp_config.json` |
| Hooks | `.claude/settings.json` → `hooks` | `~/.gemini/config/hooks.json` |
| Permisos ask/deny | bloque `permissions` | **Dentro del hook**, vía `decision` |
| Memoria de lo instalado | no hace falta: un symlink se ve y se reemplaza solo | `~/.gemini/qa-harness-state.json` (sidecar del harness; `QA_HARNESS_STATE` lo mueve) |
| Tamaño de las skills | sin límite conocido | límite documentado de 12.000 caracteres por archivo de reglas — ver la limitación conocida más abajo |
| Reglas del agente | `AGENTS.md` (fuente única), importado desde `adapters/claude/CLAUDE.md` | el mismo `AGENTS.md`, importado desde `adapters/antigravity/GEMINI.md` |

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

### 3. Los nombres de las tools no están documentados

**Este es el punto que hay que cerrar a mano.**

En Claude Code las tools MCP se llaman `mcp__atlassian__createJiraIssue`. En Antigravity, la
documentación no especifica el formato. Por eso los hooks:

- Corren con `matcher: "*"` (sobre toda llamada), no sobre un nombre adivinado
- Reconocen las tools **por patrón** sobre el nombre (`jira.*create.*issue`, etc.), no por igualdad
- Anotan en `~/.gemini/qa-harness-unknown-tools.log` cualquier tool que huela a Atlassian/Notion y
  no haya matcheado

### Cómo cerrarlo

1. Instalá y reiniciá Antigravity.
2. Autenticá el MCP de Atlassian.
3. Pedile que **lea** un ticket (`getJiraIssue`) y que **comente** en uno.
4. Mirá el log:

   ```bash
   bat ~/.gemini/qa-harness-unknown-tools.log
   ```

5. Si aparece algo, agregá la herramienta al catálogo en `core/gates/catalogo.py`.
   Es el único lugar: los tres runtimes la heredan.

6. **Verificá que el gate tiene dientes**: pedile que publique un comentario que contenga
   `PON-AQUI-EL-ID`. Debe bloquearlo. Si lo publica, el matcher no está enganchando y hay que
   volver al paso 4.

> No saltees el paso 6. Un gate desconectado no avisa que está desconectado: simplemente deja pasar
> todo, y vos creés que estás protegida.

## Limitación conocida: las skills grandes pueden no cargar

**Esto no está en las tres diferencias de arriba porque no es una diferencia de diseño: es un techo
del runtime, y puede dejarte trabajando sin método sin que nadie te avise.**

### Lo que está medido

Antigravity documenta un límite de **12.000 caracteres por archivo de reglas**. Estos son los
tamaños reales de las cinco skills. **`wc -c` cuenta bytes, no caracteres**, y estos archivos están
llenos de emojis y acentos: por eso las dos columnas no coinciden. El límite está expresado en
caracteres, así que la columna que manda es la primera:

| Skill | Caracteres | Bytes (`wc -c`) | ¿Supera los 12.000? |
|---|---:|---:|---|
| `skills/qa-cierre-ciclo/SKILL.md` | 13.739 | 14.492 | **sí** |
| `skills/qa-analisis-ticket/SKILL.md` | 12.886 | 13.453 | **sí** |
| `skills/qa-cierre-prod/SKILL.md` | 9.861 | 10.653 | no |
| `skills/qa-automatizacion/SKILL.md` | 5.060 | 5.162 | no |
| `skills/qa-generacion-casos/SKILL.md` | 3.166 | 3.460 | no |

Las dos que lo superan son las dos más importantes del método: el análisis de ticket —el corazón del
harness— y el cierre de ciclo.

### Qué se hizo, y qué sigue sin estar resuelto

Las dos skills grandes tenían plantillas de salida pegadas en línea, duplicando lo que ya vive en
`templates/`. Se movieron a `templates/06-especificacion-caso.md`,
`templates/07-comentario-cierre-ciclo.md` y `templates/08-comentario-ejecucion-cp.md`, y en la skill
quedó un puntero a la ruta exacta. Eso bajó `qa-cierre-ciclo` de 15.552 a 13.739 caracteres y
`qa-analisis-ticket` de 13.402 a 12.886.

**Las dos siguen por encima de 12.000.** No alcanza, y es importante decir por qué: las plantillas
en línea eran apenas ~600 y ~2.200 caracteres. El volumen de estas skills no son plantillas, es
método — las reglas de publicación, el criterio de aprobación, la resolución de ambiente. Recortar
eso para entrar en el número sería cambiar el método por un número, que es justo el humo que este
harness existe para evitar. Así que la limitación sigue abierta.

### Lo que se observó

Probado contra una instalación real de Antigravity el **2026-09-16**, abriendo Antigravity **fuera**
del repo del harness:

- Listó **las cinco skills por su nombre**. O sea que el registro de `skills.json` funciona: las ve.
- **No pudo cargar `qa-analisis-ticket`**, y reportó por sí mismo que había quedado excluida por un
  límite de contexto.

### Qué significa en la práctica

En Antigravity, las dos skills más grandes pueden estar **anunciadas pero no cargadas**. Y ese es
exactamente el modo de falla que el harness existe para evitar: el agente sabe que la skill existe,
dice que la va a usar, y después trabaja **de memoria** en vez de seguir el método. El resultado sale
igual, y sale plausible. Lo que se pierde en silencio es el gate de calidad, el formato de los casos
y las reglas de publicación.

### Qué NO está probado

Esto es una observación, no una conclusión cerrada. Dos motivos concretos:

1. El límite de 12.000 caracteres está documentado para **archivos de reglas**, no explícitamente
   para skills. Que aplique a `SKILL.md` es lo más razonable dados los tamaños, pero es inferencia.
2. Que un modelo diga por qué falló **no es autoritativo**. La autoexplicación de un LLM sobre su
   propio contexto es un indicio, no evidencia.

### El experimento que lo confirmaría

Si querés cerrarlo de verdad:

1. Recortá `skills/qa-analisis-ticket/SKILL.md` por debajo de los 12.000 caracteres
   (`wc -c skills/qa-analisis-ticket/SKILL.md` para verificar).
2. Reiniciá Antigravity.
3. Pedile un análisis de ticket **desde fuera del repo del harness**, igual que en la observación.

Si con el archivo recortado carga y con el original no, el límite es la causa. Si sigue sin cargar,
la causa es otra y esta sección hay que reescribirla.

### Claude Code y Cursor no están afectados

En Claude Code las skills llegan por symlink en `~/.claude/skills/` y no pasan por ese límite; en
Cursor la rule apunta a `skills/` y el agente lee el `SKILL.md` que necesita como archivo. El techo
es de Antigravity.

## Las tres opciones que tenés ahora

| Entorno | Qué usar | Automatización |
|---|---|---|
| Claude Code | el harness original | Completa |
| Antigravity | este port | Completa, con las 3 diferencias de arriba **y la limitación conocida de las skills grandes** |
| Cursor | `adapters/cursor/` | Ver `adapters/cursor/README.md` |
