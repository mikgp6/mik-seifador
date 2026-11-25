-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - painel_ao_vivo.lua  (visual console ao vivo, v1.8)
  Topo: transporte (música anterior, PLAY/PAUSE, próxima, STOP, AUTO, HOLD, LOOP),
        setlist em quadrados (capa da pasta da música, se houver), saídas
        (L/R, Ao Vivo, Studio), tom e Menu.
  Meio: forma de onda da música com as seções coloridas (clique = pular),
        régua com compassos e cursor de reprodução.
  Barra: tempo, BPM (- / + / R), compasso, IR, Solo Click, Loop Click, PAD.
  Baixo: mixer com um canal por stem (pan, mute, solo, fader e medidor) e
        PAD, GUIA, CLICK e MASTER à direita.

  IMPORTAR (botão verde no topo, ao lado da Biblioteca): escolha a pasta da
  música e pronto - ou ARRASTE a pasta (ou vários) do Explorer/Finder para
  dentro do painel. Só pergunta o tom se não conseguir descobrir sozinho.

  MÚSICA COMUM / VS FECHADO: importou um arquivo só? O kit gera sozinho click,
  guia falada, seções e cifra (o acorde atual aparece em cima da forma de onda).
  Duplo clique numa seção (ou tecla N) = renomear. Menu > Corrigir BPM.

  Precisa da extensão ReaImGui (instale pelo ReaPack).
  Se o motor_ao_vivo.lua não estiver rodando, o próprio painel faz o papel
  dele enquanto estiver aberto.

  Teclas com o painel em foco:
    Espaço = Play/Pause      Esc = Stop (volta ao início da música)
    Seta → / ← = próxima / anterior seção
    Page Down / Page Up = próxima / anterior música
    + / - = Tom   A = AUTO   H = HOLD   L = LOOP   C = SOLO CLICK   P = PAD
  Mixer: arraste o fader/knob; duplo clique volta ao padrão (0 dB / centro);
         roda do mouse = ajuste fino.
]]
local r = reaper
local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
local MT = dofile(dir .. "mt_lib.lua")
-- Mik Seifador Remoto (celular): publica o estado e recebe os comandos do navegador
local REM, QR
do
  local ok, m = pcall(function() return dofile(dir .. "mt_remoto.lua")(MT) end)
  if ok then REM = m end
  local okq, q = pcall(dofile, dir .. "mt_qr.lua")
  if okq then QR = q end
end
local function secoes_grandes() return MT.get("SECOES_GRANDES", "0") == "1" end
-- REAPER 7.03+: rodar de novo = DESLIGA (sem perguntar)
if reaper.set_action_options then reaper.set_action_options(1 | 2) end

if not r.ImGui_GetBuiltinPath then
  r.MB("O painel precisa da extensão ReaImGui.\n\n" ..
    "Instale pelo ReaPack:\n  Extensions > ReaPack > Browse packages...\n" ..
    "  procure \"ReaImGui\" > clique com o botão direito > Install > Apply\n" ..
    "Depois reinicie o REAPER.\n\n" ..
    "Todos os outros scripts (atalhos e pedal) funcionam sem o painel.",
    "Painel Mik Seifador", 0)
  return
end

package.path = r.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.9"
-- O shim do ReaImGui (imgui.lua) DÁ ERRO ao ler um campo que não existe
-- (não devolve nil). Nunca use `if ImGui.Foo then`. Confira no reaper:
local function tem_imgui(nome)
  return r["ImGui_" .. nome] ~= nil
end
local function imgui_opcional(nome, padrao)
  if not tem_imgui(nome) then return padrao end
  local ok, v = pcall(function() return ImGui[nome] end)
  if ok and v ~= nil then return v end
  return padrao
end

local ctx = ImGui.CreateContext("Multitrack Ao Vivo")

-- fontes (se falhar, usa a fonte padrão)
local F = {}
do
  local function nova(nome, tam, flags)
    local ok, f = pcall(ImGui.CreateFont, "sans-serif", tam, flags)
    if ok and f then
      local ok2 = pcall(ImGui.Attach, ctx, f)
      if ok2 then F[nome] = f end
    end
  end
  local negrito = 0
  pcall(function() negrito = ImGui.FontFlags_Bold end)
  nova("base", 15)
  nova("peq", 12)
  nova("mini", 11)
  nova("dica", 10)
  nova("media", 19, negrito)
  nova("grande", 30, negrito)
  nova("lcd", 26, negrito)
  nova("tile", 13, negrito)
  nova("lane", 14, negrito)
  nova("capa_g", 64, negrito)   -- capa animada
  nova("capa_m", 20, negrito)
  nova("capa_p", 14)
  nova("capa_gx", 128, negrito)   -- capa em alta resolução (reduzida com AddTextEx)
  nova("capa_mx", 48, negrito)
  nova("capa_px", 36)
end
local function com_fonte(f, fn, ...)
  if f then ImGui.PushFont(ctx, f) end
  local a, b, c = fn(...)
  if f then ImGui.PopFont(ctx) end
  return a, b, c
end

-- botão da barra de ferramentas acende enquanto o painel está aberto
local _, _, secao_cmd, id_cmd = r.get_action_context()
if id_cmd and id_cmd > 0 then r.SetToggleCommandState(secao_cmd, id_cmd, 1); r.RefreshToolbar2(secao_cmd, id_cmd) end
r.atexit(function()
  if id_cmd and id_cmd > 0 then r.SetToggleCommandState(secao_cmd, id_cmd, 0); r.RefreshToolbar2(secao_cmd, id_cmd) end
end)

---------------------------------------------------------------------------
-- cores (formato 0xRRGGBBAA)
---------------------------------------------------------------------------
local function rgba(rr, gg, bb, a) return ((rr & 255) << 24) | ((gg & 255) << 16) | ((bb & 255) << 8) | (a or 255) end
local function de_nativa(c, padrao)
  if not c or c == 0 then return padrao end
  local rr, gg, bb = r.ColorFromNative(c & 0xFFFFFF)
  return rgba(rr, gg, bb)
end
local function ajustar(c, f)
  local rr, gg, bb, a = (c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255, c & 255
  local function lim(v) v = math.floor(v * f); if v > 255 then v = 255 end; if v < 0 then v = 0 end; return v end
  return rgba(lim(rr), lim(gg), lim(bb), a)
end
local function alfa(c, a) return (c & 0xFFFFFF00) | (math.floor(a) & 255) end

local C = {
  fundo    = 0x0C0E12FF, painel = 0x161A20FF, painel2 = 0x1E232BFF, painel3 = 0x2A303AFF,
  borda    = 0x3A424EFF, texto  = 0xF2F4F8FF, texto2  = 0x8B93A3FF, texto3  = 0x5C6574FF,
  acento   = 0x4EC8E8FF, lavanda = 0x8ED8ECFF, acento_esc = 0x1A3A48FF, acento_fundo = 0x102028FF,
  escuro   = 0x0A0C10FF, onda_tocada = 0xF4F1EAFF, onda = 0x5A6270FF,
  verde    = 0x3DDC84FF, amarelo = 0xF2B23AFF, vermelho = 0xE5484DFF, ciano = 0x4EC8E8FF,
  lcd      = 0x7EE8F4FF, lcd_bg   = 0x07090CFF,
}

-- flags opcionais do draw list (0 = todos os cantos / ignorar)
local DRAW_ROUND_TOP = imgui_opcional("DrawFlags_RoundCornersTop", 0)
local DRAW_ROUND_BOTTOM = imgui_opcional("DrawFlags_RoundCornersBottom", 0)

local function mmss(t)
  if not t or t < 0 then t = 0 end
  return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
end

---------------------------------------------------------------------------
-- ações pedidas pelo painel (executadas FORA do frame, pois algumas abrem janelas)
---------------------------------------------------------------------------
local pendente = nil
local function depois(fn) pendente = fn end

---------------------------------------------------------------------------
-- dicas (tooltips): fonte menor, atraso curto, só as 3 primeiras vezes
---------------------------------------------------------------------------
local DICA_VEZES, DICA_ATRASO = 3, 0.55
local dica_t0, dica_ja, dica_visto = {}, {}, {}

local function dicas_ligadas()
  return MT.get("DICAS", "1") ~= "0"
end

local function dicas_ler()
  local t, s = {}, MT.get("DICAS_N", "")
  for k, v in string.gmatch(s, "([^;=]+)=(%d+)") do t[k] = tonumber(v) or 0 end
  return t
end

local function dicas_gravar(t)
  local p = {}
  for k, v in pairs(t) do
    if v and v > 0 then p[#p + 1] = k .. "=" .. tostring(v) end
  end
  table.sort(p)
  MT.set("DICAS_N", table.concat(p, ";"))
end

local function dicas_resetar()
  MT.set("DICAS", "1")
  MT.set("DICAS_N", "")
  dica_t0, dica_ja, dica_visto = {}, {}, {}
  MT.aviso("Dicas ligadas de novo (cada botão mostra a dica 3 vezes).")
end

local function dicas_desligar()
  MT.set("DICAS", "0")
  dica_t0, dica_ja, dica_visto = {}, {}, {}
  MT.aviso("Dicas desligadas. Menu > Mostrar dicas de novo para reativar.")
end

local function dica_fim_frame()
  for id in pairs(dica_t0) do
    if not dica_visto[id] then dica_t0[id] = nil; dica_ja[id] = nil end
  end
  dica_visto = {}
end

local function dica(id, texto)
  if not texto or texto == "" then return end
  if not dicas_ligadas() then return end
  if not ImGui.IsItemHovered(ctx) then return end
  id = tostring(id or texto)
  dica_visto[id] = true
  local cont = dicas_ler()
  if (cont[id] or 0) >= DICA_VEZES then return end
  local agora = r.time_precise()
  dica_t0[id] = dica_t0[id] or agora
  if agora - dica_t0[id] < DICA_ATRASO then return end
  if not dica_ja[id] then
    dica_ja[id] = true
    cont[id] = (cont[id] or 0) + 1
    dicas_gravar(cont)
  end
  local ok_bt = false
  if tem_imgui("BeginTooltip") then
    local padding = tem_imgui("StyleVar_WindowPadding")
    if padding then ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 7, 5) end
    ok_bt = ImGui.BeginTooltip(ctx)
    if ok_bt then
      com_fonte(F.dica or F.mini or F.peq, function()
        if tem_imgui("PushTextWrapPos") then ImGui.PushTextWrapPos(ctx, 280) end
        ImGui.Text(ctx, texto)
        if tem_imgui("PopTextWrapPos") then ImGui.PopTextWrapPos(ctx) end
      end)
      if tem_imgui("EndTooltip") then ImGui.EndTooltip(ctx) end
    end
    if padding then ImGui.PopStyleVar(ctx) end
  end
  if not ok_bt then
    -- fallback: tooltip nativo (sem fonte menor)
    ImGui._SetTooltipNativo(ctx, texto)
  end
end

-- Wrapper: chave = texto da dica (estável). NÃO use GetItemID — esta
-- versão do ReaImGui não exporta ImGui_GetItemID e o shim explode.
ImGui._SetTooltipNativo = ImGui.SetTooltip
function ImGui.SetTooltip(c, texto)
  local chave = "t:" .. (tostring(texto or ""):gsub("%s+", " "):sub(1, 80))
  dica(chave, texto)
end

---------------------------------------------------------------------------
-- auxiliares de desenho
---------------------------------------------------------------------------
local dl -- draw list da janela atual
local salvar_projeto_painel -- definido mais abaixo (botão Salvar / Ctrl+S)

local function texto_tam(txt) return ImGui.CalcTextSize(ctx, txt) end

local function cortar(txt, w)
  if texto_tam(txt) <= w then return txt end
  local s = txt
  while #s > 1 and texto_tam(s .. "..") > w do
    s = s:sub(1, -2)
    -- não deixa um caractere UTF-8 pela metade
    while #s > 0 and (s:byte(-1) & 0xC0) == 0x80 do s = s:sub(1, -2) end
    if #s > 0 and s:byte(-1) >= 0xC0 then s = s:sub(1, -2) end
  end
  return s .. ".."
end

local function texto_centro(x1, y1, x2, y2, txt, cor)
  local tw, th = texto_tam(txt)
  ImGui.DrawList_AddText(dl, math.floor(x1 + (x2 - x1 - tw) / 2), math.floor(y1 + (y2 - y1 - th) / 2), cor, txt)
end

-- quebra o texto em até n linhas que caibam em w
local function quebrar(txt, w, n)
  local linhas, atual = {}, ""
  for palavra in tostring(txt):gmatch("%S+") do
    local teste = atual == "" and palavra or (atual .. " " .. palavra)
    if texto_tam(teste) <= w or atual == "" then atual = teste
    else linhas[#linhas + 1] = atual; atual = palavra end
  end
  if atual ~= "" then linhas[#linhas + 1] = atual end
  if #linhas > n then
    local resto = table.concat(linhas, " ", n)
    for k = #linhas, n + 1, -1 do linhas[k] = nil end
    linhas[n] = cortar(resto, w)
  end
  for k = 1, #linhas do linhas[k] = cortar(linhas[k], w) end
  return linhas
end

local function nome_sem_numero(nome)
  return (tostring(nome or ""):gsub("^%d+%.%s*", ""))
end

-- quebra por palavra, preferindo " - " (número já vai no badge; artista / música / resto)
local function quebrar_titulo(nome, w, nlinhas)
  nlinhas = nlinhas or 3
  local resto = nome_sem_numero(nome)
  local segs = {}
  local NL = string.char(10)
  local marcado = resto:gsub("%s+%-%s+", NL)
  marcado = marcado .. NL
  for seg in marcado:gmatch("(.-)" .. NL) do
    if seg ~= "" then
      local q = quebrar(seg, w, nlinhas)
      for _, ln in ipairs(q) do segs[#segs + 1] = ln end
    end
  end
  if #segs == 0 then segs[1] = resto end
  local overflow = #segs > nlinhas
  if overflow then
    local resto2 = table.concat(segs, " ", nlinhas)
    for k = #segs, nlinhas + 1, -1 do segs[k] = nil end
    segs[nlinhas] = cortar(resto2, w)
  else
    for k = 1, #segs do
      if segs[k] and segs[k]:sub(-2) == ".." then overflow = true end
    end
  end
  return segs, overflow
end

local function fade_bordas(x1, y1, x2, y2, cor, fade)
  fade = fade or 16
  if not tem_imgui("DrawList_AddRectFilledMultiColor") then return end
  if x2 - x1 < fade * 2 then return end
  local t0 = cor
  local t1 = alfa(cor, 0)
  pcall(ImGui.DrawList_AddRectFilledMultiColor, dl, x1, y1, x1 + fade, y2, t0, t1, t1, t0)
  pcall(ImGui.DrawList_AddRectFilledMultiColor, dl, x2 - fade, y1, x2, y2, t1, t0, t0, t1)
end

-- área clicável genérica: devolve clicou, passando, segurando
local function area(id, x, y, w, h)
  ImGui.SetCursorScreenPos(ctx, x, y)
  local clicou = ImGui.InvisibleButton(ctx, id, math.max(1, w), math.max(1, h))
  local passando = ImGui.IsItemHovered(ctx)
  local segurando = ImGui.IsItemActive(ctx)
  if passando then ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand) end
  return clicou, passando, segurando
end

-- ReaImGui 0.10: se SetCursorPos/SetCursorScreenPos for a última coisa da janela,
-- o ImGui.End derruba o script. Sempre submeta um item depois (Dummy 0x0).
local function imgui_dummy()
  pcall(ImGui.Dummy, ctx, 0, 0)
end

-- ícones simples desenhados (não dependem de fonte)
local ICONE = {}
function ICONE.play(cx, cy, s, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx - s * 0.30, cy - s * 0.48, cx - s * 0.30, cy + s * 0.48, cx + s * 0.54, cy, cor)
end
function ICONE.pause(cx, cy, s, cor)
  local w = s * 0.26
  ImGui.DrawList_AddRectFilled(dl, cx - s * 0.40, cy - s * 0.48, cx - s * 0.40 + w, cy + s * 0.48, cor, 2)
  ImGui.DrawList_AddRectFilled(dl, cx + s * 0.40 - w, cy - s * 0.48, cx + s * 0.40, cy + s * 0.48, cor, 2)
end
function ICONE.stop(cx, cy, s, cor)
  ImGui.DrawList_AddRectFilled(dl, cx - s * 0.38, cy - s * 0.38, cx + s * 0.38, cy + s * 0.38, cor, 3)
end
function ICONE.nota(cx, cy, s, cor)
  -- clave simples (placeholder quando ainda não há capa)
  ImGui.DrawList_AddCircleFilled(dl, cx - s * 0.28, cy + s * 0.42, s * 0.28, cor, 16)
  ImGui.DrawList_AddRectFilled(dl, cx + s * 0.08, cy - s * 0.62, cx + s * 0.20, cy + s * 0.42, cor, 1)
  ImGui.DrawList_AddLine(dl, cx + s * 0.20, cy - s * 0.62, cx + s * 0.55, cy - s * 0.40, cor, 2)
end
function ICONE.rec(cx, cy, s, cor)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, s * 0.42, cor, 20)
end
function ICONE.anterior(cx, cy, s, cor)
  ImGui.DrawList_AddRectFilled(dl, cx - s * 0.5, cy - s * 0.45, cx - s * 0.32, cy + s * 0.45, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx + s * 0.45, cy - s * 0.45, cx + s * 0.45, cy + s * 0.45, cx - s * 0.3, cy, cor)
end
function ICONE.proxima(cx, cy, s, cor)
  ImGui.DrawList_AddRectFilled(dl, cx + s * 0.32, cy - s * 0.45, cx + s * 0.5, cy + s * 0.45, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx - s * 0.45, cy - s * 0.45, cx - s * 0.45, cy + s * 0.45, cx + s * 0.3, cy, cor)
end
function ICONE.sec_ant(cx, cy, s, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx + s * 0.05, cy - s * 0.42, cx + s * 0.05, cy + s * 0.42, cx - s * 0.5, cy, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx + s * 0.55, cy - s * 0.42, cx + s * 0.55, cy + s * 0.42, cx, cy, cor)
end
function ICONE.sec_prox(cx, cy, s, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx - s * 0.05, cy - s * 0.42, cx - s * 0.05, cy + s * 0.42, cx + s * 0.5, cy, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx - s * 0.55, cy - s * 0.42, cx - s * 0.55, cy + s * 0.42, cx, cy, cor)
end
function ICONE.auto(cx, cy, s, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx - s * 0.5, cy - s * 0.35, cx - s * 0.5, cy + s * 0.35, cx, cy, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx, cy - s * 0.35, cx, cy + s * 0.35, cx + s * 0.5, cy, cor)
end
function ICONE.hold(cx, cy, s, cor)
  ImGui.DrawList_AddLine(dl, cx - s * 0.5, cy, cx + s * 0.2, cy, cor, 2)
  ImGui.DrawList_AddTriangleFilled(dl, cx + s * 0.05, cy - s * 0.25, cx + s * 0.05, cy + s * 0.25, cx + s * 0.32, cy, cor)
  ImGui.DrawList_AddRectFilled(dl, cx + s * 0.38, cy - s * 0.4, cx + s * 0.5, cy + s * 0.4, cor)
end
function ICONE.loop(cx, cy, s, cor)
  ImGui.DrawList_AddCircle(dl, cx, cy, s * 0.42, cor, 24, 2)
  ImGui.DrawList_AddTriangleFilled(dl, cx + s * 0.10, cy - s * 0.56, cx + s * 0.10, cy - s * 0.22, cx + s * 0.38, cy - s * 0.39, cor)
end
function ICONE.lr(cx, cy, s, cor)
  ImGui.DrawList_AddCircle(dl, cx - s * 0.25, cy, s * 0.22, cor, 16, 2)
  ImGui.DrawList_AddCircle(dl, cx + s * 0.25, cy, s * 0.22, cor, 16, 2)
end
function ICONE.aovivo(cx, cy, s, cor)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy, s * 0.14, cor, 12)
  ImGui.DrawList_AddCircle(dl, cx, cy, s * 0.3, cor, 20, 1.5)
  ImGui.DrawList_AddCircle(dl, cx, cy, s * 0.48, alfa(cor, 120), 24, 1.5)
end
function ICONE.studio(cx, cy, s, cor)
  for k = -1, 1 do
    local x = cx + k * s * 0.32
    ImGui.DrawList_AddLine(dl, x, cy - s * 0.45, x, cy + s * 0.45, cor, 2)
    local yk = cy + (k == 0 and -0.15 or 0.2) * s
    ImGui.DrawList_AddRectFilled(dl, x - s * 0.1, yk - s * 0.07, x + s * 0.1, yk + s * 0.07, cor, 1)
  end
end
function ICONE.menu(cx, cy, s, cor)
  for k = -1, 1 do
    ImGui.DrawList_AddRectFilled(dl, cx - s * 0.42, cy + k * s * 0.3 - 1, cx + s * 0.42, cy + k * s * 0.3 + 1, cor, 1)
  end
end
function ICONE.lixo(cx, cy, s, cor)
  -- lixeira simples
  ImGui.DrawList_AddRectFilled(dl, cx - s * 0.22, cy - s * 0.52, cx + s * 0.22, cy - s * 0.38, cor, 1)
  ImGui.DrawList_AddRectFilled(dl, cx - s * 0.08, cy - s * 0.62, cx + s * 0.08, cy - s * 0.52, cor, 1)
  ImGui.DrawList_AddRect(dl, cx - s * 0.36, cy - s * 0.32, cx + s * 0.36, cy + s * 0.52, cor, 2, 0, 2)
  for k = -1, 1 do
    local x = cx + k * s * 0.16
    ImGui.DrawList_AddLine(dl, x, cy - s * 0.18, x, cy + s * 0.36, cor, 1.5)
  end
end
function ICONE.disquete(cx, cy, s, cor)
  -- disquete: corpo, janela de metal em cima e etiqueta embaixo
  local h = s * 0.46
  ImGui.DrawList_AddRect(dl, cx - h, cy - h, cx + h, cy + h, cor, 2, 0, 1.6)
  ImGui.DrawList_AddRectFilled(dl, cx - h * 0.55, cy - h, cx + h * 0.45, cy - h * 0.3, cor, 1)
  ImGui.DrawList_AddRect(dl, cx - h * 0.62, cy + h * 0.1, cx + h * 0.62, cy + h, cor, 1, 0, 1.3)
end
function ICONE.biblio(cx, cy, s, cor)
  -- três "capas" de pé, como numa estante
  local w = s * 0.24
  for k = -1, 1 do
    local x = cx + k * (w + s * 0.08)
    ImGui.DrawList_AddRectFilled(dl, x - w / 2, cy - s * 0.42, x + w / 2, cy + s * 0.42, cor, 1)
  end
end
function ICONE.mais(cx, cy, s, cor)
  local e = math.max(2, s * 0.14)
  ImGui.DrawList_AddRectFilled(dl, cx - s * 0.5, cy - e, cx + s * 0.5, cy + e, cor, 1)
  ImGui.DrawList_AddRectFilled(dl, cx - e, cy - s * 0.5, cx + e, cy + s * 0.5, cor, 1)
end
function ICONE.esq(cx, cy, s, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx + s * 0.25, cy - s * 0.4, cx + s * 0.25, cy + s * 0.4, cx - s * 0.25, cy, cor)
end
function ICONE.dir(cx, cy, s, cor)
  ImGui.DrawList_AddTriangleFilled(dl, cx - s * 0.25, cy - s * 0.4, cx - s * 0.25, cy + s * 0.4, cx + s * 0.25, cy, cor)
end
function ICONE.trava(cx, cy, s, cor)
  -- cadeado fechado (bem visível)
  ImGui.DrawList_AddRectFilled(dl, cx - s * 0.38, cy - s * 0.02, cx + s * 0.38, cy + s * 0.52, cor, 3)
  ImGui.DrawList_AddCircle(dl, cx, cy - s * 0.22, s * 0.28, cor, 16, 2.4)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy + s * 0.22, s * 0.08, 0x0C0E12FF, 10)
end
function ICONE.trava_aberta(cx, cy, s, cor)
  ImGui.DrawList_AddRectFilled(dl, cx - s * 0.38, cy - s * 0.02, cx + s * 0.38, cy + s * 0.52, cor, 3)
  ImGui.DrawList_AddCircle(dl, cx + s * 0.18, cy - s * 0.22, s * 0.28, cor, 16, 2.4)
  ImGui.DrawList_AddCircleFilled(dl, cx, cy + s * 0.22, s * 0.08, 0x0C0E12FF, 10)
end

-- clip do draw list (nunca lê campo ausente no shim do ReaImGui)
local function clip_ini(x1, y1, x2, y2)
  if not tem_imgui("DrawList_PushClipRect") then return false end
  pcall(ImGui.DrawList_PushClipRect, dl, x1, y1, x2, y2, true)
  return true
end
local function clip_fim()
  if tem_imgui("DrawList_PopClipRect") then pcall(ImGui.DrawList_PopClipRect, dl) end
end

-- relevo discreto (DAW): sombra suave, gradiente sutil, borda 1 px clara em cima e escura embaixo
-- devolve o deslocamento vertical do desenho (1 px se estiver pressionado)
local function desenhar_relevo(x, y, w, h, fundo, rds, passando, segurando, ativo)
  rds = rds or 6
  local oy = 0
  if segurando then
    oy = 1
    fundo = ajustar(fundo, 0.92)
  else
    ImGui.DrawList_AddRectFilled(dl, x + 1, y + 1, x + w + 1, y + h + 2, 0x00000040, rds)
  end
  local yy = y + oy
  ImGui.DrawList_AddRectFilled(dl, x, yy, x + w, yy + h, fundo, rds)
  if not segurando then
    ImGui.DrawList_AddRectFilled(dl, x + 1, yy + 1, x + w - 1, yy + math.max(3, h * 0.42), ativo and 0xFFFFFF18 or 0xFFFFFF12, rds)
  end
  -- borda 1 px: clara no topo, escura embaixo (sem contorno grosso)
  ImGui.DrawList_AddLine(dl, x + rds, yy + 0.5, x + w - rds, yy + 0.5, 0xFFFFFF2A, 1)
  ImGui.DrawList_AddLine(dl, x + rds, yy + h - 0.5, x + w - rds, yy + h - 0.5, 0x00000050, 1)
  local borda
  if passando then borda = alfa(C.acento, 160)
  elseif ativo then borda = ajustar(fundo, 1.10)
  else borda = C.borda end
  ImGui.DrawList_AddRect(dl, x, yy, x + w, yy + h, borda, rds, 0, 1)
  return oy
end

local function sep_grupo(x, y, h)
  ImGui.DrawList_AddLine(dl, x + 0.5, y + 5, x + 0.5, y + h - 5, 0xFFFFFF16, 1)
  ImGui.DrawList_AddLine(dl, x + 1.5, y + 5, x + 1.5, y + h - 5, 0x00000040, 1)
  return x + 8
end

-- rótulo que cabe no botão; mede na MESMA fonte do desenho.
-- se não couber, corta com ".." (o texto cheio vai no tooltip só no hover)
local function rotulo_cabivel(rotulo, w, fonte)
  if not rotulo or rotulo == "" then return nil, false end
  local vis, cortou
  com_fonte(fonte or F.dica or F.mini, function()
    local maxw = math.max(4, w - 6)
    if texto_tam(rotulo) <= maxw then vis, cortou = rotulo, false; return end
    local t = cortar(rotulo, maxw)
    if not t or t == "" or t == ".." then vis, cortou = nil, true; return end
    vis, cortou = t, true
  end)
  return vis, cortou
end

-- botão quadrado com ícone e rótulo pequeno (console escuro, cantos arredondados)
local function botao_icone(id, x, y, w, h, icone, rotulo, ativo, cor_ativo)
  local clicou, passando, segurando = area(id, x, y, w, h)
  local rds = 7
  local fundo = ativo and (cor_ativo or C.acento) or (passando and C.painel3 or C.painel2)
  local oy = desenhar_relevo(x, y, w, h, fundo, rds, passando, segurando, ativo)
  local cor = ativo and 0x0C0E12FF or (passando and C.texto or 0xD0D4DCFF)
  local fonte_rot = F.peq or F.mini
  local vis, cortou = rotulo_cabivel(rotulo, w, fonte_rot)
  local tem_rot = vis ~= nil
  local cy = y + oy + (tem_rot and (h * 0.36) or (h / 2))
  local s = math.min(w, h) * (tem_rot and 0.34 or 0.42)
  if icone and ICONE[icone] then ICONE[icone](x + w / 2, cy, s, cor) end
  if tem_rot then
    local yy = y + oy
    local temc = clip_ini(x + 2, yy, x + w - 2, yy + h)
    com_fonte(fonte_rot, function() texto_centro(x, yy + h * 0.64, x + w, yy + h - 2, vis, cor) end)
    if temc then clip_fim() end
  end
  if cortou and passando and rotulo then ImGui.SetTooltip(ctx, rotulo) end
  return clicou
