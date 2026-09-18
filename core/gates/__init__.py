"""Los tres quality gates del harness, sin entrada/salida de ningún runtime.

  destructivos  — lo irreversible no se ejecuta solo.
  publicacion   — nada sale a Jira/Confluence/Notion a medio hacer.
  post_edicion  — un cambio que rompe algo se detecta en el acto.

Todos responden un `Verdict` de `contract`; ninguno imprime nada.
"""
