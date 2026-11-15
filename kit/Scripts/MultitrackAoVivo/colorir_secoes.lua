-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - colorir_secoes.lua
  Recolore todos os marcadores conforme o nome (I, V, P, R, PONTE...).
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
MT.colorir_secoes()
