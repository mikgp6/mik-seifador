-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - exportar_trilhas.lua
  Exporta a música atual para qualquer DAW: pasta Exportar com as 6 trilhas
  separadas (as que existirem), click e guia em WAV (mesmo começo e mesmo
  comprimento), LEIA-ME.txt (BPM, compasso, seções) e MIDI de tempo/marcadores.
  Não abre prompt, não salva e não altera o projeto. No fim abre a pasta.
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
MT.exportar_trilhas()
