#!/usr/bin/env bash
# QA Harness Pro — smoke tests del instalador único (./install.sh --agent <nombre>) y de validate-config.sh.
# TODO corre en directorios temporales (mktemp): jamás toca ~/.claude, ~/.cursor, ~/.gemini
# ni tu configuración real.
set -euo pipefail

# Los instaladores de Cursor y Antigravity fusionan su config con jq, y estos smoke lo usan para verificarla.
command -v jq > /dev/null 2>&1 || { echo "❌ Falta jq: lo necesitan ./install.sh --agent cursor|antigravity y estos smoke."; exit 1; }

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAILED=0

say()   { echo; echo "── $1"; }
t_ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
t_bad() { echo "  ❌ $1"; FAILED=$((FAILED+1)); }

assert_eq() { # assert_eq <descripción> <esperado> <obtenido>
  if [ "$2" = "$3" ]; then t_ok "$1"; else t_bad "$1 (esperado: '$2', obtenido: '$3')"; fi
}

# El `--` no es decorativo: sin él, un texto esperado que empieza con '-' (por ejemplo
# '--agent necesita un valor') se le pasa a grep como si fuera una opción.
assert_contains() { # assert_contains <descripción> <texto> <archivo-de-output>
  if grep -qF -- "$2" "$3"; then t_ok "$1"; else t_bad "$1 (no encontré: '$2' en $(basename "$3"))"; fi
}

assert_not_contains() { # assert_not_contains <descripción> <texto> <archivo-de-output>
  if grep -qF -- "$2" "$3"; then t_bad "$1 (encontré '$2' en $(basename "$3") y NO debería estar)"; else t_ok "$1"; fi
}

copy_repo() { # copy_repo <destino> — copia limpia del repo, sin .git ni configs reales
  cp -R "$REPO_ROOT" "$1"
  rm -rf "$1/.git" "$1/.atl" "$1/tests"
  rm -f "$1"/profile/profile.json
  find "$1/companies" -name '*.json' ! -name '_template.json' -delete
}

write_profile() { # write_profile <repo> <nombre>
  cat > "$1/profile/profile.json" <<EOF
{
  "name": "$2",
  "role": "QA",
  "activeCompany": "acme",
  "language": "es",
  "tone": "directo",
  "signature": "$2 — QA"
}
EOF
}

write_company_confluence() { # write_company_confluence <repo> <cloudId>
  cat > "$1/companies/acme.json" <<EOF
{
  "company": { "name": "Acme Corp", "key": "ACME" },
  "tracker": {
    "type": "jira",
    "host": "acme.atlassian.net",
    "cloudId": "$2",
    "ticketPrefixes": ["PROJ"],
    "browseUrlPattern": "https://acme.atlassian.net/browse/{KEY}"
  },
  "docs": {
    "backend": "confluence",
    "confluence": { "spaceKey": "QA", "parentPageId": "12345" },
    "notion": { "parents": { "casos": "PON-AQUI-EL-ID-DEL-PARENT-DE-NOTION" } }
  },
  "automation": { "framework": "", "workspacePath": "", "subprojects": [] }
}
EOF
}

write_company_notion() { # write_company_notion <repo>
  cat > "$1/companies/acme.json" <<EOF
{
  "company": { "name": "Acme Corp", "key": "ACME" },
  "tracker": {
    "type": "jira",
    "host": "acme.atlassian.net",
    "cloudId": "abc-123-cloudid",
    "ticketPrefixes": ["PROJ"],
    "browseUrlPattern": "https://acme.atlassian.net/browse/{KEY}"
  },
  "docs": {
    "backend": "notion",
    "confluence": { "spaceKey": "QA", "parentPageId": "PON-AQUI-EL-ID-DE-LA-PAGINA-PADRE" },
    "notion": { "parents": { "casos": "1234567890abcdef" } }
  },
  "automation": { "framework": "", "workspacePath": "", "subprojects": [] }
}
EOF
}

write_company_sin_tracker() { # write_company_sin_tracker <repo>
  cat > "$1/companies/acme.json" <<EOF
{
  "company": { "name": "Acme Corp", "key": "ACME" },
  "docs": {
    "backend": "confluence",
    "confluence": { "spaceKey": "QA", "parentPageId": "12345" }
  }
}
EOF
}

write_company_tracker() { # write_company_tracker <repo> <type> <prefixes-json> <browseUrlPattern> [host]
  # Empresa con docs confluence válidos y tracker parametrizable (para probar la semántica del tracker).
  local host="${5:-acme.atlassian.net}"
  cat > "$1/companies/acme.json" <<EOF
{
  "company": { "name": "Acme Corp", "key": "ACME" },
  "tracker": {
    "type": "$2",
    "host": "$host",
    "cloudId": "abc-123-cloudid",
    "ticketPrefixes": $3,
    "browseUrlPattern": "$4"
  },
  "docs": {
    "backend": "confluence",
    "confluence": { "spaceKey": "QA", "parentPageId": "12345" }
  },
  "automation": { "framework": "", "workspacePath": "", "subprojects": [] }
}
EOF
}

run_validate_en() { # run_validate_en <repo> <claude_dir> <cursor_dir> <gemini_dir> <archivo-output> [args...] → imprime exit code
  # Los TRES destinos se fijan siempre, nunca se heredan: si se dejara que CURSOR_DIR y
  # GEMINI_DIR cayeran en el HOME real, el resultado dependería de si quien corre los smoke
  # tiene el harness instalado en su propio Cursor o Antigravity.
  local repo="$1" claude_dir="$2" cursor_dir="$3" gemini_dir="$4" out="$5" rc=0
  shift 5
  env CLAUDE_DIR="$claude_dir" CURSOR_DIR="$cursor_dir" GEMINI_DIR="$gemini_dir" \
      QA_HARNESS_STATE="$gemini_dir/qa-harness-state.json" \
      bash "$repo/validate-config.sh" "$@" > "$out" 2>&1 || rc=$?
  echo "$rc"
}

run_validate() { # run_validate <repo> <claude_dir> <archivo-output> [args...] → imprime exit code
  # Atajo para los escenarios que solo miran claude: cursor y antigravity apuntan a rutas
  # temporales que NO existen, o sea "no instalados".
  local repo="$1" claude_dir="$2" out="$3"
  shift 3
  run_validate_en "$repo" "$claude_dir" "$TMP_ROOT/sin-cursor" "$TMP_ROOT/sin-gemini" "$out" "$@"
}

run_installer() { # run_installer <repo> <agente> <home> <archivo-output> → imprime exit code
  # HOME temporal y sin CLAUDE_DIR/CURSOR_DIR/GEMINI_DIR heredados: el instalador solo
  # puede tocar el sandbox, y cada destino se deriva del HOME temporal.
  local rc=0
  env -u CLAUDE_DIR -u CURSOR_DIR -u GEMINI_DIR HOME="$3" bash "$1/install.sh" --agent "$2" > "$4" 2>&1 || rc=$?
  echo "$rc"
}

assert_json() { # assert_json <descripción> <archivo>
  if jq empty "$2" > /dev/null 2>&1; then t_ok "$1"; else t_bad "$1 ($(basename "$2") no existe o no es JSON válido)"; fi
}

assert_file() { # assert_file <descripción> <archivo>
  if [ -f "$2" ]; then t_ok "$1"; else t_bad "$1 ($2 no existe)"; fi
}

# El límite de Antigravity para archivos de reglas está expresado en CARACTERES, no en
# bytes: con acentos y emojis `wc -c` sobreestima. Se cuenta con python3 en UTF-8.
assert_max_chars() { # assert_max_chars <descripción> <archivo> <máximo>
  local n
  if [ ! -f "$2" ]; then t_bad "$1 ($(basename "$2") no existe)"; return; fi
  n="$(python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8").read()))' "$2")"
  if [ "$n" -lt "$3" ]; then t_ok "$1 ($n caracteres)"; else t_bad "$1 ($n caracteres, máximo $3)"; fi
}

files_under() { # files_under <dir> — archivos bajo <dir>, relativos y ordenados, en una línea
  (cd "$1" && find . -type f | LC_ALL=C sort | tr '\n' ' ')
}

hook_commands() { # hook_commands <config.json> — cantidad de entradas "command" del config de hooks
  jq '[.. | objects | .command? // empty] | length' "$1"
}

