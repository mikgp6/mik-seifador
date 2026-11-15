-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - importar_multitrack.lua  (Ctrl+Shift+I)
  Importação RÁPIDA: escolha a pasta da música e pronto.
  - Entra a multitrack INTEIRA (todos os stems da pasta e das subpastas), no fim do setlist.
  - Escolheu uma subpasta de grupo (ex.: VS\Bateria)? ele sobe sozinho para a música inteira.
  - Nome, tom, BPM e compasso são detectados sozinhos (mt_info.txt, .als, nome da pasta).
    Só pergunta o TOM se não achar (deixe vazio para importar sem tom).
  - A pasta é COPIADA para a Biblioteca (o original não é mexido).
  - Com a extensão js_ReaScriptAPI abre uma janela de escolher PASTA; sem ela,
    escolha QUALQUER arquivo dentro da pasta.
  Quer revisar tudo (stems, nome, artista, BPM, mover/copiar)? Painel > Menu > Importar (avançado)...
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
MT.importar_rapido()
