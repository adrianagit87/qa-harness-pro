# Onboarding — sumar un QA al harness

Guía para alguien que recibe el harness por primera vez. Toma unos 15 minutos.

## Qué recibes

1. **El repo** (por `git bundle` o clon).
2. **`<empresa>.json`** por separado — la config de la empresa (en esta guía, `acme.json`). No viaja con el repo a propósito:
   `companies/*.json` está en `.gitignore` para que los datos de la empresa no queden en el
   historial de git.

## 1. Clona el repo

Si te llegó un bundle:

```bash
git clone qa-harness-pro.bundle ~/Documents/qa-harness-pro
cd ~/Documents/qa-harness-pro
```

> El repo tiene que quedar en un lugar **permanente**. La instalación crea enlaces que apuntan
> acá: si después mueves o borras la carpeta, las skills dejan de funcionar.

## 2. Pon la config de la empresa

```bash
cp ~/Downloads/acme.json companies/acme.json
```

Trae ya resueltos el `cloudId` de Jira, los prefijos de ticket, el proyecto de QA y los
sub-proyectos de automatización.

**Falta un campo:** `automation.workspacePath` viene vacío, porque es una ruta local y cada uno
tiene la suya. Pon la tuya:

```json
"automation": {
  "framework": "playwright",
  "workspacePath": "/ruta/local/a/tu/Pruebas automatizadas",
  ...
}
```

Si todavía no tienes la suite clonada, deja `automation` sin completar: `validate-config.sh` te va a
dar un aviso (no un error) cuando `framework` esté vacío, y la skill de automatización va a poder
evaluar, pero no generar código integrado. `workspacePath` no se valida: si lo dejas vacío con un
`framework` puesto, el aviso no aparece y la skill falla recién cuando la uses.

## 3. Crea tu perfil

```bash
cp profile/profile.example.json profile/profile.json
```

Edítalo con **tu** nombre — es el que va a firmar los cierres en Jira:

```json
{
  "name": "Tu Nombre",
  "role": "QA Engineer",
  "activeCompany": "acme",
  "language": "es",
  "tone": "directo, técnico, sin humo",
  "signature": "Tu Nombre — QA"
}
```

## 4. Instala para tu herramienta

Hay un solo instalador y eliges la herramienta con `--agent`:

| Herramienta | Comando |
|---|---|
| Claude Code | `./install.sh --agent claude` |
| Cursor | `./install.sh --agent cursor` |
| Antigravity | `./install.sh --agent antigravity` |
| Codex CLI | `./install.sh --agent codex` (y después `/hooks` en Codex: es obligatorio) |
| Las cuatro | `./install.sh --agent all` |

`--agent` es obligatorio: `./install.sh` a secas imprime la ayuda y sale con error, para que nadie
crea que instaló algo que no instaló. `./install.sh --help` te lista los valores.

Puedes instalar más de una: corre el comando una vez por herramienta, o usa `--agent all` para las
cuatro de una. Comparten las mismas skills y la misma config.

## 5. Verifica

```bash
./validate-config.sh
```

**Lo que tiene que quedar limpio son los ❌, no el color.** Cada error dice exactamente qué falta.

El 🟡 no es una falla. Significa "usable, con avisos", y hay dos avisos que vas a ver aunque hayas
hecho todo bien:

- **Si no instalaste Claude Code.** El validador revisa `claude` **siempre** —`.mcp.json` y
  `.claude/settings.json` viajan versionados en este repo— así que instalando solo Cursor, solo
  Antigravity o solo Codex te va a avisar que falta `~/.claude/CLAUDE.md` y que no hay skills enlazadas. Son
  avisos de algo que no instalaste.
- **Si dejaste `automation` sin completar** (paso 2). También es un aviso, no un error.

Pasarle tu runtime (`--agent claude`, `--agent cursor`, `--agent antigravity`, `--agent codex` o
`--agent all`) saca del medio los avisos de los otros, pero no los de tu config: el 🟢 recién aparece cuando no
queda ningún aviso pendiente.

