# Template: Análisis de Requerimiento (Gate de Calidad)

> **Prompt integrado:** Pega la historia de usuario o requerimiento junto con este prompt:
>
> *"Actúa como Analista Funcional QA Senior. Analiza este requerimiento usando el checklist de validación de abajo. Para cada criterio obligatorio indica ✅ o ❌. Si falta algún obligatorio, marca como RECHAZADA. Incluye preguntas para el PO/Dev, riesgos identificados, y áreas grises. Al final, da tu veredicto: ¿está lista para testing?"*

---

## Datos del requerimiento

| Campo | Valor |
|---|---|
| Ticket ID | [ID] |
| Título | [Título del ticket] |
| Sprint | [Sprint actual] |
| Autor | [PO/PM que lo escribió] |
| Fecha de análisis | [DD/MM/AAAA] |
| Analista QA | [Tu nombre] |

---

## Requerimiento original

> [Pegar aquí la historia de usuario o requerimiento completo]

---

## Checklist de validación

### Criterios obligatorios (si falta alguno → ❌ RECHAZADA)

| # | Criterio | Estado | Observación |
|---|---|---|---|
| 1 | Título claro y descriptivo | ✅ / ❌ | |
| 2 | Descripción completa del comportamiento esperado | ✅ / ❌ | |
| 3 | Criterios de aceptación medibles y verificables | ✅ / ❌ | |
| 4 | Definición de Done clara | ✅ / ❌ | |

### Criterios condicionales (si falta → ⚠️ CON OBSERVACIONES)

| # | Criterio | Estado | Observación |
|---|---|---|---|
| 5 | Datos de prueba especificados | ✅ / ❌ / N/A | |
| 6 | Diseños o mockups adjuntos (si es UI) | ✅ / ❌ / N/A | |
| 7 | Dependencias identificadas | ✅ / ❌ / N/A | |
| 8 | Consideraciones de permisos/seguridad | ✅ / ❌ / N/A | |

---

## Veredicto

| Estado | Significado | Selección |
|---|---|---|
| ✅ APROBADA | Lista para generar casos de prueba | ☐ |
| ⚠️ APROBADA CON OBSERVACIONES | Se puede avanzar pero hay huecos | ☐ |
| ❌ RECHAZADA | No está lista — requiere información antes de continuar | ☐ |

---

## Bloqueos críticos

- [ ] [Qué falta para poder probar esto]
- [ ] [Qué información es necesaria]

## Mejoras recomendadas

- [ ] [Sugerencia para mejorar el requerimiento]
- [ ] [Sugerencia para facilitar el testing]

---

## Preguntas para PO/Dev

| # | Pregunta | Dirigida a | Respuesta |
|---|---|---|---|
| 1 | [Pregunta sobre comportamiento esperado] | PO / Dev | [Pendiente] |
| 2 | [Pregunta sobre validaciones] | Dev | [Pendiente] |
| 3 | [Pregunta sobre edge cases] | PO | [Pendiente] |

---

## Riesgos identificados

| Tipo | Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|---|
| Técnico | [Descripción] | Alta/Media/Baja | Alto/Medio/Bajo | [Acción] |
| Negocio | [Descripción] | | | |
| Área gris | [Comportamiento no especificado] | | | |

---

## Siguiente paso

- ❌ RECHAZADA → Enviar feedback al PO/Dev. No generar casos de prueba.
- ⚠️/✅ → Continuar con generación de casos de prueba.
