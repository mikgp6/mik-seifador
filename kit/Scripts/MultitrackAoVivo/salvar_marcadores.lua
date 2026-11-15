-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - salvar_marcadores.lua
  Salva as seções da música atual em 'marcadores.txt' na pasta da música
  (na próxima importação elas voltam sozinhas).
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
MT.salvar_marcadores()
MT.sem_undo()