end

-- botão de destaque (cor cheia) - usado no IMPORTAR
local function botao_destaque(id, x, y, w, h, icone, rotulo, cor_base)
  local clicou, passando, segurando = area(id, x, y, w, h)
  local fundo = cor_base
  if passando and not segurando then fundo = ajustar(cor_base, 1.08) end
  local oy = desenhar_relevo(x, y, w, h, fundo, 7, passando, segurando, true)
  local cor = 0x0C1210FF
  local fonte_rot = F.peq or F.mini
  local vis, cortou = rotulo_cabivel(rotulo, w, fonte_rot)
  local cy = y + oy + h * 0.36
  local s = math.min(w, h) * 0.34
  if icone and ICONE[icone] then ICONE[icone](x + w / 2, cy, s, cor) end
  if vis then
    local yy = y + oy
    local temc = clip_ini(x + 2, yy, x + w - 2, yy + h)
    com_fonte(fonte_rot, function() texto_centro(x, yy + h * 0.64, x + w, yy + h - 2, vis, cor) end)
    if temc then clip_fim() end
  end
  if cortou and passando and rotulo then ImGui.SetTooltip(ctx, rotulo) end
  return clicou
end

-- arrastar e soltar pastas/arquivos do Explorer/Finder = importar
-- (só se a versão do ReaImGui tiver a função; rawget evita erro em versões antigas)
local TEM_SOLTAR = rawget(ImGui, "BeginDragDropTarget") and rawget(ImGui, "AcceptDragDropPayloadFiles")
  and rawget(ImGui, "GetDragDropPayloadFile") and rawget(ImGui, "EndDragDropTarget") and true or false
local function alvo_soltar_arquivos()
  if not TEM_SOLTAR then return end
  if not ImGui.BeginDragDropTarget(ctx) then return end
  local ok, n = ImGui.AcceptDragDropPayloadFiles(ctx)
  if ok and n and n > 0 then
    local lista = {}
    for i = 0, n - 1 do
      local ok2, arq = ImGui.GetDragDropPayloadFile(ctx, i)
      if ok2 and arq and arq ~= "" then lista[#lista + 1] = arq end
    end
    if #lista > 0 then depois(function() MT.importar_varias(lista) end) end
  end
  ImGui.EndDragDropTarget(ctx)
end

-- botão de texto (chip) na barra de informações
local function chip(id, x, y, w, h, txt, ativo, cor_ativo)
  local clicou, passando, segurando = area(id, x, y, w, h)
  local fundo = ativo and (cor_ativo or C.lavanda) or (passando and C.painel3 or C.painel2)
  if segurando then fundo = ajustar(fundo, 1.2) end
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, fundo, 6)
  if not ativo then ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, C.borda, 6, 0, 1) end
  texto_centro(x, y, x + w, y + h, txt, ativo and 0x14121FFF or (passando and C.texto or 0xC8C8D6FF))
  return clicou
end

local function caixa(x, y, w, h, cor)
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, cor or C.painel2, 6)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, C.borda, 6, 0, 1)
end

---------------------------------------------------------------------------
-- capas das músicas (imagem .jpg/.png na pasta dos stems)
---------------------------------------------------------------------------
local biblio = { lista = nil, busca = "" }
local abrir_biblio = false
local abrir_sobre = false
local abrir_limpar = false
local abrir_importar = false
local saidas_ui = { abrir = false, t = 0 }
local limpar_ui = { musicas = {}, sel = {}, lixo = { qtd = 0, bytes = 0 }, incluir_lixo = false, confirma = false, busca = "" }
local pads_ui = { abrir = false }
local cel_ui = { abrir = false, porta = "8080", usuario = "", senha = "", ip_sel = 1 }
local capas = {}          -- nome da música -> { img = ImGui_Image | false }
local EXT_IMG = { jpg = true, jpeg = true, png = true }

