"""Núcleo del harness: la lógica que no depende de ningún runtime.

Los hooks de `adapters/claude/hooks/`, `adapters/cursor/hooks/` y
`adapters/antigravity/hooks/` son adaptadores:
leen la entrada con la forma de su runtime, llaman acá y proyectan el veredicto
a la salida que ese runtime entiende. Las decisiones viven en un solo lugar.
"""
