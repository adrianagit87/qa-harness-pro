#!/usr/bin/env python3
"""Copias sincronizadas de las skills del harness en la carpeta global de Antigravity.

Por qué copias y no symlinks: Antigravity resuelve el symlink y aplica su política de
workspace sobre la ruta REAL. Como el repo del harness queda fuera del workspace abierto,
leer un SKILL.md a través del symlink da "Permission denied — Matches default system policy"
(prueba en vivo del 2026-09-28). Un archivo real en ~/.gemini/config/skills/ sí se lee.

La carpeta es COMPARTIDA con otras herramientas, así que solo se toca lo que se puede probar
que es nuestro: una carpeta con nuestra marca (MARCA) o un symlink de la instalación anterior
que apunta a skills/<nombre> de un clon del harness. Lo demás se avisa y se saltea.

Uso:
  copias_skills.py sincronizar <skills-del-repo> <destino> <skills-previo o ""> <archivo-estado>
  copias_skills.py estado <skills-del-repo> <destino>
  copias_skills.py hash <carpeta>
"""
from __future__ import annotations

import datetime
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

MARCA = ".qa-harness-copia.json"
IGNORAR = {MARCA, "__pycache__", ".DS_Store"}


def huella(carpeta: Path) -> str:
    """sha256 del contenido de la carpeta: rutas relativas + bytes, sin la marca ni basura."""
    h = hashlib.sha256()
    archivos = []
    for raiz, dirs, nombres in os.walk(carpeta):
        dirs[:] = sorted(d for d in dirs if d not in IGNORAR)
        for n in nombres:
            if n not in IGNORAR:
                archivos.append(Path(raiz, n))
    for archivo in sorted(archivos, key=lambda p: p.relative_to(carpeta).as_posix()):
        h.update(archivo.relative_to(carpeta).as_posix().encode("utf-8") + b"\0")
        h.update(archivo.read_bytes() + b"\0")
    return h.hexdigest()