-- pastas (sem repetir) dos arquivos de áudio da música
local function pastas_da_musica(m)
  local lista, vistas = {}, {}
  for i = 0, r.CountMediaItems(0) - 1 do
    local it = r.GetMediaItem(0, i)
    local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
    if p >= m.inicio - 0.01 and p < m.fim then
      local tk = r.GetActiveTake(it)
      if tk and not r.TakeIsMIDI(tk) then
        local src = r.GetMediaItemTake_Source(tk)
        local pai = r.GetMediaSourceParent and r.GetMediaSourceParent(src)
        if pai then src = pai end
        local arq = r.GetMediaSourceFileName(src, "")
        local pasta = arq and arq:match("^(.*)[\\/][^\\/]+$")
        if pasta and pasta ~= "" and not vistas[pasta] and not pasta:find("MultitrackAoVivo[\\/]pads") then
          vistas[pasta] = true
          lista[#lista + 1] = pasta
          if #lista >= 8 then break end
        end
      end
    end
  end
  return lista
end

local function achar_imagem(pasta)
  local melhor, nota_melhor = nil, -1
  local i = 0
  while true do
    local f = r.EnumerateFiles(pasta, i)
    if not f then break end
    local ext = (f:match("%.(%w+)$") or ""):lower()
    if EXT_IMG[ext] then
      local n = f:lower()
      local nota = 1
      if n:find("cover") or n:find("artwork") or n:find("folder") or n:find("album") then nota = 2 end
      if n:find("capa") then nota = 3 end
      if n == "capa.jpg" or n == "capa.jpeg" or n == "capa.png" then nota = 4 end
      if nota > nota_melhor then melhor, nota_melhor = pasta .. MT.SEP .. f, nota end
    end
    i = i + 1
  end
  return melhor
end

local function liberar_img(img)
  if not img then return end
  pcall(ImGui.Detach, ctx, img)
  if tem_imgui("DestroyImage") then pcall(ImGui.DestroyImage, img) end
end

local function liberar_capas()
  for _, c in pairs(capas) do
    if type(c) == "table" then liberar_img(c.img) end
  end
  capas = {}
end

local function capa(m)
  if not m then return nil end
  local agora = r.time_precise and r.time_precise() or 0
  local c = capas[m.nome]
  if c and c.img then return c.img end
  if c and (agora - (c.t or 0)) < 2.0 then return nil end
  if c then liberar_img(c.img) end
  c = { img = nil, t = agora }
  capas[m.nome] = c
  local arq
  if MT.pasta_da_musica then
    local pasta = MT.pasta_da_musica(m)
    if pasta then arq = achar_imagem(pasta) end
  end
  if not arq then
    local pastas = pastas_da_musica(m)
    for _, pasta in ipairs(pastas) do
      arq = achar_imagem(pasta)
      if arq then break end
    end
    if not arq then
      -- sobe ate 2 niveis (multitrack aninhada); evita pasta Downloads
      for _, pasta in ipairs(pastas) do
        local acima = pasta:match("^(.*)[\\/][^\\/]+$")
        for nivel = 1, 2 do
          if not acima then break end
          if nivel == 2 and not (acima:match("[^\\/]+$") or ""):lower():find("multitrack") then break end
          arq = achar_imagem(acima)
          if arq then break end
          acima = acima:match("^(.*)[\\/][^\\/]+$")
        end
        if arq then break end
      end
    end
  end
  if arq then
    local ok, img = pcall(ImGui.CreateImage, arq)
    if ok and img then
      if pcall(ImGui.Attach, ctx, img) then c.img = img end
    end
  end
  return c.img or nil
end

---------------------------------------------------------------------------
local ondas = {}  -- chave -> { picos = {...}, ok = bool, tentativa = tempo }

local function stems_da_banda()
  local lista = {}
  local banda = MT.achar_trilha(MT.CFG.NOME_BANDA)
  local nome_pad = MT.norm(MT.CFG.NOME_PAD)
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if banda and tr ~= banda and MT.descende_de(tr, banda)
       and r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") <= 0
       and MT.norm(MT.nome_trilha(tr)) ~= nome_pad then
      lista[#lista + 1] = tr
    end
  end
  return lista
end

local function calcular_onda(m, n)
  local dur = m.fim - m.inicio
  if dur <= 0 or n < 2 then return nil, true end
  local soma = {}
  for k = 1, n do soma[k] = 0 end
  local taxa = n / dur
  local completo = true
  local trilhas = stems_da_banda()
  if #trilhas == 0 then
    local g = MT.achar_trilha(MT.CFG.NOME_GUIA)
    if g then trilhas = { g } end
  end
  for _, tr in ipairs(trilhas) do
    for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
      local it = r.GetTrackMediaItem(tr, k)
      local ip = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local il = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      local a, b = math.max(ip, m.inicio), math.min(ip + il, m.fim)
      local tk = r.GetActiveTake(it)
      if b > a and tk and not r.TakeIsMIDI(tk) then
        local i1 = math.floor((a - m.inicio) * taxa) + 1
        local i2 = math.min(n, math.floor((b - m.inicio) * taxa))
        local ns = i2 - i1 + 1
        if ns > 0 then
          local buf = r.new_array(ns * 2)
          local ret = r.GetMediaItemTake_Peaks(tk, taxa, m.inicio + (i1 - 1) / taxa, 1, ns, 0, buf)
          local qtd = (ret or 0) & 0xFFFFF
          if qtd == 0 then completo = false end
          local vol = r.GetMediaItemInfo_Value(it, "D_VOL") * r.GetMediaItemTakeInfo_Value(tk, "D_VOL")
          for j = 1, math.min(qtd, ns) do
            local mx, mn = buf[j] or 0, buf[ns + j] or 0
            local v = math.max(math.abs(mx), math.abs(mn)) * vol
            soma[i1 + j - 1] = soma[i1 + j - 1] + v
          end
        end
      end
    end
  end
  -- normaliza (usa um percentil alto para não achatar tudo por um pico)
  local ord = {}
  for k = 1, n do ord[k] = soma[k] end
  table.sort(ord)
  local ref = ord[math.max(1, math.floor(n * 0.985))]
  if not ref or ref <= 0 then ref = ord[n] or 0 end
  if ref <= 0 then return soma, completo end
  for k = 1, n do
    local v = soma[k] / ref
    if v > 1 then v = 1 end
    soma[k] = v ^ 0.8
  end
  return soma, completo
end

local function onda(m, n)
  local chave = string.format("%s|%.3f|%.3f|%d", m.nome, m.inicio, m.fim, n)
  local o = ondas[chave]
  local agora = r.time_precise()
  if o and (o.ok or agora - o.tentativa < 1.5) then return o.picos end
  if o and o.vezes and o.vezes > 20 then return o.picos end
  local picos, ok = calcular_onda(m, n)
  ondas[chave] = { picos = picos, ok = ok, tentativa = agora, vezes = ((o and o.vezes) or 0) + 1 }
  return picos
end

-- compassos dentro da música (para a régua)
local reguas = {}
local function compassos(m)
  local chave = string.format("%s|%.3f|%.3f", m.nome, m.inicio, m.fim)
  if reguas[chave] then return reguas[chave] end
  local lista = {}
  local _, med_ini = r.TimeMap2_timeToBeats(0, m.inicio + 0.001)
  med_ini = math.floor(med_ini or 0)
  local k = med_ini
  local limite = 0
  while limite < 2000 do
    local t = r.TimeMap_GetMeasureInfo(0, k)
    if t > m.fim + 0.001 then break end
    if t >= m.inicio - 0.01 then lista[#lista + 1] = { t = t, n = k - med_ini + 1 } end
    k = k + 1
    limite = limite + 1
  end
  reguas[chave] = lista
  return lista
end

-- rótulo curto da seção (V1, C1, B, PC1...)
local CURTOS = {
  INTRO = "In", VERSE = "V", VERSO = "V", CHORUS = "C", REFRAO = "R", BRIDGE = "B", PONTE = "P",
  PRE = "Pr", PRECHORUS = "PC", INSTRUMENTAL = "Inst", INST = "Inst", INTERLUDE = "It",
  INTERLUDIO = "It", TAG = "Tag", OUTRO = "Out", ENDING = "End", FINAL = "Fim", VAMP = "Vp",
  COUNT = "CO", COUNTOFF = "CO", CONTAGEM = "Ct", BREAKDOWN = "Bd", TURNAROUND = "Ta",
  SOLO = "Solo", REFRAIN = "Rf", INICIO = "Ini", BREAK = "Bk", ESPONTANEO = "Esp",
}
local function curto(nome)
  local n = MT.norm(nome)
  local num = n:match("(%d+)%s*$") or ""
  local palavras = {}
  for w in n:gmatch("[%a]+") do palavras[#palavras + 1] = w end
  if #palavras == 0 then return nome end
  local p1 = palavras[1]
  if p1 == "PRE" and palavras[2] then return "PC" .. num end
  if p1 == "COUNT" then return "CO" end
  local c = CURTOS[p1]
  if c then return c .. num end
  if #nome <= 4 then return nome end
  return nome:sub(1, 3) .. num
end

---------------------------------------------------------------------------
-- estado do painel
---------------------------------------------------------------------------
local fila = nil              -- seção que vai tocar quando terminar o compasso
local setlist_ini = 1         -- primeira música visível na faixa do setlist (alvo)
local setlist_anim = { x = nil, from = 0, alvo = 0, t0 = 0, dur = 0.30 }
local setlist_fx = {}          -- por música: hover e realce do card ativo
local setlist_fx_t = nil
local setlist_marquee = {}  -- [i] = instante em que o título começou a precisar rolar
local setlist_fx_dt = 1 / 60
local ultima_musica = nil

local function ease_out_cubic(tt)
  if tt <= 0 then return 0 end
  if tt >= 1 then return 1 end
  local u = 1 - tt
  return 1 - u * u * u
end

local function setlist_ir_px(alvo_px, dur)
  local agora = r.time_precise()
  dur = dur or 0.30
  if dur < 0.25 then dur = 0.25 elseif dur > 0.35 then dur = 0.35 end
  if setlist_anim.x == nil then
    setlist_anim.x, setlist_anim.from, setlist_anim.alvo = alvo_px, alvo_px, alvo_px
    setlist_anim.t0, setlist_anim.dur = agora, dur
    return
  end
  if math.abs(alvo_px - (setlist_anim.alvo or 0)) < 0.5 then return end
  setlist_anim.from = setlist_anim.x
  setlist_anim.alvo = alvo_px
  setlist_anim.t0 = agora
  setlist_anim.dur = dur
end

local function setlist_tick(arrasto_ativo)
  local agora = r.time_precise()
  if setlist_anim.x == nil then return agora end
  if arrasto_ativo then
    setlist_anim.x = setlist_anim.alvo
    return agora
  end
  local dur = setlist_anim.dur or 0.30
  if math.abs(setlist_anim.x - setlist_anim.alvo) <= 0.4 then
    setlist_anim.x = setlist_anim.alvo
    return agora
  end
  local tt = (agora - setlist_anim.t0) / dur
  if tt >= 1 then
    setlist_anim.x = setlist_anim.alvo
  else
    if tt < 0 then tt = 0 end
    setlist_anim.x = setlist_anim.from + (setlist_anim.alvo - setlist_anim.from) * ease_out_cubic(tt)
  end
  return agora
end

local function setlist_max_ini(nmus, cabem)
  return math.max(1, (nmus or 0) - (cabem or 1) + 1)
end

local function setlist_pagina(dir, cabem, nmus, passo, por_pagina)
  por_pagina = por_pagina or cabem or 1
  local max_ini = setlist_max_ini(nmus, cabem)
  local novo = setlist_ini + dir * por_pagina
  if novo < 1 then novo = 1 elseif novo > max_ini then novo = max_ini end
  if novo == setlist_ini then
    -- no limite: “mola” visível, depois volta
    setlist_anim.x = (setlist_anim.x or ((setlist_ini - 1) * passo)) + dir * 20
    setlist_ir_px((setlist_ini - 1) * passo, 0.26)
    return
  end
  setlist_ini = novo
  setlist_ir_px((setlist_ini - 1) * passo, 0.30)
end

local function setlist_centralizar(n, cabem, nmus, passo, animar)
  if not n or not cabem then return end
  local vis = math.min(cabem, nmus or 1)
  local ini = n - math.floor((vis - 1) / 2)
  local max_ini = setlist_max_ini(nmus, cabem)
  if ini < 1 then ini = 1 elseif ini > max_ini then ini = max_ini end
  setlist_ini = ini
  local alvo = (ini - 1) * passo
  if animar then setlist_ir_px(alvo, 0.32) else
    setlist_anim.x, setlist_anim.from, setlist_anim.alvo = alvo, alvo, alvo
  end
end
local medidores = {}          -- trilha -> pico suavizado

local function pular_secao(e, sec)
  if not sec then return end
  MT.ir_para_secao(sec)
  if e.tocando and MT.salto_suave() and e.musica then
    fila = { musica = e.musica.nome, inicio = sec.inicio, nome = sec.nome, t = r.time_precise() }
  else
    fila = nil
  end
end

---------------------------------------------------------------------------
-- TOPO
---------------------------------------------------------------------------
local ultimo_prog, ultimo_prog_t = nil, 0
local function progresso_atual()
  if not MT.progresso_trabalho then return nil end
  local agora = reaper.time_precise and reaper.time_precise() or 0
  if ultimo_prog_t > 0 and agora - ultimo_prog_t < 0.2 then return ultimo_prog end
  ultimo_prog_t = agora
  local ok, info = pcall(MT.progresso_trabalho)
  ultimo_prog = (ok and info) or nil
  return ultimo_prog
end

-- Barrinha compacta no canto estratégico do topo: debaixo dos botões
-- L/R…Menu, na mesma faixa do visor LCD. Não cobre a forma de onda nem os cards.
local function desenhar_barra_progresso_topo(x0, W, yl, hl, larg_dir)
  local info = progresso_atual()
  if not info then return end
  local bw = math.min(300, math.max(220, larg_dir > 0 and math.min(larg_dir, 300) or 280))
  local bx = x0 + W - bw
  local by = yl + 8
  local bh = 10
  local x2, y2 = bx + bw, by + bh
  ImGui.DrawList_AddRectFilled(dl, bx, by, x2, y2, 0x0A0A12CC, 5)
  ImGui.DrawList_AddRect(dl, bx, by, x2, y2, C.borda, 5, 0, 1)
  local fill = info.pronto and 1 or math.max(0, math.min(1, tonumber(info.prog) or 0))
  local fw = (bw - 2) * fill
  if fw > 1 then
    local cor = (MT.cor_progresso and MT.cor_progresso(fill)) or C.verde
    ImGui.DrawList_AddRectFilled(dl, bx + 1, by + 1, bx + 1 + math.max(fw, 6), y2 - 1, cor, 4)
    ImGui.DrawList_AddRectFilled(dl, bx + 1, by + 1, bx + 1 + math.max(fw, 6), by + 4, 0xFFFFFF38, 4)
  end
  local ty = y2 + 5
  local cancelar = info.pode_cancelar and not info.pronto
  com_fonte(F.peq, function()
    local reserva = 0
    if cancelar then reserva = (texto_tam("Cancelar") or 50) + 8 end
    local maxw = bw - reserva
    local linha
    if info.pronto then
      linha = info.frase or "Pronto ✓"
    else
      local acao = (info.tipo == "instalacao" and "Instalando")
        or (info.tipo == "analise" and "Analisando")
        or (info.rapido and "Separando (rápida)" or "Separando")
      local suf = string.format(" — %d%%", info.pct or 0)
      local nome = info.nome or ""
      if nome == "" then
        linha = acao .. suf
      else
        local prefixo = acao .. ": "
        local wfix = texto_tam(prefixo .. suf) or 80
        linha = prefixo .. cortar(nome, math.max(20, maxw - wfix)) .. suf
      end
    end
    if (texto_tam(linha) or 0) > maxw then linha = cortar(linha, maxw) end
    ImGui.DrawList_AddText(dl, bx, ty, info.pronto and C.verde or C.texto, linha)
    local sub = {}
    if info.etapa and not info.pronto then sub[#sub + 1] = info.etapa end
    if info.fila then sub[#sub + 1] = info.fila end
    if info.eta and not info.pronto then sub[#sub + 1] = "resta " .. info.eta end
    if #sub > 0 and ty + 28 < yl + hl then
      ImGui.DrawList_AddText(dl, bx, ty + 15, C.texto2, table.concat(sub, "  ·  "))
    end
    if cancelar then
      local tw = texto_tam("Cancelar") or 50
      local cx1, cy1 = bx + bw - tw, ty
      local clicou, passando = area("##prog_cancelar", cx1, cy1, tw, 16)
      ImGui.DrawList_AddText(dl, cx1, cy1, passando and C.vermelho or C.texto3, "Cancelar")
      if clicou then depois(MT.cancelar_fila_importacao) end
    end
  end)
end

local function desenhar_topo(e, x0, y0, W)
  local m = e.musica
  local hb = 44
  local x = x0
  local H_BARRA = 128
  pcall(r.SetExtState, MT.SEC, "BARRA_UI", "v4", false)
  if MT.tick_capas then pcall(MT.tick_capas, e and e.musicas) end

  -- fundo da barra (leve gradiente + borda), fiel às cores atuais
  do
    local bx, by, bw, bh = x0 - 6, y0 - 4, W + 12, H_BARRA + 6
    ImGui.DrawList_AddRectFilled(dl, bx + 1, by + 3, bx + bw + 1, by + bh + 3, 0x00000055, 10)
    ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw, by + bh, 0x14181EFF, 10)
    if tem_imgui("DrawList_AddRectFilledMultiColor") then
      pcall(ImGui.DrawList_AddRectFilledMultiColor, dl, bx + 1, by + 1, bx + bw - 1, by + bh - 1,
        0x262C36FF, 0x262C36FF, 0x10141AFF, 0x10141AFF)
    end
    ImGui.DrawList_AddRectFilled(dl, bx + 8, by + 1, bx + bw - 8, by + 4, 0xFFFFFF14, 3)
    ImGui.DrawList_AddRect(dl, bx, by, bx + bw, by + bh, 0x2A303AFF, 10, 0, 1)
  end

  -- transporte (mesma altura dos outros botões)
  local bt = hb
  local bt_w = 34
  if botao_icone("##ant_mus", x, y0, bt_w, bt, "anterior", nil, false) then MT.musica_anterior() end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Música anterior (Page Up)") end
  x = x + bt_w + 5
  do
    local d = hb
    local py = y0
    local clicou, passando, segurando = area("##play", x, py, d, d)
    local cor = passando and ajustar(C.acento, 1.10) or C.acento
    if segurando then cor = ajustar(C.acento, 0.92) end
    local cor_play = e.tocando and C.verde or cor
    local cx, cy = x + d / 2, py + d / 2 + (segurando and 1 or 0)
    local raio = d / 2
    if not segurando then
      ImGui.DrawList_AddCircleFilled(dl, cx, cy + 2, raio + 1, 0x00000066, 40)
      ImGui.DrawList_AddCircleFilled(dl, cx, cy, raio + 3, alfa(cor_play, 50), 40)
    end
    ImGui.DrawList_AddCircleFilled(dl, cx, cy, raio, cor_play, 40)
    ImGui.DrawList_AddCircle(dl, cx, cy - 1, raio - 2, 0xFFFFFF30, 40, 1.4)
    ImGui.DrawList_AddCircle(dl, cx, cy, raio - 1, 0x00000028, 40, 1)
    local ic = (raio - 4)
    if e.tocando then ICONE.pause(cx, cy, ic * 0.85, 0x0C0E12FF)
    else ICONE.play(cx + 1, cy, ic, 0x0C0E12FF) end
    if clicou then MT.play_pause() end
    if passando then ImGui.SetTooltip(ctx, "Play / Pause (Espaço)") end
    x = x + d + 5
  end
  if botao_icone("##prox_mus", x, y0, bt_w, bt, "proxima", nil, false) then MT.proxima_musica() end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Próxima música (Page Down)") end
  x = x + bt_w + 5
  if botao_icone("##stop", x, y0, bt_w, bt, "stop", nil, false) then MT.parar() end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Stop (Enter)") end
  x = x + bt_w + 6
  x = sep_grupo(x, y0, hb)
  local wf = 46
  if botao_icone("##sec_ant", x, y0, wf, hb, "sec_ant", "SEÇÃO", false) then
    local alvo = e.secao and e.secoes[e.secao.n - 1] or (e.secoes and e.secoes[1])
    if e.secao and e.pos - e.secao.inicio > 2.0 then alvo = e.secao end   -- volta ao início da seção atual
    pular_secao(e, alvo)
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Seção anterior (seta esquerda)") end
  x = x + wf + 6
  if botao_icone("##sec_prox", x, y0, wf, hb, "sec_prox", "SEÇÃO", false) then
    local alvo = e.secao and e.secoes[e.secao.n + 1] or (e.secoes and e.secoes[1])
    if alvo then pular_secao(e, alvo) else MT.aviso("Última seção da música") end
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Próxima seção (seta direita)") end
  x = x + wf + 6
  if botao_icone("##auto", x, y0, wf, hb, "auto", "AUTO", MT.flag("AUTO")) then MT.alternar("AUTO", "AUTO") end
  x = x + wf + 6
  if botao_icone("##hold", x, y0, wf, hb, "hold", "HOLD", MT.flag("HOLD")) then MT.alternar("HOLD", "HOLD") end
  x = x + wf + 6
  if botao_icone("##loop", x, y0, wf, hb, "loop", "LOOP", MT.flag("LOOP")) then MT.alternar_loop() end
  x = x + wf + 6
  x = sep_grupo(x, y0, hb)
  local fim_esq = x

  -- LCD: tempo, BPM e tom (embaixo do transporte)
  local yl, hl = y0 + hb + 8, 62
  local xl, wl = x0, math.max(220, fim_esq - x0)
  ImGui.DrawList_AddRectFilled(dl, xl, yl, xl + wl, yl + hl, C.lcd_bg or 0x07090CFF, 8)
  ImGui.DrawList_AddRect(dl, xl, yl, xl + wl, yl + hl, C.borda, 8, 0, 1)
  ImGui.DrawList_AddRectFilled(dl, xl + 3, yl + 2, xl + wl - 3, yl + 5, 0xFFFFFF10, 6)
  local lcd_x, lcd_w = xl, wl
  if m and wl >= 280 then
    local lado = hl - 8
    local cx1, cy1 = xl + 4, yl + 4
    local img_lcd = capa(m)
    if img_lcd and ((not tem_imgui("ValidatePtr")) or ImGui.ValidatePtr(img_lcd, "ImGui_Image*")) then
      ImGui.DrawList_AddImageRounded(dl, img_lcd, cx1, cy1, cx1 + lado, cy1 + lado, 0, 0, 1, 1, 0xFFFFFFFF, 6)
    else
      ImGui.DrawList_AddRectFilled(dl, cx1, cy1, cx1 + lado, cy1 + lado, 0x1A2230FF, 6)
      if ICONE.nota then ICONE.nota(cx1 + lado / 2, cy1 + lado / 2, lado * 0.28, 0xFFFFFF66) end
    end
    ImGui.DrawList_AddRect(dl, cx1, cy1, cx1 + lado, cy1 + lado, 0xFFFFFF22, 6, 0, 1)
    lcd_x = cx1 + lado + 6
    lcd_w = xl + wl - lcd_x
  end
  local tempo = m and (mmss(e.pos - m.inicio) .. "  /  " .. mmss(m.fim - m.inicio)) or "0:00  /  0:00"
  local taxa_lcd = r.Master_GetPlayRate(0) or 1
  local bpm_v = (e.bpm or 0) * taxa_lcd
  local bpm_txt = "--"
  if e.bpm and e.bpm > 0 then
    bpm_txt = (math.abs(bpm_v - math.floor(bpm_v + 0.5)) < 0.05)
      and string.format("%d", math.floor(bpm_v + 0.5)) or string.format("%.1f", bpm_v)
  end
  local tom_txt = (m and (e.tom or "--")) or "--"
  local colw = lcd_w / 3
  com_fonte(F.lcd or F.grande or F.media, function()
    texto_centro(lcd_x, yl + 2, lcd_x + colw, yl + 34, tempo, C.lcd or C.ciano)
    texto_centro(lcd_x + colw, yl + 2, lcd_x + colw * 2, yl + 34, bpm_txt, C.lcd or C.ciano)
    texto_centro(lcd_x + colw * 2, yl + 2, xl + wl, yl + 34, tom_txt, C.lcd or C.ciano)
  end)
  com_fonte(F.mini, function()
    texto_centro(lcd_x, yl + 32, lcd_x + colw, yl + 46, "TEMPO", C.texto3)
    texto_centro(lcd_x + colw, yl + 32, lcd_x + colw * 2, yl + 46, "BPM", C.texto3)
    texto_centro(lcd_x + colw * 2, yl + 32, xl + wl, yl + 46, "TOM", C.texto3)
  end)
  local status = e.tocando and "TOCANDO" or (e.pausado and "PAUSADO" or "PARADO")
  local cor_st = e.tocando and C.verde or (e.pausado and C.amarelo or C.texto2)
  local nome = m and string.format("%d. %s", m.n, m.nome) or "Clique em + IMPORTAR para começar"
  local sec = e.secao and ("  ·  " .. e.secao.nome) or ""
  com_fonte(F.peq, function()
    ImGui.DrawList_AddCircleFilled(dl, lcd_x + 10, yl + hl - 10, 4, cor_st, 12)
    ImGui.DrawList_AddText(dl, lcd_x + 20, yl + hl - 18, C.texto, cortar(status .. "  " .. nome .. sec, lcd_w - 28))
  end)

  -- bloco da direita: L/R, Ao Vivo, Studio, Tom, IMPORTAR, Biblioteca, Limpar, Menu
  -- larguras medidas no rótulo para não reservar espaço a mais (libera a faixa do setlist)
  local gap = 4
  local wi = 76
  local w_lr, w_aovivo, w_studio, w_tom, w_bib, w_limpar, w_menu, w_salvar = 40, 54, 50, 42, 108, 50, 42, 48
  com_fonte(F.peq or F.mini, function()
    local function wr(s, minw)
      return math.max(minw, math.ceil((texto_tam(s) or minw) + 10))
    end
    w_lr = wr("L/R", 40)
    w_aovivo = wr("Ao Vivo", 54)
    w_studio = wr("Studio", 50)
    w_tom = wr("Tom", 42)
    w_bib = math.max(108, math.ceil((texto_tam("Biblioteca") or 80) + 20))
    w_limpar = wr("Limpar", 50)
    w_menu = wr("Menu", 42)
    w_salvar = wr("Salvar", 48)
  end)
  local larg_dir = w_lr + w_aovivo + w_studio + w_tom + wi + w_bib + w_salvar + w_limpar + w_menu + gap * 8 + 16
  local xd = x0 + W - larg_dir
  local com_click = MT.get("LR_COM_CLICK", "0") == "1"
  xd = sep_grupo(xd, y0, hb)
  if botao_icone("##lr", xd, y0, w_lr, hb, "lr", "L/R", e.modo == "LR" and not com_click) then
    depois(function() MT.set("LR_COM_CLICK", "0"); MT.modo_lr() end)
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "L/R: banda em estéreo nas saídas 1/2, SEM click (para a mesa).\nPara ouvir o click no ensaio, use Studio.") end
  xd = xd + w_lr + gap
  if botao_icone("##aovivo", xd, y0, w_aovivo, hb, "aovivo", "Ao Vivo", e.modo == "AO_VIVO") then depois(MT.modo_ao_vivo) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Ao Vivo: " .. MT.descrever_roteamento(saidas_ui.rot or MT.roteamento_efetivo(), "AO_VIVO") .. "\n(botão Saídas para trocar 2 / 4 canais)") end
  xd = xd + w_aovivo + gap
  if botao_icone("##studio", xd, y0, w_studio, hb, "studio", "Studio", e.modo == "LR" and com_click) then
    depois(function() MT.set("LR_COM_CLICK", "1"); MT.modo_lr() end)
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Studio: tudo em estéreo nas saídas 1/2, com click e guia (ensaio)") end
  xd = xd + w_studio + gap
  -- tom
  do
    local clicou, passando, segurando = area("##tom", xd, y0, w_tom, hb)
    local mudou = (e.transp or 0) ~= 0
    local fundo = mudou and C.lavanda or (passando and C.painel3 or C.painel2)
    local oy = desenhar_relevo(xd, y0, w_tom, hb, fundo, 7, passando, segurando, mudou)
    local cor = mudou and 0x14121FFF or C.texto
    com_fonte(F.media, function() texto_centro(xd, y0 + oy + 1, xd + w_tom, y0 + oy + hb * 0.62, (m and (e.tom or "--")) or "--", cor) end)
    com_fonte(F.dica or F.mini, function()
      local rt, _c = rotulo_cabivel(mudou and string.format("Tom %+d", e.transp) or "Tom", w_tom)
      if rt then texto_centro(xd, y0 + oy + hb * 0.62, xd + w_tom, y0 + oy + hb - 2, rt, mudou and cor or C.texto2) end
    end)
    if clicou then ImGui.OpenPopup(ctx, "popup_tom") end
    if passando then ImGui.SetTooltip(ctx, "Tom (só a banda; click e guia não mudam)") end
  end
  xd = xd + w_tom + gap
  xd = sep_grupo(xd, y0, hb)
  if botao_destaque("##importar", xd, y0, wi, hb, "mais", "IMPORTAR", C.verde) then ImGui.OpenPopup(ctx, "popup_importar") end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Importar: MÚSICA(S) comum(ns) ou MULTITRACK (VS).\n" ..
      "Música: um ou vários arquivos (Ctrl ou Shift). Multitrack: a pasta ou os stems dela." ..
      (TEM_SOLTAR and "\nDica: também dá para ARRASTAR arquivos ou pastas para o painel." or ""))
  end
  xd = xd + wi + gap
  if botao_icone("##biblio", xd, y0, w_bib, hb, "biblio", "Biblioteca", false) then
    biblio.lista = MT.listar_biblioteca(); biblio.busca = biblio.busca or ""
    ImGui.OpenPopup(ctx, "popup_biblio")
  end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Biblioteca de multitracks: 1 clique põe a música no fim do setlist") end
  xd = xd + w_bib + gap
  if botao_icone("##salvar", xd, y0, w_salvar, hb, "disquete", "Salvar", false) then depois(salvar_projeto_painel) end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Salvar o projeto (" .. MT.atalho("Ctrl+S") .. ")\n" ..
      "Guarda tudo: fórmula de compasso identificada, click/guia gerados, setlist e trilhas.\n" ..
      "Projeto ainda sem nome: abre o \"Salvar como\".")
  end
  xd = xd + w_salvar + gap
  if botao_icone("##limpar", xd, y0, w_limpar, hb, "lixo", "Limpar", false) then
    limpar_ui.musicas = MT.listar_musicas_para_apagar()
    limpar_ui.lixo = MT.listar_lixo()
    limpar_ui.sel = {}
    limpar_ui.incluir_lixo = false
    limpar_ui.confirma = false
    limpar_ui.busca = ""
    abrir_limpar = true
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "Escolha quais músicas (multitracks) apagar, ou limpe só os arquivos gerados\n" ..
      "que não estão em uso (clicks antigos, __stems órfãos e temporários).\n" ..
      "Pede confirmação. Os arquivos vão para a Lixeira.")
  end
  xd = xd + w_limpar + gap
  if botao_icone("##menu", xd, y0, w_menu, hb, "menu", "Menu", false) then ImGui.OpenPopup(ctx, "popup_menu") end

  -- setlist: ocupa TODO o vão entre o grupo esquerdo e os modos, cards completos
  local sx1, sx2 = fim_esq + 6, x0 + W - larg_dir - 6
  local larg = sx2 - sx1
  local seta = 18
  local gap_t = 8
  local musicas = e.musicas
  local travado = MT.setlist_travado and MT.setlist_travado() or false
  local nmus = #musicas
  local trava_w = (nmus > 0) and 28 or 0
  local reserva = trava_w + ((trava_w > 0) and 4 or 0) + 2 * (seta + 4)
  local tile_h = math.max(74, math.min(110, H_BARRA - 14))
  local vista = math.max(52, larg - reserva)
  local min_tile = 58
  local cabem = math.max(1, math.floor((vista + gap_t) / (min_tile + gap_t)))
  local mostrar = math.max(1, math.min(cabem, math.max(nmus, 1)))
  -- estica os cards para preencher a faixa, sem folga vazia no meio
  local tile = math.floor((vista - (mostrar - 1) * gap_t) / mostrar)
  if tile < 52 then tile = 52 end
  local passo = tile + gap_t
  local total_w = mostrar * tile + math.max(0, mostrar - 1) * gap_t
  -- setas nas bordas da faixa; viewport começa logo após cadeado + seta esquerda
  local tx = sx1 + ((trava_w > 0) and (trava_w + 4) or 0) + seta + 4
  local ty = y0
  local mudou_musica = (m and m.n ~= ultima_musica)
  if mudou_musica then
    ultima_musica = m.n
    setlist_centralizar(m.n, cabem, nmus, passo, setlist_anim.x ~= nil)
  end
  if setlist_ini > setlist_max_ini(nmus, cabem) then setlist_ini = setlist_max_ini(nmus, cabem) end
  if setlist_ini < 1 then setlist_ini = 1 end
  local arrasto_ativo = false
  pcall(function()
    if ImGui.IsMouseDragging then arrasto_ativo = ImGui.IsMouseDragging(ctx, 0) end
  end)
  do
    local cmd = r.GetExtState(MT.SEC, "SETLIST_CMD") or ""
    if cmd ~= "" then
      pcall(r.SetExtState, MT.SEC, "SETLIST_CMD", "", false)
      if cmd == "ant" then setlist_pagina(-1, cabem, nmus, passo, cabem)
      elseif cmd == "prox" then setlist_pagina(1, cabem, nmus, passo, cabem) end
    end
  end
  if setlist_anim.x == nil then
    local alvo0 = (setlist_ini - 1) * passo
    setlist_anim.x, setlist_anim.from, setlist_anim.alvo = alvo0, alvo0, alvo0
  else
    local alvo_px = (setlist_ini - 1) * passo
    -- se a largura do card mudou (redimensionou a janela), encaixa no novo passo
    if math.abs((setlist_anim.alvo or 0) - alvo_px) > 0.5 or
       (passo > 0 and math.abs((setlist_anim.alvo or 0) / passo - (setlist_ini - 1)) > 0.05) then
      if not arrasto_ativo then
        if setlist_anim.x and math.abs((setlist_anim.x or 0) - alvo_px) > cabem * passo then
          setlist_anim.x, setlist_anim.from, setlist_anim.alvo = alvo_px, alvo_px, alvo_px
        else
          setlist_ir_px(alvo_px, 0.30)
        end
      end
    end
  end
  local agora = setlist_tick(arrasto_ativo)
  pcall(r.SetExtState, MT.SEC, "SETLIST_INFO",
    string.format("ini=%d cabem=%d n=%d x=%.1f alvo=%.1f passo=%.0f tile=%d tile_h=%.0f vista=%.0f",
      setlist_ini or 0, cabem or 0, nmus or 0, setlist_anim.x or 0, setlist_anim.alvo or 0,
      passo or 0, tile or 0, tile_h or 0, vista or 0), false)
  if nmus > 0 and ImGui.GetMouseWheel then
    local mx, my = ImGui.GetMousePos(ctx)
    if mx and my and mx >= sx1 and mx <= sx2 and my >= ty - 6 and my <= ty + tile_h + 8 then
      local roda = ImGui.GetMouseWheel(ctx) or 0
      if roda > 0.15 then setlist_pagina(-1, cabem, nmus, passo, 1)
      elseif roda < -0.15 then setlist_pagina(1, cabem, nmus, passo, 1) end
    end
  end
  do
    local dt = 1 / 60
    if setlist_fx_t then dt = agora - setlist_fx_t end
    if dt < 0 then dt = 0 elseif dt > 0.08 then dt = 0.08 end
    setlist_fx_dt = dt
    setlist_fx_t = agora
    local vistos = {}
    for i = 1, nmus do
      local mu = musicas[i]
      if mu then vistos[mu.n] = true end
    end
    for n, fx in pairs(setlist_fx) do
      if type(n) == "number" and not vistos[n] then setlist_fx[n] = nil end
    end
  end
  if larg >= reserva + 52 then
    local cy = ty + tile_h / 2
    if nmus == 0 then
      local clicou, passando = area("##vazio_importar", sx1, ty, sx2 - sx1, tile_h)
      ImGui.DrawList_AddRectFilled(dl, sx1, ty, sx2, ty + tile_h, passando and C.acento_fundo or C.painel, 8)
      ImGui.DrawList_AddRect(dl, sx1, ty, sx2, ty + tile_h, passando and C.verde or C.borda, 8, 0, passando and 2 or 1)
      com_fonte(F.peq, function()
        texto_centro(sx1, ty, sx2, ty + tile_h * 0.55, "Clique em + IMPORTAR para começar", passando and C.texto or C.texto2)
        texto_centro(sx1, ty + tile_h * 0.45, sx2, ty + tile_h, TEM_SOLTAR and "(ou arraste arquivos ou a pasta da música para cá)" or "", C.texto3)
      end)
      if clicou then abrir_importar = true end
    else
      if botao_icone("##set_trava", sx1, cy - 14, 28, 28, travado and "trava" or "trava_aberta", nil, travado, travado and C.amarelo or nil) then
        if MT.alternar_trava_setlist then pcall(MT.alternar_trava_setlist) end
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, travado
          and "Setlist TRAVADO — clique para destravar\nTocar no card ainda troca a música. Arrastar a ordem fica bloqueado."
          or "Travar o setlist\nTravado, não dá para arrastar os cards. O clique no card continua trocando a música.")
      end
      if botao_icone("##set_esq", tx - seta - 4, cy - 12, seta, 24, "esq", nil, false) then
        setlist_pagina(-1, cabem, nmus, passo, cabem)
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Página anterior do setlist") end
      if botao_icone("##set_dir", tx + total_w + 4, cy - 12, seta, 24, "dir", nil, false) then
        setlist_pagina(1, cabem, nmus, passo, cabem)
      end
      if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Próxima página do setlist") end
      if travado then
        ImGui.DrawList_AddRect(dl, sx1 - 2, ty - 4, sx2 + 2, ty + tile_h + 4, C.amarelo, 8, 0, 1.8)
      end
    end
    local clip_l, clip_r = tx, tx + total_w
    local i0 = math.floor((setlist_anim.x or 0) / passo) + 1
    if i0 < 1 then i0 = 1 end
    local i1 = math.ceil(((setlist_anim.x or 0) + total_w) / passo) + 1
    if i1 > nmus then i1 = nmus end
    local tem_clip_faixa = clip_ini(clip_l - 2, ty - 8, clip_r + 2, ty + tile_h + 10)
    local kuse = 1 - math.exp(-(setlist_fx_dt or 0.016) / 0.09)
    for i = i0, i1 do
      local mu = musicas[i]
      if not mu then break end
      local x1 = tx + (i - 1) * passo - (setlist_anim.x or 0)
      if x1 + tile > clip_l - 8 and x1 < clip_r + 8 then
      local atual = (m and mu.n == m.n)
      local mx, my = ImGui.GetMousePos(ctx)
      local hover_alvo = 0
      if mx and my and mx >= x1 and mx <= x1 + tile and my >= ty and my <= ty + tile_h then hover_alvo = 1 end
      local fx = setlist_fx[mu.n]
      if not fx then
        fx = { hover = hover_alvo, ativo = atual and 1 or 0 }
        setlist_fx[mu.n] = fx
      end
      fx.hover = fx.hover + (hover_alvo - fx.hover) * kuse
      fx.ativo = fx.ativo + ((atual and 1 or 0) - fx.ativo) * kuse
      local escala = 1 + 0.05 * fx.ativo + 0.03 * fx.hover
      local lift = 3 * fx.hover
      local cx = x1 + tile / 2
      local cy_c = ty + tile_h / 2 - lift
      local hw, hh = (tile * escala) / 2, (tile_h * escala) / 2
      local cx1, cy1, cx2, cy2 = cx - hw, cy_c - hh, cx + hw, cy_c + hh
      local vis_x1 = math.max(math.min(cx1, x1), clip_l)
      local vis_x2 = math.min(math.max(cx2, x1 + tile), clip_r)
      local clicou, passando = false, false
      if vis_x2 - vis_x1 > 2 then
        clicou, passando = area("##mus" .. i, vis_x1, ty - 4, vis_x2 - vis_x1, tile_h + 8)
      end
      if passando then hover_alvo = 1 end
      local base = de_nativa(mu.cor, C.acento)
      local img = capa(mu)
      if fx.hover > 0.05 or fx.ativo > 0.05 then
        local so = 2 + 3 * fx.hover
        ImGui.DrawList_AddRectFilled(dl, cx1 + 1, cy1 + so, cx2 + 1, cy2 + so, alfa(0x000000FF, math.floor(40 + 50 * fx.hover)), 7)
      end
      local pad = 6
      local badge_h = 16
      local tw_area = (cx2 - cx1) - pad * 2
      if tw_area < 20 then tw_area = 20 end
      -- reserva o topo para os badges; o título fica numa faixa no rodapé
      local linha_h = 13
      com_fonte(F.peq or F.mini, function()
        local _, lh = texto_tam("Ag")
        if lh and lh > 1 then linha_h = lh end
      end)
      local faixa_h = math.min((cy2 - cy1) * 0.48, linha_h * 3 + 8)
      if faixa_h < linha_h * 2 + 6 then faixa_h = linha_h * 2 + 6 end
      local texto_base = cy2 - 4
      local texto_topo = math.max(cy1 + badge_h + 3, cy2 - faixa_h)
      if img and ((not tem_imgui("ValidatePtr")) or ImGui.ValidatePtr(img, "ImGui_Image*")) then
        local iw, ih = ImGui.Image_GetSize(img)
        local u1, v1, u2, v2 = 0, 0, 1, 1
        if iw and ih and iw > 0 and ih > 0 then
          if iw > ih then local d = (1 - ih / iw) / 2; u1, u2 = d, 1 - d
          elseif ih > iw then local d = (1 - iw / ih) / 2; v1, v2 = d, 1 - d end
        end
        ImGui.DrawList_AddImageRounded(dl, img, cx1, cy1, cx2, cy2, u1, v1, u2, v2, 0xFFFFFFFF, 7)
      else
        ImGui.DrawList_AddRectFilledMultiColor(dl, cx1, cy1, cx2, cy2,
          ajustar(base, 0.75), ajustar(base, 0.45), ajustar(base, 0.18), ajustar(base, 0.35))
      end
      -- faixa de título no rodapé (não invade a área dos badges)
      ImGui.DrawList_AddRectFilled(dl, cx1, texto_topo - 2, cx2, cy2, 0x000000B8, 7, DRAW_ROUND_BOTTOM)
      -- número e tom (faixa reservada no topo)
      com_fonte(F.mini, function()
        ImGui.DrawList_AddRectFilled(dl, cx1 + 3, cy1 + 3, cx1 + 19, cy1 + 3 + badge_h, 0x000000A0, 4)
        texto_centro(cx1 + 3, cy1 + 3, cx1 + 19, cy1 + 3 + badge_h, tostring(mu.n), 0xFFFFFFFF)
        local tm = MT.tom_soando(mu)
        if tm then
          local twb = texto_tam(tm)
          ImGui.DrawList_AddRectFilled(dl, cx2 - twb - 9, cy1 + 3, cx2 - 3, cy1 + 3 + badge_h, 0x000000A0, 4)
          ImGui.DrawList_AddText(dl, cx2 - twb - 6, cy1 + 4, 0xFFFFFFFF, tm)
        end
      end)
      -- título: 2–3 linhas com quebra; se ainda não cabe, marquee no ativo/hover
      com_fonte(F.peq or F.mini, function()
        local linhas, overflow = quebrar_titulo(mu.nome, tw_area, 3)
        local _, lh = texto_tam("Ag")
        if not lh or lh < 1 then lh = 13 end
        -- wrap 2–3 linhas no card; o letreiro só entra no hover (o ativo fica estável e legível)
        local rolar = (overflow or false) and passando
        local temc = clip_ini(cx1 + pad, texto_topo, cx2 - pad, texto_base)
        if rolar then
          local full = string.format("%d. %s", mu.n, nome_sem_numero(mu.nome))
          local fw = texto_tam(full) or tw_area
          local yy = texto_topo + math.max(0, (texto_base - texto_topo - lh) / 2)
          if fw <= tw_area then
            texto_centro(cx1 + pad, yy, cx2 - pad, yy + lh, full, 0xFFFFFFFF)
            setlist_marquee[i] = nil
          else
            if not setlist_marquee[i] then setlist_marquee[i] = agora end
            local espera, vel, pausa = 0.90, 26, 1.10
            local caminho = fw - tw_area + 12
            local dt = agora - setlist_marquee[i] - espera
            local off = 0
            if dt > 0 and caminho > 1 then
              local vai = caminho / vel
              local fase = dt % (vai + pausa)
              if fase < vai then off = fase * vel end
            end
            ImGui.DrawList_AddText(dl, cx1 + pad - off, yy, 0xFFFFFFFF, full)
          end
        else
          setlist_marquee[i] = nil
          local bloco = #linhas * lh
          local yy = texto_topo + math.max(0, (texto_base - texto_topo - bloco) / 2)
          for _, ln in ipairs(linhas) do
            texto_centro(cx1 + pad, yy, cx2 - pad, yy + lh, ln, 0xFFFFFFFF)
            yy = yy + lh
          end
        end
        if temc then clip_fim() end
      end)
      if fx.ativo > 0.02 then
        local g = 2 + 4 * fx.ativo
        ImGui.DrawList_AddRect(dl, cx1 - g, cy1 - g, cx2 + g, cy2 + g,
          alfa(C.lavanda, math.floor(50 + 180 * fx.ativo)), 9, 0, 1.4 + 1.2 * fx.ativo)
        ImGui.DrawList_AddRect(dl, cx1 - 1, cy1 - 1, cx2 + 1, cy2 + 1,
          alfa(0xFFFFFFFF, math.floor(20 + 50 * fx.ativo)), 7, 0, 1)
      elseif fx.hover > 0.15 then
        ImGui.DrawList_AddRect(dl, cx1 - 1, cy1 - 1, cx2 + 1, cy2 + 1,
          alfa(0xFFFFFFFF, math.floor(40 + 80 * fx.hover)), 7, 0, 1)
      else
        ImGui.DrawList_AddRect(dl, cx1, cy1, cx2, cy2, 0x00000050, 7, 0, 1)
      end
      if passando or atual then
        local tm = MT.tom_soando(mu)
        local dica = string.format("%d. %s%s\nClique para ir para esta música", mu.n, mu.nome, tm and ("  [" .. tm .. "]") or "")
        if travado then dica = dica .. "\nSetlist travado (não arrasta)"
        else dica = dica .. "\nArraste para trocar a ordem do setlist (não mexe na timeline)" end
        if passando then ImGui.SetTooltip(ctx, dica) end
      end
      pcall(function()
        if travado then return end
        if ImGui.BeginDragDropSource and ImGui.BeginDragDropSource(ctx) then
          ImGui.SetDragDropPayload(ctx, "MT_SETLIST", tostring(i))
          if ImGui.Text then ImGui.Text(ctx, string.format("%d. %s", mu.n, mu.nome or "")) end
          ImGui.EndDragDropSource(ctx)
        end
        if ImGui.BeginDragDropTarget and ImGui.BeginDragDropTarget(ctx) then
          local okp, a, b = pcall(ImGui.AcceptDragDropPayload, ctx, "MT_SETLIST")
          local payload = nil
          if okp then
            if type(a) == "string" or type(a) == "number" then payload = a
            elseif type(b) == "string" or type(b) == "number" then payload = b end
          end
          local de = tonumber(payload)
          if de and de ~= i and MT.reordenar_setlist then pcall(MT.reordenar_setlist, de, i) end
          ImGui.EndDragDropTarget(ctx)
        end
      end)
      local arrastando = false
      pcall(function()
        if ImGui.IsMouseDragging then arrastando = ImGui.IsMouseDragging(ctx, 0) end
      end)
      if clicou and not arrastando then MT.ir_para_musica(i) end
      end -- visível na faixa
    end
    -- fade só no meio do slide, quando um card vizinho aparece cortado na borda
    do
      local mid = math.abs((setlist_anim.x or 0) - (setlist_anim.alvo or 0)) > 1
      local resto = 0
      if (passo or 0) > 0 then resto = math.abs((setlist_anim.x or 0) % passo) end
      if mid or (resto > 1.5 and resto < (passo or 0) - 1.5) then
        fade_bordas(clip_l, ty - 2, clip_r, ty + tile_h + 2, 0x10141AFF, 14)
      end
    end
    if tem_clip_faixa then clip_fim() end
  end

  desenhar_barra_progresso_topo(x0, W, yl, hl, larg_dir)

  -- popups do tom e do menu
  if ImGui.BeginPopup(ctx, "popup_tom") then
    ImGui.TextDisabled(ctx, "Tom (só a banda)")
    if m then
      ImGui.Text(ctx, string.format("Original: %s   Agora: %s (%+d)", m.tom or "--", e.tom or "--", e.transp or 0))
    end
    if ImGui.Button(ctx, "  -  ", 60, 34) then depois(MT.tom_menos) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "  +  ", 60, 34) then depois(MT.tom_mais) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Original", 90, 34) then depois(MT.tom_zerar) end
    if ImGui.Button(ctx, "Definir tom original...", 226, 30) then depois(MT.definir_tom); ImGui.CloseCurrentPopup(ctx) end
    ImGui.EndPopup(ctx)
  end
  if abrir_biblio then abrir_biblio = false; ImGui.OpenPopup(ctx, "popup_biblio") end
  if abrir_sobre then abrir_sobre = false; ImGui.OpenPopup(ctx, "Sobre o Mik Seifador") end
  if abrir_limpar then abrir_limpar = false; ImGui.OpenPopup(ctx, "Limpar arquivos") end
  if abrir_importar then abrir_importar = false; ImGui.OpenPopup(ctx, "popup_importar") end
  if ImGui.BeginPopupModal(ctx, "Sobre o Mik Seifador", true, ImGui.WindowFlags_AlwaysAutoResize) then
    com_fonte(F.media, function() ImGui.TextColored(ctx, C.lavanda, (MT.NOME or "Mik Seifador") .. "  v" .. (MT.VERSAO or "1.0")) end)
    ImGui.Text(ctx, "Criado por " .. (MT.AUTOR or "Miqueias Felix") .. "  -  2026")
    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Player de multitracks ao vivo para o REAPER:")
    ImGui.Text(ctx, "setlist, seções, AUTO / HOLD / LOOP, tom só da banda, PAD no tom,")
    ImGui.Text(ctx, "click e guia no fone e banda na mesa (placas de 2 ou 4+ saídas),")
    ImGui.Text(ctx, "biblioteca de multitracks e controle por teclado ou pedal MIDI.")
    if MT.NOVIDADES and #MT.NOVIDADES > 0 then
      ImGui.Separator(ctx)
      ImGui.TextColored(ctx, C.verde, "Novidades da versão " .. MT.VERSAO .. ":")
      for _, linha in ipairs(MT.NOVIDADES) do
        if linha:sub(1, 1) == " " then ImGui.Text(ctx, "   " .. linha) else ImGui.Text(ctx, "  - " .. linha) end
      end
    end
    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "Fechar", 120, 0) then ImGui.CloseCurrentPopup(ctx) end
    ImGui.EndPopup(ctx)
  end
  if pads_ui.abrir then
    pads_ui.abrir = false
    MT.garantir_pasta_pads()
    MT.recarregar_pads()
    pads_ui.lista = MT.listar_pacotes_pads()
    ImGui.OpenPopup(ctx, "popup_pads")
  end
  if ImGui.BeginPopup(ctx, "popup_pads") then
    local mm = e.musica
    ImGui.TextDisabled(ctx, "Pacote de pads  (" .. MT.pasta_pads_raiz() .. ")")
    local atual = MT.pacote_pads()
    local classico = MT.PACOTE_PAD_CLASSICO or "Pad clássico"
    local continuo = MT.PACOTE_PAD_CONTINUO or "Pad contínuo"
    local function opcao(nome, rotulo)
      local pasta = (nome == "" and MT.pasta_pads_raiz() or (MT.pasta_pads_raiz() .. MT.SEP .. nome))
      local qtd = (nome == classico) and 12 or #MT.pads_da_pasta(pasta)
      local rot = (MT.rotulo_pacote_pads and MT.rotulo_pacote_pads(nome)) or rotulo
      if ImGui.Selectable(ctx, string.format("%s   (%d tons)##pac_%s", rot, qtd, nome), atual == nome) then
        local n = nome
        depois(function() MT.definir_pacote_pads(n) end)
      end
    end
    local vistos = {}
    local function tem(nome)
      if nome == classico then return true end
      for _, d in ipairs(pads_ui.lista or {}) do if d == nome then return true end end
      return false
    end
    if tem(continuo) then opcao(continuo, "Pad contínuo (padrão)"); vistos[continuo] = true end
    opcao(classico, "Pad clássico"); vistos[classico] = true
    for _, d in ipairs(pads_ui.lista or {}) do
      if not vistos[d] and d ~= "Shimmer" then opcao(d, d) end
    end
    opcao("", "(arquivos soltos na pasta _PADS)")
    if not tem(continuo) then
      ImGui.TextDisabled(ctx, "Pad contínuo ainda não está na Biblioteca. Use Importar pasta de pads…")
    end
    ImGui.Separator(ctx)
    if mm then ImGui.Text(ctx, "Esta música: " .. MT.descrever_pad(mm)) end
    if ImGui.Button(ctx, "Importar pasta de pads...") then
      depois(function() MT.importar_pasta_pads() end)
      ImGui.CloseCurrentPopup(ctx)
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Copia uma pasta com 12 pads (C-PAD.mp3, Pad G.wav…) para a Biblioteca,\ncomo pacote Pad contínuo (padrão). Os arquivos originais não são movidos.")
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Abrir pasta _PADS") then MT.abrir_no_sistema(MT.garantir_pasta_pads()) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Recarregar pads") then
      depois(function() MT.recarregar_pads(); MT.definir_pacote_pads(MT.pacote_pads()) end)
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.EndPopup(ctx)
  end
  if saidas_ui.abrir then
    saidas_ui.abrir = false
    saidas_ui.info = MT.info_placa()
    saidas_ui.perfil = MT.perfil_saidas()
    saidas_ui.click = tonumber(MT.get("SAIDA_CLICK", "1")) or 1
    saidas_ui.guia = tonumber(MT.get("SAIDA_GUIA", "2")) or 2
    saidas_ui.banda = tonumber(MT.get("SAIDA_BANDA", "3")) or 3
    ImGui.OpenPopup(ctx, "Saídas de áudio")
  end
  if ImGui.BeginPopupModal(ctx, "Saídas de áudio", true, ImGui.WindowFlags_AlwaysAutoResize) then
    local info = saidas_ui.info or MT.info_placa()
    com_fonte(F.media, function() ImGui.TextColored(ctx, C.lavanda, info.nome ~= "" and info.nome or "Placa de áudio") end)
    if info.modo and info.modo ~= "" then ImGui.TextDisabled(ctx, "Driver: " .. info.modo) end
    if info.n > 0 then ImGui.Text(ctx, string.format("%d saída(s) disponíveis", info.n))
    else ImGui.TextColored(ctx, 0xFF8080FF, "Áudio fechado: abra o dispositivo nas Preferências do REAPER") end
    if info.aviso then ImGui.PushTextWrapPos(ctx, 420); ImGui.TextColored(ctx, 0xFFC060FF, info.aviso); ImGui.PopTextWrapPos(ctx) end
    if ImGui.Button(ctx, "Detectar de novo") then saidas_ui.info = MT.info_placa(); info = saidas_ui.info end
    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Perfil (usado no modo AO VIVO):")
    for _, pf in ipairs(MT.PERFIS_SAIDA) do
      if ImGui.RadioButton(ctx, pf.nome, saidas_ui.perfil == pf.id) then saidas_ui.perfil = pf.id end
    end
    local function combo(rotulo, atual, par)
      local nomes = info.canais
      local function nome_de(c)
        if par then return string.format("%d/%d  %s / %s", c, c + 1, nomes[c] or "?", nomes[c + 1] or "?") end
        return string.format("%d  %s", c, nomes[c] or "?")
      end
      ImGui.SetNextItemWidth(ctx, 340)
      if ImGui.BeginCombo(ctx, rotulo, nome_de(atual)) then
        local ult = par and (info.n - 1) or info.n
        for c = 1, math.max(ult, 1) do
          if ImGui.Selectable(ctx, nome_de(c) .. "##" .. rotulo .. c, c == atual) then atual = c end
        end
        ImGui.EndCombo(ctx)
      end
      return atual
    end
    if saidas_ui.perfil == "CUSTOM" then
      ImGui.Indent(ctx)
      saidas_ui.click = combo("Click", saidas_ui.click, false)
      saidas_ui.guia = combo("Guia", saidas_ui.guia, false)
      saidas_ui.banda = combo("VS L/R", saidas_ui.banda, true)
      ImGui.Unindent(ctx)
    end
    -- prévia
    local prev = MT.roteamento_efetivo(info, { perfil = saidas_ui.perfil, click = saidas_ui.click, guia = saidas_ui.guia, banda = saidas_ui.banda })
    ImGui.Separator(ctx)
    ImGui.Text(ctx, "Resultado: " .. MT.descrever_roteamento(prev, "AO_VIVO"))
    ImGui.TextDisabled(ctx, "No automático, 4 ou mais saídas = Click 1, Guia 2, VS estéreo 3/4.  2 saídas = Click+Guia no 1, VS no 2.")
    ImGui.TextDisabled(ctx, "As saídas são renomeadas no REAPER (CLICK, GUIA, VS L, VS R). Os nomes aparecem ao reabrir o dispositivo de áudio.")
    if prev.aviso then ImGui.PushTextWrapPos(ctx, 420); ImGui.TextColored(ctx, 0xFFC060FF, "Atenção: " .. prev.aviso); ImGui.PopTextWrapPos(ctx) end
    if prev.perfil ~= "2" then
      local cn = info.canais
      ImGui.TextDisabled(ctx, string.format("Click -> %s   |   Guia -> %s   |   VS -> %s / %s",
        cn[prev.click] or "?", cn[prev.guia] or "?", cn[prev.banda] or "?", cn[prev.banda + 1] or "?"))
    end
    if e.modo == "LR" then ImGui.TextDisabled(ctx, "(agora está em L/R ou Studio: o perfil vale quando voltar para AO VIVO)") end
    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, "Aplicar", 120, 0) then
      local pf, c, g, b = saidas_ui.perfil, saidas_ui.click, saidas_ui.guia, saidas_ui.banda
      depois(function() saidas_ui.rot = MT.definir_perfil_saidas(pf, c, g, b) end)
      ImGui.CloseCurrentPopup(ctx)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Cancelar", 120, 0) then ImGui.CloseCurrentPopup(ctx) end
    ImGui.EndPopup(ctx)
  end
  if cel_ui.abrir then
    cel_ui.abrir = false
    cel_ui.web = REM.ler_web()
    cel_ui.ips = REM.ips()
    cel_ui.pagina = REM.pagina_instalada()
    cel_ui.ip_sel, cel_ui.msg, cel_ui.reiniciar = 1, nil, false
    ImGui.OpenPopup(ctx, "Controle pelo celular")
  end
  if REM and ImGui.BeginPopupModal(ctx, "Controle pelo celular", true, ImGui.WindowFlags_AlwaysAutoResize) then
    local web = cel_ui.web or {}
    local ips = cel_ui.ips or {}
    com_fonte(F.media, function() ImGui.TextColored(ctx, C.lavanda, "Mik Seifador Remoto") end)
    ImGui.TextDisabled(ctx, "Android e iPhone, no mesmo Wi-Fi deste computador. Tudo em tempo real.")
    ImGui.Separator(ctx)
    -- 1) página
    if cel_ui.pagina then
      ImGui.TextColored(ctx, 0x7CE38BFF, "OK  Página do controle instalada no REAPER")
    else
      ImGui.TextColored(ctx, 0xFFC060FF, "!  Página do controle ainda não instalada")
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Instalar agora") then
        REM.instalar_pagina(); cel_ui.pagina = REM.pagina_instalada()
      end
    end
    -- 2) interface web
    local w = web[1]
    if w then
      ImGui.TextColored(ctx, 0x7CE38BFF, string.format("OK  Interface web do REAPER configurada na porta %d%s", w.porta,
        (w.usuario ~= "" and ("  (usuário: " .. w.usuario .. ")") or "")))
      if cel_ui.reiniciar then
        ImGui.TextColored(ctx, 0xFFC060FF, "Salve o projeto, FECHE o REAPER e abra de novo para ligar o controle.")
      end
    else
      ImGui.TextColored(ctx, 0xFFC060FF, "!  Interface web do REAPER desligada")
    end
    if cel_ui.msg then ImGui.TextColored(ctx, cel_ui.msg_cor or 0xFF8080FF, cel_ui.msg) end
    ImGui.Spacing(ctx)
    if w then
      -- endereço + QR
      local escolhido = ips[cel_ui.ip_sel] or ips[1]
      local ip = escolhido and escolhido.ip or "IP-DO-PC"
      local url = REM.url(ip, w.porta, true)
      ImGui.Text(ctx, "No celular, aponte a câmera para o QR code ou digite no navegador:")
      com_fonte(F.media, function() ImGui.TextColored(ctx, 0x6FD3FFFF, url) end)
      if ImGui.Button(ctx, "Copiar endereço") then ImGui.SetClipboardText(ctx, url) end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Abrir neste PC") then MT.abrir_no_sistema(REM.url("127.0.0.1", w.porta, true)) end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Detectar IP de novo") then cel_ui.ips = REM.ips(); ips = cel_ui.ips; cel_ui.ip_sel = 1 end
      if #ips > 1 then
        ImGui.TextDisabled(ctx, "Rede do computador (escolha a do Wi-Fi/cabo onde o celular está):")
        for i, it in ipairs(ips) do
          if ImGui.RadioButton(ctx, it.ip .. "   " .. (it.nome or "") .. "##ip" .. i, cel_ui.ip_sel == i) then cel_ui.ip_sel = i end
        end
      elseif #ips == 0 then
        ImGui.TextColored(ctx, 0xFFC060FF, "Não achei o IP do computador: veja em Configurações de rede (IPv4).")
      end
      if QR and escolhido then
        if cel_ui.qr_url ~= url then
          local ok, mat, n = pcall(QR.gerar, url)
          cel_ui.qr_url = url
          if ok then cel_ui.qr, cel_ui.qr_n = mat, n else cel_ui.qr = nil end
        end
        if cel_ui.qr then
          local n, quiet = cel_ui.qr_n, 4
          local m = math.max(3, math.floor(240 / (n + 2 * quiet)))
          local tot = m * (n + 2 * quiet)
          ImGui.Spacing(ctx)
          local x, y = ImGui.GetCursorScreenPos(ctx)
          local dlq = ImGui.GetWindowDrawList(ctx)
          ImGui.DrawList_AddRectFilled(dlq, x, y, x + tot, y + tot, 0xFFFFFFFF, 6)
          for yy = 0, n - 1 do
            local lin = cel_ui.qr[yy]
            for xx = 0, n - 1 do
              if lin[xx] and lin[xx] ~= 0 then
                local px, py = x + (xx + quiet) * m, y + (yy + quiet) * m
                ImGui.DrawList_AddRectFilled(dlq, px, py, px + m, py + m, 0x000000FF)
              end
            end
          end
          ImGui.Dummy(ctx, tot, tot)
        end
      end
      ImGui.Spacing(ctx)
      ImGui.TextDisabled(ctx, "Instalar como app:  iPhone: Safari > Compartilhar > Adicionar à Tela de Início")
      ImGui.TextDisabled(ctx, "                    Android: Chrome > menu (3 pontos) > Adicionar à tela inicial")
      ImGui.TextDisabled(ctx, "Windows: na 1ª vez, se o Firewall perguntar, permita o REAPER em Redes privadas.")
      ImGui.TextDisabled(ctx, "O painel (ou o motor ao vivo) precisa estar aberto no REAPER.")
    else
      ImGui.Text(ctx, "Ligar automaticamente (grava no reaper.ini, com backup):")
      ImGui.SetNextItemWidth(ctx, 90)
      local _, p = ImGui.InputText(ctx, "Porta", cel_ui.porta); cel_ui.porta = p or cel_ui.porta
      ImGui.SetNextItemWidth(ctx, 160)
      local _, u = ImGui.InputText(ctx, "Usuário (opcional)", cel_ui.usuario); cel_ui.usuario = u or ""
      ImGui.SetNextItemWidth(ctx, 160)
      local _, sn = ImGui.InputText(ctx, "Senha (opcional)", cel_ui.senha, ImGui.InputTextFlags_Password); cel_ui.senha = sn or ""
      if ImGui.Button(ctx, "Ativar controle pelo celular", 260, 0) then
        local ok, msg = REM.ativar_web(cel_ui.porta, cel_ui.usuario, cel_ui.senha)
        if ok then
          REM.instalar_pagina(); cel_ui.pagina = REM.pagina_instalada()
          cel_ui.web = REM.ler_web(); cel_ui.ips = cel_ui.ips or REM.ips()
          cel_ui.reiniciar = true
          cel_ui.msg, cel_ui.msg_cor = "Pronto! Agora salve o projeto, feche o REAPER e abra de novo.", 0x7CE38BFF
        else
          cel_ui.msg, cel_ui.msg_cor = "Não deu: " .. tostring(msg), 0xFF8080FF
        end
      end
      ImGui.Spacing(ctx)
      ImGui.TextDisabled(ctx, "Ou pelo REAPER: Options > Preferences > Control/OSC/web > Add > Web browser interface,")
      ImGui.TextDisabled(ctx, "porta 8080, Default interface: mikseifador.html > OK. Depois volte aqui para ver o QR code.")
    end
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Fechar", 120, 0) then ImGui.CloseCurrentPopup(ctx) end
    ImGui.EndPopup(ctx)
  end
  if ImGui.BeginPopup(ctx, "popup_biblio") then
    local lista = biblio.lista or {}
    ImGui.TextDisabled(ctx, "Biblioteca: " .. MT.pasta_biblioteca())
    ImGui.SetNextItemWidth(ctx, 420)
    if ImGui.IsWindowAppearing(ctx) then ImGui.SetKeyboardFocusHere(ctx) end
    local _, b = ImGui.InputTextWithHint(ctx, "##busca_bib", "Buscar música, artista ou tom...", biblio.busca or "")
    biblio.busca = b or ""
    ImGui.Separator(ctx)
    local filtro = MT.norm(biblio.busca)
    local mostradas = 0
    if ImGui.BeginChild(ctx, "##lista_bib", 520, 320) then
      for i, it in ipairs(lista) do
        local alvo = MT.norm(it.rotulo .. " " .. (it.tom or ""))
        if filtro == "" or alvo:find(filtro, 1, true) then
          mostradas = mostradas + 1
          local info = string.format("%s   |   Tom: %s   |   BPM: %s%s", it.rotulo, it.tom or "--",
            it.bpm and tostring(it.bpm) or "--", it.compasso and ("  (" .. it.compasso .. ")") or "")
          if ImGui.Selectable(ctx, info .. "##bib" .. i, false) then
            local item = it
            depois(function() MT.adicionar_da_biblioteca(item) end)
            ImGui.CloseCurrentPopup(ctx)
          end
          if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Clique para pôr no fim do setlist\n" .. it.pasta) end
        end
      end
      if mostradas == 0 then ImGui.TextDisabled(ctx, #lista == 0 and "Biblioteca vazia - use o botão IMPORTAR" or "Nada encontrado") end
      ImGui.EndChild(ctx)
    end
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, "Importar de outra pasta...") then depois(MT.importar_rapido); ImGui.CloseCurrentPopup(ctx) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Atualizar") then biblio.lista = MT.listar_biblioteca() end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Abrir pasta") then
      MT.garantir_biblioteca()
      MT.abrir_no_sistema(MT.pasta_biblioteca())
    end
    ImGui.EndPopup(ctx)
  end
  -- v1.8: + IMPORTAR serve para as duas coisas (música comum e multitrack / VS)
  if ImGui.BeginPopup(ctx, "popup_importar") then
    ImGui.TextDisabled(ctx, "O que você quer importar?")
    if ImGui.MenuItem(ctx, "Música(s)  -  um ou vários arquivos...") then depois(MT.importar_rapido) end
    if ImGui.MenuItem(ctx, "Multitrack / VS  -  escolher a PASTA...") then depois(MT.importar_multitrack_pasta) end
    if ImGui.MenuItem(ctx, "Multitrack / VS  -  escolher os stems...") then
      depois(function()
        local lista, erro = MT.escolher_para_importar()
        if erro and (not lista or #lista == 0) then return r.MB(erro, "Importar multitrack", 0) end
        if not lista or #lista == 0 then return end
        if #lista == 1 then
          -- 1 arquivo só: importa a pasta inteira dele como multitrack
          return MT.importar_multitrack_arquivos({ lista[1] }, nil, true)
        end
        MT.importar_multitrack_arquivos(lista)
      end)
    end
    ImGui.Separator(ctx)
    ImGui.TextDisabled(ctx, "Dica: vários arquivos de uma pasta de stems = 1 multitrack.")
    ImGui.EndPopup(ctx)
  end
  if ImGui.BeginPopup(ctx, "popup_menu") then
    if ImGui.MenuItem(ctx, "Importar música...", MT.atalho("Ctrl+Shift+I")) then depois(MT.importar_rapido) end
    if ImGui.MenuItem(ctx, "Importar (avançado)...") then depois(MT.importar_interativo) end
    if ImGui.MenuItem(ctx, "Biblioteca de multitracks...") then biblio.lista = MT.listar_biblioteca(); abrir_biblio = true end
    if ImGui.MenuItem(ctx, "Pasta da biblioteca...") then depois(MT.definir_pasta_biblioteca) end
    if ImGui.MenuItem(ctx, "Salvar projeto", MT.atalho("Ctrl+S")) then depois(salvar_projeto_painel) end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Marcar seção aqui", "M") then depois(MT.marcar_secao) end
    if ImGui.MenuItem(ctx, "Salvar marcadores", MT.atalho("Ctrl+Alt+S")) then depois(MT.salvar_marcadores) end
    if ImGui.MenuItem(ctx, "Renomear seção atual...", "N") then depois(MT.renomear_secao) end
    if ImGui.MenuItem(ctx, "Colorir seções") then depois(MT.colorir_secoes) end
    if ImGui.MenuItem(ctx, "Definir tom original...", "T") then depois(MT.definir_tom) end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Gerar click + guia + seções + cifra (música atual)") then depois(function() MT.analisar_musica_atual() end) end
    if ImGui.MenuItem(ctx, "Corrigir BPM / compasso (dobro, metade...)") then depois(MT.corrigir_bpm) end
    if ImGui.MenuItem(ctx, "Análise automática ao importar (música comum / VS)", nil, MT.analise_auto()) then MT.alternar_analise_auto() end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Separar trilhas (bateria, baixo, guitarra, teclado, voz)", MT.atalho("Ctrl+Shift+E")) then depois(MT.separar_musica_atual) end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Separa a música atual (comum ou VS fechado) em BATERIA, BAIXO, GUITARRA, TECLADO, VOZ e OUTROS.  [" .. MT.atalho("Ctrl+Shift+E") .. "]\n" ..
        "Roda sem travar o REAPER; as trilhas entram na BANDA alinhadas.\n" ..
        (MT.motor_instalado() and "Motor de separação: instalado" or "Na 1ª vez instala o motor (~1 GB, 1 clique)."))
    end
    if ImGui.MenuItem(ctx, "Exportar trilhas (para qualquer DAW)", MT.atalho("Ctrl+Shift+X")) then depois(MT.exportar_trilhas) end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Gera uma pasta Exportar na pasta da música com as 6 trilhas\n" ..
        "(Bateria, Baixo, Guitarra, Teclado, Voz, Outros — as que existirem),\n" ..
        "o click e a guia em WAV (mesmo começo e mesmo comprimento),\n" ..
        "um LEIA-ME (BPM, compasso, seções) e um MIDI de tempo/marcadores.\n" ..
        "Abre a pasta no fim. Não altera e não salva o projeto.  [" .. MT.atalho("Ctrl+Shift+X") .. "]")
    end
    if ImGui.MenuItem(ctx, "Voltar para a música original (tirar trilhas separadas)") then depois(MT.desfazer_separacao) end
    if ImGui.MenuItem(ctx, "Separar trilhas ao importar (música comum / VS)", nil, MT.separacao_auto()) then MT.alternar_separacao_auto() end
    if ImGui.MenuItem(ctx, "Manter a música original mutada depois de separar", nil, MT.mutar_original()) then MT.alternar_mutar_original() end
    if ImGui.MenuItem(ctx, "Separação rápida (~15% mais rápida, qualidade um pouco menor)", nil, MT.separacao_rapida and MT.separacao_rapida()) then
      depois(MT.alternar_separacao_rapida)
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Quando ligada, a separação usa menos passadas e menos sobreposição\n" ..
        "e costuma ser cerca de 15% mais rápida, com qualidade um pouco menor.\n" ..
        "Padrão: desligada (qualidade normal). A barrinha mostra “Separando (rápida)”.")
    end
    if ImGui.MenuItem(ctx, "Qualidade máxima (tipo Stem Splitter)", nil, MT.separacao_qualidade and MT.separacao_qualidade()) then
      depois(MT.alternar_separacao_qualidade)
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Voz com BS-Roformer e o resto em cascata. Melhor isolamento, mas bem mais lento: cerca de 20 min por música de 3,5 min neste notebook. Desligado = padrão na placa de vídeo, cerca de 2 a 2,5 min.")
    end
    if not MT.motor_instalado() then
      if ImGui.MenuItem(ctx, MT.motor_instalando() and "Instalando o motor de separação..." or "Instalar motor de separação (1 clique)...") then
        depois(function() MT.instalar_motor() end)
      end
    elseif ImGui.BeginMenu(ctx, "Motor de separação") then
      if ImGui.MenuItem(ctx, "Reinstalar motor de separação...") then depois(function() MT.instalar_motor() end) end
      if ImGui.MenuItem(ctx, "Abrir pasta do motor (registros)") then MT.abrir_no_sistema(MT.motor_dir()) end
      ImGui.EndMenu(ctx)
    end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Salto suave (pula no fim do compasso)", "Q", MT.salto_suave()) then MT.alternar_salto_suave() end
    if ImGui.MenuItem(ctx, "Repetir click (Loop Click)", "R", MT.flag("REPETIR_CLICK")) then MT.alternar_repetir_click() end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx, "Reparar estrutura / roteamento") then
      depois(function() r.Undo_BeginBlock(); MT.aplicar_modo(); r.Undo_EndBlock("Reparar estrutura", -1) end)
    end
    if ImGui.MenuItem(ctx, "Recarregar capas e formas de onda") then liberar_capas(); ondas = {}; reguas = {} end
    if ImGui.MenuItem(ctx, "Limpar / apagar músicas...") then
      limpar_ui.musicas = MT.listar_musicas_para_apagar()
      limpar_ui.lixo = MT.listar_lixo()
      limpar_ui.sel, limpar_ui.incluir_lixo, limpar_ui.confirma, limpar_ui.busca = {}, false, false, ""
      abrir_limpar = true
    end
    if ImGui.MenuItem(ctx, "Saídas de áudio (placa)...") then saidas_ui.abrir = true end
    if REM and ImGui.MenuItem(ctx, "Controle pelo celular...") then cel_ui.abrir = true end
    if REM and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Mik Seifador Remoto: controle tudo pelo celular (Android / iPhone)\nno mesmo Wi-Fi, em tempo real.")
    end
    if ImGui.MenuItem(ctx, "Pacote de pads...") then pads_ui.abrir = true end
    if ImGui.MenuItem(ctx, "Importar pasta de pads...") then depois(function() MT.importar_pasta_pads() end) end
    if ImGui.MenuItem(ctx, "Botões grandes de seção (toque)", nil, secoes_grandes()) then
      MT.set("SECOES_GRANDES", secoes_grandes() and "0" or "1")
    end
    if ImGui.MenuItem(ctx, "Mostrar dicas de novo") then dicas_resetar() end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Liga as dicas e zera a contagem: cada botão volta a mostrar a dica 3 vezes.")
    end
    if ImGui.MenuItem(ctx, "Desligar dicas", nil, not dicas_ligadas()) then dicas_desligar() end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "Não mostra mais nenhuma dica até você escolher Mostrar dicas de novo.")
    end
    if ImGui.MenuItem(ctx, "Como usar (guia rápido)...") then depois(function() MT.abrir_como_usar() end) end
    if ImGui.MenuItem(ctx, "Novidades da versão " .. MT.VERSAO .. "...") then abrir_sobre = true end
    if ImGui.MenuItem(ctx, "Sobre o Mik Seifador...") then abrir_sobre = true end
    do -- atualização automática (GitHub): procurar agora / atualizar
      local rem = MT.atualizacao_disponivel and MT.atualizacao_disponivel()
      local st = MT.atualizacao_estado and MT.atualizacao_estado()
      local ocupado = st and st.ocupado
      if rem then
        if ImGui.MenuItem(ctx, "Atualizar agora (build " .. tostring(rem) .. ")", nil, false, not ocupado) then
          depois(function() MT.atualizar_agora() end)
        end
      end
      local rot = "Procurar atualizações" .. (MT.build and ("  (v" .. MT.VERSAO .. " · build " .. tostring(MT.build()) .. ")") or "")
      if ImGui.MenuItem(ctx, rot, nil, false, MT.procurar_atualizacoes ~= nil and not ocupado) then
        depois(function() MT.procurar_atualizacoes(true) end)
      end
    end
    if ImGui.MenuItem(ctx, "Capa animada ao abrir", nil, MT.get("CAPA", "1") ~= "0") then
      MT.set("CAPA", MT.get("CAPA", "1") ~= "0" and "0" or "1")
    end
    if ImGui.MenuItem(ctx, "Ver a capa agora") then MT._rever_capa = true end
    ImGui.Separator(ctx)
    if MT.motor_ativo() then ImGui.TextColored(ctx, C.verde, "Motor ao vivo: rodando")
    else ImGui.TextColored(ctx, C.amarelo, "Motor: o painel cuida do AUTO/HOLD") end
    ImGui.EndPopup(ctx)
  end

  -- v1.6: escolher quais músicas apagar + opção de limpar lixo gerado
  ImGui.SetNextWindowSize(ctx, 680, 560, ImGui.Cond_Appearing)
  if ImGui.BeginPopupModal(ctx, "Limpar arquivos", true) then
    local mus = limpar_ui.musicas or {}
    local lixo = limpar_ui.lixo or { qtd = 0, bytes = 0 }
    if not limpar_ui.confirma then
      com_fonte(F.media, function() ImGui.TextColored(ctx, C.lavanda, "Escolha as músicas que quer apagar") end)
      ImGui.TextWrapped(ctx, "Marque as multitracks. Os arquivos vão para a Lixeira. O desfazer do REAPER não os restaura.")
      ImGui.SetNextItemWidth(ctx, 420)
      local _, b = ImGui.InputTextWithHint(ctx, "##busca_limpar", "Buscar música...", limpar_ui.busca or "")
      limpar_ui.busca = b or ""
      ImGui.Separator(ctx)
      if ImGui.BeginChild(ctx, "##lista_limpar", 0, 310) then
        local filtro = MT.norm(limpar_ui.busca)
        local mostradas = 0
        for i, it in ipairs(mus) do
          local alvo = MT.norm((it.rotulo or it.nome or "") .. " " .. (it.tom or ""))
          if filtro == "" or alvo:find(filtro, 1, true) then
            mostradas = mostradas + 1
            local id = it.id or ("m" .. i)
            local marcado = limpar_ui.sel[id] and true or false
            local rotulo = (it.rotulo or it.nome or "Música") .. "   " .. (MT.fmt_mb and MT.fmt_mb(it.bytes) or "")
            if it.no_projeto then rotulo = rotulo .. "   [neste projeto]" end
            if it.protegida then rotulo = rotulo .. "   (arquivos avulsos)" end
            local mudou, v = ImGui.Checkbox(ctx, rotulo .. "##lim" .. id, marcado)
            if mudou then limpar_ui.sel[id] = v and it or nil end
            if ImGui.IsItemHovered(ctx) then
              local tip = (it.pasta and ("Pasta: " .. it.pasta) or "Pasta não encontrada")
              if it.no_projeto then tip = tip .. "\nEstá neste projeto: sai do setlist também." end
              if it.protegida then tip = tip .. "\nA pasta é compartilhada: só os arquivos desta música serão apagados." end
              ImGui.SetTooltip(ctx, tip)
            end
          end
        end
        if mostradas == 0 then
          ImGui.TextDisabled(ctx, #mus == 0 and "Nenhuma música na Biblioteca nem neste projeto." or "Nada encontrado")
        end
        ImGui.EndChild(ctx)
      end
      if ImGui.Button(ctx, "Marcar todas") then
        for _, it in ipairs(mus) do limpar_ui.sel[it.id] = it end
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Desmarcar") then limpar_ui.sel = {} end
      local nsel, bsel, nproj = 0, 0, 0
      for _, it in pairs(limpar_ui.sel) do
        nsel = nsel + 1
        bsel = bsel + (it.bytes or 0)
        if it.no_projeto then nproj = nproj + 1 end
      end
      ImGui.SameLine(ctx)
      ImGui.Text(ctx, nsel == 0 and "Nenhuma música marcada" or string.format("Selecionadas: %d  ·  %s", nsel, MT.fmt_mb(bsel)))
      ImGui.Separator(ctx)
      local txt_lixo
      if (lixo.qtd or 0) == 0 then
        txt_lixo = "Também limpar lixo gerado (nada pendente)"
      else
        txt_lixo = string.format("Também limpar lixo gerado (%d %s, %s): clicks antigos, __stems órfãos e temporários",
          lixo.qtd, lixo.qtd == 1 and "item" or "itens", MT.fmt_mb(lixo.bytes))
      end
      local _, inc = ImGui.Checkbox(ctx, txt_lixo .. "##incluir_lixo", limpar_ui.incluir_lixo and true or false)
      limpar_ui.incluir_lixo = inc and (lixo.qtd or 0) > 0
      if (lixo.qtd or 0) == 0 then limpar_ui.incluir_lixo = false end
      ImGui.Spacing(ctx)
      local pode = nsel > 0 or limpar_ui.incluir_lixo
      if ImGui.Button(ctx, "Apagar selecionados...", 200, 32) and pode then limpar_ui.confirma = true end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Fechar", 120, 32) then ImGui.CloseCurrentPopup(ctx) end
    else
      local nsel, bsel, nproj, sel = 0, 0, 0, {}
      for _, it in pairs(limpar_ui.sel) do
        sel[#sel + 1] = it
        nsel = nsel + 1
        bsel = bsel + (it.bytes or 0)
        if it.no_projeto then nproj = nproj + 1 end
      end
      local total = bsel + ((limpar_ui.incluir_lixo and lixo.bytes) or 0)
      com_fonte(F.media, function() ImGui.TextColored(ctx, C.amarelo, "Confirma apagar?") end)
      ImGui.Spacing(ctx)
      if nsel > 0 then
        ImGui.TextWrapped(ctx, string.format("Vai apagar %d %s (%s):", nsel, nsel == 1 and "música" or "músicas", MT.fmt_mb(bsel)))
        if ImGui.BeginChild(ctx, "##conf_lista", 0, 140) then
          for _, it in ipairs(sel) do
            local linha = (it.rotulo or it.nome) .. "  (" .. MT.fmt_mb(it.bytes) .. ")"
            if it.no_projeto then ImGui.TextColored(ctx, C.vermelho, linha .. "  — neste projeto")
            else ImGui.Text(ctx, linha) end
          end
          ImGui.EndChild(ctx)
        end
      else
        ImGui.Text(ctx, "Nenhuma música marcada.")
      end
      if limpar_ui.incluir_lixo then
        ImGui.Text(ctx, string.format("Mais o lixo gerado: %s.", MT.fmt_mb(lixo.bytes or 0)))
      end
      ImGui.Text(ctx, "Total: " .. MT.fmt_mb(total) .. ".")
      ImGui.Spacing(ctx)
      if nproj > 0 then
        ImGui.TextColored(ctx, C.vermelho, nproj == 1 and "ATENÇÃO: 1 música está neste projeto e vai sair do setlist."
          or string.format("ATENÇÃO: %d músicas estão neste projeto e vão sair do setlist.", nproj))
      end
      ImGui.TextColored(ctx, C.vermelho, "Os arquivos vão para a Lixeira. O desfazer do REAPER NÃO os restaura.")
      ImGui.Spacing(ctx)
      if ImGui.Button(ctx, "Apagar agora", 160, 32) then
        local itens, inc = sel, limpar_ui.incluir_lixo
        depois(function() MT.apagar_musicas_escolhidas(itens, { incluir_lixo = inc }) end)
        limpar_ui.confirma = false
        ImGui.CloseCurrentPopup(ctx)
      end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Voltar", 120, 32) then limpar_ui.confirma = false end
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Cancelar", 120, 32) then limpar_ui.confirma = false; ImGui.CloseCurrentPopup(ctx) end
    end
    ImGui.EndPopup(ctx)
  end

end

---------------------------------------------------------------------------
-- FORMA DE ONDA + SEÇÕES
---------------------------------------------------------------------------
-- Cifra (acorde atual -> próximo), análise em andamento e versão, por cima da forma de onda
local function desenhar_extras_onda(e, x0, y0, W, H)
  local m = e.musica
  if m then
    local atual, prox, t_prox = MT.acorde_em(e.pos, m)
    if atual or prox then
      local txt1 = atual or "-"
      local txt2 = prox and ("> " .. prox) or ""
      local w1 = com_fonte(F.grande, function() return texto_tam(txt1) end) or 40
      local w2 = com_fonte(F.media, function() return texto_tam(txt2) end) or 40
      local bw = 24 + w1 + 14 + w2
      local bx, by = x0 + 10, y0 + 8
      ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw, by + 46, 0x000000B0, 8)
      ImGui.DrawList_AddRect(dl, bx, by, bx + bw, by + 46, C.borda, 8, 0, 1)
      com_fonte(F.grande, function() ImGui.DrawList_AddText(dl, bx + 12, by + 6, C.amarelo, txt1) end)
      if prox then
        local falta = t_prox and (t_prox - e.pos) or 99
        local cor = (falta < 1.0 and e.tocando) and C.verde or C.texto2
        com_fonte(F.media, function() ImGui.DrawList_AddText(dl, bx + 24 + w1, by + 14, cor, txt2) end)
      end
    end
  end
  -- selo antigo só se a barrinha nova ainda não existir
  local st = (not MT.progresso_trabalho) and MT.analise_status() or nil
  if st then
    com_fonte(F.peq, function()
      local cancela = MT.pode_cancelar_fila_importacao and MT.pode_cancelar_fila_importacao()
      local link = cancela and "  cancelar" or ""
      local tw = texto_tam(st .. link)
      local bx = x0 + W - tw - 30
      ImGui.DrawList_AddRectFilled(dl, bx, y0 + 8, x0 + W - 10, y0 + 32, 0x3A3366E0, 6)
      ImGui.DrawList_AddText(dl, bx + 10, y0 + 13, C.texto, st)
      if cancela then
        local lw = texto_tam(link)
        local lx = x0 + W - 10 - lw - 8
        ImGui.DrawList_AddText(dl, lx, y0 + 13, C.amarelo, link)
        if area("##cancela_fila", lx - 4, y0 + 8, lw + 12, 24) then
          depois(MT.cancelar_fila_importacao)
        end
        if ImGui.IsItemHovered(ctx) then
          ImGui.SetTooltip(ctx, "Cancela as próximas músicas da fila.\nA que está em andamento termina normalmente.")
        end
      end
    end)
  elseif MT.fone_esta_mudo and MT.fone_esta_mudo() then
    -- v1.5: no modo L/R a pasta FONE fica muda — o click existe, mas não sai
    com_fonte(F.peq, function()
      local av = "CLICK MUDO no modo L/R  —  clique aqui ou em Studio para ouvir"
      local tw = texto_tam(av)
      local bw, bh = tw + 24, 28
      local bx, by = x0 + W - bw - 10, y0 + 8
      ImGui.DrawList_AddRectFilled(dl, bx, by, bx + bw, by + bh, 0x5A3010F0, 6)
      ImGui.DrawList_AddText(dl, bx + 12, by + 6, C.amarelo, av)
      if area("##click_mudo", bx, by, bw, bh) then
        depois(function() MT.set("LR_COM_CLICK", "1"); MT.modo_lr() end)
      end
      if ImGui.IsItemHovered(ctx) then
        ImGui.SetTooltip(ctx, "No modo L/R o click fica mudo para não ir para a mesa (PA).\n" ..
          "Studio = ouvir click e banda no ensaio (saídas 1/2).\n" ..
          "Ao Vivo = click num lado e banda no outro.")
      end
    end)
  elseif e.musica and MT.click_aproximado and MT.click_aproximado(e.musica) then
    -- v1.4: aviso discreto quando o click é aproximado (gravação ao vivo difícil)
    com_fonte(F.mini, function()
      local av = "click aproximado - ajuste em Corrigir BPM"
      local tw = texto_tam(av)
      ImGui.DrawList_AddText(dl, x0 + W - tw - 14, y0 + 12, C.texto3, av)
    end)
  end
  com_fonte(F.mini, function()
    local v = (MT.NOME or "Mik Seifador") .. "  v" .. (MT.VERSAO or "?")
    local tw, th = texto_tam(v)
    ImGui.DrawList_AddText(dl, x0 + W - tw - 10, y0 + H - th - 6, C.texto3, v)
  end)
end

local function desenhar_onda(e, x0, y0, W, H)
  local m = e.musica
  caixa(x0, y0, W, H, C.escuro)
  if not m then
    com_fonte(F.media, function() texto_centro(x0, y0, x0 + W, y0 + H, "Importe uma música para ver a forma de onda", C.texto3) end)
    return
  end
  local com_lane = MT.get("SECOES_GRANDES", "0") ~= "1"   -- a faixa de arranjo já mostra os nomes
  local regua_h, rot_h = 18, com_lane and 0 or 22
  local wx1, wx2 = x0 + 8, x0 + W - 8
  local wy1, wy2 = y0 + regua_h + 4, y0 + H - 4
  local ww = wx2 - wx1
  local dur = math.max(0.001, m.fim - m.inicio)
  local function x_de(t) return wx1 + (t - m.inicio) / dur * ww end
  local function t_de(x) return m.inicio + (x - wx1) / ww * dur end

  ImGui.DrawList_PushClipRect(dl, x0 + 1, y0 + 1, x0 + W - 1, y0 + H - 1, true)

  -- seções (fundo colorido)
  local agora = r.time_precise()
  if fila and (not e.tocando or fila.musica ~= m.nome or agora - fila.t > 30
     or (e.secao and math.abs(e.secao.inicio - fila.inicio) < 0.01)) then fila = nil end
  for i, sc in ipairs(e.secoes) do
    local x1, x2 = x_de(sc.inicio), x_de(sc.fim)
    local cor = sc.virtual and 0x6A6A7AFF or de_nativa(sc.cor, rgba(table.unpack(MT.COR_SECAO_PADRAO)))
    local atual = e.secao and sc.n == e.secao.n
    ImGui.DrawList_AddRectFilled(dl, x1, wy1, x2, wy2, alfa(cor, atual and 0x40 or 0x22))
    ImGui.DrawList_AddLine(dl, x1, wy1, x1, wy2, alfa(cor, 0xB0), 1)
    -- rótulo embaixo
    local rot = curto(sc.nome)
    if not com_lane then com_fonte(F.peq, function()
      local tw = texto_tam(rot)
      local larg = x2 - x1
      local txt = (larg > texto_tam(sc.nome) + 16) and sc.nome or rot
      if larg < tw + 8 then txt = "" end
      local by = wy2 - rot_h
      ImGui.DrawList_AddRectFilled(dl, x1 + 1, by, x2 - 1, wy2, alfa(cor, atual and 0xE0 or 0x70))
      if txt ~= "" then ImGui.DrawList_AddText(dl, x1 + 5, by + 4, 0xFFFFFFFF, txt) end
    end) end
  end

  -- loop ativo
  if MT.flag("LOOP") or MT.flag("REPETIR_CLICK") then
    local ls, le = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
    if le > ls then
      local a, b = x_de(ls), x_de(le)
      ImGui.DrawList_AddRectFilled(dl, a, wy1, b, wy1 + 4, C.lavanda)
      ImGui.DrawList_AddRect(dl, a, wy1, b, wy2, alfa(C.lavanda, 0x90), 0, 0, 1.5)
    end
  end

  -- picos
  local passo = 2
  local n = math.max(2, math.floor(ww / passo))
  local picos = onda(m, n)
  local meio = (wy1 + wy2 - rot_h) / 2
  local amp = (wy2 - rot_h - wy1) / 2 - 4
  local xpos = x_de(e.pos)
  if picos then
    for k = 1, n do
      local v = picos[k] or 0
      local h = math.max(0.5, v * amp)
      local xx = wx1 + (k - 1) * passo
      local cor = (xx < xpos) and C.onda_tocada or C.onda
      ImGui.DrawList_AddRectFilled(dl, xx, meio - h, xx + passo - 0.6, meio + h, cor)
    end
  else
    ImGui.DrawList_AddLine(dl, wx1, meio, wx2, meio, C.onda, 1)
  end

  -- régua (compassos)
  ImGui.DrawList_AddRectFilled(dl, x0 + 1, y0 + 1, x0 + W - 1, y0 + regua_h, 0x0A0A0EFF, 6, DRAW_ROUND_TOP)
  local meds = compassos(m)
  local px_comp = (#meds > 1) and (ww / #meds) or ww
  local cada = 1
  for _, c in ipairs({ 1, 2, 4, 8, 16, 32, 64 }) do cada = c; if px_comp * c >= 34 then break end end
  com_fonte(F.mini, function()
    for _, c in ipairs(meds) do
      local xx = x_de(c.t)
      if (c.n - 1) % cada == 0 then
        ImGui.DrawList_AddLine(dl, xx, y0 + regua_h - 6, xx, y0 + regua_h, C.texto3, 1)
        ImGui.DrawList_AddText(dl, xx + 3, y0 + 3, C.texto2, tostring(c.n))
      elseif px_comp >= 5 then
        ImGui.DrawList_AddLine(dl, xx, y0 + regua_h - 3, xx, y0 + regua_h, C.texto3, 1)
      end
    end
  end)

  -- seção na fila (pisca)
  if fila then
    local x1 = x_de(fila.inicio)
    local sc_fim = m.fim
    for _, sc in ipairs(e.secoes) do if math.abs(sc.inicio - fila.inicio) < 0.01 then sc_fim = sc.fim end end
    local a = 0x60 + math.floor(0x9F * (0.5 + 0.5 * math.sin(agora * 9)))
    ImGui.DrawList_AddRect(dl, x1, wy1, x_de(sc_fim), wy2, alfa(C.lavanda, a), 3, 0, 3)
  end

  -- cursor de reprodução
  if xpos >= wx1 - 1 and xpos <= wx2 + 1 then
    ImGui.DrawList_AddLine(dl, xpos, y0 + regua_h - 2, xpos, wy2, C.lavanda, 2)
    ImGui.DrawList_AddTriangleFilled(dl, xpos - 6, y0 + regua_h - 8, xpos + 6, y0 + regua_h - 8, xpos, y0 + regua_h, C.lavanda)
  end
  ImGui.DrawList_PopClipRect(dl)

  -- clique: pula para a seção (Ctrl+clique = posição exata)
  local clicou, passando = area("##onda", wx1, y0, ww, H)
  if passando then
    local mx = ImGui.GetMousePos(ctx)
    local t = t_de(mx)
    local sc = MT.secao_atual(t, e.secoes)
    ImGui.DrawList_AddLine(dl, mx, wy1, mx, wy2, 0xFFFFFF50, 1)
    if sc then ImGui.SetTooltip(ctx, sc.nome .. "  (" .. mmss(sc.inicio - m.inicio) .. ")\nClique: pular para a seção   Ctrl+clique: posição exata") end
    if clicou then
      if tem_imgui("GetKeyMods") then
        local mods = ImGui.GetKeyMods(ctx) or 0
        local mascara = imgui_opcional("Mod_Ctrl", 0) | imgui_opcional("Mod_Super", 0)
        if mascara ~= 0 and (mods & mascara) ~= 0 then MT.ir_para(t); fila = nil
        else pular_secao(e, sc) end
      else
        pular_secao(e, sc)
      end
    end
  end
end

---------------------------------------------------------------------------
-- BARRA DE INFORMAÇÕES
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- LINHA DE SEÇÕES (botões grandes: clique = pular, botão direito = loop)
---------------------------------------------------------------------------
local SEC_H, SEC_GAP = 38, 6
local function layout_secoes(e, W)
  local linhas, x, lin = {}, 0, 1
  local itens = {}
  com_fonte(F.media, function()
    for i, sc in ipairs(e.secoes or {}) do
      local w = math.max(76, math.min(220, texto_tam(sc.nome) + 30))
      if x > 0 and x + w > W then lin = lin + 1; x = 0 end
      itens[i] = { x = x, lin = lin, w = w }
      x = x + w + SEC_GAP
    end
  end)
  -- mais de 2 linhas: encolhe todos para caber em 2
  if lin > 2 and #itens > 0 then
    local por_linha = math.ceil(#itens / 2)
    local w = math.floor((W - SEC_GAP * (por_linha - 1)) / por_linha)
    for i = 1, #itens do
      local k = (i - 1) % por_linha
      itens[i] = { x = k * (w + SEC_GAP), lin = (i <= por_linha) and 1 or 2, w = w }
    end
    lin = 2
  end
  return itens, math.max(1, math.min(2, lin))
end

-- Faixa de ARRANJO (estilo Logic Pro): um bloco por seção, largura = duração,
-- alinhado com a forma de onda. Clique = pular, botão direito = loop.
local LANE_H = 44   -- caixa de 44 px: 6 px de margem + blocos de 32 px
local function pastel(c)
  local rr, gg, bb = (c >> 24) & 255, (c >> 16) & 255, (c >> 8) & 255
  local cinza = (rr + gg + bb) / 3
  local function f(v) v = v * 0.80 + cinza * 0.06 + 255 * 0.14; return math.max(0, math.min(255, math.floor(v))) end
  return rgba(f(rr), f(gg), f(bb), 255)
end

local function acao_loop_secao(sc, em_loop)
  depois(function()
    if em_loop and MT.flag("LOOP") then MT.alternar_loop()
    else
      if not MT.flag("LOOP") then MT.set_flag("LOOP", true) end
      MT.definir_loop(sc.inicio, sc.fim)
      r.GetSetRepeat(1)
      MT.aviso("LOOP: " .. sc.nome)
    end
  end)
end

local function desenhar_lane(e, x0, y0, W)
  local m = e.musica
  if not m or not e.secoes or #e.secoes == 0 then return end
  local wx1, wx2 = x0 + 8, x0 + W - 8
  local ww = wx2 - wx1
  local dur = math.max(0.001, m.fim - m.inicio)
  local function x_de(t) return wx1 + (t - m.inicio) / dur * ww end
  local agora = r.time_precise()
  local loop_on = MT.flag("LOOP") or MT.flag("REPETIR_CLICK")
  local ls, le = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
  local h, y = LANE_H - 12, y0 + 6
  caixa(x0, y0, W, LANE_H, C.escuro)
  for i, sc in ipairs(e.secoes) do
    local x1 = math.floor(x_de(sc.inicio) + 1)
    local x2 = math.floor(x_de(sc.fim) - 1)
    if x2 - x1 < 4 then x2 = x1 + 4 end
    local base = sc.virtual and 0x7A7A8AFF or de_nativa(sc.cor, rgba(table.unpack(MT.COR_SECAO_PADRAO)))
    local atual = e.secao and sc.n == e.secao.n
    local na_fila = fila and math.abs(fila.inicio - sc.inicio) < 0.01
    local em_loop = loop_on and math.abs(ls - sc.inicio) < 0.01 and math.abs(le - sc.fim) < 0.05
    local clicou, passando, segurando = area("##lane" .. i, x1, y, x2 - x1, h)
    local direito = ImGui.IsItemClicked(ctx, 1)
    local duplo = passando and ImGui.IsMouseDoubleClicked(ctx, 0)
    local cor = pastel(base)
    if not atual then cor = ajustar(cor, 0.78) end
    if passando then cor = ajustar(cor, 1.18) end
    if segurando then cor = ajustar(cor, 1.30) end
    -- brilho (glow) do bloco atual
    if atual then
      for k = 2, 1, -1 do
        ImGui.DrawList_AddRect(dl, x1 - k * 1.5, y - k * 1.5, x2 + k * 1.5, y + h + k * 1.5, alfa(cor, 0x30 * (3 - k)), 4 + k, 0, 1)
      end
    end
    -- sombra
    ImGui.DrawList_AddRectFilled(dl, x1 + 1, y + 2, x2 + 1, y + h + 2, 0x00000070, 4)
    -- corpo + degradê (luz em cima, sombra embaixo)
    ImGui.DrawList_AddRectFilled(dl, x1, y, x2, y + h, cor, 4)
    local yi = y + 2
    if x2 - x1 > 6 then
      ImGui.DrawList_AddRectFilledMultiColor(dl, x1 + 2, yi, x2 - 2, y + h * 0.48, 0xFFFFFF40, 0xFFFFFF40, 0xFFFFFF08, 0xFFFFFF08)
      ImGui.DrawList_AddRectFilledMultiColor(dl, x1 + 2, y + h * 0.55, x2 - 2, y + h - 2, 0x00000000, 0x00000000, 0x00000030, 0x00000030)
      ImGui.DrawList_AddLine(dl, x1 + 4, y + 1, x2 - 4, y + 1, 0xFFFFFF60, 1)
    end
    -- progresso dentro do bloco atual
    if atual then
      local k = math.max(0, math.min(1, (e.pos - sc.inicio) / math.max(0.001, sc.fim - sc.inicio)))
      ImGui.DrawList_AddRectFilled(dl, x1, y, x1 + (x2 - x1) * k, y + h, 0xFFFFFF26, 4)
      ImGui.DrawList_AddRectFilled(dl, x1 + 3, y + h - 4, x1 + 3 + (x2 - x1 - 6) * k, y + h - 2, 0xFFFFFFD0, 1)
      ImGui.DrawList_AddRect(dl, x1, y, x2, y + h, 0xFFFFFFFF, 4, 0, 2)
    else
      ImGui.DrawList_AddRect(dl, x1, y, x2, y + h, 0x00000050, 4, 0, 1)
    end
    if na_fila then
      local a = 0x40 + math.floor(0xBF * (0.5 + 0.5 * math.sin(agora * 9)))
      ImGui.DrawList_AddRectFilled(dl, x1, y, x2, y + h, alfa(0xFFFFFF00, a // 4), 4)
      ImGui.DrawList_AddRect(dl, x1 - 1, y - 1, x2 + 1, y + h + 1, alfa(C.lavanda, a), 5, 0, 2)
    end
    -- rótulo branco em negrito, alinhado à esquerda
    local dir_txt = x2 - 6
    if em_loop and x2 - x1 > 30 then ICONE.loop(x2 - 12, y + h / 2, 11, 0xFFFFFFFF); dir_txt = x2 - 22 end
    if dir_txt - (x1 + 7) > 8 then
      ImGui.DrawList_PushClipRect(dl, x1 + 2, y, dir_txt, y + h, true)
      com_fonte(F.lane or F.tile, function()
        local txt = sc.nome
        if texto_tam(txt) > dir_txt - (x1 + 7) then txt = curto(sc.nome) end
        local th = select(2, texto_tam(txt))
        local ty = y + (h - th) / 2 - 1
        ImGui.DrawList_AddText(dl, x1 + 8, ty + 1, 0x00000080, txt)
        ImGui.DrawList_AddText(dl, x1 + 7, ty, 0xFFFFFFFF, txt)
      end)
      ImGui.DrawList_PopClipRect(dl)
    end
    if passando then
      ImGui.SetTooltip(ctx, sc.nome .. "  (" .. mmss(sc.inicio - m.inicio) .. ", " .. mmss(sc.fim - sc.inicio) .. ")\nClique: pular" ..
        (MT.salto_suave() and " no fim do compasso" or "") .. "\nBotão direito: " .. (em_loop and "desligar o loop" or "repetir (loop) esta seção") ..
        (sc.virtual and "" or "\nDuplo clique: renomear"))
    end
    if clicou then pular_secao(e, sc) end
    if duplo and not sc.virtual then
      local alvo_sec = sc
      depois(function() MT.renomear_secao(alvo_sec) end)
    end
    if direito then
      acao_loop_secao(sc, em_loop)
      if not (em_loop and MT.flag("LOOP")) and not atual then pular_secao(e, sc) end
    end
  end
end


local function altura_secoes(e, W)
  if not e.musica or not e.secoes or #e.secoes == 0 then return 0 end
  if not secoes_grandes() then return LANE_H end
  local _, lin = layout_secoes(e, W)
  return lin * SEC_H + (lin - 1) * SEC_GAP
end

local function desenhar_secoes(e, x0, y0, W)
  if not e.musica or not e.secoes or #e.secoes == 0 then return end
  local itens = layout_secoes(e, W)
  local agora = r.time_precise()
  local loop_on = MT.flag("LOOP") or MT.flag("REPETIR_CLICK")
  local ls, le = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
  for i, sc in ipairs(e.secoes) do
    local it = itens[i]
    local x, y = x0 + it.x, y0 + (it.lin - 1) * (SEC_H + SEC_GAP)
    local w = it.w
    local cor = sc.virtual and 0x6A6A7AFF or de_nativa(sc.cor, rgba(table.unpack(MT.COR_SECAO_PADRAO)))
    local atual = e.secao and sc.n == e.secao.n
    local na_fila = fila and math.abs(fila.inicio - sc.inicio) < 0.01
    local em_loop = loop_on and math.abs(ls - sc.inicio) < 0.01 and math.abs(le - sc.fim) < 0.05
    local clicou, passando, segurando = area("##secbtn" .. i, x, y, w, SEC_H)
    local direito = ImGui.IsItemClicked(ctx, 1)
    local duplo = passando and ImGui.IsMouseDoubleClicked(ctx, 0)
    local fundo = atual and cor or alfa(ajustar(cor, 0.55), 0xFF)
    if passando and not atual then fundo = ajustar(fundo, 1.25) end
    if segurando then fundo = ajustar(cor, 1.2) end
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + SEC_H, fundo, 7)
    if atual then
      ImGui.DrawList_AddRect(dl, x - 1, y - 1, x + w + 1, y + SEC_H + 1, 0xFFFFFFE0, 8, 0, 2.5)
    else
      ImGui.DrawList_AddRect(dl, x, y, x + w, y + SEC_H, alfa(cor, 0xC0), 7, 0, 1)
    end
    if na_fila then
      local a = 0x50 + math.floor(0xAF * (0.5 + 0.5 * math.sin(agora * 9)))
      ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + SEC_H, alfa(0xFFFFFF00, a // 3), 7)
      ImGui.DrawList_AddRect(dl, x - 2, y - 2, x + w + 2, y + SEC_H + 2, alfa(C.lavanda, a), 9, 0, 3)
    end
    if em_loop then ICONE.loop(x + w - 13, y + 11, 12, 0xFFFFFFFF) end
    -- progresso dentro da seção atual
    if atual and e.musica then
      local k = math.max(0, math.min(1, (e.pos - sc.inicio) / math.max(0.001, sc.fim - sc.inicio)))
      ImGui.DrawList_AddRectFilled(dl, x + 4, y + SEC_H - 5, x + 4 + (w - 8) * k, y + SEC_H - 2, 0xFFFFFFC0, 2)
    end
    local f = atual and F.media or F.peq
    com_fonte(f, function()
      texto_centro(x + 2, y, x + w - 2, y + SEC_H - 2, cortar(sc.nome, w - 12), atual and 0xFFFFFFFF or 0xE8E8F0FF)
    end)
    if passando then
      ImGui.SetTooltip(ctx, sc.nome .. "  (" .. mmss(sc.inicio - e.musica.inicio) .. ")\nClique: pular" ..
        (MT.salto_suave() and " no fim do compasso" or "") .. "\nBotão direito: " .. (em_loop and "desligar o loop" or "repetir (loop) esta seção") ..
        (sc.virtual and "" or "\nDuplo clique: renomear"))
    end
    if clicou then pular_secao(e, sc) end
    if duplo and not sc.virtual then
      local alvo_sec = sc
      depois(function() MT.renomear_secao(alvo_sec) end)
    end
    if direito then
      local secao = sc
      depois(function()
        if em_loop and MT.flag("LOOP") then MT.alternar_loop()
        else
          if not MT.flag("LOOP") then MT.set_flag("LOOP", true) end
          MT.definir_loop(secao.inicio, secao.fim)
          r.GetSetRepeat(1)
          MT.aviso("LOOP: " .. secao.nome)
        end
      end)
      if not (em_loop and MT.flag("LOOP")) and not atual then pular_secao(e, sc) end
    end
  end
end

local function desenhar_info(e, x0, y0, W)
  local m = e.musica
  local h = 36
  local x = x0
  -- tempo
  caixa(x, y0, 190, h)
  com_fonte(F.media, function()
    local txt = m and (mmss(e.pos - m.inicio) .. " / " .. mmss(m.fim - m.inicio)) or "0:00 / 0:00"
    ImGui.DrawList_AddText(dl, x + 12, y0 + 8, C.texto, txt)
  end)
  if m then
    com_fonte(F.mini, function()
      local rest = "-" .. mmss(m.fim - e.pos)
      local tw = texto_tam(rest)
      ImGui.DrawList_AddText(dl, x + 190 - tw - 8, y0 + 12, C.texto2, rest)
    end)
  end
  x = x + 198
  -- BPM com velocidade (playrate)
  local taxa = r.Master_GetPlayRate(0)
  local bpm_base = e.bpm or 0
  local bpm = bpm_base * taxa
  caixa(x, y0, 190, h)
  com_fonte(F.mini, function() ImGui.DrawList_AddText(dl, x + 8, y0 + 12, C.texto2, "BPM") end)
  com_fonte(F.media, function()
    local txt = (math.abs(bpm - math.floor(bpm + 0.5)) < 0.05) and string.format("%d", math.floor(bpm + 0.5)) or string.format("%.1f", bpm)
    ImGui.DrawList_AddText(dl, x + 38, y0 + 8, math.abs(taxa - 1) > 0.0005 and C.lavanda or C.texto, txt)
  end)
  local function mudar_bpm(delta)
    if bpm_base <= 0 then return end
    local alvo = math.floor(bpm + 0.5) + delta
    if alvo < 20 then alvo = 20 end
    local nova = alvo / bpm_base
    if nova < 0.5 then nova = 0.5 elseif nova > 2 then nova = 2 end
    r.CSurf_OnPlayRateChange(nova)
  end
  if chip("##bpm-", x + 96, y0 + 5, 26, h - 10, "-", false) then mudar_bpm(-1) end
  if chip("##bpm+", x + 126, y0 + 5, 26, h - 10, "+", false) then mudar_bpm(1) end
  if chip("##bpmR", x + 156, y0 + 5, 26, h - 10, "R", false) then r.CSurf_OnPlayRateChange(1) end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Volta ao andamento original da música") end
  x = x + 198
  -- compasso
  local num, den = r.TimeMap_GetTimeSigAtTime(0, e.pos)
  caixa(x, y0, 56, h)
  com_fonte(F.media, function() texto_centro(x, y0, x + 56, y0 + h, string.format("%d/%d", num or 4, den or 4), C.texto) end)
  x = x + 64
  -- IR (lista das seções)
  if chip("##ir", x, y0, 64, h, "IR", false) then ImGui.OpenPopup(ctx, "popup_ir") end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Ir para uma seção da música") end
  x = x + 72
  if chip("##soloclick", x, y0, 104, h, "Solo Click", MT.flag("SOLO_CLICK")) then MT.alternar_solo_click() end
  x = x + 110
  if chip("##loopclick", x, y0, 104, h, "Loop Click", MT.flag("REPETIR_CLICK")) then MT.alternar_repetir_click() end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Repetir click: só o click toca, repetindo a seção atual") end
  x = x + 110
  if chip("##pad", x, y0, 88, h, "PAD", MT.flag("PAD")) then depois(MT.alternar_pad) end
  if ImGui.IsItemClicked(ctx, 1) then pads_ui.abrir = true end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, "PAD no tom (liga/desliga com fade)\n" .. MT.descrever_pad(m) ..
      "\nPacote: " .. ((MT.rotulo_pacote_pads and MT.rotulo_pacote_pads(MT.pacote_pads())) or MT.pacote_pads() or "(pasta _PADS)") ..
      "\nBotão direito: escolher o pacote ou Importar pasta de pads…")
  end
  x = x + 96
  if x + 112 <= x0 + W then
    if chip("##suave", x, y0, 112, h, "Salto suave", MT.salto_suave()) then MT.alternar_salto_suave() end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Pular de seção só no fim do compasso") end
    x = x + 120
  end
  -- botão Saídas + status do motor e da saída (à direita)
  if x + 96 <= x0 + W then
    if chip("##saidas", x, y0, 88, h, "Saídas", false) then saidas_ui.abrir = true end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Placa de áudio e saídas (2 canais, 4 canais ou personalizado)") end
    x = x + 96
  end
  com_fonte(F.peq, function()
    local agora = r.time_precise()
    if not saidas_ui.rot or agora - saidas_ui.t > 1.0 then
      saidas_ui.info = MT.info_placa()
      saidas_ui.rot = MT.roteamento_efetivo(saidas_ui.info)
      saidas_ui.t = agora
    end
    local info_s = saidas_ui.info or MT.info_placa()
    local saida = "Saída: " .. MT.descrever_roteamento(saidas_ui.rot, e.modo)
    if info_s and info_s.nome and info_s.nome ~= "" then saida = saida .. "  [" .. info_s.nome .. "]" end
    local motor = MT.motor_ativo() and "Motor: ON" or "Motor: painel"
    local txt = saida .. "   " .. motor
    local tw = texto_tam(txt)
    if x + tw + 8 <= x0 + W then
      ImGui.DrawList_AddText(dl, x0 + W - tw - 4, y0 + 11, C.texto2, txt)
    end
  end)

  if ImGui.BeginPopup(ctx, "popup_ir") then
    ImGui.TextDisabled(ctx, "Ir para a seção")
    for i, sc in ipairs(e.secoes) do
      local atual = e.secao and sc.n == e.secao.n
      if ImGui.Selectable(ctx, string.format("%s   %s##ir%d", mmss(sc.inicio - (m and m.inicio or 0)), sc.nome, i), atual) then
        pular_secao(e, sc)
      end
    end
    ImGui.EndPopup(ctx)
  end
end

---------------------------------------------------------------------------
-- MIXER
---------------------------------------------------------------------------
-- curva estilo Pro Tools (mt_lib): 0.75 = 0 dB, topo = +12, fundo = -inf
local function vol_para_pos(vol) return MT.fader_pos_ganho(vol) end
local function pos_para_vol(p)
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  return MT.fader_ganho(p)
end
local function db_txt(vol)
  if vol <= 0.0000001 then return "-inf" end
  local db = 20 * math.log(vol, 10)
  if db < -99 then return "-inf" end
  return string.format("%.1f dB", db)
end

local function pico_db(tr, ch)
  local v = r.Track_GetPeakInfo(tr, ch)
  if not v or v <= 0.0000001 then return -90 end
  return 20 * math.log(v, 10)
end

-- v1.8: CANAL clássico v3 (layout do mixer original, console escuro Mik Seifador) com acabamento realista 3D: o mesmo layout de antes
-- (faixa de cor, nome, knob de pan, M/S, fader com escala +12..-inf, medidor e visor em dB),
-- agora com sombras projetadas em camadas, botão metálico com reflexo e chanfro, trilho fundo,
-- knob sombreado, LEDs com brilho e textura escovada no painel. Desenho próprio, sem imagens.
local TEM_MULTICOR = tem_imgui("DrawList_AddRectFilledMultiColor")

local function degrade_v(x1, y1, x2, y2, c_cima, c_baixo)
  if TEM_MULTICOR then
    ImGui.DrawList_AddRectFilledMultiColor(dl, x1, y1, x2, y2, c_cima, c_cima, c_baixo, c_baixo)
  else
    local ym = (y1 + y2) / 2
    ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, ym, c_cima)
    ImGui.DrawList_AddRectFilled(dl, x1, ym, x2, y2, c_baixo)
  end
end
local function degrade_h(x1, y1, x2, y2, c_esq, c_dir)
  if TEM_MULTICOR then
    ImGui.DrawList_AddRectFilledMultiColor(dl, x1, y1, x2, y2, c_esq, c_dir, c_dir, c_esq)
  else
    ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, c_esq)
  end
end
local function mistura(a, b, t)
  local function c(s) local va, vb = (a >> s) & 255, (b >> s) & 255; return math.floor(va + (vb - va) * t + 0.5) << s end
  return c(24) | c(16) | c(8) | c(0)
end
local function com_alfa(cor, a) return (cor & 0xFFFFFF00) | (math.max(0, math.min(255, math.floor(a)))) end
-- sombra macia projetada (várias camadas fracas, deslocadas para baixo/direita: luz de cima/esquerda)
local function sombra_projetada(x1, y1, x2, y2, camadas, forca, dx, dy, raio)
  for k = camadas, 1, -1 do
    local t = k / camadas
    ImGui.DrawList_AddRectFilled(dl, x1 - k * 0.5 + dx * t, y1 - k * 0.3 + dy * t, x2 + k * 0.6 + dx * t, y2 + k * 0.8 + dy * t,
      com_alfa(0x000000FF, forca / (k + 0.8)), (raio or 2) + k * 0.7)
  end
end
local function mods_reset()
  if not tem_imgui("GetKeyMods") then return false end
  local ok, mods = pcall(ImGui.GetKeyMods, ctx)
  if not ok or not mods then return false end
  local m = imgui_opcional("Mod_Ctrl", 0) | imgui_opcional("Mod_Alt", 0) | imgui_opcional("Mod_Super", 0)
  return m ~= 0 and (mods & m) ~= 0
end
local function shift_fino()
  if not tem_imgui("GetKeyMods") then return false end
  local ok, mods = pcall(ImGui.GetKeyMods, ctx)
  local sh = imgui_opcional("Mod_Shift", 0)
  return ok and mods and sh ~= 0 and (mods & sh) ~= 0
end

-- botão do fader (v3): barra de metal escovado, fina e baixa, com chanfro, reflexo especular,
-- sombra macia em camadas (cresce ao arrastar) e linha-guia ciano acesa
local function botao_fader(cx1, cy1, cx2, cy2, ativo)
  local w, h = cx2 - cx1, cy2 - cy1
  local cy = (cy1 + cy2) / 2
  local lev = ativo and 1.7 or 1
  sombra_projetada(cx1, cy1, cx2, cy2, 8, ativo and 120 or 95, 2.5 * lev, 5 * lev, 3)
  ImGui.DrawList_AddRectFilled(dl, cx1 - 0.5, cy1 + 1, cx2 + 1, cy2 + 1.8, 0x000000A0, 3)        -- sombra de contato
  ImGui.DrawList_AddRectFilled(dl, cx1 - 1, cy1 - 1, cx2 + 1, cy2 + 1, 0x0C0E12FF, 3.5)
  local c1, c2, c3 = 0xF1F3F7FF, 0xB4BAC4FF, 0x5A5F69FF
  if ativo then c1, c2, c3 = 0xFFFFFFFF, 0xCDD2DBFF, 0x6C717BFF end
  degrade_v(cx1, cy1, cx2, cy, c1, c2)
  degrade_v(cx1, cy, cx2, cy2, c2, c3)
  -- escovado: riscos horizontais finos alternando claro/escuro
  for k = 1, math.floor(h) - 2, 2 do
    local yy = cy1 + k + 0.5
    ImGui.DrawList_AddLine(dl, cx1 + 1.5, yy, cx2 - 1.5, yy, (k % 4 == 1) and 0xFFFFFF14 or 0x0000001A, 1)
  end
  -- cilindro: luz na esquerda, sombra na direita
  local xm = cx1 + w * 0.38
  degrade_h(cx1 + 1, cy1 + 1, xm, cy2 - 1, 0xFFFFFF2E, 0xFFFFFF00)
  degrade_h(xm, cy1 + 1, cx2 - 1, cy2 - 1, 0x00000000, 0x00000055)
  -- linha-guia ciano com brilho
  ImGui.DrawList_AddRectFilled(dl, cx1 + 1, cy - 1.8, cx2 - 1, cy + 1.8, com_alfa(C.acento, 0x40), 1)
  ImGui.DrawList_AddLine(dl, cx1 + 1.5, cy, cx2 - 1.5, cy, ajustar(C.acento, 1.15), 1.2)
  -- reflexo especular e chanfros
  ImGui.DrawList_AddLine(dl, cx1 + 2, cy1 + 1, cx2 - 2, cy1 + 1, 0xFFFFFFE0, 1)
  ImGui.DrawList_AddRectFilled(dl, cx1 + 2.5, cy1 + 1.5, cx1 + w * 0.45, cy1 + 2.5, 0xFFFFFF60, 1)
  ImGui.DrawList_AddRect(dl, cx1, cy1, cx2, cy2, 0x14161AFF, 3, 0, 1)
  ImGui.DrawList_AddLine(dl, cx1 + 1, cy1 + 2, cx1 + 1, cy2 - 2, 0xFFFFFF60, 1)
  ImGui.DrawList_AddLine(dl, cx1 + 2, cy2 - 1, cx2 - 2, cy2 - 1, 0x000000B0, 1)
  ImGui.DrawList_AddLine(dl, cx2 - 1, cy1 + 2, cx2 - 1, cy2 - 2, 0x00000080, 1)
end

-- medidor como no original: -60..+6 dB em escala linear de dB; ciano, lavanda (> -6) e vermelho (> -0,5)
local function med_frac(db) local f = (db + 60) / 66; if f < 0 then return 0 elseif f > 1 then return 1 end; return f end

local function fader_3d(id, tr, nome, x, y, w, h)
  -- mesma geometria do mixer original: trilho fino no centro, medidores ao lado, valor embaixo
  local fy1, fy2 = y + 80, y + h - 24
  if fy2 - fy1 < 20 then fy2 = fy1 + 20 end
  local fh = fy2 - fy1
  local fx = math.floor(x + w / 2 - 8) + 0.5
  local CAP_W, CAP_H = 18, 13
  local vol = r.GetMediaTrackInfo_Value(tr, "D_VOL")

  -- interação (arrastar / roda / duplo clique / Ctrl, Alt ou Cmd + clique = 0 dB)
  local _, pass_f, seg_f = area(id .. "vol", fx - 11, fy1 - 8, 32, fh + 16)
  local reset = false
  if pass_f and ImGui.IsMouseClicked(ctx, 0) and mods_reset() then reset = true end
  if pass_f and ImGui.IsMouseDoubleClicked(ctx, 0) then reset = true end
  if reset then
    r.SetMediaTrackInfo_Value(tr, "D_VOL", 1)
  elseif seg_f and not mods_reset() then
    local _, dy = ImGui.GetMouseDelta(ctx)
    if dy ~= 0 then
      local p = vol_para_pos(vol) - dy / fh * (shift_fino() and 0.2 or 1)
      r.SetMediaTrackInfo_Value(tr, "D_VOL", pos_para_vol(p))
    end
  end
  if pass_f then
    local roda = ImGui.GetMouseWheel(ctx)
    if roda and roda ~= 0 then
      local db = (vol > 0) and (20 * math.log(vol, 10)) or -60
      db = math.min(12, db + roda * 0.5)
      r.SetMediaTrackInfo_Value(tr, "D_VOL", 10 ^ (db / 20))
    end
    ImGui.SetTooltip(ctx, nome .. ": " .. db_txt(r.GetMediaTrackInfo_Value(tr, "D_VOL")) ..
      "\nArraste (Shift = fino) ou roda do mouse\nDuplo clique ou Ctrl/Alt + clique = 0 dB")
  end
  vol = r.GetMediaTrackInfo_Value(tr, "D_VOL")
  local p = vol_para_pos(vol)
  local cy = math.floor(fy2 - p * fh) + 0.5

  -- trilho fino afundado: canaleta com chanfro, fenda de 4 px com sombra interna
  local t1, t2 = fy1 - 4, fy2 + 1
  ImGui.DrawList_AddRectFilled(dl, fx - 5, t1 - 2, fx + 5, t2 + 2, 0x0A0C10FF, 5)
  ImGui.DrawList_AddLine(dl, fx - 4, t2 + 2.5, fx + 5, t2 + 2.5, 0xFFFFFF1E, 1)               -- lábio claro embaixo
  ImGui.DrawList_AddLine(dl, fx + 5.5, t1, fx + 5.5, t2 + 1, 0xFFFFFF10, 1)
  ImGui.DrawList_AddRectFilled(dl, fx - 2, t1, fx + 2, t2, 0x000000FF, 2)
  degrade_v(fx - 2, t1, fx + 2, t1 + 12, 0x000000FF, 0x00000000)
  ImGui.DrawList_AddLine(dl, fx - 1.5, t1 + 2, fx - 1.5, t2 - 1, 0x000000FF, 1)
  ImGui.DrawList_AddLine(dl, fx + 1.5, t1 + 3, fx + 1.5, t2 - 1, 0xFFFFFF0E, 1)
  -- parte ativa (do fundo até o botão) acesa em ciano bem suave
  if p > 0 then
    ImGui.DrawList_AddRectFilled(dl, fx - 1, cy, fx + 1, t2 - 1, com_alfa(C.acento, 0x70), 1)
    ImGui.DrawList_AddRectFilled(dl, fx - 3, cy, fx + 3, t2 - 1, com_alfa(C.acento, 0x12), 2)
  end
  -- marca de 0 dB: risco gravado com ponto ciano
  local un = math.floor(fy2 - vol_para_pos(1) * fh) + 0.5
  ImGui.DrawList_AddLine(dl, fx - 8, un, fx + 8, un, 0x000000B0, 1)
  ImGui.DrawList_AddLine(dl, fx - 8, un + 1, fx + 8, un + 1, 0x6A7382FF, 1)
  ImGui.DrawList_AddCircleFilled(dl, fx - 9.5, un + 0.5, 2.2, com_alfa(C.acento, 0x40), 10)
  ImGui.DrawList_AddCircleFilled(dl, fx - 9.5, un + 0.5, 1.1, C.acento, 8)

  -- medidores (2 barras finas de 4 px) em caixas de vidro, com degradê, brilho e LEDs finos
  for ch = 0, 1 do
    local db = pico_db(tr, ch)
    local chave = tostring(tr) .. ch
    local ant = medidores[chave] or -90
    if db < ant then db = math.max(db, ant - 1.2) end
    medidores[chave] = db
    local frac = med_frac(db)
    local mx = fx + 11.5 + ch * 6
    ImGui.DrawList_AddRectFilled(dl, mx - 1, fy1 - 1, mx + 5, fy2 + 1, 0x06070AFF, 2)
    ImGui.DrawList_AddRectFilled(dl, mx, fy1, mx + 4, fy2, 0x020304FF, 1)
    ImGui.DrawList_AddLine(dl, mx - 0.5, fy2 + 1.5, mx + 4.5, fy2 + 1.5, 0xFFFFFF16, 1)
    -- trilha apagada (bem fraca) com as 3 faixas de cor
    local y_lav = fy2 - med_frac(-6) * fh
    local y_red = fy2 - med_frac(-0.5) * fh
    ImGui.DrawList_AddRectFilled(dl, mx, y_lav, mx + 4, fy2, com_alfa(C.acento, 0x14))
    ImGui.DrawList_AddRectFilled(dl, mx, y_red, mx + 4, y_lav, com_alfa(C.lavanda, 0x14))
    ImGui.DrawList_AddRectFilled(dl, mx, fy1, mx + 4, y_red, com_alfa(C.vermelho, 0x16))
    if frac > 0 then
      local ytop = fy2 - frac * fh
      local function faixa(a, b, cor)
        a, b = math.max(a, ytop), b
        if b <= a then return end
        ImGui.DrawList_AddRectFilled(dl, mx - 1.5, a - 1, mx + 5.5, b, com_alfa(cor, 0x2A), 2)          -- brilho
        degrade_h(mx, a, mx + 4, b, ajustar(cor, 1.18), ajustar(cor, 0.78))
      end
      faixa(y_lav, fy2, C.acento)
      faixa(y_red, y_lav, C.lavanda)
      faixa(fy1, y_red, C.vermelho)
      ImGui.DrawList_AddLine(dl, mx, ytop + 0.5, mx + 4, ytop + 0.5, 0xFFFFFFC0, 1)                       -- topo aceso
    end
    -- divisões finas de LED e reflexo do vidro
    for yy = fy2 - 3, fy1, -3 do ImGui.DrawList_AddLine(dl, mx, yy + 0.5, mx + 4, yy + 0.5, 0x02030480, 1) end
    degrade_h(mx, fy1, mx + 2, fy2, 0xFFFFFF14, 0xFFFFFF00)
  end

  -- botão do fader
  botao_fader(fx - CAP_W / 2, cy - CAP_H / 2, fx + CAP_W / 2, cy + CAP_H / 2, seg_f or pass_f)

  -- valor (igual ao original)
  com_fonte(F.mini, function() texto_centro(x, fy2 + 4, x + w, y + h - 2, db_txt(vol), C.texto2) end)
end

local function canal(id, tr, nome, cor_trilha, x, y, w, h, eh_master)
  -- fundo
  ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.painel, 6)
  ImGui.DrawList_AddRect(dl, x, y, x + w, y + h, C.borda, 6, 0, 1)
  ImGui.DrawList_AddRectFilled(dl, x + 6, y + 3, x + w - 6, y + 5, cor_trilha, 2)
  com_fonte(F.mini, function() texto_centro(x + 2, y + 6, x + w - 2, y + 22, cortar(nome, w - 6), C.texto) end)

  -- knob de pan
  local pan = r.GetMediaTrackInfo_Value(tr, "D_PAN")
  local kr = 11
  local kcx, kcy = x + w / 2, y + 38
  local _, pass_k, seg_k = area(id .. "pan", kcx - kr - 2, kcy - kr - 2, kr * 2 + 4, kr * 2 + 4)
  if seg_k then
    local _, dy = ImGui.GetMouseDelta(ctx)
    local dx = ImGui.GetMouseDelta(ctx)
    local nv = pan + (dx - dy) * 0.01
    if nv < -1 then nv = -1 elseif nv > 1 then nv = 1 end
    if nv ~= pan then r.SetMediaTrackInfo_Value(tr, "D_PAN", nv); pan = nv end
  end
  if pass_k then
    if ImGui.IsMouseDoubleClicked(ctx, 0) then r.SetMediaTrackInfo_Value(tr, "D_PAN", 0); pan = 0 end
    local roda = ImGui.GetMouseWheel(ctx)
    if roda and roda ~= 0 then
      local nv = math.max(-1, math.min(1, pan + roda * 0.05)); r.SetMediaTrackInfo_Value(tr, "D_PAN", nv); pan = nv
    end
    local ptxt = math.abs(pan) < 0.005 and "Centro" or (pan < 0 and string.format("%d%% E", math.floor(-pan * 100 + 0.5)) or string.format("%d%% D", math.floor(pan * 100 + 0.5)))
    ImGui.SetTooltip(ctx, nome .. "\nPan: " .. ptxt .. "  (duplo clique = centro)")
  end
  ImGui.DrawList_AddCircleFilled(dl, kcx, kcy, kr, pass_k and 0x2E2E40FF or 0x252533FF, 24)
  ImGui.DrawList_AddCircle(dl, kcx, kcy, kr, alfa(C.acento, 0xA0), 24, 1.5)
  local ang = (-135 + (pan + 1) / 2 * 270 - 90) * math.pi / 180
  ImGui.DrawList_AddLine(dl, kcx, kcy, kcx + math.cos(ang) * (kr - 2), kcy + math.sin(ang) * (kr - 2), C.lavanda, 2)

  -- mute / solo
  local by = y + 54
  local bw = math.floor((w - 14) / 2)
  local mudo
  if eh_master then mudo = MT.master_mudo() else mudo = r.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 end
  if chip(id .. "M", x + 5, by, bw, 16, "M", mudo, C.vermelho) then
    if eh_master then MT.mutar_master(not mudo) else r.SetMediaTrackInfo_Value(tr, "B_MUTE", mudo and 0 or 1) end
  end
  if not eh_master then
    local solo = r.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0
    if chip(id .. "S", x + 9 + bw, by, bw, 16, "S", solo, C.amarelo) then
      r.SetMediaTrackInfo_Value(tr, "I_SOLO", solo and 0 or 2)
    end
  end

  -- fader + medidor (v3: fino, realista 3D)
  fader_3d(id, tr, nome, x, y, w, h)
end

local function cor_da_trilha(tr, padrao)
  local c = r.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR")
  if c and c ~= 0 then return de_nativa(math.floor(c), padrao) end
  local pai = r.GetParentTrack(tr)
  if pai then
    local cp = r.GetMediaTrackInfo_Value(pai, "I_CUSTOMCOLOR")
    if cp and cp ~= 0 then return de_nativa(math.floor(cp), padrao) end
  end
  return padrao
end

local function desenhar_mixer(x0, y0, W, H, e)
  local cw, gap = 60, 6
  local direita = {}
  local pad = MT.achar_trilha(MT.CFG.NOME_PAD)
  local guia = MT.achar_trilha(MT.CFG.NOME_GUIA)
  local click = MT.achar_trilha(MT.CFG.NOME_CLICK)
  if pad then direita[#direita + 1] = { tr = pad, nome = "PAD" } end
  if guia then direita[#direita + 1] = { tr = guia, nome = "GUIA" } end
  if click then direita[#direita + 1] = { tr = click, nome = "CLICK" } end
  -- outros clicks/guias da pasta FONE (ex.: INT CLK, NAT CLK)
  local fone = MT.achar_fone()
  if fone then
    for i = 0, r.CountTracks(0) - 1 do
      local tr = r.GetTrack(0, i)
      if r.GetParentTrack(tr) == fone and tr ~= click and tr ~= guia then
        local _, nm = r.GetTrackName(tr)
        direita[#direita + 1] = { tr = tr, nome = nm }
      end
    end
  end
  direita[#direita + 1] = { tr = r.GetMasterTrack(0), nome = "MASTER", master = true }
  local cwd = 66
  local larg_dir = #direita * (cwd + gap) + 10

  -- títulos
  com_fonte(F.mini, function()
    ImGui.DrawList_AddText(dl, x0 + 2, y0, C.texto3, "STEMS  -  BANDA")
    ImGui.DrawList_AddText(dl, x0 + W - larg_dir + 12, y0, C.texto3, "FONE / SAÍDA")
  end)
  local yc = y0 + 16
  local hc = H - 16

  -- stems (rolagem horizontal se não couber)
  -- v1.8: só os stems com áudio na música atual (as outras músicas ficam escondidas)
  local stems, total_stems = MT.trilhas_da_musica("painel", stems_da_banda, e and e.musica)
  total_stems = total_stems or #stems
  local area_w = W - larg_dir
  ImGui.SetCursorScreenPos(ctx, x0, yc)
  local flags = ImGui.WindowFlags_HorizontalScrollbar | ImGui.WindowFlags_NoBackground
  if ImGui.BeginChild(ctx, "##stems", area_w, hc, 0, flags) then
    local dl_ant = dl
    dl = ImGui.GetWindowDrawList(ctx)
    local cx0, cy0 = ImGui.GetCursorScreenPos(ctx)
    local total = #stems * (cw + gap)
    local precisa_rolar = total > area_w
    local hh = hc - (precisa_rolar and 14 or 0)
    if #stems == 0 then
      com_fonte(F.peq, function() texto_centro(cx0, cy0, cx0 + area_w, cy0 + hh, total_stems > 0 and "Nenhum stem nesta música" or "Nenhum stem na pasta BANDA", C.texto3) end)
    end
    for i, tr in ipairs(stems) do
      canal("##st" .. i, tr, MT.nome_trilha(tr), cor_da_trilha(tr, C.acento), cx0 + (i - 1) * (cw + gap), cy0, cw, hh, false)
    end
    ImGui.SetCursorScreenPos(ctx, cx0, cy0)
    ImGui.Dummy(ctx, math.max(1, total), math.max(1, hh))
    dl = dl_ant
    ImGui.EndChild(ctx)
  end

  -- PAD / GUIA / CLICK / MASTER
  local xd = x0 + W - larg_dir + 10
  ImGui.DrawList_AddLine(dl, xd - 6, yc, xd - 6, yc + hc, C.borda, 1)
  for i, c in ipairs(direita) do
    local cor = c.master and C.lavanda or cor_da_trilha(c.tr, C.ciano)
    canal("##dir" .. i, c.tr, c.nome, cor, xd + (i - 1) * (cwd + gap), yc, cwd, hc, c.master)
  end
end

-- aviso rápido no painel (ex.: "Projeto salvo"), some sozinho
local aviso_painel = { txt = nil, t = 0 }
local function avisar_painel(txt) aviso_painel.txt = txt; aviso_painel.t = reaper.time_precise() end
local function desenhar_aviso_painel()
  if not aviso_painel.txt then return end
  local idade = reaper.time_precise() - aviso_painel.t
  if idade > 2.5 then aviso_painel.txt = nil; return end
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww, wh = ImGui.GetWindowSize(ctx)
  local d = tem_imgui("GetForegroundDrawList") and ImGui.GetForegroundDrawList(ctx) or ImGui.GetWindowDrawList(ctx)
  local tw, th = ImGui.CalcTextSize(ctx, aviso_painel.txt)
  local bw, bh = tw + 36, th + 18
  local x1, y1 = wx + (ww - bw) / 2, wy + wh - bh - 40
  local a = idade > 2.0 and math.max(0, 1 - (idade - 2.0) / 0.5) or 1
  local alfa = math.floor(0xEE * a)
  ImGui.DrawList_AddRectFilled(d, x1, y1, x1 + bw, y1 + bh, (0x1E7A46 << 8) | alfa, 8)
  ImGui.DrawList_AddText(d, x1 + 18, y1 + 9, 0xFFFFFF00 | math.floor(0xFF * a), aviso_painel.txt)
end
-- botão SALVAR / Ctrl+S: salva o projeto atual (sem nome = "Salvar como")
salvar_projeto_painel = function()
  local ok, msg = MT.salvar_projeto()
  avisar_painel(msg or (ok and "Projeto salvo" or "Projeto não foi salvo"))
end

---------------------------------------------------------------------------
-- QUADRO
---------------------------------------------------------------------------
local function teclado()
  if ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows) and not ImGui.IsAnyItemActive(ctx)
     and not ImGui.IsPopupOpen(ctx, "", ImGui.PopupFlags_AnyPopupId) then
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Space, false) then MT.play_pause() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then MT.parar() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_RightArrow, false) then MT.proxima_secao() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_LeftArrow, false) then MT.secao_anterior() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_PageDown, false) then MT.proxima_musica() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_PageUp, false) then MT.musica_anterior() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadAdd, false) or ImGui.IsKeyPressed(ctx, ImGui.Key_Equal, false) then depois(MT.tom_mais) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadSubtract, false) or ImGui.IsKeyPressed(ctx, ImGui.Key_Minus, false) then depois(MT.tom_menos) end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_A, false) then MT.alternar("AUTO", "AUTO") end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_H, false) then MT.alternar("HOLD", "HOLD") end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_L, false) then MT.alternar_loop() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_C, false) then MT.alternar_solo_click() end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_P, false) then depois(MT.alternar_pad) end
    do -- atalhos com modificador: Ctrl+S salva o projeto; Ctrl+Shift+E separa trilhas; Ctrl+Shift+X exporta trilhas
      local okm, mods = false, 0
      if tem_imgui("GetKeyMods") then okm, mods = pcall(ImGui.GetKeyMods, ctx) end
      if not okm or not mods then mods = 0 end
      local ctrl = (mods & (imgui_opcional("Mod_Ctrl", 0) | imgui_opcional("Mod_Super", 0))) ~= 0
      local shift = (mods & imgui_opcional("Mod_Shift", 0)) ~= 0
      local alt = (mods & imgui_opcional("Mod_Alt", 0)) ~= 0
      if ctrl and not shift and not alt and ImGui.IsKeyPressed(ctx, ImGui.Key_S, false) then depois(salvar_projeto_painel) end
      if ctrl and shift and not alt and ImGui.IsKeyPressed(ctx, ImGui.Key_E, false) then depois(MT.separar_musica_atual) end
      if ctrl and shift and not alt and ImGui.IsKeyPressed(ctx, ImGui.Key_X, false) then depois(MT.exportar_trilhas) end
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_N, false) then depois(MT.renomear_secao) end
  end
