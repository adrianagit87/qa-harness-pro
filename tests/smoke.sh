#!/usr/bin/env bash
# QA Harness Pro — smoke tests del instalador único (./install.sh --agent <nombre>) y de validate-config.sh.
# TODO corre en directorios temporales (mktemp): jamás toca ~/.claude, ~/.cursor, ~/.gemini,
# ~/.codex, ~/.agents ni tu configuración real.
set -euo pipefail

# Los instaladores de Cursor y Antigravity fusionan su config con jq, y estos smoke lo usan para verificarla.
command -v jq > /dev/null 2>&1 || { echo "❌ Falta jq: lo necesitan ./install.sh --agent cursor|antigravity|codex y estos smoke."; exit 1; }

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
  rm -rf "$1/.git" "$1/.atl" "$1/tests" "$1/baseline"
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
  # TODOS los destinos se fijan siempre, nunca se heredan: si se dejara que CURSOR_DIR,
  # GEMINI_DIR o CODEX_HOME cayeran en el HOME real, el resultado dependería de si quien corre
  # los smoke tiene el harness instalado en su propio Cursor, Antigravity o Codex.
  # Codex se fija aparte con VALIDATE_CODEX_HOME / VALIDATE_CODEX_SKILLS (default: "no instalado").
  local repo="$1" claude_dir="$2" cursor_dir="$3" gemini_dir="$4" out="$5" rc=0
  shift 5
  env CLAUDE_DIR="$claude_dir" CURSOR_DIR="$cursor_dir" GEMINI_DIR="$gemini_dir" \
      QA_HARNESS_STATE="$gemini_dir/qa-harness-state.json" \
      CODEX_HOME="${VALIDATE_CODEX_HOME:-$TMP_ROOT/sin-codex}" \
      CODEX_SKILLS_DIR="${VALIDATE_CODEX_SKILLS:-$TMP_ROOT/sin-codex-skills}" \
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
  # HOME temporal y sin CLAUDE_DIR/CURSOR_DIR/GEMINI_DIR/CODEX_HOME/CODEX_SKILLS_DIR
  # heredados: el instalador solo puede tocar el sandbox, y cada destino se deriva del HOME
  # temporal. CODEX_HOME importa de verdad: Codex lo exporta en sus propias sesiones.
  local rc=0
  env -u CLAUDE_DIR -u CURSOR_DIR -u GEMINI_DIR -u CODEX_HOME -u CODEX_SKILLS_DIR HOME="$3" bash "$1/install.sh" --agent "$2" > "$4" 2>&1 || rc=$?
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

skills_del_repo() { # skills_del_repo <repo> — nombres de las skills del repo, ordenados, en una línea
  (cd "$1/skills" && for d in */; do printf '%s\n' "${d%/}"; done) | LC_ALL=C sort | paste -sd ' ' -
}

