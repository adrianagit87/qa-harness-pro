#!/usr/bin/env bash
# QA Harness Pro — valida tu configuración antes del primer uso.
# El harness enseña gates de calidad; este es el suyo.
#
# Qué valida (campo por campo, no con un grep ciego; los campos string se extraen con strip():
# un valor de solo espacios cuenta como vacío, no como configurado):
#   - profile/profile.json: name real, activeCompany apunta a un archivo existente.
#   - companies/<activa>.json: tracker completo Y coherente (type=jira, host limpio —solo hostname—,
#     cloudId, ticketPrefixes sin entradas vacías, browseUrlPattern https:// + {KEY} + hostname REAL
#     de la URL igual a tracker.host — se parsea con urllib, no se busca subcadena)
#     y el bloque del backend de docs QUE USAS. El bloque del backend NO usado puede quedar con
#     placeholders — se ignora a propósito (no es un error tener el template intacto ahí).
#   - .mcp.json: no solo JSON válido — que los servers atlassian/notion apunten a las URLs oficiales.
#   - .claude/settings.json: no solo JSON válido — que la seguridad prometida esté activa
#     (deny de transitionJiraIssue, escrituras externas en ask o deny y los tres hooks conectados).
#   - Skills enlazadas en $CLAUDE_DIR/skills: symlinks reales que resuelven a skills/ de ESTE repo
#     (un symlink roto o apuntando a otro lado no cuenta como enlazada).
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
ERRORS=0
WARNINGS=0

fail() { echo "❌ $1"; ERRORS=$((ERRORS+1)); }
warn() { echo "⚠️  $1"; WARNINGS=$((WARNINGS+1)); }
ok()   { echo "✅ $1"; }

json_get() { # json_get <archivo> <expresión python sobre d>
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2" 2>/dev/null
}

json_get_str() { # como json_get pero para campos string: normaliza con strip() EN LA EXTRACCIÓN.
  # Así un campo de solo espacios ("   ") llega vacío a TODOS los chequeos de vacío/placeholder
  # (-z, is_placeholder) sin duplicar la normalización campo por campo.
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); v=eval(sys.argv[2]); print(v.strip() if isinstance(v,str) else v)" "$1" "$2" 2>/dev/null
}

resolve_path() { # realpath portable (macOS/Linux) — python3 ya es requisito
  python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1" 2>/dev/null
}

url_host() { # url_host <url> — hostname REAL de la URL según urllib.parse (vacío si no parsea)
  python3 -c "import sys; from urllib.parse import urlparse; print(urlparse(sys.argv[1]).hostname or '')" "$1" 2>/dev/null
}

is_placeholder() { # vacío o empieza con PON-AQUI
  case "$1" in
    "" | PON-AQUI*) return 0 ;;
    *) return 1 ;;
  esac
}

echo "🧰 QA Harness Pro — validación de configuración"
echo

# 0. python3 disponible (lo usamos para validar JSON)
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Necesito python3 para validar los JSON (viene con macOS/Linux). Instálalo y reintenta."
  exit 1
fi

# 1. profile/profile.json
ACTIVE=""
if [ ! -f profile/profile.json ]; then
  fail "No existe profile/profile.json — copia profile/profile.example.json y complétalo."
elif ! python3 -m json.tool profile/profile.json >/dev/null 2>&1; then
  fail "profile/profile.json no es JSON válido."
else
  ok "profile/profile.json existe y es JSON válido."
  NAME="$(json_get_str profile/profile.json "d.get('name','')")"
  ACTIVE="$(json_get_str profile/profile.json "d.get('activeCompany','')")"
  if [ -z "$NAME" ] || [ "$NAME" = "Tu Nombre" ]; then
    fail "profile.name sigue en placeholder ('Tu Nombre') — pon tu nombre real (firma los cierres)."
  fi
  if [ -z "$ACTIVE" ]; then
    fail "profile.activeCompany está vacío — indica qué empresa de companies/ usar (ej. 'acme')."
  elif [ ! -f "companies/$ACTIVE.json" ]; then
    fail "profile.activeCompany = '$ACTIVE' pero no existe companies/$ACTIVE.json — créalo desde companies/_template.json."
  fi
