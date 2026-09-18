# Template: Comentario de Cierre de Ciclo

> **Lo usa [[qa-cierre-ciclo]]** (Paso 3) como comentario estandarizado a publicar en Jira.
> `[AMBIENTE]`, `[label]` y `[emoji]` salen del ambiente resuelto en `environments.list`.
> El formato debe ser idéntico en todos los tickets del mismo ciclo: no improvises ni reordenes.
> Cómo se calculan las métricas y el criterio de aprobación viven en el `SKILL.md`, no acá.

---

```
[emoji] CIERRE DE PRUEBAS — AMBIENTE [label]
────────────────────────────────────────
📅 Fecha: [fecha actual]
👤 QA: [profile.name]
🎯 Ticket: [TICKET-ID] — [Título]

📊 MÉTRICAS
• Total planificados: [N]
• Total ejecutados:   [n] (Pass + Fail)
• ✅ Pass:            [n]
• ❌ Fail:            [n]
• ⏭️ Bloqueados:      [n]
• ⏸️ No ejecutados:   [n]
• 📐 Cobertura de ejecución: [X]% (ejecutados / planificados)
• 📈 Pass Rate:              [X]% (Pass / ejecutados)

🧪 CASOS VALIDADOS
| ID | Caso | Resultado |
| --- | --- | --- |
| TC-001 | [título/descripción del caso] | ✅ Pass / ❌ Fail / ⏭️ Bloqueado / ⏸️ No ejecutado |
[... una fila por caso ...]

🐛 BUGS ENCONTRADOS
[Si hay bugs:]
• [BUG-ID o descripción] — Severidad: 🔴/🟠/🟡/🟢
[Si no hay bugs:]
• Sin bugs reportados en este ciclo ✅

📋 OBSERVACIONES
[Observaciones del usuario o "Sin observaciones adicionales"]
[Si se cierra con cobertura < 100% aceptada: "⚠️ Alcance reducido aceptado por [nombre]: [motivo]"]

🔄 ESTADO DEL CICLO [AMBIENTE]
[Algún caso 🔴 crítico en Fail, Bloqueado o No ejecutado]                          → ⚠️ REQUIERE CORRECCIONES ANTES DE AVANZAR
[Cobertura < 100% sin excepción explícita declarada]                               → ⚠️ REQUIERE CORRECCIONES ANTES DE AVANZAR
[Sin críticos, Pass Rate ≥ 80%, sin bugs, cobertura 100% (o excepción registrada)] → ✅ APROBADO PARA SIGUIENTE AMBIENTE  ← si el ambiente tiene `final: false`
                                                                                   → ✅ FUNCIONALIDAD APROBADA            ← si tiene `final: true` (no hay ambiente siguiente)
[Sin críticos pendientes, pero Pass Rate < 80% o hay bugs]                         → ⚠️ REQUIERE CORRECCIONES ANTES DE AVANZAR
────────────────────────────────────────
📝 Documentación completa: [link a la página de doc]
```
