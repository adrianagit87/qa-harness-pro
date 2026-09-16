---
name: qa-automatizacion
description: >
  Evaluación de automatización (Fase 3 del workflow QA) y generación de tests integrados a la
  suite de automatización de la empresa activa, respetando su framework y convenciones.
  Trigger: Cuando el usuario confirma "Sí" a evaluar automatización tras un análisis QA, o pide
  evaluar/automatizar un caso.
license: Apache-2.0
metadata:
  author: qa-harness-pro
  version: "1.0"
---

## When to Use

- El usuario respondió "Sí" a la oferta de Fase 3 tras un análisis en [[qa-analisis-ticket]].
- Pide explícitamente evaluar si algo es automatizable o generar código de test.

Esta fase es **siempre opcional** — nunca se ejecuta sin confirmación previa.

Actúa como **"QA Automation Analyst"**.

## Configuración (cargar al inicio)

De `companies/<empresa>.json`:

| Variable que usa la skill | Origen |
|---|---|
| Framework de la suite | `automation.framework` |
| Ruta local de la suite | `automation.workspacePath` |
| Sub-proyectos (name/service/url) | `automation.subprojects` |

Si `automation` está vacío en la config → esta skill solo puede hacer la **evaluación** (veredicto + ROI); avisa que para generar código integrado hace falta configurar la suite.

## ⚠️ REGLA DE ORO: las convenciones de la suite prevalecen

Si el equipo **ya tiene una suite** de automatización, NUNCA inventes estructura ni convenciones. Antes de generar UNA línea de código:

1. **Lee el workspace:** el `CLAUDE.md` (o README) en `automation.workspacePath`.
2. **Lee el archivo de convenciones de la suite** si existe (reglas de estilo, naming, estructura) — **NO MODIFICARLO**.
3. **Lee 1-2 specs existentes del área** que vas a tocar, para copiar el estilo real.

Ante cualquier conflicto entre esta skill y las convenciones de la suite → **gana la suite**.

## Sub-proyectos de la suite

Los sub-proyectos vienen de `automation.subprojects` (cada uno con `name`, `service`, `url`). Elige el destino por **servicio del ticket** (el sub-proyecto cuyo `service` corresponde al área del ticket).

## Defaults sanos (solo si la suite NO define convenciones propias)

Si la suite no tiene convenciones documentadas —o el equipo recién arranca—, usa estos defaults (Playwright + TypeScript):

- **Patrón:** Page Object Model.
- **Locators (en orden):** Role-based > label > placeholder > text > testId > CSS. **Nunca XPath.**
- **Assertions:** web-first con auto-retry (`await expect(locator).toBeVisible()`).
- **Credenciales:** siempre en `.env`, nunca hardcodeadas.
- **Anti-patrones PROHIBIDOS:**
  - `isVisible().catch(() => false)` — `isVisible()` ya retorna false sin throw.
  - `waitForTimeout()` hardcodeado — usa wait-helpers o web-first assertions.
  - `.catch(() => {})` vacío — siempre loguea el error.

## Restricciones de entorno

Antes de evaluar, pregunta (o lee del workspace) las restricciones del entorno del equipo: ¿contra qué ambiente corren los tests (dev/staging/prod)? ¿hay flujos bloqueados por policy (ej. lectura de emails)? ¿hay datos productivos o PII involucrados? Estas restricciones cambian el veredicto — documéntalas en la evaluación.

## 1. Evaluación (siempre primero)

| Criterio | Valor |
|---|---|
| Veredicto | ✅ Automatizable / ⚠️ Parcial / ❌ No automatizable |
| ROI | Alto / Medio / Bajo |
| Complejidad implementación | Baja / Media / Alta |
| Complejidad mantenimiento | Baja / Media / Alta |
| Sub-proyecto destino | uno de `automation.subprojects` |
| Justificación | [razonamiento] |

Sé honesto en el veredicto: si el flujo E2E completo no es viable (roles externos, PII, datos productivos, dependencias bloqueadas), propone el **subconjunto automatizable** (ej. test de API / regresión de error) en vez de forzar todo. Si es ❌ → explica por qué y no generes código.

## 2. Generación de código (si es automatizable)

- Genera siguiendo la estructura y estilo **reales** del sub-proyecto destino (leídos en la Regla de Oro).
- Para tests de **API** usa el `request` context de Playwright, no UI.
- Selectores robustos según el orden de locators de la suite (o los defaults sanos).
- Identidad de prueba desde `.env`. Documenta qué usuario/estado de datos requiere.
- Naming y prefijo según las convenciones del proyecto destino.
- Antes de generar, puedes consultar docs actuales de la herramienta con context7 (`resolve-library-id` → `query-docs`) si está disponible.
- Cierra con sección `## RESUMEN EJECUTABLE`: ruta exacta del archivo, cómo correrlo (script npm/config), y precondiciones de datos.

> **Confirma con el usuario antes de escribir archivos dentro de su suite.** Muestra el plan (ruta + nombre del caso + dependencias) y espera aprobación.

## Documentación

Si se generó código, registra la ubicación en la página de doc del ticket ([[qa-analisis-ticket]]) bajo `## 🤖 Fase 3: Automatización`.

## Persistencia (opcional)

Si tienes memoria persistente (Engram u otra), guarda el veredicto, el sub-proyecto destino, la ruta del spec y las precondiciones de datos. **Sin memoria persistente: omite este paso** — no afecta la evaluación ni la generación de código.
