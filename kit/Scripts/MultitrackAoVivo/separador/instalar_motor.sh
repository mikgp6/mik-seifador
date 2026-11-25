#!/bin/bash
# Mik Seifador - instala o MOTOR DE SEPARAÇÃO (bateria, baixo, guitarra, teclado, voz, outros) no Mac
# Criado por Miqueias Felix (2026)
# Baixa (só na 1ª vez): uv (Astral), Python 3.11, PyTorch (CUDA se houver NVIDIA, senão CPU/MPS),
# Demucs 4, audio-separator e o modelo padrão htdemucs_6s (~80 MB).
# Os modelos da qualidade máxima (BS-Roformer ~610 MB e htdemucs_ft) NÃO vêm no instalador:
# são baixados na primeira vez que o modo "Qualidade máxima" for usado.
# Tudo fica em ~/Library/Application Support/MikSeifador/motor (nada é instalado no sistema).
# Funciona em Mac Apple Silicon (M1/M2/M3/M4) e Intel.
KIT="${1:-$(cd "$(dirname "$0")" && pwd)}"
UV_VERSAO="0.13.7"
BASE="$HOME/Library/Application Support/MikSeifador/motor"
STATUS="$BASE/instalacao.txt"
LOG="$BASE/instalacao.log"
mkdir -p "$BASE"
passo() { printf 'PROGRESSO %s %s\n' "$1" "$2" > "$STATUS"; echo "[$(date +%H:%M:%S)] $2" >> "$LOG"; echo "  $2"; }
falha() { echo "ERRO $1" > "$STATUS"; echo "ERRO: $1" >> "$LOG"; echo "  ERRO: $1 (veja $LOG)"; exit 1; }
echo "Mik Seifador - instalação do motor $(date)" > "$LOG"
# Arquitetura REAL do Mac: sob Rosetta o "uname -m" diz x86_64 mesmo num M1/M2/M3/M4,
# por isso o sysctl hw.optional.arm64 manda (Apple Silicon roda tudo nativo, sem Rosetta).
ARQ="$(uname -m)"
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then ARQ="arm64"; fi
echo "Arquitetura: $ARQ" >> "$LOG"
case "$ARQ" in
  arm64|aarch64) ALVO="aarch64-apple-darwin"; REQ="requisitos_mac_arm.txt" ;;
  x86_64)        ALVO="x86_64-apple-darwin";  REQ="requisitos_mac_intel.txt" ;;
  *) falha "processador não suportado: $ARQ" ;;
esac
# Python/uv nativos do arm64 mesmo se este script foi aberto por um Terminal em Rosetta
if [ "$ARQ" = "arm64" ] && [ "$(uname -m)" != "arm64" ] && [ -z "$MIK_ARM64_REEXEC" ] && [ -x /usr/bin/arch ]; then
  export MIK_ARM64_REEXEC=1
  exec /usr/bin/arch -arm64 /bin/bash "$0" "$@"
fi
UV="$BASE/uv/uv"
if [ ! -x "$UV" ]; then
  passo 0.05 "Baixando o uv (gerenciador do Python)..."
  mkdir -p "$BASE/uv"
  curl -fsSL "https://github.com/astral-sh/uv/releases/download/$UV_VERSAO/uv-$ALVO.tar.gz" -o "$BASE/uv.tgz" >> "$LOG" 2>&1 || falha "não consegui baixar o uv (internet?)"
  tar -xzf "$BASE/uv.tgz" -C "$BASE/uv" --strip-components 1 || falha "não consegui extrair o uv"
  rm -f "$BASE/uv.tgz"; chmod +x "$UV"; xattr -dr com.apple.quarantine "$BASE/uv" 2>/dev/null
