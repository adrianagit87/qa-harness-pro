#!/usr/bin/env bash
# QA Harness Pro — setup reproducible. Un solo instalador para los cuatro agentes:
#
#   ./install.sh --agent claude       enlaza las skills y el CLAUDE.md base en ~/.claude
#   ./install.sh --agent cursor       fusiona hooks y MCP en ~/.cursor
#   ./install.sh --agent antigravity  fusiona hooks y MCP en ~/.gemini/config, copia las skills
#                                     en ~/.gemini/config/skills y deja la rule en .agents/rules/
#                                     de este repo
#   ./install.sh --agent codex        fusiona hooks en $CODEX_HOME/hooks.json, agrega bloques
#                                     gestionados a config.toml y AGENTS.md, y enlaza las skills
#                                     en ~/.agents/skills
#   ./install.sh --agent all          los cuatro
#
# No pisa nada tuyo sin avisar: hace backup con timestamp de lo que fuera a sobrescribir. Si ya
# tienes skills PROPIAS con el nombre de las del harness (en ~/.claude/skills o ~/.agents/skills),
# se frena sin tocar nada; solo con --reemplazar-skills las respalda y las reemplaza.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CURSOR_DIR="${CURSOR_DIR:-$HOME/.cursor}"
GEMINI_DIR="${GEMINI_DIR:-$HOME/.gemini}"
CONFIG_DIR="$GEMINI_DIR/config"
# CODEX_HOME es la variable que respeta el propio Codex: si la tienes fijada, el harness se
# instala donde Codex de verdad lee. Las skills de usuario de Codex viven FUERA de CODEX_HOME,
# en ~/.agents/skills; CODEX_SKILLS_DIR existe para poder probarlo en un sandbox.
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_SKILLS_DIR="${CODEX_SKILLS_DIR:-$HOME/.agents/skills}"
# Sidecar PROPIO del harness: acá anotamos qué registramos en la config ajena, para poder
# retirarlo después sin adivinar. Vive al lado de qa-harness-unknown-tools.log, que ya
# estableció ~/.gemini como un lugar donde el harness escribe lo suyo.
STATE_FILE="${QA_HARNESS_STATE:-$GEMINI_DIR/qa-harness-state.json}"
STAMP="$(date +%Y%m%d-%H%M%S)"

AGENTES="claude cursor antigravity codex"

usage() {
  cat <<EOF
QA Harness Pro — install

  uso:  ./install.sh --agent <claude|cursor|antigravity|codex|all>

    claude        skills enlazadas + CLAUDE.md base en $CLAUDE_DIR
    cursor        hooks + MCP en $CURSOR_DIR, y la rule en .cursor/rules/ de este repo
    antigravity   hooks + MCP en $CONFIG_DIR, skills copiadas en $CONFIG_DIR/skills, y la rule
                  en .agents/rules/ de este repo
    codex         hooks en $CODEX_HOME/hooks.json, bloque gestionado en config.toml (MCP de
                  Atlassian con aprobación por tool) y en AGENTS.md, skills en $CODEX_SKILLS_DIR
    all           los cuatro, en ese orden

    --reemplazar-skills
                  (claude y codex) si en la carpeta de skills ya hay una tuya con el mismo
                  nombre que una del harness, la mueve a <nombre>.bak-<fecha> y enlaza la del
                  harness. Sin esta opción, el instalador se frena y no toca nada.
    --help        muestra esta ayuda

  --agent es obligatorio y no tiene default: sin él no se instala nada.
  Valores válidos: claude, cursor, antigravity, codex, all.
EOF
}

# ── Argumentos ──────────────────────────────────────────────────────
# Sin --agent NO se instala nada. Elegir claude por default sería un éxito ambiguo:
# quien viene de Cursor creería que instaló y se iría sin reglas, con el instalador
# diciéndole "✅". Un fallo ruidoso es mejor.
AGENT=""
REEMPLAZAR_SKILLS=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --reemplazar-skills) REEMPLAZAR_SKILLS=1; shift ;;
    --agent)
      if [ $# -lt 2 ]; then
        echo "❌ --agent necesita un valor."; echo; usage; exit 1
      fi
      AGENT="$2"; shift 2 ;;
    --agent=*) AGENT="${1#--agent=}"; shift ;;
    *) echo "❌ Argumento desconocido: $1"; echo; usage; exit 1 ;;
  esac
done

if [ -z "$AGENT" ]; then
  echo "❌ Falta --agent: no adivino para qué herramienta quieres instalar."; echo; usage; exit 1
fi

case " $AGENTES all " in
  *" $AGENT "*) ;;
  *) echo "❌ Agente desconocido: '$AGENT'."; echo; usage; exit 1 ;;
esac

