@/AGENTS.md

# QA Harness Pro

La línea de arriba importa la fuente única de reglas. El método, la carga de config y las reglas
que no se rompen viven en **`AGENTS.md`**, en la raíz de este repo. **Léelo antes de operar.** No
repitas su contenido acá ni trabajes de memoria.

Esta rule existe solo como red. Verificado el 2026-09-18 contra Antigravity IDE: `AGENTS.md`
aparece en el panel de Customizations como regla de proyecto por sí solo, sin este archivo. Pero
ese comportamiento no está en la documentación oficial —la que sí documenta `.agents/rules/` como
la ubicación de las reglas del workspace—, así que acá queda el camino documentado por si tu
versión no lo hace. Si las dos rutas cargan, lees lo mismo dos veces y no pasa nada.
