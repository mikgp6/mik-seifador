# Mik Seifador - instala o MOTOR DE SEPARAÇÃO (bateria, baixo, guitarra, teclado, voz, outros)
# Criado por Miqueias Felix (2026)
# Baixa (só na 1ª vez): uv (Astral), Python 3.11, PyTorch (CUDA se houver NVIDIA, senão CPU),
# Demucs 4, audio-separator e o modelo padrão htdemucs_6s (~80 MB).
# Os modelos da qualidade máxima (BS-Roformer ~610 MB e htdemucs_ft) NÃO vêm no instalador:
# são baixados na primeira vez que o modo "Qualidade máxima" for usado.
# Tudo fica em %LOCALAPPDATA%\MikSeifador\motor (nada é instalado no sistema).
# Pode rodar quantas vezes quiser: o que já está instalado é reaproveitado.
param([string]$KitDir = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UV_VERSAO = '0.13.7'
$Base   = Join-Path $env:LOCALAPPDATA 'MikSeifador\motor'
$Status = Join-Path $Base 'instalacao.txt'
$Log    = Join-Path $Base 'instalacao.log'
New-Item -ItemType Directory -Force -Path $Base | Out-Null
function Passo($p, $txt) {
  $linha = ('PROGRESSO {0:0.00} {1}' -f $p, $txt) -replace ',', '.'
  [IO.File]::WriteAllText($Status, $linha + "`n", (New-Object Text.UTF8Encoding $false))
  Add-Content -Path $Log -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $txt) -Encoding UTF8
  Write-Host ("  [{0,3}%] {1}" -f [int]($p * 100), $txt) -ForegroundColor Cyan
}
function Rodar($exe, [string[]]$argumentos) {
  $antes = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  & $exe @argumentos 2>&1 | ForEach-Object { "$_" } | Out-File -FilePath $Log -Append -Encoding UTF8
  $ErrorActionPreference = $antes
  if ($LASTEXITCODE -ne 0) { throw "falhou: $exe $($argumentos -join ' ') (código $LASTEXITCODE) - veja $Log" }
}
function Tem-Nvidia {
  try {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    foreach ($g in @($gpus)) {
      if ($g.Name -and ($g.Name -match 'NVIDIA')) { return $true }
    }
  } catch {}
  try {
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) { return $true }
  } catch {}
  return $false
}
try {
  Set-Content -Path $Log -Value "Mik Seifador - instalação do motor $(Get-Date)" -Encoding UTF8
  $uv = Join-Path $Base 'uv\uv.exe'
  if (-not (Test-Path $uv)) {
    Passo 0.05 'Baixando o uv (gerenciador do Python, 32 MB)...'
    $zip = Join-Path $Base 'uv.zip'
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/astral-sh/uv/releases/download/$UV_VERSAO/uv-x86_64-pc-windows-msvc.zip" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath (Join-Path $Base 'uv') -Force
    Remove-Item $zip -Force
  }
  $env:UV_PYTHON_INSTALL_DIR = Join-Path $Base 'python'
  $env:UV_CACHE_DIR = Join-Path $Base 'cache'
  $env:UV_LINK_MODE = 'copy'
  $py = Join-Path $Base 'venv\Scripts\python.exe'
  if (-not (Test-Path $py)) {
    Passo 0.15 'Baixando o Python 3.11 (só para o motor)...'
    Rodar $uv @('venv', '--clear', '--force', '--python', '3.11', '--python-preference', 'only-managed', (Join-Path $Base 'venv'))
  }
  $temNvidia = Tem-Nvidia
  if ($temNvidia) {
    Passo 0.30 'Placa NVIDIA detectada. Baixando PyTorch com CUDA + Demucs...'
  } else {
    Passo 0.30 'Baixando PyTorch (CPU) + Demucs (~250 MB, pode levar alguns minutos)...'
  }
  Rodar $uv @('pip', 'install', '--python', $py, '-r', (Join-Path $KitDir 'requisitos_windows.txt'))
  if ($temNvidia) {
    Passo 0.55 'Trocando o PyTorch pela versão com CUDA...'
    Rodar $uv @('pip', 'install', '--python', $py, 'torch==2.2.2', 'torchaudio==2.2.2', '--index-url', 'https://download.pytorch.org/whl/cu118')
  }
  Passo 0.68 'Instalando o audio-separator (modo qualidade máxima)...'
  Rodar $uv @('pip', 'install', '--python', $py, 'audio-separator==0.48.0')
  # o audio-separator pode puxar outro torch; recoloca o que escolhemos
  if ($temNvidia) {
    Rodar $uv @('pip', 'install', '--python', $py, 'torch==2.2.2', 'torchaudio==2.2.2', '--index-url', 'https://download.pytorch.org/whl/cu118')
  } else {
    Rodar $uv @('pip', 'install', '--python', $py, 'torch==2.2.2', 'torchaudio==2.2.2')
  }
  Passo 0.85 'Baixando o modelo padrão htdemucs_6s (~80 MB)...'
  $env:MIK_MOTOR = $Base
  Rodar $py @((Join-Path $KitDir 'separar.py'), '--baixar-modelo')
  Passo 0.95 'Limpando arquivos temporários...'
  $ErrorActionPreference = 'Continue'; & $uv cache clean 2>&1 | Out-Null; $ErrorActionPreference = 'Stop'
  $torchKind = $(if ($temNvidia) { 'cuda' } else { 'cpu' })
  Set-Content -Path (Join-Path $Base 'versao.txt') -Value "motor=1`nuv=$UV_VERSAO`nmodelo=htdemucs_6s`ntorch=$torchKind`naudio_separator=0.48.0`n" -Encoding UTF8
  [IO.File]::WriteAllText($Status, "OK`n", (New-Object Text.UTF8Encoding $false))
  Write-Host '  Motor de separação instalado!' -ForegroundColor Green
  exit 0
} catch {
  $msg = ($_.Exception.Message -split "`n")[0]
  Add-Content -Path $Log -Value "ERRO: $msg" -Encoding UTF8
  [IO.File]::WriteAllText($Status, "ERRO $msg`n", (New-Object Text.UTF8Encoding $false))
  Write-Host "  ERRO: $msg" -ForegroundColor Red
  exit 1
}