origen_copia() { # origen_copia <carpeta> — el "origen" que anota la marca de una copia del harness
  if [ -L "$1" ]; then echo "symlink"; return; fi
  jq -r '.origen // ""' "$1/.qa-harness-copia.json" 2>/dev/null || true
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
# El symlink es de la CARPETA de la skill, no del SKILL.md: references/ viaja con ella.
# Si alguien lo cambia por un symlink de archivo, la skill carga sin el detalle de sus pasos.
if [ -f "$C1/skills/qa-analisis-ticket/references/publicacion-jira.md" ]; then
  t_ok "las references/ de la skill se ven a través del symlink"
else
  t_bad "las references/ de la skill se ven a través del symlink"
fi
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
# Un directorio real con el nombre de una skill del harness es, casi seguro, una skill TUYA que
# se llama igual. Moverla a un .bak sin preguntar te la haría desaparecer del agente sin que
# te enteres: sin --reemplazar-skills el instalador se frena y no toca NADA (ni esa carpeta ni
# el resto de la instalación). Con la opción, recién ahí hace backup y enlaza.
say "2. ./install.sh --agent claude con directorio real preexistente: sin la opción se frena; con --reemplazar-skills hace backup, no anida symlink"
R2="$TMP_ROOT/repo2"; copy_repo "$R2"
C2="$TMP_ROOT/claude2"
mkdir -p "$C2/skills/qa-analisis-ticket"
echo "contenido previo del comprador" > "$C2/skills/qa-analisis-ticket/nota.md"
echo "mis reglas propias" > "$C2/CLAUDE.md"
RC2=0
CLAUDE_DIR="$C2" bash "$R2/install.sh" --agent claude > "$TMP_ROOT/out-install2a.txt" 2>&1 || RC2=$?
if [ "$RC2" -ne 0 ]; then
  t_ok "sin --reemplazar-skills: sale con código ≠ 0 ($RC2)"
else
  t_bad "sin --reemplazar-skills: sale con código ≠ 0 (salió 0)"
fi
if [ -d "$C2/skills/qa-analisis-ticket" ] && [ ! -L "$C2/skills/qa-analisis-ticket" ]; then
  t_ok "sin la opción: tu carpeta sigue siendo una carpeta real"
else
  t_bad "sin la opción: tu carpeta sigue siendo una carpeta real"
fi
assert_eq "sin la opción: tu carpeta conserva su contenido" "contenido previo del comprador" "$(cat "$C2/skills/qa-analisis-ticket/nota.md" 2>/dev/null)"
assert_eq "sin la opción: no se crea ningún backup" "0" \
  "$(find "$C2/skills" -maxdepth 1 -name '*.bak-*' | wc -l | tr -d ' ')"
assert_eq "sin la opción: no se enlaza ninguna otra skill (nada a medias)" "0" \
  "$(find "$C2/skills" -maxdepth 1 -type l | wc -l | tr -d ' ')"
assert_eq "sin la opción: el CLAUDE.md no se toca" "mis reglas propias" "$(cat "$C2/CLAUDE.md")"
assert_eq "sin la opción: no aparece ningún CLAUDE.md.bak" "0" \
  "$(find "$C2" -maxdepth 1 -name 'CLAUDE.md.bak-*' | wc -l | tr -d ' ')"
assert_contains "el error nombra la ruta en conflicto y qué es" "$C2/skills/qa-analisis-ticket  (carpeta propia)" "$TMP_ROOT/out-install2a.txt"
assert_contains "el error dice que no tocó nada" "No toqué nada" "$TMP_ROOT/out-install2a.txt"
assert_contains "el error dice cómo reemplazarlas" "./install.sh --agent claude --reemplazar-skills" "$TMP_ROOT/out-install2a.txt"
assert_not_contains "sin la opción no reporta skills enlazadas" "→ enlazada" "$TMP_ROOT/out-install2a.txt"

CLAUDE_DIR="$C2" bash "$R2/install.sh" --agent claude --reemplazar-skills > "$TMP_ROOT/out-install2.txt" 2>&1

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
assert_eq "el backup trae exactamente tu contenido" "contenido previo del comprador" "$(cat "$BACKUP_DIR/nota.md" 2>/dev/null)"
assert_eq "el symlink que queda apunta a la skill del repo" "$R2/skills/qa-analisis-ticket" "$(readlink "$C2/skills/qa-analisis-ticket")"
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
assert_contains "el error dice que v2 solo soporta Jira" "v2 soporta solo Jira" "$TMP_ROOT/out-v8.txt"
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
# reparar CV para no ensuciar futuros tests. El symlink impostor apunta FUERA de un clon del
# harness, así que el instalador lo trataría como tuyo y se frenaría: se saca a mano.
rm "$CV/skills/qa-analisis-ticket"
CLAUDE_DIR="$CV" bash "$RV/install.sh" --agent claude > /dev/null 2>&1

# ────────────────────────────────────────────────────────────────────
say "18. ./install.sh --agent claude --reemplazar-skills: backup exitoso + ln fallido → restaura el backup y sale ≠ 0"
R18="$TMP_ROOT/repo18"; copy_repo "$R18"
C18="$TMP_ROOT/claude18"
mkdir -p "$C18/skills/qa-analisis-ticket"
echo "contenido previo del comprador" > "$C18/skills/qa-analisis-ticket/nota.md"
# stub de ln vía PATH: siempre falla — simula un ln que muere tras el mv del backup
STUB_BIN="$TMP_ROOT/stub-bin"; mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nexit 1\n' > "$STUB_BIN/ln"
chmod +x "$STUB_BIN/ln"
RC18=0
PATH="$STUB_BIN:$PATH" CLAUDE_DIR="$C18" bash "$R18/install.sh" --agent claude --reemplazar-skills > "$TMP_ROOT/out-install18.txt" 2>&1 || RC18=$?
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
assert_eq "los seis eventos quedan registrados" "afterFileEdit beforeMCPExecution beforeShellExecution postToolUse postToolUseFailure preToolUse" \
  "$(jq -r '.hooks | keys | join(" ")' "$HC/.cursor/hooks.json")"
assert_eq "el par del shell engancha solo la terminal (matcher Shell)" "Shell Shell Shell" \
  "$(jq -r '[.hooks.preToolUse[0].matcher, .hooks.postToolUse[0].matcher, .hooks.postToolUseFailure[0].matcher] | join(" ")' "$HC/.cursor/hooks.json")"
assert_not_contains "el placeholder {{HARNESS}} quedó resuelto" "{{HARNESS}}" "$HC/.cursor/hooks.json"
assert_contains "los comandos apuntan al repo instalado" "$RC_DIR/adapters/cursor/hooks/" "$HC/.cursor/hooks.json"
assert_eq "los seis hooks apuntan a scripts que existen" "0" "$(missing_hook_scripts "$HC/.cursor/hooks.json" "$RC_DIR")"
assert_eq "servers MCP registrados" "atlassian notion" "$(jq -r '.mcpServers | keys | join(" ")' "$HC/.cursor/mcp.json")"
assert_eq "instalación limpia: solo hooks.json y mcp.json en HOME" "./.cursor/hooks.json ./.cursor/mcp.json " "$(files_under "$HC")"
# La rule se copia al scope de proyecto de la COPIA, no al de este repo.
assert_contains "la rule llega al .cursor/rules del repo copiado" "marca-smoke-cursor" "$RC_DIR/.cursor/rules/qa-harness.mdc"
assert_not_contains "el repo real no se tocó" "marca-smoke-cursor" "$REPO_ROOT/.cursor/rules/qa-harness.mdc"
# El hook instalado funciona de punta a punta: config → shim → hook original del harness.
CMD="$(jq -r '.hooks.beforeShellExecution[0].command' "$HC/.cursor/hooks.json")"
echo '{"command": "rm -rf /", "cwd": "/tmp"}' | env HOME="$HC" bash -c "$CMD" > "$TMP_ROOT/out-i28-hook.txt" 2>&1
assert_contains "el hook instalado bloquea un comando destructivo" '"deny"' "$TMP_ROOT/out-i28-hook.txt"
# El par del shell instalado, de punta a punta: foto en preToolUse, JSON roto escrito "por la
# terminal", aviso en postToolUse. TMPDIR en el sandbox: la foto no sale de ahí.
P28="$TMP_ROOT/proyecto28"; mkdir -p "$P28" "$HC/tmp"; git -C "$P28" init -q
LLAMADA28='{"conversation_id":"c-28","tool_name":"Shell","tool_use_id":"call-28","tool_input":{"command":"printf"}}'
CMD="$(jq -r '.hooks.preToolUse[0].command' "$HC/.cursor/hooks.json")"
echo "$LLAMADA28" | env HOME="$HC" TMPDIR="$HC/tmp" QA_HARNESS_ROOT="$P28" bash -c "$CMD" > "$TMP_ROOT/out-i28-pre.txt" 2>&1
assert_eq "preToolUse (foto) no dice nada" "" "$(cat "$TMP_ROOT/out-i28-pre.txt")"
printf '{"a": }' > "$P28/zz-smoke.json"
CMD="$(jq -r '.hooks.postToolUse[0].command' "$HC/.cursor/hooks.json")"
echo "$LLAMADA28" | env HOME="$HC" TMPDIR="$HC/tmp" QA_HARNESS_ROOT="$P28" bash -c "$CMD" > "$TMP_ROOT/out-i28-post.txt" 2>&1
assert_contains "postToolUse avisa el JSON roto que escribió la terminal" "fallo JSON despues de editar zz-smoke.json" "$TMP_ROOT/out-i28-post.txt"
assert_contains "el aviso va por additional_context" '"additional_context"' "$TMP_ROOT/out-i28-post.txt"
rm -rf "$HC/tmp" "$P28"

# ────────────────────────────────────────────────────────────────────
say "29. ./install.sh --agent cursor dos veces: idempotente (no duplica entradas)"
RC="$(run_installer "$RC_DIR" cursor "$HC" "$TMP_ROOT/out-i29.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_eq "sigue habiendo un solo hook por evento (seis eventos)" "6" "$(hook_commands "$HC/.cursor/hooks.json")"
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
assert_not_contains "el placeholder {{HARNESS}} quedó resuelto en hooks" "{{HARNESS}}" "$HA/.gemini/config/hooks.json"
assert_eq "el grupo del harness queda registrado" "true" \
  "$(jq -r 'has("qa-harness-pro")' "$HA/.gemini/config/hooks.json")"
assert_eq "los cuatro hooks apuntan a scripts que existen" "0" "$(missing_hook_scripts "$HA/.gemini/config/hooks.json" "$RA_DIR")"
# Las skills van COPIADAS a la carpeta GLOBAL de Antigravity, que es donde su agente va a LEER
# un SKILL.md. Con el solo registro de skills.json las listaba pero no las encontraba, y a
# través de un symlink su política de workspace le niega leer la ruta real (fuera del workspace).
assert_eq "una copia marcada por skill en config/skills, que vino del repo" "$(skills_del_repo "$RA_DIR" | wc -w | tr -d ' ')" \
  "$(for n in $(skills_del_repo "$RA_DIR"); do [ "$(origen_copia "$HA/.gemini/config/skills/$n")" = "$RA_DIR/skills/$n" ] && echo "$n"; done | wc -l | tr -d ' ')"
if diff -r -x .qa-harness-copia.json "$RA_DIR/skills/qa-analisis-ticket" "$HA/.gemini/config/skills/qa-analisis-ticket" > /dev/null; then
  t_ok "la copia es idéntica a la skill del repo (árbol completo)"
else
  t_bad "la copia es idéntica a la skill del repo (árbol completo)"
fi
assert_eq "son archivos reales, no un symlink" "no" "$([ -L "$HA/.gemini/config/skills/qa-analisis-ticket" ] && echo si || echo no)"
assert_file "el SKILL.md está en la carpeta global" "$HA/.gemini/config/skills/qa-analisis-ticket/SKILL.md"
assert_file "references/ viaja con la carpeta de la skill" "$HA/.gemini/config/skills/qa-analisis-ticket/references/publicacion-jira.md"
assert_file "references/ de qa-cierre-ciclo también" "$HA/.gemini/config/skills/qa-cierre-ciclo/references/metricas-aprobacion.md"
assert_eq "servers MCP registrados" "atlassian notion" "$(jq -r '.mcpServers | keys | join(" ")' "$HA/.gemini/config/mcp_config.json")"
# El sidecar es un archivo REAL que el harness deja en el HOME del usuario, así que entra
# en el inventario: si mañana aparece un archivo inesperado, este assert lo canta. Las copias
# de skills se miran arriba; skills.json ya NO se crea: con las copias en la carpeta global,
# una entrada ahí haría que Antigravity listara cada skill dos veces.
assert_eq "instalación limpia: los dos configs + el sidecar del harness en HOME (fuera de config/skills)" \
  "./.gemini/config/hooks.json ./.gemini/config/mcp_config.json ./.gemini/qa-harness-state.json " \
  "$( (cd "$HA" && find . -type f -not -path './.gemini/config/skills/*' | LC_ALL=C sort | tr '\n' ' ') )"
assert_eq "config/skills solo tiene las copias del harness" "$(skills_del_repo "$RA_DIR")" \
  "$( (cd "$HA/.gemini/config/skills" && for d in */; do printf '%s\n' "${d%/}"; done) | LC_ALL=C sort | paste -sd ' ' -)"
assert_eq "el sidecar anota el skills/ del repo" "$RA_DIR/skills" \
  "$(jq -r '.antigravity.skillsPath' "$HA/.gemini/qa-harness-state.json")"
assert_eq "el sidecar anota las skills copiadas" "$(skills_del_repo "$RA_DIR")" \
  "$(jq -r '.antigravity.skillCopies | join(" ")' "$HA/.gemini/qa-harness-state.json")"
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
assert_eq "siguen siendo copias, una por skill" "$(skills_del_repo "$RA_DIR" | wc -w | tr -d ' ')" \
  "$(find "$HA/.gemini/config/skills" -mindepth 2 -maxdepth 2 -name .qa-harness-copia.json | wc -l | tr -d ' ')"
assert_contains "reinstalar sin cambios no reescribe las copias" "qa-analisis-ticket → al día" "$TMP_ROOT/out-i32.txt"
assert_eq "no quedan carpetas temporales de la copia" "0" \
  "$(find "$HA/.gemini/config/skills" -mindepth 1 -maxdepth 1 -name '.*qa-harness-*' | wc -l | tr -d ' ')"
assert_eq "sigue sin haber skills.json" "no" "$([ -e "$HA/.gemini/config/skills.json" ] && echo si || echo no)"
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
# Sin nada nuestro adentro, el skills.json del usuario ni se reescribe: ni backup, ni cambio.
if cmp -s "$HAU/.gemini/config/skills.json" "$TMP_ROOT/skills-usuario-original.json"; then
  t_ok "el skills.json del usuario queda idéntico"
else
  t_bad "el skills.json del usuario queda idéntico"
fi
assert_eq "no hay backup de un archivo que no se tocó" "0" \
  "$(find "$HAU/.gemini/config" -maxdepth 1 -name 'skills.json.bak-*' | wc -l | tr -d ' ')"
RC="$(run_installer "$RA_DIR" antigravity "$HAU" "$TMP_ROOT/out-i33b.txt")"
assert_eq "reinstalar: exit code 0" "0" "$RC"
assert_eq "reinstalar deja sola la entrada del usuario" "/mis/skills" "$(jq -r '[.entries[].path] | join(" ")' "$HAU/.gemini/config/skills.json")"
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
assert_eq "siguen siendo seis comandos de hook, no doce" "6" "$(hook_commands "$H34/.cursor/hooks.json")"
assert_eq "ningún comando quedó apuntando al repo viejo" "0" \
  "$(jq --arg viejo "$RC34A/" '[.. | objects | .command? // empty | select(contains($viejo))] | length' "$H34/.cursor/hooks.json")"
assert_eq "los seis comandos apuntan al repo nuevo" "6" \
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
assert_eq "las copias pasan a venir del repo nuevo" "$RA35B/skills/qa-analisis-ticket" \
  "$(origen_copia "$H35/.gemini/config/skills/qa-analisis-ticket")"
assert_eq "ninguna copia quedó marcada con el repo viejo" "0" \
  "$(for c in "$H35"/.gemini/config/skills/*; do origen_copia "$c"; done | { grep -c -F "$RA35A/" || true; })"
# Instalación ANTERIOR por symlinks (la versión previa de este instalador), con el clon viejo ya
# borrado: el sidecar lo reconoce, y su symlink roto se reemplaza por una copia.
rm -rf "$RA35A" "$H35/.gemini/config/skills/qa-baseline"
ln -s "$RA35A/skills/qa-baseline" "$H35/.gemini/config/skills/qa-baseline"
jq --arg p "$RA35A/skills" '.antigravity.skillsPath = $p' "$H35/.gemini/qa-harness-state.json" > "$TMP_ROOT/state35.json"
mv "$TMP_ROOT/state35.json" "$H35/.gemini/qa-harness-state.json"
RC="$(run_installer "$RA35B" antigravity "$H35" "$TMP_ROOT/out-i35c.txt")"
assert_eq "reinstalar con el clon viejo borrado: exit code 0" "0" "$RC"
assert_eq "el symlink de la instalación anterior se reemplaza por una copia" "$RA35B/skills/qa-baseline" \
  "$(origen_copia "$H35/.gemini/config/skills/qa-baseline")"
assert_file "la copia que reemplaza al symlink trae su SKILL.md" "$H35/.gemini/config/skills/qa-baseline/SKILL.md"

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
assert_eq "la entrada previa sobrevive (sin sidecar no hay prueba de que sea nuestra)" "1" \
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
  env -u CLAUDE_DIR -u CURSOR_DIR -u GEMINI_DIR -u CODEX_HOME -u CODEX_SKILLS_DIR HOME="$home" bash "$repo/install.sh" "$@" > "$out" 2>&1 || rc=$?
  echo "$rc"
}

