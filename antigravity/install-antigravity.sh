#!/usr/bin/env bash
# QA Harness Pro — instalación para Antigravity (Gemini).
# Fusiona la config del harness en ~/.gemini/config/ SIN pisar lo que ya tengas:
# hooks y mcpServers se agregan a los existentes; de todo lo que toca hace backup.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEMINI_DIR="${GEMINI_DIR:-$HOME/.gemini}"
CONFIG_DIR="$GEMINI_DIR/config"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "🧰 QA Harness Pro — install (Antigravity)"
echo "   repo:   $REPO_DIR"
echo "   gemini: $CONFIG_DIR"
echo

if [ ! -d "$GEMINI_DIR" ]; then
  echo "❌ No existe $GEMINI_DIR — ¿está instalado Antigravity? Abrilo una vez y volvé a correr esto."
  exit 1
fi
mkdir -p "$CONFIG_DIR"

merge() { # merge <archivo-destino> <expresión jq> <archivo-fuente>
  local dest="$1" expr="$2" src="$3" tmp
  tmp="$(mktemp)"
  if [ -f "$dest" ]; then
    cp "$dest" "$dest.bak-$STAMP"
    echo "   backup: $(basename "$dest") → $(basename "$dest").bak-$STAMP"
  else
    echo '{}' > "$dest"
  fi
  if ! jq --slurpfile new "$src" "$expr" "$dest" > "$tmp"; then
    echo "❌ Falló la fusión de $(basename "$dest") — tu archivo quedó intacto."
    rm -f "$tmp"; exit 1
  fi
  mv "$tmp" "$dest"
}

# Las rutas se resuelven acá: los JSON del repo llevan el placeholder {{HARNESS}}.
render() { sed "s|{{HARNESS}}|$REPO_DIR|g" "$1" > "$2"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. hooks — se agrega la clave "qa-harness-pro" sin tocar tus otros grupos
render "$REPO_DIR/antigravity/config/hooks.json" "$TMP/hooks.json"
merge "$CONFIG_DIR/hooks.json" '. * $new[0]' "$TMP/hooks.json"
echo "   hooks:  grupo 'qa-harness-pro' registrado"

# 2. MCP — se agregan atlassian y notion a tus servers existentes
merge "$CONFIG_DIR/mcp_config.json" '.mcpServers = ((.mcpServers // {}) * $new[0].mcpServers)' "$REPO_DIR/antigravity/config/mcp_config.json"
echo "   mcp:    servers atlassian y notion registrados"

# 3. skills — se apunta al MISMO skills/ que usa Claude Code (fuente única)
render "$REPO_DIR/antigravity/config/skills.json" "$TMP/skills.json"
merge "$CONFIG_DIR/skills.json" '.entries = ((.entries // []) + $new[0].entries | unique_by(.path))' "$TMP/skills.json"
echo "   skills: $REPO_DIR/skills registrado como fuente"

echo
echo "✅ Instalado. Las skills son las MISMAS que usa Claude Code — un solo lugar que mantener."
echo
echo "🔎 Pasos que faltan (ver antigravity/README.md):"
echo "   ▢ 1. Reiniciá Antigravity para que tome la config"
echo "   ▢ 2. Autenticá el MCP de Atlassian (OAuth en el navegador)"
echo "   ▢ 3. IMPORTANTE — descubrí los nombres reales de las tools:"
echo "        corré una acción que toque Jira y después mirá"
echo "        ~/.gemini/qa-harness-unknown-tools.log"
echo "        Si aparece algo ahí, ajustá los patrones de"
echo "        antigravity/hooks/validate-external-write.py"
echo "   ▢ 4. Verificá el gate: pedile que publique algo con un placeholder"
echo "        sin resolver — debe bloquearlo"
