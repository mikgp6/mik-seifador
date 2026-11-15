-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador - mt_analise.lua  (análise de MÚSICA COMUM / VS fechado)
  ---------------------------------------------------------------------
  Lua puro (não usa nada do REAPER): quem lê o áudio é o mt_lib.lua, que
  entrega blocos de amostras a 8000 Hz. Daqui sai:
    * BPM e batidas (inclusive o 1º tempo do compasso)
    * canal de click de um VS fechado (click num lado L/R), se houver
    * seções (divididas em blocos de compassos, com nomes sugeridos)
    * cifra (acordes por tempo: G, Em, D/F#, A7...) e o tom provável
  NÃO execute este arquivo pelo Action List (ele só define funções).

  Uso:
    local A = dofile(dir .. "mt_analise.lua")
    local st = A.novo(numero_de_canais)
    A.processar(st, buffer_intercalado, n_amostras_por_canal)   -- várias vezes
    local res = A.finalizar(st, { bpm = nil, bpb = 4 }, pausa)     -- pausa(p) opcional
]]
local A = {}

A.SR = 8000          -- taxa pedida ao REAPER
A.HOP = 80           -- 10 ms por quadro (100 quadros/s)
A.DEC = 4            -- cromagrama a 2000 Hz
A.NFFT = 1024        -- 0,51 s por análise de acorde
A.LATENCIA = 0.008     -- correção fixa (s) do envelope de ataques (calibrada nos testes)
A.AJUSTE_RASTREIO = 0.0085   -- v1.4: o rastreador cai ~1 quadro depois do ataque (calibrado no teste sintético)

local floor, sqrt, log, exp, abs, max, min, cos, sin, pi =
  math.floor, math.sqrt, math.log, math.exp, math.abs, math.max, math.min, math.cos, math.sin, math.pi

-------------------------------------------------------------------------------
-- filtros (biquad passa-baixa RBJ)
-------------------------------------------------------------------------------
local function lp(fc, fs, q)
  q = q or 0.7071
  local w0 = 2 * pi * fc / fs
  local al = sin(w0) / (2 * q)
  local c = cos(w0)
  local a0 = 1 + al
  return { b0 = (1 - c) / 2 / a0, b1 = (1 - c) / a0, b2 = (1 - c) / 2 / a0, a1 = -2 * c / a0, a2 = (1 - al) / a0 }
end

function A.novo(nch)
  nch = (nch and nch >= 2) and 2 or 1
  local st = { nch = nch, canais = {}, n = 0 }
  local f150, f2k, f1k = lp(150, A.SR), lp(2000, A.SR), lp(900, A.SR)
  for c = 1, nch do
    st.canais[c] = {
      f150 = f150, f2k = f2k, f1k = f1k,
      z = { 0, 0, 0, 0, 0, 0, 0, 0 },
      el = 0, em = 0, eh = 0, k = 0, d = 0,
      low = {}, mid = {}, high = {}, dec = {},
    }
  end
  return st
end

-- buf: tabela intercalada (L,R,L,R...) ; n: amostras por canal
function A.processar(st, buf, n)
  local nch = st.nch
  local HOP, DEC = A.HOP, A.DEC
  for c = 1, nch do
    local C = st.canais[c]
    local f1, f2, f3 = C.f150, C.f2k, C.f1k
    local b01, b11, b21, a11, a21 = f1.b0, f1.b1, f1.b2, f1.a1, f1.a2
    local b02, b12, b22, a12, a22 = f2.b0, f2.b1, f2.b2, f2.a1, f2.a2
    local b03, b13, b23, a13, a23 = f3.b0, f3.b1, f3.b2, f3.a1, f3.a2
    local z = C.z
    local s11, s21, s12, s22, s13, s23, s14, s24 = z[1], z[2], z[3], z[4], z[5], z[6], z[7], z[8]
    local el, em, eh, k, d = C.el, C.em, C.eh, C.k, C.d
    local low, mid, high, dec = C.low, C.mid, C.high, C.dec
    local nl, nd = #low, #dec
    local idx = c
    for _ = 1, n do
      local x = buf[idx] or 0
      idx = idx + nch
      -- passa-baixa 150 Hz (graves)
      local y1 = b01 * x + s11
      s11 = b11 * x - a11 * y1 + s21
      s21 = b21 * x - a21 * y1
      -- passa-baixa 2 kHz
      local y2 = b02 * x + s12
      s12 = b12 * x - a12 * y2 + s22
      s22 = b22 * x - a22 * y2
      -- 2x passa-baixa 900 Hz (para o cromagrama a 2000 Hz)
      local y3 = b03 * x + s13
      s13 = b13 * x - a13 * y3 + s23
      s23 = b23 * x - a23 * y3
      local y4 = b03 * y3 + s14
      s14 = b13 * y3 - a13 * y4 + s24
      s24 = b23 * y3 - a23 * y4
      local m = y2 - y1
      local h = x - y2
      el = el + y1 * y1
      em = em + m * m
      eh = eh + h * h
      k = k + 1
      if k == HOP then
        nl = nl + 1
        low[nl], mid[nl], high[nl] = el, em, eh
        el, em, eh, k = 0, 0, 0, 0
      end
      d = d + 1
      if d == DEC then nd = nd + 1; dec[nd] = y4; d = 0 end
    end
    z[1], z[2], z[3], z[4], z[5], z[6], z[7], z[8] = s11, s21, s12, s22, s13, s23, s14, s24
    C.el, C.em, C.eh, C.k, C.d = el, em, eh, k, d
  end
  -- v1.4: fluxo espectral (FFT 128 a cada 10 ms) na mistura mono - pega ataques
  -- suaves (violão, voz, ao vivo) que as 3 bandas de energia não pegam
  local fx = st.fx
  if not fx then
    fx = { ring = {}, pos = 0, k = 0, fluxo = {}, cheio = 0 }
    for i = 1, 128 do fx.ring[i] = 0 end
    st.fx = fx
  end
  local ring, pos, k, cheio = fx.ring, fx.pos, fx.k, fx.cheio
  local inv = 1 / nch
  local base = 0
  for i = 1, n do
    local v = buf[base + 1] or 0
    if nch == 2 then v = (v + (buf[base + 2] or 0)) * inv end
    base = base + nch
    pos = pos % 128 + 1
    ring[pos] = v
    if cheio < 128 then cheio = cheio + 1 end
    k = k + 1
    if k == HOP then
      k = 0
      fx.pos = pos
      A._fluxo_quadro(fx)
    end
  end
  fx.pos, fx.k, fx.cheio = pos, k, cheio
  st.n = st.n + n
end

-------------------------------------------------------------------------------
-- utilidades numéricas
-------------------------------------------------------------------------------
local function media(t, a, b)
  a, b = a or 1, b or #t
  if b < a then return 0 end
  local s = 0
  for i = a, b do s = s + t[i] end
  return s / (b - a + 1)
end