# jq solo hace falta para fusionar JSON ajeno, o sea para cursor, antigravity y codex. La
# instalación de claude no lo toca, así que exigirlo ahí sería pedir una dependencia
# que no se usa.
case "$AGENT" in
  cursor|antigravity|codex|all)
    command -v jq > /dev/null 2>&1 || {
      echo "❌ Falta jq: lo necesita la instalación de '$AGENT' para fusionar tu config JSON sin pisarla."
      echo "   macOS: brew install jq · Debian/Ubuntu: sudo apt install jq"
      exit 1
    } ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── Piezas compartidas ──────────────────────────────────────────────
banner() { # banner <nombre-del-agente> <línea-de-destino>
  echo "🧰 QA Harness Pro — install ($1)"
  echo "   repo:   $REPO_DIR"
  echo "   $2"
  echo
}

# Las rutas se resuelven acá: los JSON y el CLAUDE.md del repo llevan el placeholder
# {{HARNESS}}. Tiene que quedar una ruta ABSOLUTA porque los archivos se instalan FUERA
# del repo, y tanto Claude Code como los hooks resuelven lo relativo contra otra cosa.
render() { sed "s|{{HARNESS}}|$REPO_DIR|g" "$1" > "$2"; }

# Fusión de JSON ajeno (cursor y antigravity): se respalda con `cp` y se reescribe el
# archivo. No es el mismo backup que el de claude, y es a propósito: acá el destino es
# un archivo que sigue existiendo después (fusionado), no un directorio que se reemplaza
# por un symlink.
merge() { # merge <archivo-destino> <expresión jq> <archivo-fuente> [args extra de jq]
  local dest="$1" expr="$2" src="$3" tmp
  shift 3
  tmp="$(mktemp)"
  if [ -f "$dest" ]; then
    cp "$dest" "$dest.bak-$STAMP"
    echo "   backup: $(basename "$dest") → $(basename "$dest").bak-$STAMP"
  else
    echo '{}' > "$dest"
  fi
  if ! jq --slurpfile new "$src" "$@" "$expr" "$dest" > "$tmp"; then
    echo "❌ Falló la fusión de $(basename "$dest") — tu archivo quedó intacto."
    rm -f "$tmp"; exit 1
  fi
  mv "$tmp" "$dest"
}

# ── claude ──────────────────────────────────────────────────────────
BACKUP_PATH=""  # backup_if_exists y enlazar_skills dejan aquí la ruta del último backup (o vacío)

# Backup con `mv` y salteando symlinks, para el CLAUDE.md del harness que se re-renderiza:
# el contenido previo sale del camino (no alcanza con copiarlo). Las skills NO pasan por
# acá: un symlink en la carpeta de skills puede ser tuyo, y enlazar_skills lo decide con
# es_del_harness.
backup_if_exists() {
  local target="$1"
  BACKUP_PATH=""
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mv "$target" "$target.bak-$STAMP"
    BACKUP_PATH="$target.bak-$STAMP"
    echo "   backup: $target → $(basename "$target").bak-$STAMP"
  fi
}

# ¿Es del harness lo que hay en <carpeta>/<nombre>? Mismo criterio que symlink_del_harness en
# adapters/antigravity/copias_skills.py: lo es si no existe, si es un symlink roto, si apunta a
# skills/<nombre> de este repo, o si apunta a skills/<nombre> de OTRO clon del harness (lo dejó
# una instalación desde otra ruta). Otro clon se reconoce porque la ruta, sin el sufijo
# /skills/<nombre>, tiene install.sh Y core/gates/: un solo archivo con nombre genérico podría
# estar en cualquier repo, los dos juntos solo en el harness. Todo lo demás (una carpeta o un
# archivo real, un symlink a otro lado) es TUYO.
es_del_harness() { # es_del_harness <ruta> <nombre>
  local ruta="$1" name="$2" apunta sufijo="/skills/$2" raiz
  [ -e "$ruta" ] || [ -L "$ruta" ] || return 0
  [ -L "$ruta" ] || return 1
  [ -e "$ruta" ] || return 0
  apunta="$(readlink "$ruta")"
  apunta="${apunta%/}"
  [ "$apunta" = "$REPO_DIR/skills/$name" ] && return 0
  case "$apunta" in
    /*"$sufijo")
      raiz="${apunta%"$sufijo"}"
      [ -f "$raiz/install.sh" ] && [ -d "$raiz/core/gates" ] && return 0 ;;
  esac
  return 1
}

# Antes de tocar NADA (claude y codex): si en la carpeta de skills hay algo tuyo con el nombre
# de una skill del harness, lo más probable es que sea una skill propia que se llama igual.
# Moverla a un .bak en silencio te la haría desaparecer del agente sin que te enteres, así que
# sin --reemplazar-skills se frena acá, con la instalación entera sin empezar.
# Si sigue, avisa además de las skills qa-* que no son del harness: no chocan de nombre, pero
# sus triggers pueden pisarse con los nuestros.
revisar_conflictos_skills() { # revisar_conflictos_skills <carpeta-destino> <agente>
  local destino="$1" agente="$2" skill name target conflictos="" entrada
  [ -d "$REPO_DIR/skills" ] || return 0
  for skill in "$REPO_DIR"/skills/*/; do
    [ -d "$skill" ] || continue
    name="$(basename "$skill")"
    target="$destino/$name"
    es_del_harness "$target" "$name" && continue
    if [ -L "$target" ]; then
      conflictos="$conflictos     $target  (symlink → $(readlink "$target"))"$'\n'
    elif [ -d "$target" ]; then
      conflictos="$conflictos     $target  (carpeta propia)"$'\n'
    else
      conflictos="$conflictos     $target  (archivo propio)"$'\n'
    fi
  done

  if [ -n "$conflictos" ] && [ "$REEMPLAZAR_SKILLS" != "1" ]; then
    echo "❌ En $destino ya hay skills con el mismo nombre que las del harness, y no son de este repo:"
    printf '%s' "$conflictos"
    echo "   Seguramente son skills tuyas que se llaman igual. No toqué nada: ni esas ni el resto de la instalación."
    echo "   Si quieres reemplazarlas por las del harness, vuelve a correr con --reemplazar-skills:"
    echo "     ./install.sh --agent $agente --reemplazar-skills"
    echo "   Cada una se mueve a <nombre>.bak-<fecha> en la misma carpeta, y en su lugar queda el enlace a este repo."
    exit 1
  fi

  local ajenas=0
  for entrada in "$destino"/qa-*; do
    [ -e "$entrada" ] || [ -L "$entrada" ] || continue
    name="$(basename "$entrada")"
    case "$name" in *.bak-*) continue ;; esac
    [ -d "$REPO_DIR/skills/$name" ] && continue
    es_del_harness "$entrada" "$name" && [ -L "$entrada" ] && continue
    echo "   ⚠️  skill qa-* que no es del harness: $entrada"
    ajenas=1
  done
  if [ "$ajenas" = "1" ]; then
    echo "       Sus triggers pueden pisarse con los de las skills del harness, y el agente puede elegir cualquiera de las dos."
  fi
  return 0
}