missing_hook_scripts() { # missing_hook_scripts <config.json> <repo> — comandos que no apuntan a un script existente del repo
  local missing=0 cmd script
  while IFS= read -r cmd; do
    script="${cmd#python3 }"
    case "$script" in
      "$2"/*) [ -f "$script" ] || missing=$((missing+1)) ;;
      *) missing=$((missing+1)) ;;
    esac
  done < <(jq -r '.. | objects | .command? // empty' "$1")
  echo "$missing"
}

echo "🧪 QA Harness Pro — smoke tests (sandbox: $TMP_ROOT)"

# ────────────────────────────────────────────────────────────────────
say "1. ./install.sh --agent claude en CLAUDE_DIR vacío crea los symlinks"
R1="$TMP_ROOT/repo1"; copy_repo "$R1"
C1="$TMP_ROOT/claude1"
CLAUDE_DIR="$C1" bash "$R1/install.sh" --agent claude > "$TMP_ROOT/out-install1.txt" 2>&1

ALL_LINKED=1
for skill in "$R1"/skills/*/; do
  name="$(basename "$skill")"
  [ -L "$C1/skills/$name" ] || ALL_LINKED=0
done
assert_eq "todas las skills quedan como symlink" "1" "$ALL_LINKED"
assert_eq "el symlink resuelve al repo" \
  "$(cd "$R1/skills/qa-analisis-ticket" && pwd -P)" \
  "$(cd "$C1/skills/qa-analisis-ticket" && pwd -P)"
# Ausencia real de la regresión: 'mcp.example' no aparece por ningún lado
# (assert_contains '.mcp.json' no la detectaba: '.mcp.json' es subcadena de 'mcp.example.json → .mcp.json').
assert_not_contains "el mensaje final no menciona mcp.example" "mcp.example" "$TMP_ROOT/out-install1.txt"
assert_contains "el mensaje final sí menciona .mcp.json (aprobar servers MCP)" ".mcp.json" "$TMP_ROOT/out-install1.txt"
# El CLAUDE.md instalado ya NO es una copia byte a byte: lleva el placeholder {{HARNESS}}
# resuelto a la ruta absoluta del repo. Tiene que ser absoluta porque el archivo vive fuera
# del repo y Claude Code resuelve los imports relativos contra el archivo que importa: un
# `@AGENTS.md` relativo apuntaría a ~/.claude/AGENTS.md y no importaría nada, en silencio.
if [ -f "$C1/CLAUDE.md" ]; then
  t_ok "instala el CLAUDE.md base cuando no hay uno"
else
  t_bad "instala el CLAUDE.md base cuando no hay uno (no existe $C1/CLAUDE.md)"
fi
assert_contains "el CLAUDE.md instalado importa el AGENTS.md por ruta absoluta" \
  "@$R1/AGENTS.md" "$C1/CLAUDE.md"
assert_not_contains "no queda ningún {{HARNESS}} sin resolver" "{{HARNESS}}" "$C1/CLAUDE.md"
# Que la ruta del import apunte a un archivo que existe de verdad: si AGENTS.md se renombra,
# el import queda colgando y el usuario se queda sin reglas sin enterarse.
IMPORT_PATH="$(grep -o '@/[^ ]*/AGENTS\.md' "$C1/CLAUDE.md" | head -1 | cut -c2-)"
if [ -n "$IMPORT_PATH" ] && [ -f "$IMPORT_PATH" ]; then
  t_ok "el AGENTS.md que importa existe"
else
  t_bad "el AGENTS.md que importa existe (ruta importada: '${IMPORT_PATH:-ninguna}')"
fi
# Claude Code IGNORA los imports dentro de backticks o de un bloque de código: si alguien
# "prolija" el archivo metiendo la línea en un fence, el harness deja de llegar en silencio.
FIRST_LINE="$(grep -v '^[[:space:]]*$' "$R1/adapters/claude/CLAUDE.md" | head -1)"
case "$FIRST_LINE" in
  '@'*) t_ok "la línea de import del CLAUDE.md no está dentro de backticks ni de un fence" ;;
  *)    t_bad "la línea de import del CLAUDE.md no está dentro de backticks ni de un fence (primera línea no vacía: '$FIRST_LINE')" ;;
esac

# ────────────────────────────────────────────────────────────────────
say "2. ./install.sh --agent claude con directorio real preexistente: hace backup, no anida symlink"
R2="$TMP_ROOT/repo2"; copy_repo "$R2"
C2="$TMP_ROOT/claude2"
mkdir -p "$C2/skills/qa-analisis-ticket"
echo "contenido previo del comprador" > "$C2/skills/qa-analisis-ticket/nota.md"
echo "mis reglas propias" > "$C2/CLAUDE.md"
CLAUDE_DIR="$C2" bash "$R2/install.sh" --agent claude > "$TMP_ROOT/out-install2.txt" 2>&1

if [ -L "$C2/skills/qa-analisis-ticket" ]; then
  t_ok "el target preexistente ahora es un symlink"
else
  t_bad "el target preexistente ahora es un symlink (sigue siendo directorio real)"
fi
BACKUP_COUNT=$(find "$C2/skills" -maxdepth 1 -name 'qa-analisis-ticket.bak-*' | wc -l | tr -d ' ')
assert_eq "existe exactamente un backup del directorio previo" "1" "$BACKUP_COUNT"
BACKUP_DIR="$(find "$C2/skills" -maxdepth 1 -name 'qa-analisis-ticket.bak-*' | head -1)"
if [ -f "$BACKUP_DIR/nota.md" ]; then
  t_ok "el backup conserva el contenido previo"
else
  t_bad "el backup conserva el contenido previo (falta nota.md)"
fi
if [ -L "$C2/skills/qa-analisis-ticket/qa-analisis-ticket" ] || [ -L "$BACKUP_DIR/qa-analisis-ticket" ]; then
  t_bad "no hay symlink anidado dentro del directorio (bug de ln -sfn sobre dir real)"
else
  t_ok "no hay symlink anidado dentro del directorio"
fi
assert_contains "el instalador reporta el backup" "backup:" "$TMP_ROOT/out-install2.txt"
assert_eq "no pisa el CLAUDE.md que ya tenías" "mis reglas propias" "$(cat "$C2/CLAUDE.md")"
# No pisarlo sin más dejaría al usuario sin reglas y sin saberlo: el instalador tiene que
# decirle la línea exacta, con la ruta ya resuelta, que le falta agregar a su archivo.
assert_contains "le dice qué línea agregar a su CLAUDE.md" "@$R2/AGENTS.md" "$TMP_ROOT/out-install2.txt"

# ────────────────────────────────────────────────────────────────────
say "3. validate-config.sh: confluence completa (placeholders SOLO en bloque notion no usado) = exit 0"
RV="$TMP_ROOT/repo-validate"; copy_repo "$RV"
CV="$TMP_ROOT/claude-validate"
CLAUDE_DIR="$CV" bash "$RV/install.sh" --agent claude > /dev/null 2>&1
write_profile "$RV" "Ana QA"
write_company_confluence "$RV" "abc-123-cloudid"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v3.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_contains "reconoce el backend confluence" "Backend de docs: confluence" "$TMP_ROOT/out-v3.txt"
assert_contains "valida .mcp.json versionado" ".mcp.json existe y es JSON válido" "$TMP_ROOT/out-v3.txt"

# ────────────────────────────────────────────────────────────────────
say "4. validate-config.sh: cloudId vacío = exit 1"
write_company_confluence "$RV" ""
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v4.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error menciona cloudId" "cloudId" "$TMP_ROOT/out-v4.txt"

# ────────────────────────────────────────────────────────────────────
say "5. validate-config.sh: sin bloque tracker = exit 1"
write_company_sin_tracker "$RV"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v5.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error menciona tracker" "tracker" "$TMP_ROOT/out-v5.txt"

# ────────────────────────────────────────────────────────────────────
say "6. validate-config.sh: backend notion válido (placeholder en bloque confluence no usado) = exit 0"
write_company_notion "$RV"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v6.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_contains "reconoce el backend notion" "Backend de docs: notion" "$TMP_ROOT/out-v6.txt"

# ────────────────────────────────────────────────────────────────────
say "7. validate-config.sh: profile con nombre en placeholder = exit 1"
write_profile "$RV" "Tu Nombre"
write_company_confluence "$RV" "abc-123-cloudid"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v7.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error menciona el placeholder del nombre" "placeholder" "$TMP_ROOT/out-v7.txt"

# ────────────────────────────────────────────────────────────────────
say "8. validate-config.sh: tracker.type ≠ jira = exit 1"
write_profile "$RV" "Ana QA"
write_company_tracker "$RV" "github" '["PROJ"]' "https://acme.atlassian.net/browse/{KEY}"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v8.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error dice que v1 solo soporta Jira" "v1 soporta solo Jira" "$TMP_ROOT/out-v8.txt"
assert_contains "el error apunta a ADAPTAR-OTRO-STACK" "ADAPTAR-OTRO-STACK" "$TMP_ROOT/out-v8.txt"

# ────────────────────────────────────────────────────────────────────
say "9. validate-config.sh: ticketPrefixes con entrada vacía = exit 1"
write_company_tracker "$RV" "jira" '[""]' "https://acme.atlassian.net/browse/{KEY}"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v9.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error menciona la entrada vacía" "ticketPrefixes" "$TMP_ROOT/out-v9.txt"

# ────────────────────────────────────────────────────────────────────
say "10. validate-config.sh: browseUrlPattern sin https:// = exit 1"
write_company_tracker "$RV" "jira" '["PROJ"]' "garbage/{KEY}"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v10.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error exige https://" "https://" "$TMP_ROOT/out-v10.txt"

# ────────────────────────────────────────────────────────────────────
say "11. validate-config.sh: browseUrlPattern con el host del template = exit 1 (aunque el formato sea válido)"
write_company_tracker "$RV" "jira" '["PROJ"]' "https://tuempresa.atlassian.net/browse/{KEY}"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v11.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error menciona el host del template" "tuempresa.atlassian.net" "$TMP_ROOT/out-v11.txt"

# ────────────────────────────────────────────────────────────────────
say "12. validate-config.sh: browseUrlPattern de otro host (incoherente con tracker.host) = exit 1"
write_company_tracker "$RV" "jira" '["PROJ"]' "https://otraempresa.atlassian.net/browse/{KEY}"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v12.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error menciona la incoherencia con tracker.host" "no a tu tracker.host" "$TMP_ROOT/out-v12.txt"

# ────────────────────────────────────────────────────────────────────
say "13. validate-config.sh: settings.json con deny vaciado = exit 1 (la seguridad prometida no está activa)"
R13="$TMP_ROOT/repo13"; copy_repo "$R13"
C13="$TMP_ROOT/claude13"
CLAUDE_DIR="$C13" bash "$R13/install.sh" --agent claude > /dev/null 2>&1
write_profile "$R13" "Ana QA"
write_company_confluence "$R13" "abc-123-cloudid"
python3 - "$R13/.claude/settings.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["permissions"]["deny"] = []
json.dump(d, open(p, "w"), indent=2)
PYEOF
RC="$(run_validate "$R13" "$C13" "$TMP_ROOT/out-v13.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error menciona transitionJiraIssue" "transitionJiraIssue" "$TMP_ROOT/out-v13.txt"
assert_contains "el error dice que la seguridad prometida no está activa" "la seguridad prometida no está activa" "$TMP_ROOT/out-v13.txt"

