-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - renomear_secao.lua
  Renomeia a seção onde está o cursor (a guia falada acompanha o nome novo
  e o marcadores.txt da pasta da música é atualizado).
  No painel: duplo clique na seção ou tecla N.
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
MT.renomear_secao()
