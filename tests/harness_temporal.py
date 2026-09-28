"""Un harness de mentira en un directorio temporal, con su propia config.

Los hooks leen la config desde la raíz del harness donde viven (la que
encuentran subiendo hasta `core/gates/contract.py`). Para probar el baseline
configurado sin tocar el `profile/` real de quien corre la suite, se copia
`core/` y los hooks de un adaptador a un directorio temporal y se escribe ahí
una config propia.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

RAIZ_REAL = Path(__file__).resolve().parents[1]

BASELINE_VALIDO = """<!-- qa-harness:baseline v1 -->
# Baseline

## VEN-PED — Ventas › Pedidos

### VEN-PED-001 — Sin stock no se confirma
- Estado: vigente
- Regla: Un pedido con un ítem sin stock no se puede confirmar.
- Verificado: TC-994-03 · US-994 · 2026-09-20 · PROD
"""

BASELINE_ROTO = BASELINE_VALIDO.replace(
    "- Verificado: TC-994-03 · US-994 · 2026-09-20 · PROD\n", ""
)


def escribir_config(raiz: Path, baseline: object | None, empresa: str = "acme") -> None:
    """profile/profile.json + companies/<empresa>.json; `baseline=None` omite el bloque."""
    (raiz / "profile").mkdir(parents=True, exist_ok=True)
    (raiz / "companies").mkdir(parents=True, exist_ok=True)
    (raiz / "profile" / "profile.json").write_text(
        json.dumps({"name": "Ana QA", "activeCompany": empresa}), encoding="utf-8"
    )
    config: dict = {"company": {"name": "Acme", "key": "ACME"}}
    if baseline is not None:
        config["baseline"] = baseline
    (raiz / "companies" / f"{empresa}.json").write_text(json.dumps(config), encoding="utf-8")


def copiar_harness(destino: Path, adaptador: str) -> Path:
    """Copia core/ y los hooks del adaptador; devuelve la carpeta de hooks copiada."""
    shutil.copytree(RAIZ_REAL / "core", destino / "core", ignore=shutil.ignore_patterns("__pycache__"))
    hooks = destino / "adapters" / adaptador / "hooks"
    shutil.copytree(
        RAIZ_REAL / "adapters" / adaptador / "hooks", hooks, ignore=shutil.ignore_patterns("__pycache__")
    )
    return hooks