# ────────────────────────────────────────────────────────────────────
say "14. validate-config.sh: settings.json con una escritura fuera de ask y deny = exit 1"
python3 - "$R13/.claude/settings.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["permissions"]["deny"] = ["mcp__atlassian__transitionJiraIssue"]
d["permissions"]["ask"] = [t for t in d["permissions"]["ask"] if t != "mcp__atlassian__addCommentToJiraIssue"]
json.dump(d, open(p, "w"), indent=2)
PYEOF
RC="$(run_validate "$R13" "$C13" "$TMP_ROOT/out-v14.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error nombra la herramienta sin gate" "mcp__atlassian__addCommentToJiraIssue" "$TMP_ROOT/out-v14.txt"

# ────────────────────────────────────────────────────────────────────
say "15. validate-config.sh: .mcp.json con mcpServers vacío = exit 1"
R15="$TMP_ROOT/repo15"; copy_repo "$R15"
C15="$TMP_ROOT/claude15"
CLAUDE_DIR="$C15" bash "$R15/install.sh" --agent claude > /dev/null 2>&1
write_profile "$R15" "Ana QA"
write_company_confluence "$R15" "abc-123-cloudid"
printf '{ "mcpServers": {} }\n' > "$R15/.mcp.json"
RC="$(run_validate "$R15" "$C15" "$TMP_ROOT/out-v15.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error menciona mcpServers vacío" "mcpServers está vacío" "$TMP_ROOT/out-v15.txt"

# ────────────────────────────────────────────────────────────────────
say "16. validate-config.sh: symlink roto = warning de no-enlazada (no cuenta como ok)"
write_company_confluence "$RV" "abc-123-cloudid"   # RV vuelve a config válida
# Total derivado del repo copiado: agregar/quitar una skill no debe romper este test.
TOTAL_SKILLS="$(find "$RV/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
ln -sfn "$TMP_ROOT/no-existe-este-destino" "$CV/skills/qa-analisis-ticket"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v16.txt")"
assert_eq "exit code 0 (warning, no error)" "0" "$RC"
assert_contains "avisa que el symlink está roto" "symlink ROTO" "$TMP_ROOT/out-v16.txt"
assert_contains "el resumen no la cuenta como enlazada" "Solo $((TOTAL_SKILLS-1)) de $TOTAL_SKILLS" "$TMP_ROOT/out-v16.txt"
assert_not_contains "no reporta todas las skills como enlazadas" "Las $TOTAL_SKILLS skills están enlazadas" "$TMP_ROOT/out-v16.txt"

# ────────────────────────────────────────────────────────────────────
say "17. validate-config.sh: symlink que apunta a OTRO lado = warning de no-enlazada"
mkdir -p "$TMP_ROOT/skill-impostora"
ln -sfn "$TMP_ROOT/skill-impostora" "$CV/skills/qa-analisis-ticket"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v17.txt")"
assert_eq "exit code 0 (warning, no error)" "0" "$RC"
assert_contains "avisa que apunta a otro lado" "no a la skill de este repo" "$TMP_ROOT/out-v17.txt"
assert_contains "el resumen no la cuenta como enlazada" "Solo $((TOTAL_SKILLS-1)) de $TOTAL_SKILLS" "$TMP_ROOT/out-v17.txt"
# reparar CV para no ensuciar futuros tests
CLAUDE_DIR="$CV" bash "$RV/install.sh" --agent claude > /dev/null 2>&1

# ────────────────────────────────────────────────────────────────────
say "18. ./install.sh --agent claude: backup exitoso + ln fallido → restaura el backup y sale ≠ 0"
R18="$TMP_ROOT/repo18"; copy_repo "$R18"
C18="$TMP_ROOT/claude18"
mkdir -p "$C18/skills/qa-analisis-ticket"
echo "contenido previo del comprador" > "$C18/skills/qa-analisis-ticket/nota.md"
# stub de ln vía PATH: siempre falla — simula un ln que muere tras el mv del backup
STUB_BIN="$TMP_ROOT/stub-bin"; mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nexit 1\n' > "$STUB_BIN/ln"
chmod +x "$STUB_BIN/ln"
RC18=0
PATH="$STUB_BIN:$PATH" CLAUDE_DIR="$C18" bash "$R18/install.sh" --agent claude > "$TMP_ROOT/out-install18.txt" 2>&1 || RC18=$?
if [ "$RC18" -ne 0 ]; then
  t_ok "install.sh sale con código ≠ 0 ($RC18)"
else
  t_bad "install.sh sale con código ≠ 0 (salió 0)"
fi
if [ -d "$C18/skills/qa-analisis-ticket" ] && [ ! -L "$C18/skills/qa-analisis-ticket" ] && [ -f "$C18/skills/qa-analisis-ticket/nota.md" ]; then
  t_ok "el contenido previo fue restaurado en su lugar original"
else
  t_bad "el contenido previo fue restaurado en su lugar original (falta el dir o nota.md)"
fi
LEFTOVER=$(find "$C18/skills" -maxdepth 1 -name 'qa-analisis-ticket.bak-*' 2>/dev/null | wc -l | tr -d ' ')
assert_eq "no queda backup huérfano tras la restauración" "0" "$LEFTOVER"
assert_contains "el mensaje dice qué se restauró" "Restauré tu contenido previo" "$TMP_ROOT/out-install18.txt"
assert_contains "el mensaje dice qué quedó sin enlazar" "quedó sin enlazar" "$TMP_ROOT/out-install18.txt"

# ────────────────────────────────────────────────────────────────────
say "19. validate-config.sh: settings.json con deny como STRING = exit 1 (substring matching NO cuenta como deny)"
R19="$TMP_ROOT/repo19"; copy_repo "$R19"
C19="$TMP_ROOT/claude19"
CLAUDE_DIR="$C19" bash "$R19/install.sh" --agent claude > /dev/null 2>&1
write_profile "$R19" "Ana QA"
write_company_confluence "$R19" "abc-123-cloudid"
python3 - "$R19/.claude/settings.json" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
# El ejemplo de la auditoría: deny como string. 'x' in "…transitionJiraIssue…" daría True
# por matching de subcadenas, pero Claude Code ignora este formato.
d["permissions"]["deny"] = "mcp__atlassian__transitionJiraIssue"
json.dump(d, open(p, "w"), indent=2)
PYEOF
RC="$(run_validate "$R19" "$C19" "$TMP_ROOT/out-v19.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "el error exige que deny sea una lista" "permissions.deny debe ser una lista" "$TMP_ROOT/out-v19.txt"

# ────────────────────────────────────────────────────────────────────
say "20. validate-config.sh: URLs trampa que contienen el host como subcadena = exit 1 cada una"
# 20a. host real como prefijo de un dominio ajeno
write_company_tracker "$RV" "jira" '["PROJ"]' "https://acme.atlassian.net.evil.example/browse/{KEY}"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v20a.txt")"
assert_eq "sufijo malicioso (host.evil.example): exit code 1" "1" "$RC"
assert_contains "el error nombra el host real de la URL" "apunta al host 'acme.atlassian.net.evil.example'" "$TMP_ROOT/out-v20a.txt"
# 20b. host real escondido en el PATH de otro dominio
write_company_tracker "$RV" "jira" '["PROJ"]' "https://evil.example/acme.atlassian.net/browse/{KEY}"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v20b.txt")"
assert_eq "host en el path (evil.example/host/...): exit code 1" "1" "$RC"
assert_contains "el error apunta al host equivocado" "no a tu tracker.host" "$TMP_ROOT/out-v20b.txt"
# 20c. host real como userinfo (user@host)
write_company_tracker "$RV" "jira" '["PROJ"]' "https://acme.atlassian.net@evil.example/browse/{KEY}"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v20c.txt")"
assert_eq "userinfo (host@evil.example): exit code 1" "1" "$RC"
assert_contains "el hostname real detectado es el malicioso" "apunta al host 'evil.example'" "$TMP_ROOT/out-v20c.txt"

# ────────────────────────────────────────────────────────────────────
say "21. validate-config.sh: tracker.host sucio (esquema, '@' o puerto) = exit 1 y sin falso 'coherente'"
write_company_tracker "$RV" "jira" '["PROJ"]' "https://acme.atlassian.net/browse/{KEY}" "https://acme.atlassian.net"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v21a.txt")"
assert_eq "host con esquema: exit code 1" "1" "$RC"
assert_contains "el error exige hostname limpio" "hostname limpio" "$TMP_ROOT/out-v21a.txt"
assert_not_contains "con host sucio NO se afirma coherencia del pattern" "browseUrlPattern coherente" "$TMP_ROOT/out-v21a.txt"
write_company_tracker "$RV" "jira" '["PROJ"]' "https://acme.atlassian.net/browse/{KEY}" "qa@acme.atlassian.net"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v21b.txt")"
assert_eq "host con '@': exit code 1" "1" "$RC"
assert_contains "el error exige hostname limpio" "hostname limpio" "$TMP_ROOT/out-v21b.txt"
assert_not_contains "con host sucio ('@') NO se afirma coherencia del pattern" "browseUrlPattern coherente" "$TMP_ROOT/out-v21b.txt"
write_company_tracker "$RV" "jira" '["PROJ"]' "https://acme.atlassian.net/browse/{KEY}" "acme.atlassian.net:8443"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v21c.txt")"
assert_eq "host con puerto: exit code 1" "1" "$RC"
assert_contains "el error exige hostname limpio (sin puerto)" "hostname limpio" "$TMP_ROOT/out-v21c.txt"
assert_not_contains "con host sucio (puerto) NO se afirma coherencia del pattern" "browseUrlPattern coherente" "$TMP_ROOT/out-v21c.txt"

