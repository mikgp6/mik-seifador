-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - play_pause.lua
  Play / Pause.
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
if MT.pedal_solto() then return end -- ignora o 'soltar' do pedal MIDI
MT.play_pause()
MT.sem_undo()
