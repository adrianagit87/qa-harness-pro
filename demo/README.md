# Demo — tu primer análisis en 2 minutos

Esta demo funciona **sin conectar nada**: no necesitas Jira ni Confluence/Notion todavía. Sirve
para ver el método en acción antes de configurar tus herramientas.

## Cómo correrla

1. Abre Claude Code en la raíz de este repo. (La primera vez te pedirá aprobar los servers MCP
   de `.mcp.json` — acepta; para esta demo no hace falta autenticar nada todavía.)
2. Escribe:

   ```
   Analiza el ticket de demo/ticket-ejemplo.md
   ```

3. Observa lo que hace el agente.

## Qué deberías ver

**Fase 1 — el gate.** El ticket de demo está incompleto *a propósito*. El agente debería:

- Darle ⚠️ **APROBADA CON OBSERVACIONES** (tiene título, descripción, criterios y DoD — pero con huecos).
- Detectar que "el formulario debe validar los campos" **no es un criterio medible**.
- Detectar que "la política estándar de contraseñas" **no está definida** en el ticket.
- Convertir esos huecos en **preguntas concretas para el PO/Dev** (¿qué campos y con qué reglas? ¿cuál es la política de contraseñas? ¿qué pasa si el email ya está registrado?).
- Tomar los **comentarios del dev como instrucciones autoritativas** (la expiración de 24h y el rate limit del reenvío deben aparecer en los casos).

**Fase 2 — los casos.** Después del gate, el agente genera la tabla de casos (~10–25) con
escenarios positivos, negativos, edge (expiración del link, rate limit, email duplicado),
integración y seguridad — priorizados 🔴/🟡/🟢 — y cierra con la matriz de riesgos.

**La regla de oro en acción.** Como no hay Jira ni doc conectados, el agente NO intenta publicar
nada: te muestra el resultado en el chat. Cuando conectes tus herramientas (ver `SETUP.md`), este
mismo flujo lee el ticket real y te muestra el **borrador** de la doc antes de crear nada.

## Siguiente paso

Cuando esto te haga clic: configura tu empresa real (`SETUP.md`) y corre `Analiza` con una URL de
tu Jira. Mismo método, tus tickets.
