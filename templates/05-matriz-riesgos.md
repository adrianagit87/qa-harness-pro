# Template: Matriz de Riesgos Pre-Release

> **Prompt integrado:** Llena la sección "Datos del release" y pega junto con este prompt:
>
> *"Actúa como QA Senior evaluando riesgos antes de un release. Con los cambios que te doy, genera: matriz de riesgos (probabilidad × impacto) para cada cambio, áreas de regresión críticas, smoke test mínimo que DEBE pasar, plan de monitoreo post-release, criterios de rollback, y recomendación go/no-go con justificación."*

---

## Datos del release

| Campo | Valor |
|---|---|
| Versión / Release | [Nombre o número] |
| Fecha planificada | [DD/MM/AAAA] |
| Ventana de deploy | [Horario] |
| Responsable de deploy | [Nombre] |
| QA que valida | [Nombre] |

### Cambios incluidos

| # | Ticket | Descripción del cambio | Tipo | Áreas afectadas |
|---|---|---|---|---|
| 1 | [ID] | [Descripción breve] | Feature / Fix / Mejora | [Módulos/Páginas] |
| 2 | | | | |
| 3 | | | | |

### Contexto adicional

| Campo | Valor |
|---|---|
| Último incidente en prod | [Descripción y fecha, o "Ninguno reciente"] |
| Cambios de infraestructura | [Si aplica] |
| Dependencias externas afectadas | [APIs, servicios de terceros] |

---

## Matriz de riesgos

| # | Cambio/Área | Probabilidad | Impacto | Nivel de riesgo | Mitigación |
|---|---|---|---|---|---|
| 1 | [Cambio] | Alta/Media/Baja | Alto/Medio/Bajo | 🔴/🟡/🟢 | [Acción preventiva] |
| 2 | | | | | |
| 3 | | | | | |

### Cómo calcular el nivel

|  | Impacto Alto | Impacto Medio | Impacto Bajo |
|---|---|---|---|
| **Prob. Alta** | 🔴 Crítico | 🔴 Crítico | 🟡 Moderado |
| **Prob. Media** | 🔴 Crítico | 🟡 Moderado | 🟢 Bajo |
| **Prob. Baja** | 🟡 Moderado | 🟢 Bajo | 🟢 Bajo |

---

## Áreas de regresión críticas

| # | Flujo / Funcionalidad | Por qué es crítico | Probado | Resultado |
|---|---|---|---|---|
| 1 | [Flujo principal] | [Razón] | ☐ | |
| 2 | [Integración] | [Razón] | ☐ | |
| 3 | [Autenticación] | [Razón] | ☐ | |

---

## Smoke Test mínimo pre-release

> Estos tests DEBEN pasar antes de aprobar el deploy:

| # | Test | Tiempo estimado | Resultado | Ejecutado por |
|---|---|---|---|---|
| 1 | [Login funciona correctamente] | [min] | ✅/❌ | |
| 2 | [Flujo principal completo] | [min] | ✅/❌ | |
| 3 | [API principal responde] | [min] | ✅/❌ | |
| 4 | [Integración crítica funciona] | [min] | ✅/❌ | |
| 5 | [Página principal carga sin errores] | [min] | ✅/❌ | |

**Criterio:** Si algún smoke test falla → ❌ NO DEPLOY

---

## Plan de monitoreo post-release

| Qué monitorear | Herramienta | Umbral de alerta | Responsable |
|---|---|---|---|
| Errores 5xx | [Logs/Sentry/etc.] | [>N en X min] | [Nombre] |
| Tiempo de respuesta | [APM/Grafana/etc.] | [>Xms promedio] | [Nombre] |
| Tasa de errores de usuario | [Analytics] | [>X%] | [Nombre] |
| Funcionalidad nueva | [Prueba manual] | [No funciona] | [Nombre] |

**Ventana de monitoreo:** [Primeras X horas post-deploy]

---

## Criterios de rollback

| Condición | Acción |
|---|---|
| Errores 5xx > [N] en [X] minutos | Rollback inmediato |
| Flujo crítico no funciona | Rollback inmediato |
| Bug de severidad 🔴 Crítico detectado | Rollback inmediato |
| Bug 🟠 Alto sin workaround | Evaluar rollback vs hotfix |
| Degradación de performance > [X]% | Evaluar rollback |

**Comando de rollback:** [Documentar aquí cómo hacer rollback]

---

## Decisión GO / NO-GO

| Criterio | Estado |
|---|---|
| Todos los tickets del release probados | ✅ / ❌ |
| Sin bugs 🔴 Críticos abiertos | ✅ / ❌ |
| Smoke test pass | ✅ / ❌ |
| Plan de rollback documentado | ✅ / ❌ |
| Equipo disponible para monitoreo post-deploy | ✅ / ❌ |

### Veredicto

| Decisión | Selección |
|---|---|
| ✅ **GO** — Proceder con el release | ☐ |
| ⚠️ **GO CONDICIONAL** — Proceder con observaciones | ☐ |
| ❌ **NO-GO** — Posponer el release | ☐ |

**Justificación:** [Por qué se tomó esta decisión]

**Firma QA:** _________________ **Fecha:** _____________