RC="$(run_cli "$R38" "$H38" "$TMP_ROOT/out-i38a.txt")"
assert_eq "sin argumentos: exit code 1 (no elige claude por default)" "1" "$RC"
assert_contains "sin argumentos dice que falta --agent" "Falta --agent" "$TMP_ROOT/out-i38a.txt"
assert_contains "sin argumentos imprime el uso" "uso:  ./install.sh --agent" "$TMP_ROOT/out-i38a.txt"
assert_contains "el uso nombra los cinco valores válidos" "claude, cursor, antigravity, codex, all" "$TMP_ROOT/out-i38a.txt"
assert_eq "sin argumentos no toca nada en HOME" "" "$(files_under "$H38")"

RC="$(run_cli "$R38" "$H38" "$TMP_ROOT/out-i38b.txt" --help)"
assert_eq "--help: exit code 0" "0" "$RC"
assert_contains "--help imprime el uso" "uso:  ./install.sh --agent" "$TMP_ROOT/out-i38b.txt"
assert_contains "--help documenta --reemplazar-skills" "--reemplazar-skills" "$TMP_ROOT/out-i38b.txt"
assert_eq "--help no toca nada en HOME" "" "$(files_under "$H38")"

RC="$(run_cli "$R38" "$H38" "$TMP_ROOT/out-i38c.txt" --agent gemini)"
assert_eq "agente desconocido: exit code 1" "1" "$RC"
assert_contains "dice cuál fue el agente desconocido" "Agente desconocido: 'gemini'" "$TMP_ROOT/out-i38c.txt"
assert_contains "el error nombra los valores válidos" "claude, cursor, antigravity, codex, all" "$TMP_ROOT/out-i38c.txt"
assert_eq "agente desconocido no toca nada en HOME" "" "$(files_under "$H38")"

RC="$(run_cli "$R38" "$H38" "$TMP_ROOT/out-i38d.txt" --agent)"
assert_eq "--agent sin valor: exit code 1" "1" "$RC"
assert_contains "--agent sin valor lo dice" "--agent necesita un valor" "$TMP_ROOT/out-i38d.txt"

RC="$(run_cli "$R38" "$H38" "$TMP_ROOT/out-i38e.txt" --reemplazar-skills)"
assert_eq "--reemplazar-skills sin --agent: exit code 1" "1" "$RC"
assert_contains "--reemplazar-skills no reemplaza a --agent" "Falta --agent" "$TMP_ROOT/out-i38e.txt"
assert_eq "--reemplazar-skills sin --agent no toca nada en HOME" "" "$(files_under "$H38")"

# ────────────────────────────────────────────────────────────────────
# --agent all: los destinos son independientes, así que un agente que falla NO cancela a
# los otros. Se corren todos igual, se reporta cuál falló y el exit queda ≠ 0.
say "39. ./install.sh --agent all: instala los cuatro, y si uno falla sigue con los demás"
R39="$TMP_ROOT/repo39"; copy_repo "$R39"
H39="$TMP_ROOT/home39"; mkdir -p "$H39/.cursor" "$H39/.gemini" "$H39/.codex"
RC="$(run_installer "$R39" all "$H39" "$TMP_ROOT/out-i39.txt")"
assert_eq "exit code 0" "0" "$RC"
if [ -L "$H39/.claude/skills/qa-analisis-ticket" ]; then
  t_ok "claude: las skills quedaron enlazadas"
else
  t_bad "claude: las skills quedaron enlazadas"
fi
assert_json "cursor: hooks.json válido" "$H39/.cursor/hooks.json"
assert_file "antigravity: skills copiadas" "$H39/.gemini/config/skills/qa-analisis-ticket/SKILL.md"
assert_json "codex: hooks.json válido" "$H39/.codex/hooks.json"
assert_contains "el cierre confirma los cuatro" "Los cuatro agentes quedaron instalados" "$TMP_ROOT/out-i39.txt"

# Mismo repo, HOME sin ~/.cursor: cursor falla y los otros dos se instalan igual.
H39B="$TMP_ROOT/home39b"; mkdir -p "$H39B/.gemini" "$H39B/.codex"
RC="$(run_installer "$R39" all "$H39B" "$TMP_ROOT/out-i39b.txt")"
assert_eq "con un agente que falla: exit code 1" "1" "$RC"
assert_contains "nombra al agente que falló" "Falló la instalación de: cursor" "$TMP_ROOT/out-i39b.txt"
if [ -L "$H39B/.claude/skills/qa-analisis-ticket" ]; then
  t_ok "claude se instaló igual pese al fallo de cursor"
else
  t_bad "claude se instaló igual pese al fallo de cursor"
fi
assert_json "antigravity se instaló igual pese al fallo de cursor" "$H39B/.gemini/config/hooks.json"
assert_eq "cursor no dejó nada suyo en HOME" "0" "$(find "$H39B" -maxdepth 2 -name 'hooks.json' -path '*/.cursor/*' | wc -l | tr -d ' ')"

# --reemplazar-skills tiene que llegar a cada proceso hijo: con una skill tuya en ~/.claude/skills
# y otra en ~/.agents/skills, `--agent all` sin la opción frena claude y codex; con ella, los
# cuatro quedan instalados y lo tuyo queda en su .bak.
H39C="$TMP_ROOT/home39c"; mkdir -p "$H39C/.cursor" "$H39C/.gemini" "$H39C/.codex" \
  "$H39C/.claude/skills/qa-cierre-prod" "$H39C/.agents/skills/qa-cierre-prod"
echo "mía (claude)" > "$H39C/.claude/skills/qa-cierre-prod/SKILL.md"
echo "mía (codex)" > "$H39C/.agents/skills/qa-cierre-prod/SKILL.md"
RC="$(run_cli "$R39" "$H39C" "$TMP_ROOT/out-i39c.txt" --agent all)"
assert_eq "all sin la opción y con skills tuyas: exit code 1" "1" "$RC"
assert_contains "all sin la opción: nombra a claude y codex como fallidos" "Falló la instalación de: claude codex" "$TMP_ROOT/out-i39c.txt"
RC="$(run_cli "$R39" "$H39C" "$TMP_ROOT/out-i39d.txt" --agent all --reemplazar-skills)"
assert_eq "all --reemplazar-skills: exit code 0" "0" "$RC"
assert_eq "claude: la skill del harness quedó enlazada" "$R39/skills/qa-cierre-prod" "$(readlink "$H39C/.claude/skills/qa-cierre-prod")"
assert_eq "codex: la skill del harness quedó enlazada" "$R39/skills/qa-cierre-prod" "$(readlink "$H39C/.agents/skills/qa-cierre-prod")"
assert_eq "claude: tu skill quedó en su backup" "mía (claude)" \
  "$(cat "$(find "$H39C/.claude/skills" -maxdepth 1 -name 'qa-cierre-prod.bak-*' | head -1)/SKILL.md" 2>/dev/null)"
