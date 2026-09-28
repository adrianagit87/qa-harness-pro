"""Estructura del baseline: solo entra lo que tiene trazabilidad.

El baseline se reconoce por su PRIMERA línea (`MARCA`), no por su ruta: la ruta
la elige cada QA en `baseline.path`, y un `.md` cualquiera del proyecto no tiene
por qué pasar por este chequeo.

Lo que se valida es la forma, nunca el contenido de una regla. Es deliberado:
el gate no puede saber si una regla es cierta, pero sí puede exigir que cada una
diga de qué caso, ticket, fecha y ambiente sale — y eso es lo que impide que
entre una regla inferida sin que nadie lo note.

Formato (el mismo que documenta `templates/09-baseline.md`):

    <!-- qa-harness:baseline v1 -->
    ## VEN-PED — Ventas › Pedidos
    ### VEN-PED-001 — Título corto
    - Estado: vigente | reemplazada por VEN-PED-004
    - Regla: comportamiento observable, en una línea
    - Verificado: TC-994-03 · US-994 · 2026-09-20 · PROD

Lo que va dentro de un bloque de código (```) no se interpreta: ahí vive el
ejemplo del template.

El baseline puede vivir en CUALQUIER ruta (`baseline.path`: relativa a la raíz del
harness, absoluta o con `~`). Por eso, además de la marca, el gate reconoce la
ruta configurada de la empresa activa (`ruta_configurada`), aunque quede fuera
de la raíz del proyecto.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path
from typing import Any

MARCA = "<!-- qa-harness:baseline v1 -->"
PREFIJO_MARCA = "<!-- qa-harness:baseline"

# Un código de módulo: segmentos en mayúscula separados por guion (VEN-PED, CORE).
_CODIGO = r"[A-Z][A-Z0-9]*(?:-[A-Z][A-Z0-9]*)*"
MODULO = re.compile(rf"^## ({_CODIGO}) — (\S.*)$")
REGLA = re.compile(rf"^### ({_CODIGO})-(\d{{3,}}) — (\S.*)$")
ID_REGLA = re.compile(rf"^{_CODIGO}-\d{{3,}}$")
ESTADO = re.compile(r"^- Estado: (vigente|reemplazada por (\S+))$")
TEXTO_REGLA = re.compile(r"^- Regla: (\S.*)$")
VERIFICADO = re.compile(r"^- Verificado: (\S+) · (\S+) · (\d{4}-\d{2}-\d{2}) · (\S+)$")

MAXIMO_DE_PROBLEMAS = 10


@dataclass
class _Regla:
    id: str
    linea: int
    estados: list[str] = field(default_factory=list)
    reemplazo: str | None = None
    tiene_texto: bool = False
    verificaciones: int = 0


def es_baseline(texto: str) -> bool:
    """¿Declara este archivo, en su primera línea, que es un baseline?"""
    primera = texto.lstrip("﻿").split("\n", 1)[0].strip()
    return primera.startswith(PREFIJO_MARCA)


def problemas(texto: str) -> list[str]:
    """Lista de problemas estructurales, vacía si el baseline es válido."""
    lineas = texto.lstrip("﻿").splitlines()
    encontrados: list[str] = []
    if not lineas or lineas[0].strip() != MARCA:
        encontrados.append(f"la primera línea tiene que ser exactamente {MARCA}")

    reglas: list[_Regla] = []
    modulo: str | None = None
    actual: _Regla | None = None
    en_codigo = False

    for numero, cruda in enumerate(lineas[1:], start=2):
        linea = cruda.rstrip()
        if linea.lstrip().startswith("```"):
            en_codigo = not en_codigo
            continue
        if en_codigo:
            continue

        if linea.startswith("# "):
            actual = None
            modulo = None
            continue

        if linea.startswith("## "):
            actual = None
            coincide = MODULO.match(linea)
            modulo = coincide.group(1) if coincide else None
            continue

        if linea.startswith("### "):
            coincide = REGLA.match(linea)
            if not coincide:
                encontrados.append(
                    f"línea {numero}: encabezado de regla mal formado; "
                    "se espera '### <MÓDULO>-<NNN> — <título>'"
                )
                actual = None
                continue
            codigo, correlativo, _ = coincide.groups()
            if modulo is None:
                encontrados.append(
                    f"línea {numero}: la regla {codigo}-{correlativo} no está dentro de "
                    "una sección de módulo '## <CÓDIGO> — <nombre>'"
                )
            elif codigo != modulo:
                encontrados.append(
                    f"línea {numero}: la regla {codigo}-{correlativo} está bajo el módulo "
                    f"{modulo}; su ID tiene que empezar con {modulo}-"
                )
            actual = _Regla(id=f"{codigo}-{correlativo}", linea=numero)
            reglas.append(actual)
            continue

        if actual is None or not linea.strip():
            continue

        if linea.startswith("- Estado:"):
            estado = ESTADO.match(linea)
            actual.estados.append(linea)
            if estado:
                actual.reemplazo = estado.group(2)
            else:
                encontrados.append(
                    f"línea {numero}: 'Estado' de {actual.id} inválido; se espera "
                    "'vigente' o 'reemplazada por <ID>'"
                )
        elif linea.startswith("- Regla:"):
            if TEXTO_REGLA.match(linea):
                actual.tiene_texto = True
        elif linea.startswith("- Verificado:"):
            verificado = VERIFICADO.match(linea)
            if not verificado:
                encontrados.append(
                    f"línea {numero}: 'Verificado' de {actual.id} mal formado; se espera "
                    "'- Verificado: <caso> · <ticket> · <AAAA-MM-DD> · <ambiente>'"
                )
            elif not _fecha_valida(verificado.group(3)):
                encontrados.append(
                    f"línea {numero}: {actual.id} tiene una fecha que no existe "
                    f"({verificado.group(3)})"
                )
            else:
                actual.verificaciones += 1
        else:
            encontrados.append(
                f"línea {numero}: línea no reconocida dentro de {actual.id}; una regla solo "
                "lleva 'Estado', 'Regla' y 'Verificado'"
            )

    encontrados.extend(_problemas_de_reglas(reglas))
    return encontrados


def _problemas_de_reglas(reglas: list[_Regla]) -> list[str]:
    encontrados: list[str] = []
    por_id: dict[str, _Regla] = {}
    for regla in reglas:
        if regla.id in por_id:
            encontrados.append(
                f"línea {regla.linea}: el ID {regla.id} está repetido "
                f"(ya aparece en la línea {por_id[regla.id].linea}); los IDs no se reutilizan"
            )
        else:
            por_id[regla.id] = regla

    for regla in reglas:
        if len(regla.estados) != 1:
            encontrados.append(
                f"{regla.id}: necesita exactamente una línea "
                "'- Estado: vigente' o '- Estado: reemplazada por <ID>'"
            )
        if not regla.tiene_texto:
            encontrados.append(f"{regla.id}: falta la línea '- Regla: <comportamiento>'")
        if regla.verificaciones == 0:
            encontrados.append(
                f"{regla.id}: falta al menos una línea "
                "'- Verificado: <caso> · <ticket> · <AAAA-MM-DD> · <ambiente>'"
            )
        if regla.reemplazo is not None:
            encontrados.extend(_problemas_de_reemplazo(regla, por_id))
    return encontrados


def _problemas_de_reemplazo(regla: _Regla, por_id: dict[str, _Regla]) -> list[str]:
    destino = regla.reemplazo
    if destino is None:
        return []
    if not ID_REGLA.match(destino):
        return [f"{regla.id}: 'reemplazada por {destino}' no es un ID de regla válido"]
    if destino == regla.id:
        return [f"{regla.id}: una regla no puede reemplazarse a sí misma"]
    if destino not in por_id:
        return [f"{regla.id}: está reemplazada por {destino}, que no existe en el baseline"]

    visitadas = {regla.id}
    siguiente: str | None = destino
    while siguiente is not None and siguiente in por_id:
        if siguiente in visitadas:
            return [f"{regla.id}: la cadena de reemplazos vuelve sobre sí misma ({siguiente})"]
        visitadas.add(siguiente)
        siguiente = por_id[siguiente].reemplazo
    return []


def _fecha_valida(valor: str) -> bool:
    try:
        date.fromisoformat(valor)
    except ValueError:
        return False
    return True


def motivo(texto: str) -> str | None:
    """Motivo de bloqueo en texto plano, o None si el baseline es válido."""
    encontrados = problemas(texto)
    if not encontrados:
        return None
    visibles = encontrados[:MAXIMO_DE_PROBLEMAS]
    resto = len(encontrados) - len(visibles)
    lineas = [f"- {problema}" for problema in visibles]
    if resto:
        lineas.append(f"- … y {resto} problema(s) más")
    return "\n".join(lineas)


def ruta_configurada(raiz_harness: Any) -> Path | None:
    """Ruta resuelta del baseline de la empresa activa, o None si no hay uno encendido.

    profile/profile.json -> activeCompany -> companies/<empresa>.json -> baseline.
    Solo cuenta con `enabled: true`. Cualquier cosa ilegible devuelve None: sin
    config, el gate se comporta exactamente como si la función no existiera.
    """
    if not isinstance(raiz_harness, (str, Path)):
        return None
    try:
        raiz = Path(raiz_harness).resolve()
        perfil = _leer_json(raiz / "profile" / "profile.json")
        empresa = perfil.get("activeCompany") if isinstance(perfil, dict) else None
        if not isinstance(empresa, str) or not empresa.strip():
            return None
        empresa = empresa.strip()
        if "/" in empresa or "\\" in empresa or empresa.startswith("."):
            return None
        config = _leer_json(raiz / "companies" / f"{empresa}.json")
        bloque = config.get("baseline") if isinstance(config, dict) else None
        if not isinstance(bloque, dict) or bloque.get("enabled") is not True:
            return None
        ruta = bloque.get("path")
        if not isinstance(ruta, str) or not ruta.strip():
            return None
        candidata = Path(ruta.strip()).expanduser()
        if not candidata.is_absolute():
            candidata = raiz / candidata
        return candidata.resolve()
    except (OSError, ValueError, RuntimeError):
        return None


def _leer_json(ruta: Path) -> Any:
    with open(ruta, encoding="utf-8") as archivo:
        return json.load(archivo)
