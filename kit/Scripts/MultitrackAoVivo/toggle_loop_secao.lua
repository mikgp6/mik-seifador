-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - toggle_loop_secao.lua
  LOOP liga/desliga: repete a seção atual (loop nativo, sem falha).
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
if MT.pedal_solto() then return end -- ignora o 'soltar' do pedal MIDI
MT.registrar_toggle("LOOP")
MT.alternar_loop()
MT.sem_undo()