assert_eq "codex: tu skill quedó en su backup" "mía (codex)" \
  "$(cat "$(find "$H39C/.agents/skills" -maxdepth 1 -name 'qa-cierre-prod.bak-*' | head -1)/SKILL.md" 2>/dev/null)"

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
assert_contains "el uso nombra los cinco valores válidos" "claude, cursor, antigravity, codex, all" "$TMP_ROOT/out-v40a.txt"

RC="$(run_validate "$R40" "$C40" "$TMP_ROOT/out-v40b.txt" --agent gemini)"
assert_eq "agente desconocido: exit code 1" "1" "$RC"
assert_contains "dice cuál fue el agente desconocido" "Agente desconocido: 'gemini'" "$TMP_ROOT/out-v40b.txt"
assert_contains "el error nombra los valores válidos" "claude, cursor, antigravity, codex, all" "$TMP_ROOT/out-v40b.txt"

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
say "45. validate-config.sh: instalación limpia de los cuatro = verde por agente"
R45="$TMP_ROOT/repo45"; copy_repo "$R45"
H45="$TMP_ROOT/home45"; mkdir -p "$H45/.cursor" "$H45/.gemini" "$H45/.codex"
write_profile "$R45" "Ana QA"; write_company_confluence "$R45" "abc-123-cloudid"
RC="$(run_installer "$R45" all "$H45" "$TMP_ROOT/out-i45.txt")"
assert_eq "instalar los cuatro: exit code 0" "0" "$RC"
for agente in claude cursor antigravity codex all; do
  RC="$(VALIDATE_CODEX_HOME="$H45/.codex" VALIDATE_CODEX_SKILLS="$H45/.agents/skills" \
    run_validate_en "$R45" "$H45/.claude" "$H45/.cursor" "$H45/.gemini" "$TMP_ROOT/out-v45-$agente.txt" --agent "$agente")"
  assert_eq "--agent $agente: exit code 0" "0" "$RC"
  assert_not_contains "--agent $agente: sin un solo error" "❌" "$TMP_ROOT/out-v45-$agente.txt"
done
# Codex recién instalado: los hooks todavía no pasaron por /hooks, y el validador lo dice
# como aviso (no como error: desde afuera no se puede confirmar ni negar del todo).
assert_contains "--agent codex avisa que falta aprobar los hooks en /hooks" "corre /hooks" "$TMP_ROOT/out-v45-codex.txt"
# Y la invocación pelada detecta los cuatro instalados sin que se los nombre.
RC="$(VALIDATE_CODEX_HOME="$H45/.codex" VALIDATE_CODEX_SKILLS="$H45/.agents/skills" \
  run_validate_en "$R45" "$H45/.claude" "$H45/.cursor" "$H45/.gemini" "$TMP_ROOT/out-v45-auto.txt")"
assert_eq "sin --agent: exit code 0" "0" "$RC"
assert_contains "sin --agent detecta cursor instalado" "cursor" "$TMP_ROOT/out-v45-auto.txt"
assert_contains "sin --agent detecta antigravity instalado" "antigravity" "$TMP_ROOT/out-v45-auto.txt"
assert_contains "sin --agent detecta codex instalado" "🔹 codex" "$TMP_ROOT/out-v45-auto.txt"

# ────────────────────────────────────────────────────────────────────
# El baseline es opcional: sin el bloque (o apagado) todo tiene que seguir exactamente igual.
say "46. validate-config.sh: bloque baseline — ausente y apagado no cambian nada; activo se valida"
set_baseline() { # set_baseline <repo> <json-del-bloque>
  python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['baseline']=json.loads(sys.argv[2]); json.dump(d, open(p,'w'))" \
    "$1/companies/acme.json" "$2"
}
write_profile "$RV" "Ana QA"
write_company_confluence "$RV" "abc-123-cloudid"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v46a.txt")"
assert_eq "sin bloque baseline: exit code 0" "0" "$RC"
assert_not_contains "sin bloque baseline: no lo menciona" "baseline" "$TMP_ROOT/out-v46a.txt"

set_baseline "$RV" '{"enabled": false, "path": "", "modules": "no-es-lista", "mirror": {"backend": "otro"}}'
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v46b.txt")"
assert_eq "baseline apagado (aunque el resto esté mal): exit code 0" "0" "$RC"
assert_contains "dice que está desactivado" "baseline desactivado" "$TMP_ROOT/out-v46b.txt"

set_baseline "$RV" '{"enabled": true, "path": "baseline/baseline.md", "modules": [{"code": "VEN-PED", "name": "Ventas › Pedidos"}], "mirror": {"backend": "none", "pageId": ""}}'
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v46c.txt")"
assert_eq "baseline activo y válido: exit code 0" "0" "$RC"
assert_contains "reconoce el baseline activo" "baseline activo: baseline/baseline.md" "$TMP_ROOT/out-v46c.txt"

assert_contains "avisa que la carpeta del baseline todavía no existe" "todavía no existe" "$TMP_ROOT/out-v46c.txt"

# Cualquier ruta sirve: absoluta fuera del repo y con '~' (HOME del sandbox).
mkdir -p "$TMP_ROOT/conocimiento" "$TMP_ROOT/home46/qa"
set_baseline "$RV" "{\"enabled\": true, \"path\": \"$TMP_ROOT/conocimiento/baseline.md\", \"modules\": [], \"mirror\": {\"backend\": \"none\"}}"
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v46f.txt")"
assert_eq "baseline con ruta absoluta fuera del repo: exit code 0" "0" "$RC"
assert_not_contains "la ruta absoluta con carpeta existente no avisa" "todavía no existe" "$TMP_ROOT/out-v46f.txt"
set_baseline "$RV" '{"enabled": true, "path": "~/qa/baseline.md", "modules": [], "mirror": {"backend": "none"}}'
RC="$(HOME="$TMP_ROOT/home46" run_validate "$RV" "$CV" "$TMP_ROOT/out-v46g.txt")"
assert_eq "baseline con ruta ~: exit code 0" "0" "$RC"
assert_not_contains "la ruta ~ se expande al HOME y encuentra la carpeta" "todavía no existe" "$TMP_ROOT/out-v46g.txt"

set_baseline "$RV" '{"enabled": true, "path": "", "modules": [{"code": "ven pedidos", "name": "Ventas"}, {"code": "FAC", "name": "Facturas"}, {"code": "FAC", "name": "Otra"}], "mirror": {"backend": "notion", "pageId": "PON-AQUI-EL-ID"}}'
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v46d.txt")"
assert_eq "baseline activo y mal configurado: exit code 1" "1" "$RC"
assert_contains "rechaza la ruta vacía" "baseline.path está vacío o en placeholder" "$TMP_ROOT/out-v46d.txt"
assert_contains "rechaza un código de módulo inválido" "baseline.modules tiene 1 entrada(s) inválida(s)" "$TMP_ROOT/out-v46d.txt"
assert_contains "rechaza códigos de módulo repetidos" "baseline.modules repite códigos" "$TMP_ROOT/out-v46d.txt"
assert_contains "exige pageId para el espejo" "baseline.mirror.pageId está vacío o en placeholder" "$TMP_ROOT/out-v46d.txt"

mkdir -p "$RV/baseline"
echo "# un markdown cualquiera" > "$RV/baseline/baseline.md"
set_baseline "$RV" '{"enabled": true, "path": "baseline/baseline.md", "modules": [], "mirror": {"backend": "none"}}'
RC="$(run_validate "$RV" "$CV" "$TMP_ROOT/out-v46e.txt")"
assert_eq "baseline existente sin la marca: exit code 1" "1" "$RC"
assert_contains "explica que falta la marca" "su primera línea no es" "$TMP_ROOT/out-v46e.txt"
rm -rf "$RV/baseline"
write_company_confluence "$RV" "abc-123-cloudid"

# ────────────────────────────────────────────────────────────────────
# Codex: ~/.codex NO es del harness. hooks.json ya trae hooks de otras herramientas (Orca,
# gentle-ai), config.toml trae servers y permisos del usuario, y AGENTS.md sus reglas. La
# instalación tiene que sumar lo suyo sin tocar un byte de lo ajeno, y reinstalar no duplica.
say "47. ./install.sh --agent codex sobre config ajena: la conserva y agrega lo suyo una vez"
R47="$TMP_ROOT/repo47"; copy_repo "$R47"
H47="$TMP_ROOT/home47"; mkdir -p "$H47/.codex" "$H47/.agents/skills/skill-ajena"
cat > "$H47/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "/bin/sh '/opt/orca/codex-hook.sh'", "timeout": 10 } ] }
    ],
    "PostToolUse": [
      { "hooks": [ { "type": "command", "command": "/bin/sh '/opt/orca/codex-hook.sh'", "timeout": 10 } ] }
    ],
    "SessionStart": [
      { "matcher": "startup|resume", "hooks": [ { "type": "command", "command": "gentle-ai skill-registry refresh || true", "timeout": 30, "statusMessage": "Refreshing" } ] }
    ]
  }
}
EOF
CONFIG_AJENO='model = "gpt-x"
approval_policy = "on-request"

# servers del usuario
[mcp_servers.playwright]
command = "npx"
args = ["@playwright/mcp@latest"]

