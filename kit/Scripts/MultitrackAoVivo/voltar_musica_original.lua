-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - voltar_musica_original.lua
  Tira as trilhas separadas (BATERIA, BAIXO, VOZ, OUTROS) da música atual
  e volta a tocar a música original. As trilhas continuam salvas em __stems
  (Separar trilhas de novo recoloca na hora, sem separar outra vez).
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
MT.desfazer_separacao()
