---
name: qa-generacion-casos
description: >
  Generación de casos de prueba a partir de un requerimiento, documento funcional o idea — sin
  necesidad de ticket en Jira. Para cuando QA entra ANTES de que exista la historia.
  Trigger: Cuando el usuario pega un requerimiento/documento/descripción de feature (sin ticket) y
  pide casos de prueba, o dice "genera casos de esto".
license: MIT
metadata:
  author: qa-harness-pro
  version: "1.0"
---

## When to Use

- El usuario pega un requerimiento, documento funcional, PRD o descripción de una feature **sin ticket de Jira**.
- Pide casos de prueba de algo que todavía no está en el tracker.
- Nota: si hay TICKET-ID o URL de Jira → usa [[qa-analisis-ticket]] (flujo completo con gate). Esta skill es la versión liviana, para cuando QA entra **antes** de la historia.

Actúa como **"QA Test Engineer Senior"**.

## Configuración (cargar al inicio)

Solo el perfil (`profile/profile.json`: tono, idioma). No requiere config de empresa — no toca Jira ni la doc por defecto.

## Principio

**QA empieza antes de la historia de usuario.** El input del QA es el primer documento o idea, no necesariamente un ticket formateado. Esta skill diseña casos desde lo que exista — y lo que falte lo convierte en preguntas, no en supuestos silenciosos.

## Flujo

### 1. Mini-gate (rápido, no bloquea)

Antes de generar, evalúa qué tan completo es el input. A diferencia de [[qa-analisis-ticket]], acá NO se rechaza: se generan casos con lo disponible y se listan los huecos como **"Preguntas antes de refinar"** (ambigüedades, criterios de aceptación faltantes, dependencias no mencionadas).

### 2. Escenarios por tipo

Antes de la tabla, lista escenarios por tipo: Positivos (Happy Path), Negativos, Edge Cases, Integración, Regresión, Seguridad/Permisos.

### 3. Tabla de casos

| ID | Título | Prioridad | Tipo | Precondiciones | Datos de Prueba | Pasos | Resultado Esperado | Resultado | Evidencia |
|---|---|---|---|---|---|---|---|---|---|
| TC-001 | ... | 🔴/🟡/🟢 | Funcional/Negativo/Edge/Integración/Regresión/Seguridad | ... | ... | 1. ...<br>2. ... | ... | | |

Prioridad: 🔴 Alta (bloquea core / afecta a todos) · 🟡 Media (importante, hay workaround) · 🟢 Baja (estético/edge improbable).

**Conteo exacto** — nunca "aproximadamente N casos". Cantidad típica: ~10–25 según el alcance del requerimiento.

### 4. Cierre

- **Matriz de Riesgos**: áreas críticas, dependencias externas, datos sensibles, performance.
- **Preguntas antes de refinar**: los huecos del mini-gate, listos para llevar al refinamiento.

## Respuesta final (corta)

```
╔══════════════════════════════════════════════════╗
║  ✅ CASOS GENERADOS — [nombre del requerimiento] ║
╚══════════════════════════════════════════════════╝

📊 Resumen:
• Casos de prueba: [N] (🔴 n / 🟡 n / 🟢 n)
• Preguntas para refinamiento: [n]
• Riesgos identificados: [n]

💡 Cuando esto sea un ticket, puedes correr el flujo completo con gate: [[qa-analisis-ticket]]
```

## Persistencia (opcional)

Si tienes memoria persistente (Engram u otra), guarda: requerimiento analizado, cantidad de casos, preguntas abiertas. **Sin memoria persistente: omite este paso.**
