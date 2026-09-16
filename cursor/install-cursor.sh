#!/usr/bin/env bash
# QA Harness Pro — instalación para Cursor.
# Fusiona hooks y MCP en ~/.cursor/ sin pisar lo que ya tengas (backup con timestamp).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURSOR_DIR="${CURSOR_DIR:-$HOME/.cursor}"
STAMP="$(date +%Y%m%d-%H%M%S)"

echo "🧰 QA Harness Pro — install (Cursor)"
echo "   repo:   $REPO_DIR"
echo "   cursor: $CURSOR_DIR"
echo

[ -d "$CURSOR_DIR" ] || { echo "❌ No existe $CURSOR_DIR — abrí Cursor una vez y volvé a correr esto."; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
render() { sed "s|{{HARNESS}}|$REPO_DIR|g" "$1" > "$2"; }

merge() { # merge <destino> <expr jq> <fuente>
  local dest="$1" expr="$2" src="$3" tmp
  tmp="$(mktemp)"
  if [ -f "$dest" ]; then
    cp "$dest" "$dest.bak-$STAMP"
    echo "   backup: $(basename "$dest") → $(basename "$dest").bak-$STAMP"
  else
    echo '{}' > "$dest"
  fi
  if ! jq --slurpfile new "$src" "$expr" "$dest" > "$tmp"; then
    echo "❌ Falló la fusión de $(basename "$dest") — tu archivo quedó intacto."; rm -f "$tmp"; exit 1
  fi
  mv "$tmp" "$dest"
}

render "$REPO_DIR/cursor/config/hooks.json" "$TMP/hooks.json"
merge "$CURSOR_DIR/hooks.json" '.version = 1 | .hooks = ((.hooks // {}) * $new[0].hooks)' "$TMP/hooks.json"
echo "   hooks:  beforeShellExecution · beforeMCPExecution · afterFileEdit"

merge "$CURSOR_DIR/mcp.json" '.mcpServers = ((.mcpServers // {}) * $new[0].mcpServers)' "$REPO_DIR/cursor/config/mcp.json"
echo "   mcp:    servers atlassian y notion registrados"

# La rule va en el SCOPE DE PROYECTO. Cursor lee `<proyecto>/.cursor/rules/`,
# NO `~/.cursor/rules/`. Como el repo es el proyecto que se abre, la rule ya viaja
# versionada; esto solo re-sincroniza si alguien edito cursor/rules/.
mkdir -p "$REPO_DIR/.cursor/rules"
cp "$REPO_DIR/cursor/rules/qa-harness.mdc" "$REPO_DIR/.cursor/rules/qa-harness.mdc"
echo "   rules:  qa-harness.mdc en .cursor/rules/ del repo (scope de proyecto)"

echo
echo "✅ Instalado."
echo
echo "🔎 Pasos que faltan:"
echo "   ▢ 1. Reiniciá Cursor"
echo "   ▢ 2. Autenticá el MCP de Atlassian (OAuth en el navegador)"
echo "   ▢ 3. Abrí Cursor EN LA RAÍZ de este repo"
echo "   ▢ 4. Verificá que las reglas llegan: escribí PING-HARNESS en un chat nuevo"
echo "        — debe responder 'PONG <empresa> <backend> <proyecto>' y nada más"
echo "   ▢ 5. Verificá el gate: pedile publicar un comentario que contenga"
echo "        PON-AQUI-EL-ID — debe bloquearlo"
