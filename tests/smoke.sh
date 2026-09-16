#!/usr/bin/env bash
# QA Harness Pro — smoke tests de install.sh y validate-config.sh.
# TODO corre en directorios temporales (mktemp): jamás toca ~/.claude ni tu configuración real.
set -euo pipefail

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

assert_contains() { # assert_contains <descripción> <texto> <archivo-de-output>
  if grep -qF "$2" "$3"; then t_ok "$1"; else t_bad "$1 (no encontré: '$2' en $(basename "$3"))"; fi
}

assert_not_contains() { # assert_not_contains <descripción> <texto> <archivo-de-output>
  if grep -qF "$2" "$3"; then t_bad "$1 (encontré '$2' en $(basename "$3") y NO debería estar)"; else t_ok "$1"; fi
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

run_validate() { # run_validate <repo> <claude_dir> <archivo-output> → imprime exit code
  local rc=0
  CLAUDE_DIR="$2" bash "$1/validate-config.sh" > "$3" 2>&1 || rc=$?
  echo "$rc"
}

echo "🧪 QA Harness Pro — smoke tests (sandbox: $TMP_ROOT)"

# ────────────────────────────────────────────────────────────────────
say "1. install.sh en CLAUDE_DIR vacío crea los symlinks"
R1="$TMP_ROOT/repo1"; copy_repo "$R1"
C1="$TMP_ROOT/claude1"
CLAUDE_DIR="$C1" bash "$R1/install.sh" > "$TMP_ROOT/out-install1.txt" 2>&1

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

# ────────────────────────────────────────────────────────────────────
say "2. install.sh con directorio real preexistente: hace backup, no anida symlink"
R2="$TMP_ROOT/repo2"; copy_repo "$R2"
C2="$TMP_ROOT/claude2"
mkdir -p "$C2/skills/qa-analisis-ticket"
echo "contenido previo del comprador" > "$C2/skills/qa-analisis-ticket/nota.md"
CLAUDE_DIR="$C2" bash "$R2/install.sh" > "$TMP_ROOT/out-install2.txt" 2>&1

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

# ────────────────────────────────────────────────────────────────────
say "3. validate-config.sh: confluence completa (placeholders SOLO en bloque notion no usado) = exit 0"
RV="$TMP_ROOT/repo-validate"; copy_repo "$RV"
CV="$TMP_ROOT/claude-validate"
CLAUDE_DIR="$CV" bash "$RV/install.sh" > /dev/null 2>&1
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
CLAUDE_DIR="$C13" bash "$R13/install.sh" > /dev/null 2>&1
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
CLAUDE_DIR="$C15" bash "$R15/install.sh" > /dev/null 2>&1
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
CLAUDE_DIR="$CV" bash "$RV/install.sh" > /dev/null 2>&1

# ────────────────────────────────────────────────────────────────────
say "18. install.sh: backup exitoso + ln fallido → restaura el backup y sale ≠ 0"
R18="$TMP_ROOT/repo18"; copy_repo "$R18"
C18="$TMP_ROOT/claude18"
mkdir -p "$C18/skills/qa-analisis-ticket"
echo "contenido previo del comprador" > "$C18/skills/qa-analisis-ticket/nota.md"
# stub de ln vía PATH: siempre falla — simula un ln que muere tras el mv del backup
STUB_BIN="$TMP_ROOT/stub-bin"; mkdir -p "$STUB_BIN"
printf '#!/bin/sh\nexit 1\n' > "$STUB_BIN/ln"
chmod +x "$STUB_BIN/ln"
RC18=0
PATH="$STUB_BIN:$PATH" CLAUDE_DIR="$C18" bash "$R18/install.sh" > "$TMP_ROOT/out-install18.txt" 2>&1 || RC18=$?
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
CLAUDE_DIR="$C19" bash "$R19/install.sh" > /dev/null 2>&1
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
echo
if [ "$FAILED" -gt 0 ]; then
  echo "❌ Smoke tests: $FAILED fallo(s), $PASS ok."
  exit 1
fi
echo "🟢 Smoke tests: $PASS asserts OK, 0 fallos."
