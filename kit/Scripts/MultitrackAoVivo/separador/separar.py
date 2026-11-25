# -*- coding: utf-8 -*-
"""
Mik Seifador - separador de trilhas (bateria, baixo, guitarra, teclado, voz, outros)
Criado por Miqueias Felix (2026). Usa o modelo Demucs v4 (htdemucs_6s, Meta/Facebook, licença MIT).

O REAPER chama este arquivo com o Python do "motor" (instalado por instalar_motor):
    python separar.py PEDIDO.txt
PEDIDO.txt (UTF-8), uma chave por linha:
    entrada=C:\\...\\musica.mp3
    saida=C:\\...\\__stems
    canal=ambos | L | R      (L/R = usa só esse lado; ex.: VS com click no outro lado)
    modelo=htdemucs_6s | qualidade
    rapido=0 | 1             (1 = só htdemucs_6s, menos passadas; qualidade um pouco menor)
    qualidade = voz com BS-Roformer + bateria/baixo com htdemucs_ft +
                guitarra/teclado com htdemucs_6s (mais lento, menos vazamento de voz)
Escreve na pasta de saída:  Bateria.flac  Baixo.flac  Guitarra.flac  Teclado.flac  Voz.flac  Outros.flac
e o andamento em  status.txt :  "PROGRESSO 0.42 texto"  ...  "OK"  ou  "ERRO texto".

Outros modos:
    python separar.py --baixar-modelo      (baixa o modelo, usado na instalação)
    python separar.py --teste ARQUIVO SAIDA (separa um arquivo direto, para teste)
    python separar.py --teste ARQUIVO SAIDA --qualidade
"""
import os, sys, time, traceback

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

AQUI = os.path.dirname(os.path.abspath(__file__))
MOTOR = os.environ.get("MIK_MOTOR") or os.path.dirname(os.path.dirname(os.path.abspath(sys.executable)))
if os.path.basename(MOTOR).lower() == "venv":
    MOTOR = os.path.dirname(MOTOR)
os.environ.setdefault("TORCH_HOME", os.path.join(MOTOR, "modelos"))
# pythonw.exe (Windows, sem janela preta) não tem console: manda as mensagens para um log
if sys.stdout is None or sys.stderr is None:
    try:
        os.makedirs(MOTOR, exist_ok=True)
        _log = open(os.path.join(MOTOR, "ultima_separacao.log"), "w", encoding="utf-8", buffering=1)
    except OSError:
        _log = open(os.devnull, "w")
    sys.stdout = sys.stdout or _log
    sys.stderr = sys.stderr or _log

MODELO_PADRAO = "htdemucs_6s"
NOMES = {
    "drums": "Bateria", "bass": "Baixo", "vocals": "Voz", "other": "Outros",
    "guitar": "Guitarra", "piano": "Teclado",
}
STATUS = None
MODELOS_QUALIDADE = {"qualidade", "max", "stem-splitter", "stem_splitter", "htdemucs_6s+roformer"}
ROFORMER_VOZ = "model_bs_roformer_ep_317_sdr_12.9755.ckpt"


def status(txt):
    print(txt, flush=True)
    if not STATUS:
        return
    tmp = STATUS + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(txt + "\n")
        os.replace(tmp, STATUS)
    except OSError:
        pass


def progresso(p, txt):
    status("PROGRESSO %.3f %s" % (max(0.0, min(1.0, p)), txt))


def log_device(msg):
    """Registra escolha/fallback de dispositivo (sem popup)."""
    print(msg, flush=True)
    try:
        with open(os.path.join(MOTOR, "dispositivo.log"), "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")
    except OSError:
        pass


