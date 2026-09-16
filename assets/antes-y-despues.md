# Antes y después — 3 ejemplos reales

Ejemplos anonimizados de trabajo real con el método que implementan las skills del harness. El ticket, lo que hace el agente, y cuánto tiempo cambia.

---

## Ejemplo 1 — Análisis de un ticket de registro de usuarios

**El ticket decía:**

> "Como usuario quiero poder registrarme en la plataforma para acceder a los cursos."
>
> Criterios de aceptación: El formulario debe validar los campos. El usuario debe recibir un email de confirmación.

**Antes (sin IA):**

Leer el ticket, abrir un documento, escribir los casos uno por uno, pensar los edge cases, olvidarlos, agregarlos después, darse cuenta de que los criterios son vagos, mandar mensaje al PO, esperar respuesta, reescribir los casos. **45 minutos.**

**Con el harness:**

`Analiza` + la URL del ticket. El agente:

1. Rechaza el ticket en 30 segundos — marca que "validar los campos" no es un criterio medible y que no hay definición de Done.
2. Genera 6 preguntas específicas para el PO: ¿qué campos? ¿longitud mínima del password? ¿qué pasa si el email ya existe? ¿el email de confirmación expira?
3. Cuando el PO responde y actualiza el ticket, se vuelve a pasar y genera 14 casos con datos concretos.

**Tiempo total: 12 minutos.** Y los casos son mejores, porque el gate obligó a completar el ticket antes de escribir un solo caso.

---

## Ejemplo 2 — Bug report de un error intermitente

**Lo que llegó por chat:**

> "Oye, a veces cuando le doy a guardar no pasa nada"

**Antes:**

Intentar reproducirlo. No lograrlo. Preguntar al dev "¿en qué página?". "En la de editar perfil, creo". Intentar de nuevo. A veces falla, a veces no. Bug report mediocre. El dev no puede reproducirlo. Ida y vuelta de 3 comentarios en Jira. **30 minutos desperdiciados.**

**Con el harness (template Bug Report + agente):**

El agente genera:

- 5 preguntas para el reportador (¿qué browser? ¿editando qué campo? ¿revisaste la consola?)
- Un borrador del bug report con hipótesis: "Posible race condition — el botón no se desactiva durante el submit, el usuario hace doble click, la segunda request falla silenciosamente"
- Sugerencias de evidencia: screenshot del network tab, logs de consola

Con las respuestas, el borrador era 90% correcto. **8 minutos**, bug report completo, el dev lo reprodujo al primer intento.

---

## Ejemplo 3 — Cierre de pruebas para un sprint

**Antes:**

Abrir Jira, revisar cada caso, contar a mano cuántos pasaron, calcular el pass rate en la calculadora, escribir el comentario de cierre, pegarlo en Jira, actualizar la documentación. **20 minutos por ticket.** Con 5 tickets por sprint: hora y media solo en documentación de cierre.

**Con el harness:**

`Cierre DEV TICKET-123`. El agente lee los casos desde la página de doc, pregunta solo cuáles fallaron (el resto asume ✅), calcula las métricas, arma el comentario estandarizado y **muestra el borrador**. Confirmas → publica en Jira y actualiza la doc, solo. **3 minutos por ticket.** 15 minutos los 5 tickets: más de una hora ahorrada por sprint.

> La diferencia con "un prompt": el agente está conectado a tus herramientas vía MCP. No copias ni
>
> pegas nada — pero **nada se publica sin tu confirmación** (regla de oro del harness).

---

*QA Harness Pro · calidadsinhumo.com*