def leer_marca(carpeta: Path) -> dict | None:
    try:
        datos = json.loads((carpeta / MARCA).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return datos if isinstance(datos, dict) and datos.get("qaHarness") == "copia-de-skill" else None


def symlink_del_harness(enlace: Path, nombre: str, repo_skills: Path, previo: str) -> bool:
    """El symlink que dejaba la versión anterior del instalador: apunta a skills/<nombre> de
    este repo, del clon que anotó el sidecar (aunque ya no exista) o de otro clon del harness."""
    destino = os.readlink(enlace).rstrip("/")
    if destino in (str(repo_skills / nombre), f"{previo}/{nombre}" if previo else None):
        return True
    sufijo = f"/skills/{nombre}"
    if destino.startswith("/") and destino.endswith(sufijo):
        return Path(destino[: -len(sufijo)], "adapters", "antigravity", "README.md").is_file()
    return False


def skills_del_repo(repo_skills: Path) -> list[Path]:
    return sorted(p for p in repo_skills.iterdir() if p.is_dir() and not p.name.startswith("."))


def copiar(origen: Path, destino: Path, reemplazar: bool) -> None:
    """Copia completa en una carpeta temporal y recién después la cambia por la vieja: nunca
    queda una copia a medias, y lo que se borró en el repo desaparece de la copia (espejo)."""
    nueva = destino.with_name(f".{destino.name}.qa-harness-nueva")
    vieja = destino.with_name(f".{destino.name}.qa-harness-vieja")
    for resto in (nueva, vieja):
        if resto.exists() or resto.is_symlink():
            shutil.rmtree(resto)
    shutil.copytree(origen, nueva, ignore=shutil.ignore_patterns(*IGNORAR))
    marca = {
        "qaHarness": "copia-de-skill",
        "repo": str(origen.parent.parent),
        "origen": str(origen),
        "hash": huella(origen),
        "instalado": datetime.datetime.now().isoformat(timespec="seconds"),
    }
    (nueva / MARCA).write_text(json.dumps(marca, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if reemplazar:
        if destino.is_symlink():
            destino.unlink()
        else:
            destino.rename(vieja)
    nueva.rename(destino)
    if vieja.exists():
        shutil.rmtree(vieja)


def sincronizar(repo_skills: Path, destino: Path, previo: str, archivo_estado: Path) -> int:
    destino.mkdir(parents=True, exist_ok=True)
    copiadas: list[str] = []
    salteadas = 0
    nombres = set()
    for origen in skills_del_repo(repo_skills):
        nombre = origen.name
        nombres.add(nombre)
        objetivo = destino / nombre
        if objetivo.is_symlink():
            if not symlink_del_harness(objetivo, nombre, repo_skills, previo):
                print(f"   ⚠️  skill:  {nombre} — {objetivo} es un symlink ajeno (→ {os.readlink(objetivo)}): no lo toco.")
                salteadas += 1
                continue
            copiar(origen, objetivo, reemplazar=True)
            print(f"   skill:  {nombre} → copiada (reemplaza el symlink de la instalación anterior)")
        elif objetivo.exists():
            if not objetivo.is_dir() or leer_marca(objetivo) is None:
                print(f"   ⚠️  skill:  {nombre} — {objetivo} ya existe y no es una copia del harness: no lo toco.")
                print(f"       Si es una copia vieja del método, muévela fuera de {destino} y vuelve a correr esto.")
                salteadas += 1
                continue
            if huella(objetivo) == huella(origen) and leer_marca(objetivo).get("origen") == str(origen):
                print(f"   skill:  {nombre} → al día")
            else:
                copiar(origen, objetivo, reemplazar=True)
                print(f"   skill:  {nombre} → copia actualizada")
        else:
            copiar(origen, objetivo, reemplazar=False)
            print(f"   skill:  {nombre} → copiada")
        copiadas.append(nombre)

    # Una skill que ya no existe en el repo: su copia se retira, pero solo si la marca dice que
    # vino de ESTE repo o del que anotó el sidecar. Una copia de otro clon no es asunto nuestro.
    propios = {str(repo_skills)} | ({previo} if previo else set())
    for carpeta in sorted(destino.iterdir()):
        if carpeta.name in nombres or carpeta.is_symlink() or not carpeta.is_dir():
            continue
        marca = leer_marca(carpeta)
        if marca and str(Path(str(marca.get("origen", ""))).parent) in propios:
            shutil.rmtree(carpeta)
            print(f"   skill:  {carpeta.name} → retirada (ya no existe en el repo)")

    archivo_estado.write_text(json.dumps({"copiadas": copiadas, "salteadas": salteadas}), encoding="utf-8")
    return 0


def estado(repo_skills: Path, destino: Path) -> int:
    """Una línea por skill: <nombre>\\t<estado>\\t<detalle>. Estados: ok, falta, symlink,
    ajena, otro-clon, desactualizada."""
    for origen in skills_del_repo(repo_skills):
        objetivo = destino / origen.name
        if objetivo.is_symlink():
            print(f"{origen.name}\tsymlink\t{os.readlink(objetivo)}")
        elif not objetivo.exists():
            print(f"{origen.name}\tfalta\t{objetivo}")
        elif not objetivo.is_dir() or (marca := leer_marca(objetivo)) is None:
            print(f"{origen.name}\tajena\t{objetivo}")
        elif os.path.realpath(str(marca.get("origen", ""))) != os.path.realpath(origen):
            print(f"{origen.name}\totro-clon\t{marca.get('origen', '')}")
        elif huella(objetivo) != huella(origen):
            print(f"{origen.name}\tdesactualizada\t{marca.get('instalado', '')}")
        else:
            print(f"{origen.name}\tok\t{objetivo}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 6 and argv[1] == "sincronizar":
        return sincronizar(Path(argv[2]), Path(argv[3]), argv[4].rstrip("/"), Path(argv[5]))
    if len(argv) == 4 and argv[1] == "estado":
        return estado(Path(argv[2]), Path(argv[3]))
    if len(argv) == 3 and argv[1] == "hash":
        print(huella(Path(argv[2])))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
