#!/usr/bin/env bash
# QA Harness Pro — valida tu configuración antes del primer uso.
# El harness enseña gates de calidad; este es el suyo.
#
#   ./validate-config.sh                        valida lo portable + cada runtime que encuentre instalado
#   ./validate-config.sh --agent claude         solo Claude Code
#   ./validate-config.sh --agent cursor         solo Cursor
#   ./validate-config.sh --agent antigravity    solo Antigravity
#   ./validate-config.sh --agent all            los tres, estén instalados o no
#
# Qué valida (campo por campo, no con un grep ciego; los campos string se extraen con strip():
# un valor de solo espacios cuenta como vacío, no como configurado):
#
#   Portable (siempre, no depende de qué agente uses):
#   - profile/profile.json: name real, activeCompany apunta a un archivo existente.
#   - companies/<activa>.json: tracker completo Y coherente (type=jira, host limpio —solo hostname—,
#     cloudId, ticketPrefixes sin entradas vacías, browseUrlPattern https:// + {KEY} + hostname REAL
#     de la URL igual a tracker.host — se parsea con urllib, no se busca subcadena)
#     y el bloque del backend de docs QUE USAS. El bloque del backend NO usado puede quedar con
#     placeholders — se ignora a propósito (no es un error tener el template intacto ahí).
#
#   claude:
#   - .mcp.json: no solo JSON válido — que los servers atlassian/notion apunten a las URLs oficiales.
#     (lo lee SOLO Claude Code: Cursor usa ~/.cursor/mcp.json y Antigravity su mcp_config.json)
#   - .claude/settings.json: no solo JSON válido — que la seguridad prometida esté activa
#     (deny de transitionJiraIssue, escrituras externas en ask o deny y los tres hooks conectados).
#   - $CLAUDE_DIR/CLAUDE.md: que el import del AGENTS.md sea el de ESTE repo.
#   - Skills enlazadas en $CLAUDE_DIR/skills: symlinks reales que resuelven a skills/ de ESTE repo.
#
#   cursor:       $CURSOR_DIR/hooks.json, $CURSOR_DIR/mcp.json y la rule en .cursor/rules/ del repo.
#   antigravity:  $GEMINI_DIR/config/{hooks,mcp_config,skills}.json y la rule en .agents/rules/.
#
#   Y para los tres, el chequeo que importa: TODO lo que el harness dejó instalado afuera tiene
#   que resolver ADENTRO de este repo. Config apuntando a otro clon es un gate que no protege.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"
# Mismos destinos y mismas variables de entorno que install.sh: si divergen, el validador
# estaría mirando un lugar distinto del que escribe el instalador.
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CURSOR_DIR="${CURSOR_DIR:-$HOME/.cursor}"
GEMINI_DIR="${GEMINI_DIR:-$HOME/.gemini}"
CONFIG_DIR="$GEMINI_DIR/config"
STATE_FILE="${QA_HARNESS_STATE:-$GEMINI_DIR/qa-harness-state.json}"
ERRORS=0
WARNINGS=0

AGENTES="claude cursor antigravity"

usage() {
  cat <<EOF
QA Harness Pro — validación de configuración

  uso:  ./validate-config.sh [--agent <claude|cursor|antigravity|all>]

    claude        .mcp.json, .claude/settings.json, el CLAUDE.md base y las skills de $CLAUDE_DIR
    cursor        hooks y MCP en $CURSOR_DIR, y la rule en .cursor/rules/ de este repo
    antigravity   hooks, MCP y skills en $CONFIG_DIR, y la rule en .agents/rules/ de este repo
    all           los tres, estén instalados o no

    --help        muestra esta ayuda

  Sin --agent NO es un error, a diferencia de install.sh: se valida lo portable (perfil y
  empresa) más cada runtime que se encuentre instalado. Es el modo que AGENTS.md documenta
  como paso de reparación, y romperlo cambiaría el significado de una instrucción que ya
  viaja en el ~/.claude/CLAUDE.md de cada usuario.
  Valores válidos: claude, cursor, antigravity, all.
EOF
}