[mcp_servers.playwright.tools.browser_close]
approval_mode = "approve"'
printf '%s\n' "$CONFIG_AJENO" > "$H47/.codex/config.toml"
printf '# mis reglas de Codex\n' > "$H47/.codex/AGENTS.md"
AJENO_ANTES="$(jq -S '[.hooks | to_entries[] | {k: .key, v: .value}] | sort_by(.k)' "$H47/.codex/hooks.json")"

RC="$(run_installer "$R47" codex "$H47" "$TMP_ROOT/out-i47.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_json "hooks.json sigue siendo JSON válido" "$H47/.codex/hooks.json"
assert_eq "los grupos ajenos quedan intactos y PRIMERO (no les cambia el índice de confianza)" "$AJENO_ANTES" \
  "$(jq -S '[.hooks | to_entries[] | select(.key != "PreToolUse" and .key != "PostToolUse") | {k: .key, v: .value}] +
            [.hooks | to_entries[] | select(.key == "PreToolUse" or .key == "PostToolUse") | {k: .key, v: .value[:1]}] | sort_by(.k)' "$H47/.codex/hooks.json")"
assert_eq "cinco hooks del harness, ni uno más" "5" \
  "$(jq '[.. | objects | .command? // empty | select(test("/adapters/codex/hooks/"))] | length' "$H47/.codex/hooks.json")"
assert_eq "PreToolUse: ajeno primero, después destructivo, MCP y la foto del shell (en ese orden)" \
  "/bin/sh '/opt/orca/codex-hook.sh'|Bash $R47/adapters/codex/hooks/block-destructive-command.py|mcp__.* $R47/adapters/codex/hooks/validate-external-write.py|Bash $R47/adapters/codex/hooks/snapshot-before-shell.py" \
  "$(jq -r '[.hooks.PreToolUse[] | "\(.matcher // "") \(.hooks[0].command)" | sub("^ "; "") | sub(" python3 "; " ")] | join("|")' "$H47/.codex/hooks.json")"
assert_eq "PostToolUse: ajeno primero, después apply_patch y el shell (en ese orden)" \
  "/bin/sh '/opt/orca/codex-hook.sh'|apply_patch|Edit|Write $R47/adapters/codex/hooks/check-after-edit.py|Bash $R47/adapters/codex/hooks/check-after-shell.py" \
  "$(jq -r '[.hooks.PostToolUse[] | "\(.matcher // "") \(.hooks[0].command)" | sub("^ "; "") | sub(" python3 "; " ")] | join("|")' "$H47/.codex/hooks.json")"
assert_eq "Bash → block-destructive-command.py" "$R47/adapters/codex/hooks/block-destructive-command.py" \
  "$(jq -r '.hooks.PreToolUse[] | select(.matcher == "Bash") | .hooks[0].command | sub("^python3 "; "")' "$H47/.codex/hooks.json" | head -1)"
assert_eq "mcp__.* → validate-external-write.py" "$R47/adapters/codex/hooks/validate-external-write.py" \
  "$(jq -r '.hooks.PreToolUse[] | select(.matcher == "mcp__.*") | .hooks[0].command | sub("^python3 "; "")' "$H47/.codex/hooks.json")"
assert_eq "apply_patch|Edit|Write (PostToolUse) → check-after-edit.py" "$R47/adapters/codex/hooks/check-after-edit.py" \
  "$(jq -r '.hooks.PostToolUse[] | select(.matcher == "apply_patch|Edit|Write") | .hooks[0].command | sub("^python3 "; "")' "$H47/.codex/hooks.json")"
assert_eq "todos los hooks del harness apuntan a un script que existe" "0" "$(missing_hook_scripts <(jq '{h: [.. | objects | select((.command? // "") | test("/adapters/codex/hooks/"))]}' "$H47/.codex/hooks.json") "$R47")"
assert_eq "config.toml: lo del usuario queda byte a byte al principio" "$CONFIG_AJENO" \
  "$(head -n "$(printf '%s\n' "$CONFIG_AJENO" | wc -l | tr -d ' ')" "$H47/.codex/config.toml")"
assert_eq "config.toml: un solo bloque del harness" "1" "$(grep -c '^# >>> qa-harness-pro >>>' "$H47/.codex/config.toml")"
assert_eq "config.toml: parsea y trae la segunda capa" "https://mcp.atlassian.com/v1/mcp/authv2 transitionJiraIssue prompt approve" \
  "$(python3 -c 'import sys,tomllib; d=tomllib.load(open(sys.argv[1],"rb"))["mcp_servers"]; a=d["atlassian"]; print(a["url"], " ".join(a["disabled_tools"]), a["tools"]["addCommentToJiraIssue"]["approval_mode"], d["playwright"]["tools"]["browser_close"]["approval_mode"])' "$H47/.codex/config.toml")"
assert_file "config.toml: backup antes de tocarlo" "$(ls "$H47/.codex/"config.toml.bak-* 2>/dev/null | head -1)"
assert_eq "AGENTS.md: lo del usuario sigue primero" "# mis reglas de Codex" "$(head -1 "$H47/.codex/AGENTS.md")"
assert_eq "AGENTS.md: un solo bloque del harness" "1" "$(grep -c '<!-- >>> qa-harness-pro >>>' "$H47/.codex/AGENTS.md")"
assert_contains "AGENTS.md: el bloque apunta al AGENTS.md de este repo" "$R47/AGENTS.md" "$H47/.codex/AGENTS.md"
if [ -L "$H47/.agents/skills/qa-analisis-ticket" ] && [ -f "$H47/.agents/skills/qa-analisis-ticket/SKILL.md" ]; then
  t_ok "skills enlazadas en ~/.agents/skills (con su SKILL.md)"
else
  t_bad "skills enlazadas en ~/.agents/skills (con su SKILL.md)"
fi
if [ -d "$H47/.agents/skills/skill-ajena" ] && [ ! -L "$H47/.agents/skills/skill-ajena" ]; then
  t_ok "la skill ajena de ~/.agents/skills sigue ahí"
else
  t_bad "la skill ajena de ~/.agents/skills sigue ahí"
fi
assert_contains "el cierre exige el paso de confianza en /hooks" "corre /hooks" "$TMP_ROOT/out-i47.txt"

# ────────────────────────────────────────────────────────────────────
say "48. ./install.sh --agent codex dos veces: idempotente"
cp "$H47/.codex/hooks.json" "$TMP_ROOT/h47-hooks-1.json"
cp "$H47/.codex/config.toml" "$TMP_ROOT/h47-config-1.toml"
cp "$H47/.codex/AGENTS.md" "$TMP_ROOT/h47-agents-1.md"
BAKS_ANTES="$(ls "$H47/.codex/" | grep -c -E '^(config\.toml|AGENTS\.md)\.bak-' || true)"
sleep 1  # otro STAMP: si reinstalar respaldara lo que no cambia, aparecería un .bak nuevo
RC="$(run_installer "$R47" codex "$H47" "$TMP_ROOT/out-i48.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_eq "hooks.json idéntico" "$(jq -S . "$TMP_ROOT/h47-hooks-1.json")" "$(jq -S . "$H47/.codex/hooks.json")"
assert_eq "config.toml idéntico" "$(cat "$TMP_ROOT/h47-config-1.toml")" "$(cat "$H47/.codex/config.toml")"
assert_eq "AGENTS.md idéntico" "$(cat "$TMP_ROOT/h47-agents-1.md")" "$(cat "$H47/.codex/AGENTS.md")"
assert_eq "sin cambios no hay backups nuevos de config.toml ni AGENTS.md" "$BAKS_ANTES" \
  "$(ls "$H47/.codex/" | grep -c -E '^(config\.toml|AGENTS\.md)\.bak-' || true)"
assert_contains "dice que no hubo cambios" "sin cambios" "$TMP_ROOT/out-i48.txt"

# ────────────────────────────────────────────────────────────────────
say "49. ./install.sh --agent codex desde OTRA ruta: reemplaza, no suma, y el validador caza la vieja"
R49A="$TMP_ROOT/repo49-vieja"; copy_repo "$R49A"
R49B="$TMP_ROOT/repo49-nueva"; copy_repo "$R49B"
H49="$TMP_ROOT/home49"; mkdir -p "$H49/.codex"
write_profile "$R49B" "Ana QA"; write_company_confluence "$R49B" "abc-123-cloudid"
C49="$TMP_ROOT/claude49"; CLAUDE_DIR="$C49" bash "$R49B/install.sh" --agent claude > /dev/null 2>&1
RC="$(run_installer "$R49A" codex "$H49" "$TMP_ROOT/out-i49a.txt")"
assert_eq "instalar desde la ruta vieja: exit code 0" "0" "$RC"
RC="$(VALIDATE_CODEX_HOME="$H49/.codex" VALIDATE_CODEX_SKILLS="$H49/.agents/skills" \
  run_validate "$R49B" "$C49" "$TMP_ROOT/out-v49a.txt" --agent codex)"
assert_eq "validar desde la ruta nueva: exit code 1" "1" "$RC"
assert_contains "dice que apunta a otro clon" "OTRO clon" "$TMP_ROOT/out-v49a.txt"
assert_contains "nombra la ruta vieja del hook" "$R49A/adapters/codex/hooks/" "$TMP_ROOT/out-v49a.txt"
assert_contains "nombra el comando que lo repara" "./install.sh --agent codex" "$TMP_ROOT/out-v49a.txt"
RC="$(run_installer "$R49B" codex "$H49" "$TMP_ROOT/out-i49b.txt")"
assert_eq "reinstalar desde la ruta nueva: exit code 0" "0" "$RC"
assert_eq "siguen siendo cinco hooks del harness" "5" \
  "$(jq '[.. | objects | .command? // empty | select(test("/adapters/codex/hooks/"))] | length' "$H49/.codex/hooks.json")"
assert_eq "ninguno apunta a la ruta vieja" "0" \
  "$(jq --arg v "$R49A/" '[.. | objects | .command? // empty | select(contains($v))] | length' "$H49/.codex/hooks.json")"
assert_not_contains "el bloque de AGENTS.md ya no nombra la ruta vieja" "$R49A/AGENTS.md" "$H49/.codex/AGENTS.md"
RC="$(VALIDATE_CODEX_HOME="$H49/.codex" VALIDATE_CODEX_SKILLS="$H49/.agents/skills" \
  run_validate "$R49B" "$C49" "$TMP_ROOT/out-v49b.txt" --agent codex)"
assert_eq "validar después de reinstalar: exit code 0" "0" "$RC"

# ────────────────────────────────────────────────────────────────────
# Si el usuario YA tiene su propio [mcp_servers.atlassian], agregar el bloque duplicaría la
# tabla: TOML inválido y Codex que no arranca. Se deja todo intacto, se dice qué falta, y el
# exit queda ≠ 0 para que nadie se vaya creyendo que la segunda capa quedó puesta.
say "50. ./install.sh --agent codex con [mcp_servers.atlassian] propio: no rompe el TOML"
R50="$TMP_ROOT/repo50"; copy_repo "$R50"
H50="$TMP_ROOT/home50"; mkdir -p "$H50/.codex"
printf '[mcp_servers.atlassian]\nurl = "https://mcp.atlassian.com/v1/mcp/authv2"\n' > "$H50/.codex/config.toml"
cp "$H50/.codex/config.toml" "$TMP_ROOT/h50-config.toml"
RC="$(run_installer "$R50" codex "$H50" "$TMP_ROOT/out-i50.txt")"
assert_eq "exit code 1 (instalado a medias)" "1" "$RC"
assert_eq "config.toml intacto" "$(cat "$TMP_ROOT/h50-config.toml")" "$(cat "$H50/.codex/config.toml")"
assert_contains "explica el conflicto" "ya define [mcp_servers.atlassian]" "$TMP_ROOT/out-i50.txt"
assert_contains "dice qué agregar a mano" "disabled_tools" "$TMP_ROOT/out-i50.txt"
assert_eq "los hooks sí quedaron" "5" \
  "$(jq '[.. | objects | .command? // empty | select(test("/adapters/codex/hooks/"))] | length' "$H50/.codex/hooks.json")"
write_profile "$R50" "Ana QA"; write_company_confluence "$R50" "abc-123-cloudid"
RC="$(VALIDATE_CODEX_HOME="$H50/.codex" VALIDATE_CODEX_SKILLS="$H50/.agents/skills" \
  run_validate "$R50" "$TMP_ROOT/claude50" "$TMP_ROOT/out-v50.txt" --agent codex)"
assert_eq "el validador lo marca: exit code 1" "1" "$RC"
assert_contains "el validador nombra la transición todavía disponible" "transitionJiraIssue sigue disponible" "$TMP_ROOT/out-v50.txt"

# ────────────────────────────────────────────────────────────────────
say "51. ./install.sh --agent codex sin ~/.codex: exit 1 y no crea nada"
R51="$TMP_ROOT/repo51"; copy_repo "$R51"
H51="$TMP_ROOT/home51"; mkdir -p "$H51"
RC="$(run_installer "$R51" codex "$H51" "$TMP_ROOT/out-i51.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_contains "dice qué falta" "No existe $H51/.codex" "$TMP_ROOT/out-i51.txt"
assert_eq "no crea nada en HOME" "" "$(files_under "$H51")"

# ────────────────────────────────────────────────────────────────────
# Actualizar el harness sobre una instalación VIEJA (los 3 hooks de antes, ya aprobados en
# /hooks): se agregan solo los 2 grupos nuevos, al final de cada evento, y ni lo ajeno ni lo
# nuestro de antes cambia de posición ni de command — su aprobación sigue valiendo.
say "52. ./install.sh --agent codex sobre la instalación anterior: suma solo los grupos nuevos"
R52="$TMP_ROOT/repo52"; copy_repo "$R52"
H52="$TMP_ROOT/home52"; mkdir -p "$H52/.codex"
cat > "$H52/.codex/hooks.json" <<EOF
{
  "hooks": {
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "/bin/sh '/opt/orca/codex-hook.sh'", "timeout": 10 } ] },
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "python3 $R52/adapters/codex/hooks/block-destructive-command.py", "timeout": 15 } ] },
      { "matcher": "mcp__.*", "hooks": [ { "type": "command", "command": "python3 $R52/adapters/codex/hooks/validate-external-write.py", "timeout": 15 } ] }
    ],
    "PostToolUse": [
      { "hooks": [ { "type": "command", "command": "/bin/sh '/opt/orca/codex-hook.sh'", "timeout": 10 } ] },
      { "matcher": "apply_patch|Edit|Write", "hooks": [ { "type": "command", "command": "python3 $R52/adapters/codex/hooks/check-after-edit.py", "timeout": 120 } ] }
    ]
  }
}
EOF
cp "$H52/.codex/hooks.json" "$TMP_ROOT/h52-antes.json"
RC="$(run_installer "$R52" codex "$H52" "$TMP_ROOT/out-i52.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_eq "PreToolUse: los grupos de antes, idénticos y en su lugar" \
  "$(jq -S '.hooks.PreToolUse' "$TMP_ROOT/h52-antes.json")" "$(jq -S '.hooks.PreToolUse[:3]' "$H52/.codex/hooks.json")"
