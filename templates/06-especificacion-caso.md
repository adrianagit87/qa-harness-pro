# Template: Especificación de Caso de Prueba (CP)

> **Lo usa [[qa-analisis-ticket]]** como descripción de cada issue hijo cuando
> `docs.backend = jira`. Respeta estos encabezados y su orden: es el formato que el equipo ya usa.
> Las reglas de cuándo omitir secciones viven en el `SKILL.md`, no acá.

---

## Objetivo
[Qué valida este caso, en una frase.]

## Fase
[Fase o agrupación a la que pertenece, si aplica.]

## Precondiciones
* [Estado de datos / configuración / despliegue necesario]

## Datos de entrada
* **[campo]:** `[valor]`

## Endpoint
```
[MÉTODO] [URL]
Content-Type: application/json
```

## Payload
```json
[payload completo]
```

## Resultado esperado
* [Condición verificable 1]
* [Condición verificable 2]

## Queries de validación

### 1. [Capa / servicio]
```sql
[SQL]
```

## Resultado obtenido
[Se completa al ejecutar — lo llena el cierre de ciclo, no el análisis.]
