# skills/ — el MÉTODO

Cada skill es una forma de trabajo de QA, portable y config-driven (lee de `companies/` y
`profile/`, nunca hardcodea datos).

Las 5 skills:

| Skill | Qué hace | Necesita |
|---|---|---|
| `qa-analisis-ticket` | Análisis funcional (gate) + casos + doc. **El corazón.** | Jira + config de empresa |
| `qa-generacion-casos` | Casos desde un requerimiento, sin ticket. QA antes de la historia. | Nada (solo perfil) |
| `qa-cierre-ciclo` | Cierre de ciclo en cualquier ambiente de `environments`: métricas + comentario Jira + doc actualizada. | Jira + doc + config |
| `qa-cierre-prod` | Cierre formal del ambiente final + página separada. Solo si `environments` define un ambiente final distinto del de prueba. | Jira + doc + config |
| `qa-automatizacion` | Fase 3 opcional: veredicto + ROI + código integrado a tu suite. | `automation` en config |

El flujo completo y cómo se encadenan: [`docs/METODO.md`](../docs/METODO.md).
