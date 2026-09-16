# QA Harness Pro — port a Antigravity (Gemini)

Port del harness completo a **Antigravity**. **No se pierde casi nada**: Antigravity soporta MCP,
skills y hooks.

## Instalación

```bash
./antigravity/install-antigravity.sh
```

Fusiona la config en `~/.gemini/config/` sin pisar lo que ya tengas (hace backup con timestamp de
todo lo que toca).

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
| Reglas del agente | `CLAUDE.md` | `GEMINI.md` / `AGENTS.md` |

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

5. Si aparece algo, ajustá los patrones de `EXTERNAL_WRITE` y `FORBIDDEN` en
   `antigravity/hooks/validate-external-write.py`.

6. **Verificá que el gate tiene dientes**: pedile que publique un comentario que contenga
   `PON-AQUI-EL-ID`. Debe bloquearlo. Si lo publica, el matcher no está enganchando y hay que
   volver al paso 4.

> No saltees el paso 6. Un gate desconectado no avisa que está desconectado: simplemente deja pasar
> todo, y vos creés que estás protegida.

## Las tres opciones que tenés ahora

| Entorno | Qué usar | Automatización |
|---|---|---|
| Claude Code | el harness original | Completa |
| Antigravity | este port | Completa, con las 3 diferencias de arriba |
| Cursor | `cursor/` | Ver `cursor/README.md` |
