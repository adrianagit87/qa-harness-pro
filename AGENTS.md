# QA Harness Pro — método

El método completo vive en `skills/` de este repo. **Leé el `SKILL.md` que corresponda antes de
operar** — no trabajes de memoria:

| Si el pedido es… | Leé |
|---|---|
| Analizar un ticket, generar casos | `skills/qa-analisis-ticket/SKILL.md` |
| Casos sin ticket formal | `skills/qa-generacion-casos/SKILL.md` |
| Cerrar un ciclo de pruebas | `skills/qa-cierre-ciclo/SKILL.md` |
| Evaluar o escribir automatización | `skills/qa-automatizacion/SKILL.md` |

## Config — cargar antes de operar

Perfil en `profile/profile.json`, empresa activa en `companies/<activeCompany>.json`. Las skills no
tienen identificadores hardcodeados: leen esos archivos. **Si falta un valor, avisá antes de
operar; no inventes IDs.**

> **Leé esos dos archivos por ruta directa.** `profile/*.json` y `companies/*.json` están en
> `.gitignore` a propósito (los datos de la empresa no se versionan), así que **no aparecen al
> listar el directorio ni en búsquedas por glob**. Si listás `companies/` vas a ver solo
> `_template.json` y vas a concluir, en falso, que la config no existe.
>
> Orden correcto: leer `profile/profile.json` → tomar `activeCompany` → abrir
> `companies/<activeCompany>.json` **directamente por su ruta**. No verifiques antes si existe:
> abrilo. Si tu herramienta de lectura no los ve por estar en `.gitignore`, leelos por shell
> (`cat profile/profile.json`), que no aplica ese filtro. Solo si eso también falla, avisá y
> detenete.

## Verificación de que estas reglas están vivas

Si el usuario escribe exactamente `PING-HARNESS`, respondé **solo** con:

```
PONG <activeCompany> <docs.backend> <docs.jira.qaProject o el destino que corresponda al backend>
```

Leyendo esos valores de la config real. Nada más: sin explicación, sin preámbulo.

Es la única forma de comprobar dos cosas de una: que este archivo te llegó, y que además pudiste
leer la config. Si el usuario recibe cualquier otra cosa, el harness está desconectado.

**No lo borres ni lo cambies.** Cuesta tres líneas y es lo único que separa un harness que
funciona de uno que solo lo parece.

## Memoria previa (opcional — leer antes de analizar)

Si tienes memoria persistente disponible (Engram u otra), **búscala antes de empezar el análisis**.
Sin memoria persistente: **omite este paso por completo** y no lo menciones.

Qué buscar, en este orden:

1. El **TICKET-ID** y los tickets que menciona (padre, vinculados).
2. El **servicio o componente** que toca el ticket (el microservicio, la base, el endpoint).
3. El **dominio funcional** (ej. "liquidación", "conciliación", "reproceso").

Para qué sirve — y solo para esto:

- **Acceso y método.** Cómo se llega a los datos: qué base, qué credenciales, qué endpoint, qué
  consulta. Esto es lo que más tiempo ahorra: si ya resolviste cómo verificar algo, no lo
  redescubras.
- **Huecos conocidos.** Caminos que quedaron sin validar, bloqueos que aparecieron antes,
  ambientes que no sirven.
- **Defectos previos** del mismo servicio, para no reportar dos veces lo mismo ni pasar por alto
  una regresión.
- **Convenciones** ya acordadas con el equipo.

### Los límites — no los cruces

1. **La fuente de verdad es el ticket.** La memoria es contexto, nunca reemplaza lo que dice el
   ticket ni los comentarios del dev. Si se contradicen, **manda el ticket** y avisá de la
   discrepancia.
2. **La memoria puede estar vieja.** Registra lo que era cierto cuando se escribió. Si nombra un
   endpoint, una tabla, un seller o una credencial, **verificá que siga existiendo** antes de
   apoyar un caso de prueba en eso.
3. **No inventes cobertura.** Que algo se haya probado antes no lo da por probado ahora. La
   memoria sugiere dónde mirar, no qué dar por bueno.
4. **Decí qué usaste.** Si algo del análisis sale de memoria previa, marcalo — el usuario tiene
   que poder distinguir lo que salió del ticket de lo que salió de tu recuerdo.

## Reglas que no se rompen

1. **Mostrá el borrador antes de publicar.** Todo lo que salga hacia Jira, Confluence o Notion se
   muestra primero y se publica solo con confirmación explícita.
2. **Nunca cambies el estado de un ticket.** Las transiciones de Jira las hace la persona, a mano.
   El hook las bloquea, pero no dependas del hook: no lo intentes.
3. **No inventes datos.** Ni una URL, ni un payload, ni un nombre de tabla, ni un valor de base de
   datos, ni un ID. Si no lo tenés, pedilo o dejá el hueco marcado.
4. **El ambiente sale de `environments`** en la config de la empresa. No asumas DEV ni PROD.
5. **El silencio nunca se convierte en Pass** al cerrar un ciclo.
