"""Gate de SQL: la IA consulta la base de un ambiente de prueba, y solo para leer.

Reglas, en este orden:

1. **Qué base.** Solo el MCP de Postgres que un ambiente de prueba declara en
   `environments.list[].database`. La base de un ambiente con `production: true`
   se bloquea siempre, y un server que ningún ambiente declara también.

2. **Qué herramienta.** Solo `pg_execute_query`. Las demás del server (SQL libre,
   mutaciones, gestión de esquema o usuarios, import/export) se bloquean.
   Tampoco se acepta `connectionString`: con ese parámetro una llamada "a DEV"
   puede terminar en cualquier otra base.

3. **Qué consulta.** Una sola sentencia que empieza con SELECT o WITH, sin
   cláusulas que escriban o bloqueen filas, y sin funciones que lean archivos
   del servidor, cambien la sesión o ejecuten SQL que viene en un texto.

Este gate es una segunda capa. La frontera real es el permiso en la base: el MCP
tiene que conectarse con un usuario de solo lectura. Una función propia de la
base que escribe no se puede detectar mirando el texto de la consulta.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

from . import contract, empresa
from .catalogo import SQL_LECTURA, canonico_sql

MAX_LARGO = 20_000
OPERACIONES = frozenset({"select", "count", "exists"})

_NOMBRE_DE_SERVER = re.compile(r"[A-Za-z0-9_-]+")

# Con una sola sentencia que empieza con SELECT o WITH, lo que todavía puede
# escribir o bloquear es: un CTE con INSERT/UPDATE/DELETE/MERGE, SELECT INTO
# (crea una tabla) y FOR UPDATE/SHARE (bloquea filas). Se buscan como palabra
# suelta después de sacar comentarios y textos: un `WHERE estado = 'deleted'` pasa.
_PROHIBIDA = re.compile(r"\b(insert|update|delete|merge|into)\b")
_FOR_SHARE = re.compile(r"\bfor\s+(?:no\s+key\s+|key\s+)?share\b")

# Funciones que leen archivos del servidor, escriben, frenan la base o ejecutan
# SQL que llega como texto (y que este gate no puede revisar).
_FUNCION_PROHIBIDA = re.compile(
    r"\b(pg_read_file|pg_read_binary_file|pg_ls_\w+|pg_stat_file|lo_\w+|dblink\w*|"
    r"query_to_xml\w*|cursor_to_xml\w*|set_config|nextval|setval|pg_sleep\w*|"
    r"pg_terminate_backend|pg_cancel_backend|pg_reload_conf|pg_rotate_logfile|"
    r"pg_switch_wal|pg_create_\w+|pg_drop_\w+|pg_advisory\w*|pg_try_advisory\w*|"
    r"pg_notify|pg_logical_\w+|pg_replication_\w+|txid_current|pg_current_xact_id)\s*\("
)

# Una sola pasada de izquierda a derecha: lo que aparece primero manda. Así un
# `--` dentro de un texto no es un comentario, ni una comilla dentro de un
# comentario abre un texto. Los textos y los identificadores entre comillas se
# reemplazan por un valor neutro; los comentarios, por un espacio.
_PIEZA_OPACA = re.compile(
    r"(?P<texto>(?:(?<!\w)(?:[eEbBxXnN]|[uU]&))?'(?:[^']|'')*')"
    r"|(?P<ident>\"(?:[^\"]|\"\")*\")"
    r"|(?P<linea>--[^\n]*)"
    r"|(?P<bloque>/\*.*?\*/)",
    re.DOTALL,
)
_DOLAR = re.compile(r"\$[A-Za-z_]?\w*\$")


def _sin_textos_ni_comentarios(texto: str) -> str:
    def neutro(pieza: re.Match[str]) -> str:
        if pieza.group("texto"):
            return " 0 "
        if pieza.group("ident"):
            return " x "
        return " "

    return _PIEZA_OPACA.sub(neutro, texto)


@dataclass(frozen=True)
class Bases:
    """Qué servers de base declara la empresa activa, separados por tipo de ambiente."""

    prueba: frozenset[str] = frozenset()
    produccion: frozenset[str] = frozenset()
    error: str = ""


def bases_de_config(config: Any) -> Bases:
    """Servers de `environments.list[].database`. Uno de producción es producción."""
    prueba: set[str] = set()
    produccion: set[str] = set()
    for ambiente in empresa.ambientes(config):
        server = ambiente.get("database")
        if isinstance(server, str) and _NOMBRE_DE_SERVER.fullmatch(server.strip()):
            (produccion if ambiente.get("production") is True else prueba).add(server.strip())
    return Bases(frozenset(prueba - produccion), frozenset(produccion))


def cargar_bases(raiz_harness: Any) -> Bases:
    config, error = empresa.leer_config_activa(raiz_harness)
    if config is None:
        return Bases(error=error)
    return bases_de_config(config)


def revisar_consulta(texto: Any) -> contract.Verdict:
    """¿Es una sola sentencia de lectura?"""
    if not isinstance(texto, str) or not texto.strip():
        return contract.bloquear("la consulta está vacía o no es texto.")
    if len(texto) > MAX_LARGO:
        return contract.bloquear(f"la consulta tiene más de {MAX_LARGO} caracteres; pártela.")
    if _DOLAR.search(texto):
        return contract.bloquear("los textos con $$ (dollar quoting) no se aceptan: no se pueden revisar.")

    limpio = _sin_textos_ni_comentarios(texto)
    if "/*" in limpio or "*/" in limpio:
        return contract.bloquear("la consulta tiene un comentario /* */ anidado o sin cerrar.")
    if "'" in limpio or '"' in limpio:
        return contract.bloquear("la consulta tiene comillas sin cerrar.")
    limpio = limpio.strip().lower()
    if limpio.endswith(";"):
        limpio = limpio[:-1].rstrip()
    if ";" in limpio:
        return contract.bloquear("solo se ejecuta una sentencia por llamada (hay más de un ';').")
    if not re.match(r"\(*\s*(select|with)\b", limpio):
        return contract.bloquear("solo se aceptan consultas que empiezan con SELECT o WITH.")

    palabra = _PROHIBIDA.search(limpio) or _FOR_SHARE.search(limpio)
    if palabra:
        return contract.bloquear(
            f"la consulta usa «{palabra.group(0).upper()}»: solo se lee, nunca se escribe ni se bloquea."
        )
    funcion = _FUNCION_PROHIBIDA.search(limpio)
    if funcion:
        return contract.bloquear(
            f"la consulta usa {funcion.group(1)}(): lee archivos del servidor, escribe o ejecuta SQL "
            "que no se puede revisar."
        )
    return contract.permitir()


def revisar_accion(nombre: Any, entrada: Any, bases: Bases) -> contract.Verdict:
    """Veredicto para una llamada a una tool de un MCP de Postgres."""
    canonico = canonico_sql(nombre)
    if canonico is None:
        return contract.abstenerse("no es una tool de un MCP de Postgres.")
    server, tool = canonico
    if bases.error:
        return contract.bloquear(bases.error)
    if server in bases.produccion:
        return contract.bloquear(
            f"«{server}» es la base de PRODUCCIÓN. La IA no consulta producción, ni para leer."
        )
    if server not in bases.prueba:
        return contract.bloquear(
            f"«{server}» no es la base de ningún ambiente de la empresa activa "
            "(environments.list[].database). Solo se consulta la base declarada."
        )
    if tool != SQL_LECTURA:
        return contract.bloquear(
            f"{tool} no está permitida: solo {SQL_LECTURA}, para leer. Nada de SQL libre, "
            "mutaciones ni gestión de la base."
        )
    if not isinstance(entrada, dict):
        return contract.bloquear("la entrada de la consulta es ilegible.")
    if "connectionString" in entrada:
        return contract.bloquear(
            "connectionString no se acepta: la consulta va a la base del server declarado y a ninguna otra."
        )
    if entrada.get("operation") not in OPERACIONES:
        return contract.bloquear("operation tiene que ser select, count o exists.")
    return revisar_consulta(entrada.get("query"))
