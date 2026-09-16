# Template: Cierre de Pruebas (DEV / PROD)

> **Prompt integrado:** Llena la tabla de resultados y pega junto con este prompt:
>
> *"Con los siguientes resultados de prueba, genera un resumen de cierre profesional con: métricas de ejecución (total planificados, total ejecutados, pass, fail, bloqueados, no ejecutados, cobertura de ejecución = ejecutados/planificados, pass rate = pass/ejecutados), bugs encontrados con severidad, evaluación del estado (aprobado/requiere correcciones), y observaciones. Un caso bloqueado o no ejecutado NO cuenta como ejecutado. La aprobación exige cobertura de ejecución del 100% del alcance comprometido; si se cierra con menos, debe existir una excepción explícita registrada en observaciones como '⚠️ Alcance reducido aceptado por [nombre]: [motivo]' — sin ella, el veredicto es requiere correcciones. Formato copiable directo a Jira o herramienta de gestión."*

---

## Datos del cierre

| Campo | Valor |
|---|---|
| Ticket | [ID — Título] |
| Ambiente | DEV / PROD |
| Fecha de ejecución | [DD/MM/AAAA] |
| QA ejecutor | [Nombre] |
| Ciclo de pruebas | [1° / 2° / Re-test] |

---

## Resultados de ejecución

| ID | Título del caso | Prioridad | Resultado | Observación |
|---|---|---|---|---|
| TC-001 | | 🔴/🟡/🟢 | ✅ Pass / ❌ Fail / ⏭️ Bloqueado / ⏸️ No ejecutado | |
| TC-002 | | | | |
| TC-003 | | | | |
| TC-004 | | | | |
| TC-005 | | | | |

---

## Métricas

| Métrica | Valor |
|---|---|
| Total planificados | [N] |
| Total ejecutados (Pass + Fail) | [n] |
| ✅ Pass | [n] |
| ❌ Fail | [n] |
| ⏭️ Bloqueados | [n] |
| ⏸️ No ejecutados | [n] |
| **📐 Cobertura de ejecución** (ejecutados / planificados) | **[X]%** |
| **📈 Pass Rate** (Pass / ejecutados) | **[X]%** |

> Bloqueados y no ejecutados NO cuentan como ejecutados. Un Pass Rate de 100% con media
> suite sin correr no es calidad — para eso está la cobertura de ejecución.

---

## Bugs encontrados

| # | Descripción | Severidad | Ticket bug | Estado |
|---|---|---|---|---|
| 1 | [Descripción corta] | 🔴/🟠/🟡/🟢 | [ID si se creó] | Abierto / Resuelto |
| 2 | | | | |

**Sin bugs encontrados:** ☐

---

## Evaluación

### Ambiente DEV

| Condición | Resultado |
|---|---|
| Ningún caso 🔴 crítico en Fail, Bloqueado o No ejecutado | ✅ / ❌ |
| Cobertura 100% del alcance o excepción explícita registrada | ✅ / ❌ |
| Pass Rate ≥ 80% (sobre ejecutados) | ✅ / ❌ |
| Sin bugs abiertos (cualquier severidad) | ✅ / ❌ |
| **Veredicto** | **✅ Aprobado para siguiente ambiente / ⚠️ Requiere correcciones** |

### Ambiente PROD

| Condición | Resultado |
|---|---|
| Ningún caso 🔴 crítico en Fail, Bloqueado o No ejecutado | ✅ / ❌ |
| Cobertura 100% del alcance o excepción explícita registrada | ✅ / ❌ |
| Pass Rate ≥ 80% (sobre ejecutados) | ✅ / ❌ |
| Sin incidencias abiertas (cualquier severidad) | ✅ / ❌ |
| **Veredicto** | **✅ Aprobado en producción / 🔴 Requiere atención inmediata / ⚠️ Revisión requerida** |

> La primera condición manda: un crítico sin ejecutar veta la aprobación aunque el
> Pass Rate sea 100%. La segunda no se cumple en silencio: cerrar con cobertura < 100%
> exige que alguien lo declare, y queda registrado en Observaciones como
> "⚠️ Alcance reducido aceptado por [nombre]: [motivo]". Un "cierra nomás" no es una
> excepción — y la excepción tampoco salva a un 🔴 crítico: ese veta igual.

---

## Observaciones

[Notas relevantes para el equipo — limitaciones de la prueba, áreas no cubiertas, riesgos aceptados]

[Si se cierra con cobertura < 100% aceptada: "⚠️ Alcance reducido aceptado por [nombre]: [motivo]"]

---

## Evidencia

| Tipo | Link/Ubicación |
|---|---|
| Screenshots | [Link o carpeta] |
| Video de ejecución | [Link] |
| Reporte automatizado | [Link al HTML report] |
| Logs | [Link o referencia] |

---

## Comentario para herramienta de gestión

> Copia el siguiente bloque directamente en Jira/Linear/etc:

```
CIERRE DE PRUEBAS — [DEV/PROD]
────────────────────────────────────────
Fecha: [fecha]
QA: [nombre]
Ticket: [ID] — [Título]

Planificados: [N] | Ejecutados: [n] | ✅ [n] Pass | ❌ [n] Fail | ⏭️/⏸️ [n]
Cobertura: [X]% | Pass Rate (sobre ejecutados): [X]%
Bugs: [n encontrados / ninguno]

Estado: ✅ Aprobado / ⚠️ Requiere correcciones / 🔴 Atención inmediata
────────────────────────────────────────
```
