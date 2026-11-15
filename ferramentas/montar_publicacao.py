#!/usr/bin/env python3
"""Mik Seifador - monta a pasta kit/ e o manifest.json do repositório de atualizações.

Uso:
  montar_publicacao.py --kit <MultitrackAoVivo> --keymap <MultitrackAoVivo.ReaperKeyMap>
                       --repo <pasta do repositório> [--build N] [--ref SHA] [--notas "..."]
                       [--so-manifest]
Sem --build: usa build do manifest atual + 1 (ou 1).
"""
import argparse, hashlib, json, os, shutil, sys
from datetime import datetime, timezone, timedelta

EXCL_DIRS = ("bak-", "_backups", "_atualizacao", "click_gerado", "pads", "guia_voz",
             "__pycache__", "peaks")
EXCL_ARQ = ("build.txt", "atualizacao_local.json")

def ok_nome(n):
    b = n.lower()
    if ".bak" in b or ".original" in b or b.endswith(".pdf") or b.startswith("como usar"):
        return False
    if b.startswith("teste") or b.startswith("test_") or b.startswith("_") or b.endswith(".upd-old"):
        return False
    return True

def arquivos_do_kit(kit):
    out = []
    for n in sorted(os.listdir(kit)):
        p = os.path.join(kit, n)
        if os.path.isfile(p) and n.lower().endswith(".lua") and ok_nome(n) and n not in EXCL_ARQ:
            out.append(n)
    sep = os.path.join(kit, "separador")
    if os.path.isdir(sep):
        for n in sorted(os.listdir(sep)):
            if os.path.isfile(os.path.join(sep, n)) and os.path.splitext(n)[1].lower() in (".py", ".ps1", ".sh", ".txt") and ok_nome(n):
                out.append("separador/" + n)
    rw = os.path.join(kit, "remoto_web")
    for raiz, dirs, files in os.walk(rw):
        dirs[:] = sorted(d for d in dirs if not d.startswith(EXCL_DIRS) and ".bak" not in d)
        for n in sorted(files):
            if ok_nome(n):
                rel = os.path.relpath(os.path.join(raiz, n), kit).replace(os.sep, "/")
                out.append(rel)
    return out

def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kit", required=True)
    ap.add_argument("--keymap")
    ap.add_argument("--repo", required=True)
    ap.add_argument("--build", type=int)
    ap.add_argument("--ref", default="main")
    ap.add_argument("--notas", default="")
    ap.add_argument("--so-manifest", action="store_true")
    a = ap.parse_args()
    man_p = os.path.join(a.repo, "manifest.json")
    build = a.build
    if build is None:
        try:
            build = int(json.load(open(man_p, encoding="utf-8-sig"))["build"]) + 1
        except Exception:
            build = 1
    dst_kit = os.path.join(a.repo, "kit", "Scripts", "MultitrackAoVivo")
    if not a.so_manifest:
        if os.path.isdir(dst_kit):
            shutil.rmtree(dst_kit)
        for rel in arquivos_do_kit(a.kit):
            d = os.path.join(dst_kit, rel)
            os.makedirs(os.path.dirname(d), exist_ok=True)
            shutil.copy2(os.path.join(a.kit, rel), d)
        if a.keymap:
            dk = os.path.join(a.repo, "kit", "KeyMaps")
            os.makedirs(dk, exist_ok=True)
            shutil.copy2(a.keymap, os.path.join(dk, "MultitrackAoVivo.ReaperKeyMap"))
    arqs = []
    base = os.path.join(a.repo, "kit")
    for raiz, dirs, files in os.walk(base):
        dirs.sort()
        for n in sorted(files):
            p = os.path.join(raiz, n)
            rel = os.path.relpath(p, base).replace(os.sep, "/")
            arqs.append({"caminho": rel, "sha256": sha256(p), "tamanho": os.path.getsize(p)})
    agora = datetime.now(timezone(timedelta(hours=-3)))
    man = {"versao": "1.8", "build": build, "data": agora.strftime("%Y-%m-%dT%H:%M:%S-03:00"),
           "ref": a.ref, "arquivos": arqs, "notas": a.notas}
    with open(man_p, "w", encoding="utf-8", newline="\n") as f:
        json.dump(man, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"build={build} arquivos={len(arqs)} ref={a.ref}")

if __name__ == "__main__":
    main()
