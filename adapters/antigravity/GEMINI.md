@../../AGENTS.md

# QA Harness Pro — reglas del agente

Estas reglas aplican a cualquier sesión de Antigravity abierta en la raíz de este harness.
El método, la config y las reglas que no se rompen viven en el `AGENTS.md` que se importa arriba
—es la fuente única—; acá abajo va solo lo específico de Antigravity.

## Qué hace cada gate

| Hook | Cuándo | Qué hace |
|---|---|---|
| `block-destructive-command.py` | antes de `run_command` | Bloquea `rm -rf`, `git reset --hard`, `git clean -fd`, `git push --force` |
| `validate-external-write.py` | antes de cualquier tool | Deniega transiciones de Jira. En escrituras externas: bloquea placeholders sin resolver y pide confirmación explícita |
| `check-after-edit.py` | después de editar | Corre tests / `bash -n` / validación JSON según la extensión |
| `surface-pending-check.py` | antes de cualquier tool | Levanta la falla que dejó el anterior y frena la sesión |

## Diferencia con Claude Code que conviene tener presente

En Claude Code, el gate post-edit le devuelve el error al modelo en el acto. Acá no: el
`PostToolUse` de Antigravity no tiene canal de vuelta, así que la falla aparece **en la siguiente
acción**, como una confirmación. Si ves un "Quality gate post-edit" al azar, es eso: algo que
editaste antes rompió los tests.