# ────────────────────────────────────────────────────────────────────
say "22. validate-config.sh: regresión — config completamente válida sigue dando exit 0"
write_company_confluence "$RV" "abc-123-cloudid"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v22.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_contains "el patrón coherente con el host sigue pasando" "browseUrlPattern coherente" "$TMP_ROOT/out-v22.txt"

# ────────────────────────────────────────────────────────────────────
say "23. validate-config.sh: campos de solo espacios (name, cloudId, spaceKey, parentPageId) = exit 1"
# La config del auditor: nada está "vacío" a ojo de un chequeo ingenuo, pero todo es whitespace.
write_profile "$RV" "   "
cat > "$RV/companies/acme.json" <<'EOF'
{
  "company": { "name": "Acme Corp", "key": "ACME" },
  "tracker": {
    "type": "jira",
    "host": "acme.atlassian.net",
    "cloudId": "   ",
    "ticketPrefixes": ["PROJ"],
    "browseUrlPattern": "https://acme.atlassian.net/browse/{KEY}"
  },
  "docs": {
    "backend": "confluence",
    "confluence": { "spaceKey": "   ", "parentPageId": " " }
  },
  "automation": { "framework": "", "workspacePath": "", "subprojects": [] }
}
EOF
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v23.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "profile.name de solo espacios cae como placeholder" "profile.name sigue en placeholder" "$TMP_ROOT/out-v23.txt"
assert_contains "cloudId de solo espacios cae como vacío/placeholder" "tracker.cloudId está vacío o en placeholder" "$TMP_ROOT/out-v23.txt"
assert_contains "spaceKey de solo espacios cae como vacío/placeholder" "docs.confluence.spaceKey está vacío o en placeholder" "$TMP_ROOT/out-v23.txt"
assert_contains "parentPageId de solo espacios cae como vacío/placeholder" "docs.confluence.parentPageId está vacío o en placeholder" "$TMP_ROOT/out-v23.txt"
# Y el strip NO rompe una config válida (bordes con espacios se normalizan, no fallan de más)
write_profile "$RV" "Ana QA"
write_company_confluence "$RV" "abc-123-cloudid"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v23b.txt")"
assert_eq "config válida sigue en exit 0 tras la normalización" "0" "$RC"
# Bordes con espacios en TODOS los campos string: se limpian y pasan (no fallan de más)
write_profile "$RV" "  Ana QA  "
cat > "$RV/companies/acme.json" <<'EOF'
{
  "company": { "name": "  Acme Corp  ", "key": "ACME" },
  "tracker": {
    "type": "jira",
    "host": "  acme.atlassian.net  ",
    "cloudId": "  abc-123-cloudid  ",
    "ticketPrefixes": ["PROJ"],
    "browseUrlPattern": "  https://acme.atlassian.net/browse/{KEY}  "
  },
  "docs": {
    "backend": "  confluence  ",
    "confluence": { "spaceKey": "  QA  ", "parentPageId": "  12345  " }
  },
  "automation": { "framework": "", "workspacePath": "", "subprojects": [] }
}
EOF
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v23c.txt")"
assert_eq "config válida con bordes de espacios: exit 0" "0" "$RC"
assert_contains "el pattern con bordes limpios sigue coherente" "browseUrlPattern coherente" "$TMP_ROOT/out-v23c.txt"
# Los 6 campos restantes migrados a json_get_str, whitespace-only = error
write_profile "$RV" "Ana QA"
cat > "$RV/companies/acme.json" <<'EOF'
{
  "company": { "name": "   ", "key": "ACME" },
  "tracker": {
    "type": "jira",
    "host": "   ",
    "cloudId": "abc-123-cloudid",
    "ticketPrefixes": ["PROJ"],
    "browseUrlPattern": "   "
  },
  "docs": {
    "backend": "   ",
    "confluence": { "spaceKey": "QA", "parentPageId": "12345" }
  },
  "automation": { "framework": "", "workspacePath": "", "subprojects": [] }
}
EOF
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v23d.txt")"
assert_eq "company.name/host/browse/backend de solo espacios: exit 1" "1" "$RC"
assert_contains "company.name de espacios cae como placeholder" "company.name sigue en placeholder" "$TMP_ROOT/out-v23d.txt"
assert_contains "host de espacios cae como vacío" "tracker.host está vacío" "$TMP_ROOT/out-v23d.txt"
assert_contains "browseUrlPattern de espacios cae como vacío" "tracker.browseUrlPattern está vacío" "$TMP_ROOT/out-v23d.txt"
assert_contains "backend de espacios cae como inválido" "docs.backend debe ser" "$TMP_ROOT/out-v23d.txt"
# activeCompany whitespace-only
cat > "$RV/profile/profile.json" <<'EOF'
{ "name": "Ana QA", "role": "QA", "activeCompany": "   ", "language": "es", "tone": "directo", "signature": "Ana QA" }
EOF
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v23e.txt")"
assert_eq "activeCompany de solo espacios: exit 1" "1" "$RC"
assert_contains "activeCompany de espacios cae como vacío" "profile.activeCompany está vacío" "$TMP_ROOT/out-v23e.txt"
# notion.parents.casos whitespace-only (backend notion)
write_profile "$RV" "Ana QA"
write_company_notion "$RV"
python3 -c "import json; p='$RV/companies/acme.json'; d=json.load(open(p)); d['docs']['notion']['parents']['casos']='   '; json.dump(d, open(p,'w'))"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v23f.txt")"
assert_eq "parents.casos de solo espacios: exit 1" "1" "$RC"
assert_contains "parents.casos de espacios cae como vacío/placeholder" "docs.notion.parents.casos está vacío o en placeholder" "$TMP_ROOT/out-v23f.txt"

# ────────────────────────────────────────────────────────────────────
say "24. validate-config.sh: hook destructivo ausente = exit 1"
R24="$TMP_ROOT/repo-v24"
C24="$TMP_ROOT/claude-v24"
copy_repo "$R24"
mkdir -p "$C24/skills"
write_profile "$R24" "Carla QA"
write_company_confluence "$R24" "abc-123-cloudid"
python3 - "$R24/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["hooks"] = {}
open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
RC="$(run_validate "$R24" "$C24" "$TMP_ROOT/out-v24.txt")"
assert_eq "sin hook destructivo: exit code 1" "1" "$RC"
assert_contains "el error dice que el quality gate no está activo" "el quality gate no está activo" "$TMP_ROOT/out-v24.txt"

# ────────────────────────────────────────────────────────────────────
say "25. validate-config.sh: hook post-edit ausente = exit 1"
R25="$TMP_ROOT/repo-v25"
C25="$TMP_ROOT/claude-v25"
copy_repo "$R25"
mkdir -p "$C25/skills"
write_profile "$R25" "Carla QA"
write_company_confluence "$R25" "abc-123-cloudid"
python3 - "$R25/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["hooks"]["PostToolUse"] = []
open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
RC="$(run_validate "$R25" "$C25" "$TMP_ROOT/out-v25.txt")"
assert_eq "sin hook post-edit: exit code 1" "1" "$RC"
assert_contains "el error dice que no hay feedback automático" "no reciben feedback automático" "$TMP_ROOT/out-v25.txt"

# ────────────────────────────────────────────────────────────────────
say "26. validate-config.sh: hook de publicación externa ausente = exit 1"
R26="$TMP_ROOT/repo-v26"
C26="$TMP_ROOT/claude-v26"
copy_repo "$R26"
mkdir -p "$C26/skills"
write_profile "$R26" "Carla QA"
write_company_confluence "$R26" "abc-123-cloudid"
python3 - "$R26/.claude/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["hooks"]["PreToolUse"] = [
    group for group in d["hooks"]["PreToolUse"]
    if group.get("matcher") == "Bash"
]
open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
RC="$(run_validate "$R26" "$C26" "$TMP_ROOT/out-v26.txt")"
assert_eq "sin hook de publicación externa: exit code 1" "1" "$RC"
assert_contains "el error explica el riesgo del payload incompleto" "un payload incompleto podría llegar" "$TMP_ROOT/out-v26.txt"

# ────────────────────────────────────────────────────────────────────
# Los ports (Cursor y Antigravity), ahora detrás del mismo ./install.sh --agent <nombre>.
# Cada escenario corre contra una copia temporal del repo y con HOME en un
# directorio temporal: ni tu ~/.cursor, ni tu ~/.gemini, ni este repo se tocan.
RC_DIR="$TMP_ROOT/repo-cursor"; copy_repo "$RC_DIR"
RA_DIR="$TMP_ROOT/repo-antigravity"; copy_repo "$RA_DIR"

# La guarda de directorio DIVERGE a propósito por agente: claude CREA ~/.claude, mientras
# que cursor y antigravity se niegan si su directorio no existe (crearlo dejaría una
# config huérfana que ningún IDE lee).
say "27. cursor y antigravity sin el directorio del IDE: exit 1 y no crean nada en HOME"
H27="$TMP_ROOT/home27"; mkdir -p "$H27"
RC="$(run_installer "$RC_DIR" cursor "$H27" "$TMP_ROOT/out-i27a.txt")"
assert_eq "cursor sin ~/.cursor: exit code 1" "1" "$RC"
assert_contains "cursor dice qué falta" "No existe" "$TMP_ROOT/out-i27a.txt"
RC="$(run_installer "$RA_DIR" antigravity "$H27" "$TMP_ROOT/out-i27b.txt")"
assert_eq "antigravity sin ~/.gemini: exit code 1" "1" "$RC"
assert_contains "antigravity dice qué falta" "No existe" "$TMP_ROOT/out-i27b.txt"
assert_eq "ningún instalador dejó archivos en HOME" "" "$(files_under "$H27")"

