-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - proxima_secao.lua
  Pula para a próxima seção (marcador) da música atual.
  Com 'Salto suave' ligado, o pulo acontece no fim do compasso.
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
if MT.pedal_solto() then return end -- ignora o 'soltar' do pedal MIDI
MT.proxima_secao()
MT.sem_undo()
