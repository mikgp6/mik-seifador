-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - gerar_click_guia_cifra.lua
  Para a música onde está o cursor (música comum ou VS fechado):
  detecta o BPM e o 1º tempo, alinha a grade, gera CLICK, GUIA falada,
  SEÇÕES e CIFRA. Roda aos poucos (o REAPER não trava) e avisa no fim.
  (Ao importar uma música de um arquivo só isso já acontece sozinho.)
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
MT.analisar_musica_atual()
