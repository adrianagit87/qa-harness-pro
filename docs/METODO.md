# El método — cómo trabaja este harness

Este documento explica el flujo completo de QA que implementan las skills, y cómo el recurso
entero ES un ejemplo del modelo loop/goal/harness que enseña.

---

## El flujo de trabajo

```
                    ┌─────────────────────┐
   requerimiento →  │ qa-generacion-casos │  (sin ticket — QA entra ANTES de la historia)
                    └─────────────────────┘
                              │ cuando existe el ticket…
                              ▼
   ticket Jira →    ┌─────────────────────┐
                    │  qa-analisis-ticket │  FASE 1: gate de calidad (✅/⚠️/❌)
                    │     (el corazón)    │  FASE 2: casos de prueba + matriz de riesgos
                    └─────────────────────┘  + doc en el backend configurado (si amerita)
                              │ "¿evalúo automatización?" → Sí
                              ▼
                    ┌─────────────────────┐
                    │  qa-automatizacion  │  FASE 3 (opcional): veredicto + ROI + código
                    └─────────────────────┘  integrado a TU suite
                              │ se ejecutan las pruebas…
                              ▼
                    ┌─────────────────────┐
   "Cierre <AMB> X"→ │   qa-cierre-ciclo   │  métricas + comentario Jira + doc actualizada
                    └─────────────────────┘
                              │ promovido a producción…
                              ▼
   "Cierre PROD X"→ ┌─────────────────────┐
                    │   qa-cierre-prod    │  cierre formal + página de cierre separada
                    └─────────────────────┘
                              │ aprobado en el ambiente final (y `baseline` encendido)…
                              ▼
                    ┌─────────────────────┐
                    │     qa-baseline     │  CONSOLIDAR: reglas verificadas → baseline
                    └─────────────────────┘  (qa-analisis-ticket lo CONSULTA antes de la Fase 1)
```

Cada etapa es independiente: puedes usar solo el análisis, solo los cierres, o el ciclo completo.

**El baseline (opcional).** Si lo enciendes en la config, cada ticket aprobado en el
ambiente `final: true` deja en un `.md` local las reglas que sus casos ✅ Pass verificaron, cada
una con caso, ticket, fecha y ambiente. Consolida el cierre que aprueba el ambiente final:
`qa-cierre-prod`, o `qa-cierre-ciclo` cuando es él quien cierra ese ambiente (por ejemplo, con un
solo ambiente en la config). El análisis del
siguiente ticket lo lee antes de empezar; si el ticket lo contradice, manda el ticket y la
desviación queda escrita, para que el cierre reemplace la regla vieja sin perder su historia.

## Los principios detrás (el porqué del diseño)

1. **El gate antes que los casos.** Diseñar pruebas sobre criterios vagos produce pruebas vagas.
   El gate de Fase 1 rechaza tickets incompletos con feedback — el QA sube la calidad de las
   historias, no solo las ejecuta. Detalle: `assets/gate-de-calidad.md`.

2. **QA empieza antes de la historia.** Por eso existe `qa-generacion-casos`: el input del QA es
   el primer documento o idea, no un ticket formateado.

3. **El humano dirige, la IA ejecuta.** Nada se publica sin tu confirmación. El agente propone
   borradores; tú decides. Los estados de Jira se cambian a mano, siempre.

4. **La IA ayuda con el CÓMO, tú decides el QUÉ.** Qué probar, qué prioridad real tiene un bug,
   cuándo un requerimiento no tiene sentido — eso no se delega. Detalle: `assets/5-errores-con-ia.md`.

5. **Método separado de config.** Las skills no saben de tu empresa; leen tu config. Cambias de
   trabajo, cambias un archivo, el método te sigue.

## El recurso como ejemplo del modelo

Este harness es, en sí mismo, el modelo que enseña:

| Concepto | Dónde lo ves en este recurso |
|---|---|
| **Harness** | El repo entero: tools (MCP) + método (skills) + reglas (`AGENTS.md` como fuente única; el `CLAUDE.md` de Claude Code y el `GEMINI.md` de Antigravity lo importan y solo agregan lo propio de su runtime, la rule de Cursor apunta a él, y Codex lo lee nativo en la raíz del repo) + config alrededor del modelo |
| **Goal** | El gate (✅/⚠️/❌), el conteo exacto de casos, el pass rate del cierre — criterios verificables en cada etapa |
| **Loop** | Cada skill itera: leer → analizar → proponer borrador → tu feedback → ajustar → publicar |

Si quieres el modelo mental completo, está gratis en calidadsinhumo.com (serie "Loop, Goal, Harness para QA").
