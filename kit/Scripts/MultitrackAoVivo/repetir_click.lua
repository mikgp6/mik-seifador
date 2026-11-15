-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - repetir_click.lua
  REPETIR CLICK liga/desliga: só o click, repetindo a seção atual em loop.
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
if MT.pedal_solto() then return end -- ignora o 'soltar' do pedal MIDI
MT.registrar_toggle("REPETIR_CLICK")
MT.alternar_repetir_click()
MT.sem_undo()