end

local function desenhar()
  MT.tick_se_sem_motor()  -- se o motor não estiver ligado, o painel confere a guia sozinho
  local e = MT.estado()
  teclado()
  dl = ImGui.GetWindowDrawList(ctx)
  local x0, y0 = ImGui.GetCursorScreenPos(ctx)
  local W, H = ImGui.GetContentRegionAvail(ctx)

  local h_topo = 128
  local h_info = 36
  local h_sec = altura_secoes(e, W)
  local esp_sec = h_sec > 0 and (h_sec + 10) or 0
  -- v1.8: mixer estilo Pro Tools: faders altos (metade da janela, até 620 px)
  local h_mixer = math.max(300, math.min(620, math.floor(H * 0.52)))
  local h_onda = H - h_topo - h_info - h_mixer - esp_sec - 3 * 10
  if h_onda < 90 then
    h_onda = 90
    h_mixer = math.max(240, H - h_topo - h_info - esp_sec - h_onda - 30)
  end

  desenhar_topo(e, x0, y0, W)
  local y = y0 + h_topo + 10
  desenhar_onda(e, x0, y, W, h_onda)
  desenhar_extras_onda(e, x0, y, W, h_onda)
  y = y + h_onda + 10
  if h_sec > 0 then
    if secoes_grandes() then desenhar_secoes(e, x0, y, W) else desenhar_lane(e, x0, y, W) end
    y = y + h_sec + 10
  end
  desenhar_info(e, x0, y, W)
  y = y + h_info + 10
  desenhar_mixer(x0, y, W, h_mixer, e)
  -- marca o tamanho total usado (evita aviso de limites do ImGui)
  ImGui.SetCursorScreenPos(ctx, x0, y0)
  ImGui.Dummy(ctx, W, math.max(1, H - 1))
  -- a janela inteira aceita pastas/arquivos soltos (importa do jeito rápido)
  alvo_soltar_arquivos()