def _compat_runtime():
    """ffmpeg no PATH + shims para o audio-separator no torch 2.2 do motor."""
    try:
        import torch
        comp = getattr(torch, "compiler", None)
        if comp is not None and not hasattr(comp, "is_compiling"):
            comp.is_compiling = lambda: False
    except Exception:
        pass
    bin_dir = os.path.join(MOTOR, "bin")
    ffmpeg = os.path.join(bin_dir, "ffmpeg.exe" if os.name == "nt" else "ffmpeg")
    if not os.path.exists(ffmpeg):
        try:
            import shutil
            import imageio_ffmpeg
            src = imageio_ffmpeg.get_ffmpeg_exe()
            if src and os.path.exists(src):
                os.makedirs(bin_dir, exist_ok=True)
                shutil.copy2(src, ffmpeg)
                try:
                    os.chmod(ffmpeg, 0o755)
                except OSError:
                    pass
        except Exception as e:
            log_device("nao consegui preparar o ffmpeg: %s" % e)
    if os.path.isdir(bin_dir):
        os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")
    # audio-separator 0.48 importa torch.nn.attention (só no torch 2.3+)
    try:
        attend = os.path.join(MOTOR, "venv", "Lib", "site-packages",
                              "audio_separator", "separator", "uvr_lib_v5", "roformer", "attend.py")
        if not os.path.exists(attend):
            return
        with open(attend, "r", encoding="utf-8") as f:
            src = f.read()
        needle = "from torch.nn.attention import SDPBackend, sdpa_kernel\n"
        if needle in src and "PyTorch 2.2" not in src:
            # o patch permanente já foi aplicado nesta máquina; se reinstalarem, o shim
            # em torch.compiler cobre o outro ponto. Aqui só evitamos o import duro.
            pass
    except Exception:
        pass


def ler_pedido(caminho):
    d = {}
    with open(caminho, "r", encoding="utf-8-sig") as f:
        for linha in f:
            if "=" in linha:
                k, v = linha.split("=", 1)
                d[k.strip().lower()] = v.strip().strip('"')
    return d


def carregar_audio(caminho, sr_alvo, pasta_tmp):
    import numpy as np
    import soundfile as sf
    dados, sr = None, None
    try:
        dados, sr = sf.read(caminho, dtype="float32", always_2d=True)
    except Exception:
        # m4a/aac/etc.: decodifica com o ffmpeg que vem no pacote imageio-ffmpeg
        import subprocess
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        tmp = os.path.join(pasta_tmp, "_entrada_tmp.wav")
        flags = 0x08000000 if os.name == "nt" else 0  # CREATE_NO_WINDOW
        subprocess.run([ff, "-y", "-v", "error", "-i", caminho, "-vn", "-ac", "2", "-ar", str(sr_alvo), tmp],
                       check=True, creationflags=flags)
        dados, sr = sf.read(tmp, dtype="float32", always_2d=True)
        try:
            os.remove(tmp)
        except OSError:
            pass
    return dados, sr


def preparar(dados, sr, sr_alvo, canal):
    import numpy as np
    import torch
    if dados.shape[1] == 1:
        dados = np.repeat(dados, 2, axis=1)
    if canal in ("L", "R") and dados.shape[1] >= 2:
        lado = dados[:, 0 if canal == "L" else 1]
        dados = np.stack([lado, lado], axis=1)
    dados = dados[:, :2]
    wav = torch.from_numpy(np.ascontiguousarray(dados.T))
    if sr != sr_alvo:
        import julius
        wav = julius.resample_frac(wav, sr, sr_alvo)
    return wav


class _BarraProgresso:
    """Substitui o tqdm do Demucs para mandar o andamento ao REAPER."""
    def __init__(self, iterable=None, total=None, **kw):
        self.it = iterable
        self.total = total if total is not None else (len(iterable) if hasattr(iterable, "__len__") else 0)

    def __iter__(self):
        n = 0
        for x in self.it:
            yield x
            n += 1
            if self.total:
                _BarraProgresso.cb(n / self.total)

    def update(self, *a):
        pass

    def close(self):
        pass

    cb = staticmethod(lambda p: None)


def carregar_modelo(nome):
    from demucs.pretrained import get_model
    m = get_model(nome)
    m.eval()
    return m