fi

# 2. companies/<activeCompany>.json — validación campo por campo
BACKEND=""
if [ -n "$ACTIVE" ] && [ -f "companies/$ACTIVE.json" ]; then
  COMPANY_FILE="companies/$ACTIVE.json"
  if ! python3 -m json.tool "$COMPANY_FILE" >/dev/null 2>&1; then
    fail "$COMPANY_FILE no es JSON válido."
  else
    ok "$COMPANY_FILE existe y es JSON válido."

    # -- company --
    CNAME="$(json_get_str "$COMPANY_FILE" "d.get('company',{}).get('name','')")"
    if [ -z "$CNAME" ] || [ "$CNAME" = "Tu Empresa" ]; then
      fail "company.name sigue en placeholder ('Tu Empresa') — pon el nombre real de tu empresa."
    fi

    # -- tracker (obligatorio) --
    HAS_TRACKER="$(json_get "$COMPANY_FILE" "'tracker' in d")"
    if [ "$HAS_TRACKER" != "True" ]; then
      fail "Falta el bloque 'tracker' en $COMPANY_FILE — sin él las skills no saben dónde vive tu Jira. Míralo en companies/_template.json."
    else
      TTYPE="$(json_get "$COMPANY_FILE" "d['tracker'].get('type','')")"
      if [ "$TTYPE" != "jira" ]; then
        fail "tracker.type = '$TTYPE' — v1 soporta solo Jira: pon \"jira\". Para adaptar el harness a otro tracker, mira docs/ADAPTAR-OTRO-STACK.md."
      fi

      HOST="$(json_get_str "$COMPANY_FILE" "d['tracker'].get('host','')")"
      HOST_CLEAN=0
      if [ -z "$HOST" ]; then
        fail "tracker.host está vacío — pon tu host de Jira (ej. miempresa.atlassian.net)."
      elif [ "$HOST" = "tuempresa.atlassian.net" ]; then
        fail "tracker.host sigue con el valor del template ('tuempresa.atlassian.net')."
      else
        case "$HOST" in
          *://*|*/*|*@*|*:*|*[[:space:]]*)
            fail "tracker.host debe ser un hostname limpio: sin esquema, sin '/', sin '@', sin puerto y sin espacios (tiene: '$HOST'). Ej.: miempresa.atlassian.net."
            ;;
          *)
            HOST_CLEAN=1
            ok "tracker.host: $HOST"
            ;;
        esac
      fi

      CLOUDID="$(json_get_str "$COMPANY_FILE" "d['tracker'].get('cloudId','')")"
      if is_placeholder "$CLOUDID"; then
        fail "tracker.cloudId está vacío o en placeholder — obténlo con GET https://<tu-host>/_edge/tenant_info."
      fi

      PREF_COUNT="$(json_get "$COMPANY_FILE" "len(d['tracker']['ticketPrefixes']) if isinstance(d['tracker'].get('ticketPrefixes'),list) else -1")"
      : "${PREF_COUNT:=-1}"
      if [ "$PREF_COUNT" = "-1" ]; then
        fail "tracker.ticketPrefixes debe ser una lista de prefijos (ej. [\"PROJ\"])."
      elif [ "$PREF_COUNT" = "0" ]; then
        fail "tracker.ticketPrefixes está vacío — agrega al menos un prefijo de proyecto (ej. \"PROJ\")."
      else
        PREF_BAD="$(json_get "$COMPANY_FILE" "sum(1 for p in d['tracker']['ticketPrefixes'] if not isinstance(p,str) or not p.strip())")"
        : "${PREF_BAD:=0}"
        if [ "$PREF_BAD" != "0" ]; then
          fail "tracker.ticketPrefixes tiene $PREF_BAD entrada(s) vacía(s) o que no son texto — cada prefijo debe ser un string no vacío (ej. \"PROJ\")."
        fi
      fi

      BROWSE="$(json_get_str "$COMPANY_FILE" "d['tracker'].get('browseUrlPattern','')")"
      if [ -z "$BROWSE" ]; then
        fail "tracker.browseUrlPattern está vacío — patrón de URL de ticket, con {KEY} como marcador (ej. https://<tu-host>/browse/{KEY})."
      else
        BROWSE_OK=1
        if ! printf '%s' "$BROWSE" | grep -q "{KEY}"; then
          fail "tracker.browseUrlPattern no contiene {KEY} — sin ese marcador no se pueden construir las URLs de tickets."
          BROWSE_OK=0
        fi
        case "$BROWSE" in
          https://*) : ;;
          *)
            fail "tracker.browseUrlPattern debe empezar con https:// (tiene: '$BROWSE')."
            BROWSE_OK=0
            ;;
        esac
        # Coherencia host ↔ pattern: se compara el HOSTNAME REAL de la URL (urllib.parse) con
        # tracker.host, EXACTO — no subcadenas. 'acme.atlassian.net.evil.example',
        # 'evil.example/acme.atlassian.net/...' o 'acme.atlassian.net@evil.example' no pasan
        # por parecerse: el navegador iría a otro sitio.
        if [ "$HOST_CLEAN" = "1" ] && [ "${BROWSE#https://}" != "$BROWSE" ]; then
          PATTERN_HOST="$(url_host "$BROWSE")"
          HOST_LC="$(printf '%s' "$HOST" | tr '[:upper:]' '[:lower:]')"
          if [ "$PATTERN_HOST" = "tuempresa.atlassian.net" ]; then
            fail "tracker.browseUrlPattern sigue con el host del template ('tuempresa.atlassian.net') — cámbialo por tu host real ($HOST)."
            BROWSE_OK=0
          elif [ -z "$PATTERN_HOST" ]; then
            fail "tracker.browseUrlPattern no tiene un hostname reconocible (tiene: '$BROWSE')."
            BROWSE_OK=0
          elif [ "$PATTERN_HOST" != "$HOST_LC" ]; then
            fail "tracker.browseUrlPattern apunta al host '$PATTERN_HOST', no a tu tracker.host ($HOST) — el patrón generaría URLs de tickets de otro sitio (tiene: '$BROWSE')."
            BROWSE_OK=0
          fi
        fi
        if [ "$HOST_CLEAN" = "1" ]; then
          [ "$BROWSE_OK" = "1" ] && ok "tracker.browseUrlPattern coherente con tracker.host."
        else
          warn "La coherencia de tracker.browseUrlPattern no se pudo verificar — arregla primero tracker.host."
        fi
      fi
    fi

    # -- docs: solo se valida el bloque del backend ACTIVO --
    BACKEND="$(json_get_str "$COMPANY_FILE" "d.get('docs',{}).get('backend','')")"
    case "$BACKEND" in
      confluence)
        SPACE="$(json_get_str "$COMPANY_FILE" "d.get('docs',{}).get('confluence',{}).get('spaceKey','')")"
        PARENT="$(json_get_str "$COMPANY_FILE" "d.get('docs',{}).get('confluence',{}).get('parentPageId','')")"
        BLOCK_OK=1
        if is_placeholder "$SPACE"; then
          fail "docs.backend=confluence pero docs.confluence.spaceKey está vacío o en placeholder."
          BLOCK_OK=0
        fi
        if is_placeholder "$PARENT"; then
          fail "docs.backend=confluence pero docs.confluence.parentPageId está vacío o en placeholder — es obligatorio (bajo esa página se crea toda la doc)."
          BLOCK_OK=0
        fi
        [ "$BLOCK_OK" = "1" ] && ok "Backend de docs: confluence (space: $SPACE). El bloque notion no se valida (no lo usas)."
        ;;
      jira)
        QAPROJ="$(json_get_str "$COMPANY_FILE" "d.get('docs',{}).get('jira',{}).get('qaProject','')")"
        CONT_TYPE="$(json_get_str "$COMPANY_FILE" "d.get('docs',{}).get('jira',{}).get('containerIssueType','')")"
        CASE_TYPE="$(json_get_str "$COMPANY_FILE" "d.get('docs',{}).get('jira',{}).get('caseIssueType','')")"
        CASE_PAT="$(json_get_str "$COMPANY_FILE" "d.get('docs',{}).get('jira',{}).get('caseTitlePattern','')")"
        BLOCK_OK=1
        if is_placeholder "$QAPROJ"; then
          fail "docs.backend=jira pero docs.jira.qaProject está vacío o en placeholder — es el proyecto donde se crean los tickets de QA."
          BLOCK_OK=0
        fi
        if is_placeholder "$CONT_TYPE"; then
          fail "docs.backend=jira pero docs.jira.containerIssueType está vacío o en placeholder — es el tipo del ticket de QA que contiene los CP (ej. Epic)."
          BLOCK_OK=0
        fi
        if is_placeholder "$CASE_TYPE"; then
          fail "docs.backend=jira pero docs.jira.caseIssueType está vacío o en placeholder — es el tipo de cada CP hijo (ej. Tarea)."
          BLOCK_OK=0
        fi
        if is_placeholder "$CASE_PAT"; then
          fail "docs.backend=jira pero docs.jira.caseTitlePattern está vacío o en placeholder — sin patrón, los CP se nombran de forma inconsistente."
          BLOCK_OK=0
        elif ! printf '%s' "$CASE_PAT" | grep -q '{CP_ID}'; then
          fail "docs.jira.caseTitlePattern debe incluir {CP_ID} — sin él, los CP no se pueden identificar al cerrar el ciclo (tiene: '$CASE_PAT')."
          BLOCK_OK=0
        fi
        [ "$BLOCK_OK" = "1" ] && ok "Backend de docs: jira (proyecto QA: $QAPROJ · contenedor: $CONT_TYPE · casos: $CASE_TYPE). Los bloques confluence/notion no se validan (no los usas)."
        ;;
      notion)
        NPARENT="$(json_get_str "$COMPANY_FILE" "d.get('docs',{}).get('notion',{}).get('parents',{}).get('casos','')")"
        if is_placeholder "$NPARENT"; then
          fail "docs.backend=notion pero docs.notion.parents.casos está vacío o en placeholder — es obligatorio."
        else
          ok "Backend de docs: notion. El bloque confluence no se valida (no lo usas)."
        fi
        ;;
      *)
        fail "docs.backend debe ser 'confluence', 'notion' o 'jira' (tiene: '$BACKEND')."
        ;;
    esac

    # -- automation es opcional — solo aviso --
    FRAMEWORK="$(json_get "$COMPANY_FILE" "d.get('automation',{}).get('framework','')")"
    [ -z "$FRAMEWORK" ] && warn "automation sin configurar — qa-automatizacion solo podrá evaluar, no generar código integrado (OK si no automatizas aún)."
  fi
