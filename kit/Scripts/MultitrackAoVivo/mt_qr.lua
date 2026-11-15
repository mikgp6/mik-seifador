-- Mik Seifador - gerador de QR Code (puro Lua 5.3+), para o "Controle pelo celular"
-- Criado por Miqueias Felix (2026). Modo byte, correção M (ou L), versões 1 a 10,
-- escolhe a melhor das 8 máscaras (regras de penalidade do padrão ISO 18004).
-- uso: local QR = dofile(dir .. "mt_qr.lua");  local mat, n = QR.gerar("http://...")
--      mat[y][x] == true -> módulo escuro (0-based: y, x de 0 a n-1)
local Q = {}

local ECC_POR_BLOCO = {
  L = { 7, 10, 15, 20, 26, 18, 20, 24, 30, 18 },
  M = { 10, 16, 26, 18, 24, 16, 18, 22, 22, 26 },
}
local BLOCOS = {
  L = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 4 },
  M = { 1, 1, 1, 2, 2, 4, 4, 4, 5, 5 },
}
local FORMATO = { L = 1, M = 0 }

local function bit(x, i) return ((x >> i) & 1) ~= 0 end

local function modulos_brutos(ver)
  local r = (16 * ver + 128) * ver + 64
  if ver >= 2 then
    local na = ver // 7 + 2
    r = r - (25 * na - 10) * na + 55
    if ver >= 7 then r = r - 36 end
  end
  return r
end

local function palavras_dados(ver, ecl)
  return modulos_brutos(ver) // 8 - ECC_POR_BLOCO[ecl][ver] * BLOCOS[ecl][ver]
end

-- GF(256) / Reed-Solomon
local function mult(x, y)
  local z = 0
  for i = 7, 0, -1 do
    z = ((z << 1) ~ ((z >> 7) * 0x11D)) & 0xFF
    if ((y >> i) & 1) ~= 0 then z = z ~ x end
  end
  return z
end

local function divisor(grau)
  local res = {}
  for i = 1, grau - 1 do res[i] = 0 end
  res[grau] = 1
  local raiz = 1
  for _ = 1, grau do
    for j = 1, grau do
      res[j] = mult(res[j], raiz)
      if j < grau then res[j] = res[j] ~ res[j + 1] end
    end
    raiz = mult(raiz, 0x02)
  end
  return res
end