## 6. Reinicia la herramienta y ábrela en la raíz del repo

**No es opcional y no se puede saltear.** Las reglas y los hooks se leen **al arrancar**: la sesión
que tenías abierta mientras instalabas no los tiene. Cierra la herramienta, vuelve a abrirla y ábrela
en `~/Documents/qa-harness-pro` (la raíz del repo), que es desde donde aplican los permisos, los
hooks y las reglas.

Si instalaste Antigravity, aprovecha y comprueba en la UI que la rule `qa-harness` quede activa
(*Always on*): el harness deja el archivo en `.agents/rules/`, pero el modo de activación se fija
desde ahí.

## 7. Verifica que las reglas te llegan

**Este paso va ANTES de la demo, y no es opcional.** Si las reglas no llegaron, la demo igual sale
—y sale bien—, así que probarla primero no te dice nada. Escribe en un chat nuevo, como única
palabra:

```
PING-HARNESS
```

Tiene que responder `PONG <empresa> <backend> <destino>` con los valores de tu config, y nada más.
Con el ejemplo de esta guía sería `PONG acme jira PROJ`; si tu `docs.backend` es `confluence` o
`notion`, el tercer valor es el destino de ese backend, no un proyecto de Jira.

Si te contesta cualquier otra cosa, **el método te llegó pero las reglas no**. Es la falla más
traicionera del harness. Lo que se pierde en silencio es que te muestre el borrador antes de
publicar, que no toque estados de Jira y que no invente datos. Revisa el paso 6: que hayas
reiniciado de verdad y que la abriste en la raíz del repo.

## 8. Verifica que el gate muerde

Pídele que publique un comentario en Jira que contenga el texto `PON-AQUI-EL-ID`. Tiene que
**bloquearlo**.

Si lo publica, el hook no está enganchado. Los hooks también se leen al arrancar: vuelve al paso 6.

Un gate desconectado no avisa que lo está. Simplemente deja pasar todo.

## 9. Recién ahora, prueba sin tocar nada real

```
Analiza el ticket de demo/ticket-ejemplo.md
```

El ticket de demo está incompleto a propósito. Deberías ver un gate ⚠️ con observaciones y unos
20 casos de prueba. No publica nada en ningún lado.

## Si ya lo tenías instalado y quieres actualizar

```bash
cd ~/Documents/qa-harness-pro
git pull ~/Downloads/qa-harness-pro.bundle main
cp ~/Downloads/acme.json companies/acme.json     # la config también cambia
./install.sh --agent cursor                      # o claude / antigravity / codex / all, según lo tuyo
```

Tu `profile/profile.json` no se toca: está en `.gitignore` y no viaja en el bundle.

Si además **moviste el repo** o lo clonaste en otra carpeta, reinstalar desde la ruta nueva alcanza:
el instalador reemplaza las entradas de la instalación anterior en vez de acumularlas. Y
`./validate-config.sh` te marca como error cualquier cosa que haya quedado apuntando a otro clon o a
una ruta que ya no existe, con el comando exacto para repararlo.

Después **reinicia la herramienta** y repite los pasos 7 y 8. Si antes tenías una rule en
`~/.cursor/rules/qa-harness.mdc`, bórrala: Cursor no lee esa ruta y solo genera confusión.

## Cómo trabaja el harness

- **Abre tu herramienta en la raíz de este repo.** Los permisos y hooks aplican desde acá.
- **Nunca cambia el estado de un ticket.** Las transiciones de Jira las haces tú, a mano. Es por
  diseño.
- **Siempre te muestra el borrador antes de publicar.**
- **Ambientes:** los que define `environments.list` en tu config. El marcado `final: true` es el de
  validación final.

## Comandos del día a día

| Escribes | Hace |
|---|---|
| `Analiza PROJ-1234` | Gate de calidad + casos de prueba + doc en Jira |
| `Cierre STG PROJ-1234` | Métricas, comentario de cierre y comentarios de ejecución por CP |
| Pegas un requerimiento sin ticket | Casos de prueba sin gate bloqueante |