fi

# 3. .mcp.json (viene versionado en el repo — Claude Code lo carga desde la raíz)
# No basta que sea JSON válido: tiene que declarar los servers que el harness promete.
if [ ! -f .mcp.json ]; then
  warn "No existe .mcp.json — viene versionado en el repo; si lo borraste, restáuralo con 'git checkout -- .mcp.json'. Sin él el agente no se conecta a Jira/Confluence/Notion (la demo funciona sin esto)."
elif python3 -m json.tool .mcp.json >/dev/null 2>&1; then
  ok ".mcp.json existe y es JSON válido."
  SERVER_COUNT="$(json_get .mcp.json "len(d.get('mcpServers',{}))")"
  : "${SERVER_COUNT:=0}"
  if [ "$SERVER_COUNT" = "0" ]; then
    fail ".mcp.json es JSON válido pero mcpServers está vacío — sin el server atlassian el agente no llega a Jira/Confluence. Restáuralo con 'git checkout -- .mcp.json'."
  else
    ATL_TYPE="$(json_get .mcp.json "d.get('mcpServers',{}).get('atlassian',{}).get('type','')")"
    ATL_URL="$(json_get .mcp.json "d.get('mcpServers',{}).get('atlassian',{}).get('url','')")"
    if [ "$ATL_TYPE" = "http" ] && [ "$ATL_URL" = "https://mcp.atlassian.com/v1/mcp/authv2" ]; then
      ok ".mcp.json: server atlassian OK (type http, URL oficial)."
    else
      fail ".mcp.json: falta el server 'atlassian' o no apunta al oficial (esperado: type \"http\", url https://mcp.atlassian.com/v1/mcp/authv2) — restáuralo con 'git checkout -- .mcp.json'."
    fi
    NOTION_TYPE="$(json_get .mcp.json "d.get('mcpServers',{}).get('notion',{}).get('type','')")"
    NOTION_URL="$(json_get .mcp.json "d.get('mcpServers',{}).get('notion',{}).get('url','')")"
    if [ "$NOTION_TYPE" = "http" ] && [ "$NOTION_URL" = "https://mcp.notion.com/mcp" ]; then
      ok ".mcp.json: server notion OK (type http, URL oficial)."
    elif [ "$BACKEND" = "notion" ]; then
      fail ".mcp.json: falta el server 'notion' o no apunta al oficial (esperado: type \"http\", url https://mcp.notion.com/mcp) y tu docs.backend es notion — sin él no se puede documentar. Restáuralo con 'git checkout -- .mcp.json'."
    else
      warn ".mcp.json: el server 'notion' falta o no apunta al oficial (https://mcp.notion.com/mcp). Con docs.backend=confluence o jira no lo necesitas, pero si algún día cambias a notion, restáuralo."
    fi
  fi