local function resto(dados, div)
  local res = {}
  for i = 1, #div do res[i] = 0 end
  for _, b in ipairs(dados) do
    local fator = b ~ table.remove(res, 1)
    res[#res + 1] = 0
    for i = 1, #div do res[i] = res[i] ~ mult(div[i], fator) end
  end
  return res
end

local function posicoes_alinhamento(ver)
  if ver == 1 then return {} end
  local na = ver // 7 + 2
  local tam = ver * 4 + 17
  local passo = math.ceil((ver * 4 + 4) / (na * 2 - 2)) * 2
  local res = { 6 }
  local pos = tam - 7
  local tmp = {}
  while #tmp < na - 1 do tmp[#tmp + 1] = pos; pos = pos - passo end
  for i = #tmp, 1, -1 do res[#res + 1] = tmp[i] end
  return res
end

local function gerar_com(ver, ecl, bytes, mascara_fixa)
  local n = ver * 4 + 17
  local mod, fun = {}, {}
  for y = 0, n - 1 do mod[y] = {}; fun[y] = {}; for x = 0, n - 1 do mod[y][x] = false; fun[y][x] = false end end
  local function set(x, y, v) mod[y][x] = v; fun[y][x] = true end

  -- padrões de função
  for i = 0, n - 1 do set(6, i, i % 2 == 0); set(i, 6, i % 2 == 0) end
  local function finder(cx, cy)
    for dy = -4, 4 do for dx = -4, 4 do
      local d = math.max(math.abs(dx), math.abs(dy))
      local xx, yy = cx + dx, cy + dy
      if xx >= 0 and xx < n and yy >= 0 and yy < n then set(xx, yy, d ~= 2 and d ~= 4) end
    end end
  end
  finder(3, 3); finder(n - 4, 3); finder(3, n - 4)
  local al = posicoes_alinhamento(ver)
  local na = #al
  for i = 1, na do for j = 1, na do
    if not ((i == 1 and j == 1) or (i == 1 and j == na) or (i == na and j == 1)) then
      for dy = -2, 2 do for dx = -2, 2 do
        set(al[i] + dx, al[j] + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
      end end
    end
  end end
  local function formato(mascara)
    local dados = (FORMATO[ecl] << 3) | mascara
    local rem = dados
    for _ = 1, 10 do rem = (rem << 1) ~ ((rem >> 9) * 0x537) end
    local bits = ((dados << 10) | (rem & 0x3FF)) ~ 0x5412
    for i = 0, 5 do set(8, i, bit(bits, i)) end
    set(8, 7, bit(bits, 6)); set(8, 8, bit(bits, 7)); set(7, 8, bit(bits, 8))
    for i = 9, 14 do set(14 - i, 8, bit(bits, i)) end
    for i = 0, 7 do set(n - 1 - i, 8, bit(bits, i)) end
    for i = 8, 14 do set(8, n - 15 + i, bit(bits, i)) end
    set(8, n - 8, true)
  end
  formato(0)
  if ver >= 7 then
    local rem = ver
    for _ = 1, 12 do rem = (rem << 1) ~ ((rem >> 11) * 0x1F25) end
    local bits = (ver << 12) | (rem & 0xFFF)
    for i = 0, 17 do
      local b = bit(bits, i)
      local a, c = n - 11 + i % 3, i // 3
      set(a, c, b); set(c, a, b)
    end
  end

  -- dados: modo byte
  local bb = {}
  local function add(v, len) for i = len - 1, 0, -1 do bb[#bb + 1] = ((v >> i) & 1) end end
  add(4, 4)
  add(#bytes, ver <= 9 and 8 or 16)
  for _, b in ipairs(bytes) do add(b, 8) end
  local cap = palavras_dados(ver, ecl) * 8
  for _ = 1, math.min(4, cap - #bb) do bb[#bb + 1] = 0 end
  while #bb % 8 ~= 0 do bb[#bb + 1] = 0 end
  local dados = {}
  for i = 1, #bb, 8 do
    local v = 0
    for k = 0, 7 do v = (v << 1) | bb[i + k] end
    dados[#dados + 1] = v
  end
  local pad = 0xEC
  while #dados < palavras_dados(ver, ecl) do dados[#dados + 1] = pad; pad = (pad == 0xEC) and 0x11 or 0xEC end

  -- blocos + ECC + intercalação
  local nb, ecl_len = BLOCOS[ecl][ver], ECC_POR_BLOCO[ecl][ver]
  local brutos = modulos_brutos(ver) // 8
  local curtos = nb - brutos % nb
  local tam_curto = brutos // nb
  local div = divisor(ecl_len)
  local blocos, k = {}, 1
  for i = 0, nb - 1 do
    local len = tam_curto - ecl_len + ((i < curtos) and 0 or 1)
    local dat = {}
    for j = 0, len - 1 do dat[#dat + 1] = dados[k + j] end
    k = k + len
    local ecc = resto(dat, div)
    if i < curtos then dat[#dat + 1] = -1 end
    for _, e in ipairs(ecc) do dat[#dat + 1] = e end
    blocos[#blocos + 1] = dat
  end
  local final = {}
  for i = 1, #blocos[1] do
    for j = 1, #blocos do
      if i ~= tam_curto - ecl_len + 1 or (j - 1) >= curtos then final[#final + 1] = blocos[j][i] end
    end
  end

  -- desenha os códigos (zigue-zague)
  local i = 0
  local total = #final * 8
  local direita = n - 1
  while direita >= 1 do
    if direita == 6 then direita = 5 end
    for vert = 0, n - 1 do
      for j = 0, 1 do
        local x = direita - j
        local subindo = ((direita + 1) & 2) == 0
        local y = subindo and (n - 1 - vert) or vert
        if not fun[y][x] and i < total then
          mod[y][x] = bit(final[(i >> 3) + 1], 7 - (i & 7))
          i = i + 1
        end
      end
    end
    direita = direita - 2
  end

  local MASC = {
    [0] = function(x, y) return (x + y) % 2 == 0 end,
    function(x, y) return y % 2 == 0 end,
    function(x, y) return x % 3 == 0 end,
    function(x, y) return (x + y) % 3 == 0 end,
    function(x, y) return (x // 3 + y // 2) % 2 == 0 end,
    function(x, y) return x * y % 2 + x * y % 3 == 0 end,
    function(x, y) return (x * y % 2 + x * y % 3) % 2 == 0 end,
    function(x, y) return ((x + y) % 2 + x * y % 3) % 2 == 0 end,
  }
  local function aplicar(m)
    local f = MASC[m]
    for y = 0, n - 1 do for x = 0, n - 1 do
      if not fun[y][x] and f(x, y) then mod[y][x] = not mod[y][x] end
    end end
  end
  local function penalidade()
    local p = 0
    local escuros = 0
    local function linha(get)
      local corrida, cor_ant = 0, nil
      local seq = {}
      for i2 = 0, n - 1 do
        local c = get(i2)
        seq[#seq + 1] = c and 1 or 0
        if c == cor_ant then corrida = corrida + 1
        else
          if corrida >= 5 then p = p + 3 + (corrida - 5) end
          corrida, cor_ant = 1, c
        end
      end
      if corrida >= 5 then p = p + 3 + (corrida - 5) end
      local s = table.concat(seq)
      local a, b = "10111010000", "00001011101"
      for ini = 1, #s - 10 do
        local sub = s:sub(ini, ini + 10)
        if sub == a or sub == b then p = p + 40 end
      end
    end
    for y = 0, n - 1 do linha(function(x) return mod[y][x] end) end
    for x = 0, n - 1 do linha(function(y) return mod[y][x] end) end
    for y = 0, n - 2 do for x = 0, n - 2 do
      local c = mod[y][x]
      if c == mod[y][x + 1] and c == mod[y + 1][x] and c == mod[y + 1][x + 1] then p = p + 3 end
    end end
    for y = 0, n - 1 do for x = 0, n - 1 do if mod[y][x] then escuros = escuros + 1 end end end
    local pct = escuros * 100 / (n * n)
    p = p + 10 * (math.floor(math.abs(pct - 50) / 5))
    return p
  end

  local melhor = mascara_fixa
  if not melhor then
    local menor = math.huge
    for m = 0, 7 do
      aplicar(m); formato(m)
      local pen = penalidade()
      if pen < menor then menor, melhor = pen, m end
      aplicar(m)   -- desfaz (XOR)
    end
  end
  aplicar(melhor); formato(melhor)
  return mod, n, melhor
end

-- texto -> matriz. ecl = "M" (padrão) ou "L". Devolve nil se não couber (até versão 10).
function Q.gerar(texto, ecl, mascara, versao_min)
  ecl = ecl or "M"
  local bytes = { texto:byte(1, -1) }
  for ver = (versao_min or 1), 10 do
    local bits = 4 + (ver <= 9 and 8 or 16) + 8 * #bytes
    if bits <= palavras_dados(ver, ecl) * 8 then
      local mat, n, m = gerar_com(ver, ecl, bytes, mascara)
      return mat, n, ver, m
    end
  end
  if ecl == "M" then return Q.gerar(texto, "L", mascara) end
  return nil
end

return Q
