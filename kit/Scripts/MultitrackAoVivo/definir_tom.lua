-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - definir_tom.lua
  Define o tom ORIGINAL da música atual (fica no nome da região: 'Nome [G]').
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
MT.definir_tom()
