# El Gate de Calidad — ¿está lista la historia para probarse?

El gate es la Fase 1 de `qa-analisis-ticket`: antes de escribir un solo caso, el agente valida que
el ticket esté completo. Si falta algo obligatorio, se **rechaza con feedback** — no se generan
casos sobre una historia rota.

**Por qué existe:** los casos de prueba escritos sobre criterios vagos prueban cosas vagas. El
gate obliga a completar el ticket ANTES de invertir tiempo en diseñar pruebas — y convierte al QA
en la persona que sube la calidad de las historias, no solo la que las ejecuta.

---

## Obligatorios (su ausencia = ❌ RECHAZADA)

| Ítem | Por qué es obligatorio |
|---|---|
| **Título claro** | Si el título no dice qué es, nadie va a encontrar el ticket después — ni entender el alcance de un vistazo. |
| **Descripción completa** | Sin descripción no hay contexto: no sabes QUÉ construyeron ni PARA QUIÉN. Los casos salen genéricos. |
| **Criterios de aceptación medibles** | "Debe validar los campos" no es medible. ¿Qué campos? ¿Con qué reglas? Cada criterio vago es un bug esperando pasar. |
| **Definición de Done** | Sin Done acordado, "terminado" significa una cosa para el dev y otra para el PO. QA queda en el medio. |

## Condicionales (su ausencia = ⚠️ APROBADA CON OBSERVACIONES)

| Ítem | Cuándo pesa |
|---|---|
| **Datos de prueba** | Si el flujo necesita usuarios/estados específicos y nadie los definió, la ejecución se frena a mitad de ciclo. |
| **Diseños/mockups** | Solo si es UI. Sin mockup no puedes validar "se ve como debe verse". |
| **Dependencias** | Si depende de otro ticket/servicio y no está dicho, te enteras al ejecutar. |
| **Permisos/seguridad** | Si hay roles involucrados y no están descritos, los casos de permisos no existen — y esos bugs son caros. |

---

## Los tres veredictos

- ✅ **APROBADA** — todo lo obligatorio + condicionales cubiertos. A diseñar casos.
- ⚠️ **APROBADA CON OBSERVACIONES** — lo obligatorio está; faltan condicionales. Se avanza documentando los huecos como preguntas para PO/Dev.
- ❌ **RECHAZADA** — falta al menos un obligatorio. STOP: no se generan casos. Se documenta el rechazo con feedback completo para que el ticket vuelva completo.

> El rechazo no es burocracia: es la jugada que más tiempo ahorra. Un ticket rechazado en 30
> segundos con 6 preguntas concretas para el PO vale más que 20 casos escritos sobre supuestos.

---

*QA Harness Pro · calidadsinhumo.com*