assert_eq "PostToolUse: los grupos de antes, idénticos y en su lugar" \
  "$(jq -S '.hooks.PostToolUse' "$TMP_ROOT/h52-antes.json")" "$(jq -S '.hooks.PostToolUse[:2]' "$H52/.codex/hooks.json")"
assert_eq "PreToolUse: un solo grupo nuevo, al final, con la foto del shell" \
  "1 Bash $R52/adapters/codex/hooks/snapshot-before-shell.py" \
  "$(jq -r '"\(.hooks.PreToolUse[3:] | length) \(.hooks.PreToolUse[3].matcher) \(.hooks.PreToolUse[3].hooks[0].command | sub("^python3 "; ""))"' "$H52/.codex/hooks.json")"
assert_eq "PostToolUse: un solo grupo nuevo, al final, con el check del shell" \
  "1 Bash $R52/adapters/codex/hooks/check-after-shell.py" \
  "$(jq -r '"\(.hooks.PostToolUse[2:] | length) \(.hooks.PostToolUse[2].matcher) \(.hooks.PostToolUse[2].hooks[0].command | sub("^python3 "; ""))"' "$H52/.codex/hooks.json")"
cp "$H52/.codex/hooks.json" "$TMP_ROOT/h52-despues.json"
RC="$(run_installer "$R52" codex "$H52" "$TMP_ROOT/out-i52b.txt")"
assert_eq "reinstalar otra vez: exit code 0" "0" "$RC"
assert_eq "reinstalar otra vez no duplica nada" "$(jq -S . "$TMP_ROOT/h52-despues.json")" "$(jq -S . "$H52/.codex/hooks.json")"
assert_contains "el cierre avisa que /hooks muestra los hooks nuevos" "solo los hooks nuevos" "$TMP_ROOT/out-i52.txt"
# Aprobaste los 4 hooks de antes y la foto del shell, pero no su check: el par queda cojo y el
# gate de la terminal se abstiene en silencio. El validador lo nombra aparte.
for clave in pre_tool_use:1:0 pre_tool_use:2:0 pre_tool_use:3:0 post_tool_use:1:0; do
  printf '\n[hooks.state."%s:%s"]\ntrusted_hash = "x"\n' "$H52/.codex/hooks.json" "$clave" >> "$H52/.codex/config.toml"
done
write_profile "$R52" "Ana QA"; write_company_confluence "$R52" "abc-123-cloudid"
VALIDATE_CODEX_HOME="$H52/.codex" VALIDATE_CODEX_SKILLS="$H52/.agents/skills" \
  run_validate "$R52" "$TMP_ROOT/claude52" "$TMP_ROOT/out-v52.txt" --agent codex > /dev/null
assert_contains "el validador avisa que el par del shell tiene uno solo aprobado" "hay UNO solo aprobado" "$TMP_ROOT/out-v52.txt"

