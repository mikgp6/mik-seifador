# Mik Seifador v1.8 — atualizações

Player de multitracks ao vivo para REAPER, criado por Miqueias Felix.

## Instalar do zero
Baixe o instalador na página de [Releases](https://github.com/mikgp6/mik-seifador/releases):
- **Windows:** `Mik-Seifador-v1.8-Instalador.zip` → descompacte e rode `Windows\INSTALAR.bat`.
- **Mac:** `Mik-Seifador-v1.8-Mac.pkg` → dois cliques e siga o instalador.

## Atualização automática
Depois de instalado, o próprio painel procura atualizações (no máximo uma vez por dia, sem travar).
Quando houver uma nova, aparece **"Atualização disponível — Atualizar"** no topo do painel.
Um clique baixa só os arquivos que mudaram, confere o SHA-256, faz backup em
`MultitrackAoVivo\_backups\update-<data>` e recarrega o painel. Também dá para procurar na hora em
**Menu › Procurar atualizações**. Sem internet, nada acontece.

## Conteúdo deste repositório
- `kit/` — arquivos atualizáveis (scripts .lua, separador .py, remoto do celular, mapa de atalhos).
  Sem modelos de separação, sem ambiente Python e sem backups.
- `manifest.json` — versão, build interna, data, lista de arquivos com SHA-256 e tamanho.
- `ferramentas/` — scripts para publicar uma nova build (`publicar_atualizacao.ps1` no Windows,
  `publicar_atualizacao.sh` no Linux/Mac).
