-- Mik Seifador - CONTROLE PELO CELULAR (Mik Seifador Remoto) - v1.8
-- Criado por Miqueias Felix (2026)
--[[
  Ponte entre o painel/motor (Lua, dentro do REAPER) e a página do celular, que
  roda na INTERFACE WEB do próprio REAPER (Preferências > Control/OSC/web >
  Web browser interface). Não precisa de internet nem de app: só Wi-Fi local.

  ExtState (seção "MikSeifadorRemoto", não persistente):
    PING        o celular escreve um contador (~1 s) -> "tem alguém olhando"
    STATE       JSON do estado "lento" (setlist, seções, trilhas, opções)
    SEQ         número que muda quando o STATE muda
    FAST        JSON rápido (~12x/s): posição, play, seção, faders, medidores, avisos
    WAVE        forma de onda da música atual (texto compacto)
    BIBLIO      lista da biblioteca (quando o celular pede)
    C0..C31     fila de comandos do celular: "id|comando|arg1|arg2" (args em %XX)
    ACK         id do último comando executado
  Strings do JSON vão com % codificado (sem barra invertida) -> o celular usa
  decodeURIComponent; assim o escape da interface web do REAPER não atrapalha.

  O painel e o motor_ao_vivo chamam REM.tick(). Os dois podem rodar juntos:
  quem pegar o comando primeiro apaga o slot (o REAPER roda os scripts em fila,
  não há corrida), e o envio do estado é limitado por horário compartilhado.
]]
local r = reaper

return function(MT)
local R = {}
local SEC = "MikSeifadorRemoto"
R.SEC = SEC
R.PAGINA = "mikseifador.html"
R.PORTA_PADRAO = 8080
local N_SLOTS = 32
local SEP = package.config:sub(1, 1)
local SO_WIN = (r.GetOS() or ""):find("Win") ~= nil