end

local CORES_ESTILO = {
  { "Col_WindowBg", C.fundo }, { "Col_ChildBg", 0x00000000 }, { "Col_PopupBg", 0x161A20F8 },
  { "Col_Border", C.borda }, { "Col_Text", C.texto }, { "Col_TextDisabled", C.texto2 },
  { "Col_TitleBg", 0x0A0C10FF }, { "Col_TitleBgActive", 0x161A20FF }, { "Col_TitleBgCollapsed", 0x0A0C10FF },
  { "Col_FrameBg", C.painel2 }, { "Col_FrameBgHovered", C.painel3 }, { "Col_FrameBgActive", C.acento_esc },
  { "Col_Button", C.painel2 }, { "Col_ButtonHovered", C.painel3 }, { "Col_ButtonActive", C.acento_esc },
  { "Col_Header", C.acento_esc }, { "Col_HeaderHovered", 0x2A4A58FF }, { "Col_HeaderActive", C.acento },
  { "Col_Separator", C.borda }, { "Col_ScrollbarBg", 0x0C0E12FF }, { "Col_ScrollbarGrab", 0x3A424EFF },
  { "Col_ScrollbarGrabHovered", 0x4A6270FF }, { "Col_ScrollbarGrabActive", C.acento },
  { "Col_CheckMark", C.acento }, { "Col_ResizeGrip", 0x1A3A4850 }, { "Col_ResizeGripHovered", C.acento_esc },
  { "Col_ResizeGripActive", C.acento },
}
local VARS_ESTILO = {
  { "StyleVar_WindowPadding", 14, 12 }, { "StyleVar_WindowRounding", 8 }, { "StyleVar_FrameRounding", 8 },
  { "StyleVar_PopupRounding", 8 }, { "StyleVar_ItemSpacing", 8, 6 }, { "StyleVar_ScrollbarSize", 10 },
  { "StyleVar_ScrollbarRounding", 8 }, { "StyleVar_WindowBorderSize", 1 }, { "StyleVar_PopupBorderSize", 1 },
  { "StyleVar_FramePadding", 10, 6 },
}
-- resolve as constantes uma vez (ignora as que não existirem nesta versão)
local cores_ok, vars_ok = {}, {}
for _, c in ipairs(CORES_ESTILO) do
  local ok, id = pcall(function() return ImGui[c[1]] end)
  if ok and id then cores_ok[#cores_ok + 1] = { id, c[2] } end
end
for _, v in ipairs(VARS_ESTILO) do
  local ok, id = pcall(function() return ImGui[v[1]] end)
  if ok and id then vars_ok[#vars_ok + 1] = { id, v[2], v[3] } end
end

-- Barra de título própria (Minimizar / Maximizar / Fechar), no estilo Windows.
-- O título nativo do ImGui não oferece minimizar/maximizar, então desenhamos um.
local TITULO_H = 32
local COMPACT_H = 44   -- barra compacta: transporte + restaurar
local janela = { minimizado = false, maximizado = false, prev = nil, pedido = nil, arrastando = false }

local function flag_janela(nome)
  local ok, v = pcall(function() return ImGui[nome] end)
  if ok and type(v) == "number" then return v end
  return 0
end

local FLAGS_JANELA = flag_janela("WindowFlags_NoCollapse")
  | flag_janela("WindowFlags_NoScrollbar")
  | flag_janela("WindowFlags_NoScrollWithMouse")
  | flag_janela("WindowFlags_NoTitleBar")
  | flag_janela("WindowFlags_NoMove")

local function titulo_janela()
  return "Mik Seifador  v" .. (MT.VERSAO or "1.0")
end

local function titulo_hwnd_ok(h)
  if not h or h == 0 then return false end
  if not r.JS_Window_GetTitle then return true end
  local ok, tit = pcall(r.JS_Window_GetTitle, h)
  if not ok or type(tit) ~= "string" then return true end
  return tit:find("Mik Seifador", 1, true) ~= nil
end

local function hwnd_painel()
  if not r.JS_Window_Find then return nil end
  local versao = tostring(MT.VERSAO or "1.8")
  local candidatos = { titulo_janela(), "Mik Seifador  v" .. versao, "Mik Seifador v" .. versao }
  for _, tit in ipairs(candidatos) do
    local h = r.JS_Window_Find(tit, true)
    if titulo_hwnd_ok(h) then return h end
  end
  -- substring só se o título realmente for do painel (não outra janela qualquer)
  local h = r.JS_Window_Find("Mik Seifador", false)
  if titulo_hwnd_ok(h) then return h end
  return nil
end

local function js_show(hwnd, estado)
  if not hwnd or not r.JS_Window_Show then return false end
  -- A API pede uma STRING ("SHOWMINIMIZED", "RESTORE"...), não o número SW_*.
  local ok, ret = pcall(r.JS_Window_Show, hwnd, estado)
  return ok and ret ~= false
end

-- JS_Window_GetRect devolve (ok, l, t, r, b); pcall acrescenta mais um boolean.
-- No macOS o eixo Y é o da Cocoa (origem embaixo): top > bottom. Largura e
-- altura usam o valor absoluto; a conversão do Y para o ImGui (origem em cima)
-- fica a cargo de quem conhece a altura da tela.
local function js_rect(hwnd)
  if not hwnd or not r.JS_Window_GetRect then return end
  local pok, a, b, c, d, e = pcall(r.JS_Window_GetRect, hwnd)
  if not pok then return end
  local l, t, rgt, bt
  if type(a) == "boolean" then
    if not a then return end
    l, t, rgt, bt = b, c, d, e
  else
    l, t, rgt, bt = a, b, c, d
  end
  if type(l) ~= "number" then return end
  t, rgt, bt = t or 0, rgt or l, bt or t or 0
  local cocoa = MT.EH_MAC and t > bt
  return l, t, rgt, bt, cocoa
end

local function js_rect_tamanho(l, t, rgt, bt, cocoa)
  local w = math.abs((rgt or l) - l)
  local h = cocoa and math.abs((t or 0) - (bt or 0)) or ((bt or t or 0) - (t or 0))
  return w, h
end

-- Área ÚTIL do MONITOR (sem menu / dock / barra de tarefas), em pontos do
-- ImGui (já vale para Retina/HiDPI). Não usa a viewport da própria janela.
local mon_cache = { t = -1 }
local function area_monitor()
  local agora = r.time_precise and r.time_precise() or 0
  if mon_cache.w and agora - (mon_cache.t or 0) < 0.4 then
    return mon_cache.x, mon_cache.y, mon_cache.w, mon_cache.h
  end
  local function ok(x, y, w, h)
    if w and h and w >= 640 and h >= 400 then return x or 0, y or 0, w, h end
  end
  local function ltrb(l, tp, rgt, bt)
    if type(l) ~= "number" or type(rgt) ~= "number" then return end
    local cocoa = MT.EH_MAC and type(bt) == "number" and tp and tp > bt
    local w, h = js_rect_tamanho(l, tp or 0, rgt, bt or 0, cocoa)
    if w >= 640 and h >= 400 then
      local y = tp or 0
      if cocoa then
        -- Cocoa: tp é o topo (Y maior). ImGui Y = altura_da_tela - tp.
        -- Se bt é a base da área útil, a altura da tela primária costuma
        -- ser o próprio tp da tela cheia; aqui h já é a área útil.
        y = 0
        -- Se o retângulo útil não começa no fundo, y = (bt medido a partir
        -- da base) vira margem inferior; o topo ImGui fica tela - tp.
        -- Sem a altura total, o melhor aproximado é 0 quando bt é pequeno.
        if bt and bt > 8 then
          -- área de trabalho acima do dock: topo ImGui = desconhecido.
          -- Deixamos y=0 e deixamos o ImGui / GetMainViewport corrigir.
        end
      end
      return ok(l, y, w, h)
    end
    if rgt >= 640 and (bt or 0) >= 400 then
      return ok(l, tp or 0, rgt, bt or 0)
    end
  end
  local melhor
  local function considerar(x, y, w, h)
    local a, b, c, d = ok(x, y, w, h)
    if not a then return end
    if (not melhor) or (c * d > melhor[3] * melhor[4]) then
      melhor = { a, b, c, d }
    end
  end

  -- 1) Área de trabalho do viewport principal do ImGui (pontos, já com HiDPI)
  if tem_imgui("GetMainViewport") and tem_imgui("Viewport_GetWorkPos") and tem_imgui("Viewport_GetWorkSize") then
    local okv, vp = pcall(ImGui.GetMainViewport, ctx)
    if okv and vp then
      local x, y = ImGui.Viewport_GetWorkPos(vp)
      local w, hmon = ImGui.Viewport_GetWorkSize(vp)
      -- Só aceita se for claramente uma tela (não a própria janela flutuante)
      local ww, wh = 0, 0
      pcall(function() ww, wh = ImGui.GetWindowSize(ctx) end)
      if w and hmon and (w >= 640 and hmon >= 400) and (w > (ww or 0) + 40 or hmon > (wh or 0) + 40 or ww < 50) then
        considerar(x or 0, y or 0, w, hmon)
      end
      if tem_imgui("Viewport_GetPos") and tem_imgui("Viewport_GetSize") then
        local px, py = ImGui.Viewport_GetPos(vp)
        local sw, sh = ImGui.Viewport_GetSize(vp)
        if sw and sh and (sw > (ww or 0) + 40 or sh > (wh or 0) + 40 or ww < 50) then
          -- tela cheia; se Work* já entrou, esta só entra se for maior
          considerar(px or 0, py or 0, sw, sh)
        end
      end
    end
  end

  -- 2) js_ReaScriptAPI: área útil do monitor sob um ponto da janela
  local wx, wy, ww, wh = 80, 80, 800, 600
  pcall(function()
    if ctx then
      wx, wy = ImGui.GetWindowPos(ctx)
      ww, wh = ImGui.GetWindowSize(ctx)
    end
  end)
  local hwnd = hwnd_painel()
  if hwnd then
    local l, t, rgt, bt, cocoa = js_rect(hwnd)
    if l then
      local jw, jh = js_rect_tamanho(l, t, rgt, bt, cocoa)
      if jw >= 10 then ww = jw end
      if jh >= 10 then wh = jh end
      if not cocoa then wx, wy = l, t or wy end
    end
  end
  local function tentar_js_viewport(x1, y1, x2, y2)
    if not r.JS_Window_GetViewportFromRect then return end
    local okj, a1, a2, a3, a4, a5 = pcall(r.JS_Window_GetViewportFromRect, x1, y1, x2, y2, true)
    if not okj then return end
    local l, tp, rgt, bt
    if type(a1) == "boolean" then
      l, tp, rgt, bt = a2, a3, a4, a5
    else
      l, tp, rgt, bt = a1, a2, a3, a4
    end
    local a, b, c, d = ltrb(l, tp, rgt, bt)
    if a then considerar(a, b, c, d) end
  end
  tentar_js_viewport(wx, wy, wx + ww, wy + wh)
  -- no Mac, tenta também o canto da tela primária (coordenadas Cocoa e ImGui)
  if MT.EH_MAC then
    tentar_js_viewport(0, 0, 80, 80)
    tentar_js_viewport(0, 600, 80, 680)
  else
    tentar_js_viewport(10, 10, 80, 80)
  end

  local x, y, w, h
  if melhor then
    x, y, w, h = melhor[1], melhor[2], melhor[3], melhor[4]
  else
    -- último recurso: não inventa 1920x1080 (estoura TV/notebook)
    x, y, w, h = 0, MT.EH_MAC and 28 or 0, math.max(ww or 0, 1280), math.max(wh or 0, 720)
  end
  mon_cache = { t = agora, x = x, y = y, w = w, h = h }
  return x, y, w, h