# ────────────────────────────────────────────────────────────────────
say "28. ./install.sh --agent cursor en ~/.cursor vacío: config válida y apuntando al repo"
HC="$TMP_ROOT/home-cursor"; mkdir -p "$HC/.cursor"
# Marca en la rule de la copia: sirve para probar que el instalador toca SU repo, no este.
echo "<!-- marca-smoke-cursor -->" >> "$RC_DIR/adapters/cursor/rules/qa-harness.mdc"
RC="$(run_installer "$RC_DIR" cursor "$HC" "$TMP_ROOT/out-i28.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_json "hooks.json es JSON válido" "$HC/.cursor/hooks.json"
assert_json "mcp.json es JSON válido" "$HC/.cursor/mcp.json"
assert_eq "hooks.json declara version 1" "1" "$(jq -r '.version' "$HC/.cursor/hooks.json")"
assert_eq "los tres eventos quedan registrados" "afterFileEdit beforeMCPExecution beforeShellExecution" \
  "$(jq -r '.hooks | keys | join(" ")' "$HC/.cursor/hooks.json")"
assert_not_contains "el placeholder {{HARNESS}} quedó resuelto" "{{HARNESS}}" "$HC/.cursor/hooks.json"
assert_contains "los comandos apuntan al repo instalado" "$RC_DIR/adapters/cursor/hooks/" "$HC/.cursor/hooks.json"
assert_eq "los tres hooks apuntan a scripts que existen" "0" "$(missing_hook_scripts "$HC/.cursor/hooks.json" "$RC_DIR")"
assert_eq "servers MCP registrados" "atlassian notion" "$(jq -r '.mcpServers | keys | join(" ")' "$HC/.cursor/mcp.json")"
assert_eq "instalación limpia: solo hooks.json y mcp.json en HOME" "./.cursor/hooks.json ./.cursor/mcp.json " "$(files_under "$HC")"
# La rule se copia al scope de proyecto de la COPIA, no al de este repo.
assert_contains "la rule llega al .cursor/rules del repo copiado" "marca-smoke-cursor" "$RC_DIR/.cursor/rules/qa-harness.mdc"
assert_not_contains "el repo real no se tocó" "marca-smoke-cursor" "$REPO_ROOT/.cursor/rules/qa-harness.mdc"
# El hook instalado funciona de punta a punta: config → shim → hook original del harness.
CMD="$(jq -r '.hooks.beforeShellExecution[0].command' "$HC/.cursor/hooks.json")"
echo '{"command": "rm -rf /", "cwd": "/tmp"}' | env HOME="$HC" bash -c "$CMD" > "$TMP_ROOT/out-i28-hook.txt" 2>&1
assert_contains "el hook instalado bloquea un comando destructivo" '"deny"' "$TMP_ROOT/out-i28-hook.txt"

# ────────────────────────────────────────────────────────────────────
say "29. ./install.sh --agent cursor dos veces: idempotente (no duplica entradas)"
RC="$(run_installer "$RC_DIR" cursor "$HC" "$TMP_ROOT/out-i29.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_eq "sigue habiendo un solo hook por evento" "3" "$(hook_commands "$HC/.cursor/hooks.json")"
assert_eq "sigue habiendo dos servers MCP" "2" "$(jq '.mcpServers | length' "$HC/.cursor/mcp.json")"
assert_contains "la reinstalación hace backup" "backup:" "$TMP_ROOT/out-i29.txt"

# ────────────────────────────────────────────────────────────────────
say "30. ./install.sh --agent cursor sobre config propia: no pisa los hooks ni los servers del usuario"
HCU="$TMP_ROOT/home-cursor-usuario"; mkdir -p "$HCU/.cursor"
cat > "$HCU/.cursor/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [ { "command": "echo hook-propio" } ],
    "stop": [ { "command": "echo al-terminar" } ]
  }
}
EOF
cat > "$HCU/.cursor/mcp.json" <<'EOF'
{ "mcpServers": { "mi-server": { "command": "mi-mcp" } } }
EOF
cp "$HCU/.cursor/hooks.json" "$TMP_ROOT/hooks-usuario-original.json"
RC="$(run_installer "$RC_DIR" cursor "$HCU" "$TMP_ROOT/out-i30.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_json "hooks.json sigue siendo JSON válido" "$HCU/.cursor/hooks.json"
assert_eq "el hook propio del MISMO evento sobrevive" "true" \
  "$(jq -r '[.hooks.beforeShellExecution[].command] | any(. == "echo hook-propio")' "$HCU/.cursor/hooks.json")"
assert_eq "el hook del harness se suma a ese evento" "true" \
  "$(jq -r '[.hooks.beforeShellExecution[].command] | any(endswith("/adapters/cursor/hooks/block-destructive-command.py"))' "$HCU/.cursor/hooks.json")"
assert_eq "el hook propio de otro evento sobrevive" "echo al-terminar" \
  "$(jq -r '.hooks.stop[0].command' "$HCU/.cursor/hooks.json")"
assert_eq "el server MCP propio sobrevive junto a los del harness" "atlassian mi-server notion" \
  "$(jq -r '.mcpServers | keys | join(" ")' "$HCU/.cursor/mcp.json")"
BAK="$(find "$HCU/.cursor" -maxdepth 1 -name 'hooks.json.bak-*' | head -1)"
if [ -n "$BAK" ] && cmp -s "$BAK" "$TMP_ROOT/hooks-usuario-original.json"; then
  t_ok "el backup guarda el hooks.json original del usuario"
else
  t_bad "el backup guarda el hooks.json original del usuario"
fi
# Reinstalar sobre la config fusionada tampoco duplica.
RC="$(run_installer "$RC_DIR" cursor "$HCU" "$TMP_ROOT/out-i30b.txt")"
assert_eq "reinstalar: exit code 0" "0" "$RC"
assert_eq "reinstalar no duplica el hook del harness ni el propio" "2" \
  "$(jq '.hooks.beforeShellExecution | length' "$HCU/.cursor/hooks.json")"
assert_eq "reinstalar no duplica servers MCP" "3" "$(jq '.mcpServers | length' "$HCU/.cursor/mcp.json")"

# ────────────────────────────────────────────────────────────────────
say "31. ./install.sh --agent antigravity en ~/.gemini vacío: config válida y apuntando al repo"
HA="$TMP_ROOT/home-antigravity"; mkdir -p "$HA/.gemini"
# Marca en la rule de la copia: igual que en cursor, prueba que el instalador toca SU repo.
echo "<!-- marca-smoke-antigravity -->" >> "$RA_DIR/adapters/antigravity/rules/qa-harness.md"
RC="$(run_installer "$RA_DIR" antigravity "$HA" "$TMP_ROOT/out-i31.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_json "hooks.json es JSON válido" "$HA/.gemini/config/hooks.json"
assert_json "mcp_config.json es JSON válido" "$HA/.gemini/config/mcp_config.json"
assert_json "skills.json es JSON válido" "$HA/.gemini/config/skills.json"
assert_not_contains "el placeholder {{HARNESS}} quedó resuelto en hooks" "{{HARNESS}}" "$HA/.gemini/config/hooks.json"
assert_not_contains "el placeholder {{HARNESS}} quedó resuelto en skills" "{{HARNESS}}" "$HA/.gemini/config/skills.json"
assert_eq "el grupo del harness queda registrado" "true" \
  "$(jq -r 'has("qa-harness-pro")' "$HA/.gemini/config/hooks.json")"
assert_eq "los cuatro hooks apuntan a scripts que existen" "0" "$(missing_hook_scripts "$HA/.gemini/config/hooks.json" "$RA_DIR")"
assert_eq "skills apunta al skills/ del repo" "$RA_DIR/skills" "$(jq -r '.entries[0].path' "$HA/.gemini/config/skills.json")"
if [ -d "$(jq -r '.entries[0].path' "$HA/.gemini/config/skills.json")" ]; then
  t_ok "el directorio de skills registrado existe"
else
  t_bad "el directorio de skills registrado existe"
fi
assert_eq "servers MCP registrados" "atlassian notion" "$(jq -r '.mcpServers | keys | join(" ")' "$HA/.gemini/config/mcp_config.json")"
# El sidecar es un archivo REAL que el harness deja en el HOME del usuario, así que entra
# en el inventario: si mañana aparece un cuarto archivo inesperado, este assert lo canta.
# Sacarlo del inventario (sandboxeándolo con QA_HARNESS_STATE) haría que el test afirmara
# que una instalación limpia deja tres archivos cuando en realidad deja cuatro.
assert_eq "instalación limpia: los tres configs + el sidecar del harness en HOME" \
  "./.gemini/config/hooks.json ./.gemini/config/mcp_config.json ./.gemini/config/skills.json ./.gemini/qa-harness-state.json " "$(files_under "$HA")"
# La entrada registrada NO lleva marcas nuestras (el schema de Antigravity es {path} y nada
# más): lo que nos deja retirarla en la próxima instalación es el sidecar.
assert_eq "la entrada de skills solo tiene el campo del schema de Antigravity" "path" \
  "$(jq -r '.entries[0] | keys | join(" ")' "$HA/.gemini/config/skills.json")"
assert_eq "el sidecar anota el path de skills registrado" "$RA_DIR/skills" \
  "$(jq -r '.antigravity.skillsPath' "$HA/.gemini/qa-harness-state.json")"