else
  fail ".mcp.json no es JSON válido — restáuralo con 'git checkout -- .mcp.json'."
fi

# 4. .claude/settings.json (los permisos del harness — deny de transiciones, ask antes de escribir)
# No basta que sea JSON válido: tiene que CONTENER la seguridad que el README promete.
if [ ! -f .claude/settings.json ]; then
  warn "No existe .claude/settings.json — viene versionado en el repo; sin él NO aplican los permisos del harness (el deny de transitionJiraIssue incluido). Restáuralo con 'git checkout -- .claude/settings.json'."
elif python3 -m json.tool .claude/settings.json >/dev/null 2>&1; then
  # 4a. Tipos primero: permissions.allow/ask/deny (las que existan) deben ser LISTAS de strings.
  # Con un string, el 'in' de Python haría matching de SUBCADENAS en los chequeos de pertenencia
  # (un settings malformado pasaría), y Claude Code directamente ignora ese formato.
  PERM_TYPES_OK=1
  PERMS_IS_DICT="$(json_get .claude/settings.json "isinstance(d.get('permissions',{}),dict)")"
  if [ "$PERMS_IS_DICT" != "True" ]; then
    fail ".claude/settings.json: 'permissions' debe ser un objeto con listas allow/ask/deny — Claude Code ignora este formato y la seguridad prometida no aplica. Restáuralo con 'git checkout -- .claude/settings.json'."
    PERM_TYPES_OK=0
  else
    for key in allow ask deny; do
      KEY_OK="$(json_get .claude/settings.json "(lambda v: True if v is None else (isinstance(v,list) and all(isinstance(x,str) for x in v)))(d.get('permissions',{}).get('$key'))")"
      if [ "$KEY_OK" != "True" ]; then
        fail ".claude/settings.json: permissions.$key debe ser una lista de strings — Claude Code ignora este formato y la seguridad prometida no aplica. Restáuralo con 'git checkout -- .claude/settings.json'."
        PERM_TYPES_OK=0
      fi
    done
  fi
  # 4b. Pertenencia — solo tiene sentido sobre listas de verdad.
  if [ "$PERM_TYPES_OK" = "1" ]; then
    DENY_OK="$(json_get .claude/settings.json "'mcp__atlassian__transitionJiraIssue' in d.get('permissions',{}).get('deny',[])")"
    if [ "$DENY_OK" = "True" ]; then
      ok ".claude/settings.json: transitionJiraIssue está en permissions.deny (nadie cambia estados de Jira por ti)."
    else
      fail ".claude/settings.json: mcp__atlassian__transitionJiraIssue NO está en permissions.deny — la seguridad prometida no está activa (el agente podría cambiar estados de Jira). Restáuralo con 'git checkout -- .claude/settings.json'."
    fi
    # Toda herramienta externa de ESCRITURA debe estar gated: en ask (pregunta antes) o en deny.
    WRITE_TOOLS="mcp__atlassian__addCommentToJiraIssue mcp__atlassian__createJiraIssue mcp__atlassian__editJiraIssue mcp__atlassian__createConfluencePage mcp__atlassian__updateConfluencePage mcp__notion__notion-create-pages mcp__notion__notion-update-page"
    UNGATED=""
    for tool in $WRITE_TOOLS; do
      GATED="$(json_get .claude/settings.json "'$tool' in d.get('permissions',{}).get('ask',[]) or '$tool' in d.get('permissions',{}).get('deny',[])")"
      [ "$GATED" != "True" ] && UNGATED="$UNGATED $tool"
    done
    if [ -z "$UNGATED" ]; then
      ok ".claude/settings.json: todas las escrituras externas (Jira/Confluence/Notion) están en ask o deny."
    else
      fail ".claude/settings.json: estas herramientas de ESCRITURA quedaron fuera de ask y de deny:$UNGATED — el agente podría escribir hacia afuera sin preguntar. Restáuralo con 'git checkout -- .claude/settings.json'."
    fi
  fi
  # 4c. El primer hook de seguridad debe estar conectado de verdad, no solo existir como script.
  HOOK_OK="$(json_get .claude/settings.json "any(isinstance(g,dict) and g.get('matcher') == 'Bash' and any(isinstance(h,dict) and h.get('type') == 'command' and h.get('command') == 'python3' and h.get('args') == ['\${CLAUDE_PROJECT_DIR}/hooks/block-destructive-command.py'] for h in g.get('hooks',[]) if isinstance(g.get('hooks',[]),list)) for g in d.get('hooks',{}).get('PreToolUse',[]) if isinstance(d.get('hooks',{}),dict) and isinstance(d.get('hooks',{}).get('PreToolUse',[]),list))")"
  if [ "$HOOK_OK" = "True" ] && [ -f hooks/block-destructive-command.py ]; then
    ok ".claude/settings.json: hook PreToolUse de comandos destructivos conectado."
  else
    fail ".claude/settings.json: falta el hook PreToolUse de comandos destructivos o no apunta a hooks/block-destructive-command.py — el quality gate no está activo. Restáuralo con 'git checkout -- .claude/settings.json hooks/block-destructive-command.py'."
  fi
  POST_EDIT_HOOK_OK="$(json_get .claude/settings.json "any(isinstance(g,dict) and g.get('matcher') == 'Edit|Write' and any(isinstance(h,dict) and h.get('type') == 'command' and h.get('command') == 'python3' and h.get('args') == ['\${CLAUDE_PROJECT_DIR}/hooks/check-after-edit.py'] for h in g.get('hooks',[]) if isinstance(g.get('hooks',[]),list)) for g in d.get('hooks',{}).get('PostToolUse',[]) if isinstance(d.get('hooks',{}),dict) and isinstance(d.get('hooks',{}).get('PostToolUse',[]),list))")"
  if [ "$POST_EDIT_HOOK_OK" = "True" ] && [ -f hooks/check-after-edit.py ]; then
    ok ".claude/settings.json: hook PostToolUse de validación post-edit conectado."
  else
    fail ".claude/settings.json: falta el hook PostToolUse de validación post-edit o no apunta a hooks/check-after-edit.py — los cambios no reciben feedback automático. Restáuralo con 'git checkout -- .claude/settings.json hooks/check-after-edit.py'."
  fi
  EXTERNAL_WRITE_MATCHER="mcp__atlassian__addCommentToJiraIssue|mcp__atlassian__createJiraIssue|mcp__atlassian__editJiraIssue|mcp__atlassian__createConfluencePage|mcp__atlassian__updateConfluencePage|mcp__notion__notion-create-pages|mcp__notion__notion-update-page"
  EXTERNAL_WRITE_HOOK_OK="$(json_get .claude/settings.json "any(isinstance(g,dict) and g.get('matcher') == '$EXTERNAL_WRITE_MATCHER' and any(isinstance(h,dict) and h.get('type') == 'command' and h.get('command') == 'python3' and h.get('args') == ['\${CLAUDE_PROJECT_DIR}/hooks/validate-external-write.py'] for h in g.get('hooks',[]) if isinstance(g.get('hooks',[]),list)) for g in d.get('hooks',{}).get('PreToolUse',[]) if isinstance(d.get('hooks',{}),dict) and isinstance(d.get('hooks',{}).get('PreToolUse',[]),list))")"
  if [ "$EXTERNAL_WRITE_HOOK_OK" = "True" ] && [ -f hooks/validate-external-write.py ]; then
    ok ".claude/settings.json: hook PreToolUse de validación de publicaciones externas conectado."
  else
    fail ".claude/settings.json: falta el hook PreToolUse de publicaciones externas o no apunta a hooks/validate-external-write.py — un payload incompleto podría llegar a Jira/Confluence/Notion. Restáuralo con 'git checkout -- .claude/settings.json hooks/validate-external-write.py'."
  fi