# ── Argumentos ──────────────────────────────────────────────────────
AGENT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --agent)
      if [ $# -lt 2 ]; then
        echo "❌ --agent necesita un valor."; echo; usage; exit 1
      fi
      AGENT="$2"; shift 2 ;;
    --agent=*) AGENT="${1#--agent=}"; shift ;;
    *) echo "❌ Argumento desconocido: $1"; echo; usage; exit 1 ;;
  esac
done

if [ -n "$AGENT" ]; then
  case " $AGENTES all " in
    *" $AGENT "*) ;;
    *) echo "❌ Agente desconocido: '$AGENT'."; echo; usage; exit 1 ;;
  esac
fi

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

json_valido() { # json_valido <archivo> — existe y parsea
  [ -f "$1" ] && python3 -m json.tool "$1" >/dev/null 2>&1
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

primera_linea_util() { grep -v '^[[:space:]]*$' "$1" 2>/dev/null | head -1 || true; }

# ── Identidad de lo instalado ───────────────────────────────────────
# Lo que el harness deja FUERA del repo hay que poder reconocerlo sin depender de la ruta:
# si el repo se muda, lo viejo sigue instalado y hace falta poder decir "esto es mío y está
# apuntando a otro lado". Se usan EXACTAMENTE las mismas reglas de identidad que install.sh
# — si divergen, el validador miente:
#   · cursor       → el NOMBRE del script del hook (por eso desduplica el instalador)
#   · antigravity  → el grupo 'qa-harness-pro' (hooks) y el sidecar $STATE_FILE (skills)
#   · claude       → la FORMA del import '@<algo>/AGENTS.md' y los symlinks de skills/
# Lo que no entra en esas reglas es del USUARIO: un hook suyo o un server suyo apuntando a
# donde quiera no es un error nuestro, y no se toca ni se reporta.
comandos_de_hooks() { # comandos_de_hooks <archivo> <clave-raíz o ""> <resolver-{{HARNESS}} 0|1>
  python3 - "$1" "$2" "$3" "$REPO_DIR" <<'PY' 2>/dev/null
import json, sys
ruta, clave, resolver, repo = sys.argv[1:5]
crudo = open(ruta, encoding="utf-8").read()
if resolver == "1":
    crudo = crudo.replace("{{HARNESS}}", repo)
d = json.loads(crudo)
if clave:
    d = d.get(clave, {})
def comandos(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "command" and isinstance(v, str):
                yield v
            else:
                yield from comandos(v)
    elif isinstance(o, list):
        for v in o:
            yield from comandos(v)
for c in comandos(d):
    print(c)
PY
}

script_del_comando() { printf '%s\n' "${1##* }"; }   # "python3 /x/y.py" → /x/y.py
nombre_de_script()   { printf '%s\n' "${1##*/}"; }   # /x/y.py → y.py

scripts_del_adaptador() { # scripts_del_adaptador <agente> — nombres de los hooks que instala ese adaptador
  # Se derivan del config del repo, no de una lista escrita a mano: agregar o quitar un hook
  # en adapters/<agente>/config/hooks.json no puede dejar al validador chequeando otra cosa.
  local cfg="$REPO_DIR/adapters/$1/config/hooks.json" cmd
  [ -f "$cfg" ] || return 0
  while IFS= read -r cmd; do
    [ -n "$cmd" ] && nombre_de_script "$(script_del_comando "$cmd")"
  done < <(comandos_de_hooks "$cfg" "" 0)
}

REPO_REAL="$(resolve_path "$REPO_DIR")"

dentro_del_repo() { # dentro_del_repo <ruta> — ¿resuelve ADENTRO de este repo?
  # Por realpath, no por texto: /tmp y /var son symlinks en macOS, y la misma carpeta se
  # escribe de dos formas distintas según quién la nombró.
  case "$(resolve_path "$1")" in
    "$REPO_REAL"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# EL chequeo que habría cazado los bugs de la mudanza de repo: todo lo instalado tiene que
# resolver adentro de ESTE repo. Si no, el gate no es el tuyo — y eso es un error, no un
# aviso: un gate que no corre no protege nada.
# Se separan dos causas porque se leen y se sienten distinto (aunque la reparación sea la misma):
#   · la ruta ya no existe          → el gate NO corre, y no avisa: falla en silencio
#   · existe, pero es de OTRO clon  → el gate corre, pero es el de ese otro clon: valida
#                                     contra sus reglas, sus skills y sus hooks, no los tuyos
ruta_instalada_ok() { # ruta_instalada_ok <agente> <qué-es> <ruta> — 0 si apunta a este repo
  local agente="$1" que="$2" ruta="$3"
  if [ ! -e "$ruta" ]; then
    fail "$que apunta a una ruta que YA NO EXISTE: '$ruta'. Ese gate no corre, y no te avisa: falla en silencio. Reinstálalo desde este repo con ./install.sh --agent $agente"
    return 1
  fi
  if ! dentro_del_repo "$ruta"; then
    fail "$que apunta a OTRO clon del harness: '$ruta', no a este repo ($REPO_DIR). Lo que corre son los gates de ese otro clon, no los de acá. Reapúntalo con ./install.sh --agent $agente"
    return 1
  fi
  return 0
}

echo "🧰 QA Harness Pro — validación de configuración"

# 0. python3 disponible (lo usamos para validar JSON)
if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ Necesito python3 para validar los JSON (viene con macOS/Linux). Instálalo y reintenta."
  exit 1
fi

# ── Alcance ─────────────────────────────────────────────────────────
# Con --agent: el usuario afirma que ese runtime está instalado, así que no encontrarlo es un
# ERROR. Sin --agent: se valida lo que HAY. claude entra siempre (este repo es un proyecto de
# Claude Code: .mcp.json y .claude/settings.json vienen versionados acá, y validarlos no
# depende de haber instalado nada). cursor y antigravity entran solo si el harness dejó su
# huella ahí — que ~/.cursor exista no significa que lo hayas instalado, y gritarle a quien
# solo usa Claude Code convertiría el comando de reparación en ruido.
hay_footprint_cursor() {
  local cmd base esperados
  json_valido "$CURSOR_DIR/hooks.json" || return 1
  esperados=" $(scripts_del_adaptador cursor | tr '\n' ' ') "
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    base="$(nombre_de_script "$(script_del_comando "$cmd")")"
    case "$esperados" in *" $base "*) return 0 ;; esac
  done < <(comandos_de_hooks "$CURSOR_DIR/hooks.json" "" 0)
  return 1
}

hay_footprint_antigravity() {
  if [ -f "$STATE_FILE" ] && [ -n "$(json_get_str "$STATE_FILE" "d.get('antigravity',{}).get('skillsPath','')")" ]; then
    return 0
  fi
  json_valido "$CONFIG_DIR/hooks.json" || return 1
  [ "$(json_get "$CONFIG_DIR/hooks.json" "'qa-harness-pro' in d")" = "True" ]
}

if [ -n "$AGENT" ]; then
  MODO="explicito"
  case "$AGENT" in
    all) SELECCION="$AGENTES" ;;
    *) SELECCION="$AGENT" ;;
  esac
  echo "   agente: $AGENT"
