# Onboarding — sumar un QA al harness

Guía para alguien que recibe el harness por primera vez. Toma unos 15 minutos.

## Qué recibís

1. **El repo** (por `git bundle` o clon).
2. **`<empresa>.json`** por separado — la config de la empresa (en esta guía, `acme.json`). No viaja con el repo a propósito:
   `companies/*.json` está en `.gitignore` para que los datos de la empresa no queden en el
   historial de git.

## 1. Cloná el repo

Si te llegó un bundle:

```bash
git clone qa-harness-pro.bundle ~/Documents/qa-harness-pro
cd ~/Documents/qa-harness-pro
```

> El repo tiene que quedar en un lugar **permanente**. La instalación crea enlaces que apuntan
> acá: si después movés o borrás la carpeta, las skills dejan de funcionar.

## 2. Poné la config de la empresa

```bash
cp ~/Downloads/acme.json companies/acme.json
```

Trae ya resueltos el `cloudId` de Jira, los prefijos de ticket, el proyecto de QA y los
sub-proyectos de automatización.

**Falta un campo:** `automation.workspacePath` viene vacío, porque es una ruta local y cada uno
tiene la suya. Poné la tuya:

```json
"automation": {
  "framework": "playwright",
  "workspacePath": "/ruta/local/a/tu/Pruebas automatizadas",
  ...
}
```

Si todavía no tenés la suite clonada, dejá `automation` sin completar: `validate-config.sh` te va a
dar un aviso (no un error) cuando `framework` esté vacío, y la skill de automatización va a poder
evaluar, pero no generar código integrado. `workspacePath` no se valida: si lo dejás vacío con un
`framework` puesto, el aviso no aparece y la skill falla recién cuando la uses.

## 3. Creá tu perfil

```bash
cp profile/profile.example.json profile/profile.json
```

Editalo con **tu** nombre — es el que va a firmar los cierres en Jira:

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

## 4. Instalá para tu herramienta

Hay un solo instalador y elegís la herramienta con `--agent`:

| Herramienta | Comando |
|---|---|
| Claude Code | `./install.sh --agent claude` |
| Cursor | `./install.sh --agent cursor` |
| Antigravity | `./install.sh --agent antigravity` |
| Las tres | `./install.sh --agent all` |

`--agent` es obligatorio: `./install.sh` a secas imprime la ayuda y sale con error, para que nadie
crea que instaló algo que no instaló. `./install.sh --help` te lista los valores.

Podés instalar más de una: corré el comando una vez por herramienta, o usá `--agent all` para las
tres de una. Comparten las mismas skills y la misma config.

## 5. Verificá

```bash
./validate-config.sh
```

Tiene que dar 🟢. Si da error, el mensaje dice exactamente qué falta.

Así, pelado, valida tu perfil y tu empresa más cada runtime que encuentre instalado. Si querés
apuntar a uno solo, pasale `--agent claude`, `--agent cursor`, `--agent antigravity` o `--agent all`.

## 6. Probá sin tocar nada real

```
Analiza el ticket de demo/ticket-ejemplo.md
```

El ticket de demo está incompleto a propósito. Deberías ver un gate ⚠️ con observaciones y unos
20 casos de prueba. No publica nada en ningún lado.

## 7. Verificá que las reglas te llegan

**Este paso no es opcional.** Escribí en un chat nuevo, como única palabra:

```
PING-HARNESS
```

Tiene que responder `PONG <empresa> <backend> <destino>` con los valores de tu config, y nada más.
Con el ejemplo de esta guía sería `PONG acme jira PROJ`; si tu `docs.backend` es `confluence` o
`notion`, el tercer valor es el destino de ese backend, no un proyecto de Jira.

Si te contesta cualquier otra cosa, **el método te llegó pero las reglas no**. Es la falla más
traicionera del harness, porque el análisis igual sale — y sale bien. Lo que se pierde en
silencio es que te muestre el borrador antes de publicar, que no toque estados de Jira y que no
invente datos. Revisá que hayas reiniciado la herramienta y que la abriste en la raíz del repo.

## 8. Verificá que el gate muerde

Pedile que publique un comentario en Jira que contenga el texto `PON-AQUI-EL-ID`. Tiene que
**bloquearlo**.

Si lo publica, el hook no está enganchado. Los hooks se leen al arrancar: reiniciá la
herramienta.

Un gate desconectado no avisa que lo está. Simplemente deja pasar todo.

## Si ya lo tenías instalado y querés actualizar

```bash
cd ~/Documents/qa-harness-pro
git pull ~/Downloads/qa-harness-pro.bundle main
cp ~/Downloads/acme.json companies/acme.json     # la config también cambia
./install.sh --agent cursor                      # o claude / antigravity / all, según lo tuyo
```

Tu `profile/profile.json` no se toca: está en `.gitignore` y no viaja en el bundle.

Si además **moviste el repo** o lo clonaste en otra carpeta, reinstalar desde la ruta nueva alcanza:
el instalador reemplaza las entradas de la instalación anterior en vez de acumularlas. Y
`./validate-config.sh` te marca como error cualquier cosa que haya quedado apuntando a otro clon o a
una ruta que ya no existe, con el comando exacto para repararlo.

Después **reiniciá la herramienta** y repetí los pasos 7 y 8. Si antes tenías una rule en
`~/.cursor/rules/qa-harness.mdc`, borrala: Cursor no lee esa ruta y solo genera confusión.

## Cómo trabaja el harness

- **Abrí tu herramienta en la raíz de este repo.** Los permisos y hooks aplican desde acá.
- **Nunca cambia el estado de un ticket.** Las transiciones de Jira las hacés vos, a mano. Es por
  diseño.
- **Siempre te muestra el borrador antes de publicar.**
- **Ambientes:** los que define `environments.list` en tu config. El marcado `final: true` es el de
  validación final.

## Comandos del día a día

| Escribís | Hace |
|---|---|
| `Analiza PROJ-1234` | Gate de calidad + casos de prueba + doc en Jira |
| `Cierre STG PROJ-1234` | Métricas, comentario de cierre y comentarios de ejecución por CP |
| Pegás un requerimiento sin ticket | Casos de prueba sin gate bloqueante |
