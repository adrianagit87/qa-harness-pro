#!/usr/bin/env bash
# QA Harness Pro — setup reproducible.
# Enlaza las skills a ~/.claude, instala la config base si no existe, y te guía con el resto.
# No pisa nada tuyo sin avisar: hace backup con timestamp de lo que fuera a sobrescribir.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "🧰 QA Harness Pro — install"
echo "   repo:   $REPO_DIR"
echo "   claude: $CLAUDE_DIR"
echo

mkdir -p "$CLAUDE_DIR/skills"

BACKUP_PATH=""  # backup_if_exists deja aquí la ruta del último backup (o vacío)

backup_if_exists() {
  local target="$1"
  BACKUP_PATH=""
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mv "$target" "$target.bak-$STAMP"
    BACKUP_PATH="$target.bak-$STAMP"
    echo "   backup: $target → $(basename "$target").bak-$STAMP"
  fi
}

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
      echo "   La skill '$name' quedó sin enlazar. Revisa permisos de $CLAUDE_DIR/skills y vuelve a correr ./install.sh."
      exit 1
    fi
    echo "   skill:  $name → enlazada"
  done
fi

# 2. Copiar CLAUDE.md base solo si no existe (no pisa el tuyo)
if [ ! -e "$CLAUDE_DIR/CLAUDE.md" ]; then
  cp "$REPO_DIR/claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  echo "   config: CLAUDE.md base copiado"
else
  echo "   config: ya tienes ~/.claude/CLAUDE.md — no lo toco (revisa claude/CLAUDE.md a mano)"
fi

# Cierre: checklist de verificación REAL — se chequea qué existe, no se asume un orden.
# (SETUP.md pide empresa/perfil/validación ANTES de este install; si seguiste ese orden,
#  acá solo deberías ver ✔.)
COMPANY_COUNT="$(find "$REPO_DIR/companies" -maxdepth 1 -name '*.json' ! -name '_template.json' 2>/dev/null | wc -l | tr -d ' ')"

echo
echo "✅ Skills enlazadas en $CLAUDE_DIR/skills."
echo
echo "🔎 Checklist de verificación (el paso a paso completo está en SETUP.md):"
if [ "$COMPANY_COUNT" -gt 0 ]; then
  echo "   ✔ companies/: $COMPANY_COUNT empresa(s) configurada(s) además del template"
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
