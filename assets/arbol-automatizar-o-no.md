# El árbol de decisión: ¿automatizar o no?

La pregunta equivocada es "¿se puede automatizar?". Casi todo se puede. La pregunta correcta es
**"¿vale la pena?"** — y eso se decide con cuatro preguntas en orden. Es la lógica que usa
`qa-automatizacion` en su evaluación (veredicto + ROI), y la puedes usar tú sin IA.

---

## El árbol

```
1. ¿Se ejecuta más de 1 vez por sprint?
     NO → Manual
     SÍ ↓

2. ¿La funcionalidad es estable (no cambia cada sprint)?
     NO → Manual (automatizar cuando estabilice)
     SÍ ↓

3. ¿El flujo es reproducible sin intervención humana?
     NO → Manual (captchas, aprobaciones externas, hardware físico)
     SÍ ↓

4. ¿El riesgo de no detectar un fallo es alto?
     SÍ → AUTOMATIZAR (prioridad alta)
     NO → AUTOMATIZAR (prioridad media)
```

## El porqué de cada pregunta

**1. Frecuencia.** Un test automatizado se paga con ejecuciones. Si el flujo se prueba una vez por
release, el costo de escribirlo y mantenerlo nunca se recupera. La automatización es una inversión:
sin repetición, no hay retorno.

**2. Estabilidad.** Automatizar una feature que cambia cada sprint es mantener un test que se rompe
cada sprint. No es un test: es una carga. Espera a que el diseño se asiente; mientras tanto, manual.

**3. Reproducibilidad.** Si el flujo necesita un humano (resolver un captcha, aprobar desde un
sistema externo, tocar un dispositivo físico), la "automatización" va a necesitar intervención
manual igual — perdiendo el punto. A veces la respuesta es automatizar un **subconjunto**: la parte
reproducible por API, y dejar el paso humano fuera.

**4. Riesgo.** Todo lo que llegó hasta acá conviene automatizarlo — la pregunta 4 solo decide la
**prioridad**. Flujo de pagos, login, datos sensibles: prioridad alta, primero en la cola. Un
reporte interno que miran dos personas: prioridad media, cuando haya tiempo.

## Errores comunes con este árbol

- **Saltarse la pregunta 2 por entusiasmo.** "Automaticemos todo el sprint 1" es la receta para una
  suite roja e ignorada en el sprint 4.
- **Tratar "manual" como derrota.** Manual es el veredicto correcto para flujos únicos, inestables
  o exploratorios. Un QA que automatiza lo que no debe pierde el tiempo dos veces: al escribirlo y
  al mantenerlo.
- **Automatizar el flujo entero cuando solo un tramo lo amerita.** El veredicto ⚠️ Parcial existe
  por algo: a veces el 20% del flujo (la API, la regresión del error) da el 80% del valor.

---

*QA Harness Pro · calidadsinhumo.com*