else
  fail ".claude/settings.json no es JSON válido — restáuralo con 'git checkout -- .claude/settings.json'."
fi

# 5. skills enlazadas (respeta CLAUDE_DIR, igual que install.sh)
# Enlazada = symlink ∧ destino existente ∧ resuelve a skills/<nombre> de ESTE repo.
# Un symlink roto o apuntando a otro lado NO cuenta como enlazada.
LINKED=0
for skill in skills/*/; do
  name="$(basename "$skill")"
  link="$CLAUDE_DIR/skills/$name"
  if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    continue  # no enlazada a secas — la cuenta el resumen de abajo
  elif [ ! -L "$link" ]; then
    warn "skill '$name': $link existe pero NO es un symlink — no cuenta como enlazada (¿copia vieja?). Corre ./install.sh (hace backup antes de enlazar)."
  elif [ ! -e "$link" ]; then
    warn "skill '$name': symlink ROTO — apunta a '$(readlink "$link")' que ya no existe. No cuenta como enlazada; corre ./install.sh."
  elif [ "$(resolve_path "$link")" != "$(resolve_path "${skill%/}")" ]; then
    warn "skill '$name': el symlink apunta a '$(resolve_path "$link")', no a la skill de este repo ($(resolve_path "${skill%/}")). No cuenta como enlazada; corre ./install.sh."
  else
    LINKED=$((LINKED+1))
  fi
done
TOTAL=$(find skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "$LINKED" -eq "$TOTAL" ]; then
  ok "Las $TOTAL skills están enlazadas en $CLAUDE_DIR/skills (symlinks que resuelven a este repo)."
else
  warn "Solo $LINKED de $TOTAL skills enlazadas de verdad en $CLAUDE_DIR/skills — corre ./install.sh."
fi

echo
if [ "$ERRORS" -gt 0 ]; then
  echo "❌ $ERRORS error(es), $WARNINGS aviso(s). Corrige los errores antes de usar el harness."
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo "🟡 Configuración usable con $WARNINGS aviso(s)."
else
  echo "🟢 Configuración lista. Prueba la demo: abre Claude Code y escribe 'Analiza el ticket de demo/ticket-ejemplo.md'."
fi
