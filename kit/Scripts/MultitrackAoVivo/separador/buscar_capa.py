#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Busca a capa da música no YouTube (miniatura) e grava capa.jpg na pasta.
Roda sozinho, em segundo plano. Sem internet ou sem resultado: sai sem erro
e sem gravar arquivo quebrado.
"""
from __future__ import annotations

import argparse
import json
import os
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

# v1.8: no Windows, todo subprocesso (ffmpeg, yt-dlp, powershell, audio-separator,
# pydub...) roda oculto, sem janela preta de prompt. Vale também para o que as
# bibliotecas abrem por dentro (pydub/audio-separator chamam o ffmpeg).
def _subprocessos_ocultos():
    if os.name != "nt":
        return
    try:
        import subprocess
        if getattr(subprocess.Popen, "_mik_oculto", False):
            return
        _orig = subprocess.Popen.__init__

        def _init(self, *a, **kw):
            try:
                fl = kw.get("creationflags", 0) or 0
                if not (fl & 0x00000010):  # CREATE_NEW_CONSOLE pedido de propósito: respeita
                    kw["creationflags"] = fl | 0x08000000  # CREATE_NO_WINDOW
                si = kw.get("startupinfo")
                if si is None:
                    si = subprocess.STARTUPINFO()
                    kw["startupinfo"] = si
                si.dwFlags |= subprocess.STARTF_USESHOWWINDOW
                si.wShowWindow = 0  # SW_HIDE
            except Exception:
                pass
            _orig(self, *a, **kw)

        subprocess.Popen.__init__ = _init
        subprocess.Popen._mik_oculto = True
    except Exception:
        pass


_subprocessos_ocultos()

TIMEOUT_BUSCA = 45
TIMEOUT_HTTP = 20
MIN_BYTES = 4000

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; 64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

CTX = ssl.create_default_context()


def log(msg: str, fh=None) -> None:
    linha = time.strftime("%Y-%m-%d %H:%M:%S") + " " + str(msg)
    try:
        sys.stdout.write(linha + "\n")
        sys.stdout.flush()
    except Exception:
        pass
    if fh:
        try:
            fh.write(linha + "\n")
            fh.flush()
        except Exception:
            pass


def ler_pedido(path: Path) -> dict:
    dados = {}
    txt = path.read_text(encoding="utf-8-sig")
    for ln in txt.splitlines():
        if "=" in ln and not ln.strip().startswith("#"):
            k, v = ln.split("=", 1)
            dados[k.strip().lower()] = v.strip()
    return dados


def ferramentas_dir() -> Path:
    base = os.environ.get("LOCALAPPDATA") or os.environ.get("HOME") or str(Path.home())
    if os.name == "nt":
        d = Path(base) / "MikSeifador" / "ferramentas"
    else:
        d = Path(base) / "Library" / "Application Support" / "MikSeifador" / "ferramentas"
    d.mkdir(parents=True, exist_ok=True)
    return d


def achar_yt_dlp() -> str | None:
    exe = "yt-dlp.exe" if os.name == "nt" else "yt-dlp"
    cands = []
    here = Path(__file__).resolve().parent
    cands.append(ferramentas_dir() / exe)
    cands.append(here / exe)
    # PATH
    for p in os.environ.get("PATH", "").split(os.pathsep):
        if p:
            cands.append(Path(p) / exe)
            cands.append(Path(p) / "yt-dlp")
    for c in cands:
        try:
            if c.is_file() and os.access(c, os.X_OK if os.name != "nt" else os.F_OK):
                return str(c)
        except Exception:
            continue
    return None


def baixar_yt_dlp(logf=None) -> str | None:
    dest = ferramentas_dir() / ("yt-dlp.exe" if os.name == "nt" else "yt-dlp")
    url = (
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
        if os.name == "nt"
        else "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
    )
    log("baixando yt-dlp para " + str(dest), logf)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=60, context=CTX) as r:
            data = r.read()
        if not data or len(data) < 100000:
            log("yt-dlp inesperado (%s bytes)" % len(data or b""), logf)
            return None
        tmp = dest.with_suffix(dest.suffix + ".part")
        tmp.write_bytes(data)
        tmp.replace(dest)
        if os.name != "nt":
            dest.chmod(dest.stat().st_mode | 0o111)
        return str(dest)
    except Exception as e:
        log("falha ao baixar yt-dlp: %s" % e, logf)
        return None


def http_get(url: str, timeout: int = TIMEOUT_HTTP):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as r:
            data = r.read()
            ctype = r.headers.get("Content-Type", "")
            code = getattr(r, "status", 200) or 200
            return code, ctype, data
    except urllib.error.HTTPError as e:
        return e.code, "", b""
    except Exception:
        return 0, "", b""


def id_via_yt_dlp(yt: str, busca: str, logf=None) -> str | None:
    cmd = [
        yt,
        "--skip-download",
        "--no-playlist",
        "--no-warnings",
        "--no-progress",
        "--print",
        "%(id)s",
        "ytsearch1:" + busca,
    ]
    try:
        p = subprocess.run(
            cmd,
            capture_output=True,
            timeout=TIMEOUT_BUSCA,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except Exception as e:
        log("yt-dlp exceção: %s" % e, logf)
        return None
    if p.returncode != 0:
        log("yt-dlp rc=%s err=%s" % (p.returncode, (p.stderr or "")[:400]), logf)
        # ainda pode ter impresso o id
    out = (p.stdout or "").strip().splitlines()
    for ln in out:
        s = ln.strip()
        if s and all(c.isalnum() or c in "-_" for c in s) and 5 <= len(s) <= 15:
            return s
    log("yt-dlp sem id. out=%s" % (p.stdout or "")[:300], logf)
    return None


def id_via_busca_html(busca: str, logf=None) -> str | None:
    q = urllib.parse.quote_plus(busca)
    url = "https://www.youtube.com/results?search_query=" + q + "&sp=EgIQAQ%3D%3D"
    code, _, data = http_get(url, timeout=25)
    if code != 200 or not data:
        log("busca html falhou code=%s" % code, logf)
        return None
    txt = data.decode("utf-8", "replace")
    # "videoId":"XXXXXXXXXXX"
    import re
    for m in re.finditer(r'"videoId":"([A-Za-z0-9_-]{11})"', txt):
        return m.group(1)
    for m in re.finditer(r"watch\?v=([A-Za-z0-9_-]{11})", txt):
        return m.group(1)
    log("busca html sem videoId", logf)
    return None


def baixar_miniatura(vid: str, dest: Path, logf=None) -> bool:
    for nome in ("maxresdefault.jpg", "sddefault.jpg", "hqdefault.jpg"):
        url = "https://i.ytimg.com/vi/%s/%s" % (vid, nome)
        code, ctype, data = http_get(url)
        if code != 200 or not data or len(data) < MIN_BYTES:
            log("thumb %s -> code=%s bytes=%s" % (nome, code, len(data or b"")), logf)
            continue
        if "jpeg" not in (ctype or "").lower() and "jpg" not in (ctype or "").lower() and not data.startswith(b"\xff\xd8"):
            # alguns 404 do YouTube vêm como imagem minúscula ou html
            if not data.startswith(b"\xff\xd8"):
                log("thumb %s tipo estranho %s" % (nome, ctype), logf)
                continue
        dest.write_bytes(data)
        log("baixou %s (%d bytes)" % (nome, len(data)), logf)
        return True
    return False


def recorte_pil(src: Path, dest: Path) -> bool:
    try:
        from PIL import Image
    except Exception:
        return False
    im = Image.open(src).convert("RGB")
    w, h = im.size
    if w < 32 or h < 32:
        return False
    # hqdefault 4:3 com faixa preta: corta ~12.5% em cima e embaixo
    top, bot = 0, h
    if h < w and (w / float(h)) >= 1.25:
        corte = int(round(h * 0.125))
        top, bot = corte, h - corte
        if bot - top < 32:
            top, bot = 0, h
    h2 = bot - top
    lado = min(w, h2)
    x = (w - lado) // 2
    y = top + (h2 - lado) // 2
    im = im.crop((x, y, x + lado, y + lado))
    if lado > 800:
        im = im.resize((800, 800), Image.Resampling.LANCZOS if hasattr(Image, "Resampling") else Image.LANCZOS)
    im.save(dest, "JPEG", quality=90, optimize=True)
    return dest.is_file() and dest.stat().st_size > MIN_BYTES


def recorte_powershell(src: Path, dest: Path, logf=None) -> bool:
    if os.name != "nt":
        return False
    ps = r'''
param($In,$Out)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Image]::FromFile($In)
try {
  $w = $bmp.Width; $h = $bmp.Height
  if ($w -lt 32 -or $h -lt 32) { throw "imagem pequena" }
  $top = 0; $bot = $h
  if ($h -lt $w -and ($w / [double]$h) -ge 1.25) {
    $corte = [int][Math]::Round($h * 0.125)
    $top = $corte; $bot = $h - $corte
    if (($bot - $top) -lt 32) { $top = 0; $bot = $h }
  }
  $h2 = $bot - $top
  $lado = [Math]::Min($w, $h2)
  $x = [int](($w - $lado) / 2)
  $y = [int]($top + (($h2 - $lado) / 2))
  $ladoFinal = [Math]::Min(800, $lado)
  $outBmp = New-Object System.Drawing.Bitmap $ladoFinal, $ladoFinal
  $g = [System.Drawing.Graphics]::FromImage($outBmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0,0,$ladoFinal,$ladoFinal), (New-Object System.Drawing.Rectangle $x,$y,$lado,$lado), [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose()
  $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $enc = New-Object System.Drawing.Imaging.EncoderParameters 1
  $enc.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [int64]90)
  $outBmp.Save($Out, $codec, $enc)
  $outBmp.Dispose()
} finally { $bmp.Dispose() }
'''
    ps1 = Path(tempfile.gettempdir()) / ("mik_crop_capa_%s.ps1" % os.getpid())
    try:
        ps1.write_text(ps, encoding="utf-8")
        r = subprocess.run(
            [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ps1),
                "-In",
                str(src),
                "-Out",
                str(dest),
            ],
            capture_output=True,
            timeout=30,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if r.returncode != 0:
            log("crop powershell rc=%s %s" % (r.returncode, (r.stderr or r.stdout or "")[:400]), logf)
            return False
        return dest.is_file() and dest.stat().st_size > MIN_BYTES
    except Exception as e:
        log("crop powershell exceção: %s" % e, logf)
        return False
    finally:
        try:
            ps1.unlink()
        except Exception:
            pass


def recorte_ffmpeg(src: Path, dest: Path, logf=None) -> bool:
    ffmpeg = "ffmpeg.exe" if os.name == "nt" else "ffmpeg"
    # crop central + letterbox aproximado
    vf = "crop=min(iw\\,ih*0.75):min(iw\\,ih*0.75),scale=min(800\\,iw):min(800\\,ih)"
    try:
        r = subprocess.run(
            [ffmpeg, "-y", "-i", str(src), "-vf", vf, "-q:v", "2", str(dest)],
            capture_output=True,
            timeout=30,
        )
        return r.returncode == 0 and dest.is_file() and dest.stat().st_size > MIN_BYTES
    except Exception as e:
        log("ffmpeg: %s" % e, logf)
        return False


def recortar_quadrado(src: Path, dest: Path, logf=None) -> bool:
    if recorte_pil(src, dest):
        log("recorte via Pillow", logf)
        return True
    if recorte_powershell(src, dest, logf):
        log("recorte via System.Drawing", logf)
        return True
    if recorte_ffmpeg(src, dest, logf):
        log("recorte via ffmpeg", logf)
        return True
    # último caso: usa a miniatura como está (melhor que nada)
    try:
        dest.write_bytes(src.read_bytes())
        log("sem recorte; gravei a miniatura original", logf)
        return dest.is_file() and dest.stat().st_size > MIN_BYTES
    except Exception as e:
        log("não consegui gravar capa: %s" % e, logf)
        return False


def gravar_status(path: Path, estado: str, detalhe: str = "") -> None:
    try:
        path.write_text(estado + "\n" + (detalhe or "") + "\n", encoding="utf-8")
    except Exception:
        pass


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pedido", default="")
    ap.add_argument("--pasta", default="")
    ap.add_argument("--busca", default="")
    ap.add_argument("--status", default="")
    ap.add_argument("--log", default="")
    args = ap.parse_args()
    pasta = args.pasta
    busca = args.busca
    status_p = Path(args.status) if args.status else None
    if args.pedido:
        d = ler_pedido(Path(args.pedido))
        pasta = d.get("pasta", pasta)
        busca = d.get("busca", busca)
        if d.get("status"):
            status_p = Path(d["status"])
        if d.get("log") and not args.log:
            args.log = d["log"]
    if not pasta or not busca:
        print("uso: buscar_capa.py --pasta PASTA --busca \"artista - música\"")
        return 2
    pasta_p = Path(pasta)
    if not pasta_p.is_dir():
        print("pasta inexistente:", pasta)
        if status_p:
            gravar_status(status_p, "falhou", "pasta inexistente")
        return 3
    dest = pasta_p / "capa.jpg"
    logf = None
    log_path = Path(args.log) if args.log else (ferramentas_dir() / "capa_busca.log")
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        logf = open(log_path, "a", encoding="utf-8")
    except Exception:
        logf = None
    log("BEGIN pasta=%s busca=%s" % (pasta, busca), logf)
    if dest.is_file() and dest.stat().st_size > MIN_BYTES:
        log("já existe capa.jpg, nada a fazer", logf)
        if status_p:
            gravar_status(status_p, "ok", "já existia")
        if logf:
            logf.close()
        return 0
    if status_p:
        gravar_status(status_p, "run", busca)
    yt = achar_yt_dlp()
    if not yt:
        yt = baixar_yt_dlp(logf)
    vid = None
    if yt:
        log("yt-dlp=%s" % yt, logf)
        vid = id_via_yt_dlp(yt, busca, logf)
    if not vid:
        log("fallback busca html", logf)
        vid = id_via_busca_html(busca, logf)
    if not vid:
        log("sem resultado para %r" % busca, logf)
        if status_p:
            gravar_status(status_p, "falhou", "sem resultado")
        if logf:
            logf.close()
        return 0
    log("videoId=%s" % vid, logf)
    with tempfile.TemporaryDirectory(prefix="mik_capa_") as td:
        raw = Path(td) / "raw.jpg"
        if not baixar_miniatura(vid, raw, logf):
            log("não baixou miniatura", logf)
            if status_p:
                gravar_status(status_p, "falhou", "sem miniatura")
            if logf:
                logf.close()
            return 0
        tmp_out = Path(td) / "capa.jpg"
        if not recortar_quadrado(raw, tmp_out, logf):
            if status_p:
                gravar_status(status_p, "falhou", "recorte")
            if logf:
                logf.close()
            return 0
        # troca "atômica" na pasta da música
        final_tmp = dest.with_name("capa.jpg.part")
        try:
            final_tmp.write_bytes(tmp_out.read_bytes())
            final_tmp.replace(dest)
        except Exception as e:
            log("falha ao gravar capa.jpg: %s" % e, logf)
            if status_p:
                gravar_status(status_p, "falhou", "gravar")
            if logf:
                logf.close()
            return 0
    log("OK capa.jpg %d bytes" % dest.stat().st_size, logf)
    # meta opcional (não quebra nada se falhar)
    try:
        (pasta_p / "capa.json").write_text(
            json.dumps({"busca": busca, "videoId": vid, "quando": time.strftime("%Y-%m-%d %H:%M:%S")}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    except Exception:
        pass
    if status_p:
        gravar_status(status_p, "ok", vid)
    if logf:
        logf.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        try:
            sys.stderr.write("erro: %s\n" % e)
        except Exception:
            pass
        sys.exit(0)
