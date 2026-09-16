# 5 errores que cometí usando IA para testing (y que tú vas a cometer si no lees esto)

Estos errores no son teóricos: los cometí trabajando, con tickets reales. El harness está diseñado
para protegerte de varios de ellos — pero la protección final eres tú.

---

## Error 1: Aceptar todo lo que genera sin revisar

La primera semana usé los casos de prueba tal cual los generaba la IA. Sin revisarlos. Se me coló un caso que decía "verificar que el usuario puede hacer login con credenciales válidas" sin especificar QUÉ credenciales. ¿Email o username? ¿Password con caracteres especiales? Cuando lo ejecuté, me di cuenta de que el caso no probaba nada concreto.

**La regla:** La IA genera borradores. Tú eres el filtro. Siempre revisa los datos de prueba concretos y los resultados esperados.

## Error 2: Pedirle que genere TODO

"Dame todos los casos de prueba posibles para este formulario de registro." Me generó 43 casos. Para un formulario de 4 campos. Incluía cosas como "verificar que el formulario se muestra correctamente en un monitor de 4K con zoom al 75%". Nadie va a ejecutar 43 casos.

**La regla:** Pon límites siempre. "Máximo 15 casos, priorizados por riesgo" te da el 80% del valor en el 20% del esfuerzo. (Las skills del harness ya traen ese límite: ~10–25 casos según alcance.)

## Error 3: No darle contexto de negocio

Le pedía "genera casos para un endpoint de inscripción a cursos" y me daba casos técnicos genéricos: campo vacío, tipo incorrecto, servidor no disponible. Correctos pero inútiles. El bug que llegó a producción fue: "un usuario se inscribió a un curso avanzado sin haber completado el prerequisito". La IA no podía adivinarlo porque yo no le dije que existían prerequisitos.

**La regla:** Las reglas de negocio son más importantes que la descripción técnica. Si hay prerequisitos, límites de cupo, horarios, permisos especiales — dilo. La IA no lee la mente ni el Confluence de tu equipo. (Por eso el harness carga tu config de empresa: cuanto más contexto tenga, mejores casos.)

## Error 4: Usar la IA para decidir QUÉ probar

Esto es lo más peligroso. Le pregunté "¿qué debería probar de este release?" y me dio una lista razonable. Pero no incluyó el módulo de notificaciones — porque no lo mencioné y no estaba en los cambios del release. Resulta que el refactor del módulo de usuarios afectaba las notificaciones por un servicio compartido. Llegó un bug a producción.

**La regla:** La IA te ayuda con el CÓMO (generar casos, documentar, automatizar). El QUÉ probar lo decides tú, basándote en tu conocimiento del sistema, el historial de bugs, y tu instinto. Eso no se delega.

## Error 5: Ignorar lo que la IA no sabe

La IA no sabe que tu equipo deployó un hotfix el martes que rompió las sesiones. No sabe que el PO cambió un criterio de aceptación en una conversación de Slack que nunca se documentó. No sabe que el ambiente de staging lleva 3 días caído. No sabe que el dev que escribió ese módulo se fue de la empresa y nadie entiende el código.

**La regla:** La IA trabaja con lo que le das. Si le das información incompleta, genera resultados incompletos que *parecen* completos. Eso es más peligroso que no usar IA — porque te da falsa confianza.

---

# Cuándo NO usar IA para testing

Saber cuándo NO usarla es tan importante como saber cuándo sí:

- **Testing exploratorio.** Necesitas intuición, curiosidad, y la habilidad de decir "esto se siente raro". La IA no tiene intuición.
- **Evaluar la experiencia de usuario.** "¿Esto es confuso?" es una pregunta humana. La IA puede verificar que el botón existe, no que tiene sentido.
- **Decidir la prioridad real de un bug.** La IA dice "severidad media" basándose en la descripción. Tú sabes que ese flujo lo usa el cliente más grande y que si falla un viernes van a llamar al CEO. Eso cambia la severidad a crítica.
- **Cuestionar el requerimiento.** "¿Realmente necesitamos esto?" No es una pregunta de testing, es una pregunta de negocio. Y es la pregunta más valiosa que un QA puede hacer.

---

*QA Harness Pro · calidadsinhumo.com*