# La rule va al scope de PROYECTO de la copia: Antigravity lee <workspace>/.agents/rules/.
# Sin esto, las skills quedan registradas pero las reglas del método no llegan nunca — que
# es exactamente el agujero que estos asserts existen para que no vuelva a pasar.
assert_contains "la rule llega al .agents/rules del repo copiado" "marca-smoke-antigravity" "$RA_DIR/.agents/rules/qa-harness.md"
assert_file "la rule de antigravity está versionada en este repo" "$REPO_ROOT/.agents/rules/qa-harness.md"
assert_not_contains "el repo real no se tocó" "marca-smoke-antigravity" "$REPO_ROOT/.agents/rules/qa-harness.md"
assert_contains "la rule apunta a AGENTS.md" "AGENTS.md" "$RA_DIR/.agents/rules/qa-harness.md"
assert_file "el AGENTS.md que la rule referencia existe" "$RA_DIR/AGENTS.md"
assert_max_chars "la rule entra en el límite de reglas de Antigravity" "$RA_DIR/.agents/rules/qa-harness.md" 12000
CMD="$(jq -r '."qa-harness-pro".PreToolUse[0].hooks[0].command' "$HA/.gemini/config/hooks.json")"
echo '{"toolCall": {"name": "run_command", "args": {"CommandLine": "rm -rf /"}}}' | env HOME="$HA" bash -c "$CMD" > "$TMP_ROOT/out-i31-hook.txt" 2>&1
assert_contains "el hook instalado bloquea un comando destructivo" '"deny"' "$TMP_ROOT/out-i31-hook.txt"

# ────────────────────────────────────────────────────────────────────
say "32. ./install.sh --agent antigravity dos veces: idempotente (no duplica entradas)"
RC="$(run_installer "$RA_DIR" antigravity "$HA" "$TMP_ROOT/out-i32.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_eq "siguen siendo cuatro hooks" "4" "$(hook_commands "$HA/.gemini/config/hooks.json")"
assert_eq "sigue habiendo una sola entrada de skills" "1" "$(jq '.entries | length' "$HA/.gemini/config/skills.json")"
assert_eq "siguen siendo dos servers MCP" "2" "$(jq '.mcpServers | length' "$HA/.gemini/config/mcp_config.json")"

# ────────────────────────────────────────────────────────────────────
say "33. ./install.sh --agent antigravity sobre config propia: no pisa grupos, servers ni skills del usuario"
HAU="$TMP_ROOT/home-antigravity-usuario"; mkdir -p "$HAU/.gemini/config"
cat > "$HAU/.gemini/config/hooks.json" <<'EOF'
{
  "mi-grupo": {
    "PreToolUse": [ { "matcher": "*", "hooks": [ { "type": "command", "command": "echo hook-propio" } ] } ]
  }
}
EOF
cat > "$HAU/.gemini/config/mcp_config.json" <<'EOF'
{ "mcpServers": { "mi-server": { "command": "mi-mcp" } } }
EOF
cat > "$HAU/.gemini/config/skills.json" <<'EOF'
{ "entries": [ { "path": "/mis/skills" } ] }
EOF
cp "$HAU/.gemini/config/skills.json" "$TMP_ROOT/skills-usuario-original.json"
RC="$(run_installer "$RA_DIR" antigravity "$HAU" "$TMP_ROOT/out-i33.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_eq "el grupo de hooks propio sobrevive" "echo hook-propio" \
  "$(jq -r '."mi-grupo".PreToolUse[0].hooks[0].command' "$HAU/.gemini/config/hooks.json")"
assert_eq "el grupo del harness se suma" "true" "$(jq -r 'has("qa-harness-pro")' "$HAU/.gemini/config/hooks.json")"
assert_eq "el server MCP propio sobrevive junto a los del harness" "atlassian mi-server notion" \
  "$(jq -r '.mcpServers | keys | join(" ")' "$HAU/.gemini/config/mcp_config.json")"
assert_eq "la skill propia sobrevive y se suma la del harness" "2" "$(jq '.entries | length' "$HAU/.gemini/config/skills.json")"
assert_contains "la ruta de skills propia sigue ahí" "/mis/skills" "$HAU/.gemini/config/skills.json"
BAK="$(find "$HAU/.gemini/config" -maxdepth 1 -name 'skills.json.bak-*' | head -1)"
if [ -n "$BAK" ] && cmp -s "$BAK" "$TMP_ROOT/skills-usuario-original.json"; then
  t_ok "el backup guarda el skills.json original del usuario"
else
  t_bad "el backup guarda el skills.json original del usuario"
fi
RC="$(run_installer "$RA_DIR" antigravity "$HAU" "$TMP_ROOT/out-i33b.txt")"
assert_eq "reinstalar: exit code 0" "0" "$RC"
assert_eq "reinstalar no duplica las entradas de skills" "2" "$(jq '.entries | length' "$HAU/.gemini/config/skills.json")"
assert_eq "reinstalar no duplica los hooks (4 del harness + 1 propio)" "5" "$(hook_commands "$HAU/.gemini/config/hooks.json")"

# ────────────────────────────────────────────────────────────────────
# Mudanza del repo: mismo HOME, el repo en OTRA ruta. Es el caso real de quien clona
# de nuevo, renombra la carpeta o se muda de disco. Si la config se desduplica por la
# ruta absoluta renderizada, la entrada vieja es una clave distinta y sobrevive: el
# usuario queda con hooks apuntando a scripts que ya no existen, o con reglas que
# nunca llegan. Lo que identifica lo que es del harness tiene que ser independiente
# de la ruta.
say "34. ./install.sh --agent cursor desde OTRA ruta del repo: no sobrevive la config vieja"
RC34A="$TMP_ROOT/repo-cursor-vieja"; copy_repo "$RC34A"
RC34B="$TMP_ROOT/repo-cursor-nueva"; copy_repo "$RC34B"
H34="$TMP_ROOT/home-cursor-mudanza"; mkdir -p "$H34/.cursor"
RC="$(run_installer "$RC34A" cursor "$H34" "$TMP_ROOT/out-i34a.txt")"
assert_eq "instalar desde la ruta vieja: exit code 0" "0" "$RC"
RC="$(run_installer "$RC34B" cursor "$H34" "$TMP_ROOT/out-i34b.txt")"
assert_eq "instalar desde la ruta nueva: exit code 0" "0" "$RC"
assert_json "hooks.json sigue siendo JSON válido" "$H34/.cursor/hooks.json"
assert_eq "siguen siendo tres comandos de hook, no seis" "3" "$(hook_commands "$H34/.cursor/hooks.json")"
assert_eq "ningún comando quedó apuntando al repo viejo" "0" \
  "$(jq --arg viejo "$RC34A/" '[.. | objects | .command? // empty | select(contains($viejo))] | length' "$H34/.cursor/hooks.json")"
assert_eq "los tres comandos apuntan al repo nuevo" "3" \
  "$(jq --arg nuevo "$RC34B/" '[.. | objects | .command? // empty | select(contains($nuevo))] | length' "$H34/.cursor/hooks.json")"
assert_eq "no queda ningún hook apuntando a un script inexistente" "0" "$(missing_hook_scripts "$H34/.cursor/hooks.json" "$RC34B")"

# ────────────────────────────────────────────────────────────────────
say "35. ./install.sh --agent antigravity desde OTRA ruta del repo: no sobrevive la config vieja"
RA35A="$TMP_ROOT/repo-antigravity-vieja"; copy_repo "$RA35A"
RA35B="$TMP_ROOT/repo-antigravity-nueva"; copy_repo "$RA35B"
H35="$TMP_ROOT/home-antigravity-mudanza"; mkdir -p "$H35/.gemini"
RC="$(run_installer "$RA35A" antigravity "$H35" "$TMP_ROOT/out-i35a.txt")"
assert_eq "instalar desde la ruta vieja: exit code 0" "0" "$RC"
RC="$(run_installer "$RA35B" antigravity "$H35" "$TMP_ROOT/out-i35b.txt")"
assert_eq "instalar desde la ruta nueva: exit code 0" "0" "$RC"
assert_json "skills.json sigue siendo JSON válido" "$H35/.gemini/config/skills.json"
assert_eq "queda una sola entrada de skills, no dos" "1" "$(jq '.entries | length' "$H35/.gemini/config/skills.json")"
assert_eq "la entrada de skills apunta al repo nuevo" "$RA35B/skills" \
  "$(jq -r '.entries[0].path' "$H35/.gemini/config/skills.json")"
# Los hooks ya se reemplazan bien porque se indexan por el nombre del grupo, que no
# lleva ruta: acá se blinda que siga siendo así.
assert_eq "siguen siendo cuatro comandos de hook" "4" "$(hook_commands "$H35/.gemini/config/hooks.json")"
assert_eq "no queda ningún hook apuntando a un script inexistente" "0" "$(missing_hook_scripts "$H35/.gemini/config/hooks.json" "$RA35B")"

# ────────────────────────────────────────────────────────────────────
say "36. ./install.sh --agent claude desde OTRA ruta del repo: el import viejo no sobrevive"
R36A="$TMP_ROOT/repo-claude-vieja"; copy_repo "$R36A"
R36B="$TMP_ROOT/repo-claude-nueva"; copy_repo "$R36B"
C36="$TMP_ROOT/claude-mudanza"
CLAUDE_DIR="$C36" bash "$R36A/install.sh" --agent claude > "$TMP_ROOT/out-i36a.txt" 2>&1
CLAUDE_DIR="$C36" bash "$R36B/install.sh" --agent claude > "$TMP_ROOT/out-i36b.txt" 2>&1
IMPORT_36="$(grep -v '^[[:space:]]*$' "$C36/CLAUDE.md" | head -1)"
assert_eq "la primera línea importa el AGENTS.md del repo nuevo" "@$R36B/AGENTS.md" "$IMPORT_36"
# Un import roto falla EN SILENCIO: si la ruta no existe, el usuario se queda sin reglas
# y sin enterarse. Por eso no alcanza con mirar el texto: el archivo tiene que existir.
IMPORT_PATH_36="${IMPORT_36#@}"
if [ -f "$IMPORT_PATH_36" ]; then
  t_ok "el AGENTS.md que importa existe de verdad"