# Enlazar skills (idempotente). Lo usan claude y codex: los dos leen una carpeta de skills
# con un directorio por skill, y el symlink trae references/ entero sin copiar nada.
# Lo del harness (un symlink nuestro, de este clon o de otro) se pisa sin respaldar: no es
# contenido de nadie. Lo tuyo solo llega hasta acá con --reemplazar-skills (ver
# revisar_conflictos_skills), y entonces primero se respalda con `mv` — incluso un symlink
# tuyo, que se mueve tal cual. Sin ese backup, `ln -sfn` crearía el symlink ADENTRO de un
# directorio existente y reportaría "enlazada" sin que fuera verdad.
# Y si `ln` falla DESPUÉS del backup, se restaura el backup: jamás te dejamos sin
# contenido y sin enlace a la vez.
enlazar_skills() { # enlazar_skills <carpeta-destino> <agente>
  local destino="$1" agente="$2" skill name target
  [ -d "$REPO_DIR/skills" ] || return 0
  for skill in "$REPO_DIR"/skills/*/; do
    [ -d "$skill" ] || continue
    name="$(basename "$skill")"
    target="$destino/$name"
    BACKUP_PATH=""
    if ! es_del_harness "$target" "$name"; then
      mv "$target" "$target.bak-$STAMP"
      BACKUP_PATH="$target.bak-$STAMP"
      echo "   backup: $target → $(basename "$target").bak-$STAMP"
    fi
    if ! ln -sfn "${skill%/}" "$target"; then
      echo "❌ No pude crear el enlace de '$name' en $target."
      if [ -n "$BACKUP_PATH" ]; then
        if mv "$BACKUP_PATH" "$target" 2>/dev/null; then
          echo "   Restauré tu contenido previo desde el backup: $target quedó como estaba (SIN enlazar a este repo)."
        else
          echo "   ⚠️  No pude restaurar el backup automáticamente — tu contenido sigue intacto en: $BACKUP_PATH"
        fi
      fi
      echo "   La skill '$name' quedó sin enlazar. Revisa permisos de $destino y vuelve a correr ./install.sh --agent $agente."
      exit 1
    fi
    echo "   skill:  $name → enlazada"
  done
}

install_claude() {
  banner "Claude Code" "claude: $CLAUDE_DIR"

  # Skills tuyas con el nombre de las del harness: se frena ANTES de crear o escribir nada.
  revisar_conflictos_skills "$CLAUDE_DIR/skills" claude

  # A diferencia de cursor y antigravity, acá el directorio se CREA: ~/.claude es del
  # harness tanto como de Claude Code, y no hay config ajena que fusionar.
  mkdir -p "$CLAUDE_DIR/skills"

  # 1. Enlazar skills (idempotente, con backup y restauración: ver enlazar_skills)
  enlazar_skills "$CLAUDE_DIR/skills" claude

  # 2. Instalar el CLAUDE.md base solo si no existe (no pisa el tuyo)
  # "Ya existe" no alcanza como guarda: la vez anterior el archivo lo escribió ESTE
  # instalador, así que en la segunda instalación existe siempre. Si el repo se mudó de
  # ruta, dejarlo intacto conserva un import `@/ruta/vieja/AGENTS.md` que ya no resuelve
  # — y un import roto no avisa: falla en silencio y te quedas sin reglas.
  # Por eso se distingue por la FORMA de la primera línea no vacía: si es el import que
  # renderiza este archivo (`@<algo>/AGENTS.md`), el archivo es nuestro y se re-renderiza
  # con backup. Si es cualquier otra cosa, es tuyo y no se toca.
  local es_nuestro=0
  if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
    case "$(primera_linea_util "$CLAUDE_DIR/CLAUDE.md")" in
      '@'*/AGENTS.md) es_nuestro=1 ;;
    esac
  fi

  if [ ! -e "$CLAUDE_DIR/CLAUDE.md" ]; then
    render "$REPO_DIR/adapters/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
    echo "   config: CLAUDE.md base instalado (importa $REPO_DIR/AGENTS.md)"
  elif [ "$es_nuestro" = "1" ]; then
    backup_if_exists "$CLAUDE_DIR/CLAUDE.md"
    render "$REPO_DIR/adapters/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
    echo "   config: CLAUDE.md del harness re-renderizado (ahora importa $REPO_DIR/AGENTS.md)"
  else
    echo "   config: ya tienes ~/.claude/CLAUDE.md — no lo toco."
    echo "           Para que las reglas te lleguen, agrega esta línea al principio de ese archivo:"
    echo "             @$REPO_DIR/AGENTS.md"
  fi

  # Cierre: checklist de verificación REAL — se chequea qué existe, no se asume un orden.
  # (SETUP.md pide empresa/perfil/validación ANTES de este install; si seguiste ese orden,
  #  acá solo deberías ver ✔.)
  local company_count
  company_count="$(find "$REPO_DIR/companies" -maxdepth 1 -name '*.json' ! -name '_template.json' 2>/dev/null | wc -l | tr -d ' ')"

  echo
  echo "✅ Skills enlazadas en $CLAUDE_DIR/skills."
  echo
  echo "🔎 Checklist de verificación (el paso a paso completo está en SETUP.md):"
  if [ "$company_count" -gt 0 ]; then
    echo "   ✔ companies/: $company_count empresa(s) configurada(s) además del template"
  else
    echo "   ▢ falta tu empresa: cp companies/_template.json companies/<tu-empresa>.json y complétalo (SETUP.md paso 2)"
  fi
  if [ -f "$REPO_DIR/profile/profile.json" ]; then
    echo "   ✔ profile/profile.json existe"
  else
    echo "   ▢ falta tu perfil: cp profile/profile.example.json profile/profile.json y complétalo (SETUP.md paso 3)"
  fi
  echo "   ▢ corre ./validate-config.sh para confirmar que nada quedó a medias (si ya lo corriste antes de este install, vale igual: ahora también chequea los enlaces)"
  echo "   ▢ abre Claude Code EN LA RAÍZ de este repo — la primera vez te pedirá aprobar los"
  echo "     servers MCP de .mcp.json (atlassian/notion); la autenticación es OAuth en el navegador"
  echo "   ▢ prueba con demo/ (ver demo/README.md)"
  echo
  echo "ℹ️  Los permisos del harness (deny de transiciones de Jira, ask antes de escribir hacia afuera)"
  echo "   viven en .claude/settings.json y aplican SOLO en sesiones de Claude Code abiertas desde la"
  echo "   raíz de este repo — que es como el método manda trabajar. Si vas a trabajar desde otra"
  echo "   carpeta, fusiónalos a mano en tu ~/.claude/settings.json (el snippet está en SETUP.md)."
}

