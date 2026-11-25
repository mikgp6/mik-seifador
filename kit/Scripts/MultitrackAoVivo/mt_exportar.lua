-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  mt_exportar.lua — exportação geral de trilhas para qualquer DAW.
  Fica num arquivo à parte porque o mt_lib.lua já está no limite de 200
  variáveis locais do chunk principal do Lua (REAPER). Carregado sob demanda
  por mt_lib (M.exportar_trilhas), sem adicionar "local" no chunk do mt_lib.
]]
return function(M)
  local r = reaper
  local SEP = M.SEP
  local function inteiro(n, padrao)
    return M.inteiro(n, padrao)
  end

-------------------------------------------------------------------------------
-- EXPORTAR TRILHAS (para qualquer DAW)
-- Menu / Ctrl+Shift+X (Cmd+Shift+X no Mac). Gera <pasta da música>/Exportar/<nome>
-- com as 6 trilhas separadas (as que existirem), click e guia em WAV de mesmo
-- começo e mesmo comprimento, LEIA-ME.txt e MIDI de tempo/marcadores.
-- Não abre janela de prompt, não salva e não altera o projeto (só lê o áudio).
-------------------------------------------------------------------------------

function M.exportar_nome_seguro(s)
  s = tostring(s or "Musica")
  s = s:gsub("[\\/:*?\"<>|]", "-"):gsub("[%c]", "")
  s = s:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.+$", "")
  if s == "" or s == "." or s == ".." then s = "Musica" end
  if #s > 80 then s = s:sub(1, 80):gsub("%s+$", "") end
  return s
end

