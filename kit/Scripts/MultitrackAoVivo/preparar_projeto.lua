-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - preparar_projeto.lua
  Cria ou repara a estrutura (FONE, BANDA, subpastas, PAD) e aplica o modo de saída atual.
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
reaper.Undo_BeginBlock()
MT.aplicar_modo()
MT.gerar_todos_pads()
reaper.Undo_EndBlock("Preparar projeto Multitrack Ao Vivo", -1)
MT.aviso("Estrutura pronta - modo: " .. MT.modo())
