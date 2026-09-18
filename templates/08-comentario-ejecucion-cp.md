# Template: Comentario de Ejecución de un CP

> **Lo usa [[qa-cierre-ciclo]]** (Paso 4) como comentario en cada issue hijo cuando
> `docs.backend = jira`. Respeta este formato, que es el que el equipo ya usa.
> Las reglas de qué se puede escribir y qué no viven en el `SKILL.md`, no acá.

---

```markdown
## Ejecución [CP_ID] — [YYYY-MM-DD]

**Resultado: ✅ PASS / ❌ FAIL / ⏭️ Bloqueado / ⏸️ No ejecutado**

### Pasos ejecutados
1. [paso]

### Validaciones
| # | Capa | Query | Resultado |
| --- | --- | --- | --- |
| 1 | [capa] | `[query o endpoint]` | [resultado real observado] ✅ |

### Observaciones
* [Hallazgo, o "Sin observaciones"]

### Conclusión
[Una o dos frases.]
```
