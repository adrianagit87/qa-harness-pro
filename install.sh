#!/usr/bin/env bash
# QA Harness Pro — setup reproducible. Un solo instalador para los tres agentes:
#
#   ./install.sh --agent claude       enlaza las skills y el CLAUDE.md base en ~/.claude
#   ./install.sh --agent cursor       fusiona hooks y MCP en ~/.cursor
#   ./install.sh --agent antigravity  fusiona hooks, MCP y skills en ~/.gemini/config, y la
#                                     rule en .agents/rules/ de este repo
#   ./install.sh --agent all          los tres
#
# No pisa nada tuyo sin avisar: hace backup con timestamp de lo que fuera a sobrescribir.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
CURSOR_DIR="${CURSOR_DIR:-$HOME/.cursor}"
GEMINI_DIR="${GEMINI_DIR:-$HOME/.gemini}"
CONFIG_DIR="$GEMINI_DIR/config"
# Sidecar PROPIO del harness: acá anotamos qué registramos en la config ajena, para poder
# retirarlo después sin adivinar. Vive al lado de qa-harness-unknown-tools.log, que ya
# estableció ~/.gemini como un lugar donde el harness escribe lo suyo.
STATE_FILE="${QA_HARNESS_STATE:-$GEMINI_DIR/qa-harness-state.json}"
STAMP="$(date +%Y%m%d-%H%M%S)"

AGENTES="claude cursor antigravity"

usage() {
  cat <<EOF
QA Harness Pro — install

  uso:  ./install.sh --agent <claude|cursor|antigravity|all>

    claude        skills enlazadas + CLAUDE.md base en $CLAUDE_DIR
    cursor        hooks + MCP en $CURSOR_DIR, y la rule en .cursor/rules/ de este repo
    antigravity   hooks + MCP + skills en $CONFIG_DIR, y la rule en .agents/rules/ de este repo
    all           los tres, en ese orden

    --help        muestra esta ayuda

  --agent es obligatorio y no tiene default: sin él no se instala nada.
  Valores válidos: claude, cursor, antigravity, all.
EOF
}

# ── Argumentos ──────────────────────────────────────────────────────
# Sin --agent NO se instala nada. Elegir claude por default sería un éxito ambiguo:
# quien viene de Cursor creería que instaló y se iría sin reglas, con el instalador
# diciéndole "✅". Un fallo ruidoso es mejor.
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

if [ -z "$AGENT" ]; then
  echo "❌ Falta --agent: no adivino para qué herramienta quieres instalar."; echo; usage; exit 1
fi

case " $AGENTES all " in
  *" $AGENT "*) ;;
  *) echo "❌ Agente desconocido: '$AGENT'."; echo; usage; exit 1 ;;
esac

# jq solo hace falta para fusionar JSON ajeno, o sea para cursor y antigravity. La
# instalación de claude no lo toca, así que exigirlo ahí sería pedir una dependencia
# que no se usa.
case "$AGENT" in
  cursor|antigravity|all)
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
BACKUP_PATH=""  # backup_if_exists deja aquí la ruta del último backup (o vacío)

# Backup con `mv` y salteando symlinks: acá el destino se REEMPLAZA por un enlace, así
# que el contenido previo tiene que salir del camino (no alcanza con copiarlo), y un
# symlink previo no es contenido de nadie: se pisa sin respaldar.
backup_if_exists() {
  local target="$1"
  BACKUP_PATH=""
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mv "$target" "$target.bak-$STAMP"
    BACKUP_PATH="$target.bak-$STAMP"
    echo "   backup: $target → $(basename "$target").bak-$STAMP"
  fi
}