# ────────────────────────────────────────────────────────────────────
# Claude Code no se instala con hooks: viven en .claude/settings.json del repo y aplican al
# abrirlo en su raíz. Se prueban tal como quedaron enganchados ahí, de punta a punta, sobre
# una copia: foto en PreToolUse Bash, JSON roto escrito "por la terminal", block en
# PostToolUse y contexto en PostToolUseFailure (el comando que falla también escribió).
say "53. Claude Code: el par del shell de .claude/settings.json frena lo que escribió la terminal"
R53="$TMP_ROOT/repo53"; copy_repo "$R53"; git -C "$R53" init -q
T53="$TMP_ROOT/tmp53"; mkdir -p "$T53"
claude_hook() { # claude_hook <evento> <script> — argv del hook en settings.json, con la raíz resuelta
  local argv
  argv="$(jq -r --arg e "$1" --arg s "$2" \
    '[.hooks[$e][] | .hooks[] | select(.args[-1] | endswith("/" + $s)) | ([.command] + .args) | join(" ")] | first // ""' \
    "$R53/.claude/settings.json")"
  printf '%s\n' "${argv//\$\{CLAUDE_PROJECT_DIR\}/$R53}"
}
correr_claude() { # correr_claude <evento> <script> <payload> <salida>
  printf '%s' "$3" | env CLAUDE_PROJECT_DIR="$R53" TMPDIR="$T53" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    $(claude_hook "$1" "$2") > "$4" 2>&1
}
for evento in PostToolUse PostToolUseFailure; do
  LLAMADA53="{\"session_id\":\"s-53\",\"tool_use_id\":\"toolu-$evento\",\"hook_event_name\":\"$evento\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"printf\"}}"
  correr_claude PreToolUse snapshot-before-shell.py "$LLAMADA53" "$TMP_ROOT/out-53-pre-$evento.txt"
  assert_eq "$evento: la foto de PreToolUse no dice nada" "" "$(cat "$TMP_ROOT/out-53-pre-$evento.txt")"
  printf '{"a": }' > "$R53/zz-smoke-$evento.json"
  correr_claude "$evento" check-after-shell.py "$LLAMADA53" "$TMP_ROOT/out-53-post-$evento.txt"
  assert_contains "$evento: avisa el JSON roto que escribió la terminal" "falló JSON después de editar zz-smoke-$evento.json" "$TMP_ROOT/out-53-post-$evento.txt"
done
assert_contains "PostToolUse lo devuelve como block" '"decision": "block"' "$TMP_ROOT/out-53-post-PostToolUse.txt"
assert_contains "PostToolUseFailure lo devuelve como contexto" '"additionalContext"' "$TMP_ROOT/out-53-post-PostToolUseFailure.txt"
LLAMADA53='{"session_id":"s-53","tool_use_id":"toolu-sin-foto","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}'
correr_claude PostToolUse check-after-shell.py "$LLAMADA53" "$TMP_ROOT/out-53-sin-foto.txt"
assert_eq "sin foto de antes, un comando cualquiera no se frena" "" "$(cat "$TMP_ROOT/out-53-sin-foto.txt")"

# ────────────────────────────────────────────────────────────────────
# ~/.gemini/config/skills es una carpeta COMPARTIDA (gentle-ai y otras herramientas dejan ahí
# las suyas). El instalador copia lo del harness, y lo ajeno —un directorio real o un symlink
# a otro lado con el mismo nombre que una skill del harness— no lo respalda ni lo pisa: avisa.
# También retira la entrada vieja de skills.json (la de antes de las copias) y nada más.
say "54. ./install.sh --agent antigravity con config/skills ajena: la conserva, copia lo suyo, es idempotente y espeja el repo"
R54="$TMP_ROOT/repo54"; copy_repo "$R54"
H54="$TMP_ROOT/home54"; mkdir -p "$H54/.gemini/config/skills/sdd-apply" "$H54/.gemini/config/skills/qa-baseline"
echo "skill de otra herramienta" > "$H54/.gemini/config/skills/sdd-apply/SKILL.md"
echo "copia vieja del método" > "$H54/.gemini/config/skills/qa-baseline/SKILL.md"
mkdir -p "$TMP_ROOT/otra-herramienta/qa-cierre-prod"
ln -s "$TMP_ROOT/otra-herramienta/qa-cierre-prod" "$H54/.gemini/config/skills/qa-cierre-prod"
ln -s "$TMP_ROOT/otra-herramienta" "$H54/.gemini/config/skills/mi-enlace"
cat > "$H54/.gemini/config/skills.json" <<EOF
{ "entries": [ { "path": "/mis/skills" }, { "path": "$R54/skills" } ] }
EOF
RC="$(run_installer "$R54" antigravity "$H54" "$TMP_ROOT/out-i54.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_eq "la skill de otra herramienta queda intacta" "skill de otra herramienta" "$(cat "$H54/.gemini/config/skills/sdd-apply/SKILL.md")"
assert_eq "el directorio real con nombre de skill del harness NO se pisa" "copia vieja del método" "$(cat "$H54/.gemini/config/skills/qa-baseline/SKILL.md")"
assert_eq "el symlink ajeno con nombre de skill del harness NO se pisa" "$TMP_ROOT/otra-herramienta/qa-cierre-prod" \
  "$(readlink "$H54/.gemini/config/skills/qa-cierre-prod")"
assert_eq "un symlink ajeno con otro nombre ni se mira" "$TMP_ROOT/otra-herramienta" "$(readlink "$H54/.gemini/config/skills/mi-enlace")"
assert_eq "no se creó ningún backup en config/skills" "0" \
  "$(find "$H54/.gemini/config/skills" -maxdepth 1 -name '*.bak-*' | wc -l | tr -d ' ')"
assert_contains "avisa del directorio real" "qa-baseline" "$TMP_ROOT/out-i54.txt"
assert_contains "avisa del symlink ajeno" "symlink ajeno" "$TMP_ROOT/out-i54.txt"
assert_contains "el cierre dice cuántas quedaron sin copiar" "2 skill(s) quedaron SIN copiar" "$TMP_ROOT/out-i54.txt"
assert_eq "las demás skills del harness quedan copiadas" "$R54/skills/qa-analisis-ticket" \
  "$(origen_copia "$H54/.gemini/config/skills/qa-analisis-ticket")"
assert_file "references/ viaja con la copia" "$H54/.gemini/config/skills/qa-analisis-ticket/references/publicacion-jira.md"
assert_eq "skills.json: se retira SOLO la entrada del harness" "/mis/skills" \
  "$(jq -r '[.entries[].path] | join(" ")' "$H54/.gemini/config/skills.json")"
assert_eq "el sidecar anota solo lo que copió" "qa-analisis-ticket qa-automatizacion qa-cierre-ciclo qa-generacion-casos" \
  "$(jq -r '.antigravity.skillCopies | join(" ")' "$H54/.gemini/qa-harness-state.json")"
