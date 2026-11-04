#!/usr/bin/env bash
# Lanza Playwright MCP con la configuración del harness (lo usa .mcp.json).
#
#   --isolated        perfil en memoria: ni tus sesiones ni tus cookies reales.
#   --output-dir      capturas sin nombre explícito van a ejecuciones/.playwright-mcp
#   --block-service-workers  un service worker podría pedir recursos sin pasar por el gate.
#   --secrets         SOLO si existe profile/browser-secrets.env: Playwright MCP no
#                     arranca si el archivo no existe (verificado con 0.0.84).
#
# La versión va fija: una versión nueva puede renombrar tools (pasó con
# browser_run_code -> browser_run_code_unsafe) y el gate dejaría de verlas.
# Para subirla: cambia la versión, corre `npx @playwright/mcp@<v> --help`, revisa
# los nombres de tools contra core/gates/catalogo.py y corre la suite.
set -euo pipefail

VERSION="0.0.84"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETOS="$RAIZ/profile/browser-secrets.env"

args=(--isolated --block-service-workers --output-dir "$RAIZ/ejecuciones/.playwright-mcp")
if [ -f "$SECRETOS" ]; then
  args+=(--secrets "$SECRETOS")
fi

exec npx -y "@playwright/mcp@$VERSION" "${args[@]}" "$@"