end

-- Tamanho/posição padrão que CABE na área útil. Em tela grande (ex.: 1920x1080
-- no Windows) continua 1360x820. Em TV/notebook/Retina menor, encolhe e centra.
local function geom_padrao()
  local x, y, w, h = area_monitor()
  local mx = (w < 1100) and 16 or 40
  local my = (h < 800) and 16 or 24
  local dw = math.min(1360, math.max(640, w - mx * 2))
  local dh = math.min(820, math.max(480, h - my * 2))
  local dx = x + math.max(0, math.floor((w - dw) / 2))
  local dy = y + math.max(0, math.floor((h - dh) / 2))
  return { x = dx, y = dy, w = dw, h = dh }
end

-- Encaixa a geometria na área útil (não fica gigante, minúscula nem fora).
-- Devolve a geom e um boolean dizendo se precisou ajustar.
local function encaixar_geom(g)
  local x, y, w, h = area_monitor()
  local gg = { x = tonumber(g and g.x) or x, y = tonumber(g and g.y) or y,
               w = tonumber(g and g.w) or w, h = tonumber(g and g.h) or h }
  local minw = math.min(1200, math.max(400, w - 24))
  local minh = math.min(600, math.max(220, h - 24))
  local nw = math.max(minw, math.min(gg.w, w))
  local nh = math.max(minh, math.min(gg.h, h))
  -- se a tela é menor que o mínimo "ideal", usa a tela inteira (com folga mínima)
  if w < 900 then nw = math.max(400, w - 8) end
  if h < 620 then nh = math.max(220, h - 8) end
  local nx = math.max(x, math.min(gg.x, x + w - nw))
  local ny = math.max(y, math.min(gg.y, y + h - nh))
  local mudou = math.abs(nx - gg.x) >= 8 or math.abs(ny - gg.y) >= 8
             or math.abs(nw - gg.w) >= 8 or math.abs(nh - gg.h) >= 8
  return { x = nx, y = ny, w = nw, h = nh }, mudou
