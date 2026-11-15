-- Mik Seifador - atualização automática (mt_atualizar.lua)
-- Criado por Miqueias Felix (2026)
--[[
  Procura uma build nova no GitHub (mikgp6/mik-seifador) e, se o usuário
  clicar em "Atualizar", baixa só os arquivos que mudaram, confere o SHA-256,
  faz backup em MultitrackAoVivo\_backups\update-<data>, troca e recarrega o
  painel/motor. Sem internet: ignora em silêncio. A versão mostrada continua
  sendo M.VERSAO (1.8); a BUILD é só um número interno (build.txt).

  Tudo roda sem travar a interface: o trabalho fica numa coroutine que o
  painel avança um pouco a cada quadro (U.tick()). Downloads rodam em
  segundo plano (Windows: wscript + curl.exe oculto, sem janela; Mac: curl).
]]
return function(M)
local r = reaper
local SEP = M.SEP or package.config:sub(1, 1)
local U = {}

U.REPO = "mikgp6/mik-seifador"
U.URL_PADRAO = "https://raw.githubusercontent.com/" .. U.REPO .. "/"
U.REF_PADRAO = "main"
U.INTERVALO = 20 * 3600     -- no máximo 1 verificação automática por dia
U.ATRASO_INICIO = 6         -- segundos depois de abrir o painel
U.TIMEOUT_MANIFEST = 40
U.TIMEOUT_ARQUIVOS = 600

-------------------------------------------------------------------------------
-- caminhos
-------------------------------------------------------------------------------
local function raiz() return U.raiz_teste or r.GetResourcePath() end
local function kit_dir() return raiz() .. SEP .. "Scripts" .. SEP .. "MultitrackAoVivo" end
local function nativo(p) if SEP == "\\" then return (p:gsub("/", "\\")) end return p end
local function trabalho() return kit_dir() .. SEP .. "_atualizacao" end
local function existe(p) local f = io.open(p, "rb"); if f then f:close(); return true end; return false end
local function ler(p) local f = io.open(p, "rb"); if not f then return nil end; local d = f:read("a"); f:close(); return d end
local function gravar(p, d) local f = io.open(p, "wb"); if not f then return false end; f:write(d); f:close(); return true end
local function mkdir(p) if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(p, 0) end end
local function dir_de(p) return p:match("^(.*)[\\/][^\\/]+$") end

function U.url_base()
  local u = M.get and M.get("UPD_URL", "") or ""
  if u == "" then u = U.URL_PADRAO end
  if u:sub(-1) ~= "/" then u = u .. "/" end
  return u
end

-------------------------------------------------------------------------------
-- build local
-------------------------------------------------------------------------------
local _build_cache = nil
function U.build_local()
  if _build_cache then return _build_cache end
  local d = ler(kit_dir() .. SEP .. "build.txt")
  local n = d and tonumber(d:match("(%d+)"))
  _build_cache = n or tonumber(M.BUILD) or 0
  return _build_cache
end
function U.esquecer_build() _build_cache = nil end

-------------------------------------------------------------------------------
-- SHA-256 (Lua 5.3/5.4, incremental: cede a vez a cada pedaço)
-------------------------------------------------------------------------------
local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2 }
local M32 = 0xffffffff
local function rotr(x, n) return ((x >> n) | (x << (32 - n))) & M32 end
local function bloco(H, s, p, w)
  for j = 0, 15 do
    local a, b, c, d = s:byte(p + j * 4, p + j * 4 + 3)
    w[j] = (a << 24) | (b << 16) | (c << 8) | d
  end
  for j = 16, 63 do
    local v15, v2 = w[j - 15], w[j - 2]
    local s0 = rotr(v15, 7) ~ rotr(v15, 18) ~ (v15 >> 3)
    local s1 = rotr(v2, 17) ~ rotr(v2, 19) ~ (v2 >> 10)
    w[j] = (w[j - 16] + s0 + w[j - 7] + s1) & M32
  end
  local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
  for j = 0, 63 do
    local S1 = rotr(e, 6) ~ rotr(e, 11) ~ rotr(e, 25)
    local ch = (e & f) ~ ((~e) & g)
    local t1 = (h + S1 + ch + K[j + 1] + w[j]) & M32
    local S0 = rotr(a, 2) ~ rotr(a, 13) ~ rotr(a, 22)
    local maj = (a & b) ~ (a & c) ~ (b & c)
    local t2 = (S0 + maj) & M32
    h, g, f, e, d, c, b, a = g, f, e, (d + t1) & M32, c, b, a, (t1 + t2) & M32
  end
  H[1] = (H[1] + a) & M32; H[2] = (H[2] + b) & M32; H[3] = (H[3] + c) & M32; H[4] = (H[4] + d) & M32
  H[5] = (H[5] + e) & M32; H[6] = (H[6] + f) & M32; H[7] = (H[7] + g) & M32; H[8] = (H[8] + h) & M32