function M.exportar_planejar_nomes(nomes_banda)
  local oficiais, faltando, extras = {}, {}, {}
  local usado = {}
  local mapa = {}
  for _, n in ipairs(nomes_banda or {}) do
    local chave = M.norm(n)
    if chave ~= "" and not mapa[chave] then mapa[chave] = n end
  end
  for _, s in ipairs(M.STEMS_SEPARADOS) do
    local n = mapa[M.norm(s)]
    if n then
      oficiais[#oficiais + 1] = { rotulo = s, origem = n }
      usado[M.norm(s)] = true
    else
      faltando[#faltando + 1] = s
    end
  end
  for _, n in ipairs(nomes_banda or {}) do
    if not usado[M.norm(n)] then extras[#extras + 1] = n end
  end
  local exportar = {}
  if #oficiais > 0 then
    for _, x in ipairs(oficiais) do exportar[#exportar + 1] = x end
  else
    for _, n in ipairs(extras) do
      exportar[#exportar + 1] = { rotulo = n, origem = n, extra = true }
    end
    extras = {}
  end
  return { exportar = exportar, faltando = faltando, extras = extras, usou_oficiais = #oficiais > 0 }
end

function M.exportar_mmss(t)
  t = tonumber(t) or 0
  if t < 0 then t = 0 end
  local ms = math.floor(t * 1000 + 0.5)
  local s = math.floor(ms / 1000)
  ms = ms % 1000
  local m = math.floor(s / 60)
  s = s % 60
  return string.format("%d:%02d.%03d", m, s, ms)
end

function M.exportar_texto_leia_me(info)
  info = info or {}
  local L = {}
  local function add(s) L[#L + 1] = s or "" end
  add("Mik Seifador v" .. (info.versao or M.VERSAO) .. " — Exportação geral de trilhas")
  add("Para abrir em qualquer DAW (Logic, Pro Tools, Ableton, Studio One, Reaper, etc.).")
  add("")
  add("Música: " .. tostring(info.nome or ""))
  if info.tom and info.tom ~= "" then add("Tom: " .. tostring(info.tom)) end
  add(string.format("Duração: %s (%0.3f s)", M.exportar_mmss(info.duracao or 0), tonumber(info.duracao) or 0))
  add("Início no projeto: " .. M.exportar_mmss(info.inicio_projeto or 0))
  if info.bpm_txt and info.bpm_txt ~= "" then add("BPM: " .. info.bpm_txt) else add("BPM: (não encontrado)") end
  if info.compasso_txt and info.compasso_txt ~= "" then add("Fórmula de compasso: " .. info.compasso_txt) else add("Fórmula de compasso: (não encontrada)") end
  add(string.format("Áudio: WAV PCM 24-bit, %d Hz, todas as faixas começam no início da música e têm o mesmo comprimento.", tonumber(info.sr) or 0))
  add("O áudio segue o playrate e o volume de cada item no projeto (tempo e tom da linha do tempo).")
  add("Os faders do mixer e o estado de mute/solo não entram no arquivo; o projeto não é alterado.")
  add("")
  add("Trilhas exportadas:")
  if info.arquivos and #info.arquivos > 0 then
    for _, a in ipairs(info.arquivos) do add("  - " .. a) end
  else
    add("  (nenhum WAV de áudio)")
  end
  add("")
  if info.faltando and #info.faltando > 0 then
    if info.usou_oficiais then
      add("Das 6 trilhas separadas (Bateria, Baixo, Guitarra, Teclado, Voz, Outros), não foram encontradas nesta música:")
    else
      add("As 6 trilhas separadas (Bateria, Baixo, Guitarra, Teclado, Voz, Outros) não estão nesta música.")
      add("Foram exportadas as trilhas que existiam na BANDA. Para obter as 6, use Menu > Separar trilhas.")
      add("Não encontradas:")
    end
    for _, n in ipairs(info.faltando) do add("  - " .. n) end
    add("")
  end
  if info.extras and #info.extras > 0 then
    add("Outras trilhas na BANDA (não exportadas, porque as trilhas separadas oficiais estavam presentes):")
    for _, n in ipairs(info.extras) do add("  - " .. n) end
    add("")
  end
  if info.sem_click then add("Click: não há trilha CLICK com áudio nesta música.") end
  if info.sem_guia then add("Guia: não há trilha GUIA com áudio nesta música.") end
  if info.sem_click or info.sem_guia then add("") end
  add("Seções / marcadores (tempo a partir do início da música):")
  if info.secoes and #info.secoes > 0 then
    for _, s in ipairs(info.secoes) do
      add(string.format("  %s  %s", M.exportar_mmss(s.t or 0), tostring(s.nome or "")))
    end
  else
    add("  (nenhuma seção ou marcador)")
  end
  add("")
  if info.midi and info.midi ~= "" then
    add("MIDI: " .. info.midi .. " — mapa de tempo, fórmulas de compasso e marcadores, para importar no DAW.")
    add("")
  end
  add("Gerado em: " .. tostring(info.data or ""))
  add("Mik Seifador — Miqueias Felix")
  add("")
  return table.concat(L, "\n")
end

local function i32le(n)
  n = inteiro(n)
  if n < 0 then n = n + 0x100000000 end
  n = n % 0x100000000
  local b0 = n % 256; n = math.floor(n / 256)
  local b1 = n % 256; n = math.floor(n / 256)
  local b2 = n % 256; n = math.floor(n / 256)
  return string.char(b0, b1, b2, n % 256)
end
local function i16le(n)
  n = inteiro(n)
  if n < 0 then n = n + 0x10000 end
  n = n % 0x10000
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function f32_para_i24(x)
  x = tonumber(x) or 0
  if x > 1 then x = 1 elseif x < -1 then x = -1 end
  local n = math.floor(x * 8388607 + (x >= 0 and 0.5 or -0.5))
  if n > 8388607 then n = 8388607 end
  if n < -8388607 then n = -8388607 end
  if n < 0 then n = n + 16777216 end
  local b0 = n % 256; n = math.floor(n / 256)
  local b1 = n % 256; n = math.floor(n / 256)
  return string.char(b0, b1, n % 256)
end

-- amostras: tabela 1-based de floats entrelaçados (nframes * nch)
function M.exportar_escrever_wav(path, sr, nch, amostras)
  sr = inteiro(sr, 44100)
  nch = inteiro(nch, 2)
  if nch < 1 then nch = 1 end
  if nch > 8 then nch = 8 end
  amostras = amostras or {}
  local ntotal = #amostras
  local nframes = math.floor(ntotal / nch)
  local bps = 3
  local block = nch * bps
  local data = nframes * block
  local f = io.open(path, "wb")
  if not f then return false, "não consegui criar " .. tostring(path) end
  f:write("RIFF", i32le(36 + data), "WAVE")
  f:write("fmt ", i32le(16), i16le(1), i16le(nch), i32le(sr), i32le(sr * block), i16le(block), i16le(24))
  f:write("data", i32le(data))
  local buf, nb = {}, 0
  for i = 1, nframes * nch do
    buf[#buf + 1] = f32_para_i24(amostras[i] or 0)
    nb = nb + 1
    if nb >= 2048 then f:write(table.concat(buf)); buf = {}; nb = 0 end
  end
  if #buf > 0 then f:write(table.concat(buf)) end
  f:close()
  return true, nframes
end

local function wav_abrir(path, sr, nch, nframes)
  local bps, block = 3, nch * 3
  local data = nframes * block
  local f = io.open(path, "wb")
  if not f then return nil end
  f:write("RIFF", i32le(36 + data), "WAVE")
  f:write("fmt ", i32le(16), i16le(1), i16le(nch), i32le(sr), i32le(sr * block), i16le(block), i16le(24))
  f:write("data", i32le(data))
  return f
end

local function wav_bloco(f, amostras, n)
  local buf = {}
  for i = 1, n do buf[i] = f32_para_i24(amostras[i] or 0) end
  f:write(table.concat(buf))
end

local function midi_u16(n)
  n = inteiro(n) % 0x10000
  return string.char(math.floor(n / 256) % 256, n % 256)
end
local function midi_u32(n)
  n = inteiro(n)
  if n < 0 then n = 0 end
  n = n % 0x100000000
  return string.char(math.floor(n / 0x1000000) % 256, math.floor(n / 0x10000) % 256, math.floor(n / 0x100) % 256, n % 256)
end
local function midi_vlq(n)
  n = math.max(0, inteiro(n))
  local bytes = { n % 128 }
  n = math.floor(n / 128)
  while n > 0 do
    bytes[#bytes + 1] = n % 128
    n = math.floor(n / 128)
  end
  local t = {}
  for i = #bytes, 1, -1 do
    local v = bytes[i]
    if i > 1 then v = v + 128 end
    t[#t + 1] = string.char(v)
  end
  return table.concat(t)
end

function M.exportar_escrever_midi(path, evs, ppq)
  ppq = inteiro(ppq, 480)
  evs = evs or {}
  table.sort(evs, function(a, b)
    if a.tick == b.tick then return (a.ord or 0) < (b.ord or 0) end
    return a.tick < b.tick
  end)
  local corpo = {}
  do
    local tn = "Tempo e secoes"
    corpo[#corpo + 1] = midi_vlq(0) .. string.char(0xFF, 0x03, #tn) .. tn
  end
  local ultimo = 0
  for _, e in ipairs(evs) do
    local t = inteiro(e.tick or 0)
    if t < 0 then t = 0 end
    corpo[#corpo + 1] = midi_vlq(t - ultimo) .. (e.data or "")
    ultimo = t
  end
  corpo[#corpo + 1] = midi_vlq(0) .. string.char(0xFF, 0x2F, 0x00)
  local track = table.concat(corpo)
  local f = io.open(path, "wb")
  if not f then return false, "não consegui criar " .. tostring(path) end
  f:write("MThd", midi_u32(6), midi_u16(0), midi_u16(1), midi_u16(ppq))
  f:write("MTrk", midi_u32(#track), track)
  f:close()
  return true
end

local function midi_tempo(bpm)
  bpm = tonumber(bpm) or 120
  if bpm < 1 then bpm = 120 end
  local us = inteiro(math.floor(60000000 / bpm + 0.5))
  if us < 1 then us = 1 end
  if us > 0xFFFFFF then us = 0xFFFFFF end
  return string.char(0xFF, 0x51, 0x03, math.floor(us / 0x10000) % 256, math.floor(us / 0x100) % 256, us % 256)
end
local function midi_compasso(num, den)
  num = inteiro(num, 4)
  den = inteiro(den, 4)
  if num < 1 then num = 4 end
  local dd, d = 0, den
  while d > 1 and d % 2 == 0 do dd = dd + 1; d = d / 2 end
  return string.char(0xFF, 0x58, 0x04, num % 256, dd % 256, 24, 8)
end
local function midi_marcador(nome)
  nome = tostring(nome or "")
  if #nome > 80 then nome = nome:sub(1, 80) end
  return string.char(0xFF, 0x06, #nome) .. nome
end

local function srate_exportacao(trilhas)
  if r.GetSetProjectInfo then
    local sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false)
    if sr and sr >= 8000 then return inteiro(sr) end
  end
  for _, tr in ipairs(trilhas or {}) do
    if r.ValidatePtr2(0, tr, "MediaTrack*") then
      for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
        local it = r.GetTrackMediaItem(tr, k)
        local tk = r.GetActiveTake(it)
        local src = tk and r.GetMediaItemTake_Source(tk)
        local sr = src and r.GetMediaSourceSampleRate(src)
        if sr and sr >= 8000 then return inteiro(sr) end
      end
    end
  end
  return 44100
end

local function nch_da_trilha(tr)
  local maxc = 1
  for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, k)
    local tk = r.GetActiveTake(it)
    if tk and not r.TakeIsMIDI(tk) then
      local src = r.GetMediaItemTake_Source(tk)
      local c = src and r.GetMediaSourceNumChannels(src)
      c = inteiro(c or 0)
      if c > maxc then maxc = c end
    end
  end
  if maxc < 1 then maxc = 1 end
  if maxc > 2 then maxc = 2 end
  return maxc
end

-- Escreve o WAV da trilha no intervalo [ini, fim) com playrate/volume do item,
-- em blocos (não carrega a música inteira na memória). Não mexe em mute,
-- solo, fader ou configurações de render.
local function renderizar_trilha_para_wav(tr, ini, fim, sr, nch, nframes, path)
  if not r.CreateTakeAudioAccessor or not r.GetAudioAccessorSamples or not r.new_array then
    return nil, "este REAPER não tem AudioAccessor (preciso de uma versão recente)"
  end
  local itens = {}
  for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, k)
    local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
    if pos + len > ini and pos < fim then
      local tk = r.GetActiveTake(it)
      if tk and not r.TakeIsMIDI(tk) then
        local vol_it = r.GetMediaItemInfo_Value(it, "D_VOL")
        if not vol_it or vol_it <= 0 then vol_it = 1 end
        local vol_tk = r.GetMediaItemTakeInfo_Value(tk, "D_VOL")
        if not vol_tk or vol_tk <= 0 then vol_tk = 1 end
        local aa = r.CreateTakeAudioAccessor(tk)
        if aa then
          itens[#itens + 1] = { pos = pos, fim = pos + len, ganho = vol_it * vol_tk, aa = aa }
        end
      end
    end
  end
  local f = wav_abrir(path, sr, nch, nframes)
  if not f then
    for _, it in ipairs(itens) do r.DestroyAudioAccessor(it.aa) end
    return nil, "não consegui criar " .. tostring(path)
  end
  local CHUNK = 32768
  local escrito = 0
  local mix = r.new_array(CHUNK * nch)
  local ped = r.new_array(CHUNK * nch)
  while escrito < nframes do
    local n = nframes - escrito
    if n > CHUNK then n = CHUNK end
    for i = 1, n * nch do mix[i] = 0 end
    local t0 = ini + (escrito / sr)
    local t1 = ini + ((escrito + n) / sr)
    for _, it in ipairs(itens) do
      local a = math.max(t0, it.pos)
      local b = math.min(t1, it.fim)
      if b > a then
        local off = inteiro(math.floor((a - t0) * sr + 0.5))
        local np = inteiro(math.floor((b - a) * sr + 0.5))
        if off < 0 then np = np + off; off = 0 end
        if off + np > n then np = n - off end
        if np > 0 then
          local ok = r.GetAudioAccessorSamples(it.aa, sr, nch, a - it.pos, np, ped)
          if ok then
            for i = 1, np * nch do
              local dest = off * nch + i
              mix[dest] = (mix[dest] or 0) + (ped[i] or 0) * it.ganho
            end
          end
        end
      end
    end
    local tmp = {}
    for i = 1, n * nch do tmp[i] = mix[i] or 0 end
    wav_bloco(f, tmp, n * nch)
    escrito = escrito + n
  end
  f:close()
  for _, it in ipairs(itens) do r.DestroyAudioAccessor(it.aa) end
  return true
end

local function bpm_e_compassos(ini, fim)
  local bpm0 = r.TimeMap_GetDividedBpmAtTime and r.TimeMap_GetDividedBpmAtTime(ini) or nil
  local num0, den0 = 4, 4
  if r.TimeMap_GetTimeSigAtTime then
    local a, b, c = r.TimeMap_GetTimeSigAtTime(0, ini)
    if type(a) == "number" and type(b) == "number" and b >= 1 then
      -- algumas versões: retval, num, den; outras: num, den, start
      if c and c >= 1 and a >= 1 and a <= 64 then num0, den0 = inteiro(a), inteiro(b)
      elseif a >= 1 and a <= 64 and b >= 1 then num0, den0 = inteiro(a), inteiro(b)
      elseif b >= 1 and b <= 64 and c and c >= 1 then num0, den0 = inteiro(b), inteiro(c)
      end
    elseif type(b) == "number" and b >= 1 then
      num0 = inteiro(a or 4); den0 = inteiro(b)
    end
  end
  local mudancas = {}
  local n = r.CountTempoTimeSigMarkers and r.CountTempoTimeSigMarkers(0) or 0
  for i = 0, n - 1 do
    local ok, timepos, _meas, _beat, bpm, tsnum, tsden = r.GetTempoTimeSigMarker(0, i)
    if type(ok) ~= "boolean" then
      -- algumas assinaturas devolvem timepos no 1º valor
      timepos, bpm, tsnum, tsden = ok, _meas, _beat, bpm
    end
    timepos = tonumber(timepos)
    if timepos and timepos >= ini - 0.0005 and timepos < fim - 0.0005 then
      mudancas[#mudancas + 1] = {
        t = math.max(0, timepos - ini),
        timepos = timepos,
        bpm = tonumber(bpm) or 0,
        num = inteiro(tsnum or 0),
        den = inteiro(tsden or 0),
      }
    end
  end
  local bpm_txt
  if bpm0 and bpm0 > 0 then
    local mesmo = true
    for _, m in ipairs(mudancas) do
      if m.bpm > 0 and math.abs(m.bpm - bpm0) > 0.05 then mesmo = false; break end
    end
    if mesmo then
      bpm_txt = string.format("%g", math.floor(bpm0 * 100 + 0.5) / 100)
    else
      local partes = { string.format("%g (início)", math.floor(bpm0 * 100 + 0.5) / 100) }
      for _, m in ipairs(mudancas) do
        if m.bpm > 0 then
          partes[#partes + 1] = string.format("%s = %g", M.exportar_mmss(m.t), math.floor(m.bpm * 100 + 0.5) / 100)
        end
      end
      bpm_txt = table.concat(partes, "; ")
    end
  end
  local compasso_txt
  if num0 >= 1 and den0 >= 1 then
    local partes, visto = { string.format("%d/%d", num0, den0) }, { string.format("%d/%d", num0, den0) }
    for _, m in ipairs(mudancas) do
      if m.num >= 1 and m.den >= 1 then
        local k = string.format("%d/%d", m.num, m.den)
        if not visto[k] then
          visto[k] = true
          partes[#partes + 1] = string.format("%s a partir de %s", k, M.exportar_mmss(m.t))
        elseif m.t > 0.05 and k ~= partes[1]:match("^(%d+/%d+)") then
          partes[#partes + 1] = string.format("%s a partir de %s", k, M.exportar_mmss(m.t))
        end
      end
    end
    -- se só mudou o tempo e o compasso é um só
    local unicos = {}
    for _, m in ipairs(mudancas) do
      if m.num >= 1 and m.den >= 1 then unicos[string.format("%d/%d", m.num, m.den)] = true end
    end
    local nuni = 0
    for _ in pairs(unicos) do nuni = nuni + 1 end
    if nuni <= 1 and unicos[string.format("%d/%d", num0, den0)] or nuni == 0 then
      compasso_txt = string.format("%d/%d", num0, den0)
    else
      compasso_txt = table.concat(partes, "; ")
    end
  end
  return {
    bpm0 = bpm0, num0 = num0, den0 = den0, mudancas = mudancas,
    bpm_txt = bpm_txt, compasso_txt = compasso_txt,
  }
end

local function ticks_de(qn0, tempo, ppq)
  if r.TimeMap2_timeToQN then
    return inteiro(math.floor((r.TimeMap2_timeToQN(0, tempo) - qn0) * ppq + 0.5))
  elseif r.TimeMap_timeToQN then
    return inteiro(math.floor((r.TimeMap_timeToQN(tempo) - qn0) * ppq + 0.5))
  end
  return 0
end

function M.exportar_trilhas(m)
  m = m or M.musica_atual()
  if not m or not m.inicio or not m.fim or m.fim <= m.inicio then
    M.aviso("Exportar trilhas: nenhuma música atual")
    return false, "nenhuma música atual"
  end
  local ini, fim = m.inicio, m.fim
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  local pad = banda and M.achar_filho(banda, M.CFG.NOME_PAD)
  local nomes_banda, trilhas_por_nome = {}, {}
  if banda then
    for i = 0, r.CountTracks(0) - 1 do
      local tr = r.GetTrack(0, i)
      if tr ~= pad and M.descende_de(tr, banda) and M.trilha_tem_item_em(tr, ini, fim) then
        -- só as trilhas-folha (não as pastas Bateria/Guitarras/…)
        local depth = math.floor(r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
        local tem_audio = false
        for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
          local it = r.GetTrackMediaItem(tr, k)
          local tk = r.GetActiveTake(it)
          if tk and not r.TakeIsMIDI(tk) then tem_audio = true; break end
        end
        if tem_audio then
          local nome = M.nome_trilha(tr)
          -- pastas com depth==1 e também itens são raras; entra pelo nome
          nomes_banda[#nomes_banda + 1] = nome
          trilhas_por_nome[M.norm(nome)] = tr
        end
      end
    end
  end
  local plano = M.exportar_planejar_nomes(nomes_banda)
  local click = M.trilha_click()
  local guia = M.achar_trilha(M.CFG.NOME_GUIA)
  local tem_click = click and M.trilha_tem_item_em(click, ini, fim)
  local tem_guia = guia and M.trilha_tem_item_em(guia, ini, fim)

  local pasta_m = M.pasta_da_musica(m)
  if not pasta_m or pasta_m == "" then pasta_m = M.pasta_biblioteca() end
  if not pasta_m or pasta_m == "" then
    M.aviso("Exportar trilhas: não achei a pasta da música")
    return false, "pasta da música não encontrada"
  end
  local nome_pasta = M.exportar_nome_seguro(m.nome)
  local dest = pasta_m .. SEP .. "Exportar" .. SEP .. nome_pasta
  if r.file_exists(dest .. SEP .. "LEIA-ME.txt") then
    dest = dest .. " " .. os.date("%Y-%m-%d %H%M%S")
  end
  r.RecursiveCreateDirectory(dest, 0)

  local trilhas_audio = {}
  for _, x in ipairs(plano.exportar) do
    local tr = trilhas_por_nome[M.norm(x.origem)]
    if tr then trilhas_audio[#trilhas_audio + 1] = tr end
  end
  if tem_click then trilhas_audio[#trilhas_audio + 1] = click end
  if tem_guia then trilhas_audio[#trilhas_audio + 1] = guia end

  local sr = srate_exportacao(trilhas_audio)
  local nframes = inteiro(math.floor((fim - ini) * sr + 0.5))
  if nframes < 1 then
    M.aviso("Exportar trilhas: a música é curta demais")
    return false, "duração inválida"
  end

  M.aviso("Exportando trilhas de \"" .. m.nome .. "\"…")
  local arquivos, erros = {}, {}
  local function um_wav(tr, nome_arq)
    local nch = nch_da_trilha(tr)
    local ok, err = renderizar_trilha_para_wav(tr, ini, fim, sr, nch, nframes, dest .. SEP .. nome_arq)
    if not ok then
      erros[#erros + 1] = nome_arq .. ": " .. tostring(err or "falhou")
      return
    end
    arquivos[#arquivos + 1] = nome_arq
  end

  for _, x in ipairs(plano.exportar) do
    local tr = trilhas_por_nome[M.norm(x.origem)]
    if tr then
      local arq = M.exportar_nome_seguro(x.rotulo) .. ".wav"
      um_wav(tr, arq)
    end
  end
  if tem_click then um_wav(click, "Click.wav") end
  if tem_guia then um_wav(guia, "Guia.wav") end

  -- MIDI de tempo e marcadores
  local mapa = bpm_e_compassos(ini, fim)
  local musicas, marcas = M.listar_marcadores()
  local secoes = M.secoes_da_musica(m, marcas)
  local lista_sec = {}
  for _, s in ipairs(secoes or {}) do
    lista_sec[#lista_sec + 1] = { t = (s.inicio or ini) - ini, nome = s.nome or "" }
  end
  local midi_nome = "Tempo e secoes.mid"
  local evs, ppq, ord = {}, 480, 0
  local qn0 = 0
  if r.TimeMap2_timeToQN then qn0 = r.TimeMap2_timeToQN(0, ini)
  elseif r.TimeMap_timeToQN then qn0 = r.TimeMap_timeToQN(ini) end
  if mapa.bpm0 and mapa.bpm0 > 0 then
    evs[#evs + 1] = { tick = 0, ord = 1, data = midi_tempo(mapa.bpm0) }
  end
  if mapa.num0 >= 1 and mapa.den0 >= 1 then
    evs[#evs + 1] = { tick = 0, ord = 2, data = midi_compasso(mapa.num0, mapa.den0) }
  end
  for _, ch in ipairs(mapa.mudancas) do
    local tk = math.max(0, ticks_de(qn0, ini + ch.t, ppq))
    if ch.bpm > 0 then
      ord = ord + 1
      evs[#evs + 1] = { tick = tk, ord = 10 + ord, data = midi_tempo(ch.bpm) }
    end
    if ch.num >= 1 and ch.den >= 1 then
      ord = ord + 1
      evs[#evs + 1] = { tick = tk, ord = 10 + ord, data = midi_compasso(ch.num, ch.den) }
    end
  end
  for _, s in ipairs(lista_sec) do
    local tk = math.max(0, ticks_de(qn0, ini + (s.t or 0), ppq))
    ord = ord + 1
    evs[#evs + 1] = { tick = tk, ord = 100 + ord, data = midi_marcador(s.nome) }
  end
  local ok_midi = M.exportar_escrever_midi(dest .. SEP .. midi_nome, evs, ppq)
  if not ok_midi then midi_nome = "" end

  local tom = nil
  if M.tom_soando then tom = M.tom_soando(m) end
  tom = tom or m.tom
  local txt = M.exportar_texto_leia_me({
    versao = M.VERSAO,
    nome = m.nome,
    tom = tom,
    duracao = fim - ini,
    inicio_projeto = ini,
    bpm_txt = mapa.bpm_txt,
    compasso_txt = mapa.compasso_txt,
    sr = sr,
    arquivos = (function()
      local t = {}
      for _, a in ipairs(arquivos) do t[#t + 1] = a end
      if midi_nome ~= "" then t[#t + 1] = midi_nome end
      t[#t + 1] = "LEIA-ME.txt"
      return t
    end)(),
    faltando = plano.faltando,
    extras = plano.extras,
    usou_oficiais = plano.usou_oficiais,
    sem_click = not tem_click,
    sem_guia = not tem_guia,
    secoes = lista_sec,
    midi = midi_nome,
    data = os.date("%Y-%m-%d %H:%M"),
  })
  local f = io.open(dest .. SEP .. "LEIA-ME.txt", "wb")
  if f then f:write(txt); f:close() end

  if #arquivos == 0 then
    local msg = "Exportar trilhas: não achei áudio nesta música"
    if #erros > 0 then msg = msg .. " (" .. table.concat(erros, "; ") .. ")" end
    M.aviso(msg)
    M.abrir_no_sistema(dest)
    return false, msg
  end
  local msg = string.format("Exportadas %d faixas de \"%s\"", #arquivos, m.nome)
  if #plano.faltando > 0 and plano.usou_oficiais then
    msg = msg .. " (faltando: " .. table.concat(plano.faltando, ", ") .. ")"
  end
  M.aviso(msg)
  M.abrir_no_sistema(dest)
  return true, dest, arquivos
end

  return true
end