def nucleos_fisicos():
    """Núcleos físicos (sem hyperthread). No CPU, isso costuma ser mais estável que usar todas as threads lógicas."""
    nlog = os.cpu_count() or 1
    if sys.platform == "darwin":
        try:
            import subprocess
            n = int(subprocess.check_output(["sysctl", "-n", "hw.physicalcpu"], text=True).strip())
            if n > 0:
                return n
        except Exception:
            pass
        return nlog
    if sys.platform.startswith("linux"):
        try:
            import glob
            grupos = set()
            for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/topology/thread_siblings_list"):
                with open(p, "r", encoding="ascii") as f:
                    grupos.add(f.read().strip())
            if grupos:
                return max(1, len(grupos))
        except Exception:
            pass
        return nlog
    if os.name == "nt":
        try:
            n = _nucleos_fisicos_win()
            if n:
                return n
        except Exception:
            pass
    return nlog


def _nucleos_fisicos_win():
    import ctypes
    from ctypes import wintypes
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    GetLPI = kernel32.GetLogicalProcessorInformationEx
    GetLPI.argtypes = [wintypes.DWORD, ctypes.c_void_p, ctypes.POINTER(wintypes.DWORD)]
    GetLPI.restype = wintypes.BOOL
    RelationProcessorCore = 0

    class HDR(ctypes.Structure):
        _fields_ = [("Relationship", wintypes.DWORD), ("Size", wintypes.DWORD)]

    needed = wintypes.DWORD(0)
    GetLPI(RelationProcessorCore, None, ctypes.byref(needed))
    if needed.value == 0:
        return 0
    buf = (ctypes.c_byte * needed.value)()
    if not GetLPI(RelationProcessorCore, ctypes.byref(buf), ctypes.byref(needed)):
        return 0
    cores, off = 0, 0
    while off + ctypes.sizeof(HDR) <= needed.value:
        info = HDR.from_buffer(buf, off)
        if info.Size <= 0:
            break
        if info.Relationship == RelationProcessorCore:
            cores += 1
        off += info.Size
    return cores


def escolher_device():
    """CUDA (NVIDIA) se existir; MPS no Mac; senão CPU. DirectML/XPU só se já estiverem
    instalados — neste notebook não foram mais rápidos (não instalados / não testados)."""
    env = (os.environ.get("MIK_DEVICE") or "").strip()
    if env:
        log_device("dispositivo forçado por MIK_DEVICE=%s" % env)
        return env
    try:
        import torch
        if torch.cuda.is_available() and torch.cuda.device_count() > 0:
            nome = torch.cuda.get_device_name(0)
            vram = torch.cuda.get_device_properties(0).total_memory / (1024 ** 3)
            log_device("usando CUDA: %s (%.1f GB)" % (nome, vram))
            return "cuda"
        xpu = getattr(torch, "xpu", None)
        if xpu is not None and callable(getattr(xpu, "is_available", None)) and xpu.is_available():
            # Só usaria se um teste local provasse ser mais rápido que a CPU.
            log_device("Intel XPU detectado, mas sem teste de velocidade; usando CPU")
        try:
            import torch_directml  # noqa: F401
            log_device("torch-directml instalado, mas sem teste de velocidade; usando CPU")
        except Exception:
            pass
        if sys.platform == "darwin":
            mps = getattr(torch.backends, "mps", None)
            if mps is not None and mps.is_built() and mps.is_available():
                log_device("usando MPS (Apple Silicon)")
                return "mps"
    except Exception as e:
        log_device("falha ao detectar acelerador (%s: %s); usando CPU" % (type(e).__name__, e))
    log_device("usando CPU")
    return "cpu"


def _segmento_nativo(model=None):
    """Menor segmento entre o saco e os submodelos; None = deixar o Demucs decidir."""
    if model is None:
        return None
    segs = []
    milhar = [model]
    milhar.extend(list(getattr(model, "models", []) or []))
    for m in milhar:
        s = getattr(m, "segment", None)
        try:
            if s:
                segs.append(float(s))
        except (TypeError, ValueError):
            pass
    return min(segs) if segs else None