primera_linea_util() { grep -v '^[[:space:]]*$' "$1" 2>/dev/null | head -1 || true; }

# ── cursor ──────────────────────────────────────────────────────────
install_cursor() {
  banner "Cursor" "cursor: $CURSOR_DIR"

  # A diferencia de claude, acá el directorio NO se crea: si no existe, Cursor no está
  # instalado (o nunca se abrió) y crearlo dejaría una config huérfana que nadie lee.
  [ -d "$CURSOR_DIR" ] || { echo "❌ No existe $CURSOR_DIR — abre Cursor una vez y vuelve a correr esto."; exit 1; }

  render "$REPO_DIR/adapters/cursor/config/hooks.json" "$TMP/hooks.json"
  # Evento por evento: se conservan tus hooks y se reemplazan los del harness, así
  # reinstalar no duplica. Un `*` a secas pisaría el array entero del evento y te
  # borraría los hooks propios de beforeShellExecution.
  #
  # Lo del harness se identifica por el NOMBRE del script, no por el command completo:
  # el command lleva la ruta absoluta del repo, así que si reinstalas desde otra ruta
  # (clonaste de nuevo, renombraste la carpeta, te mudaste de disco) el command viejo
  # sería una clave distinta y sobreviviría — te quedarían hooks apuntando a scripts
  # que ya no existen. El nombre del script no cambia con la ruta.
  merge "$CURSOR_DIR/hooks.json" 'def nombre_de_script: (.command // "") | split("/") | last;
.version = 1
| .hooks = reduce ($new[0].hooks | to_entries[]) as $evento ((.hooks // {});
    .[$evento.key] = ([(.[$evento.key] // [])[] | select(nombre_de_script as $s | $evento.value | all(nombre_de_script != $s))] + $evento.value))' "$TMP/hooks.json"
  echo "   hooks:  beforeShellExecution · beforeMCPExecution · afterFileEdit · preToolUse/postToolUse/postToolUseFailure (Shell: lo que escribió la terminal)"

  merge "$CURSOR_DIR/mcp.json" '.mcpServers = ((.mcpServers // {}) * $new[0].mcpServers)' "$REPO_DIR/adapters/cursor/config/mcp.json"
  echo "   mcp:    servers atlassian y notion registrados"

  # La rule va en el SCOPE DE PROYECTO. Cursor lee `<proyecto>/.cursor/rules/`,
  # NO `~/.cursor/rules/`. Como el repo es el proyecto que se abre, la rule ya viaja
  # versionada; esto solo re-sincroniza si alguien editó adapters/cursor/rules/.
  mkdir -p "$REPO_DIR/.cursor/rules"
  cp "$REPO_DIR/adapters/cursor/rules/qa-harness.mdc" "$REPO_DIR/.cursor/rules/qa-harness.mdc"
  echo "   rules:  qa-harness.mdc en .cursor/rules/ del repo (scope de proyecto)"

  echo
  echo "✅ Instalado."
  echo
  echo "🔎 Pasos que faltan:"
  echo "   ▢ 1. Reinicia Cursor"
  echo "   ▢ 2. Autentica el MCP de Atlassian (OAuth en el navegador)"
  echo "   ▢ 3. Abre Cursor EN LA RAÍZ de este repo"
  echo "   ▢ 4. Verifica que las reglas llegan: escribe PING-HARNESS en un chat nuevo"
  echo "        — debe responder 'PONG <empresa> <backend> <destino>' y nada más"
  echo "   ▢ 5. Verifica el gate: pídele publicar un comentario que contenga"
  echo "        PON-AQUI-EL-ID — debe bloquearlo"
}

# ── antigravity ─────────────────────────────────────────────────────
# Anota en el sidecar el skills/ de este repo y qué skills quedaron copiadas. Si no se puede
# escribir, se avisa y se sigue: la instalación ya quedó hecha, y sin sidecar la próxima
# corrida simplemente reconoce menos cosas como nuestras (que es el default seguro).
recordar_estado_antigravity() { # recordar_estado_antigravity <skills-del-repo> <copiadas-json>
  local path="$1" copiadas="$2" tmp rc=0
  mkdir -p "$(dirname "$STATE_FILE")"
  tmp="$(mktemp)"
  if [ -f "$STATE_FILE" ] && jq empty "$STATE_FILE" > /dev/null 2>&1; then
    jq --arg p "$path" --argjson c "$copiadas" \
      '.antigravity.skillsPath = $p | .antigravity.skillCopies = $c | del(.antigravity.skillLinks)' "$STATE_FILE" > "$tmp" || rc=$?
  else
    jq -n --arg p "$path" --argjson c "$copiadas" \
      '{ antigravity: { skillsPath: $p, skillCopies: $c } }' > "$tmp" || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    rm -f "$tmp"
    echo "   ⚠️  No pude anotar el estado en $STATE_FILE — la próxima instalación va a reconocer menos cosas como nuestras."
    return 0
  fi
  mv "$tmp" "$STATE_FILE"
}

# Retira de skills.json la entrada que registraba nuestro skills/ (la de este repo o la que
# anotó el sidecar). Con las copias en la carpeta global, esa entrada haría que Antigravity
# descubra cada skill dos veces. Las demás entradas son tuyas y no se tocan; si no hay nada
# nuestro, el archivo ni se reescribe.
retirar_entrada_skills_json() { # retirar_entrada_skills_json <skills-previo o "">
  local sj="$CONFIG_DIR/skills.json" previo="$1" nuestras
  [ -f "$sj" ] || return 0
  if ! jq empty "$sj" > /dev/null 2>&1; then
    echo "   ⚠️  $sj no es JSON válido: no lo toco. Si tiene una entrada con $REPO_DIR/skills, quítala a mano."
    return 0
  fi
  local filtro='def nuestra: type == "object" and (.path == $actual or ($previo != "" and .path == $previo));'
  nuestras="$(jq --arg actual "$REPO_DIR/skills" --arg previo "$previo" \
    "$filtro"' [(.entries // [])[] | select(nuestra)] | length' "$sj")"
  [ "$nuestras" -gt 0 ] || return 0
  merge "$sj" "$filtro"' .entries = [(.entries // [])[] | select(nuestra | not)]' "$sj" \
    --arg actual "$REPO_DIR/skills" --arg previo "$previo"
  echo "   skills: retiré de skills.json la entrada del harness (con las copias, las listaría dos veces)"
}

install_antigravity() {
  banner "Antigravity" "gemini: $CONFIG_DIR"

  # Misma guarda que Cursor, y por la misma razón: ~/.gemini es de Antigravity.
  if [ ! -d "$GEMINI_DIR" ]; then
    echo "❌ No existe $GEMINI_DIR — ¿está instalado Antigravity? Ábrelo una vez y vuelve a correr esto."
    exit 1
  fi
  # Los hooks de Antigravity son python3, y la copia de las skills también.
  command -v python3 > /dev/null 2>&1 || { echo "❌ Falta python3: lo necesitan los hooks y la copia de las skills de Antigravity."; exit 1; }
  mkdir -p "$CONFIG_DIR"

  # 1. hooks — se agrega la clave "qa-harness-pro" sin tocar tus otros grupos
  render "$REPO_DIR/adapters/antigravity/config/hooks.json" "$TMP/hooks.json"
  merge "$CONFIG_DIR/hooks.json" '. * $new[0]' "$TMP/hooks.json"
  echo "   hooks:  grupo 'qa-harness-pro' registrado"

  # 2. MCP — se agregan atlassian y notion a tus servers existentes
  merge "$CONFIG_DIR/mcp_config.json" '.mcpServers = ((.mcpServers // {}) * $new[0].mcpServers)' "$REPO_DIR/adapters/antigravity/config/mcp_config.json"
  echo "   mcp:    servers atlassian y notion registrados"

  # 3. skills — una COPIA sincronizada de cada skill en $CONFIG_DIR/skills/<skill>/, carpeta
  # entera (references/ incluida), con una marca .qa-harness-copia.json adentro. La lógica
  # vive en adapters/antigravity/copias_skills.py.
  #
  # Por qué copias: con solo el registro de skills.json el agente CONOCE las skills pero va a
  # LEER el SKILL.md a las rutas estándar (<workspace>/.agents/skills/, la legacy .agent/skills/
  # y la global ~/.gemini/config/skills/), y al no encontrarlo terminaba buscando con `find` por
  # todo el HOME. Con symlinks en la global las encuentra, pero Antigravity resuelve el symlink
  # y aplica su política de workspace a la ruta REAL, que queda fuera del workspace abierto:
  # "Permission denied". Un archivo real en la carpeta global sí se lee (pruebas en vivo del
  # 2026-09-28). El costo de copiar es que la copia puede quedar vieja: validate-config.sh
  # compara el contenido con el repo y avisa.
  #
  # La carpeta es COMPARTIDA con otras herramientas: solo se reemplaza lo que lleva nuestra
  # marca o un symlink de la instalación anterior a un clon del harness. Lo ajeno se avisa y se
  # saltea. El sidecar ($STATE_FILE) guarda el skills/ que instaló la última vez, para reconocer
  # lo de un clon mudado y retirar la entrada vieja de skills.json.
  local skills_path_previo=""
  if [ -f "$STATE_FILE" ]; then
    skills_path_previo="$(jq -r '.antigravity.skillsPath // empty' "$STATE_FILE" 2>/dev/null || true)"
  fi
  if ! python3 "$REPO_DIR/adapters/antigravity/copias_skills.py" sincronizar \
      "$REPO_DIR/skills" "$CONFIG_DIR/skills" "$skills_path_previo" "$TMP/copias.json"; then
    echo "❌ No pude copiar las skills en $CONFIG_DIR/skills. Revisa permisos y vuelve a correr ./install.sh --agent antigravity."
    exit 1
  fi
  SALTEADAS="$(jq -r '.salteadas' "$TMP/copias.json")"
  retirar_entrada_skills_json "$skills_path_previo"
  recordar_estado_antigravity "$REPO_DIR/skills" "$(jq -c '.copiadas' "$TMP/copias.json")"

  # 4. rule — igual que en Cursor, va en el SCOPE DE PROYECTO. Antigravity lee las reglas del
  # workspace desde `<workspace>/.agents/rules/`, NO desde ~/.gemini. Como el repo es el
  # workspace que se abre, la rule ya viaja versionada; esto solo re-sincroniza si alguien
  # editó adapters/antigravity/rules/. La global `~/.gemini/GEMINI.md` NO se toca: es un
  # archivo personal del usuario y pisarlo no tiene vuelta atrás.
  mkdir -p "$REPO_DIR/.agents/rules"
  cp "$REPO_DIR/adapters/antigravity/rules/qa-harness.md" "$REPO_DIR/.agents/rules/qa-harness.md"
  echo "   rules:  qa-harness.md en .agents/rules/ del repo (scope de proyecto)"

  echo
  if [ "$SALTEADAS" -gt 0 ]; then
    echo "⚠️  Instalado, pero $SALTEADAS skill(s) quedaron SIN copiar: en $CONFIG_DIR/skills ya había algo"
    echo "    ajeno con ese nombre (ver avisos de arriba). Antigravity va a leer ESO, no el método de este repo."
  else
    echo "✅ Instalado. Las skills son copias de las de este repo: si editas una, vuelve a correr"
    echo "   ./install.sh --agent antigravity (./validate-config.sh avisa si alguna quedó desactualizada)."
  fi
  echo
  echo "🔎 Pasos que faltan (ver adapters/antigravity/README.md):"
  echo "   ▢ 1. Reinicia Antigravity para que tome la config"
  echo "   ▢ 2. Comprueba en la UI que la rule .agents/rules/qa-harness.md quede activa"
  echo "        (modo 'Always on'). El harness no puede fijarlo desde el archivo."
  echo "   ▢ 3. Autentica el MCP de Atlassian (OAuth en el navegador)"
  echo "   ▢ 4. IMPORTANTE — descubre los nombres reales de las tools:"
  echo "        corre una acción que toque Jira y después mira"
  echo "        ~/.gemini/qa-harness-unknown-tools.log"
  echo "        Si aparece algo ahí, agrega esa tool al catálogo en core/gates/catalogo.py"
  echo "        — es el único lugar donde se tocan: los tres runtimes lo comparten."
  echo "   ▢ 5. Verifica el gate: pídele que publique algo con un placeholder"
  echo "        sin resolver — debe bloquearlo"
  echo "   ▢ 6. Verifica que LEE las skills desde $CONFIG_DIR/skills (sin buscar en el disco):"
  echo "        la prueba en vivo de adapters/antigravity/README.md, en un chat nuevo FUERA del repo"
}

# ── codex ───────────────────────────────────────────────────────────
install_codex() {
  banner "Codex CLI" "codex: $CODEX_HOME · skills: $CODEX_SKILLS_DIR"

  # Misma guarda que Cursor y Antigravity: si CODEX_HOME no existe, Codex nunca corrió acá y
  # crearlo dejaría una config huérfana que nadie lee.
  [ -d "$CODEX_HOME" ] || { echo "❌ No existe $CODEX_HOME — ¿está instalado Codex? Ábrelo una vez (codex) y vuelve a correr esto."; exit 1; }
  # El bloque de config.toml se valida parseándolo antes de escribirlo: un TOML roto deja a
  # Codex sin arrancar. tomllib viene con python3 desde la 3.11.
  python3 -c 'import tomllib' > /dev/null 2>&1 || {
    echo "❌ Falta python3 ≥ 3.11 (tomllib): lo necesita la instalación de codex para tocar tu config.toml sin romperlo."
    exit 1
  }
  # Skills tuyas en ~/.agents/skills con el nombre de las del harness: se frena ANTES de tocar
  # hooks.json, config.toml o AGENTS.md, para no dejarte una instalación a medias.
  revisar_conflictos_skills "$CODEX_SKILLS_DIR" codex

  # 1. hooks — ~/.codex/hooks.json, a nivel USUARIO: el .codex/ de un proyecto solo se lee si
  # ese proyecto es "trusted", y no queremos que el gate dependa de eso.
  #
  # Identidad: el sufijo `adapters/codex/hooks/<script>` del command, no el command entero
  # (lleva la ruta absoluta del repo y cambia si lo mudas) ni el nombre pelado del script
  # (cursor y claude usan los mismos nombres). Se sacan esos hooks de CUALQUIER evento — si
  # una versión vieja tenía uno en otro evento, no sobrevive — y los grupos nuevos se agregan
  # AL FINAL de cada evento. El orden importa: Codex guarda la confianza de cada hook en
  # config.toml por <evento>:<índice-de-grupo>:<índice-de-hook>, así que agregar al final no
  # corre de lugar los hooks que ya aprobaste (Orca, gentle-ai, los tuyos).
  render "$REPO_DIR/adapters/codex/config/hooks.json" "$TMP/codex-hooks.json"
  merge "$CODEX_HOME/hooks.json" 'def identidad: if type == "object" then ((.command // "") | tostring | split("/") | .[-4:] | join("/")) else "" end;
def es_nuestro: identidad as $i | $i | startswith("adapters/codex/hooks/");
.hooks = ((.hooks // {})
  | map_values(if type == "array" then [ .[]
      | if (type == "object") and any((.hooks // [])[]; es_nuestro)
        then (.hooks |= map(select(es_nuestro | not))) | select((.hooks | length) > 0)
        else . end ] else . end)
  | reduce ($new[0].hooks | to_entries[]) as $evento (.; .[$evento.key] = ((.[$evento.key] // []) + $evento.value)))' "$TMP/codex-hooks.json"
  echo "   hooks:  PreToolUse (Bash · mcp__.* · Bash: foto) · PostToolUse (apply_patch|Edit|Write · Bash: lo que escribió el shell)"

  # 2. config.toml — bloque gestionado entre marcas (ver adapters/codex/bloque_gestionado.py):
  # el server atlassian, la transición fuera de la lista de tools y aprobación obligatoria
  # por cada escritura. Jamás se reescribe tu TOML entero: se agrega o se reemplaza el bloque,
  # y si ya definiste tu propio [mcp_servers.atlassian] no se toca nada (duplicar una tabla
  # rompe el TOML y Codex no arranca).
  local salida rc=0 pendiente=0
  salida="$(python3 "$REPO_DIR/adapters/codex/bloque_gestionado.py" "$CODEX_HOME/config.toml" \
    "$REPO_DIR/adapters/codex/config/mcp.toml" toml "$STAMP")" || rc=$?
  case "$rc" in
    0) echo "   mcp:    server atlassian con aprobación por tool en config.toml (bloque gestionado: $salida)" ;;
    3)
      pendiente=1
      echo "   ⚠️  config.toml: $salida"
      echo "       Agrega a mano, dentro de tu propio server, lo que trae adapters/codex/config/mcp.toml:"
      echo "       disabled_tools = [\"transitionJiraIssue\"] y approval_mode = \"prompt\" en cada tool de escritura." ;;
    *) echo "❌ config.toml: $salida"; exit 1 ;;
  esac

  # 3. AGENTS.md global — Codex no tiene imports como el @ruta de Claude Code, y tu
  # ~/.codex/AGENTS.md es tuyo (en macOS, agents.md es el MISMO archivo). Por eso no se
  # instala uno nuestro ni se pega el método entero: se agrega un bloque gestionado corto que
  # apunta al AGENTS.md de este repo. En la raíz del repo Codex ya lo lee como instrucciones del
  # proyecto; el bloque es la red para cuando trabajas desde otra carpeta.
  render "$REPO_DIR/adapters/codex/AGENTS.md" "$TMP/codex-AGENTS.md"
  rc=0
  salida="$(python3 "$REPO_DIR/adapters/codex/bloque_gestionado.py" "$CODEX_HOME/AGENTS.md" \
    "$TMP/codex-AGENTS.md" md "$STAMP")" || rc=$?
  [ "$rc" -eq 0 ] || { echo "❌ AGENTS.md: $salida"; exit 1; }
  echo "   rules:  bloque gestionado en AGENTS.md de $CODEX_HOME ($salida), apunta a $REPO_DIR/AGENTS.md"

  # 4. skills — Codex las lee nativas desde ~/.agents/skills (una carpeta por skill con su
  # SKILL.md). Symlinks como en Claude Code: references/ viaja con cada skill.
  mkdir -p "$CODEX_SKILLS_DIR"
  enlazar_skills "$CODEX_SKILLS_DIR" codex

  echo
  if [ "$pendiente" = "1" ]; then
    echo "⚠️  Instalado a medias: los hooks, las reglas y las skills quedaron, la segunda capa del MCP no."
  else
    echo "✅ Instalado."
  fi
  echo
  echo "🔎 Pasos que faltan (ver adapters/codex/README.md):"
  echo "   ▢ 1. OBLIGATORIO — abre Codex y corre /hooks: revisa y confía en los 5 hooks del harness."
  echo "        Codex no corre un hook que no aprobaste, y NO avisa: sin este paso no hay gate."
  echo "        Si reinstalas desde otra ruta, el command cambia y te lo vuelve a pedir; si"
  echo "        actualizaste el harness, /hooks te muestra solo los hooks nuevos para aprobar."
  echo "   ▢ 2. Autentica el MCP de Atlassian: codex mcp login atlassian"
  echo "   ▢ 3. Abre Codex EN LA RAÍZ de este repo y escribe PING-HARNESS"
  echo "        — debe responder 'PONG <empresa> <backend> <destino>' y nada más"
  echo "   ▢ 4. Verifica los tres gates con la prueba en vivo de adapters/codex/README.md"
  [ "$pendiente" = "0" ] || exit 1
}

# ── Despacho ────────────────────────────────────────────────────────
if [ "$AGENT" = "all" ]; then
  # Cada agente se instala en su PROPIO proceso: los destinos son independientes, así que
  # que falte ~/.cursor no es razón para dejar a Claude sin skills. Se corren todos, se
  # dice cuál falló y el exit queda ≠ 0 — nada se abandona en silencio.
  # --reemplazar-skills viaja a cada proceso hijo: si no, `--agent all --reemplazar-skills` se
  # frenaría igual en claude y codex, como si no lo hubieras pedido.
  OPCIONES=()
  [ "$REEMPLAZAR_SKILLS" = "1" ] && OPCIONES+=(--reemplazar-skills)
  FALLIDOS=""
  for agente in $AGENTES; do
    bash "${BASH_SOURCE[0]}" --agent "$agente" ${OPCIONES[@]+"${OPCIONES[@]}"} || FALLIDOS="$FALLIDOS $agente"
    echo
  done
  if [ -n "$FALLIDOS" ]; then
    echo "❌ Falló la instalación de:$FALLIDOS — los demás sí quedaron instalados."
    echo "   Revisa el mensaje de cada uno más arriba y vuelve a correr solo el que falló."
    exit 1
  fi
  echo "✅ Los cuatro agentes quedaron instalados."
  exit 0
fi

install_"$AGENT"
