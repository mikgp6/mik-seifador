-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - modo_lr_com_click.lua
  Liga/desliga o click+guia junto quando estiver no modo L/R.
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
if MT.pedal_solto() then return end -- ignora o 'soltar' do pedal MIDI
MT.alternar_lr_com_click()
MT.aviso("L/R com click: " .. (MT.get("LR_COM_CLICK", "0") == "1" and "SIM" or "NÃO"))