end
-- ceder(): chamada a cada ~64 KB (dentro da coroutine faz yield)
function U.sha256(s, ceder)
  local H = { 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19 }
  local n = #s
  local resto = 64 - ((n + 9) % 64); if resto == 64 then resto = 0 end
  local cauda_ini = n - (n % 64) + 1
  local cauda = s:sub(cauda_ini) .. "\128" .. string.rep("\0", resto) .. string.pack(">I8", n * 8)
  local w = {}
  local p, cont = 1, 0
  while p + 63 <= n do
    bloco(H, s, p, w); p = p + 64; cont = cont + 1
    if ceder and cont % 256 == 0 then ceder() end
  end
  local q = 1
  while q <= #cauda do bloco(H, cauda, q, w); q = q + 64 end
  return string.format("%08x%08x%08x%08x%08x%08x%08x%08x", H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end

-------------------------------------------------------------------------------
-- JSON (só o necessário para o manifest)
-------------------------------------------------------------------------------
local function utf8c(c) return utf8.char(c) end
function U.json(s)
  local i = 1
  if s:sub(1, 3) == "\239\187\191" then i = 4 end
  local function ws() i = s:find("[^ \t\r\n]", i) or (#s + 1) end
  local val
  local function str()
    i = i + 1
    local out = {}
    while true do
      local c = s:sub(i, i)
      if c == "" then error("json: string aberta") end
      if c == '"' then i = i + 1; break end
      if c == "\\" then
        local e = s:sub(i + 1, i + 1)
        if e == "u" then
          local cp = tonumber(s:sub(i + 2, i + 5), 16); i = i + 6
          if cp >= 0xD800 and cp <= 0xDBFF and s:sub(i, i + 1) == "\\u" then
            local lo = tonumber(s:sub(i + 2, i + 5), 16); i = i + 6
            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00)
          end
          out[#out + 1] = utf8c(cp)
        else
          local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" }
          out[#out + 1] = map[e] or e; i = i + 2
        end
      else
        local j = s:find('["\\]', i) or (#s + 1)
        out[#out + 1] = s:sub(i, j - 1); i = j
      end
    end
    return table.concat(out)
  end
  val = function()
    ws()
    local c = s:sub(i, i)
    if c == "{" then
      local t = {}; i = i + 1; ws()
      if s:sub(i, i) == "}" then i = i + 1; return t end
      while true do
        ws(); local k = str(); ws()
        if s:sub(i, i) ~= ":" then error("json: esperava :") end
        i = i + 1; t[k] = val(); ws()
        local d = s:sub(i, i); i = i + 1
        if d == "}" then return t end
        if d ~= "," then error("json: esperava , ou }") end
      end
    elseif c == "[" then
      local t = {}; i = i + 1; ws()
      if s:sub(i, i) == "]" then i = i + 1; return t end
      while true do
        t[#t + 1] = val(); ws()
        local d = s:sub(i, i); i = i + 1
        if d == "]" then return t end
        if d ~= "," then error("json: esperava , ou ]") end
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
      if not num or num == "" then error("json: valor inválido em " .. i) end
      i = i + #num; return tonumber(num)
    end
  end
  return val()
end

-------------------------------------------------------------------------------
-- downloads em segundo plano (sem janela)
-------------------------------------------------------------------------------
local function url_cod(caminho)
  return (caminho:gsub("[^%w%-%._~/]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function utf16le(s)
  local t = {}
  for _, cp in utf8.codes(s) do
    if cp >= 0x10000 then
      cp = cp - 0x10000
      t[#t + 1] = string.pack("<I2I2", 0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF))
    else
      t[#t + 1] = string.pack("<I2", cp)
    end
  end
  return table.concat(t)
end
local BAIXAR_JS = [[
// Mik Seifador - baixa a lista (UTF-16: url<TAB>destino) com curl.exe oculto
var a = WScript.Arguments, sh = new ActiveXObject("WScript.Shell");
var fso = new ActiveXObject("Scripting.FileSystemObject");
var lista = a(0), erro = "";
var f = fso.OpenTextFile(lista, 1, false, -1), linhas = [];
while (!f.AtEndOfStream) { var l = f.ReadLine(); if (l.length > 0) linhas.push(l); }
f.Close();
for (var i = 0; i < linhas.length && erro == ""; i++) {
  var p = linhas[i].split("\t"), url = p[0], dst = p[1];
  var rc = sh.Run('curl.exe -fsSL --retry 2 --connect-timeout 15 --max-time 300 -o "' + dst + '.part" "' + url + '"', 0, true);
  if (rc != 0) { erro = "curl=" + rc + " " + url; break; }
  if (fso.FileExists(dst)) fso.DeleteFile(dst);
  fso.MoveFile(dst + ".part", dst);
}
var o = fso.CreateTextFile(lista + ".fim", true, true);
o.WriteLine(erro == "" ? "ok" : ("erro " + erro)); o.Close();
]]

-- dispara o download da lista {{url, destino}, ...}; devolve o caminho do .fim
local seq = 0
local function baixar_lista(itens)
  local w = trabalho(); mkdir(w)
  seq = seq + 1
  local id = string.format("lista_%d_%d", os.time(), seq)
  local lista = w .. SEP .. id .. ".txt"
  local fim = lista .. ".fim"
  os.remove(fim)
  if M.EH_WIN then
    local js = w .. SEP .. "baixar.js"
    if ler(js) ~= BAIXAR_JS then gravar(js, BAIXAR_JS) end
    local t = {}
    for _, it in ipairs(itens) do t[#t + 1] = it[1] .. "\t" .. nativo(it[2]) .. "\r\n" end
    gravar(lista, "\255\254" .. utf16le(table.concat(t)))
    r.ExecProcess('wscript.exe //B //Nologo "' .. js .. '" "' .. lista .. '"', -1)
  else
    local sh = { "#!/bin/sh", "erro=''" }
    local function q(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
    for _, it in ipairs(itens) do
      sh[#sh + 1] = 'if [ -z "$erro" ]; then /usr/bin/curl -fsSL --retry 2 --connect-timeout 15 --max-time 300 -o ' ..
        q(it[2] .. ".part") .. " " .. q(it[1]) .. " && mv -f " .. q(it[2] .. ".part") .. " " .. q(it[2]) ..
        " || erro=" .. q("curl " .. it[1]) .. "; fi"
    end
    sh[#sh + 1] = 'if [ -z "$erro" ]; then echo ok > ' .. q(fim .. ".tmp") .. '; else echo "erro $erro" > ' .. q(fim .. ".tmp") .. "; fi"
    sh[#sh + 1] = "mv -f " .. q(fim .. ".tmp") .. " " .. q(fim)
    gravar(lista .. ".sh", table.concat(sh, "\n") .. "\n")
    r.ExecProcess('/bin/sh "' .. lista .. '.sh"', -1)
  end
  return fim, lista
end

-- resultado do .fim (UTF-16 no Windows, texto no Mac); nil = ainda baixando
local function ler_fim(fim)
  local d = ler(fim)
  if not d or d == "" then return nil end
  if d:sub(1, 2) == "\255\254" then d = d:sub(3):gsub("(.)%z", "%1") end
  d = d:gsub("%z", "")
  if d:match("^%s*ok") then return true end
  if d:match("erro") then return false, (d:gsub("%s+$", "")) end
  return nil
end

-------------------------------------------------------------------------------
-- estado + coroutine
-------------------------------------------------------------------------------
U.estado = {
  ocupado = false, fase = nil, progresso = nil,
  remota = tonumber(M.get and M.get("UPD_REMOTA", "") or "") or nil,
  notas = M.get and M.get("UPD_NOTAS", "") or "",
  manifest = nil, ultimo_erro = nil, resultado = nil,
}
local co = nil
local t_abriu = r.time_precise()

local function avisar(txt)
  U.ultima_msg = txt
  if U.ao_avisar then pcall(U.ao_avisar, txt) elseif M.aviso then pcall(M.aviso, txt) end
end
local function ceder() coroutine.yield() end
local function esperar(fim, timeout)
  local t0 = r.time_precise()
  while true do
    local ok, err = ler_fim(fim)
    if ok ~= nil then return ok, err end
    if r.time_precise() - t0 > timeout then return false, "tempo esgotado" end
    coroutine.yield()
  end
end
local function limpar_trabalho()
  local w = trabalho()
  local nomes, i = {}, 0
  while true do
    local f = r.EnumerateFiles(w, i)
    if not f then break end
    nomes[#nomes + 1] = f
    i = i + 1
  end
  for _, f in ipairs(nomes) do
    if f ~= "baixar.js" and f ~= "relancar.lua" then os.remove(w .. SEP .. f) end
  end
end

-- baixa e lê o manifest remoto
local function obter_manifest()
  local w = trabalho(); mkdir(w)
  local dst = w .. SEP .. "manifest_remoto.json"
  os.remove(dst)
  local url = U.url_base() .. U.REF_PADRAO .. "/manifest.json?t=" .. tostring(os.time())
  local fim, lista = baixar_lista({ { url, dst } })
  local ok, err = esperar(fim, U.TIMEOUT_MANIFEST)
  os.remove(fim); os.remove(lista); os.remove(lista .. ".sh")
  if not ok then return nil, err end
  local d = ler(dst)
  if not d then return nil, "manifest vazio" end
  local okj, man = pcall(U.json, d)
  if not okj or type(man) ~= "table" or not tonumber(man.build) or type(man.arquivos) ~= "table" then
    return nil, "manifest inválido"
  end
  man.build = tonumber(man.build)
  man._bruto = d
  return man
end

local function marcar_remota(man)
  U.estado.remota = man.build
  U.estado.notas = man.notas or ""
  U.estado.manifest = man
  if M.set then
    M.set("UPD_REMOTA", tostring(man.build))
    M.set("UPD_NOTAS", (tostring(man.notas or "")):gsub("[\r\n]+", " "))
  end
end

local function job_verificar(manual)
  local man, err = obter_manifest()
  if not man then
    U.estado.ultimo_erro = err
    if manual then avisar("Não consegui procurar atualizações (sem internet?)") end
    return
  end
  marcar_remota(man)
  if M.set then M.set("UPD_ULTIMA", tostring(os.time())) end
  local loc = U.build_local()
  if man.build > loc then
    avisar("Atualização disponível (build " .. man.build .. ")")
  elseif manual then
    avisar("Você já tem a versão mais nova (v" .. tostring(M.VERSAO) .. ", build " .. loc .. ")")
  end
end

-- lê o manifest local (instalado) para não precisar recalcular tudo
local function manifest_local()
  local d = ler(kit_dir() .. SEP .. "atualizacao_local.json")
  if not d then return {} end
  local ok, man = pcall(U.json, d)
  local t = {}
  if ok and type(man) == "table" and type(man.arquivos) == "table" then
    for _, a in ipairs(man.arquivos) do if a.caminho then t[a.caminho] = a end end
  end
  return t
end

local function tamanho(p)
  local f = io.open(p, "rb"); if not f then return nil end
  local n = f:seek("end"); f:close(); return n
end

local function copiar(de, para)
  local d = ler(de); if not d then return false end
  mkdir(dir_de(para))
  return gravar(para, d)
end

local function job_atualizar()
  local est = U.estado
  est.fase = "Procurando..."
  local man, err = obter_manifest()
  if not man then
    avisar("Atualização: não consegui baixar a lista (" .. tostring(err) .. "). Nada foi trocado.")
    return
  end
  marcar_remota(man)
  local loc = U.build_local()
  if man.build <= loc and not U.forcar then
    avisar("Você já tem a versão mais nova (build " .. loc .. ")")
    return
  end
  -- 1) quais arquivos mudaram
  est.fase = "Conferindo arquivos..."
  local antigo = manifest_local()
  local mudou = {}
  for idx, a in ipairs(man.arquivos) do
    local cam = tostring(a.caminho or "")
    -- segurança: só caminhos relativos dentro da pasta do REAPER
    if cam == "" or cam:find("%.%.") or cam:match("^[/\\]") or cam:match("^%a:") then
      avisar("Atualização: caminho inválido na lista. Nada foi trocado."); return
    end
    local dest = raiz() .. SEP .. nativo(cam)
    local tam = tamanho(dest)
    local igual = false
    if tam and tam == tonumber(a.tamanho) then
      local al = antigo[cam]
      if al and al.sha256 == a.sha256 then igual = true
      else
        local d = ler(dest)
        igual = d and U.sha256(d, ceder) == a.sha256
      end
    end
    if not igual then mudou[#mudou + 1] = { a = a, dest = dest } end
    est.progresso = string.format("%d/%d", idx, #man.arquivos)
    if idx % 8 == 0 then coroutine.yield() end
  end
  -- 2) baixa só os que mudaram (em nomes ASCII na pasta de trabalho)
  local w = trabalho(); mkdir(w)
  local ref = (type(man.ref) == "string" and man.ref:match("^[%w%._%-]+$")) and man.ref or U.REF_PADRAO
  if #mudou > 0 then
    est.fase = "Baixando " .. #mudou .. " arquivo(s)..."
    local itens = {}
    for i, m in ipairs(mudou) do
      m.tmp = w .. SEP .. string.format("n%03d.bin", i)
      os.remove(m.tmp)
      itens[#itens + 1] = { U.url_base() .. ref .. "/kit/" .. url_cod(m.a.caminho), m.tmp }
    end
    local fim, lista = baixar_lista(itens)
    local ok, e2 = esperar(fim, U.TIMEOUT_ARQUIVOS)
    os.remove(fim); os.remove(lista); os.remove(lista .. ".sh")
    if not ok then
      limpar_trabalho()
      avisar("Atualização falhou ao baixar (" .. tostring(e2) .. "). Nada foi trocado.")
      return
    end
    -- 3) confere SHA-256 e (Lua) a sintaxe
    est.fase = "Conferindo SHA-256..."
    for _, m in ipairs(mudou) do
      local d = ler(m.tmp)
      if not d or #d ~= tonumber(m.a.tamanho) or U.sha256(d, ceder) ~= m.a.sha256 then
        limpar_trabalho()
        avisar("Atualização: arquivo corrompido (" .. m.a.caminho .. "). Nada foi trocado.")
        return
      end
      if m.a.caminho:match("%.lua$") then
        local f, e3 = load(d, "=" .. m.a.caminho)
        if not f then
          limpar_trabalho()
          avisar("Atualização: script com erro (" .. m.a.caminho .. "). Nada foi trocado.")
          M.registrar_erro("atualizar", e3)
          return
        end
      end
      coroutine.yield()
    end
    -- 4) backup dos arquivos atuais
    est.fase = "Backup..."
    local bk = kit_dir() .. SEP .. "_backups" .. SEP .. "update-" .. os.date("%Y%m%d-%H%M%S") .. "-build" .. loc
    mkdir(bk)
    for _, m in ipairs(mudou) do
      if existe(m.dest) then
        if not copiar(m.dest, bk .. SEP .. nativo(m.a.caminho)) then
          limpar_trabalho()
          avisar("Atualização: não consegui fazer o backup. Nada foi trocado.")
          return
        end
      end
    end
    gravar(bk .. SEP .. "build.txt", tostring(loc) .. "\n")
    est.backup = bk
    -- 5) troca (com volta atrás se algo falhar)
    est.fase = "Instalando..."
    local feitos, falhou = {}, nil
    for _, m in ipairs(mudou) do
      mkdir(dir_de(m.dest))
      local velho = m.dest .. ".upd-old"
      os.remove(velho)
      local tinha = existe(m.dest)
      if tinha and not os.rename(m.dest, velho) then falhou = m; break end
      if not os.rename(m.tmp, m.dest) then
        if tinha then os.rename(velho, m.dest) end
        falhou = m; break
      end
      feitos[#feitos + 1] = { m = m, velho = tinha and velho or nil }
    end
    if falhou then
      for i = #feitos, 1, -1 do
        local f = feitos[i]
        os.remove(f.m.dest)
        if f.velho then os.rename(f.velho, f.m.dest) end
      end
      limpar_trabalho()
      avisar("Atualização: não consegui trocar " .. falhou.a.caminho .. " (arquivo em uso?). Nada foi trocado.")
      return
    end
    for _, f in ipairs(feitos) do if f.velho then os.remove(f.velho) end end
  end
  -- 6) registra a build nova
  gravar(kit_dir() .. SEP .. "build.txt", tostring(man.build) .. "\n")
  U.esquecer_build()
  gravar(kit_dir() .. SEP .. "atualizacao_local.json", man._bruto)
  limpar_trabalho()
  est.resultado = { build = man.build, arquivos = #mudou, backup = est.backup }
  if M.set then M.set("UPD_INSTALADA", tostring(man.build)) end
  avisar("Mik Seifador atualizado (build " .. man.build .. ", " .. #mudou .. " arquivo(s)). Recarregando...")
  if not U.sem_recarregar then U.recarregar() end
end

-------------------------------------------------------------------------------
-- recarregar painel e motor (script auxiliar: desliga e liga de novo)
-------------------------------------------------------------------------------
local RELANCAR = [[
-- Mik Seifador: recarrega painel e motor depois da atualização (gerado)
local r = reaper
local kit = r.GetResourcePath() .. "/Scripts/MultitrackAoVivo/"
local function id_de(nome, arq)
  local id = r.NamedCommandLookup(nome)
  if not id or id == 0 then id = r.AddRemoveReaScript(true, 0, kit .. arq, true) end
  return id or 0
end
local painel = id_de("_MT_PAINEL", "painel_ao_vivo.lua")
local motor = id_de("_MT_MOTOR", "motor_ao_vivo.lua")
local motor_ligado = motor ~= 0 and r.GetToggleCommandState(motor) == 1
-- painel e motor usam set_action_options(1|2): rodar de novo = fecha e reabre
-- já lendo os arquivos novos do disco.
local n = 0
local function conferir()
  n = n + 1
  if n < 30 then return r.defer(conferir) end
  local hb = tonumber(r.GetExtState("MT_AO_VIVO", "PAINEL_HB")) or 0
  if painel ~= 0 and r.time_precise() - hb > 2 then r.Main_OnCommand(painel, 0) end
end
r.defer(function()
  if motor_ligado then r.Main_OnCommand(motor, 0) end
  if painel ~= 0 then r.Main_OnCommand(painel, 0) end
  r.defer(conferir)
end)
]]
function U.recarregar()
  local p = kit_dir() .. SEP .. "_atualizacao" .. SEP .. "relancar.lua"
  mkdir(dir_de(p))
  gravar(p, RELANCAR)
  local id = r.AddRemoveReaScript(true, 0, p, true)
  if id and id ~= 0 then
    r.Main_OnCommand(id, 0)
    return true
  end
  return false
end

-------------------------------------------------------------------------------
-- API para o painel
-------------------------------------------------------------------------------
local function iniciar(fn, ...)
  if co then return false end
  local args = table.pack(...)
  U.estado.ocupado = true
  co = coroutine.create(function() fn(table.unpack(args, 1, args.n)) end)
  return true
end

function U.procurar(manual)
  return iniciar(job_verificar, manual)
end

function U.atualizar()
  return iniciar(job_atualizar)
end

-- build remota maior que a local? devolve a build (ou nil)
function U.disponivel()
  local rem = U.estado.remota
  if rem and rem > U.build_local() then return rem end
  return nil
end

function U.tick()
  if co then
    local ok, err = coroutine.resume(co)
    if not ok then
      co = nil
      U.estado.ocupado, U.estado.fase, U.estado.progresso = false, nil, nil
      pcall(M.registrar_erro, "atualizar", err)
      avisar("Atualização: erro inesperado. Nada foi trocado.")
    elseif coroutine.status(co) == "dead" then
      co = nil
      U.estado.ocupado, U.estado.fase, U.estado.progresso = false, nil, nil
    end
    return
  end
  -- verificação automática: no máximo 1x por dia, alguns segundos depois de abrir
  if not U._auto_feita and r.time_precise() - t_abriu > U.ATRASO_INICIO then
    U._auto_feita = true
    if (M.get and M.get("UPD_AUTO", "1") or "1") ~= "0" then
      local ult = tonumber(M.get and M.get("UPD_ULTIMA", "0") or "0") or 0
      if os.time() - ult >= U.INTERVALO then U.procurar(false) end
    end
  end
end

-- para testes: roda um job até o fim com um laço de defer
function U._rodar_teste(fn, ao_fim)
  iniciar(fn == "atualizar" and job_atualizar or job_verificar, false)
  local function passo()
    U.tick()
    if co then r.defer(passo) elseif ao_fim then ao_fim() end
  end
  r.defer(passo)
end

return U
end