foto_skills54() { # nombre=destino-del-symlink|instalado-de-la-marca, por entrada de config/skills
  local l
  for l in "$H54"/.gemini/config/skills/*; do
    printf '%s=%s|%s\n' "$(basename "$l")" "$(readlink "$l" || true)" "$(jq -r '.instalado' "$l/.qa-harness-copia.json" 2>/dev/null || true)"
  done
}
ANTES54="$(foto_skills54)"
sleep 1  # si reinstalar reescribiera una copia, su marca cambiaría de segundo
RC="$(run_installer "$R54" antigravity "$H54" "$TMP_ROOT/out-i54b.txt")"
assert_eq "reinstalar: exit code 0" "0" "$RC"
assert_eq "reinstalar deja config/skills exactamente igual" "$ANTES54" \
  "$(foto_skills54)"
assert_eq "reinstalar no reescribe skills.json (nada nuestro que retirar)" "1" \
  "$(find "$H54/.gemini/config" -maxdepth 1 -name 'skills.json.bak-*' | wc -l | tr -d ' ')"
# El validador ve lo mismo: las ajenas son avisos con la salida a mano, no un error.
write_profile "$R54" "Ana QA"; write_company_confluence "$R54" "abc-123-cloudid"
C54="$TMP_ROOT/claude54"; CLAUDE_DIR="$C54" bash "$R54/install.sh" --agent claude > /dev/null 2>&1
RC="$(run_validate_en "$R54" "$C54" "$TMP_ROOT/sin-cursor" "$H54/.gemini" "$TMP_ROOT/out-v54.txt" --agent antigravity)"
assert_eq "validate: exit code 0 (son avisos)" "0" "$RC"
assert_contains "validate: avisa el directorio real" "Antigravity lee ESO" "$TMP_ROOT/out-v54.txt"
assert_contains "validate: cuenta las copias al día" "solo 4 de 6 skills copiadas y al día" "$TMP_ROOT/out-v54.txt"
assert_not_contains "validate: sin cambios en el repo no hay copias desactualizadas" "copia desactualizada" "$TMP_ROOT/out-v54.txt"
# Deriva: editar una skill en el repo deja la copia vieja, y el validador lo dice.
echo "línea nueva del método" >> "$R54/skills/qa-analisis-ticket/SKILL.md"
RC="$(run_validate_en "$R54" "$C54" "$TMP_ROOT/sin-cursor" "$H54/.gemini" "$TMP_ROOT/out-v54c.txt" --agent antigravity)"
assert_contains "validate: detecta la copia desactualizada" "copia desactualizada: corre ./install.sh --agent antigravity" "$TMP_ROOT/out-v54c.txt"
assert_contains "validate: nombra la skill desactualizada" "skill 'qa-analisis-ticket'" "$TMP_ROOT/out-v54c.txt"
# Espejo exacto: un archivo borrado en el repo desaparece de la copia; uno nuevo aparece.
rm "$R54/skills/qa-analisis-ticket/references/respuesta-final.md"
echo "# nueva" > "$R54/skills/qa-analisis-ticket/references/nueva.md"
RC="$(run_installer "$R54" antigravity "$H54" "$TMP_ROOT/out-i54c.txt")"
assert_eq "reinstalar tras editar: exit code 0" "0" "$RC"
assert_contains "reinstalar actualiza la copia" "qa-analisis-ticket → copia actualizada" "$TMP_ROOT/out-i54c.txt"
assert_eq "el archivo borrado en el repo desaparece de la copia" "no" \
  "$([ -e "$H54/.gemini/config/skills/qa-analisis-ticket/references/respuesta-final.md" ] && echo si || echo no)"
assert_file "el archivo nuevo del repo llega a la copia" "$H54/.gemini/config/skills/qa-analisis-ticket/references/nueva.md"
assert_contains "la edición llega a la copia" "línea nueva del método" "$H54/.gemini/config/skills/qa-analisis-ticket/SKILL.md"
RC="$(run_validate_en "$R54" "$C54" "$TMP_ROOT/sin-cursor" "$H54/.gemini" "$TMP_ROOT/out-v54d.txt" --agent antigravity)"
assert_not_contains "validate: tras reinstalar ya no hay deriva" "copia desactualizada" "$TMP_ROOT/out-v54d.txt"
# Una skill que desaparece del repo: su copia marcada se retira; lo ajeno sigue intacto.
mv "$R54/skills/qa-generacion-casos" "$TMP_ROOT/qa-generacion-casos-54"
RC="$(run_installer "$R54" antigravity "$H54" "$TMP_ROOT/out-i54d.txt")"
assert_eq "reinstalar sin una skill: exit code 0" "0" "$RC"
assert_eq "la copia de la skill que ya no está en el repo se retira" "no" \
  "$([ -e "$H54/.gemini/config/skills/qa-generacion-casos" ] && echo si || echo no)"
assert_eq "lo ajeno sigue intacto" "skill de otra herramienta|copia vieja del método" \
  "$(cat "$H54/.gemini/config/skills/sdd-apply/SKILL.md")|$(cat "$H54/.gemini/config/skills/qa-baseline/SKILL.md")"
# Y si skills.json vuelve a registrar el skills/ del repo, el validador avisa del duplicado.
echo "{ \"entries\": [ { \"path\": \"$R54/skills\" } ] }" > "$H54/.gemini/config/skills.json"
RC="$(run_validate_en "$R54" "$C54" "$TMP_ROOT/sin-cursor" "$H54/.gemini" "$TMP_ROOT/out-v54b.txt" --agent antigravity)"
assert_contains "validate: avisa la entrada vieja de skills.json" "listaría cada skill dos veces" "$TMP_ROOT/out-v54b.txt"

# ────────────────────────────────────────────────────────────────────
# Un symlink tuyo (a tus dotfiles, por ejemplo) con el nombre de una skill del harness tampoco
# es nuestro: antes se pisaba SIN backup, porque backup_if_exists salteaba los symlinks. Ahora
# se frena como una carpeta real, y con --reemplazar-skills el .bak es el symlink mismo.
say "55. ./install.sh --agent claude con un symlink ajeno: se frena; con --reemplazar-skills lo respalda tal cual"
R55="$TMP_ROOT/repo55"; copy_repo "$R55"
H55="$TMP_ROOT/home55"; mkdir -p "$H55/.claude/skills" "$TMP_ROOT/dotfiles55/qa-analisis-ticket"
echo "mi skill de dotfiles" > "$TMP_ROOT/dotfiles55/qa-analisis-ticket/SKILL.md"
ln -s "$TMP_ROOT/dotfiles55/qa-analisis-ticket" "$H55/.claude/skills/qa-analisis-ticket"
RC="$(run_installer "$R55" claude "$H55" "$TMP_ROOT/out-i55a.txt")"
assert_eq "sin la opción: exit code 1" "1" "$RC"
assert_eq "sin la opción: el symlink sigue apuntando a tus dotfiles" "$TMP_ROOT/dotfiles55/qa-analisis-ticket" \
  "$(readlink "$H55/.claude/skills/qa-analisis-ticket")"
assert_contains "el error dice a dónde apunta el symlink" \
  "$H55/.claude/skills/qa-analisis-ticket  (symlink → $TMP_ROOT/dotfiles55/qa-analisis-ticket)" "$TMP_ROOT/out-i55a.txt"
assert_eq "sin la opción: no se instala el CLAUDE.md" "no" "$([ -e "$H55/.claude/CLAUDE.md" ] && echo si || echo no)"
RC="$(run_cli "$R55" "$H55" "$TMP_ROOT/out-i55b.txt" --agent claude --reemplazar-skills)"
assert_eq "con --reemplazar-skills: exit code 0" "0" "$RC"
assert_eq "la skill queda enlazada al repo" "$R55/skills/qa-analisis-ticket" "$(readlink "$H55/.claude/skills/qa-analisis-ticket")"
BAK55="$(find "$H55/.claude/skills" -maxdepth 1 -name 'qa-analisis-ticket.bak-*' | head -1)"
assert_eq "el backup es tu symlink, tal cual" "$TMP_ROOT/dotfiles55/qa-analisis-ticket" "$(readlink "$BAK55" 2>/dev/null)"
assert_eq "tus dotfiles no se tocan" "mi skill de dotfiles" "$(cat "$TMP_ROOT/dotfiles55/qa-analisis-ticket/SKILL.md")"

# ────────────────────────────────────────────────────────────────────
# En codex el chequeo corre ANTES de hooks.json, config.toml y AGENTS.md: si se frenara recién
# al enlazar las skills, te quedaría una instalación a medias.
say "56. ./install.sh --agent codex con una skill tuya en ~/.agents/skills: se frena sin tocar ~/.codex"
R56="$TMP_ROOT/repo56"; copy_repo "$R56"
H56="$TMP_ROOT/home56"; mkdir -p "$H56/.codex" "$H56/.agents/skills/qa-baseline"
echo "mi baseline" > "$H56/.agents/skills/qa-baseline/SKILL.md"
printf '{ "hooks": {} }\n' > "$H56/.codex/hooks.json"
printf 'model = "gpt-x"\n' > "$H56/.codex/config.toml"
printf '# mis reglas de Codex\n' > "$H56/.codex/AGENTS.md"
ANTES56="$(files_under "$H56/.codex")|$(cat "$H56/.codex/hooks.json" "$H56/.codex/config.toml" "$H56/.codex/AGENTS.md")"
RC="$(run_installer "$R56" codex "$H56" "$TMP_ROOT/out-i56.txt")"
assert_eq "exit code 1" "1" "$RC"
assert_eq "hooks.json, config.toml y AGENTS.md intactos (y sin backups)" "$ANTES56" \
  "$(files_under "$H56/.codex")|$(cat "$H56/.codex/hooks.json" "$H56/.codex/config.toml" "$H56/.codex/AGENTS.md")"
assert_eq "tu skill sigue ahí" "mi baseline" "$(cat "$H56/.agents/skills/qa-baseline/SKILL.md")"
assert_eq "no se enlaza ninguna skill" "0" "$(find "$H56/.agents/skills" -maxdepth 1 -type l | wc -l | tr -d ' ')"
assert_contains "el error nombra la opción para codex" "./install.sh --agent codex --reemplazar-skills" "$TMP_ROOT/out-i56.txt"

# ────────────────────────────────────────────────────────────────────
# Una skill tuya qa-* con OTRO nombre no choca, pero sus triggers pueden pisarse con los del
# harness. Se instala igual, se avisa, y no se toca. Los .bak- del propio instalador no cuentan.
say "57. ./install.sh --agent claude con una qa-* propia de otro nombre: instala, avisa y no la toca"
R57="$TMP_ROOT/repo57"; copy_repo "$R57"
H57="$TMP_ROOT/home57"; mkdir -p "$H57/.claude/skills/qa-cierre-dev" "$H57/.claude/skills/qa-baseline.bak-20260101-000000"
echo "mi cierre dev" > "$H57/.claude/skills/qa-cierre-dev/SKILL.md"
RC="$(run_installer "$R57" claude "$H57" "$TMP_ROOT/out-i57.txt")"
assert_eq "exit code 0" "0" "$RC"
assert_contains "avisa de la qa-* ajena" "⚠️  skill qa-* que no es del harness: $H57/.claude/skills/qa-cierre-dev" "$TMP_ROOT/out-i57.txt"
assert_contains "explica por qué avisa" "Sus triggers pueden pisarse" "$TMP_ROOT/out-i57.txt"
assert_not_contains "un backup del instalador no se avisa" "qa-baseline.bak-" "$TMP_ROOT/out-i57.txt"
assert_eq "la qa-* propia queda intacta" "mi cierre dev" "$(cat "$H57/.claude/skills/qa-cierre-dev/SKILL.md")"
assert_eq "y sigue siendo una carpeta real" "no" "$([ -L "$H57/.claude/skills/qa-cierre-dev" ] && echo si || echo no)"
assert_eq "las skills del harness quedan enlazadas" "$R57/skills/qa-analisis-ticket" "$(readlink "$H57/.claude/skills/qa-analisis-ticket")"

# ────────────────────────────────────────────────────────────────────
echo
if [ "$FAILED" -gt 0 ]; then
  echo "❌ Smoke tests: $FAILED fallo(s), $PASS ok."
  exit 1
fi
echo "🟢 Smoke tests: $PASS asserts OK, 0 fallos."