def parametros_separacao(rapido, model=None):
    """shifts/overlap/segment/threads. Modo rápido: shifts=0, overlap menor; qualidade um pouco menor.
    segment=None deixa o valor nativo de cada submodelo (htdemucs ~7,8 s). Passar 10 s no saco
    quebra o view interno do transformer."""
    seg = _segmento_nativo(model)
    if rapido:
        return {"shifts": 0, "overlap": 0.1, "segment": seg, "threads": nucleos_fisicos()}
    return {"shifts": 1, "overlap": 0.25, "segment": seg, "threads": nucleos_fisicos()}


def _aplicar_modelo(dapply, model, wav, device, params):
    kw = dict(device=device, shifts=params["shifts"], split=True,
              overlap=params["overlap"], progress=True, num_workers=0)
    # Só informa segment se veio do próprio modelo (submodelo), nunca um valor inventado.
    if params.get("segment"):
        try:
            import inspect
            if "segment" in inspect.signature(dapply.apply_model).parameters:
                kw["segment"] = params["segment"]
        except Exception:
            pass
    try:
        return dapply.apply_model(model, wav[None], **kw)[0]
    except Exception as e:
        if str(device).lower() == "cpu":
            raise
        log_device("GPU falhou em %s (%s: %s); fallback silencioso para CPU" % (
            kw.get("device"), type(e).__name__, e))
        progresso(0.06, "Acelerador indisponível, usando o processador...")
        kw["device"] = "cpu"
        return dapply.apply_model(model, wav[None], **kw)[0]


def separar(entrada, saida, canal="ambos", modelo=None, rapido=False):
    global STATUS
    os.makedirs(saida, exist_ok=True)
    STATUS = os.path.join(saida, "status.txt")
    modelo = modelo or MODELO_PADRAO
    _compat_runtime()
    if (modelo or "").strip().lower() in MODELOS_QUALIDADE and not rapido:
        return separar_qualidade(entrada, saida, canal, rapido=False)
    t0 = time.time()
    progresso(0.01, "Carregando o motor...")
    import numpy as np
    import torch
    import soundfile as sf
    import demucs.apply as dapply
    from types import SimpleNamespace
    params = parametros_separacao(rapido)
    try:
        torch.set_num_threads(max(1, int(params["threads"])))
    except Exception:
        pass
    progresso(0.03, "Carregando o modelo (%s)..." % modelo)
    model = carregar_modelo(modelo)
    params = parametros_separacao(rapido, model)
    sr_alvo = model.samplerate
    progresso(0.05, "Lendo o áudio...")
    dados, sr = carregar_audio(entrada, sr_alvo, saida)
    wav = preparar(dados, sr, sr_alvo, canal)
    dur = wav.shape[-1] / sr_alvo
    ref = wav.mean(0)
    media, desvio = ref.mean(), ref.std()
    if desvio < 1e-8:
        desvio = torch.tensor(1.0)
    wav = (wav - media) / desvio

    n_mod = len(getattr(model, "models", [model]))
    estado = {"i": 0}
    rotulo = ", ".join(NOMES.get(s, s).lower() for s in list(model.sources))
    if rotulo.count(",") >= 1:
        partes = rotulo.rsplit(", ", 1)
        rotulo = partes[0] + " e " + partes[1]
    msg = ("Separando (rápida) %s..." % rotulo) if rapido else ("Separando %s..." % rotulo)

    def cb(p):
        progresso(0.07 + 0.83 * min(1.0, (estado["i"] + p) / n_mod), msg)
    _BarraProgresso.cb = staticmethod(cb)
    dapply.tqdm = SimpleNamespace(tqdm=_BarraProgresso)
    device = escolher_device()
    with torch.no_grad():
        fontes = _aplicar_modelo(dapply, model, wav, device, params)
    fontes = fontes * desvio + media
    progresso(0.92, "Gravando as trilhas...")
    nomes = list(model.sources)
    for i, fonte in enumerate(nomes):
        nome = NOMES.get(fonte, fonte.capitalize())
        audio = fontes[i].cpu().numpy().T
        pico = float(np.abs(audio).max()) if audio.size else 0.0
        if pico > 0.999:          # evita clipar o FLAC
            audio = audio * (0.999 / pico)
        final = os.path.join(saida, nome + ".flac")
        tmp = os.path.join(saida, nome + ".tmp.flac")
        sf.write(tmp, audio, sr_alvo, subtype="PCM_24", format="FLAC")
        os.replace(tmp, final)
    seg = time.time() - t0
    with open(os.path.join(saida, "separacao.txt"), "w", encoding="utf-8") as f:
        f.write("entrada=%s\nmodelo=%s\ncanal=%s\nrapido=%s\ndevice=%s\n"
                "shifts=%s\noverlap=%s\nsegment=%s\nthreads=%s\n"
                "duracao=%.1f\ntempo=%.1f\ndata=%s\n" % (
                    entrada, modelo, canal, "1" if rapido else "0", device,
                    params["shifts"], params["overlap"], params["segment"], params["threads"],
                    dur, seg, time.strftime("%Y-%m-%d %H:%M:%S")))
    status("OK %.1f %.1f" % (seg, dur))
    return seg, dur