else
  MODO="auto"
  SELECCION="claude"
  hay_footprint_cursor && SELECCION="$SELECCION cursor"
  hay_footprint_antigravity && SELECCION="$SELECCION antigravity"
  echo "   agentes: $SELECCION (lo que encontré instalado — usa --agent <claude|cursor|antigravity|all> para elegir)"
fi
echo

en_scope() { case " $SELECCION " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

no_instalado() { # no_instalado <agente> <detalle>
  if [ "$MODO" = "explicito" ]; then
    fail "$1: $2 — me pediste validar $1 y el harness no está instalado ahí. Instálalo con ./install.sh --agent $1"
  else
    warn "$1: $2 — la instalación de $1 quedó a medias. Complétala con ./install.sh --agent $1"
  fi
}

# Los tres runtimes registran los MISMOS dos servers, cada uno en su archivo. El chequeo es
# el mismo: no basta con que el JSON sea válido, tienen que apuntar a las URLs oficiales.
validar_mcp_servers() { # validar_mcp_servers <archivo> <etiqueta> <cómo-repararlo>
  local archivo="$1" etiqueta="$2" reparar="$3"
  local count atl_type atl_url notion_type notion_url
  count="$(json_get "$archivo" "len(d.get('mcpServers',{}))")"
  : "${count:=0}"
  if [ "$count" = "0" ]; then
    fail "$etiqueta es JSON válido pero mcpServers está vacío — sin el server atlassian el agente no llega a Jira/Confluence. $reparar"
    return
  fi
  atl_type="$(json_get "$archivo" "d.get('mcpServers',{}).get('atlassian',{}).get('type','')")"
  atl_url="$(json_get "$archivo" "d.get('mcpServers',{}).get('atlassian',{}).get('url','')")"
  if [ "$atl_type" = "http" ] && [ "$atl_url" = "https://mcp.atlassian.com/v1/mcp/authv2" ]; then
    ok "$etiqueta: server atlassian OK (type http, URL oficial)."
  else
    fail "$etiqueta: falta el server 'atlassian' o no apunta al oficial (esperado: type \"http\", url https://mcp.atlassian.com/v1/mcp/authv2). $reparar"
  fi
  notion_type="$(json_get "$archivo" "d.get('mcpServers',{}).get('notion',{}).get('type','')")"
  notion_url="$(json_get "$archivo" "d.get('mcpServers',{}).get('notion',{}).get('url','')")"
  if [ "$notion_type" = "http" ] && [ "$notion_url" = "https://mcp.notion.com/mcp" ]; then
    ok "$etiqueta: server notion OK (type http, URL oficial)."
  elif [ "$BACKEND" = "notion" ]; then
    fail "$etiqueta: falta el server 'notion' o no apunta al oficial (esperado: type \"http\", url https://mcp.notion.com/mcp) y tu docs.backend es notion — sin él no se puede documentar. $reparar"
  else
    warn "$etiqueta: el server 'notion' falta o no apunta al oficial (https://mcp.notion.com/mcp). Con docs.backend=confluence o jira no lo necesitas, pero si algún día cambias a notion, restáuralo."
  fi
}

# ════════════════════════════════════════════════════════════════════
# PORTABLE — no depende de qué agente uses
# ════════════════════════════════════════════════════════════════════

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
        fail "tracker.type = '$TTYPE' — v2 soporta solo Jira: pon \"jira\". Para adaptar el harness a otro tracker, mira docs/ADAPTAR-OTRO-STACK.md."
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

# ════════════════════════════════════════════════════════════════════
# claude — .mcp.json, .claude/settings.json, el CLAUDE.md base y las skills enlazadas
# ════════════════════════════════════════════════════════════════════
validar_claude() {
  echo
  echo "🔹 claude — $CLAUDE_DIR"

  # 3. .mcp.json (viene versionado en el repo — lo carga SOLO Claude Code desde la raíz)
  # No basta que sea JSON válido: tiene que declarar los servers que el harness promete.
  if [ ! -f .mcp.json ]; then
    warn "No existe .mcp.json — viene versionado en el repo; si lo borraste, restáuralo con 'git checkout -- .mcp.json'. Sin él el agente no se conecta a Jira/Confluence/Notion (la demo funciona sin esto)."
  elif python3 -m json.tool .mcp.json >/dev/null 2>&1; then
    ok ".mcp.json existe y es JSON válido."
    validar_mcp_servers .mcp.json ".mcp.json" "Restáuralo con 'git checkout -- .mcp.json'."
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
    HOOK_OK="$(json_get .claude/settings.json "any(isinstance(g,dict) and g.get('matcher') == 'Bash' and any(isinstance(h,dict) and h.get('type') == 'command' and h.get('command') == 'python3' and h.get('args') == ['\${CLAUDE_PROJECT_DIR}/adapters/claude/hooks/block-destructive-command.py'] for h in g.get('hooks',[]) if isinstance(g.get('hooks',[]),list)) for g in d.get('hooks',{}).get('PreToolUse',[]) if isinstance(d.get('hooks',{}),dict) and isinstance(d.get('hooks',{}).get('PreToolUse',[]),list))")"
    if [ "$HOOK_OK" = "True" ] && [ -f adapters/claude/hooks/block-destructive-command.py ]; then
      ok ".claude/settings.json: hook PreToolUse de comandos destructivos conectado."
    else
      fail ".claude/settings.json: falta el hook PreToolUse de comandos destructivos o no apunta a adapters/claude/hooks/block-destructive-command.py — el quality gate no está activo. Restáuralo con 'git checkout -- .claude/settings.json adapters/claude/hooks/block-destructive-command.py'."
    fi
    POST_EDIT_HOOK_OK="$(json_get .claude/settings.json "any(isinstance(g,dict) and g.get('matcher') == 'Edit|Write' and any(isinstance(h,dict) and h.get('type') == 'command' and h.get('command') == 'python3' and h.get('args') == ['\${CLAUDE_PROJECT_DIR}/adapters/claude/hooks/check-after-edit.py'] for h in g.get('hooks',[]) if isinstance(g.get('hooks',[]),list)) for g in d.get('hooks',{}).get('PostToolUse',[]) if isinstance(d.get('hooks',{}),dict) and isinstance(d.get('hooks',{}).get('PostToolUse',[]),list))")"
    if [ "$POST_EDIT_HOOK_OK" = "True" ] && [ -f adapters/claude/hooks/check-after-edit.py ]; then
      ok ".claude/settings.json: hook PostToolUse de validación post-edit conectado."
    else
      fail ".claude/settings.json: falta el hook PostToolUse de validación post-edit o no apunta a adapters/claude/hooks/check-after-edit.py — los cambios no reciben feedback automático. Restáuralo con 'git checkout -- .claude/settings.json adapters/claude/hooks/check-after-edit.py'."
    fi
    EXTERNAL_WRITE_MATCHER="mcp__atlassian__addCommentToJiraIssue|mcp__atlassian__createJiraIssue|mcp__atlassian__editJiraIssue|mcp__atlassian__createConfluencePage|mcp__atlassian__updateConfluencePage|mcp__notion__notion-create-pages|mcp__notion__notion-update-page"
    EXTERNAL_WRITE_HOOK_OK="$(json_get .claude/settings.json "any(isinstance(g,dict) and g.get('matcher') == '$EXTERNAL_WRITE_MATCHER' and any(isinstance(h,dict) and h.get('type') == 'command' and h.get('command') == 'python3' and h.get('args') == ['\${CLAUDE_PROJECT_DIR}/adapters/claude/hooks/validate-external-write.py'] for h in g.get('hooks',[]) if isinstance(g.get('hooks',[]),list)) for g in d.get('hooks',{}).get('PreToolUse',[]) if isinstance(d.get('hooks',{}),dict) and isinstance(d.get('hooks',{}).get('PreToolUse',[]),list))")"
    if [ "$EXTERNAL_WRITE_HOOK_OK" = "True" ] && [ -f adapters/claude/hooks/validate-external-write.py ]; then
      ok ".claude/settings.json: hook PreToolUse de validación de publicaciones externas conectado."
    else
      fail ".claude/settings.json: falta el hook PreToolUse de publicaciones externas o no apunta a adapters/claude/hooks/validate-external-write.py — un payload incompleto podría llegar a Jira/Confluence/Notion. Restáuralo con 'git checkout -- .claude/settings.json adapters/claude/hooks/validate-external-write.py'."
    fi
  else
    fail ".claude/settings.json no es JSON válido — restáuralo con 'git checkout -- .claude/settings.json'."
  fi

  # 5. El CLAUDE.md base: la línea de import es la que hace llegar TODAS las reglas.
  # Un import roto no avisa — Claude Code no importa nada y sigue como si nada.
  local claude_md="$CLAUDE_DIR/CLAUDE.md" primera importado
  if [ ! -f "$claude_md" ]; then
    warn "No existe $claude_md — sin él las reglas del harness (AGENTS.md) no le llegan a Claude Code. Instálalo con ./install.sh --agent claude"
  else
    primera="$(primera_linea_util "$claude_md")"
    case "$primera" in
      '@'*/AGENTS.md)
        # La forma del import es la MISMA regla de identidad que usa install.sh para saber si
        # ese archivo es suyo. Si lo es, tiene que importar el AGENTS.md de ESTE repo.
        importado="${primera#@}"
        if ruta_instalada_ok claude "claude: el import de $claude_md" "$importado"; then
          ok "$claude_md importa el AGENTS.md de este repo."
        fi
        ;;
      *)
        warn "$claude_md existe pero no empieza importando el AGENTS.md del harness — las reglas no le llegan. Agrega esta línea al principio de ese archivo: @$REPO_DIR/AGENTS.md"
        ;;
    esac
  fi

  # 6. skills enlazadas (respeta CLAUDE_DIR, igual que install.sh)
  # Enlazada = symlink ∧ destino existente ∧ resuelve a skills/<nombre> de ESTE repo.
  # Un symlink roto o apuntando a otro lado NO cuenta como enlazada.
  local LINKED=0 name link TOTAL
  for skill in skills/*/; do
    name="$(basename "$skill")"
    link="$CLAUDE_DIR/skills/$name"
    if [ ! -e "$link" ] && [ ! -L "$link" ]; then
      continue  # no enlazada a secas — la cuenta el resumen de abajo
    elif [ ! -L "$link" ]; then
      warn "skill '$name': $link existe pero NO es un symlink — no cuenta como enlazada (¿copia vieja?). Corre ./install.sh --agent claude (hace backup antes de enlazar)."
    elif [ ! -e "$link" ]; then
      warn "skill '$name': symlink ROTO — apunta a '$(readlink "$link")' que ya no existe. No cuenta como enlazada; corre ./install.sh --agent claude"
    elif [ "$(resolve_path "$link")" != "$(resolve_path "${skill%/}")" ]; then
      warn "skill '$name': el symlink apunta a '$(resolve_path "$link")', no a la skill de este repo ($(resolve_path "${skill%/}")). No cuenta como enlazada; corre ./install.sh --agent claude"
    else
      LINKED=$((LINKED+1))
    fi
  done
  TOTAL=$(find skills -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  if [ "$LINKED" -eq "$TOTAL" ]; then
    ok "Las $TOTAL skills están enlazadas en $CLAUDE_DIR/skills (symlinks que resuelven a este repo)."
  else
    warn "Solo $LINKED de $TOTAL skills enlazadas de verdad en $CLAUDE_DIR/skills — corre ./install.sh --agent claude"
  fi
}

# ════════════════════════════════════════════════════════════════════
# cursor — hooks y MCP en $CURSOR_DIR, rule en el .cursor/rules/ del repo
# ════════════════════════════════════════════════════════════════════
validar_cursor() {
  echo
  echo "🔹 cursor — $CURSOR_DIR"
  local hooks="$CURSOR_DIR/hooks.json"
  local esperados presentes="" cmd script base rutas_ok=1 propios=0

  if [ ! -f "$hooks" ]; then
    no_instalado cursor "no existe $hooks"
  elif ! python3 -m json.tool "$hooks" >/dev/null 2>&1; then
    fail "cursor: $hooks no es JSON válido — Cursor no va a cargar ningún hook y los gates no corren. Corre ./install.sh --agent cursor (hace backup antes de fusionar)."
  else
    esperados=" $(scripts_del_adaptador cursor | tr '\n' ' ') "
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      script="$(script_del_comando "$cmd")"
      base="$(nombre_de_script "$script")"
      # Solo lo NUESTRO: un hook tuyo apuntando a donde quieras es tuyo, no un error.
      case "$esperados" in *" $base "*) ;; *) continue ;; esac
      presentes="$presentes $base"
      propios=$((propios+1))
      ruta_instalada_ok cursor "cursor: el hook '$base' de $hooks" "$script" || rutas_ok=0
    done < <(comandos_de_hooks "$hooks" "" 0)

    for base in $esperados; do
      case " $presentes " in
        *" $base "*) ;;
        *) fail "cursor: falta el hook '$base' en $hooks — ese gate no está conectado. Corre ./install.sh --agent cursor"; rutas_ok=0 ;;
      esac
    done
    if [ "$propios" -eq 0 ]; then
      no_instalado cursor "$hooks no tiene ningún hook del harness"
    elif [ "$rutas_ok" = "1" ]; then
      ok "cursor: los $propios hooks del harness apuntan a este repo."
    fi
  fi

  if [ ! -f "$CURSOR_DIR/mcp.json" ]; then
    no_instalado cursor "no existe $CURSOR_DIR/mcp.json"
  elif python3 -m json.tool "$CURSOR_DIR/mcp.json" >/dev/null 2>&1; then
    validar_mcp_servers "$CURSOR_DIR/mcp.json" "cursor: mcp.json" "Corre ./install.sh --agent cursor"
  else
    fail "cursor: $CURSOR_DIR/mcp.json no es JSON válido — Cursor no va a levantar ningún server MCP. Corre ./install.sh --agent cursor (hace backup antes de fusionar)."
  fi

  # La rule va en el scope de PROYECTO: Cursor lee <proyecto>/.cursor/rules/, no ~/.cursor/rules/.
  if [ -f "$REPO_DIR/.cursor/rules/qa-harness.mdc" ]; then
    ok "cursor: la rule está en .cursor/rules/ de este repo (scope de proyecto)."
  else
    fail "cursor: falta .cursor/rules/qa-harness.mdc en este repo — sin esa rule las reglas del harness no le llegan a Cursor. Corre ./install.sh --agent cursor"
  fi
}

# ════════════════════════════════════════════════════════════════════
# antigravity — hooks, MCP y skills en $CONFIG_DIR
# ════════════════════════════════════════════════════════════════════
validar_antigravity() {
  echo
  echo "🔹 antigravity — $CONFIG_DIR"
  local hooks="$CONFIG_DIR/hooks.json"
  local esperados presentes="" cmd script base rutas_ok=1 propios=0

  if [ ! -f "$hooks" ]; then
    no_instalado antigravity "no existe $hooks"
  elif ! python3 -m json.tool "$hooks" >/dev/null 2>&1; then
    fail "antigravity: $hooks no es JSON válido — no va a cargar ningún hook y los gates no corren. Corre ./install.sh --agent antigravity (hace backup antes de fusionar)."
  elif [ "$(json_get "$hooks" "'qa-harness-pro' in d")" != "True" ]; then
    no_instalado antigravity "$hooks no tiene el grupo 'qa-harness-pro'"
  else
    # Acá la identidad es el GRUPO: todo lo que cuelga de 'qa-harness-pro' es nuestro, y los
    # grupos de al lado son del usuario y ni se miran.
    esperados=" $(scripts_del_adaptador antigravity | tr '\n' ' ') "
    while IFS= read -r cmd; do
      [ -n "$cmd" ] || continue
      script="$(script_del_comando "$cmd")"
      base="$(nombre_de_script "$script")"
      presentes="$presentes $base"
      propios=$((propios+1))
      ruta_instalada_ok antigravity "antigravity: el hook '$base' del grupo 'qa-harness-pro'" "$script" || rutas_ok=0
    done < <(comandos_de_hooks "$hooks" "qa-harness-pro" 0)

    for base in $esperados; do
      case " $presentes " in
        *" $base "*) ;;
        *) fail "antigravity: falta el hook '$base' en el grupo 'qa-harness-pro' de $hooks — ese gate no está conectado. Corre ./install.sh --agent antigravity"; rutas_ok=0 ;;
      esac
    done
    if [ "$propios" -eq 0 ]; then
      no_instalado antigravity "el grupo 'qa-harness-pro' de $hooks está vacío"
    elif [ "$rutas_ok" = "1" ]; then
      ok "antigravity: los $propios hooks del grupo 'qa-harness-pro' apuntan a este repo."
    fi
  fi

  if [ ! -f "$CONFIG_DIR/mcp_config.json" ]; then
    no_instalado antigravity "no existe $CONFIG_DIR/mcp_config.json"
  elif python3 -m json.tool "$CONFIG_DIR/mcp_config.json" >/dev/null 2>&1; then
    validar_mcp_servers "$CONFIG_DIR/mcp_config.json" "antigravity: mcp_config.json" "Corre ./install.sh --agent antigravity"
  else
    fail "antigravity: $CONFIG_DIR/mcp_config.json no es JSON válido — no va a levantar ningún server MCP. Corre ./install.sh --agent antigravity (hace backup antes de fusionar)."
  fi

  # skills: el schema de Antigravity es {path} y nada más, así que la entrada no lleva marcas
  # nuestras. Lo que la identifica es el sidecar, igual que en install.sh: ahí quedó anotado
  # QUÉ path registramos la última vez. Sin sidecar no se puede probar que una entrada sea
  # nuestra, y una entrada ajena apuntando afuera no es asunto del validador.
  local skills_json="$CONFIG_DIR/skills.json" nuestro="$REPO_DIR/skills"
  local registrado="" tiene_nuestro tiene_registrado vieja_reportada=0
  if [ -f "$STATE_FILE" ]; then
    registrado="$(json_get_str "$STATE_FILE" "d.get('antigravity',{}).get('skillsPath','')")"
  fi
  if [ ! -f "$skills_json" ]; then
    no_instalado antigravity "no existe $skills_json"
  elif ! python3 -m json.tool "$skills_json" >/dev/null 2>&1; then
    fail "antigravity: $skills_json no es JSON válido — no va a cargar ninguna skill. Corre ./install.sh --agent antigravity (hace backup antes de fusionar)."
  else
    if [ -n "$registrado" ] && [ "$registrado" != "$nuestro" ]; then
      tiene_registrado="$(json_get "$skills_json" "any(isinstance(e,dict) and e.get('path')=='$registrado' for e in d.get('entries',[]))")"
      if [ "$tiene_registrado" = "True" ]; then
        ruta_instalada_ok antigravity "antigravity: la entrada de skills de $skills_json (la que anotó el sidecar $STATE_FILE)" "$registrado"
        vieja_reportada=1
      fi
    fi
    tiene_nuestro="$(json_get "$skills_json" "any(isinstance(e,dict) and e.get('path')=='$nuestro' for e in d.get('entries',[]))")"
    if [ "$tiene_nuestro" = "True" ]; then
      ok "antigravity: skills.json registra el skills/ de este repo."
    elif [ "$vieja_reportada" = "0" ]; then
      no_instalado antigravity "$skills_json no registra $nuestro"
    fi
  fi

  # La rule va en el scope de PROYECTO: Antigravity lee <workspace>/.agents/rules/, no ~/.gemini.
  # Registrar las skills no alcanza — sin esta rule el método llega y las reglas no.
  if [ -f "$REPO_DIR/.agents/rules/qa-harness.md" ]; then
    ok "antigravity: la rule está en .agents/rules/ de este repo (scope de proyecto)."
  else
    fail "antigravity: falta .agents/rules/qa-harness.md en este repo — sin esa rule las reglas del harness no le llegan a Antigravity. Corre ./install.sh --agent antigravity"
  fi
}

en_scope claude && validar_claude
en_scope cursor && validar_cursor
en_scope antigravity && validar_antigravity

echo
if [ "$ERRORS" -gt 0 ]; then
  echo "❌ $ERRORS error(es), $WARNINGS aviso(s). Corrige los errores antes de usar el harness."
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo "🟡 Configuración usable con $WARNINGS aviso(s)."
else
  echo "🟢 Configuración lista. Prueba la demo: abre Claude Code y escribe 'Analiza el ticket de demo/ticket-ejemplo.md'."
fi