end

local function limites_janela()
  local _, _, w, h = area_monitor()
  local minw = math.min((janela._min_tmp and 900) or 1200, math.max(400, w - 24))
  local minh = math.min(600, math.max(220, h - 24))
  return minw, minh, math.max(minw, w), math.max(minh, h)
end

local function guardar_geom()
  local x, y = ImGui.GetWindowPos(ctx)
  local w, h = ImGui.GetWindowSize(ctx)
  if not (w and h and w > 200 and h > 80) then return end
  if janela.minimizado then return end
  janela.prev = { x = x, y = y, w = w, h = h }
  MT.set("JANELA_X", string.format("%.0f", x))
  MT.set("JANELA_Y", string.format("%.0f", y))
  MT.set("JANELA_W", string.format("%.0f", w))
  MT.set("JANELA_H", string.format("%.0f", h))
end

local function geom_salva()
  if janela.prev and janela.prev.w and janela.prev.w > 0 then
    return encaixar_geom(janela.prev)
  end
  local x, y = tonumber(MT.get("JANELA_X", "")), tonumber(MT.get("JANELA_Y", ""))
  local w, h = tonumber(MT.get("JANELA_W", "")), tonumber(MT.get("JANELA_H", ""))
  if w and h and w > 400 and h > 200 then
    return encaixar_geom({ x = x or 80, y = y or 80, w = w, h = h })
  end
  return geom_padrao()
end

local function pedir_geom(g)
  janela.pedido = { x = g.x, y = g.y, w = g.w, h = g.h }
end

local aplicar_depois = nil

local function aplicar_pedido()
  local p = janela.pedido
  if not p then return end
  janela.pedido = nil
  ImGui.SetNextWindowPos(ctx, p.x, p.y, ImGui.Cond_Always)
  ImGui.SetNextWindowSize(ctx, p.w, p.h, ImGui.Cond_Always)
  aplicar_depois = p
end

local function aplicar_depois_do_begin()
  local p = aplicar_depois
  if not p then return end
  aplicar_depois = nil
  pcall(ImGui.SetWindowPos, ctx, p.x, p.y, ImGui.Cond_Always)
  pcall(ImGui.SetWindowSize, ctx, p.w, p.h, ImGui.Cond_Always)
  -- No Mac, JS_Window_Move/Resize usa coordenadas Cocoa (Y invertido) e, em
  -- Retina, pode estar em pixels (não em pontos do ImGui). Mexer aqui
  -- empurrava a janela para fora da tela. Só no Windows o JS ajuda.
  if not MT.EH_MAC then
    local h = hwnd_painel()
    if h then
      if r.JS_Window_Resize then pcall(r.JS_Window_Resize, h, math.floor(p.w + 0.5), math.floor(p.h + 0.5)) end
      if r.JS_Window_Move then pcall(r.JS_Window_Move, h, math.floor(p.x + 0.5), math.floor(p.y + 0.5)) end
    end
  end
end

local function alternar_maximizar()
  if janela.minimizado then
    janela.minimizado = false
  end
  if janela.maximizado then
    pedir_geom(geom_salva())
    janela.maximizado = false
  else
    guardar_geom()
    local x, y, w, h = area_monitor()
    pedir_geom({ x = x, y = y, w = w, h = h })
    janela.maximizado = true
  end
end

local function minimizar_painel()
  -- Recolhe até a barra compacta (transporte + restaurar). Não usa
  -- JS_Window_Show("MINIMIZE"): em janela ImGui o pcall "dá certo"
  -- sem minimizar, e o return abortava este fallback — o botão
  -- parecia morto.
  if janela.minimizado then return end
  guardar_geom()
  janela.minimizado = true
  local x, y = ImGui.GetWindowPos(ctx)
  pedir_geom({ x = x, y = y, w = 620, h = COMPACT_H })
end

local function restaurar_de_compacto()
  if not janela.minimizado then return end
  janela.minimizado = false
  if janela.maximizado then
    local x, y, w, h = area_monitor()
    pedir_geom({ x = x, y = y, w = w, h = h })
  else
    pedir_geom(geom_salva())
  end
end

-- botão da barra de título (Minimizar, Maximizar/Restaurar, Fechar)
local function botao_titulo(id, x, y, w, h, tipo, fechar)
  local clicou, passando, segurando = area(id, x, y, w, h)
  local fundo
  if fechar then
    fundo = passando and 0xE81123FF or 0x00000000
  else
    fundo = (passando or segurando) and 0xFFFFFF22 or 0x00000000
  end
  if (fundo & 255) > 0 then
    ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, fundo)
  end
  local cor = (fechar and passando) and 0xFFFFFFFF or C.texto
  local cx, cy, s = x + w / 2, y + h / 2, 5
  if tipo == "min" then
    ImGui.DrawList_AddRectFilled(dl, cx - 5, cy, cx + 5, cy + 2, cor, 0)
  elseif tipo == "max" then
    ImGui.DrawList_AddRect(dl, cx - 5, cy - 5, cx + 5, cy + 5, cor, 0, 0, 1.6)
  elseif tipo == "rest" then
    ImGui.DrawList_AddRect(dl, cx - 3, cy - 6, cx + 6, cy + 3, cor, 0, 0, 1.4)
    ImGui.DrawList_AddRectFilled(dl, cx - 6, cy - 3, cx + 3, cy + 6, C.fundo)
    ImGui.DrawList_AddRect(dl, cx - 6, cy - 3, cx + 3, cy + 6, cor, 0, 0, 1.6)
  elseif tipo == "fechar" then
    ImGui.DrawList_AddLine(dl, cx - 5, cy - 5, cx + 5, cy + 5, cor, 1.6)
    ImGui.DrawList_AddLine(dl, cx + 5, cy - 5, cx - 5, cy + 5, cor, 1.6)
  end
  return clicou, passando
end

-- devolve fechar=true se o usuário clicou em Fechar
local function desenhar_barra_titulo(fechar_out)
  dl = ImGui.GetWindowDrawList(ctx)
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww, wh = ImGui.GetWindowSize(ctx)
  local h = janela.minimizado and COMPACT_H or TITULO_H
  local topo = DRAW_ROUND_TOP
  if not topo then topo = 0 end
  ImGui.DrawList_AddRectFilled(dl, wx, wy, wx + ww, wy + h, 0x0A0C10FF, 8, topo)
  ImGui.DrawList_AddLine(dl, wx, wy + h - 1, wx + ww, wy + h - 1, C.borda, 1)

  local bw = 46
  local x_fechar = wx + ww - bw
  local x_max = x_fechar - bw
  local x_min = x_max - bw

  -- atualização disponível: aviso discreto na barra de título (clique = atualizar)
  local upd_txt, upd_x, upd_w = nil, nil, 0
  if not janela.minimizado and MT.atualizacao_estado then
    local st = MT.atualizacao_estado()
    local rem = MT.atualizacao_disponivel()
    if st and st.ocupado and st.fase and st.fase ~= "Procurando..." then
      upd_txt = "Atualizando: " .. st.fase .. (st.progresso and (" " .. st.progresso) or "")
    elseif rem then
      upd_txt = "Atualização disponível — Atualizar"
    end
    if upd_txt then
      com_fonte(F.peq or F.base, function() upd_w = math.floor((ImGui.CalcTextSize(ctx, upd_txt)) + 24) end)
      upd_x = x_min - upd_w - 10
      if upd_x < wx + 160 then upd_txt, upd_x = nil, nil end
    end
  end

  local nome = titulo_janela()
  local corte_titulo = (upd_x or x_min) - wx - 16
  if janela.minimizado then
    local ok_e, e = pcall(MT.estado)
    if ok_e and e and e.musica then
      nome = nome .. "   ·   " .. (e.musica.nome or "")
    end
    -- reserva espaço do transporte compacto à esquerda de restaurar/fechar
    corte_titulo = (x_max - (28 * 4 + 3 * 3 + 10)) - wx - 16
  end
  com_fonte(F.peq or F.base, function()
    ImGui.DrawList_AddText(dl, wx + 12, wy + math.floor((h - 14) / 2), C.texto, cortar(nome, math.max(40, corte_titulo)))
  end)

  -- área de arrastar (menos os três botões)
  local larg_arrasto = math.max(8, (upd_x or x_min) - wx)
  ImGui.SetCursorScreenPos(ctx, wx, wy)
  ImGui.InvisibleButton(ctx, "##titulo_arrasto", larg_arrasto, h)
  local sobre = ImGui.IsItemHovered(ctx)
  local ativo = ImGui.IsItemActive(ctx)
  if sobre and ImGui.IsMouseDoubleClicked(ctx, 0) and not janela.minimizado then
    alternar_maximizar()
  elseif janela.minimizado and sobre and ImGui.IsMouseDoubleClicked(ctx, 0) then
    restaurar_de_compacto()
  elseif ativo then
    -- se estiver maximizado, restaura e acompanha o mouse (como no Windows)
    if janela.maximizado and not janela.arrastando then
      local mx, my = ImGui.GetMousePos(ctx)
      local g = geom_salva()
      local frac = 0.5
      if g.w > 1 then frac = math.max(0.05, math.min(0.85, (mx - wx) / math.max(ww, 1))) end
      local nx = mx - g.w * frac
      local ny = wy
      janela.maximizado = false
      ImGui.SetWindowPos(ctx, nx, ny, ImGui.Cond_Always)
      ImGui.SetWindowSize(ctx, g.w, g.h, ImGui.Cond_Always)
      wx, wy = nx, ny
    end
    janela.arrastando = true
    local dx, dy = ImGui.GetMouseDelta(ctx)
    if dx ~= 0 or dy ~= 0 then
      local x, y = ImGui.GetWindowPos(ctx)
      ImGui.SetWindowPos(ctx, x + dx, y + dy, ImGui.Cond_Always)
    end
  else
    janela.arrastando = false
  end

  if upd_txt and upd_x then
    local ph = h - 10
    local py = wy + 5
    local clicou, passando = area("##upd_aviso", upd_x, py, upd_w, ph)
    local ocupado = upd_txt:sub(1, 11) == "Atualizando"
    local fundo = ocupado and 0x2A3140FF or (passando and 0x2BA866FF or 0x1E7A46FF)
    ImGui.DrawList_AddRectFilled(dl, upd_x, py + 1, upd_x + upd_w, py + ph + 1, 0x00000066, ph / 2)
    ImGui.DrawList_AddRectFilled(dl, upd_x, py, upd_x + upd_w, py + ph, fundo, ph / 2)
    ImGui.DrawList_AddRect(dl, upd_x, py, upd_x + upd_w, py + ph, 0xFFFFFF22, ph / 2, 0, 1)
    com_fonte(F.peq or F.base, function()
      local _, th = ImGui.CalcTextSize(ctx, upd_txt)
      ImGui.DrawList_AddText(dl, upd_x + 12, py + math.floor((ph - th) / 2), 0xFFFFFFFF, upd_txt)
    end)
    if passando and not ocupado then
      local st = MT.atualizacao_estado()
      local notas = st and st.notas or ""
      ImGui.SetTooltip(ctx, "Nova build do Mik Seifador v" .. MT.VERSAO .. " (build " .. tostring(MT.atualizacao_disponivel() or "?") ..
        "; a sua: " .. tostring(MT.build()) .. ")" .. (notas ~= "" and ("\n" .. notas) or "") ..
        "\nClique para atualizar: baixa só o que mudou, faz backup e recarrega o painel.")
    end
    if clicou and not ocupado then depois(function() MT.atualizar_agora() end) end
  end

  -- barra compacta: transporte à esquerda dos botões restaurar/fechar
  if janela.minimizado then
    local ok_e, e = pcall(MT.estado)
    if not ok_e then e = { tocando = false } end
    local tw, gap = 28, 3
    local bloco = tw * 4 + gap * 3 + 10
    local tx = x_max - bloco
    if tx < wx + 90 then tx = wx + 90 end
    local function tbtn(id, x, tipo, acao)
      local clicou, passando = area(id, x, wy + (h - tw) / 2, tw, tw)
      local cor = passando and C.acento or C.texto
      local cx, cy, s = x + tw / 2, wy + h / 2, 8
      if tipo == "play" then
        if e.tocando then ICONE.pause(cx, cy, s, cor) else ICONE.play(cx + 1, cy, s, cor) end
      elseif tipo == "anterior" then ICONE.anterior(cx, cy, s, cor)
      elseif tipo == "proxima" then ICONE.proxima(cx, cy, s, cor)
      elseif tipo == "stop" then ICONE.stop(cx, cy, s, cor)
      end
      if clicou and acao then acao() end
      return x + tw + gap
    end
    tx = tbtn("##c_ant", tx, "anterior", MT.musica_anterior)
    tx = tbtn("##c_play", tx, "play", MT.play_pause)
    tx = tbtn("##c_prox", tx, "proxima", MT.proxima_musica)
    tbtn("##c_stop", tx, "stop", MT.parar)
  end

  local fechar = false
  if not janela.minimizado then
    local c, p = botao_titulo("##tit_min", x_min, wy, bw, h, "min", false)
    if p then ImGui.SetTooltip(ctx, "Minimizar") end
    if c then minimizar_painel() end
    local tipo = janela.maximizado and "rest" or "max"
    c, p = botao_titulo("##tit_max", x_max, wy, bw, h, tipo, false)
    if p then ImGui.SetTooltip(ctx, janela.maximizado and "Restaurar" or "Maximizar") end
    if c then alternar_maximizar() end
  else
    local c, p = botao_titulo("##tit_rest", x_max, wy, bw, h, "rest", false)
    if p then ImGui.SetTooltip(ctx, "Restaurar") end
    if c then restaurar_de_compacto() end
  end
  local c, p = botao_titulo("##tit_fechar", x_fechar, wy, bw, h, "fechar", true)
  if p then ImGui.SetTooltip(ctx, "Fechar") end
  if c then fechar = true end

  if not janela.minimizado then
    -- empurra o conteúdo para baixo da barra
    ImGui.SetCursorScreenPos(ctx, wx + 14, wy + TITULO_H + 8)
    imgui_dummy()
  end
  return fechar