def _gravar_flac(caminho, audio, sr):
    import numpy as np
    import soundfile as sf
    if hasattr(audio, "cpu"):
        audio = audio.cpu().numpy()
    audio = np.asarray(audio, dtype="float32")
    if audio.ndim == 2 and audio.shape[0] < audio.shape[1] and audio.shape[0] <= 8:
        audio = audio.T
    if audio.ndim == 1:
        audio = audio[:, None]
    pico = float(np.abs(audio).max()) if audio.size else 0.0
    if pico > 0.999:
        audio = audio * (0.999 / pico)
    tmp = caminho + ".tmp.flac"
    sf.write(tmp, audio, sr, subtype="PCM_24", format="FLAC")
    os.replace(tmp, caminho)


def _liberar_gpu():
    import gc
    gc.collect()
    try:
        import torch
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
    except Exception:
        pass


def _demucs_em_wav(wav, modelo, rapido, device, msg):
    """wav: tensor (C, T) já no samplerate do modelo. Devolve dict fonte -> tensor (C, T)."""
    import torch
    import demucs.apply as dapply
    from types import SimpleNamespace
    model = carregar_modelo(modelo)
    params = parametros_separacao(rapido, model)
    try:
        torch.set_num_threads(max(1, int(params["threads"])))
    except Exception:
        pass
    n_mod = max(1, len(getattr(model, "models", [model])))
    estado = {"i": 0}

    def cb(p):
        if callable(msg):
            msg(min(1.0, (estado["i"] + p) / n_mod))
    _BarraProgresso.cb = staticmethod(cb)
    dapply.tqdm = SimpleNamespace(tqdm=_BarraProgresso)
    with torch.no_grad():
        fontes = _aplicar_modelo(dapply, model, wav, device, params)
    nomes = list(model.sources)
    saida = {}
    for i, fonte in enumerate(nomes):
        saida[fonte] = fontes[i].detach().cpu()
    del model, fontes
    _liberar_gpu()
    return saida, params


