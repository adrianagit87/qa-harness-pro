# Clasificación de resultados — `qa-ejecucion-casos`

> Referencia de `skills/qa-ejecucion-casos/SKILL.md` (Paso 4). Las cuatro etiquetas son las
> mismas de `qa-cierre-ciclo`: no inventes otras. Lo que agrega esta skill es el **motivo**, para
> que un error de la herramienta nunca se lea como un bug ni un bug como un error de la herramienta.

## ✅ Pass — solo con las tres cosas

1. Ejecutaste **todos** los pasos del caso, en orden, sin saltar ni reinterpretar ninguno.
2. Lo observado coincide con el resultado esperado **completo** (cada condición que nombra).
3. Hay captura del momento en que se verifica el resultado esperado.

Si falta cualquiera de las tres, no es Pass. "Parece que anduvo" no es Pass.

## ❌ Fail — la aplicación respondió distinto de lo esperado

El caso se ejecutó completo, la aplicación respondió, y lo observado **contradice** el resultado
esperado. Es un posible defecto: captura del fallo (`[CP_ID]-fallo.png`) y en "Qué vi" lo exacto
(texto del mensaje, valor mostrado). Sin motivo de código: el motivo es la diferencia.

## ⏭️ Bloqueado — no se pudo llegar al resultado

| Código | Cuándo |
|---|---|
| `DATO_FALTANTE` | El caso necesita un dato que no está en "Datos de prueba" (un usuario, un ID, un monto). |
| `PASO_AMBIGUO` | Un paso admite más de una lectura, o nombra un elemento que no existe en la página. |
| `RESULTADO_NO_VERIFICABLE` | El esperado no se puede comprobar mirando la página ("se guarda en la base", "llega un mail"). |
| `SECRETO_FALTANTE` | Modo secretos: hace falta una credencial y su nombre no está en `profile/browser-secrets.env`. Con login manual no aplica: la persona inicia sesión. |
| `FUERA_DE_ALCANCE` | El gate del navegador bloqueó una URL, o un link/redirección sacó al navegador del ambiente. |
| `AMBIENTE_CAIDO` | La aplicación no responde, da error 5xx o no carga (no es el caso, es el ambiente). |
| `PRECONDICION` | No se pudo dejar el sistema en el estado inicial que pide el caso. |
| `HERRAMIENTA` | Error del navegador o del MCP (timeout, elemento no accionable) que no es la aplicación. |

**Casos parciales** (en el plan, "Sí, parcial"): si la parte que se hizo en el navegador
**contradice** el esperado, es ❌ Fail con su evidencia. Si todo lo que se pudo ver coincide, es
⏭️ Bloqueado (`RESULTADO_NO_VERIFICABLE`) y el motivo dice las dos cosas: qué se verificó (con ✓)
y qué quedó fuera. Ej. "La UI muestra el tipo fijo ✓; los PATCH por API quedaron fuera". La
persona puede cerrarlo como Pass en el cierre solo si verifica a mano lo que faltó.

Regla: **ante la duda entre ❌ Fail y ⏭️ Bloqueado, es Bloqueado.** Reportar un bug que no existe
le cuesta tiempo al dev; reportar como bug un error de la herramienta destruye la confianza en el
informe.

Los bloqueados por `DATO_FALTANTE`, `PASO_AMBIGUO`, `RESULTADO_NO_VERIFICABLE` y
`SECRETO_FALTANTE` generan una pregunta en "❓ PREGUNTAS PENDIENTES". Con la respuesta, el caso se
re-ejecuta: nunca se completa el resultado de memoria.

## ⏸️ No ejecutado — no se intentó

| Código | Cuándo |
|---|---|
| `NO_ES_DE_NAVEGADOR` | Los pasos son de API, SQL, logs o de otro sistema: este caso no se ejecuta en el navegador. |
| `NO_SELECCIONADO` | La persona lo sacó de la corrida en el plan. |
| `CORRIDA_INTERRUMPIDA` | La corrida se detuvo antes de llegar a este caso. |

## Lo que nunca pasa

- Un caso que no se ejecutó, o que se ejecutó a medias (incluido un "Sí, parcial" del plan),
  **nunca** es ✅ Pass.
- Un bloqueo del gate **nunca** se esquiva: no se reintenta por otra ruta, otra tool u otra URL.
- Un dato que no está en el caso **nunca** se inventa para poder avanzar (regla 3 de `AGENTS.md`).
