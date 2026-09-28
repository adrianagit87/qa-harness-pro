# skills/ — el MÉTODO

Cada skill es una forma de trabajo de QA, portable y config-driven (lee de `companies/` y
`profile/`, nunca hardcodea datos).

Las 6 skills:

| Skill | Qué hace | Necesita |
|---|---|---|
| `qa-analisis-ticket` | Análisis funcional (gate) + casos + doc. **El corazón.** | Jira + config de empresa |
| `qa-generacion-casos` | Casos desde un requerimiento, sin ticket. QA antes de la historia. | Nada (solo perfil) |
| `qa-cierre-ciclo` | Cierre de ciclo en cualquier ambiente de `environments`: métricas + comentario Jira + doc actualizada. | Jira + doc + config |
| `qa-cierre-prod` | Cierre formal del ambiente final + página separada. Solo si `environments` define un ambiente final distinto del de prueba. | Jira + doc + config |
| `qa-automatizacion` | Fase 3 opcional: veredicto + ROI + código integrado a tu suite. | `automation` en config |
| `qa-baseline` | Baseline: consolida reglas verificadas al aprobar el ambiente final y las consulta antes de analizar. Opcional, apagado por defecto. | `baseline` en config (`enabled: true`) |

Cada skill es una carpeta con su `SKILL.md`: el punto de entrada, con la config, los pasos en orden
y las reglas que tienen que estar siempre en contexto. Cuando el detalle de un paso no entra ahí, va
**textual** a `references/<tema>.md` dentro de la misma carpeta, y el paso lo pide con un puntero
imperativo ("Antes de ejecutar este paso, leé `references/<tema>.md`"). Hoy lo usan
`qa-analisis-ticket` y `qa-cierre-ciclo`. El motivo es el límite de 12.000 caracteres de Antigravity
([`adapters/antigravity/README.md`](../adapters/antigravity/README.md));
`tests/test_skills_tamano.py` falla si un `SKILL.md` lo pasa o si apunta a una referencia que no
existe. Las reglas que no pueden faltar nunca se mueven a `references/`.

El flujo completo y cómo se encadenan: [`docs/METODO.md`](../docs/METODO.md).
