<#
  Mik Seifador - publicar uma atualização para todos (Windows)
  -----------------------------------------------------------
  Copia os arquivos atualizáveis do kit instalado neste PC para o repositório
  (pasta kit\), sobe a build, gera o manifest.json e faz commit + push na main.
  Quem tem o Mik Seifador recebe o aviso "Atualização disponível" no painel.

  Uso (PowerShell):
    powershell -ExecutionPolicy Bypass -File publicar_atualizacao.ps1 -Notas "o que mudou"
  Opções: -Repo <pasta do clone>  -Kit <pasta MultitrackAoVivo>  -SemPush

  Precisa: Git for Windows (winget install Git.Git) com login no GitHub
  (o Git Credential Manager abre o navegador na 1ª vez).
#>
param(
  [string]$Notas = "",
  [string]$Repo = (Join-Path ([Environment]::GetFolderPath("MyDocuments")) "Mik-Seifador-publicar"),
  [string]$Kit = (Join-Path $env:APPDATA "REAPER\Scripts\MultitrackAoVivo"),
  [string]$KeyMap = (Join-Path $env:APPDATA "REAPER\KeyMaps\MultitrackAoVivo.ReaperKeyMap"),
  [int]$Build = 0,
  [switch]$SemPush
)
$ErrorActionPreference = "Continue"   # git escreve no stderr; conferimos $LASTEXITCODE
$URL = "https://github.com/mikgp6/mik-seifador.git"
function Git { & git -C $Repo @args; if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') falhou" } }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Git não encontrado. Instale: winget install Git.Git" }

if (-not (Test-Path (Join-Path $Repo ".git"))) {
  if (Test-Path $Repo) {
    # pasta preparada sem .git: vira o clone
    & git -C $Repo init -b main | Out-Null
    & git -C $Repo remote add origin $URL 2>$null
    & git -C $Repo fetch origin 2>$null
    & git -C $Repo reset --soft origin/main 2>$null
  } else {
    & git clone $URL $Repo; if ($LASTEXITCODE -ne 0) { throw "git clone falhou" }
  }
}
& git -C $Repo pull --ff-only origin main 2>$null
& git -C $Repo rev-parse --verify -q origin/main 2>$null | Out-Null
$primeira = ($LASTEXITCODE -ne 0)   # repositório ainda vazio no GitHub

# ---------- arquivos do kit (mesmas regras do montar_publicacao.py) ----------
function NomeOk($n) {
  $b = $n.ToLower()
  if ($b -match '\.bak|\.original|\.pdf$|^como usar|^teste|^test_|^_|\.upd-old$') { return $false }
  return $true
}
$lista = New-Object System.Collections.Generic.List[string]
Get-ChildItem $Kit -File -Filter *.lua | Where-Object { (NomeOk $_.Name) } | Sort-Object Name | ForEach-Object { $lista.Add($_.Name) }
if (Test-Path "$Kit\separador") {
  Get-ChildItem "$Kit\separador" -File | Where-Object { $_.Extension -in ".py",".ps1",".sh",".txt" -and (NomeOk $_.Name) } | Sort-Object Name | ForEach-Object { $lista.Add("separador/" + $_.Name) }
}
if (Test-Path "$Kit\remoto_web") {
  Get-ChildItem "$Kit\remoto_web" -File -Recurse | Where-Object {
    (NomeOk $_.Name) -and ($_.FullName.Substring($Kit.Length) -notmatch '\\(bak-|_backups|__pycache__)|\.bak')
  } | ForEach-Object { $lista.Add(($_.FullName.Substring($Kit.Length + 1)) -replace '\\','/') }
}
$dstKit = Join-Path $Repo "kit\Scripts\MultitrackAoVivo"
if (Test-Path $dstKit) { Remove-Item $dstKit -Recurse -Force }
foreach ($rel in $lista) {
  $d = Join-Path $dstKit ($rel -replace '/','\')
  New-Item -ItemType Directory -Force (Split-Path $d) | Out-Null
  Copy-Item (Join-Path $Kit ($rel -replace '/','\')) $d -Force
}
if (Test-Path $KeyMap) {
  New-Item -ItemType Directory -Force (Join-Path $Repo "kit\KeyMaps") | Out-Null
  Copy-Item $KeyMap (Join-Path $Repo "kit\KeyMaps\MultitrackAoVivo.ReaperKeyMap") -Force
}

# ---------- build ----------
$manP = Join-Path $Repo "manifest.json"
$build = 1
if (Test-Path $manP) {
  try {
    $build = [int]((Get-Content $manP -Raw -Encoding UTF8 | ConvertFrom-Json).build)
    if (-not $primeira) { $build = $build + 1 }   # 1ª publicação mantém a build preparada
  } catch { $build = 1 }
}
if ($Build -gt 0) { $build = $Build }

Git add -A kit README.md .gitattributes ferramentas
& git -C $Repo diff --cached --quiet
if ($LASTEXITCODE -eq 0 -and -not $primeira) { Write-Host "Nada mudou no kit. Nenhuma atualização publicada."; exit 0 }
Git commit -q -m "kit: build $build"
$ref = (& git -C $Repo rev-parse HEAD).Trim()

# ---------- manifest ----------
$arqs = @()
$base = Join-Path $Repo "kit"
Get-ChildItem $base -File -Recurse | Sort-Object FullName | ForEach-Object {
  $arqs += [ordered]@{
    caminho = ($_.FullName.Substring($base.Length + 1) -replace '\\','/')
    sha256  = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    tamanho = $_.Length
  }
}
$man = [ordered]@{
  versao = "1.8"; build = $build; data = (Get-Date -Format "yyyy-MM-ddTHH:mm:sszzz")
  ref = $ref; arquivos = $arqs; notas = $Notas
}
$json = $man | ConvertTo-Json -Depth 5
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText($manP, $json + "`n", $utf8)
Git add manifest.json
Git commit -q -m "build $build`: $Notas"
if (-not $SemPush) { Git push origin main }

# este PC já fica na build nova (não oferece a própria atualização)
[IO.File]::WriteAllText((Join-Path $Kit "build.txt"), "$build`n", $utf8)
[IO.File]::WriteAllText((Join-Path $Kit "atualizacao_local.json"), $json + "`n", $utf8)
Write-Host "Publicado: build $build ($($arqs.Count) arquivos, ref $ref)"
