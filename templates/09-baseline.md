<!-- qa-harness:baseline v1 -->
# Baseline

> **Lo escribe [[qa-baseline]]** al consolidar un ticket aprobado en el ambiente final, y lo lee
> [[qa-analisis-ticket]] antes de analizar. Este archivo es la **fuente única**: el espejo en
> Notion o Confluence, si lo hay, se publica desde acá y nunca se lee de vuelta.
>
> - Solo entra comportamiento verificado por casos ✅ Pass. Nada inferido, nada de memoria.
> - Los IDs de regla son permanentes: nunca se renumeran ni se reutilizan.
> - Una regla que cambia no se borra: queda `reemplazada por <ID nuevo>` y la nueva la sustituye.
> - El gate post-edición valida el formato en cada cambio. La primera línea (la marca
>   `qa-harness:baseline v1`) es lo que lo identifica como baseline: no la borres.

## Formato

Un módulo por sección `##` (el código sale de `baseline.modules` en la config), una regla por
sección `###` dentro de su módulo. El ID de la regla es `<CÓDIGO DEL MÓDULO>-<NNN>`. Una regla
lleva solo estas tres líneas; `Verificado` se repite si otro ticket vuelve a confirmar la regla
sin cambiarla.

```
## VEN-PED — Ventas › Pedidos

### VEN-PED-001 — Un pedido con un ítem sin stock no se puede confirmar
- Estado: reemplazada por VEN-PED-004
- Regla: Al confirmar un pedido con un ítem sin stock, el sistema rechaza la confirmación.
- Verificado: TC-994-03 · US-994 · 2026-09-20 · PROD

### VEN-PED-004 — Un pedido con un ítem sin stock se confirma como pendiente
- Estado: vigente
- Regla: Al confirmar un pedido con un ítem sin stock, el pedido queda en estado Pendiente.
- Verificado: TC-1102-02 · US-1102 · 2026-10-05 · PROD
```

<!-- Los módulos consolidados van debajo de esta línea, uno por sección ##. -->
