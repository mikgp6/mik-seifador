-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - modo_ao_vivo.lua
  Saídas no modo AO VIVO: placa de 2 saídas = Click+Guia na 1 e Banda na 2;
  placa de 4+ saídas = Click 1, Guia 2, Banda 3/4 (ou o perfil escolhido em "Saídas").
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
if MT.pedal_solto() then return end -- ignora o 'soltar' do pedal MIDI
MT.registrar_toggle("MODO_AO_VIVO")
MT.modo_ao_vivo()
