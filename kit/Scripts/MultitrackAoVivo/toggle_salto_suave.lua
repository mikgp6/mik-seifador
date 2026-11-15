-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - toggle_salto_suave.lua
  Liga/desliga o 'Salto suave' (smooth seek) do REAPER:
  os pulos de seção esperam o fim do compasso.
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
if MT.pedal_solto() then return end -- ignora o 'soltar' do pedal MIDI
MT.registrar_toggle("SALTO_SUAVE")
MT.alternar_salto_suave()