else
  t_bad "el AGENTS.md que importa existe de verdad (ruta importada: '${IMPORT_PATH_36:-ninguna}')"
fi
assert_not_contains "no queda rastro del repo viejo en el CLAUDE.md" "$R36A/AGENTS.md" "$C36/CLAUDE.md"
BAK36="$(find "$C36" -maxdepth 1 -name 'CLAUDE.md.bak-*' | wc -l | tr -d ' ')"
assert_eq "guarda backup del CLAUDE.md anterior antes de re-renderizarlo" "1" "$BAK36"

# ────────────────────────────────────────────────────────────────────
# El reverso del 35: SIN sidecar no hay forma de probar que una entrada sea nuestra, así
# que no se borra. Es el caso de quien instaló antes de que existiera el sidecar — le
# queda una entrada vieja de más, pero preferimos eso a borrarle una entrada suya.
say "37. ./install.sh --agent antigravity sin sidecar: no borra la entrada que no puede probar suya"
RA37="$TMP_ROOT/repo-antigravity-sin-sidecar"; copy_repo "$RA37"
H37="$TMP_ROOT/home-antigravity-sin-sidecar"; mkdir -p "$H37/.gemini/config"
cat > "$H37/.gemini/config/skills.json" <<'EOF'
{ "entries": [ { "path": "/ruta/vieja/del/harness/skills" } ] }
EOF
RC="$(run_installer "$RA37" antigravity "$H37" "$TMP_ROOT/out-i37.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_eq "la entrada previa sobrevive (sin sidecar no hay prueba de que sea nuestra)" "2" \
  "$(jq '.entries | length' "$H37/.gemini/config/skills.json")"
assert_contains "la ruta vieja sigue ahí" "/ruta/vieja/del/harness/skills" "$H37/.gemini/config/skills.json"
assert_eq "a partir de ahora sí queda anotada la nuestra" "$RA37/skills" \
  "$(jq -r '.antigravity.skillsPath' "$H37/.gemini/qa-harness-state.json")"

# ────────────────────────────────────────────────────────────────────
# La CLI del instalador es superficie pública: si `./install.sh` a secas instalara claude
# por default, quien viene de Cursor se iría con un "✅" y sin reglas. El fallo tiene que
# ser ruidoso y nombrar los cuatro valores válidos.
say "38. ./install.sh: la CLI misma (sin args, --help, agente desconocido)"
R38="$TMP_ROOT/repo38"; copy_repo "$R38"
H38="$TMP_ROOT/home38"; mkdir -p "$H38"

run_cli() { # run_cli <repo> <home> <archivo-output> [args...] → imprime exit code
  local repo="$1" home="$2" out="$3" rc=0
  shift 3
  env -u CLAUDE_DIR -u CURSOR_DIR -u GEMINI_DIR HOME="$home" bash "$repo/install.sh" "$@" > "$out" 2>&1 || rc=$?
  echo "$rc"
}

RC="$(run_cli "$R38" "$H38" "$TMP_ROOT/out-i38a.txt")"
assert_eq "sin argumentos: exit code 1 (no elige claude por default)" "1" "$RC"
assert_contains "sin argumentos dice que falta --agent" "Falta --agent" "$TMP_ROOT/out-i38a.txt"
assert_contains "sin argumentos imprime el uso" "uso:  ./install.sh --agent" "$TMP_ROOT/out-i38a.txt"
assert_contains "el uso nombra los cuatro valores válidos" "claude, cursor, antigravity, all" "$TMP_ROOT/out-i38a.txt"
assert_eq "sin argumentos no toca nada en HOME" "" "$(files_under "$H38")"

RC="$(run_cli "$R38" "$H38" "$TMP_ROOT/out-i38b.txt" --help)"
assert_eq "--help: exit code 0" "0" "$RC"
assert_contains "--help imprime el uso" "uso:  ./install.sh --agent" "$TMP_ROOT/out-i38b.txt"
assert_eq "--help no toca nada en HOME" "" "$(files_under "$H38")"

RC="$(run_cli "$R38" "$H38" "$TMP_ROOT/out-i38c.txt" --agent gemini)"
assert_eq "agente desconocido: exit code 1" "1" "$RC"
assert_contains "dice cuál fue el agente desconocido" "Agente desconocido: 'gemini'" "$TMP_ROOT/out-i38c.txt"
assert_contains "el error nombra los valores válidos" "claude, cursor, antigravity, all" "$TMP_ROOT/out-i38c.txt"
assert_eq "agente desconocido no toca nada en HOME" "" "$(files_under "$H38")"

RC="$(run_cli "$R38" "$H38" "$TMP_ROOT/out-i38d.txt" --agent)"
assert_eq "--agent sin valor: exit code 1" "1" "$RC"
assert_contains "--agent sin valor lo dice" "--agent necesita un valor" "$TMP_ROOT/out-i38d.txt"

# ────────────────────────────────────────────────────────────────────
# --agent all: los destinos son independientes, así que un agente que falla NO cancela a
# los otros. Se corren los tres igual, se reporta cuál falló y el exit queda ≠ 0.
say "39. ./install.sh --agent all: instala los tres, y si uno falla sigue con los demás"
R39="$TMP_ROOT/repo39"; copy_repo "$R39"
H39="$TMP_ROOT/home39"; mkdir -p "$H39/.cursor" "$H39/.gemini"
RC="$(run_installer "$R39" all "$H39" "$TMP_ROOT/out-i39.txt")"
assert_eq "exit code 0" "0" "$RC"
if [ -L "$H39/.claude/skills/qa-analisis-ticket" ]; then
  t_ok "claude: las skills quedaron enlazadas"
else
  t_bad "claude: las skills quedaron enlazadas"
fi
assert_json "cursor: hooks.json válido" "$H39/.cursor/hooks.json"
assert_json "antigravity: skills.json válido" "$H39/.gemini/config/skills.json"
assert_contains "el cierre confirma los tres" "Los tres agentes quedaron instalados" "$TMP_ROOT/out-i39.txt"

# Mismo repo, HOME sin ~/.cursor: cursor falla y los otros dos se instalan igual.
H39B="$TMP_ROOT/home39b"; mkdir -p "$H39B/.gemini"
RC="$(run_installer "$R39" all "$H39B" "$TMP_ROOT/out-i39b.txt")"
assert_eq "con un agente que falla: exit code 1" "1" "$RC"
assert_contains "nombra al agente que falló" "Falló la instalación de: cursor" "$TMP_ROOT/out-i39b.txt"
if [ -L "$H39B/.claude/skills/qa-analisis-ticket" ]; then
  t_ok "claude se instaló igual pese al fallo de cursor"
else
  t_bad "claude se instaló igual pese al fallo de cursor"
fi
assert_json "antigravity se instaló igual pese al fallo de cursor" "$H39B/.gemini/config/skills.json"
assert_eq "cursor no dejó nada suyo en HOME" "0" "$(find "$H39B" -maxdepth 2 -name 'hooks.json' -path '*/.cursor/*' | wc -l | tr -d ' ')"

# ────────────────────────────────────────────────────────────────────
# La CLI de validate-config.sh imita a la del instalador para que se sientan una sola
# herramienta, con UNA diferencia deliberada: `./validate-config.sh` a secas NO es un error.
# Es el paso de reparación que AGENTS.md le da al agente como comando pelado, y que rompa
# ahí sería cambiarle el significado a una instrucción que ya viaja en el ~/.claude/CLAUDE.md
# de cada usuario.
say "40. validate-config.sh: la CLI misma (--help, agente desconocido, invocación pelada)"
R40="$TMP_ROOT/repo40"; copy_repo "$R40"
C40="$TMP_ROOT/claude40"
CLAUDE_DIR="$C40" bash "$R40/install.sh" --agent claude > /dev/null 2>&1
write_profile "$R40" "Ana QA"
write_company_confluence "$R40" "abc-123-cloudid"

RC="$(run_validate "$R40" "$C40" "$TMP_ROOT/out-v40a.txt" --help)"
assert_eq "--help: exit code 0" "0" "$RC"
assert_contains "--help imprime el uso" "uso:  ./validate-config.sh" "$TMP_ROOT/out-v40a.txt"
assert_contains "el uso nombra los cuatro valores válidos" "claude, cursor, antigravity, all" "$TMP_ROOT/out-v40a.txt"

RC="$(run_validate "$R40" "$C40" "$TMP_ROOT/out-v40b.txt" --agent gemini)"
assert_eq "agente desconocido: exit code 1" "1" "$RC"
assert_contains "dice cuál fue el agente desconocido" "Agente desconocido: 'gemini'" "$TMP_ROOT/out-v40b.txt"
assert_contains "el error nombra los valores válidos" "claude, cursor, antigravity, all" "$TMP_ROOT/out-v40b.txt"

RC="$(run_validate "$R40" "$C40" "$TMP_ROOT/out-v40c.txt" --agent)"
assert_eq "--agent sin valor: exit code 1" "1" "$RC"
assert_contains "--agent sin valor lo dice" "--agent necesita un valor" "$TMP_ROOT/out-v40c.txt"

RC="$(run_validate "$R40" "$C40" "$TMP_ROOT/out-v40d.txt")"
assert_eq "sin argumentos: sigue funcionando y valida (exit code 0)" "0" "$RC"
assert_contains "sin argumentos valida igual el perfil" "profile/profile.json existe" "$TMP_ROOT/out-v40d.txt"

