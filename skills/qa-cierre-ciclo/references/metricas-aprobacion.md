# Métricas y criterio de aprobación — `qa-cierre-ciclo`

> Referencia de `skills/qa-cierre-ciclo/SKILL.md` (Paso 3). Es texto del `SKILL.md`, movido sin cambios para que ese archivo entre en el límite de tamaño de Antigravity. Las secciones y reglas que se nombran acá viven en ese `SKILL.md`.

**Cómo se calculan las métricas (no improvises los denominadores):**

- **Ejecutados = Pass + Fail.** Un caso Bloqueado o No ejecutado NO cuenta como ejecutado.
- **Cobertura de ejecución = ejecutados / planificados.** No es solo informativa: la aprobación
  exige cobertura del 100% del alcance comprometido, o una excepción explícita registrada.
- **Pass Rate = Pass / ejecutados.** Si ejecutados = 0, el Pass Rate es N/A — y el ciclo no se aprueba.
- **Criterio de aprobación:** si existe algún caso de prioridad 🔴 crítica en Fail, Bloqueado o
  No ejecutado, el ciclo NO se aprueba — sin importar el Pass Rate. Con eso limpio, aplica el
  umbral: Pass Rate ≥ 80% (calculado sobre ejecutados), sin bugs abiertos y cobertura de
  ejecución del 100% del alcance comprometido.
- **Excepción de alcance (la única salida al 100% de cobertura):** si el usuario decide cerrar
  con cobertura menor, debe declararlo explícitamente, y el comentario de cierre lo registra como
  `⚠️ Alcance reducido aceptado por [nombre]: [motivo]` en `📋 OBSERVACIONES` — nunca de forma
  silenciosa. Mismo espíritu que la regla de resultados del Paso 2: el silencio o un "cierra
  nomás" NO cuentan como excepción. Sin excepción declarada y con cobertura < 100%, el estado del
  ciclo es ⚠️ REQUIERE CORRECCIONES ANTES DE AVANZAR, no aprobado. Y la excepción NO sustituye el
  veto de críticos: un caso 🔴 en Fail, Bloqueado o No ejecutado veta la aprobación aunque haya
  excepción firmada.
- ¿Por qué la cobertura? Porque un Pass Rate sobre ejecutados puede dar 100% con la mitad de la
  suite sin correr. La cobertura deja ese hueco a la vista.
