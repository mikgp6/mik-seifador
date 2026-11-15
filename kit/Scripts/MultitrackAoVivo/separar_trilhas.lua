-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - separar_trilhas.lua
  Separa a música onde está o cursor (música comum ou VS fechado) em
  BATERIA, BAIXO, GUITARRA, TECLADO, VOZ e OUTROS (motor Demucs 4 / htdemucs_6s)
  e coloca as 6 trilhas na BANDA, alinhadas com a original (que fica mutada).
  Roda sem travar o REAPER e avisa no fim. Na 1ª vez oferece instalar o motor.
  (Ao importar uma música de um arquivo só isso já acontece sozinho.)
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
MT.separar_musica_atual()
