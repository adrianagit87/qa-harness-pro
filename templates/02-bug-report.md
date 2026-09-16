# Template: Bug Report Profesional

> **Prompt integrado:** Llena lo que sepas de la sección "Datos del bug" y pega junto con este prompt:
>
> *"Con la siguiente información de un bug, genera un reporte profesional completo. Incluye: severidad con justificación, pasos para reproducir exactos y numerados, resultado esperado vs actual, frecuencia, impacto en el usuario final, hipótesis de causa raíz, y sugerencias de evidencia a capturar. El reporte debe ser tan claro que cualquier desarrollador pueda reproducir el bug sin preguntar nada."*

---

## Datos del bug

| Campo | Valor |
|---|---|
| Ticket relacionado | [ID si existe] |
| Funcionalidad afectada | [Módulo/Página/Flujo] |
| Entorno | Dev / Staging / Producción |
| Browser/Dispositivo | [Chrome 120 / iPhone 15 / etc.] |
| Usuario de prueba | [Si aplica] |
| Fecha de detección | [DD/MM/AAAA] |
| Detectado por | [Nombre] |

---

## Reporte

### Severidad

| Nivel | Criterio | Selección |
|---|---|---|
| 🔴 Crítico | Bloquea funcionalidad core, afecta a todos los usuarios | ☐ |
| 🟠 Alto | Afecta funcionalidad importante, workaround difícil | ☐ |
| 🟡 Medio | Afecta funcionalidad, workaround existe | ☐ |
| 🟢 Bajo | Estético, typo, mejora menor | ☐ |

**Justificación de severidad:** [Por qué elegiste este nivel]

### Prioridad de fix

| Nivel | Criterio | Selección |
|---|---|---|
| Alta | Arreglar en este sprint | ☐ |
| Media | Arreglar antes del próximo release | ☐ |
| Baja | Backlog — arreglar cuando haya tiempo | ☐ |

---

### Título del bug

> [SEVERIDAD] Descripción corta y accionable
>
> Ejemplo: 🟡 El botón "Guardar" no se desactiva mientras se procesa el formulario de registro

---

### Pasos para reproducir

1. [Paso exacto — incluir URL si aplica]
2. [Paso exacto — incluir datos ingresados]
3. [Paso exacto — incluir clics y acciones]
4. [Observar resultado]

**Precondiciones:**
- [Estado necesario antes de reproducir]

---

### Resultado esperado

[Qué debería pasar según los criterios de aceptación o el comportamiento lógico]

### Resultado actual

[Qué está pasando — describir el bug con precisión]

---

### Frecuencia de reproducción

| Frecuencia | Selección |
|---|---|
| Siempre (100%) | ☐ |
| Frecuentemente (>50%) | ☐ |
| A veces (<50%) | ☐ |
| Una sola vez | ☐ |

---

### Impacto en el usuario

[Cómo afecta la experiencia del usuario final — ¿puede completar el flujo? ¿pierde datos? ¿ve un error?]

---

### Evidencia

| Tipo | Adjunto | Descripción |
|---|---|---|
| Screenshot | ☐ | [Qué muestra] |
| Video | ☐ | [Qué captura] |
| Logs de consola | ☐ | [Errores JS relevantes] |
| Network tab | ☐ | [Request/Response fallido] |

---

### Información adicional

| Campo | Valor |
|---|---|
| Workaround temporal | [Si existe — cómo el usuario puede evitar el bug] |
| Hipótesis de causa | [Si tienes idea de qué lo causa] |
| Otros tickets afectados | [IDs relacionados] |
| ¿Regresión? | Sí (funcionaba antes de [fecha/deploy]) / No / No sé |
