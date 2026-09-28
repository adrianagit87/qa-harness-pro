# QA Harness Pro — Cheat Sheet (Referencia Rápida)

> Para imprimir y tener al lado del monitor.

---

## COMANDOS RÁPIDOS (las skills del harness)

| Escribes | El agente hace | Skill |
|---|---|---|
| `Analiza [URL de Jira o TICKET-ID]` | Análisis funcional (gate) + casos + doc | `qa-analisis-ticket` |
| `[pegas un requerimiento sin ticket]` | Casos de prueba + preguntas para refinar | `qa-generacion-casos` |
| `Cierre [AMBIENTE] [TICKET-ID]` | Cierre con métricas: comentario Jira + doc | `qa-cierre-ciclo` |
| `Cierre PROD [TICKET-ID]` | Cierre formal PROD + página de cierre | `qa-cierre-prod` |
| `Sí` (tras un análisis) | Evalúa automatización y genera tests | `qa-automatizacion` |

> El agente siempre muestra el **borrador antes de publicar** nada. Tú confirmas, él ejecuta.

---

## SEVERIDAD DE BUGS — REFERENCIA RÁPIDA

| Icono | Nivel | Cuándo usarlo |
|---|---|---|
| 🔴 | Crítico | Bloquea funcionalidad core, afecta a todos |
| 🟠 | Alto | Funcionalidad importante, workaround difícil |
| 🟡 | Medio | Funcionalidad afectada, workaround existe |
| 🟢 | Bajo | Estético, typo, mejora menor |

---

## PRIORIDAD DE CASOS DE PRUEBA

| Icono | Nivel | Ejecutar |
|---|---|---|
| 🔴 | Alta | Siempre, en todos los ciclos |
| 🟡 | Media | En ciclo completo, skip en smoke |
| 🟢 | Baja | Solo si hay tiempo |

---

## GATE DE CALIDAD — ¿ESTÁ LISTA LA HISTORIA?

**DEBE tener (obligatorio):**
- ☐ Título claro
- ☐ Descripción completa
- ☐ Criterios de aceptación medibles
- ☐ Definición de Done

**DEBERÍA tener (condicional):**
- ☐ Datos de prueba
- ☐ Mockups (si es UI)
- ☐ Dependencias identificadas
- ☐ Permisos/seguridad

**Falta un obligatorio → RECHAZAR. No generes casos.**
(Detalle y por qué de cada ítem: `assets/gate-de-calidad.md`)

---

## TÉCNICAS ISTQB — CUÁNDO USAR CADA UNA

| Técnica | Úsala cuando | Ejemplo |
|---|---|---|
| **Partición de equivalencia** | Campo con rangos o categorías | Edad: <0, 0-17, 18-65, >65 |
| **Valores límite** | Necesitas los bordes exactos | Edad: -1, 0, 17, 18, 65, 66 |
| **Tabla de decisión** | Hay combinaciones de reglas | Descuento si cliente VIP Y compra >$100 |
| **Transición de estados** | Hay estados que cambian | Pedido: Creado→Pagado→Enviado→Entregado |

---

## DECISIÓN: ¿AUTOMATIZAR O NO?

```
¿Se ejecuta más de 1 vez por sprint?
  NO → Manual
  SÍ ↓

¿La funcionalidad es estable (no cambia cada sprint)?
  NO → Manual (automatizar cuando estabilice)
  SÍ ↓

¿El flujo es reproducible sin intervención humana?
  NO → Manual (captchas, aprobaciones externas)
  SÍ ↓

¿El riesgo de no detectar un fallo es alto?
  SÍ → AUTOMATIZAR (prioridad alta)
  NO → AUTOMATIZAR (prioridad media)
```

(Razonamiento completo y ejemplos: `assets/arbol-automatizar-o-no.md`)

---

## TEMPLATES INCLUIDOS (`templates/`)

| Template | Para qué | Cuándo |
|---|---|---|
| Test Plan | Planificar testing del sprint | Inicio del sprint |
| Bug Report | Reportar bugs profesionalmente | Cada bug que encuentres |
| Análisis de Requerimiento | Gate de calidad pre-testing | Cada ticket nuevo |
| Cierre de Pruebas | Documentar el cierre de un ambiente | Al terminar cada ciclo |
| Matriz de Riesgos | Evaluar riesgos pre-release | Día antes del release |

Estos tres no los llenas tú: son los formatos de salida que las skills leen para publicar.

| Template | Para qué | Quién lo usa |
|---|---|---|
| Especificación de Caso (CP) | Descripción de cada issue hijo en Jira | `qa-analisis-ticket` |
| Comentario de Cierre de Ciclo | Comentario estandarizado del cierre | `qa-cierre-ciclo` |
| Comentario de Ejecución de un CP | Registro de ejecución por caso | `qa-cierre-ciclo` |

---

*QA Harness Pro · calidadsinhumo.com*