RC="$(run_validate "$R40" "$C40" "$TMP_ROOT/out-v40e.txt" --agent claude)"
assert_eq "--agent claude sobre una instalación sana: exit code 0" "0" "$RC"

# ────────────────────────────────────────────────────────────────────
# EL chequeo de la mudanza de repo, ahora del lado del validador. Los tres bugs que arreglaron
# 2c200b0 y 120e6df dejaban config apuntando a un clon viejo, y NADIE avisaba: el gate seguía
# "instalado" y no protegía nada. Instalar desde repoA y validar desde repoB tiene que ser un
# ERROR (no un aviso), decir que apunta a OTRO clon y nombrar el comando exacto que lo repara.
say "41. validate-config.sh: claude instalado desde OTRA ruta = error de ruta vieja"
R41A="$TMP_ROOT/repo41-vieja"; copy_repo "$R41A"
R41B="$TMP_ROOT/repo41-nueva"; copy_repo "$R41B"
C41="$TMP_ROOT/claude41"
write_profile "$R41B" "Ana QA"; write_company_confluence "$R41B" "abc-123-cloudid"
CLAUDE_DIR="$C41" bash "$R41A/install.sh" --agent claude > /dev/null 2>&1
RC="$(run_validate "$R41B" "$C41" "$TMP_ROOT/out-v41.txt" --agent claude)"
assert_eq "exit code 1 (es un error, no un aviso)" "1" "$RC"
assert_contains "dice que apunta a otro clon" "OTRO clon" "$TMP_ROOT/out-v41.txt"
assert_contains "nombra la ruta vieja" "$R41A/AGENTS.md" "$TMP_ROOT/out-v41.txt"
assert_contains "nombra el comando que lo repara" "./install.sh --agent claude" "$TMP_ROOT/out-v41.txt"

# ────────────────────────────────────────────────────────────────────
say "42. validate-config.sh: cursor instalado desde OTRA ruta = error de ruta vieja"
R42A="$TMP_ROOT/repo42-vieja"; copy_repo "$R42A"
R42B="$TMP_ROOT/repo42-nueva"; copy_repo "$R42B"
H42="$TMP_ROOT/home42"; mkdir -p "$H42/.cursor"
write_profile "$R42B" "Ana QA"; write_company_confluence "$R42B" "abc-123-cloudid"
C42="$TMP_ROOT/claude42"; CLAUDE_DIR="$C42" bash "$R42B/install.sh" --agent claude > /dev/null 2>&1
RC="$(run_installer "$R42A" cursor "$H42" "$TMP_ROOT/out-i42.txt")"
assert_eq "instalar cursor desde la ruta vieja: exit code 0" "0" "$RC"
RC="$(run_validate_en "$R42B" "$C42" "$H42/.cursor" "$TMP_ROOT/sin-gemini" "$TMP_ROOT/out-v42.txt" --agent cursor)"
assert_eq "exit code 1" "1" "$RC"
assert_contains "dice que apunta a otro clon" "OTRO clon" "$TMP_ROOT/out-v42.txt"
assert_contains "nombra la ruta vieja del hook" "$R42A/adapters/cursor/hooks/" "$TMP_ROOT/out-v42.txt"
assert_contains "nombra el comando que lo repara" "./install.sh --agent cursor" "$TMP_ROOT/out-v42.txt"
# Y sin --agent: la invocación pelada (la que documenta AGENTS.md) tiene que cazarlo igual,
# porque el harness SÍ está instalado en ese Cursor.
RC="$(run_validate_en "$R42B" "$C42" "$H42/.cursor" "$TMP_ROOT/sin-gemini" "$TMP_ROOT/out-v42b.txt")"
assert_eq "sin --agent también lo caza: exit code 1" "1" "$RC"
assert_contains "sin --agent también dice que es de otro clon" "OTRO clon" "$TMP_ROOT/out-v42b.txt"

# ────────────────────────────────────────────────────────────────────
say "43. validate-config.sh: antigravity instalado desde OTRA ruta = error de ruta vieja"
R43A="$TMP_ROOT/repo43-vieja"; copy_repo "$R43A"
R43B="$TMP_ROOT/repo43-nueva"; copy_repo "$R43B"
H43="$TMP_ROOT/home43"; mkdir -p "$H43/.gemini"
write_profile "$R43B" "Ana QA"; write_company_confluence "$R43B" "abc-123-cloudid"
C43="$TMP_ROOT/claude43"; CLAUDE_DIR="$C43" bash "$R43B/install.sh" --agent claude > /dev/null 2>&1
RC="$(run_installer "$R43A" antigravity "$H43" "$TMP_ROOT/out-i43.txt")"
assert_eq "instalar antigravity desde la ruta vieja: exit code 0" "0" "$RC"
RC="$(run_validate_en "$R43B" "$C43" "$TMP_ROOT/sin-cursor" "$H43/.gemini" "$TMP_ROOT/out-v43.txt" --agent antigravity)"
assert_eq "exit code 1" "1" "$RC"
assert_contains "dice que apunta a otro clon" "OTRO clon" "$TMP_ROOT/out-v43.txt"
assert_contains "nombra la ruta vieja del hook" "$R43A/adapters/antigravity/hooks/" "$TMP_ROOT/out-v43.txt"
assert_contains "nombra la ruta vieja de las skills" "$R43A/skills" "$TMP_ROOT/out-v43.txt"
assert_contains "nombra el comando que lo repara" "./install.sh --agent antigravity" "$TMP_ROOT/out-v43.txt"

# ────────────────────────────────────────────────────────────────────
# El otro caso de la misma familia, con otra causa y otra lectura: el clon viejo ya NO está.
# Ahí el hook no corre — falla en silencio — y el mensaje tiene que decir ESO, no "otro clon".
say "44. validate-config.sh: config apuntando a un clon BORRADO = error de ruta inexistente"
R44A="$TMP_ROOT/repo44-vieja"; copy_repo "$R44A"
R44B="$TMP_ROOT/repo44-nueva"; copy_repo "$R44B"
H44="$TMP_ROOT/home44"; mkdir -p "$H44/.cursor"
C44="$TMP_ROOT/claude44"
write_profile "$R44B" "Ana QA"; write_company_confluence "$R44B" "abc-123-cloudid"
CLAUDE_DIR="$C44" bash "$R44A/install.sh" --agent claude > /dev/null 2>&1
RC="$(run_installer "$R44A" cursor "$H44" "$TMP_ROOT/out-i44.txt")"
assert_eq "instalar cursor desde la ruta vieja: exit code 0" "0" "$RC"
rm -rf "$R44A"   # el clon viejo desaparece (borrado, renombrado, otro disco)
RC="$(run_validate_en "$R44B" "$C44" "$H44/.cursor" "$TMP_ROOT/sin-gemini" "$TMP_ROOT/out-v44.txt" --agent cursor)"
assert_eq "cursor: exit code 1" "1" "$RC"
assert_contains "cursor: dice que la ruta ya no existe" "YA NO EXISTE" "$TMP_ROOT/out-v44.txt"
assert_not_contains "cursor: no lo confunde con otro clon" "OTRO clon" "$TMP_ROOT/out-v44.txt"
assert_contains "cursor: nombra el comando que lo repara" "./install.sh --agent cursor" "$TMP_ROOT/out-v44.txt"
RC="$(run_validate "$R44B" "$C44" "$TMP_ROOT/out-v44b.txt" --agent claude)"
assert_eq "claude: exit code 1" "1" "$RC"
assert_contains "claude: el import roto dice que la ruta ya no existe" "YA NO EXISTE" "$TMP_ROOT/out-v44b.txt"
assert_contains "claude: nombra el comando que lo repara" "./install.sh --agent claude" "$TMP_ROOT/out-v44b.txt"

# ────────────────────────────────────────────────────────────────────
# El reverso: una instalación limpia de los tres, validada desde el MISMO repo, sale verde.
# Sin esto, un validador que gritara siempre también pasaría los escenarios 41–44.
say "45. validate-config.sh: instalación limpia de los tres = verde por agente"
R45="$TMP_ROOT/repo45"; copy_repo "$R45"
H45="$TMP_ROOT/home45"; mkdir -p "$H45/.cursor" "$H45/.gemini"
write_profile "$R45" "Ana QA"; write_company_confluence "$R45" "abc-123-cloudid"
RC="$(run_installer "$R45" all "$H45" "$TMP_ROOT/out-i45.txt")"
assert_eq "instalar los tres: exit code 0" "0" "$RC"
for agente in claude cursor antigravity all; do
  RC="$(run_validate_en "$R45" "$H45/.claude" "$H45/.cursor" "$H45/.gemini" "$TMP_ROOT/out-v45-$agente.txt" --agent "$agente")"
  assert_eq "--agent $agente: exit code 0" "0" "$RC"
  assert_not_contains "--agent $agente: sin un solo error" "❌" "$TMP_ROOT/out-v45-$agente.txt"
done
# Y la invocación pelada detecta los tres instalados sin que se los nombre.
RC="$(run_validate_en "$R45" "$H45/.claude" "$H45/.cursor" "$H45/.gemini" "$TMP_ROOT/out-v45-auto.txt")"
assert_eq "sin --agent: exit code 0" "0" "$RC"
assert_contains "sin --agent detecta cursor instalado" "cursor" "$TMP_ROOT/out-v45-auto.txt"
assert_contains "sin --agent detecta antigravity instalado" "antigravity" "$TMP_ROOT/out-v45-auto.txt"

# ────────────────────────────────────────────────────────────────────
echo
if [ "$FAILED" -gt 0 ]; then
  echo "❌ Smoke tests: $FAILED fallo(s), $PASS ok."
  exit 1
fi
echo "🟢 Smoke tests: $PASS asserts OK, 0 fallos."
