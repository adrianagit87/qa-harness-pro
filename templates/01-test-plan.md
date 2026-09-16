# Template: Test Plan de Sprint

> **Prompt integrado:** Copia la sección "Datos del sprint" llena y pégala junto con este prompt en tu IA:
>
> *"Actúa como QA Lead. Con los siguientes datos del sprint, completa este test plan: define el alcance (qué se prueba y qué no), la estrategia por ticket (manual/automatizado/ambos), priorización por riesgo de negocio, dependencias entre tickets, datos de prueba necesarios, estimación de esfuerzo, y criterios de salida. Sé realista con los tiempos."*

---

## Datos del sprint

| Campo | Valor |
|---|---|
| Sprint | [Nombre o número] |
| Fecha inicio | [DD/MM/AAAA] |
| Fecha fin | [DD/MM/AAAA] |
| QA asignado | [Nombre] |
| Días disponibles para testing | [Número] |
| Herramienta de gestión | [Jira/Linear/Trello/etc.] |

### Tickets del sprint

| ID | Título | Tipo | Complejidad estimada |
|---|---|---|---|
| | | Feature / Bug fix / Mejora | Baja / Media / Alta |
| | | | |
| | | | |

---

## Alcance

### Qué se prueba

| Ticket | Tipo de testing | Justificación |
|---|---|---|
| | Funcional / API / Regresión / E2E | |
| | | |

### Qué NO se prueba (y por qué)

| Área excluida | Razón |
|---|---|
| | |

---

## Estrategia por ticket

| Ticket | Manual | Automatizado | Ambos | Justificación |
|---|---|---|---|---|
| | ☐ | ☐ | ☐ | |
| | ☐ | ☐ | ☐ | |

---

## Priorización por riesgo

| Ticket | Riesgo de negocio | Impacto si falla | Prioridad QA |
|---|---|---|---|
| | Alto / Medio / Bajo | [Descripción] | 1° / 2° / 3° |
| | | | |

---

## Dependencias

| Ticket | Depende de | Bloquea a | Notas |
|---|---|---|---|
| | | | |

---

## Datos de prueba necesarios

| Ticket | Datos requeridos | ¿Existen? | Acción |
|---|---|---|---|
| | [Descripción] | Sí / No | Crear / Solicitar |
| | | | |

---

## Estimación de esfuerzo

| Ticket | Análisis | Ejecución manual | Automatización | Total |
|---|---|---|---|---|
| | [h] | [h] | [h] | [h] |
| **Total** | | | | **[h]** |

**Capacidad disponible:** [h]
**Buffer (20%):** [h]
**¿Alcanza?** ✅ Sí / ❌ No — [acción si no alcanza]

---

## Criterios de salida del sprint

- [ ] Todos los casos de prioridad 🔴 Alta ejecutados
- [ ] Pass rate ≥ [X]%
- [ ] Sin bugs 🔴 Críticos abiertos
- [ ] Bugs 🟠 Altos documentados con workaround
- [ ] Regression testing completado en flujos críticos
- [ ] Evidencia documentada para cada ticket
- [ ] Comentarios de cierre publicados en [herramienta]

---

## Notas y riesgos del sprint

| Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|
| | Alta / Media / Baja | Alto / Medio / Bajo | [Acción] |
