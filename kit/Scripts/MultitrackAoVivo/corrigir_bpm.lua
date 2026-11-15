-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - corrigir_bpm.lua
  O BPM detectado ficou no dobro ou na metade? Digite o certo (e o compasso)
  e o kit refaz click, guia, seções e cifra da música atual.
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
MT.corrigir_bpm()