def _roformer_voz(entrada, pasta_tmp, p0=0.08, p1=0.55):
    """Separa voz + instrumental com BS-Roformer. Devolve (voz, inst, sr) em float32 (T, C)."""
    import numpy as np
    import soundfile as sf
    from audio_separator.separator import Separator

    progresso(p0, "Separando a voz (BS-Roformer)...")
    model_dir = os.path.join(MOTOR, "modelos", "roformer")
    os.makedirs(model_dir, exist_ok=True)
    os.makedirs(pasta_tmp, exist_ok=True)
    device = escolher_device()
    usar_fp16 = str(device).startswith("cuda")
    # MX330 (2 GB): segment 64 em fp16 cabe; overlap 2 é o equilíbrio qualidade/tempo.
    sep = Separator(
        log_level=30,
        model_file_dir=model_dir,
        output_dir=pasta_tmp,
        output_format="WAV",
        sample_rate=44100,
        use_autocast=False,
        use_native_fp16=usar_fp16,
        use_directml=False,
        use_torch_compile=False,
        mdxc_params={
            "segment_size": 64,
            "override_model_segment_size": True,
            "batch_size": 1,
            "overlap": 2,
            "pitch_shift": 0,
        },
    )
    sep.load_model(model_filename=ROFORMER_VOZ)
    progresso((p0 + p1) / 2, "Separando a voz (BS-Roformer)...")
    arquivos = sep.separate(entrada)
    del sep
    _liberar_gpu()
    progresso(p1, "Voz separada, seguindo para os instrumentos...")
    voz_p = inst_p = None
    for nome in arquivos:
        caminho = nome if os.path.isabs(nome) else os.path.join(pasta_tmp, nome)
        baixo = os.path.basename(caminho).lower()
        if "(vocals)" in baixo or "_vocals_" in baixo or baixo.endswith("vocals.wav"):
            voz_p = caminho
        elif "(instrumental)" in baixo or "_instrumental_" in baixo or baixo.endswith("instrumental.wav"):
            inst_p = caminho
    if not voz_p or not inst_p:
        # fallback: pega pelos nomes que o audio-separator costuma gerar
        for nome in arquivos:
            caminho = nome if os.path.isabs(nome) else os.path.join(pasta_tmp, nome)
            baixo = os.path.basename(caminho).lower()
            if "vocal" in baixo:
                voz_p = caminho
            elif "instrumental" in baixo or "no_vocal" in baixo or "accompaniment" in baixo:
                inst_p = caminho
    if not voz_p or not inst_p:
        raise RuntimeError("o BS-Roformer não gerou voz e instrumental (%s)" % (arquivos,))
    voz, sr1 = sf.read(voz_p, dtype="float32", always_2d=True)
    inst, sr2 = sf.read(inst_p, dtype="float32", always_2d=True)
    if sr1 != sr2:
        raise RuntimeError("sample rates diferentes no Roformer")
    return np.asarray(voz), np.asarray(inst), sr1


