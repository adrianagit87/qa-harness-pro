# Plantilla — Informe de ejecución en navegador

> Lo genera `skills/qa-ejecucion-casos/SKILL.md`. Se guarda en
> `ejecuciones/[TICKET-ID]-[AMBIENTE]-[YYYYMMDD-HHMM]/informe.md` (carpeta en `.gitignore`) y se
> muestra en el chat. **No se publica en ningún lado**: es la propuesta que la persona revisa y
> confirma en `qa-cierre-ciclo`. Formato literal: no reordenes secciones.

```
═══════════════════════════════════════════════════
🧪 EJECUCIÓN EN NAVEGADOR — [TICKET-ID] — [AMBIENTE]
═══════════════════════════════════════════════════

Ambiente: [key] — [label] · URL base: [origen]
Fecha: [YYYY-MM-DD HH:MM] · Ejecutó: IA (Playwright MCP) · Revisa y confirma: [profile.name]
Carpeta de evidencia: ejecuciones/[TICKET-ID]-[AMBIENTE]-[YYYYMMDD-HHMM]/
Casos: [página de la doc | comentario de Jira [id] ([fecha]) — camino Jira-only]

📊 RESULTADOS PROPUESTOS (pendientes de tu confirmación)
| ID | Caso | Resultado propuesto | Motivo |
|---|---|---|---|
| [CP_ID] | [título] | ✅ Pass / ❌ Fail / ⏭️ Bloqueado / ⏸️ No ejecutado | [código de motivo o —] |

Pass: [n] · Fail: [n] · Bloqueado: [n] · No ejecutado: [n] · Total: [N]
```

Después, **una sección por caso**, en el mismo orden de la tabla:

```
### [CP_ID] — [título] — [resultado propuesto]

**Qué hice**
1. [acción concreta: navegué a /login, escribí QA_USER_EMAIL en «Correo», clic en «Ingresar»]
2. [...]

**Qué esperaba** (copiado del caso, sin reescribir)
[resultado esperado del caso]

**Qué vi**
[lo observado en la página: textos, mensajes, estado. Errores de consola si los hubo.]

**Evidencia:** [CP_ID].png[, [CP_ID]-fallo.png]
**Motivo:** [solo si no es Pass: código + una línea. Ej. "DATO_FALTANTE — el caso no dice qué
cliente usar"]
```

Y al final:

```
❓ PREGUNTAS PENDIENTES (casos bloqueados por falta de información)
1. [CP_ID] — [la pregunta concreta]

📋 OBSERVACIONES
[lo que no es un resultado: lentitud, errores de consola sin impacto visible, avisos]
```

Reglas del formato:

- **Qué esperaba** se copia literal del caso. Si el caso cambió en la doc, manda la doc.
- **Qué vi** describe lo observado, no la conclusión. "Apareció «Pedido confirmado» y el total
  dice $0" — no "funcionó".
- Los nombres de secretos se escriben como nombres (`QA_USER_PASSWORD`), nunca su valor.
- Un caso sin captura no puede ser ✅ Pass propuesto.