local function desvio(t)
  local m = media(t)
  local s = 0
  for i = 1, #t do local d = t[i] - m; s = s + d * d end
  return sqrt(s / max(1, #t)), m
end

local function percentil(t, p)
  local c = {}
  for i = 1, #t do c[i] = t[i] end
  table.sort(c)
  if #c == 0 then return 0 end
  local i = max(1, min(#c, floor(p * (#c - 1) + 1.5)))
  return c[i]
end

local function zscore(t)
  local s, m = desvio(t)
  local o = {}
  if s < 1e-12 then s = 1 end
  for i = 1, #t do o[i] = (t[i] - m) / s end
  return o
end

local function cosseno(a, b, n)
  local s, na, nb = 0, 0, 0
  for i = 1, n do s = s + a[i] * b[i]; na = na + a[i] * a[i]; nb = nb + b[i] * b[i] end
  if na < 1e-18 or nb < 1e-18 then return 0 end
  return s / sqrt(na * nb)
end

-- envelope de ataques (onset) a partir de energias por banda
local function onset_de(bandas, nq)
  local o = {}
  for t = 1, nq do o[t] = 0 end
  for _, E in ipairs(bandas) do
    local pico = 0
    for t = 1, nq do if E[t] > pico then pico = E[t] end end
    local eps = pico * 1e-5 + 1e-12
    local ant = log(E[1] + eps)
    local d = {}
    local s2 = 0
    for t = 2, nq do
      local v = log(E[t] + eps)
      local x = v - ant
      if x < 0 then x = 0 end
      d[t] = x
      s2 = s2 + x * x
      ant = v
    end
    d[1] = 0
    local norma = sqrt(s2 / nq) + 1e-9
    for t = 1, nq do o[t] = o[t] + d[t] / norma end
  end
  -- tira a média local (0,4 s) e retifica
  local W = 20
  local acc, out = 0, {}
  local pref = { [0] = 0 }
  for t = 1, nq do acc = acc + o[t]; pref[t] = acc end
  for t = 1, nq do
    local a, b = max(1, t - W), min(nq, t + W)
    local m = (pref[b] - pref[a - 1]) / (b - a + 1)
    local v = o[t] - m
    out[t] = v > 0 and v or 0
  end
  return out
end

local function autocorr(o, lag)
  local s, n = 0, #o
  for t = 1, n - lag do s = s + o[t] * o[t + lag] end
  return s / max(1, n - lag)
end

-- "dobra" o envelope num período P (em quadros) -> pico de fase
local NB = 48
local function dobrar(o, P)
  local h = {}
  for b = 0, NB - 1 do h[b] = 0 end
  local inv = NB / P
  for t = 1, #o do
    local v = o[t]
    if v > 0 then
      local f = ((t - 1) % P) * inv
      local b = floor(f)
      if b >= NB then b = NB - 1 end
      h[b] = h[b] + v
    end
  end
  -- suaviza (circular) e acha o pico
  local melhor, bi, soma = -1, 0, 0
  local hs = {}
  for b = 0, NB - 1 do
    local v = h[(b - 1) % NB] * 0.5 + h[b] + h[(b + 1) % NB] * 0.5
    hs[b] = v
    soma = soma + v
    if v > melhor then melhor, bi = v, b end
  end
  -- interpolação parabólica
  local y0, y1, y2 = hs[(bi - 1) % NB], hs[bi], hs[(bi + 1) % NB]
  local den = y0 - 2 * y1 + y2
  local dlt = 0
  if abs(den) > 1e-12 then dlt = 0.5 * (y0 - y2) / den end
  local fase = ((bi + dlt + 0.5) / NB) * P     -- em quadros (a partir do quadro 1)
  return melhor / (soma / NB + 1e-12), fase
end

-------------------------------------------------------------------------------
-- FFT (radix-2, complexa) para o cromagrama
-------------------------------------------------------------------------------
local function prep_fft(N)
  local rev, bits = {}, floor(log(N) / log(2) + 0.5)
  for i = 0, N - 1 do
    local x, y = i, 0
    for _ = 1, bits do y = y * 2 + (x % 2); x = floor(x / 2) end
    rev[i + 1] = y + 1
  end
  local cr, ci = {}, {}
  for k = 0, N / 2 - 1 do cr[k] = cos(-2 * pi * k / N); ci[k] = sin(-2 * pi * k / N) end
  local jan = {}
  for i = 1, N do jan[i] = 0.5 - 0.5 * cos(2 * pi * (i - 1) / (N - 1)) end
  return { N = N, rev = rev, cr = cr, ci = ci, jan = jan }
end

local function fft_mag(F, x, ini)  -- x: sinal ; ini: índice da 1ª amostra
  local N, rev, jan = F.N, F.rev, F.jan
  local re, im = {}, {}
  local nx = #x
  for i = 1, N do
    local j = ini + i - 1
    local v = (j >= 1 and j <= nx) and x[j] or 0
    re[rev[i]] = v * jan[i]
    im[i] = 0
  end
  local cr, ci = F.cr, F.ci
  local size = 2
  while size <= N do
    local half = size / 2
    local passo = N / size
    for i = 1, N, size do
      local k = 0
      for j = i, i + half - 1 do
        local wr, wi = cr[k], ci[k]
        local l = j + half
        local tr = wr * re[l] - wi * im[l]
        local ti = wr * im[l] + wi * re[l]
        re[l] = re[j] - tr; im[l] = im[j] - ti
        re[j] = re[j] + tr; im[j] = im[j] + ti
        k = k + passo
      end
    end
    size = size * 2
  end
  local mag = {}
  for i = 1, N / 2 do mag[i] = sqrt(re[i] * re[i] + im[i] * im[i]) end
  return mag
end

-- v1.4: um quadro do fluxo espectral (chamado pelo A.processar a cada 80 amostras)
local FFT128 = nil
function A._fluxo_quadro(fx)
  FFT128 = FFT128 or prep_fft(128)
  local x, ring, pos = fx.x or {}, fx.ring, fx.pos
  fx.x = x
  for i = 1, 128 do x[i] = ring[(pos + i - 1) % 128 + 1] end   -- mais antiga primeiro
  local mag = fft_mag(FFT128, x, 1)
  local L = fx.L or {}
  local ant = fx.ant
  local s = 0
  for i = 2, 64 do
    local v = log(1 + 100 * mag[i])
    if ant then local d = v - ant[i]; if d > 0 then s = s + d end end
    L[i] = v
  end
  fx.L, fx.ant = ant or {}, L
  local fl = fx.fluxo
  fl[#fl + 1] = s
end

-------------------------------------------------------------------------------
-- acordes: modelos com harmônicos
-------------------------------------------------------------------------------
A.NOTAS_SUST = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
A.NOTAS_BEM  = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
-- grafia mais comum no Brasil (independente do tom): C# Eb F# Ab Bb
A.NOTAS_BR   = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }

local TIPOS = {
  { suf = "",  iv = { 0, 4, 7 } },
  { suf = "m", iv = { 0, 3, 7 } },
  { suf = "7", iv = { 0, 4, 7, 10 } },
}

local function modelo(raiz, iv)
  local t = {}
  for i = 0, 11 do t[i + 1] = 0 end
  local harm = { { 0, 1.0 }, { 0, 0.6 }, { 7, 0.36 }, { 0, 0.22 }, { 4, 0.13 } }
  for _, n in ipairs(iv) do
    for _, h in ipairs(harm) do
      local pc = (raiz + n + h[1]) % 12
      t[pc + 1] = t[pc + 1] + h[2]
    end
  end
  return t
end

local MODELOS = {}
for ti, tp in ipairs(TIPOS) do
  for raiz = 0, 11 do
    MODELOS[#MODELOS + 1] = { raiz = raiz, tipo = ti, iv = tp.iv, v = modelo(raiz, tp.iv) }
  end
end

function A.nome_acorde(raiz, tipo, baixo, nomes)
  nomes = nomes or A.NOTAS_BR
  local s = nomes[raiz + 1] .. TIPOS[tipo].suf
  if baixo and baixo ~= raiz then s = s .. "/" .. nomes[baixo + 1] end
  return s
end

-- perfis de Krumhansl (tom)
local PERF_MAI = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 }
local PERF_MEN = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 }

local function achar_tom(croma)
  local melhor, tom, menor = -2, 0, false
  for k = 0, 11 do
    for _, modo in ipairs({ { PERF_MAI, false }, { PERF_MEN, true } }) do
      local p = {}
      for i = 0, 11 do p[i + 1] = modo[1][((i - k) % 12) + 1] end
      local mx, mp = media(croma), media(p)
      local s, a, b = 0, 0, 0
      for i = 1, 12 do
        local dx, dp = croma[i] - mx, p[i] - mp
        s = s + dx * dp; a = a + dx * dx; b = b + dp * dp
      end
      local c = s / sqrt(a * b + 1e-18)
      if c > melhor then melhor, tom, menor = c, k, modo[2] end
    end
  end
  return tom, menor, melhor
end

-------------------------------------------------------------------------------
-- FINALIZAR: roda toda a análise
-- opcoes: bpm (forçado), bpb (tempos por compasso, padrão 4),
--         sem_secoes, sem_acordes
-- pausa(p): chamada de vez em quando (0..1) para não travar o REAPER
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- v1.8: ATIVIDADE DOS STEMS (multitrack / VS aberto)
-- at = { fps = quadros por segundo, stems = { {energia_q1, energia_q2, ...}, ... } }
-- (energia = média do quadrado das amostras; tempo 0 = início do áudio analisado)
-- Grava em cada barra .at[k] = 0..1 (o stem k está tocando nesse compasso?)
-- Devolve quantos stems entraram (0 = sem informação)
-------------------------------------------------------------------------------
function A.atividade_compassos(at, barras)
  if type(at) ~= "table" or type(at.stems) ~= "table" or #at.stems < 2 or #barras < 2 then return 0 end
  local fps = tonumber(at.fps) or 4
  local stems = {}
  for _, e in ipairs(at.stems) do
    if type(e) == "table" and #e > 0 then stems[#stems + 1] = e end
  end
  if #stems < 2 then return 0 end
  local Nb = #barras
  local dur_bar = (Nb >= 2) and (barras[Nb].t - barras[1].t) / (Nb - 1) or 2
  for k, e in ipairs(stems) do
    local dbs = {}
    for i = 1, Nb do
      local t0 = barras[i].t
      local t1 = barras[i + 1] and barras[i + 1].t or (t0 + dur_bar)
      local q0, q1 = floor(t0 * fps) + 1, floor(t1 * fps)
      if q1 < q0 then q1 = q0 end
      local s, n = 0, 0
      for q = q0, q1 do if e[q] then s = s + e[q]; n = n + 1 end end
      dbs[i] = 10 * log((n > 0 and s / n or 0) + 1e-10, 10)
    end
    local ref = percentil(dbs, 0.9)
    for i = 1, Nb do
      local v = (dbs[i] - (ref - 24)) / 18
      if v < 0 then v = 0 elseif v > 1 then v = 1 end
      barras[i].at = barras[i].at or {}
      barras[i].at[k] = v
    end
  end
  return #stems
end

-------------------------------------------------------------------------------
-- RASTREADOR DE BATIDAS (v1.4) - para música com andamento que varia (ao vivo)
-- Programação dinâmica sobre o envelope de ataques (estilo Ellis 2007), com o
-- período global P (quadros) como semente: cada batida escolhe a anterior que
-- maximiza "ataque forte + intervalo parecido com P". Depois: posição fina
-- (parábola no pico) e suavização local (o click acompanha a deriva do
-- andamento sem tremer com cada batida humana).
-- Devolve: lista de batidas (em QUADROS, fracionário, 1 = 1º quadro) e confiança
-------------------------------------------------------------------------------
-- "dobra" LOCAL: média, em janelas de ~12 s, da melhor concentração de fase perto
-- do período L (+-4%) - com andamento que varia, a dobra da música inteira se
-- embaralha, mas em 12 s o andamento é quase fixo
function A.dobra_local(o, L, W, H)
  W = W or 1200
  H = H or 600
  local n = #o
  local tot, nw = 0, 0
  local sl = {}
  for w0 = 1, max(1, n - W + 1), H do
    local m = min(W, n - w0 + 1)
    for i = 1, m do sl[i] = o[w0 + i - 1] end
    for i = m + 1, #sl do sl[i] = nil end
    local e = 0
    for i = 1, m do e = e + sl[i] end
    if e > 0 then
      local best = 0
      for f = -0.04, 0.0401, 0.01 do
        local sc = dobrar(sl, L * (1 + f))
        if sc > best then best = sc end
      end
      tot = tot + best; nw = nw + 1
    end
  end
  return tot / max(1, nw)
end

function A.rastrear_batidas(o, P, pausa, alfa, suave)
  pausa = pausa or function() end
  alfa = alfa or A.ALFA or 100
  suave = suave or A.SUAVE or 3
  local n = #o
  if n < P * 8 then return nil, 0 end
  local s2 = 0
  for t = 1, n do s2 = s2 + o[t] * o[t] end
  local sd = sqrt(s2 / n) + 1e-12
  local on = {}
  for t = 1, n do on[t] = o[t] / sd end
  local lmin, lmax = max(1, floor(P * 0.6)), floor(P * 1.6) + 1
  local pen = {}
  for L = lmin, lmax do pen[L] = -alfa * (log(L / P)) ^ 2 end
  local C, prev = {}, {}
  for t = 1, n do
    local best, bp = 0, 0
    local b = t - lmin
    if b >= 1 then
      local a = t - lmax
      if a < 1 then a = 1 end
      best = -1e30
      for tau = a, b do
        local v = C[tau] + pen[t - tau]
        if v > best then best, bp = v, tau end
      end
      if t <= lmax and best < 0 then best, bp = 0, 0 end   -- começo: pode ser a 1ª batida
    end
    C[t] = on[t] + best
    prev[t] = bp
    if t % 3000 == 0 then pausa(t / n) end
  end
  -- fim: melhor pontuação no último período
  local tf, cm = n, -1e30
  for t = max(1, n - floor(P + 0.5)), n do if C[t] > cm then cm, tf = C[t], t end end
  local qs = {}
  local t = tf
  while t and t > 0 do qs[#qs + 1] = t; t = prev[t] end
  local nq = #qs
  for i = 1, floor(nq / 2) do qs[i], qs[nq + 1 - i] = qs[nq + 1 - i], qs[i] end
  if nq < 8 then return nil, 0 end
  -- confiança: ataque médio nas batidas / ataque médio geral
  local sb, sa = 0, 0
  for _, q in ipairs(qs) do
    local m = 0
    for d = -1, 1 do local v = on[q + d]; if v and v > m then m = v end end
    sb = sb + m
  end
  for i = 1, n do sa = sa + on[i] end
  local conf = (sb / nq) / (sa / n + 1e-9)
  -- posição fina (parábola no pico, se a batida caiu num pico)
  local ts = {}
  for i, q in ipairs(qs) do
    local y0, y1, y2 = on[q - 1] or 0, on[q], on[q + 1] or 0
    local d = 0
    if y1 > 0 and y1 >= y0 and y1 >= y2 then
      local den = y0 - 2 * y1 + y2
      if abs(den) > 1e-9 then d = 0.5 * (y0 - y2) / den end
    end
    ts[i] = q + max(-0.5, min(0.5, d))
  end
  -- suavização: reta local de mínimos quadrados em +-'suave' batidas
  local out = {}
  for i = 1, nq do
    local a, b = max(1, i - suave), min(nq, i + suave)
    local sx, sy, sxx, sxy, k = 0, 0, 0, 0, 0
    for j = a, b do sx = sx + j; sy = sy + ts[j]; sxx = sxx + j * j; sxy = sxy + j * ts[j]; k = k + 1 end
    local den = k * sxx - sx * sx
    if den > 1e-9 then
      local bb = (k * sxy - sx * sy) / den
      out[i] = (sy - bb * sx) / k + bb * i
    else
      out[i] = ts[i]
    end
  end
  -- garante ordem crescente
  for i = 2, nq do if out[i] <= out[i - 1] + 0.3 * P then out[i] = out[i - 1] + 0.3 * P end end
  return out, conf
end

function A.finalizar(st, opcoes, pausa)
  opcoes = opcoes or {}
  pausa = pausa or function() end
  local bpb = opcoes.bpb or 4
  local fr = A.SR / A.HOP
  local res = { bpb = bpb, avisos = {} }
  local nch = st.nch
  local nq = #st.canais[1].low
  for c = 2, nch do nq = min(nq, #st.canais[c].low) end
  if nq < fr * 8 then return nil, "Áudio curto demais para analisar (menos de 8 s)." end
  res.duracao = nq / fr

  -- 1) onset por canal + detecção de click num lado (VS fechado)
  local onsets = {}
  for c = 1, nch do
    local C = st.canais[c]
    onsets[c] = onset_de({ C.low, C.mid, C.high }, nq)
  end
  pausa(0.05)
  local canal_click = nil
  if nch == 2 then
    local L, R = st.canais[1], st.canais[2]
    -- correlação das energias (log) entre os lados
    local la, ra = {}, {}
    local spars = {}
    for c = 1, 2 do
      local C = st.canais[c]
      local e = {}
      for t = 1, nq do e[t] = C.low[t] + C.mid[t] + C.high[t] end
      local p99 = percentil(e, 0.99) + 1e-12
      local p50 = percentil(e, 0.5)
      spars[c] = p50 / p99
      for t = 1, nq do e[t] = log(e[t] + p99 * 1e-6) end
      if c == 1 then la = e else ra = e end
    end
    local sl, ml = desvio(la)
    local sr_, mr = desvio(ra)
    local cc = 0
    for t = 1, nq do cc = cc + (la[t] - ml) * (ra[t] - mr) end
    cc = cc / (nq * sl * sr_ + 1e-12)
    res.correlacao_lr = cc
    res.esparsidade = { spars[1], spars[2] }
    if cc < 0.6 then
      for c = 1, 2 do
        local o = onsets[c]
        local a0 = autocorr(o, 0) + 1e-12
        local best = 0
        for lag = floor(fr * 60 / 200), floor(fr * 60 / 50) do
          local v = autocorr(o, lag) / a0
          if v > best then best = v end
        end
        local outro = 3 - c
        if spars[c] < 0.02 and spars[c] * 4 < spars[outro] and best > 0.3 then
          if not canal_click or spars[c] < spars[canal_click] then canal_click = c end
        end
        res["periodicidade_" .. c] = best
      end
    end
  end
  res.canal_click = canal_click            -- 1 = L, 2 = R, nil = não tem
  local canal_musica = canal_click and (3 - canal_click) or nil
  pausa(0.1)

  -- 2) envelope usado para o andamento
  local o
  if canal_click then
    o = onsets[canal_click]
  else
    local bl, bm, bh = {}, {}, {}
    for t = 1, nq do
      local a, b, c = 0, 0, 0
      for ch = 1, nch do
        local C = st.canais[ch]
        a = a + C.low[t]; b = b + C.mid[t]; c = c + C.high[t]
      end
      bl[t], bm[t], bh[t] = a, b, c
    end
    o = onset_de({ bl, bm, bh }, nq)
    res._bl = bl
  end

  -- 3) andamento: autocorrelação com preferência ~110 BPM
  local Lmin, Lmax = floor(fr * 60 / 210), floor(fr * 60 / 48) + 1
  local acf = {}
  local a0 = autocorr(o, 0) + 1e-12
  for lag = Lmin, Lmax do acf[lag] = autocorr(o, lag) / a0 end
  pausa(0.2)
  -- refinamento fino do período pela "dobra" do envelope
  local function busca(c, larg, passo)
    local bestS, bestP, bestF = -1, c, 0
    local P = c - larg
    while P <= c + larg do
      local s, f = dobrar(o, P)
      if s > bestS then bestS, bestP, bestF = s, P, f end
      P = P + passo
    end
    return bestP, bestS, bestF
  end
  local function refinar(L, larg)
    local P1 = busca(L, larg, 0.02)
    P1 = busca(P1, 0.03, 0.002)
    return busca(P1, 0.003, 0.0002)
  end
  local P, S, F
  if opcoes.bpm and opcoes.bpm > 0 then
    local L = fr * 60 / opcoes.bpm
    P, S, F = refinar(L, L * 0.006)
  else
    -- candidatos: picos da autocorrelação (+ metade e dobro de cada um);
    -- quem decide é a "dobra" (quanto uma grade fixa explica os ataques)
    local picos = {}
    for lag = Lmin + 1, Lmax - 1 do
      if acf[lag] >= acf[lag - 1] and acf[lag] >= acf[lag + 1] and acf[lag] > 0 then
        picos[#picos + 1] = { lag = lag, v = acf[lag] }
      end
    end
    table.sort(picos, function(x, y) return x.v > y.v end)
    local cands, vistos = {}, {}
    local function add(L)
      if L >= Lmin and L <= Lmax then
        local ch = floor(L + 0.5)
        if not (vistos[ch] or vistos[ch - 1] or vistos[ch + 1]) then vistos[ch] = true; cands[#cands + 1] = L end
      end
    end
    for i = 1, min(8, #picos) do
      add(picos[i].lag); add(picos[i].lag * 2); add(picos[i].lag / 2)
    end
    if #cands == 0 then return nil, "Não consegui achar o andamento (música sem batida clara)." end
    res._lags = cands
    local melhor = -1
    res.candidatos = {}
    for i, L in ipairs(cands) do
      local Pc, Sc, Fc = busca(L, 1.0, 0.02)
      Pc, Sc, Fc = busca(Pc, 0.03, 0.002)
      local bpm_c = fr * 60 / Pc
      local w = exp(-0.5 * (log(bpm_c / 110) / log(2) / 0.75) ^ 2)
      local v = Sc * w
      res.candidatos[#res.candidatos + 1] = string.format("%.1f:%.2f", bpm_c, Sc)
      if v > melhor then melhor, P, S, F = v, Pc, Sc, Fc end
      if i % 3 == 0 then pausa(0.2 + 0.1 * i / #cands) end
    end
    P, S, F = busca(P, 0.003, 0.0002)
    -- andamento dobrado? se as batidas se alternam forte/fraco (tempo e contratempo),
    -- o pulso de verdade é a metade (ex.: 72 com chimbal em colcheias vira 144)
    do
      local fortes = { 0, 0 }
      local nn = { 0, 0 }
      local k = 0
      local t = F
      while t <= #o - 3 do
        local q = floor(t + 0.5)
        local m = 0
        for dd = -2, 2 do local v = o[q + dd]; if v and v > m then m = v end end
        local par = (k % 2) + 1
        fortes[par] = fortes[par] + m; nn[par] = nn[par] + 1
        k = k + 1
        t = t + P
      end
      local a1, a2 = fortes[1] / max(1, nn[1]), fortes[2] / max(1, nn[2])
      local razao = max(a1, a2) / max(1e-9, min(a1, a2))
      res.alternancia = razao
      local bpm_c = fr * 60 / P
      if razao > (opcoes.limite_alternancia or 2.5) and bpm_c >= 96 and 2 * P <= Lmax then
        local fase2 = (a1 >= a2) and F or (F + P)
        P = 2 * P
        local P2, S2, F2 = busca(P, 0.01, 0.0005)
        P, S = P2, S2
        -- mantém a fase do tempo forte
        F = fase2 % P
        res.metade = true
        local _ = F2
      end
    end
    -- metade/dobro também plausível? guarda a alternativa (o usuário corrige com 1 clique)
    local alt = {}
    for _, f in ipairs({ 0.5, 2 }) do
      local L2 = P / f
      if L2 >= Lmin and L2 <= Lmax then
        local _, S2 = busca(L2, 0.05, 0.005)
        alt[#alt + 1] = { bpm = fr * 60 / L2, s = S2 }
      end
    end
    res.alternativas = alt
  end
  res.bpm_bruto = fr * 60 / P
  res.confianca = S
  -- arredonda para BPM "redondo" quando a diferença é mínima (VS normalmente é inteiro)
  local bpm = fr * 60 / P
  local inteiro = floor(bpm + 0.5)
  local meio = floor(bpm * 2 + 0.5) / 2
  -- só arredonda se o erro acumulado no fim da música ficar abaixo de ~15 ms
  local dur_m = nq / fr
  local function deriva(b) return abs(b - bpm) / bpm * dur_m end
  if deriva(inteiro) < 0.015 then bpm = inteiro
  elseif deriva(meio) < 0.015 then bpm = meio end
  P = fr * 60 / bpm
  S, F = dobrar(o, P)
  res.bpm = bpm
  res.periodo = 60 / bpm
  -- grade fraca = andamento solto (ao vivo, rubato): o click pode não acompanhar
  res.andamento_firme = S >= (opcoes.min_confianca or 2.5)
  pausa(0.35)

  -- 4) fase fina das batidas (em segundos, a partir do início do áudio)
  local fase = (F - 1) / fr      -- quadro 1 = tempo 0
  -- o ataque calculado no quadro t representa o intervalo [t-1, t] -> ajusta meio quadro
  fase = fase + 0.5 / fr + A.LATENCIA
  local T = res.periodo
  fase = fase % T
  local beats = {}
  local t0 = fase
  while t0 < res.duracao do beats[#beats + 1] = t0; t0 = t0 + T end
  res.beats = beats

  -- 4b) v1.4: o andamento VARIA? rastreia as batidas e compara com a grade fixa.
  -- Música de grade fixa (VS, estúdio) continua EXATA como antes; só quando as
  -- batidas reais se afastam da grade é que o click passa a acompanhar o andamento.
  res.variavel = false
  local forcado = opcoes.bpm and opcoes.bpm > 0
  if not canal_click and not opcoes.grade_fixa then
    local desl = 0.5 / fr + A.LATENCIA - (A.AJUSTE_RASTREIO or 0)
    local Pg = fr * 60 / bpm
    -- envelope do rastreador: fluxo espectral (+ ataques das bandas, peso menor)
    local otr = o
    local fl = st.fx and st.fx.fluxo
    if fl and #fl >= nq * 0.9 and A.MODO_ENVELOPE ~= "bandas" then
      local nf = min(#fl, nq)
      local pref, acc = { [0] = 0 }, 0
      for t = 1, nf do acc = acc + fl[t]; pref[t] = acc end
      local e, s2 = {}, 0
      for t = 1, nf do
        local a2, b2 = max(1, t - 20), min(nf, t + 20)
        local v = fl[t] - (pref[b2] - pref[a2 - 1]) / (b2 - a2 + 1)
        v = v > 0 and v or 0
        e[t] = v; s2 = s2 + v * v
      end
      local sde = sqrt(s2 / nf) + 1e-12
      local so = 0
      for t = 1, nq do so = so + o[t] * o[t] end
      local sdo = sqrt(so / nq) + 1e-12
      local wb = A.PESO_BANDAS or 0.5
      otr = {}
      for t = 1, nq do otr[t] = (e[t] or 0) / sde + wb * o[t] / sdo end
      desl = desl - (A.ATRASO_FLUXO or 0)
    end
    -- andamento solto: a "dobra" da música inteira se embaralha com a deriva, então o
    -- período também é reescolhido pelo próprio rastreador (P, dobro, metade, 3/2, 2/3...)
    local cands = { Pg }
    if not res.andamento_firme and not forcado then   -- BPM corrigido à mão: só o nível que o usuário pediu
      local function add(L)
        if L < Lmin or L > Lmax then return end
        for _, x in ipairs(cands) do if abs(x - L) / x < 0.025 then return end end
        cands[#cands + 1] = L
      end
      for _, f in ipairs({ 2, 0.5, 1.5, 2 / 3, 4 / 3, 0.75 }) do add(Pg * f) end
      -- picos da autocorrelação do envelope do rastreador (com deriva, a "dobra" da
      -- música inteira pode ter escolhido um vizinho errado)
      local ac, a0 = {}, autocorr(otr, 0) + 1e-12
      for L = Lmin, Lmax do ac[L] = autocorr(otr, L) / a0 end
      local pk = {}
      for L = Lmin + 1, Lmax - 1 do
        if ac[L] >= ac[L - 1] and ac[L] >= ac[L + 1] and ac[L] > 0 then pk[#pk + 1] = { L = L, v = ac[L] } end
      end
      table.sort(pk, function(x, y) return x.v > y.v end)
      for i = 1, min(8, #pk) do add(pk[i].L) end
      for i, L in ipairs(res._lags or {}) do if i <= 6 then add(L) end end
    end
    local melhor, pior = nil, 0
    for i, L in ipairs(cands) do
      local bt, conf = A.rastrear_batidas(otr, L, function(q) pausa(0.35 + 0.01 * (i - 1 + q) / #cands) end)
      if bt then
        local tb = {}
        for j, q in ipairs(bt) do tb[j] = (q - 1) / fr + desl end
        if i == 1 then
          -- desvio da grade fixa (mediana móvel de 8 batidas)
          local desv = {}
          for j, x in ipairs(tb) do desv[j] = x - (fase + floor((x - fase) / T + 0.5) * T) end
          -- tira o deslocamento fixo entre os dois envelopes (só interessa a DERIVA)
          local off = percentil(desv, 0.5)
          for j = 1, #desv do desv[j] = desv[j] - off end
          for j = 1, #desv - 7 do
            local w = {}
            for q = j, j + 7 do w[#w + 1] = desv[q] end
            table.sort(w)
            local md = abs((w[4] + w[5]) / 2)
            if md > pior then pior = md end
          end
        end
        local bpm_c = fr * 60 / L
        local dl = A.dobra_local(otr, L)
        local v = (A.CRITERIO == "conf" and conf or dl) * exp(-0.5 * (log(bpm_c / 110) / log(2) / 0.75) ^ 2)
        if i == 1 then v = v * (A.BONUS_SEMENTE or 1.05) end   -- empate: fica com o andamento achado antes
        res.cands_rastreio = (res.cands_rastreio or "") .. string.format(" %.1f:c%.2f:d%.2f:v%.2f", bpm_c, conf, dl, v)
        if not melhor or v > melhor.v then melhor = { v = v, tb = tb, conf = conf, L = L } end
      end
    end
    res.desvio_grade = pior
    if melhor and (not res.andamento_firme or pior > (opcoes.limite_desvio or 0.035)) then
      local tb = melhor.tb
      beats = tb
      res.beats = beats
      res.variavel = true
      res.andamento_firme = false
      res.confianca_batidas = melhor.conf
      local iv = {}
      for j = 2, #tb do iv[#iv + 1] = 60 / (tb[j] - tb[j - 1]) end
      res.bpm_min, res.bpm_max = percentil(iv, 0.05), percentil(iv, 0.95)
      local med = percentil(iv, 0.5)
      res.bpm = floor(med * 10 + 0.5) / 10
      res.periodo = 60 / res.bpm
      T = res.periodo
      res.alternativas = forcado and res.alternativas or { { bpm = res.bpm / 2 }, { bpm = res.bpm * 2 } }
      res.aproximado = melhor.conf < (opcoes.min_conf_batidas or 3.0)
    end
  end
  local nb = #beats

  -- 5) energia, início e fim da música
  local etot = {}
  local src = canal_musica and { canal_musica } or nil
  if not src then src = {}; for c = 1, nch do src[#src + 1] = c end end
  for t = 1, nq do
    local s = 0
    for _, c in ipairs(src) do local C = st.canais[c]; s = s + C.low[t] + C.mid[t] + C.high[t] end
    etot[t] = s
  end
  local pico = percentil(etot, 0.98) + 1e-12
  local lim = pico * 10 ^ (-30 / 10)      -- -30 dB do nível alto da música
  local qi, qf = 1, nq
  while qi < nq and etot[qi] < lim do qi = qi + 1 end
  while qf > 1 and etot[qf] < lim do qf = qf - 1 end
  res.inicio_som = (qi - 1) / fr
  res.fim_som = qf / fr

  -- 6) cromagrama por batida (canal da música)
  local dec
  if canal_musica then dec = st.canais[canal_musica].dec
  else
    dec = st.canais[1].dec
    if nch == 2 then
      local d2 = st.canais[2].dec
      local m = {}
      for i = 1, min(#dec, #d2) do m[i] = (dec[i] + d2[i]) * 0.5 end
      dec = m
    end
  end
  local srd = A.SR / A.DEC
  local FF = prep_fft(A.NFFT)
  local mapa = {}         -- bin -> {pc, banda(1=grave,2=agudo)}
  for i = 2, A.NFFT / 2 do
    local f = (i - 1) * srd / A.NFFT
    if f >= 38 and f <= 950 then
      local midi = 69 + 12 * log(f / 440) / log(2)
      local nota = floor(midi + 0.5)
      if abs(midi - nota) < 0.42 then
        mapa[i] = { (nota % 12) + 1, f < 170 and 1 or 2, f }
      end
    end
  end
  local cromas, baixos, energ = {}, {}, {}
  for k = 1, nb do
    local ini_t = beats[k]
    local fim_t = beats[k + 1] or (ini_t + T)
    local centro = (ini_t + fim_t) / 2
    local i0 = floor(centro * srd) - A.NFFT / 2 + 1
    local mag = fft_mag(FF, dec, i0)
    local cr, bx = {}, {}
    for p = 1, 12 do cr[p] = 0; bx[p] = 0 end
    for i, mp in pairs(mapa) do
      local v = mag[i]
      if mp[2] == 2 then cr[mp[1]] = cr[mp[1]] + v else bx[mp[1]] = bx[mp[1]] + v end
    end
    for p = 1, 12 do cr[p] = sqrt(cr[p]); bx[p] = sqrt(bx[p]) end
    cromas[k], baixos[k] = cr, bx
    -- energia da batida (dB)
    local q0, q1 = max(1, floor(ini_t * fr) + 1), min(nq, floor(fim_t * fr))
    local s = 0
    for q = q0, q1 do s = s + etot[q] end
    energ[k] = 10 * log((s / max(1, q1 - q0 + 1)) / pico + 1e-9) / log(10)
    if k % 32 == 0 then pausa(0.35 + 0.35 * k / nb) end
  end

  -- 7) 1º tempo do compasso (downbeat)
  local function no_beat(env, t)
    local q = floor(t * fr) + 1
    local m = 0
    for d = -2, 3 do local v = env[q + d]; if v and v > m then m = v end end
    return m
  end
  local onset_grave
  do
    local C = canal_musica and st.canais[canal_musica] or nil
    local bl = C and C.low or res._bl or st.canais[1].low
    onset_grave = onset_de({ bl }, nq)
  end
  local mudanca, grave, acento = {}, {}, {}
  for k = 1, nb do
    mudanca[k] = (k > 1) and (1 - cosseno(cromas[k - 1], cromas[k], 12)) or 0
    grave[k] = no_beat(onset_grave, beats[k])
    acento[k] = 0
    if canal_click then
      local C = st.canais[canal_click]
      local q = floor(beats[k] * fr) + 1
      local m = 0
      for d = -2, 4 do local v = C.high[q + d]; if v and v > m then m = v end end
      local m2 = 0
      for d = -2, 4 do local v = C.mid[q + d]; if v and v > m2 then m2 = v end end
      acento[k] = log(m + 1e-12) + 0.5 * log(m2 + 1e-12)
    end
  end
  local zm, zg = zscore(mudanca), zscore(grave)
  local za = canal_click and zscore(acento) or nil
  local scores = {}
  for rr = 0, bpb - 1 do
    local s, n = 0, 0
    for k = 1 + rr, nb, bpb do
      if beats[k] >= res.inicio_som - 0.05 and beats[k] <= res.fim_som then
        s = s + zm[k] * 1.0 + zg[k] * 0.6 + (za and za[k] * 2.0 or 0)
        n = n + 1
      end
    end
    scores[rr] = s / max(1, n)
  end
  local rbest, sbest, s2 = 0, -1e9, -1e9
  for rr = 0, bpb - 1 do
    if scores[rr] > sbest then s2 = sbest; sbest, rbest = scores[rr], rr
    elseif scores[rr] > s2 then s2 = scores[rr] end
  end
  res.downbeat_confianca = sbest - s2
  -- 1ª batida "1" do compasso (índice k)
  local k1 = rbest + 1
  -- 1º compasso com música: o primeiro "1" a partir de meia batida antes do som começar
  local kmus = k1
  while beats[kmus] and beats[kmus] < res.inicio_som - 0.5 * T do kmus = kmus + bpb end
  if not beats[kmus] then kmus = k1 end
  res.k_primeiro = kmus
  res.downbeat = beats[kmus]          -- tempo (s) do 1º tempo do 1º compasso com música
  pausa(0.72)

  -- 8) acordes por batida (Viterbi) + tom
  if not opcoes.sem_acordes then
    local soma = {}
    for p = 1, 12 do soma[p] = 0 end
    for k = 1, nb do
      local cr, bx = cromas[k], baixos[k]
      for p = 1, 12 do soma[p] = soma[p] + cr[p] + 0.5 * bx[p] end
    end
    local tom, menor = achar_tom(soma)
    res.tom_pc, res.tom_menor = tom, menor
    local NS = #MODELOS
    local emis = {}
    local silencio = {}
    for k = 1, nb do
      local cr, bx = cromas[k], baixos[k]
      local e = {}
      local mxb = 0
      for p = 1, 12 do if bx[p] > mxb then mxb = bx[p] end end
      for s = 1, NS do
        local Mo = MODELOS[s]
        local v = cosseno(cr, Mo.v, 12)
        if mxb > 0 then v = v + 0.12 * (bx[Mo.raiz + 1] / mxb) end
        if Mo.tipo == 3 then v = v - 0.035 end   -- só chama de "7" com evidência
        e[s] = v
      end
      emis[k] = e
      silencio[k] = energ[k] < -30
    end
    -- Viterbi (troca de acorde custa; trocar no 1º tempo custa menos)
    local TROCA = 0.12
    local ant, trilha = {}, {}
    for s = 1, NS do ant[s] = emis[1][s] * 6 end
    for k = 2, nb do
      local melhor_ant, sb = -1e18, 1
      for s = 1, NS do if ant[s] > melhor_ant then melhor_ant, sb = ant[s], s end end
      local custo = TROCA * (((k - k1) % bpb == 0) and 0.6 or (((k - k1) % 2 == 0) and 1.0 or 1.6))
      local cur, tk = {}, {}
      for s = 1, NS do
        local fica = ant[s]
        local muda = melhor_ant - custo
        if fica >= muda then cur[s], tk[s] = fica + emis[k][s] * 6, s
        else cur[s], tk[s] = muda + emis[k][s] * 6, sb end
      end
      trilha[k] = tk
      ant = cur
      if k % 64 == 0 then pausa(0.72 + 0.1 * k / nb) end
    end
    local seq = {}
    local sb, mb = 1, -1e18
    for s = 1, NS do if ant[s] > mb then mb, sb = ant[s], s end end
    seq[nb] = sb
    for k = nb, 2, -1 do seq[k - 1] = trilha[k][seq[k]] end
    -- agrupa em acordes e decide o baixo (inversão: C/E)
    local acordes = {}
    local k = 1
    while k <= nb do
      local j = k
      while j + 1 <= nb and seq[j + 1] == seq[k] do j = j + 1 end
      local Mo = MODELOS[seq[k]]
      local bx = {}
      for p = 1, 12 do bx[p] = 0 end
      local tudo_silencio = true
      for q = k, j do
        for p = 1, 12 do bx[p] = bx[p] + baixos[q][p] end
        if not silencio[q] then tudo_silencio = false end
      end
      local pb, vb, v2 = 0, -1, -1
      for p = 1, 12 do
        if bx[p] > vb then v2 = vb; vb, pb = bx[p], p - 1 elseif bx[p] > v2 then v2 = bx[p] end
      end
      local baixo = nil
      if pb ~= Mo.raiz and vb > 1.35 * v2 then
        for _, n in ipairs(Mo.iv) do
          if n ~= 0 and (Mo.raiz + n) % 12 == pb then baixo = pb end
        end
      end
      if not tudo_silencio then
        acordes[#acordes + 1] = { k = k, t = beats[k], beats = j - k + 1, raiz = Mo.raiz, tipo = Mo.tipo, baixo = baixo,
          nome = A.nome_acorde(Mo.raiz, Mo.tipo, baixo) }
      end
      k = j + 1
    end
    -- junta acordes de 1 batida só com o vizinho (ruído)
    local limpos = {}
    for i, c in ipairs(acordes) do
      if c.beats == 1 and #limpos > 0 and i < #acordes and limpos[#limpos].nome == acordes[i + 1].nome then
        limpos[#limpos].beats = limpos[#limpos].beats + 1
      elseif #limpos > 0 and limpos[#limpos].nome == c.nome then
        limpos[#limpos].beats = limpos[#limpos].beats + c.beats
      else
        limpos[#limpos + 1] = c
      end
    end
    res.acordes = limpos
  end
  pausa(0.85)

  -- 9) seções: compassos -> matriz de semelhança -> novidade -> blocos de 4/8 compassos
  if not opcoes.sem_secoes then
    local barras = {}
    local kf = nb
    while kf > 1 and beats[kf] > res.fim_som do kf = kf - 1 end
    local b = 0
    while kmus + (b + 1) * bpb - 1 <= kf + 1 do
      local ini = kmus + b * bpb
      local cr, bx, en = {}, {}, 0
      for p = 1, 12 do cr[p] = 0; bx[p] = 0 end
      local n = 0
      for q = ini, min(nb, ini + bpb - 1) do
        for p = 1, 12 do cr[p] = cr[p] + cromas[q][p]; bx[p] = bx[p] + baixos[q][p] end
        en = en + energ[q]; n = n + 1
      end
      barras[#barras + 1] = { cr = cr, bx = bx, en = en / max(1, n), t = beats[ini] }
      b = b + 1
    end
    local Nb = #barras
    res.n_compassos = Nb
    -- v1.8: multitrack (VS) -> quais instrumentos tocam em cada compasso
    local n_at = A.atividade_compassos(opcoes.atividade, barras)
    res.stems_atividade = n_at
    if Nb >= 4 then
      local ens = {}
      for i = 1, Nb do ens[i] = barras[i].en end
      local sdE = desvio(ens)
      if sdE < 1 then sdE = 1 end
      local Sm = {}
      for i = 1, Nb do
        Sm[i] = {}
        for j = 1, Nb do
          if j < i then Sm[i][j] = Sm[j][i]
          else
            local a, bb = barras[i], barras[j]
            if n_at >= 2 then
              local d = 0
              for k = 1, n_at do d = d + abs(a.at[k] - bb.at[k]) end
              Sm[i][j] = 0.45 * cosseno(a.cr, bb.cr, 12) + 0.15 * cosseno(a.bx, bb.bx, 12)
                + 0.1 * exp(-abs(a.en - bb.en) / sdE) + 0.3 * (1 - d / n_at)
            else
              Sm[i][j] = 0.6 * cosseno(a.cr, bb.cr, 12) + 0.2 * cosseno(a.bx, bb.bx, 12)
                + 0.2 * exp(-abs(a.en - bb.en) / sdE)
            end
          end
        end
      end
      -- novidade com núcleo "tabuleiro" de 4 compassos
      local K = 4
      local nov = {}
      for bnd = 1, Nb - 1 do       -- fronteira antes do compasso bnd+1 (índice 0-based: bnd)
        local s, w = 0, 0
        for i = -K, K - 1 do
          for j = -K, K - 1 do
            local ii, jj = bnd + 1 + i, bnd + 1 + j
            if ii >= 1 and ii <= Nb and jj >= 1 and jj <= Nb then
              local g = exp(-((i + 0.5) ^ 2 + (j + 0.5) ^ 2) / (2 * (K * 0.6) ^ 2))
              local sinal = ((i < 0) == (j < 0)) and 1 or -1
              s = s + sinal * g * Sm[ii][jj]; w = w + g
            end
          end
        end
        local v = s / max(w, 1e-9)
        -- salto de energia (2 compassos antes x depois)
        local ea, eb, na, nb2 = 0, 0, 0, 0
        for q = bnd - 1, bnd do if barras[q] then ea = ea + barras[q].en; na = na + 1 end end
        for q = bnd + 1, bnd + 2 do if barras[q] then eb = eb + barras[q].en; nb2 = nb2 + 1 end end
        local de = (na > 0 and nb2 > 0) and abs(ea / na - eb / nb2) / sdE or 0
        nov[bnd] = v + 0.15 * de
      end
      -- normaliza 0..1
      local nmin, nmax = 1e9, -1e9
      for bnd = 1, Nb - 1 do nmin = min(nmin, nov[bnd]); nmax = max(nmax, nov[bnd]) end
      for bnd = 1, Nb - 1 do nov[bnd] = (nov[bnd] - nmin) / max(1e-9, nmax - nmin) end
      res.novidade = nov
      -- programação dinâmica: melhor divisão em blocos (preferindo 4/8/16 compassos)
      local PRI = { [2] = -0.6, [4] = 0.35, [6] = -0.5, [8] = 0.8, [12] = 0.1, [16] = 0.45 }
      local PEN = 0.55
      local melhor, de_onde = { [0] = 0 }, {}
      for fim = 1, Nb do
        melhor[fim] = -1e18
        for L = 1, min(fim, 32) do
          local ini = fim - L
          local base = melhor[ini]
          if base > -1e17 then
            local pr
            if fim == Nb then pr = (L >= 2) and 0.2 or -0.4     -- última: qualquer tamanho
            elseif ini == 0 then pr = PRI[L] or ((L == 1) and -0.5 or -1.2)
            else pr = PRI[L] or -1.2 end
            local nv = (fim < Nb) and nov[fim] * 1.6 or 0
            local v = base + pr + nv - PEN
            if v > melhor[fim] then melhor[fim], de_onde[fim] = v, ini end
          end
        end
      end
      local cortes = {}
      local f = Nb
      while f > 0 do table.insert(cortes, 1, de_onde[f]); f = de_onde[f] end
      local segs = {}
      for i, ini in ipairs(cortes) do
        local fim = cortes[i + 1] or Nb
        local en = 0
        for q = ini + 1, fim do en = en + barras[q].en end
        segs[#segs + 1] = { ini = ini, fim = fim, L = fim - ini, en = en / max(1, fim - ini) }
      end
      -- semelhança entre blocos (compasso a compasso, alinhado)
      local function sim(a, bq)
        local n = min(a.L, bq.L)
        local s = 0
        for i = 1, n do s = s + Sm[a.ini + i][bq.ini + i] end
        local v = s / n
        if a.L ~= bq.L then v = v - 0.04 end
        return v
      end
      local todas = {}
      for i = 1, #segs do for j = i + 1, #segs do todas[#todas + 1] = sim(segs[i], segs[j]) end end
      local lim_sim = 0.9
      if #todas > 0 then
        local p50, p90 = percentil(todas, 0.5), percentil(todas, 0.9)
        lim_sim = max(0.8, min(0.95, p50 + 0.55 * (p90 - p50)))
      end
      res.lim_sim = lim_sim
      local grupos = {}
      for i, sg in ipairs(segs) do
        local gbest, vbest = nil, -1
        for gi, g in ipairs(grupos) do
          local v = 0
          for _, mbr in ipairs(g.m) do v = max(v, sim(sg, segs[mbr])) end
          if v > vbest then vbest, gbest = v, gi end
        end
        if gbest and vbest >= lim_sim then
          sg.g = gbest; table.insert(grupos[gbest].m, i)
        else
          grupos[#grupos + 1] = { m = { i } }
          sg.g = #grupos
        end
      end
      for _, g in ipairs(grupos) do
        local e = 0
        for _, i in ipairs(g.m) do e = e + segs[i].en end
        g.en = e / #g.m
      end
      -- nomes sugeridos
      local nS = #segs
      local tipo = {}
      local repet = {}
      for gi, g in ipairs(grupos) do if #g.m >= 2 then repet[#repet + 1] = gi end end
      if nS >= 2 and segs[1].L <= 8 and (#grupos[segs[1].g].m == 1 or segs[1].en < segs[2].en - 1.5) then tipo[1] = "INTRO" end
      if nS >= 3 and segs[nS].L <= 8 and #grupos[segs[nS].g].m == 1 then tipo[nS] = "FINAL" end
      -- refrão: grupo repetido de maior energia (empate: o que aparece mais)
      local g_ref, vref = nil, -1e9
      for _, gi in ipairs(repet) do
        local g = grupos[gi]
        local v = g.en + 0.3 * #g.m
        if v > vref then vref, g_ref = v, gi end
      end
      -- verso: grupo repetido mais fraco que aparece antes do 1º refrão
      local primeiro_ref = nS + 1
      for i = 1, nS do if segs[i].g == g_ref and not tipo[i] then primeiro_ref = i; break end end
      local g_ver, ever = nil, 1e9
      for _, gi in ipairs(repet) do
        if gi ~= g_ref then
          local g = grupos[gi]
          local antes = false
          for _, i in ipairs(g.m) do if i < primeiro_ref and not tipo[i] then antes = true end end
          if antes and g.en < ever then ever, g_ver = g.en, gi end
        end
      end
      -- pré-refrão: grupo (curto) que vem logo antes dos refrões
      local g_pre = nil
      do
        local cont = {}
        for i = 2, nS do
          if segs[i].g == g_ref and not tipo[i - 1] then
            local gp = segs[i - 1].g
            if gp ~= g_ref and gp ~= g_ver and segs[i - 1].L <= 8 then cont[gp] = (cont[gp] or 0) + 1 end
          end
        end
        local mc = 0
        for gp, c in pairs(cont) do
          if c > mc and c >= 2 then mc, g_pre = c, gp end
        end
      end
      local n_ref = 0
      -- música muito repetitiva (quase tudo no mesmo grupo): as partes mais fracas viram VERSO
      local ref_max, ref_grande = -1e9, false
      if g_ref then
        for _, i in ipairs(grupos[g_ref].m) do ref_max = max(ref_max, segs[i].en) end
        -- v1.8: só quando o grupo do refrão é quase a música inteira (antes, num VS com
        -- 7 refrões de 16 blocos, os refrões mais fracos viravam "VERSO")
        ref_grande = #grupos[g_ref].m >= 4 and #grupos[g_ref].m >= 0.6 * nS
      end
      for i = 1, nS do
        if not tipo[i] then
          local g = segs[i].g
          if g == g_ref and ref_grande and segs[i].en < ref_max - 2.0 then tipo[i] = "VERSO"
          elseif g == g_ref then tipo[i] = "REFRÃO"; n_ref = n_ref + 1
          elseif g == g_ver then tipo[i] = "VERSO"
          elseif g == g_pre then tipo[i] = "PRÉ-REFRÃO"
          elseif #grupos[g].m == 1 then
            if n_ref == 0 then tipo[i] = "VERSO"
            elseif segs[i].en < (grupos[g_ref] and grupos[g_ref].en or 0) - 4 then tipo[i] = "INSTRUMENTAL"
            else tipo[i] = "PONTE" end
          else
            -- outro grupo repetido: decide pela energia
            -- v1.8: grupo que só aparece DEPOIS do 1º refrão e em blocos seguidos = PONTE
            local depois_ref, seguidos = true, true
            for idx, mbr in ipairs(grupos[g].m) do
              if mbr < primeiro_ref then depois_ref = false end
              if idx > 1 and mbr ~= grupos[g].m[idx - 1] + 1 then seguidos = false end
            end
            if g_ref and grupos[g].en >= grupos[g_ref].en - 1 then tipo[i] = "REFRÃO"
            elseif n_ref > 0 and depois_ref and seguidos then tipo[i] = "PONTE"
            else tipo[i] = "VERSO" end
          end
        end
      end
      -- numeração (VERSO 1, VERSO 2...) só onde repete
      local total, cont = {}, {}
      for i = 1, nS do total[tipo[i]] = (total[tipo[i]] or 0) + 1 end
      res.secoes = {}
      for i = 1, nS do
        local nm = tipo[i]
        if total[nm] > 1 and nm ~= "INTRO" and nm ~= "FINAL" then
          cont[nm] = (cont[nm] or 0) + 1
          nm = nm .. " " .. cont[nm]
        end
        res.secoes[i] = { compasso = segs[i].ini, compassos = segs[i].L, nome = nm, grupo = segs[i].g,
          t = barras[segs[i].ini + 1].t }
      end
    else
      res.secoes = { { compasso = 0, compassos = Nb, nome = "INTRO", t = res.downbeat } }
    end
  end
  res._bl = nil
  res._lags = nil
  pausa(1)
  return res
end

return A