end

-- SPLASH INÍCIO --------------------------------------------------------------
-- v1.8: capa animada ao abrir (logo Mik Seifador desenhada por código, sem imagem)
local CAPA = { DUR = 2.6, SAIDA = 0.45 }
do
local SPLASH_DUR, SPLASH_SAIDA = CAPA.DUR, CAPA.SAIDA
local spl_alfa = 1
local function sa(c) return com_alfa(c, (c & 255) * spl_alfa) end
local function suave(t) t = math.max(0, math.min(1, t)); return 1 - (1 - t) ^ 3 end
local function volta(t) -- ease-out com leve "passada" (botão do fader assentando)
  t = math.max(0, math.min(1, t)); local c1, c3 = 1.70158, 2.70158
  return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
local function fase(t, a, b) return math.max(0, math.min(1, (t - a) / (b - a))) end
local function segs(rr) return math.max(32, math.min(256, math.floor(rr * 1.6))) end
local function circ(cx, cy, rr, c) ImGui.DrawList_AddCircleFilled(dl, cx, cy, rr, sa(c), segs(rr)) end
local function disco(cx, cy, r1, r2, c1, c2, passos, dy)
  -- passos de acordo com a largura do degradê: sem "faixas" visíveis mesmo em 4K
  passos = math.max(passos or 6, math.min(64, math.floor(math.abs(r1 - r2) / 1.2)))
  for k = 0, passos do
    local t = k / passos
    circ(cx, cy + (dy or 0) * t, r1 + (r2 - r1) * t, mistura(c1, c2, t))
  end
end
local function ret(x1, y1, x2, y2, c, rr) ImGui.DrawList_AddRectFilled(dl, x1, y1, x2, y2, sa(c), rr or 0) end
local function grad(x1, y1, x2, y2, c1, c2) degrade_v(x1, y1, x2, y2, sa(c1), sa(c2)) end
local function linha(x1, y1, x2, y2, c, e) ImGui.DrawList_AddLine(dl, x1, y1, x2, y2, sa(c), e or 1) end
local TEM_CLIP = tem_imgui("DrawList_PushClipRect") and tem_imgui("DrawList_PopClipRect")

-- onda (sinal de áudio) que atravessa os faders: forma fixa, determinística
local function onda_y(u) -- u de -1 a 1
  local env = (1 - u * u) ^ 1.3
  return env * (0.62 * math.sin(u * 13.0) + 0.38 * math.sin(u * 31.0 + 0.7)) * (0.75 + 0.25 * math.cos(u * 5))
end

-- emblema: disco metálico com 3 faders e a onda verde passando
local function desenhar_emblema(cx, cy, R, t, pulso)
  local a_ent = suave(fase(t, 0.0, 0.55))
  local esc = 0.72 + 0.28 * a_ent
  local Rr = R * esc
  -- halo
  for k = 16, 1, -1 do circ(cx, cy, Rr * (1 + 0.022 * k), com_alfa(0x2EC4B6FF, (4 + 3 * pulso) * a_ent * (17 - k) / 16)) end
  -- sombra
  circ(cx + Rr * 0.03, cy + Rr * 0.07, Rr * 1.02, com_alfa(0x000000FF, 150 * a_ent))
  -- aro metálico e miolo escuro
  disco(cx, cy, Rr, Rr * 0.90, 0x4C5257FF, 0xDADDE0FF, 7, -Rr * 0.03)
  ImGui.DrawList_AddCircle(dl, cx, cy - 1, Rr * 0.985, sa(0xFFFFFF40), segs(Rr), math.max(1.2, Rr / 90))
  disco(cx, cy, Rr * 0.90, Rr * 0.30, 0x0A0D0FFF, 0x1F262AFF, 8, -Rr * 0.12)
  ImGui.DrawList_AddCircle(dl, cx, cy, Rr * 0.84, sa(com_alfa(0x2EC4B6FF, 90 + 60 * pulso)), segs(Rr), math.max(1.5, Rr / 70))
  -- 3 fendas de fader
  local xs = { -0.40, 0, 0.40 }
  local alvo = { 0.20, -0.30, 0.04 }
  for i, fx in ipairs(xs) do
    local x0 = cx + fx * Rr
    ret(x0 - Rr * 0.035, cy - Rr * 0.52, x0 + Rr * 0.035, cy + Rr * 0.52, 0x000000FF, Rr * 0.03)
    linha(x0 + Rr * 0.04, cy - Rr * 0.5, x0 + Rr * 0.04, cy + Rr * 0.52, 0xFFFFFF22, math.max(1, Rr / 100))
    for k = -4, 4 do linha(x0 - Rr * 0.12, cy + k * Rr * 0.115, x0 - Rr * 0.075, cy + k * Rr * 0.115, 0x8A9096A0, math.max(1, Rr / 100)) end
  end
  -- onda desenhando da esquerda para a direita (com brilho)
  local p = suave(fase(t, 0.15, 1.15))
  if p > 0 then
    local N = math.max(90, math.min(420, math.floor(Rr * 1.4)))   -- mais pontos em telas grandes
    local nk = math.floor(N * p)
    local pts = {}
    for k = 0, nk do
      local u = -1 + 2 * k / N
      pts[#pts + 1] = cx + u * Rr * 0.80
      pts[#pts + 1] = cy - onda_y(u) * Rr * 0.34
    end
    local ult = { pts[#pts - 1], pts[#pts] }
    -- brilho: polilinha inteira (sem "contas" nas emendas); sem ela, segmentos mais fracos
    local poli = tem_imgui("DrawList_AddPolyline") and r.new_array and #pts >= 4
    for camada = 1, 2 do
      local esp = ({ Rr * 0.13, Rr * 0.07 })[camada]
      local al = ({ 0x22, 0x55 })[camada]
      local cor_meio = mistura(0x2EC4B6FF, 0x38F98CFF, 0.5)
      if poli then
        local ok = pcall(function()
          local arr = r.new_array(pts)
          ImGui.DrawList_AddPolyline(dl, arr, sa(com_alfa(cor_meio, al)), 0, esp)
        end)
        if not ok then poli = false end
      end
      if not poli then
        for k = 3, #pts - 1, 2 do linha(pts[k - 2], pts[k - 1], pts[k], pts[k + 1], com_alfa(cor_meio, al * 0.45), esp) end
      end
    end
    -- traço principal com degradê verde-água -> verde
    for k = 3, #pts - 1, 2 do
      local u = (pts[k] - cx) / (Rr * 0.80)
      linha(pts[k - 2], pts[k - 1], pts[k], pts[k + 1], mistura(0x2EC4B6FF, 0x38F98CFF, (u + 1) / 2), Rr * 0.032)
    end
    if p < 1 and ult then circ(ult[1], ult[2], Rr * 0.05, 0xE8FFF4FF); circ(ult[1], ult[2], Rr * 0.11, 0x38F98C40) end
  end
  -- botões dos faders assentando
  for i, fx in ipairs(xs) do
    local q = volta(fase(t, 0.45 + i * 0.12, 1.05 + i * 0.12))
    local y0 = cy + Rr * 0.62
    local yc = y0 + (alvo[i] * Rr - Rr * 0.62) * q
    if fase(t, 0.45 + i * 0.12, 0.6 + i * 0.12) > 0 then
      local x0 = cx + fx * Rr
      local cw, ch = Rr * 0.30, Rr * 0.17
      ret(x0 - cw / 2 + 1, yc - ch / 2 + Rr * 0.04, x0 + cw / 2 + 2, yc + ch / 2 + Rr * 0.05, 0x00000090, Rr * 0.03)
      grad(x0 - cw / 2, yc - ch / 2, x0 + cw / 2, yc, 0xF4F6F8FF, 0xA4AAB0FF)
      grad(x0 - cw / 2, yc, x0 + cw / 2, yc + ch / 2, 0xC9CDD1FF, 0x6E747AFF)
      linha(x0 - cw / 2, yc + 0.5, x0 + cw / 2, yc + 0.5, 0x15181BFF, math.max(1.5, Rr * 0.02))
      linha(x0 - cw / 2 + 1, yc - ch / 2 + 0.5, x0 + cw / 2 - 1, yc - ch / 2 + 0.5, 0xFFFFFFB0, math.max(1, Rr / 100))
    end
  end
end

-- texto da capa em qualidade máxima: com DrawList_AddTextEx usa fontes grandes (rasterizadas
-- em alta resolução) reduzidas para o tamanho da janela; sem ela, cai na fonte fixa
local TEM_EX = tem_imgui("DrawList_AddTextEx")
local ESC = 1
local FX = { capa_g = { "capa_gx", 64 }, capa_m = { "capa_mx", 20 }, capa_p = { "capa_px", 14 } }
local function usa_ex(nome) return TEM_EX and F[FX[nome][1]] ~= nil and ESC ~= 1 end
local function t_tam(nome, txt)
  local w, h = com_fonte(F[nome], function() return texto_tam(txt) end)
  if usa_ex(nome) then return w * ESC, h * ESC end
  return w, h
end
local function t_desenha(nome, x, y, cor, txt)
  if usa_ex(nome) then
    ImGui.DrawList_AddTextEx(dl, F[FX[nome][1]], FX[nome][2] * ESC, x, y, cor, txt)
  else
    com_fonte(F[nome], function() ImGui.DrawList_AddText(dl, x, y, cor, txt) end)
  end
end

-- texto metálico: sombra, brilho, base escura, metade de cima clara (recorte) e faixa de brilho passando
local function texto_metal(x, y, txt, nome, brilho_x, a)
  local tw, th = t_tam(nome, txt)
  local e = math.max(1, ESC)
  t_desenha(nome, x + 1 * e, y + 3 * e, sa(com_alfa(0x000000FF, 200 * a)), txt)
  for _, o in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
    t_desenha(nome, x + o[1] * 2 * e, y + o[2] * 2 * e, sa(com_alfa(0x2EC4B6FF, 26 * a)), txt)
  end
  t_desenha(nome, x, y, sa(com_alfa(0x8C9297FF, 255 * a)), txt)
  if TEM_CLIP then
    ImGui.DrawList_PushClipRect(dl, x - 4, y, x + tw + 4, y + th * 0.52, true)
    t_desenha(nome, x, y, sa(com_alfa(0xEEF1F3FF, 255 * a)), txt)
    ImGui.DrawList_PopClipRect(dl)
    ImGui.DrawList_PushClipRect(dl, x - 4, y + th * 0.50, x + tw + 4, y + th * 0.555, true)
    t_desenha(nome, x, y, sa(com_alfa(0x5C6267FF, 255 * a)), txt)
    ImGui.DrawList_PopClipRect(dl)
    if brilho_x then
      for k = 1, 3 do
        local lw = ({ 46, 26, 10 })[k] * e
        ImGui.DrawList_PushClipRect(dl, brilho_x - lw, y, brilho_x + lw, y + th, true)
        t_desenha(nome, x, y, sa(com_alfa(0xE6FFF4FF, ({ 70, 110, 200 })[k] * a)), txt)
        ImGui.DrawList_PopClipRect(dl)
      end
    end
  else
    t_desenha(nome, x, y - 1, sa(com_alfa(0xDDE1E4FF, 255 * a)), txt)
  end
  return tw, th
end

-- quadro da capa: x,y,w,h = área; t = segundos desde a abertura; alfa = transparência geral.
-- Tudo é calculado pelo tempo (não por quadro): mesmo se o REAPER pular quadros a animação segue certa.
function CAPA.desenhar(x, y, w, h, t, alfa)
  spl_alfa = alfa or 1
  local u = math.max(0.6, math.min(3.2, math.min(w / 1100, h / 640)))   -- acompanha tela cheia / 4K
  ESC = u
  local pulso = 0.5 + 0.5 * math.sin(t * 6.0)
  -- fundo com vinheta e grade bem fraca
  grad(x, y, x + w, y + h * 0.55, 0x15191CFF, 0x0C0F11FF)
  grad(x, y + h * 0.55, x + w, y + h, 0x0C0F11FF, 0x060708FF)
  local gp = 48 * u
  for gx = x + gp / 2, x + w, gp do linha(math.floor(gx) + 0.5, y, math.floor(gx) + 0.5, y + h, 0xFFFFFF05, 1) end
  for gy = y + gp / 2, y + h, gp do linha(x, math.floor(gy) + 0.5, x + w, math.floor(gy) + 0.5, 0xFFFFFF05, 1) end
  -- medidores pulsando no rodapé
  local passo = 14 * u
  local nb = math.floor(w / passo)
  local base = y + h - 6 * u
  local seg_h = 5 * u
  for i = 0, nb - 1 do
    local v = 0.5 + 0.5 * math.sin(i * 0.61 + t * 5.3) * math.cos(i * 0.23 - t * 2.1)
    v = v * (0.35 + 0.65 * math.abs(math.sin(i * 0.11 + t * 0.9))) * suave(fase(t, 0.1, 0.8))
    local bh = v * h * 0.11
    local bx = x + 4 * u + i * passo
    local seg = 0
    while seg * seg_h < bh do
      local yy = base - seg * seg_h
      local f = seg * seg_h / (h * 0.11)
      local cor = f > 0.85 and 0xF2281CFF or (f > 0.6 and 0xE6D51CFF or 0x23AD02FF)
      ret(bx, yy - 3 * u, bx + 10 * u, yy, com_alfa(cor, 48), u)
      seg = seg + 1
    end
  end
  -- emblema
  local R = 104 * u
  local cx, cy = x + w / 2, y + h * 0.36
  desenhar_emblema(cx, cy, R, t, pulso)
  -- nome
  local a_txt = suave(fase(t, 0.75, 1.35))
  if a_txt > 0 then
    local txt = "MIK SEIFADOR"
    local tw, th = t_tam("capa_g", txt)
    local abre = (1 - a_txt) * 40 * u
    local ty = cy + R + 26 * u + abre * 0.3
    local brilho = nil
    local s = fase(t, 1.35, 2.05)
    if s > 0 and s < 1 then brilho = x + (w - tw) / 2 - 60 * u + s * (tw + 120 * u) end
    texto_metal(x + (w - tw) / 2, ty, txt, "capa_g", brilho, a_txt)
    -- subtítulo + selo da versão
    local sub = "M U L T I T R A C K   A O   V I V O"
    local sw, sh = t_tam("capa_p", sub)
    local ver = "v" .. tostring(MT.VERSAO or "1.8")
    local vw, vh = t_tam("capa_m", ver)
    local pw, ph = 20 * u, 8 * u
    local total = sw + 18 * u + vw + pw
    local sx0 = x + (w - total) / 2
    local sy = ty + th + 10 * u
    t_desenha("capa_p", sx0, sy + (vh + ph - sh) / 2, sa(com_alfa(0x9AA3A8FF, 255 * a_txt)), sub)
    local q = volta(fase(t, 1.15, 1.55))
    if q > 0 then
      local bx1 = sx0 + sw + 18 * u
      local bcx, bcy = bx1 + (vw + pw) / 2, sy + (vh + ph) / 2
      local hw, hh = (vw + pw) / 2 * q, (vh + ph) / 2 * q
      for k = 3, 1, -1 do ret(bcx - hw - k * 2 * u, bcy - hh - k * 2 * u, bcx + hw + k * 2 * u, bcy + hh + k * 2 * u, com_alfa(0x38F98CFF, (14 + 10 * pulso) / k), (8 + k * 2) * u) end
      ret(bcx - hw, bcy - hh, bcx + hw, bcy + hh, 0x38F98CFF, 7 * u)
      grad(bcx - hw + 1, bcy - hh + 1, bcx + hw - 1, bcy, 0xFFFFFF50, 0xFFFFFF00)
      if q > 0.9 then t_desenha("capa_m", bcx - vw / 2, bcy - vh / 2, sa(0x06281AFF), ver) end
    end
  end
  -- carregando
  local prog = suave(fase(t, 0.05, SPLASH_DUR - SPLASH_SAIDA))
  local bw2 = 320 * u
  local bx = x + (w - bw2) / 2
  local by = y + h * 0.78
  local bh2 = 5 * u
  ret(bx - 1, by - 1, bx + bw2 + 1, by + bh2 + 1, 0x000000FF, 3 * u)
  ret(bx, by, bx + bw2, by + bh2, 0x1A1F22FF, 3 * u)
  if prog > 0 then
    ret(bx, by - 2 * u, bx + bw2 * prog, by + bh2 + 2 * u, com_alfa(0x38F98CFF, 30), 4 * u)
    degrade_h(bx, by, bx + bw2 * prog, by + bh2, sa(0x2EC4B6FF), sa(0x38F98CFF))
  end
  local msg = t < 0.9 and "Carregando músicas..." or (t < 1.7 and "Preparando o mixer..." or "Pronto!")
  local mw, mh = t_tam("capa_p", msg)
  t_desenha("capa_p", x + (w - mw) / 2, by + bh2 + 9 * u, sa(0x7D878CFF), msg)
  local dica = "clique ou aperte uma tecla para pular"
  local dw = t_tam("capa_p", dica)
  t_desenha("capa_p", x + (w - dw) / 2, by + bh2 + 15 * u + mh, sa(0x4A5357FF), dica)
end
end
-- SPLASH FIM -----------------------------------------------------------------

-- estado da capa (só na primeira abertura do painel nesta sessão do REAPER;
-- ExtState não persistente com a hora de início, sobrevive a relançar o
-- script / recarregar o mt_lib / terminar separação ou importação)
local capa = { t0 = nil, pular = nil, feita = MT.get("CAPA", "1") == "0"
  or (MT.capa_feita_na_sessao and MT.capa_feita_na_sessao()) or false }
if capa.feita and MT.marcar_capa_feita then pcall(MT.marcar_capa_feita) end
local TEM_FG = tem_imgui("GetForegroundDrawList")
local function capa_tecla()
  local ok, sim = pcall(function()
    for _, k in ipairs({ "Key_Escape", "Key_Space", "Key_Enter", "Key_KeypadEnter" }) do
      local cod = imgui_opcional(k, nil)
      if cod and ImGui.IsKeyPressed(ctx, cod, false) then return true end
    end
    if tem_imgui("GetInputQueueCharacter") then
      local okc, c = ImGui.GetInputQueueCharacter(ctx, 0)
      if okc and c and c ~= 0 then return true end
    end
    return false
  end)
  return ok and sim
end
-- devolve true enquanto a capa cobre o painel (aí não desenha o painel por baixo)
local function capa_quadro()
  if MT._rever_capa then MT._rever_capa = nil; capa.t0, capa.pular, capa.feita = nil, nil, false end
  if capa.feita then return false end
  local agora = r.time_precise()
  if not capa.t0 then capa.t0 = agora end
  local t = agora - capa.t0
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww, wh = ImGui.GetWindowSize(ctx)
  local x, y, w, h = wx, wy + TITULO_H, ww, wh - TITULO_H
  local inicio_saida = capa.pular or (CAPA.DUR - CAPA.SAIDA)
  if t >= inicio_saida + CAPA.SAIDA then
    capa.feita = true
    if MT.marcar_capa_feita then pcall(MT.marcar_capa_feita) end
    return false
  end
  local alfa = 1
  if t < 0.25 then alfa = t / 0.25 end
  if t > inicio_saida then alfa = 1 - (t - inicio_saida) / CAPA.SAIDA end
  local saindo = t > inicio_saida
  local dl_ant = dl
  if saindo and TEM_FG then
    desenhar()                                -- o painel já aparece por baixo, a capa some por cima
    dl = ImGui.GetForegroundDrawList(ctx)
  else
    dl = ImGui.GetWindowDrawList(ctx)
    ImGui.SetCursorScreenPos(ctx, x, y)
    if ImGui.InvisibleButton(ctx, "##capa_pular", math.max(1, w), math.max(1, h)) and not capa.pular then capa.pular = t end
  end
  if not capa.pular and not saindo and capa_tecla() then capa.pular = t end
  local ok, err = pcall(CAPA.desenhar, x, y, w, h, math.min(t, CAPA.DUR), math.max(0, math.min(1, alfa)))
  dl = dl_ant
  if not ok then
    capa.feita = true
    if MT.marcar_capa_feita then pcall(MT.marcar_capa_feita) end
  end
  return true   -- coberto pela capa (ou o painel já foi desenhado por baixo)
end

local function loop()
  for _, c in ipairs(cores_ok) do ImGui.PushStyleColor(ctx, c[1], c[2]) end
  for _, v in ipairs(vars_ok) do
    if v[3] then ImGui.PushStyleVar(ctx, v[1], v[2], v[3]) else ImGui.PushStyleVar(ctx, v[1], v[2]) end
  end
  if F.base then ImGui.PushFont(ctx, F.base) end

  -- comando de teste (ExtState), sem popup: min / max / rest
  do
    local cmd = r.GetExtState(MT.SEC, "JANELA_CMD") or ""
    if cmd ~= "" then
      r.SetExtState(MT.SEC, "JANELA_CMD", "", false)
      if cmd == "max" then alternar_maximizar()
      elseif cmd == "min" then minimizar_painel()
      elseif cmd == "rest" then
        if janela.minimizado then restaurar_de_compacto()
        elseif janela.maximizado then alternar_maximizar()
        end
      elseif cmd:sub(1, 2) == "w:" or cmd:sub(1, 2) == "W:" then
        local nw = tonumber(cmd:sub(3))
        if nw and nw >= 900 then
          local x, y = ImGui.GetWindowPos(ctx)
          local _, h = ImGui.GetWindowSize(ctx)
          janela._min_tmp = nw < 1200
          pedir_geom({ x = x, y = y, w = nw, h = math.max(h or 600, 600) })
        end
      elseif cmd:sub(1, 5) == "geom:" then
        local xs, ys, ws, hs = cmd:match("geom:([%-%d]+),([%-%d]+),(%d+),(%d+)")
        local nw, nh = tonumber(ws), tonumber(hs)
        if nw and nh and nw >= 900 and nh >= 200 then
          janela._min_tmp = nw < 1200
          pedir_geom({ x = tonumber(xs) or 0, y = tonumber(ys) or 0, w = nw, h = nh })
        end
      end
    end
  end
  -- Na 1ª abertura da sessão, aplica o tamanho padrão/salvo JÁ neste frame
  -- (antes do Begin). Assim o .ini do ImGui não reabre a barra compacta
  -- (620x44) quando o painel foi minimizado na sessão anterior, nem o
  -- 1360x820 antigo que estoura telas como a TV 1360x768.
  if not janela._abriu then
    janela._abriu = true
    local okg, g = pcall(function()
      local s = geom_salva()
      if s and tonumber(s.w) and tonumber(s.h) and s.w >= 800 and s.h >= 200 then
        return s
      end
      return geom_padrao()
    end)
    if okg and g then pedir_geom(g) end
  end
  aplicar_pedido()
  -- NÃO chamar SetNextWindowSize(..., FirstUseEver) no mesmo frame de um pedido:
  -- no ImGui a última chamada vence, e o FirstUseEver apagava o Cond_Always do
  -- maximizar (a janela ficava do mesmo tamanho, como se o botão não fizesse nada).
  if janela.minimizado then
    ImGui.SetNextWindowSizeConstraints(ctx, 320, COMPACT_H, 1100, COMPACT_H)
  elseif janela.maximizado then
    ImGui.SetNextWindowSizeConstraints(ctx, 400, 200, 10000, 10000)
  else
    -- FirstUseEver só quando NÃO há pedido neste frame (a última SetNext* vence).
    if not aplicar_depois then
      local g0 = geom_padrao()
      ImGui.SetNextWindowSize(ctx, g0.w, g0.h, ImGui.Cond_FirstUseEver)
      ImGui.SetNextWindowPos(ctx, g0.x, g0.y, ImGui.Cond_FirstUseEver)
    end
    local minw, minh, maxw, maxh = limites_janela()
    ImGui.SetNextWindowSizeConstraints(ctx, minw, minh, maxw, maxh)  -- mínimo cabe na tela; em tela grande segue 1200x600
  end

  local flags = FLAGS_JANELA
  if janela.minimizado then
    flags = flags | flag_janela("WindowFlags_NoResize")
  end
  local visivel, aberto = ImGui.Begin(ctx, titulo_janela() .. "###MultitrackAoVivo", true, flags)
  if visivel then aplicar_depois_do_begin() end
  -- Nas primeiras aberturas, se o tamanho salvo (ini/ExtState ou o antigo
  -- 1360x820) estourar a tela do Mac, encaixa na área útil. Não interfere
  -- depois que o usuário já ajustou e a janela cabe.
  if visivel and not janela.minimizado and not janela.maximizado and not janela.pedido then
    janela._aberturas = (janela._aberturas or 0) + 1
    if janela._aberturas <= 3 then
      local x, y = ImGui.GetWindowPos(ctx)
      local w, h = ImGui.GetWindowSize(ctx)
      local g, mudou = encaixar_geom({ x = x, y = y, w = w, h = h })
      if mudou then pedir_geom(g) end
    end
  end
  local pediu_fechar = false
  local ok, err = true, nil
  if visivel then
    ok, err = xpcall(function()
      pediu_fechar = desenhar_barra_titulo()
      if not janela.minimizado and not pediu_fechar then
        if not capa_quadro() then desenhar() end
      end
      desenhar_aviso_painel()
      dica_fim_frame()
    end, debug.traceback)
    -- Dummy antes do End: se um SetCursorScreenPos ficou por último (erro no meio
    -- do desenho, fechar, etc.), o ReaImGui 0.10 não derruba o script.
    pcall(function()
      local x, y = ImGui.GetWindowPos(ctx)
      local w, h = ImGui.GetWindowSize(ctx)
      local js = ""
      local hwnd = hwnd_painel()
      local l, t, rgt, bt = js_rect(hwnd)
      if l then
        js = string.format(" hwnd=%.0f,%.0f,%.0fx%.0f", l, t or 0, (rgt or l) - l, (bt or t or 0) - (t or 0))
      end
      r.SetExtState(MT.SEC, "JANELA_GEOM",
        string.format("%.0f,%.0f,%.0f,%.0f min=%s max=%s%s", x or 0, y or 0, w or 0, h or 0,
          janela.minimizado and "1" or "0", janela.maximizado and "1" or "0", js), false)
    end)
    pcall(ImGui.Dummy, ctx, 0, 0)
    pcall(ImGui.End, ctx)
  end
  if pediu_fechar then aberto = false end
  if not aberto then pcall(guardar_geom) end

  pcall(function()
    if F.base then ImGui.PopFont(ctx) end
    ImGui.PopStyleVar(ctx, #vars_ok)
    ImGui.PopStyleColor(ctx, #cores_ok)
  end)

  if not ok then
    pcall(function()
      if MT and MT.registrar_erro then MT.registrar_erro("painel", err) end
    end)
  end

  if pendente then
    local fn = pendente
    pendente = nil
    local okp, errp = xpcall(fn, debug.traceback)
    if not okp then
      pcall(function()
        if MT and MT.registrar_erro then MT.registrar_erro("painel-acao", errp) end
      end)
    end
  end
  if REM then pcall(REM.tick) end
  if MT.atualizador_tick then pcall(MT.atualizador_tick, avisar_painel) end
  pcall(r.SetExtState, MT.SEC, "PAINEL_HB", tostring(r.time_precise()), false)
  if aberto then r.defer(loop) end
end

r.defer(loop)