fi
export UV_PYTHON_INSTALL_DIR="$BASE/python" UV_CACHE_DIR="$BASE/cache" UV_LINK_MODE=copy
PY="$BASE/venv/bin/python"
if [ ! -x "$PY" ]; then
  passo 0.15 "Baixando o Python 3.11 (só para o motor)..."
  "$UV" venv --clear --force --python 3.11 --python-preference only-managed "$BASE/venv" >> "$LOG" 2>&1 || falha "não consegui criar o Python do motor"
fi
TEM_NVIDIA=0
if command -v nvidia-smi >/dev/null 2>&1; then TEM_NVIDIA=1; fi
if [ "$TEM_NVIDIA" = "1" ]; then
  passo 0.30 "NVIDIA detectada. Baixando PyTorch com CUDA + Demucs..."
else
  passo 0.30 "Baixando PyTorch + Demucs (~200 MB, pode levar alguns minutos)..."
fi
"$UV" pip install --python "$PY" -r "$KIT/$REQ" >> "$LOG" 2>&1 || falha "não consegui instalar PyTorch/Demucs"
if [ "$TEM_NVIDIA" = "1" ]; then
  passo 0.55 "Trocando o PyTorch pela versão com CUDA..."
  "$UV" pip install --python "$PY" torch==2.2.2 torchaudio==2.2.2 --index-url https://download.pytorch.org/whl/cu118 >> "$LOG" 2>&1 || falha "não consegui instalar o PyTorch com CUDA"
fi
# audio-separator 0.48 exige torch>=2.3 (no Mac Intel, torch>=2.13 no Apple Silicon).
# O PyTorch parou de publicar wheels macOS x86_64 a partir do 2.3 (só há 2.2.2),
# então neste Mac Intel o resolvedor falha. Tentamos o 0.48; se não houver wheel,
# o motor segue só com Demucs na CPU (modo padrão). A qualidade máxima (BS-Roformer)
# fica indisponível e o painel cai para htdemucs_6s.
passo 0.68 "Instalando o audio-separator (modo qualidade máxima)..."
AS_VER="0"
if "$UV" pip install --python "$PY" "audio-separator==0.48.0" >> "$LOG" 2>&1; then
  AS_VER="0.48.0"
else
  echo "AVISO: audio-separator==0.48.0 não instalou (provável falta de wheel de torch>=2.3 neste processador)." >> "$LOG"
  if [ "$ARQ" = "x86_64" ]; then
    passo 0.70 "Qualidade máxima indisponível neste Mac Intel (sem wheel do PyTorch 2.3+); seguindo com Demucs..."
  else
    # Em Apple Silicon / outros, ainda tentamos; se falhar, não derruba o motor.
    passo 0.70 "Não deu para instalar o audio-separator; o motor segue com Demucs."
  fi
fi
if [ "$TEM_NVIDIA" = "1" ]; then
  "$UV" pip install --python "$PY" torch==2.2.2 torchaudio==2.2.2 --index-url https://download.pytorch.org/whl/cu118 >> "$LOG" 2>&1 || falha "não consegui repor o PyTorch com CUDA"
else
  "$UV" pip install --python "$PY" torch==2.2.2 torchaudio==2.2.2 >> "$LOG" 2>&1 || true
fi
passo 0.85 "Baixando o modelo padrão htdemucs_6s (~80 MB)..."
MIK_MOTOR="$BASE" "$PY" "$KIT/separar.py" --baixar-modelo >> "$LOG" 2>&1 || falha "não consegui baixar o modelo"
passo 0.95 "Limpando arquivos temporários..."
"$UV" cache clean >> "$LOG" 2>&1
if [ "$TEM_NVIDIA" = "1" ]; then TORCH=cuda; else TORCH=cpu; fi
printf 'motor=1\nuv=%s\nmodelo=htdemucs_6s\ntorch=%s\naudio_separator=%s\n' "$UV_VERSAO" "$TORCH" "$AS_VER" > "$BASE/versao.txt"
echo "OK" > "$STATUS"
echo "  Motor de separação instalado!"
exit 0
