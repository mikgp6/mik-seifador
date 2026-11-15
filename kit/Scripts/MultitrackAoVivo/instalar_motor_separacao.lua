-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - instalar_motor_separacao.lua
  Instala (ou repara) o motor de separação de trilhas: uns 1 GB de download,
  uma vez só. Windows: %LOCALAPPDATA%\MikSeifador\motor
            Mac: ~/Library/Application Support/MikSeifador/motor
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
if MT.motor_instalado() and reaper.MB("O motor de separação já está instalado.\n\nInstalar/reparar de novo mesmo assim?",
  "Mik Seifador", 4) ~= 6 then return end
MT.instalar_motor(MT.motor_instalado())