def separar_qualidade(entrada, saida, canal="ambos", rapido=False):
    """Cascata tipo Stem Splitter: Roformer (voz) + htdemucs_ft (bateria/baixo) + htdemucs_6s (guitarra/teclado)."""
    global STATUS
    import numpy as np
    import torch
    os.makedirs(saida, exist_ok=True)
    STATUS = os.path.join(saida, "status.txt")
    _compat_runtime()
    t0 = time.time()
    progresso(0.01, "Carregando o motor (qualidade máxima)...")
    device = escolher_device()
    pasta_tmp = os.path.join(saida, "_tmp_qualidade")
    os.makedirs(pasta_tmp, exist_ok=True)
    try:
        voz, inst, sr_r = _roformer_voz(entrada, pasta_tmp)
    except Exception as e:
        log_device("BS-Roformer falhou (%s: %s); caindo para htdemucs_6s" % (type(e).__name__, e))
        progresso(0.05, "Qualidade máxima indisponível, usando htdemucs_6s...")
        return separar(entrada, saida, canal, modelo="htdemucs_6s", rapido=rapido)

    # lado L/R se o pedido pediu só um canal da original — já aplicado no roformer? não.
    # Recorta o instrumental/voz se canal L/R: o roformer leu o arquivo original inteiro.
    if canal in ("L", "R"):
        idx = 0 if canal == "L" else 1
        if voz.shape[1] >= 2:
            voz = np.stack([voz[:, idx], voz[:, idx]], axis=1)
        if inst.shape[1] >= 2:
            inst = np.stack([inst[:, idx], inst[:, idx]], axis=1)

    def _para_wav(arr, sr_alvo):
        wav = torch.from_numpy(np.ascontiguousarray(arr.T))
        if wav.shape[0] == 1:
            wav = wav.repeat(2, 1)
        wav = wav[:2]
        if sr_r != sr_alvo:
            import julius
            wav = julius.resample_frac(wav, sr_r, sr_alvo)
        return wav

    progresso(0.56, "Separando bateria e baixo (htdemucs_ft)...")
    model_ft = carregar_modelo("htdemucs_ft")
    sr_ft = model_ft.samplerate
    del model_ft
    _liberar_gpu()
    wav_inst = _para_wav(inst, sr_ft)

    def cb_ft(p):
        progresso(0.56 + 0.22 * p, "Separando bateria e baixo (htdemucs_ft)...")

    ft, params_ft = _demucs_em_wav(wav_inst, "htdemucs_ft", rapido, device, cb_ft)
    bateria = ft.get("drums")
    baixo = ft.get("bass")
    outros_ft = ft.get("other")
    voz_res = ft.get("vocals")
    if outros_ft is None:
        raise RuntimeError("htdemucs_ft não devolveu a trilha other")

    progresso(0.79, "Separando guitarra e teclado (htdemucs_6s)...")

    def cb_6s(p):
        progresso(0.79 + 0.14 * p, "Separando guitarra e teclado (htdemucs_6s)...")

    s6, params_6 = _demucs_em_wav(outros_ft, "htdemucs_6s", rapido, device, cb_6s)
    guitarra = s6.get("guitar")
    teclado = s6.get("piano")
    outros = s6.get("other")
    # restos do 6s (bateria/baixo/voz que sobraram no 'other' do ft) vão para Outros
    for extra in ("drums", "bass"):
        if extra in s6 and outros is not None:
            outros = outros + s6[extra]
    if s6.get("vocals") is not None:
        voz_res = s6["vocals"] if voz_res is None else voz_res + s6["vocals"]

    # voz = roformer + residual que o ft/6s ainda acharam no instrumental
    voz_t = torch.from_numpy(np.ascontiguousarray(voz.T))
    if voz_t.shape[0] == 1:
        voz_t = voz_t.repeat(2, 1)
    voz_t = voz_t[:2]
    sr_out = sr_r
    if sr_ft != sr_out:
        import julius
        if bateria is not None:
            bateria = julius.resample_frac(bateria, sr_ft, sr_out)
        if baixo is not None:
            baixo = julius.resample_frac(baixo, sr_ft, sr_out)
        if guitarra is not None:
            guitarra = julius.resample_frac(guitarra, sr_ft, sr_out)
        if teclado is not None:
            teclado = julius.resample_frac(teclado, sr_ft, sr_out)
        if outros is not None:
            outros = julius.resample_frac(outros, sr_ft, sr_out)
        if voz_res is not None:
            voz_res = julius.resample_frac(voz_res, sr_ft, sr_out)
    if voz_res is not None:
        n = min(voz_t.shape[-1], voz_res.shape[-1])
        voz_t = voz_t[:, :n] + voz_res[:, :n]

    # alinha comprimentos
    stems = {
        "Bateria": bateria, "Baixo": baixo, "Guitarra": guitarra,
        "Teclado": teclado, "Voz": voz_t, "Outros": outros,
    }
    n = min(v.shape[-1] for v in stems.values() if v is not None)
    progresso(0.94, "Gravando as trilhas...")
    for nome, audio in stems.items():
        if audio is None:
            audio = torch.zeros(2, n)
        _gravar_flac(os.path.join(saida, nome + ".flac"), audio[:, :n], sr_out)
    dur = n / float(sr_out)
    seg = time.time() - t0
    with open(os.path.join(saida, "separacao.txt"), "w", encoding="utf-8") as f:
        f.write("entrada=%s\nmodelo=qualidade\ncanal=%s\nrapido=%s\ndevice=%s\n"
                "roformer=%s\nft=htdemucs_ft\nseisso=htdemucs_6s\n"
                "ft_shifts=%s\nseisso_shifts=%s\n"
                "duracao=%.1f\ntempo=%.1f\ndata=%s\n" % (
                    entrada, canal, "1" if rapido else "0", device,
                    ROFORMER_VOZ,
                    params_ft.get("shifts"), params_6.get("shifts"),
                    dur, seg, time.strftime("%Y-%m-%d %H:%M:%S")))
    # limpa temporários do roformer (os stems finais já estão em FLAC)
    try:
        import shutil
        shutil.rmtree(pasta_tmp, ignore_errors=True)
    except Exception:
        pass
    status("OK %.1f %.1f" % (seg, dur))
    return seg, dur


