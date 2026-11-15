-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - proxima_musica.lua
  Vai para a próxima música do setlist (se estiver tocando, para e posiciona).
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
if MT.pedal_solto() then return end -- ignora o 'soltar' do pedal MIDI
MT.proxima_musica()
MT.sem_undo()
