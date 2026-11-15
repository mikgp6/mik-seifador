-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - toggle_hold.lua
  HOLD liga/desliga: ao terminar a música, para e volta pro início dela (não avança).
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
if MT.pedal_solto() then return end -- ignora o 'soltar' do pedal MIDI
MT.registrar_toggle("HOLD")
MT.alternar("HOLD", "HOLD")
MT.sem_undo()