def _pedido_rapido(p):
    v = (p.get("rapido") or p.get("modo") or "").strip().lower()
    return v in ("1", "sim", "true", "rapido", "rápida", "rapida")


def principal(argv):
    rapido_cli = "--rapido" in argv
    argv = [a for a in argv if a != "--rapido"]
    if len(argv) >= 2 and argv[1] == "--baixar-modelo":
        nome = argv[2] if len(argv) > 2 else MODELO_PADRAO
        if (nome or "").strip().lower() in MODELOS_QUALIDADE or nome == "todos":
            print("Baixando htdemucs_6s, htdemucs_ft e o BS-Roformer...", flush=True)
            carregar_modelo("htdemucs_6s")
            carregar_modelo("htdemucs_ft")
            _compat_runtime()
            try:
                from audio_separator.separator import Separator
                d = os.path.join(MOTOR, "modelos", "roformer")
                os.makedirs(d, exist_ok=True)
                sep = Separator(log_level=20, model_file_dir=d, output_dir=d)
                sep.load_model(model_filename=ROFORMER_VOZ)
                del sep
            except Exception as e:
                log_device("BS-Roformer não baixado (%s: %s); o motor segue com Demucs." % (type(e).__name__, e))
                print("AVISO: qualidade máxima indisponível neste computador; usando só o Demucs.", flush=True)
            print("MODELO_OK", flush=True)
            return 0
        print("Baixando o modelo %s (~80 MB)..." % nome, flush=True)
        carregar_modelo(nome)
        print("MODELO_OK", flush=True)
        return 0
    if len(argv) >= 4 and argv[1] == "--teste":
        qualidade_cli = "--qualidade" in argv
        argv_t = [a for a in argv if a != "--qualidade"]
        canal = argv_t[4] if (len(argv_t) > 4 and not argv_t[4].startswith("-")) else "ambos"
        modelo_t = "qualidade" if qualidade_cli else MODELO_PADRAO
        seg, dur = separar(argv_t[2], argv_t[3], canal, modelo=modelo_t, rapido=rapido_cli)
        print("TESTE_OK %s %.1f s para %.1f s de musica (%.2fx)" % (
            "rapido" if rapido_cli else "normal", seg, dur, seg / max(dur, 0.1)), flush=True)
        return 0
    if len(argv) < 2:
        print(__doc__)
        return 2
    p = ler_pedido(argv[1])
    saida = p.get("saida") or os.path.dirname(argv[1])
    try:
        separar(p["entrada"], saida, (p.get("canal") or "ambos").upper().replace("AMBOS", "ambos"),
                p.get("modelo") or MODELO_PADRAO, rapido=rapido_cli or _pedido_rapido(p))
        return 0
    except Exception as e:
        global STATUS
        STATUS = os.path.join(saida, "status.txt")
        try:
            with open(os.path.join(saida, "erro.txt"), "w", encoding="utf-8") as f:
                f.write(traceback.format_exc())
        except OSError:
            pass
        status("ERRO " + (str(e).splitlines() or [type(e).__name__])[0][:300])
        return 1


if __name__ == "__main__":
    sys.exit(principal(sys.argv))
