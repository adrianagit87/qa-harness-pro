@{{HARNESS}}/AGENTS.md

# QA Harness Pro — adaptador de Claude Code

La línea de arriba importa la fuente única de reglas. `{{HARNESS}}` lo reemplaza `install.sh` por
la ruta **absoluta** del repo al instalar este archivo como `~/.claude/CLAUDE.md`. Tiene que ser
absoluta: Claude Code resuelve los imports relativos contra el archivo que importa, y este archivo
se copia FUERA del repo, así que una ruta relativa apuntaría a `~/.claude/AGENTS.md` — que no
existe — e importaría nada, en silencio.

El método, la config y las reglas que no se rompen viven en ese `AGENTS.md`. Acá abajo va solo lo
específico de Claude Code.

## Solo para Claude Code

Los permisos de `.claude/settings.json` **deniegan** las transiciones de Jira:
`transitionJiraIssue` está bloqueado en toda sesión de Claude Code abierta desde la raíz del repo,
que es como el método manda trabajar. Si trabajas desde otra carpeta, ese bloqueo solo aplica si
fusionaste los permisos en tu `~/.claude/settings.json` como indica `SETUP.md`.
