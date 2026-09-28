"""Los tres quality gates del harness, sin entrada/salida de ningún runtime.

  destructivos  — lo irreversible no se ejecuta solo.
  publicacion   — nada sale a Jira/Confluence/Notion a medio hacer.
  post_edicion  — un cambio que rompe algo se detecta en el acto.
                  (incluye la estructura del baseline: `baseline`)
                  `post_shell` le lleva lo que escribe un comando de
                  shell, con una foto del disco antes y después.

Todos responden un `Verdict` de `contract`; ninguno imprime nada.
"""