-------------------------------------------------------------------------------
-- JSON compacto (strings com %XX no lugar de " \ % e controles)
-------------------------------------------------------------------------------
local ARR = {}
local function arr(t) return setmetatable(t or {}, ARR) end
R.arr = arr
local function esc(s)
  return (tostring(s):gsub('[%%"\\%c\127]', function(c) return string.format("%%%02X", c:byte()) end))
end
local function num(v)
  if v ~= v or v == math.huge or v == -math.huge then return "0" end
  if math.type and math.type(v) == "integer" then return tostring(v) end
  if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
  local s = string.format("%.3f", v):gsub(",", "."):gsub("0+$", ""):gsub("%.$", "")
  if s == "-0" then s = "0" end
  return s
end
local enc
enc = function(v)
  local t = type(v)
  if t == "nil" then return "null"
  elseif t == "boolean" then return v and "true" or "false"
  elseif t == "number" then return num(v)
  elseif t == "string" then return '"' .. esc(v) .. '"'
  elseif t == "table" then
    local partes = {}
    if getmetatable(v) == ARR or #v > 0 then
      for i = 1, #v do partes[i] = enc(v[i]) end
      return "[" .. table.concat(partes, ",") .. "]"
    end
    local chaves = {}
    for k in pairs(v) do chaves[#chaves + 1] = tostring(k) end
    table.sort(chaves)
    for _, k in ipairs(chaves) do partes[#partes + 1] = '"' .. esc(k) .. '":' .. enc(v[k]) end
    return "{" .. table.concat(partes, ",") .. "}"
  end
  return "null"
end
R.json = enc

local function url_dec(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
R.url_dec = url_dec

-------------------------------------------------------------------------------
-- utilidades
-------------------------------------------------------------------------------
local function hex_cor(c)
  if not c or c == 0 then return nil end
  local rr, gg, bb = r.ColorFromNative(math.floor(c) & 0xFFFFFF)
  return string.format("#%02x%02x%02x", rr, gg, bb)
end
local function cor_da_trilha(tr)
  local c = r.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR")
  if c and c ~= 0 then return hex_cor(c) end
  local pai = r.GetParentTrack(tr)
  if pai then
    local cp = r.GetMediaTrackInfo_Value(pai, "I_CUSTOMCOLOR")
    if cp and cp ~= 0 then return hex_cor(cp) end
  end
  return nil
end
-- mesma curva dos faders do painel (estilo Pro Tools, em mt_lib)
local function vol_para_pos(vol) return MT.fader_pos_ganho(vol) end
local function pos_para_vol(p)
  if p < 0 then p = 0 elseif p > 1 then p = 1 end
  return MT.fader_ganho(p)
end
R.vol_para_pos, R.pos_para_vol = vol_para_pos, pos_para_vol
local function pico_db(tr, ch)
  local v = r.Track_GetPeakInfo(tr, ch)
  if not v or v <= 0.0000001 then return -90 end
  local db = 20 * math.log(v, 10)
  if db < -90 then db = -90 end
  return math.floor(db * 10 + 0.5) / 10
end
local function hash(s)
  local h = 5381
  for i = 1, #s do h = ((h * 33) ~ s:byte(i)) & 0xFFFFFFFF end
  return string.format("%08x", h)
end
local function existe(p)
  local f = io.open(p, "rb")
  if f then f:close() return true end
  return false
end
local function ler(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end
local function gravar(p, d)
  local f = io.open(p, "wb")
  if not f then return false end
  f:write(d); f:close(); return true
end

-------------------------------------------------------------------------------
-- trilhas que aparecem no mixer (mesma ordem do painel)
-------------------------------------------------------------------------------
local function stems_da_banda()
  local lista = {}
  local banda = MT.achar_trilha(MT.CFG.NOME_BANDA)
  local nome_pad = MT.norm(MT.CFG.NOME_PAD)
  if not banda then return lista end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if tr ~= banda and MT.descende_de(tr, banda)
       and r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") <= 0
       and MT.norm(MT.nome_trilha(tr)) ~= nome_pad then
      lista[#lista + 1] = tr
    end
  end
  return lista
end
R.stems_da_banda = stems_da_banda

-- v1.8: só os stems com áudio na música atual (igual ao painel)
local function canais(m)
  local L = {}
  local stems = MT.trilhas_da_musica("remoto", stems_da_banda, m)
  for _, tr in ipairs(stems) do L[#L + 1] = { tr = tr, nome = MT.nome_trilha(tr), g = "s" } end
  local pad = MT.achar_trilha(MT.CFG.NOME_PAD)
  local guia = MT.achar_trilha(MT.CFG.NOME_GUIA)
  local click = MT.achar_trilha(MT.CFG.NOME_CLICK)
  if pad then L[#L + 1] = { tr = pad, nome = "PAD", g = "d" } end
  if guia then L[#L + 1] = { tr = guia, nome = "GUIA", g = "d" } end
  if click then L[#L + 1] = { tr = click, nome = "CLICK", g = "d" } end
  local fone = MT.achar_fone()
  if fone then
    for i = 0, r.CountTracks(0) - 1 do
      local tr = r.GetTrack(0, i)
      if r.GetParentTrack(tr) == fone and tr ~= click and tr ~= guia then
        local _, nm = r.GetTrackName(tr)
        L[#L + 1] = { tr = tr, nome = nm, g = "d" }
      end
    end
  end
  L[#L + 1] = { tr = r.GetMasterTrack(0), nome = "MASTER", g = "m", master = true }
  for _, c in ipairs(L) do
    c.id = c.master and "M" or r.GetTrackGUID(c.tr)
    c.cor = c.master and "#8ed8ec" or cor_da_trilha(c.tr)
  end
  return L
end

local function trilha_por_id(id)
  if id == "M" then return r.GetMasterTrack(0), true end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetTrackGUID(tr) == id then return tr, false end
  end
  return nil
end

-------------------------------------------------------------------------------
-- pasta da interface web do REAPER (reaper_www_root) e arquivos da página
-------------------------------------------------------------------------------
function R.www_root() return r.GetResourcePath() .. SEP .. "reaper_www_root" end
function R.fonte_web()
  local dir = debug.getinfo(1, "S").source:match("^@?(.*[\\/])") or ""
  return dir .. "remoto_web"
end

local function listar_rec(base, rel, out)
  out = out or {}
  local pasta = rel == "" and base or (base .. SEP .. rel)
  local i = 0
  while true do
    local f = r.EnumerateFiles(pasta, i)
    if not f then break end
    out[#out + 1] = rel == "" and f or (rel .. SEP .. f)
    i = i + 1
  end
  i = 0
  while true do
    local d = r.EnumerateSubdirectories(pasta, i)
    if not d then break end
    if d:sub(1, 1) ~= "." then listar_rec(base, rel == "" and d or (rel .. SEP .. d), out) end
    i = i + 1
  end
  return out
end

-- Copia remoto_web -> reaper_www_root (só o que mudou). Devolve qtd copiada, total, erro
function R.instalar_pagina()
  local orig, dest = R.fonte_web(), R.www_root()
  r.EnumerateFiles(orig, -1); r.EnumerateSubdirectories(orig, -1)   -- força reler as pastas
  local lista = listar_rec(orig, "")
  if #lista == 0 then return 0, 0, "arquivos da página não encontrados em " .. orig end
  local copiados = 0
  for _, rel in ipairs(lista) do
    if not rel:match("%.DS_Store$") then
      local a = ler(orig .. SEP .. rel)
      local destino = dest .. SEP .. rel
      if a and ler(destino) ~= a then
        local pasta = destino:match("^(.*)[\\/][^\\/]+$")
        if pasta then r.RecursiveCreateDirectory(pasta, 0) end
        if gravar(destino, a) then copiados = copiados + 1 end
      end
    end
  end
  return copiados, #lista, nil
end
function R.pagina_instalada() return existe(R.www_root() .. SEP .. R.PAGINA) end

-------------------------------------------------------------------------------
-- capas (copiadas para reaper_www_root/mikseifador/capas, o servidor do REAPER entrega)
-------------------------------------------------------------------------------
local EXT_IMG = { jpg = true, jpeg = true, png = true }
local capas = {}
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
      if nota > nota_melhor then melhor, nota_melhor = pasta .. SEP .. f, nota end
    end
    i = i + 1
  end
  return melhor
end
local function url_capa(m)
  local chave = string.format("%s|%.2f", m.nome, m.inicio)
  local c = capas[chave]
  if type(c) == "table" and c.url then return c.url end
  if type(c) == "number" then
    local agora = (r.time_precise and r.time_precise()) or 0
    if agora - c < 2.5 then return nil end
  elseif c == false then
    capas[chave] = (r.time_precise and r.time_precise()) or 0
    return nil
  end
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
  if not arq then
    capas[chave] = (r.time_precise and r.time_precise()) or 0
    return nil
  end
  local ext = (arq:match("%.(%w+)$") or "jpg"):lower()
  local nome = hash(arq) .. "." .. ext
  local pasta = R.www_root() .. SEP .. "mikseifador" .. SEP .. "capas"
  local destino = pasta .. SEP .. nome
  if not existe(destino) then
    r.RecursiveCreateDirectory(pasta, 0)
    local d = ler(arq)
    if not d or #d > 12 * 1024 * 1024 or not gravar(destino, d) then
      capas[chave] = (r.time_precise and r.time_precise()) or 0
      return nil
    end
  end
  local url = "mikseifador/capas/" .. nome
  capas[chave] = { url = url, arq = arq }
  return url
end

-------------------------------------------------------------------------------
-- forma de onda (mesmo cálculo do painel, 320 pontos, 0..63 em 1 caractere)
-------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local onda = { chave = nil, ok = false, t = 0, vezes = 0 }
local function calcular_onda(m, n)
  local dur = m.fim - m.inicio
  if dur <= 0 then return nil, true end
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
            soma[i1 + j - 1] = soma[i1 + j - 1] + math.max(math.abs(mx), math.abs(mn)) * vol
          end
        end
      end
    end
  end
  local ord = {}
  for k = 1, n do ord[k] = soma[k] end
  table.sort(ord)
  local ref = ord[math.max(1, math.floor(n * 0.985))]
  if not ref or ref <= 0 then ref = ord[n] or 0 end
  local t = {}
  for k = 1, n do
    local v = ref > 0 and math.min(1, soma[k] / ref) ^ 0.8 or 0
    local q = math.floor(v * 63 + 0.5)
    t[k] = B64:sub(q + 1, q + 1)
  end
  return table.concat(t), completo
end
local function atualizar_onda(m, agora)
  if not m then return nil end
  local chave = hash(string.format("%s|%.3f|%.3f", m.nome, m.inicio, m.fim))
  if onda.chave == chave and (onda.ok or onda.vezes > 15 or agora - onda.t < 2.0) then return chave end
  if onda.chave ~= chave then onda.vezes = 0 end
  local d, ok = calcular_onda(m, 320)
  onda.chave, onda.ok, onda.t, onda.vezes = chave, ok, agora, onda.vezes + 1
  local atual = r.GetExtState(SEC, "WAVE")
  local novo = enc({ k = chave, d = d or "" })
  if atual ~= novo then r.SetExtState(SEC, "WAVE", novo, false) end
  return chave
end

-------------------------------------------------------------------------------
-- avisos (o que aparece como dica no PC também aparece no celular)
-------------------------------------------------------------------------------
if not MT._aviso_remoto then
  local aviso0 = MT.aviso
  MT._aviso_remoto = true
  MT.aviso = function(txt)
    aviso0(txt)
    local n = (tonumber(r.GetExtState(SEC, "AV_N")) or 0) + 1
    r.SetExtState(SEC, "AV", tostring(txt or ""), false)
    r.SetExtState(SEC, "AV_N", tostring(n), false)
  end
end

-------------------------------------------------------------------------------
-- ESTADO -> celular
-------------------------------------------------------------------------------
local cache = { pads = nil, pads_t = 0, rot = nil, rot_t = 0, prog = nil, prog_t = 0, curva = nil }
local function curva()
  if cache.curva then return cache.curva end
  local c = arr()
  for i = 0, 100 do
    local db = MT.fader_db(i / 100)
    if db < -150 then db = -150 end
    c[#c + 1] = math.floor(db * 100 + 0.5) / 100
  end
  local esc_db = arr()
  for _, d in ipairs({ 12, 6, 0, -5, -10, -20, -40 }) do
    esc_db[#esc_db + 1] = arr({ d, math.floor(vol_para_pos(10 ^ (d / 20)) * 10000) / 10000 })
  end
  cache.curva = { c = c, e = esc_db }
  return cache.curva
end

function R.montar_estado(e, agora)
  e = e or MT.estado()
  agora = agora or r.time_precise()
  local m = e.musica
  local st = { v = MT.VERSAO }
  local mus = arr()
  for _, mu in ipairs(e.musicas or {}) do
    mus[#mus + 1] = { n = mu.n, nome = mu.nome, tom = MT.tom_soando(mu), cor = hex_cor(mu.cor),
      capa = url_capa(mu), ini = mu.inicio, fim = mu.fim }
  end
  st.mus = mus
  st.m = m and m.n or 0
  local secs = arr()
  for _, sc in ipairs(e.secoes or {}) do
    secs[#secs + 1] = { n = sc.n, nome = sc.nome, ini = sc.inicio, fim = sc.fim,
      cor = sc.virtual and "#7a7a8a" or (hex_cor(sc.cor) or string.format("#%02x%02x%02x", table.unpack(MT.COR_SECAO_PADRAO))),
      vt = sc.virtual and true or nil }
  end
  st.secs = secs
  st.tom = (m and e.tom) or nil
  st.tomo = (m and m.tom) or nil
  st.tr = e.transp or 0
  st.f = {
    AUTO = MT.flag("AUTO"), HOLD = MT.flag("HOLD"), LOOP = MT.flag("LOOP"),
    SOLO_CLICK = MT.flag("SOLO_CLICK"), REPETIR_CLICK = MT.flag("REPETIR_CLICK"), PAD = MT.flag("PAD"),
    suave = MT.salto_suave(), aa = MT.analise_auto(), sa = MT.separacao_auto(), mo = MT.mutar_original(),
    sr = (MT.separacao_rapida and MT.separacao_rapida()) or false,
  }
  st.modo = e.modo
  st.lrc = MT.get("LR_COM_CLICK", "0") == "1"
  if not cache.rot or agora - cache.rot_t > 2 then
    local ok, rot = pcall(MT.roteamento_efetivo); cache.rot = ok and rot or nil; cache.rot_t = agora
  end
  local ok_s, saida = pcall(MT.descrever_roteamento, cache.rot, e.modo)
  st.saida = ok_s and saida or ""
  st.motor = MT.motor_ativo()
  st.mi = MT.motor_instalado() and true or false
  st.minst = MT.motor_instalando() and true or false
  local chs = arr()
  for _, c in ipairs(canais(e.musica)) do chs[#chs + 1] = { id = c.id, nome = c.nome, cor = c.cor, g = c.g } end
  st.ch = chs
  if not cache.pads or agora - cache.pads_t > 5 then
    local ok, l = pcall(MT.listar_pacotes_pads)
    cache.pads = arr(ok and l or {}); cache.pads_t = agora
  end
  local pads = arr()
  local classico = MT.PACOTE_PAD_CLASSICO or "Pad clássico"
  local continuo = MT.PACOTE_PAD_CONTINUO or "Pad contínuo"
  local tem_cont = false
  for _, d in ipairs(cache.pads) do if d == continuo then tem_cont = true end end
  if tem_cont then pads[#pads + 1] = continuo end
  pads[#pads + 1] = classico
  for _, d in ipairs(cache.pads) do if d ~= continuo and d ~= classico and d ~= "Shimmer" then pads[#pads + 1] = d end end
  st.pads = pads
  st.trava = (MT.setlist_travado and MT.setlist_travado()) or false
  st.pac = MT.pacote_pads()
  local okp, dp = pcall(MT.descrever_pad, m)
  st.padd = okp and dp or ""
  st.cv = curva()
  return st
end

function R.montar_rapido(e, agora)
  local m = e.musica
  local f = { t = e.pos, pl = e.tocando and 1 or (e.pausado and 2 or 0),
    m = m and m.n or 0, s = e.secao and e.secao.n or 0, bpm = e.bpm or 0, rate = r.Master_GetPlayRate(0) or 1 }
  local num_, den = r.TimeMap_GetTimeSigAtTime(0, e.pos)
  f.sig = string.format("%d/%d", num_ or 4, den or 4)
  local ls, le = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
  f.ls, f.le = ls, le
  local chs = arr()
  for _, c in ipairs(canais(e.musica)) do
    local tr = c.tr
    local mudo
    if c.master then mudo = MT.master_mudo() else mudo = r.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 end
    local p = vol_para_pos(r.GetMediaTrackInfo_Value(tr, "D_VOL"))
    chs[#chs + 1] = arr({ c.id, math.floor(p * 10000) / 10000, pico_db(tr, 0), pico_db(tr, 1),
      mudo and 1 or 0, (not c.master and r.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0) and 1 or 0,
      math.floor(r.GetMediaTrackInfo_Value(tr, "D_PAN") * 100 + 0.5) / 100 })
  end
  f.ch = chs
  if agora - cache.prog_t > 0.25 then
    cache.prog_t = agora
    local ok, info = pcall(MT.progresso_trabalho or function() return nil end)
    cache.prog = nil
    if ok and info then
      cache.prog = { tipo = info.tipo, nome = info.nome, p = info.pronto and 1 or (tonumber(info.prog) or 0),
        pct = info.pct, eta = info.eta, fila = info.fila, ok = info.pronto and true or nil,
        frase = info.frase, et = (not info.pronto) and info.etapa or nil, rap = info.rapido and true or nil, can = (info.pode_cancelar and not info.pronto) and true or nil }
    end
  end
  f.pr = cache.prog
  f.av = arr({ tonumber(r.GetExtState(SEC, "AV_N")) or 0, r.GetExtState(SEC, "AV") })
  f.ack = r.GetExtState(SEC, "ACK")
  f.bl = tonumber(r.GetExtState(SEC, "BL_N")) or 0
  return f
end

-------------------------------------------------------------------------------
-- COMANDOS do celular -> mesmas funções dos botões do PC
-------------------------------------------------------------------------------
local function secoes_atuais()
  local e = MT.estado()
  return e, e.secoes or {}
end
local function pular_secao(sec) if sec then MT.ir_para_secao(sec) end end
local function loop_secao(e, sc)
  local loop_on = MT.flag("LOOP") or MT.flag("REPETIR_CLICK")
  local ls, le = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
  local em_loop = loop_on and math.abs(ls - sc.inicio) < 0.01 and math.abs(le - sc.fim) < 0.05
  local atual = e.secao and sc.n == e.secao.n
  if em_loop and MT.flag("LOOP") then MT.alternar_loop()
  else
    if not MT.flag("LOOP") then MT.set_flag("LOOP", true) end
    MT.definir_loop(sc.inicio, sc.fim)
    r.GetSetRepeat(1)
    MT.aviso("LOOP: " .. sc.nome)
    if not atual then pular_secao(sc) end
  end
end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- renomear sem a caixa de texto do PC (o nome vem do celular)
function R.renomear_secao_para(n, nome)
  local e, secs = secoes_atuais()
  local sec = secs[n]
  nome = trim(nome or ""):upper()
  if not e.musica or not sec or nome == "" then return end
  if sec.virtual or not sec.idx then return MT.aviso("Este trecho ainda não é uma seção (use Marcar seção)") end
  r.Undo_BeginBlock()
  r.SetProjectMarker3(0, sec.idx, false, sec.inicio, 0, nome, MT.cor_secao(nome))
  if MT.gerar_guia then pcall(MT.gerar_guia, e.musica, true) end
  r.Undo_EndBlock("Renomear seção: " .. nome, -1)
  r.UpdateTimeline()
  if MT.gravar_marcadores then pcall(MT.gravar_marcadores, e.musica, true) end
  MT.aviso("Seção renomeada: " .. nome)
end

-- tom original sem a caixa de texto do PC
function R.definir_tom_para(txt)
  local m = MT.musica_atual()
  if not m then return MT.aviso("Nenhuma música no projeto") end
  txt = trim(txt or "")
  if txt ~= "" and not MT.ler_tom(txt) then return MT.aviso("Tom inválido: " .. txt) end
  r.Undo_BeginBlock()
  r.SetProjectMarker3(0, m.idx, true, m.inicio, m.fim, m.nome .. (txt ~= "" and (" [" .. txt .. "]") or ""), m.cor)
  m.tom = (txt ~= "" and txt) or nil
  if m.tom then MT.gerar_pad(m) end
  r.Undo_EndBlock("Definir tom da música", -1)
  MT.aviso("Tom original: " .. (txt ~= "" and txt or "(nenhum)"))
end

local function mudar_bpm(delta)
  local e = MT.estado()
  local base = e.bpm or 0
  if base <= 0 then return end
  local taxa = r.Master_GetPlayRate(0)
  local alvo = math.floor(base * taxa + 0.5) + delta
  if alvo < 20 then alvo = 20 end
  local nova = alvo / base
  if nova < 0.5 then nova = 0.5 elseif nova > 2 then nova = 2 end
  r.CSurf_OnPlayRateChange(nova)
end

local function publicar_biblio()
  local ok, lista = pcall(MT.listar_biblioteca)
  local t = arr()
  if ok and lista then
    for _, it in ipairs(lista) do
      t[#t + 1] = { p = it.pasta, nome = it.nome, art = it.artista, tom = it.tom, bpm = it.bpm }
    end
  end
  r.SetExtState(SEC, "BIBLIO", enc(t), false)
  r.SetExtState(SEC, "BL_N", tostring((tonumber(r.GetExtState(SEC, "BL_N")) or 0) + 1), false)
end

local CMD = {}
CMD.play = function() MT.play_pause() end
CMD.stop = function() MT.parar() end
CMD.mprev = function() MT.musica_anterior() end
CMD.mnext = function() MT.proxima_musica() end
CMD.mus = function(i) MT.ir_para_musica(tonumber(i)) end
CMD.sord = function(de, para)
  if MT.setlist_travado and MT.setlist_travado() then return end
  if MT.reordenar_setlist then MT.reordenar_setlist(tonumber(de), tonumber(para)) end
end
CMD.strava = function()
  if MT.alternar_trava_setlist then MT.alternar_trava_setlist() end
end
CMD.sprev = function()
  local e, secs = secoes_atuais()
  local alvo = e.secao and secs[e.secao.n - 1] or secs[1]
  if e.secao and e.pos - e.secao.inicio > 2.0 then alvo = e.secao end
  pular_secao(alvo)
end
CMD.snext = function()
  local e, secs = secoes_atuais()
  local alvo = e.secao and secs[e.secao.n + 1] or secs[1]
  if alvo then pular_secao(alvo) else MT.aviso("Última seção da música") end
end
CMD.sec = function(n) local _, secs = secoes_atuais(); pular_secao(secs[tonumber(n)]) end
CMD.sloop = function(n) local e, secs = secoes_atuais(); local sc = secs[tonumber(n)]; if sc then loop_secao(e, sc) end end
CMD.sren = function(n, nome) R.renomear_secao_para(tonumber(n), nome) end
CMD.seek = function(t) t = tonumber(t); if t then MT.ir_para(t) end end
CMD.auto = function() MT.alternar("AUTO", "AUTO") end
CMD.hold = function() MT.alternar("HOLD", "HOLD") end
CMD.loop = function() MT.alternar_loop() end
CMD.lr = function() MT.set("LR_COM_CLICK", "0"); MT.modo_lr() end
CMD.aovivo = function() MT.modo_ao_vivo() end
CMD.studio = function() MT.set("LR_COM_CLICK", "1"); MT.modo_lr() end
CMD.tommais = function() MT.tom_mais() end
CMD.tommenos = function() MT.tom_menos() end
CMD.tomzero = function() MT.tom_zerar() end
CMD.tomdef = function(t) R.definir_tom_para(t) end
CMD.bpm = function(d) mudar_bpm(tonumber(d) or 0) end
CMD.bpmr = function() r.CSurf_OnPlayRateChange(1) end
CMD.soloclick = function() MT.alternar_solo_click() end
CMD.loopclick = function() MT.alternar_repetir_click() end
CMD.pad = function() MT.alternar_pad() end
CMD.suave = function() MT.alternar_salto_suave() end
CMD.vol = function(id, p)
  local tr = trilha_por_id(id); p = tonumber(p)
  if tr and p then r.SetMediaTrackInfo_Value(tr, "D_VOL", pos_para_vol(p)) end
end
CMD.vol0 = function(id) local tr = trilha_por_id(id); if tr then r.SetMediaTrackInfo_Value(tr, "D_VOL", 1) end end
CMD.pan = function(id, v)
  local tr, master = trilha_por_id(id); v = tonumber(v)
  if tr and v then r.SetMediaTrackInfo_Value(tr, "D_PAN", math.max(-1, math.min(1, v))) end
end
CMD.mute = function(id, v)
  local tr, master = trilha_por_id(id)
  if not tr then return end
  if master then MT.mutar_master(v == "1") else r.SetMediaTrackInfo_Value(tr, "B_MUTE", v == "1" and 1 or 0) end
end
CMD.solo = function(id, v)
  local tr, master = trilha_por_id(id)
  if tr and not master then r.SetMediaTrackInfo_Value(tr, "I_SOLO", v == "1" and 2 or 0) end
end
CMD.cancelar = function() MT.cancelar_fila_importacao() end
CMD.marcar = function() MT.marcar_secao() end
CMD.salvar = function() MT.salvar_marcadores() end
CMD.colorir = function() MT.colorir_secoes() end
CMD.analisar = function() MT.analisar_musica_atual() end
CMD.separar = function() MT.separar_musica_atual() end
CMD.desfazer = function() MT.desfazer_separacao() end
CMD.t_aa = function() MT.alternar_analise_auto() end
CMD.t_sa = function() MT.alternar_separacao_auto() end
CMD.t_mo = function() MT.alternar_mutar_original() end
CMD.t_sr = function() if MT.alternar_separacao_rapida then MT.alternar_separacao_rapida() end end
CMD.reparar = function() r.Undo_BeginBlock(); MT.aplicar_modo(); r.Undo_EndBlock("Reparar estrutura", -1); MT.aviso("Estrutura / roteamento reparados") end
CMD.motor = function() MT.instalar_motor() end
CMD.pacote = function(nome) MT.definir_pacote_pads(nome or "") end
CMD.rpads = function() MT.recarregar_pads(); MT.definir_pacote_pads(MT.pacote_pads()) end
CMD.biblio = function() publicar_biblio() end
CMD.badd = function(pasta)
  local ok, lista = pcall(MT.listar_biblioteca)
  for _, it in ipairs(ok and lista or {}) do
    if it.pasta == pasta then MT.adicionar_da_biblioteca(it); return end
  end
  MT.aviso("Música não encontrada na biblioteca")
end
R.CMD = CMD

function R.executar(v)
  -- se o servidor não decodificou o %XX do valor, decodifica aqui
  if not v:find("|", 1, true) and v:find("%%7[Cc]") then v = url_dec(v) end
  local partes = {}
  for p in (v .. "|"):gmatch("([^|]*)|") do partes[#partes + 1] = p end
  local id, nome = partes[1], partes[2]
  local args = {}
  for i = 3, #partes do args[#args + 1] = url_dec(partes[i]) end
  local fn = nome and CMD[nome]
  if fn then
    local ok, err = pcall(fn, table.unpack(args))
    if not ok then MT.aviso("Controle pelo celular: erro em " .. nome .. ": " .. tostring(err)) end
  end
  if id and id ~= "" then r.SetExtState(SEC, "ACK", id, false) end
  return fn ~= nil
end

-------------------------------------------------------------------------------
-- TICK (chamado pelo painel e pelo motor a cada ciclo)
-------------------------------------------------------------------------------
local ultimo_ping, cliente_t = nil, -1e9
local pagina_conferida = false
function R.ativo(agora) return (agora or r.time_precise()) - cliente_t < 20 end

function R.tick()
  local agora = r.time_precise()
  if not pagina_conferida then
    pagina_conferida = true
    pcall(R.instalar_pagina)
  end
  -- comandos (sempre: são baratos e só existem se houver celular)
  local teve = false
  for i = 0, N_SLOTS - 1 do
    local k = "C" .. i
    local v = r.GetExtState(SEC, k)
    if v ~= "" then
      r.SetExtState(SEC, k, "", false)
      R.executar(v)
      teve = true
    end
  end
  local ping = r.GetExtState(SEC, "PING")
  if ping ~= ultimo_ping then
    if ultimo_ping ~= nil or ping ~= "" then cliente_t = agora end
    ultimo_ping = ping
  end
  if teve then cliente_t = agora end
  -- v1.8: as instâncias atuais se coordenam pela T_FAST2. A T_FAST antiga é
  -- carimbada a cada frame: um motor/painel ANTIGO que ainda esteja carregado
  -- (aberto antes de atualizar o kit) vê o carimbo recente e fica quieto, sem
  -- sobrescrever o celular com a lista de canais antiga.
  r.SetExtState(SEC, "T_FAST", string.format("%.4f", agora), false)
  if not R.ativo(agora) then return end

  local t_fast = tonumber(r.GetExtState(SEC, "T_FAST2")) or 0
  if agora - t_fast < 0.075 and agora >= t_fast and not teve then return end
  r.SetExtState(SEC, "T_FAST2", string.format("%.4f", agora), false)

  local e = MT.estado()
  local t_st = tonumber(r.GetExtState(SEC, "T_STATE")) or 0
  if teve or agora - t_st >= 0.25 or agora < t_st then
    r.SetExtState(SEC, "T_STATE", string.format("%.4f", agora), false)
    local novo = enc(R.montar_estado(e, agora))
    if novo ~= r.GetExtState(SEC, "STATE") then
      r.SetExtState(SEC, "STATE", novo, false)
      r.SetExtState(SEC, "SEQ", tostring((tonumber(r.GetExtState(SEC, "SEQ")) or 0) + 1), false)
    end
    atualizar_onda(e.musica, agora)
  end
  local f = R.montar_rapido(e, agora)
  f.q = tonumber(r.GetExtState(SEC, "SEQ")) or 0
  f.hb = math.floor(agora * 10) % 1000000      -- muda sempre: o celular sabe que o Lua está vivo
  f.w = onda.chave
  if f.w == nil then
    local w = r.GetExtState(SEC, "WAVE"):match('"k":"(%x+)"')
    f.w = w
  end
  r.SetExtState(SEC, "FAST", enc(f), false)
end

-------------------------------------------------------------------------------
-- CONFIGURAÇÃO: interface web do REAPER, IPs e endereço
-------------------------------------------------------------------------------
-- Lê as "Control surfaces" HTTP do reaper.ini: { {porta=8080, usuario="", senha?, pagina="index.html", ativo=true}, ... }
function R.ler_web()
  local ini = r.get_ini_file()
  local d = ler(ini) or ""
  local lista = {}
  local na_secao = false
  for linha in d:gmatch("[^\r\n]+") do
    local s = linha:match("^%[(.-)%]")
    if s then na_secao = (s:upper() == "REAPER")
    elseif na_secao then
      local k, v = linha:match("^csurf_(%d+)=(.*)$")
      if k and v:match("^HTTP%s") then
        local flags, porta, resto = v:match("^HTTP%s+(%-?%d+)%s+(%d+)%s*(.*)$")
        local cred = resto and resto:match("^'([^']*)'") or ""
        local pagina = resto and resto:match("^'[^']*'%s+'([^']*)'") or ""
        lista[#lista + 1] = { idx = tonumber(k), porta = tonumber(porta), flags = tonumber(flags),
          usuario = cred:match("^([^:]*)") or "", tem_senha = cred:find(":") ~= nil, pagina = pagina }
      end
    end
  end
  return lista
end

-- Acrescenta a interface web no reaper.ini (vale depois de reiniciar o REAPER).
-- Guarda backup do reaper.ini. Devolve true ou false, msg
function R.ativar_web(porta, usuario, senha)
  porta = math.floor(tonumber(porta) or R.PORTA_PADRAO)
  if porta < 1 or porta > 65535 then return false, "porta inválida" end
  usuario = trim(usuario or ""); senha = senha or ""
  if usuario:find("[':%s]") or senha:find("['%s]") then return false, "usuário/senha não podem ter espaço, aspas ou dois-pontos" end
  local ini = r.get_ini_file()
  local d = ler(ini)
  if not d then return false, "não consegui ler " .. ini end
  for _, w in ipairs(R.ler_web()) do
    if w.porta == porta then return true, "já existe uma interface web na porta " .. porta end
  end
  local nl = d:find("\r\n") and "\r\n" or "\n"
  local cred = (usuario ~= "" and (usuario .. ":" .. senha)) or ""
  local linhas, ini_r, fim_r = {}, nil, nil
  for linha in (d .. (d:sub(-1) == "\n" and "" or nl)):gmatch("([^\n]*)\n") do
    linhas[#linhas + 1] = linha:gsub("\r$", "")
  end
  for i, l in ipairs(linhas) do
    local s = l:match("^%[(.-)%]")
    if s then
      if ini_r and not fim_r then fim_r = i - 1 end
      if s:upper() == "REAPER" then ini_r = i end
    end
  end
  if not ini_r then return false, "seção [REAPER] não encontrada no reaper.ini" end
  fim_r = fim_r or #linhas
  local cnt, idx_cnt = 0, nil
  for i = ini_r + 1, fim_r do
    local c = linhas[i]:match("^csurf_cnt=(%d+)")
    if c then cnt, idx_cnt = tonumber(c), i end
  end
  local nova = string.format("csurf_%d=HTTP 0 %d '%s' '%s' 0 ''", cnt, porta, cred, R.PAGINA)
  if idx_cnt then
    linhas[idx_cnt] = "csurf_cnt=" .. (cnt + 1)
    table.insert(linhas, idx_cnt, nova)
  else
    table.insert(linhas, ini_r + 1, "csurf_cnt=1")
    table.insert(linhas, ini_r + 1, nova)
  end
  local backup = ini .. ".bak-mikseifador-" .. os.date("%Y%m%d-%H%M%S")
  if not gravar(backup, d) then return false, "não consegui criar o backup " .. backup end
  if not gravar(ini, table.concat(linhas, nl) .. nl) then return false, "não consegui gravar " .. ini end
  return true, backup
end

-- IPs do computador na rede local (Wi-Fi / cabo), o mais provável primeiro
local IGNORAR = { "vethernet", "virtualbox", "vmware", "hyper%-v", "wsl", "loopback", "bluetooth", "docker", "tailscale", "zerotier", "vpn", "utun", "bridge" }
local function privado(ip)
  local a, b = ip:match("^(%d+)%.(%d+)%.")
  a, b = tonumber(a), tonumber(b)
  if not a then return false end
  return a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)
end
function R.parse_ipconfig(txt)
  local lista = {}
  local adaptador, ignorar = "", false
  local atual, em_gw = nil, false
  for linha in (txt or ""):gmatch("[^\r\n]+") do
    if not linha:match("^%s") and linha:find(":%s*$") then
      adaptador = linha:gsub(":%s*$", "")
      ignorar = false
      local low = adaptador:lower()
      for _, p in ipairs(IGNORAR) do if low:find(p) then ignorar = true end end
      atual = nil
    else
      local ip = linha:match("IPv4[^:]*:%s*(%d+%.%d+%.%d+%.%d+)")
      if ip then
        atual = { ip = ip, nome = adaptador, nota = (privado(ip) and 2 or 0) + (ignorar and -5 or 0) }
        if not ip:match("^169%.254%.") and not ip:match("^127%.") then lista[#lista + 1] = atual end
        em_gw = false
      elseif linha:find("[Gg]ateway") then
        -- "Gateway Padrão . . : 192.168.0.1" ou IPv6 aqui e o IPv4 na linha de baixo
        em_gw = true
        if atual and linha:match(":%s*(%d+%.%d+%.%d+%.%d+)%s*$") then atual.nota = atual.nota + 3; em_gw = false end
      elseif em_gw and linha:match("^%s+(%d+%.%d+%.%d+%.%d+)%s*$") then
        if atual then atual.nota = atual.nota + 3 end
        em_gw = false
      else
        em_gw = false
      end
    end
  end
  table.sort(lista, function(a, b) return a.nota > b.nota end)
  return lista
end
function R.parse_ifconfig(txt)
  local lista, iface = {}, ""
  for linha in (txt or ""):gmatch("[^\r\n]+") do
    local nome = linha:match("^([%w%d]+):")
    if nome then iface = nome end
    local ip = linha:match("inet%s+(%d+%.%d+%.%d+%.%d+)")
    if ip and not ip:match("^127%.") and not ip:match("^169%.254%.") then
      local nota = (privado(ip) and 2 or 0) + ((iface == "en0" or iface == "en1") and 3 or 0)
      local low = iface:lower()
      for _, p in ipairs(IGNORAR) do if low:find(p) then nota = nota - 5 end end
      lista[#lista + 1] = { ip = ip, nome = iface, nota = nota }
    end
  end
  table.sort(lista, function(a, b) return a.nota > b.nota end)
  return lista
end
function R.ips()
  local saida
  if SO_WIN then
    saida = r.ExecProcess('cmd.exe /C ipconfig', 4000)
    saida = saida and saida:gsub("^%d+\n", "") or ""
    return R.parse_ipconfig(saida)
  end
  saida = r.ExecProcess('/sbin/ifconfig', 4000)
  saida = saida and saida:gsub("^%d+\n", "") or ""
  return R.parse_ifconfig(saida)
end

function R.url(ip, porta, com_pagina)
  local u = string.format("http://%s:%d/", ip or "IP-DO-PC", porta or R.PORTA_PADRAO)
  if com_pagina then u = u .. R.PAGINA end
  return u
end

return R
end
