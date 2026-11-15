-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - motor_ao_vivo.lua
  Script de FUNDO: precisa ficar rodando durante o culto/show.
  Ele cuida de:
    * AUTO  -> no fim da música, já toca a próxima
    * HOLD  -> no fim da música, para e volta para o início dela
    * (nenhum) -> no fim da música, para e posiciona na próxima
    * LOOP / REPETIR CLICK -> o loop acompanha a seção para onde você pular
    * acende/apaga os botões da barra de ferramentas

  Rode uma vez (ou deixe no __startup.lua para abrir junto com o REAPER).
  Rodar de novo pelo Action List -> o REAPER pergunta se quer encerrar.
]]
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
-- REAPER 7.03+: rodar de novo = DESLIGA (sem perguntar)
if reaper.set_action_options then reaper.set_action_options(1 | 2) end
local r = reaper
-- Mik Seifador Remoto: o celular continua funcionando mesmo com o painel fechado
local REM
do
  local ok, m = pcall(function() return dofile(dir .. "mt_remoto.lua")(MT) end)
  if ok then REM = m end
end

local _, _, secao, cmd = r.get_action_context()
if cmd and cmd > 0 then
  r.SetToggleCommandState(secao, cmd, 1)
  r.RefreshToolbar2(secao, cmd)
end

local function sair()
  r.SetExtState(MT.SEC, "MOTOR_HB", "0", false)
  if cmd and cmd > 0 then
    r.SetToggleCommandState(secao, cmd, 0)
    r.RefreshToolbar2(secao, cmd)
  end
end
r.atexit(sair)

local function loop()
  r.SetExtState(MT.SEC, "MOTOR_HB", tostring(r.time_precise()), false)
  local ok, err = pcall(MT.tick)
  if not ok then
    pcall(function()
      if MT.registrar_erro then MT.registrar_erro("motor", err) end
    end)
  end
  if REM then pcall(REM.tick) end
  r.defer(loop)
end

MT.aviso("Motor Ao Vivo LIGADO")
loop()