install_claude() {
  banner "Claude Code" "claude: $CLAUDE_DIR"

  # A diferencia de cursor y antigravity, acá el directorio se CREA: ~/.claude es del
  # harness tanto como de Claude Code, y no hay config ajena que fusionar.
  mkdir -p "$CLAUDE_DIR/skills"

  # 1. Enlazar skills (idempotente)
  # Si ya existe un directorio o archivo REAL con el mismo nombre, primero se respalda:
  # sin ese backup, `ln -sfn` crearía el symlink ADENTRO del directorio existente y
  # reportaría "enlazada" sin que fuera verdad.
  # Y si `ln` falla DESPUÉS del backup, se restaura el backup: jamás te dejamos sin
  # contenido y sin enlace a la vez.
  if [ -d "$REPO_DIR/skills" ]; then
    for skill in "$REPO_DIR"/skills/*/; do
      [ -d "$skill" ] || continue
      name="$(basename "$skill")"
      target="$CLAUDE_DIR/skills/$name"
      backup_if_exists "$target"
      if ! ln -sfn "${skill%/}" "$target"; then
        echo "❌ No pude crear el enlace de '$name' en $target."
        if [ -n "$BACKUP_PATH" ]; then
          if mv "$BACKUP_PATH" "$target" 2>/dev/null; then
            echo "   Restauré tu contenido previo desde el backup: $target quedó como estaba (SIN enlazar a este repo)."
          else
            echo "   ⚠️  No pude restaurar el backup automáticamente — tu contenido sigue intacto en: $BACKUP_PATH"
          fi
        fi
        echo "   La skill '$name' quedó sin enlazar. Revisa permisos de $CLAUDE_DIR/skills y vuelve a correr ./install.sh --agent claude."
        exit 1
      fi
      echo "   skill:  $name → enlazada"
    done
  fi

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
  echo "   hooks:  beforeShellExecution · beforeMCPExecution · afterFileEdit"

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
# Anota en el sidecar el path de skills que acabamos de registrar. Si no se puede
# escribir, se avisa y se sigue: la instalación ya quedó hecha, y sin sidecar la próxima
# corrida simplemente no borra nada (que es el default seguro).
recordar_skills_path() { # recordar_skills_path <path-registrado>
  local tmp rc=0
  mkdir -p "$(dirname "$STATE_FILE")"
  tmp="$(mktemp)"
  if [ -f "$STATE_FILE" ] && jq empty "$STATE_FILE" > /dev/null 2>&1; then
    jq --arg p "$1" '.antigravity.skillsPath = $p' "$STATE_FILE" > "$tmp" || rc=$?
  else
    jq -n --arg p "$1" '{ antigravity: { skillsPath: $p } }' > "$tmp" || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    rm -f "$tmp"
    echo "   ⚠️  No pude anotar la ruta de skills en $STATE_FILE — la próxima instalación no va a poder retirar esta entrada sola."
    return 0
  fi
  mv "$tmp" "$STATE_FILE"
}

install_antigravity() {
  banner "Antigravity" "gemini: $CONFIG_DIR"

  # Misma guarda que Cursor, y por la misma razón: ~/.gemini es de Antigravity.
  if [ ! -d "$GEMINI_DIR" ]; then
    echo "❌ No existe $GEMINI_DIR — ¿está instalado Antigravity? Ábrelo una vez y vuelve a correr esto."
    exit 1
  fi
  mkdir -p "$CONFIG_DIR"

  # 1. hooks — se agrega la clave "qa-harness-pro" sin tocar tus otros grupos
  render "$REPO_DIR/adapters/antigravity/config/hooks.json" "$TMP/hooks.json"
  merge "$CONFIG_DIR/hooks.json" '. * $new[0]' "$TMP/hooks.json"
  echo "   hooks:  grupo 'qa-harness-pro' registrado"

  # 2. MCP — se agregan atlassian y notion a tus servers existentes
  merge "$CONFIG_DIR/mcp_config.json" '.mcpServers = ((.mcpServers // {}) * $new[0].mcpServers)' "$REPO_DIR/adapters/antigravity/config/mcp_config.json"
  echo "   mcp:    servers atlassian y notion registrados"

  # 3. skills — se apunta al MISMO skills/ que usa Claude Code (fuente única)
  render "$REPO_DIR/adapters/antigravity/config/skills.json" "$TMP/skills.json"
  # El schema de skills.json es de Antigravity, no nuestro: una entrada es {path} y nada
  # más. Marcar las nuestras con un campo inventado metería datos ajenos al contrato en la
  # config del usuario, y si Antigravity validara estricto podría rechazar el archivo
  # entero — le romperíamos la config para arreglarle un bug que quizá nunca tuvo.
  #
  # Por eso la memoria vive en un sidecar NUESTRO ($STATE_FILE): ahí queda anotado qué path
  # registramos la última vez, y en la siguiente instalación se retira EXACTAMENTE ese.
  # Desduplicar por `.path` contra la entrada nueva no alcanza — el path es la ruta absoluta
  # del repo, así que reinstalar desde otra ruta dejaba las dos entradas, una apuntando a un
  # directorio que ya no existe.
  #
  # Si el sidecar no está o no se puede leer (primera instalación, o alguien que instaló
  # antes de este cambio), no se borra nada: solo se agrega la entrada nueva. Jamás se borra
  # una entrada que no podamos probar que es nuestra.
  local skills_path_previo=""
  if [ -f "$STATE_FILE" ]; then
    skills_path_previo="$(jq -r '.antigravity.skillsPath // empty' "$STATE_FILE" 2>/dev/null || true)"
  fi
  merge "$CONFIG_DIR/skills.json" '.entries = ([(.entries // [])[]
    | select($previo == "" or .path != $previo)
    | select(.path as $p | $new[0].entries | all(.path != $p))] + $new[0].entries)' \
    "$TMP/skills.json" --arg previo "$skills_path_previo"
  echo "   skills: $REPO_DIR/skills registrado como fuente"
  recordar_skills_path "$REPO_DIR/skills"

  # 4. rule — igual que en Cursor, va en el SCOPE DE PROYECTO. Antigravity lee las reglas del
  # workspace desde `<workspace>/.agents/rules/`, NO desde ~/.gemini. Como el repo es el
  # workspace que se abre, la rule ya viaja versionada; esto solo re-sincroniza si alguien
  # editó adapters/antigravity/rules/. La global `~/.gemini/GEMINI.md` NO se toca: es un
  # archivo personal del usuario y pisarlo no tiene vuelta atrás.
  mkdir -p "$REPO_DIR/.agents/rules"
  cp "$REPO_DIR/adapters/antigravity/rules/qa-harness.md" "$REPO_DIR/.agents/rules/qa-harness.md"
  echo "   rules:  qa-harness.md en .agents/rules/ del repo (scope de proyecto)"

  echo
  echo "✅ Instalado. Las skills son las MISMAS que usa Claude Code — un solo lugar que mantener."
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
}

# ── Despacho ────────────────────────────────────────────────────────
if [ "$AGENT" = "all" ]; then
  # Cada agente se instala en su PROPIO proceso: los destinos son independientes, así que
  # que falte ~/.cursor no es razón para dejar a Claude sin skills. Se corren los tres, se
  # dice cuál falló y el exit queda ≠ 0 — nada se abandona en silencio.
  FALLIDOS=""
  for agente in $AGENTES; do
    bash "${BASH_SOURCE[0]}" --agent "$agente" || FALLIDOS="$FALLIDOS $agente"
    echo
  done
  if [ -n "$FALLIDOS" ]; then
    echo "❌ Falló la instalación de:$FALLIDOS — los demás sí quedaron instalados."
    echo "   Revisa el mensaje de cada uno más arriba y vuelve a correr solo el que falló."
    exit 1
  fi
  echo "✅ Los tres agentes quedaron instalados."
  exit 0
fi

install_"$AGENT"
