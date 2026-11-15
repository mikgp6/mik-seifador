-- Mik Seifador - player de multitracks ao vivo para REAPER
-- Criado por Miqueias Felix (2026)
--[[
  Mik Seifador (Multitrack Ao Vivo) - biblioteca principal (mt_lib.lua)
  ------------------------------------------------------------------
  Todos os scripts desta pasta carregam este arquivo. NÃO execute ele
  diretamente pelo Action List (ele só define funções).

  Conceitos usados:
    * MÚSICA  = uma REGIÃO do REAPER (nome da música + tom entre colchetes,
                ex.: "Ousado Amor [Bb]").
    * SEÇÃO   = um MARCADOR dentro da região da música (I1, V1, P1, R1,
                Re2, PONTE, FINAL...). A seção vai do marcador até o
                próximo marcador (ou até o fim da música).
    * Estados (AUTO, HOLD, LOOP...) ficam guardados em ExtState
                (seção "MT_AO_VIVO") e valem para qualquer projeto.

  Requer só a API nativa do REAPER (v6.x/7.x). ReaImGui é usado apenas no
  painel; js_ReaScriptAPI (opcional) habilita escolher vários arquivos no
  IMPORTAR e a janela "escolher pasta" no avançado.
]]

local r = reaper
local M = {}

M.SEC = "MT_AO_VIVO"
M.VERSAO = "1.8"          -- versão ÚNICA do kit (painel, título e "Sobre" usam esta)
M.BUILD = 1                -- build interna (só p/ atualização automática; a real fica em build.txt)
-- Novidades desta versão (aparecem em Menu > Novidades / Sobre)
M.NOVIDADES = {
  "MULTITRACK: CLICK E GUIA SEMPRE PRESENTES. Ao importar ou analisar, o kit vê se a",
  "  multitrack já tem Click (click, clic, metrônomo, metro, CLK) e Guia (guia, guide,",
  "  cues, guide voice, vocal guide). O que vier nela fica; o que faltar o kit gera: click",
  "  na música inteira seguindo o mapa de tempo e guia falada com contagem 1-2-3-4 e",
  "  todas as seções (Verso 2, Refrão 3, Ponte…), no FONE. Reanalisar não duplica.",
  "CONTROLE PELO CELULAR (Mik Seifador Remoto): Android e iPhone controlam o painel",
  "  em tempo real, com a mesma cara do PC: setlist com capas, seções, transporte,",
  "  tom, BPM, modos L/R / Ao Vivo / Studio, faders 3D com medidores, mute, solo, pan,",
  "  PAD, AUTO/HOLD/LOOP, barra de separação e as ações do Menu. Menu > Controle pelo",
  "  celular… liga a interface web do REAPER e mostra o endereço e o QR code.",
  "+ IMPORTAR SERVE PARA AS DUAS COISAS: ao clicar, escolha Música(s) (um ou vários",
  "  arquivos) ou Multitrack / VS (a PASTA, ou os stems dela). Se você escolher vários",
  "  arquivos da mesma pasta com cara de stems, o kit pergunta: UMA multitrack ou",
  "  cada arquivo como uma música. A escolha fica salva na Biblioteca.",
  "MULTITRACK (VS) COM SEÇÕES: a análise agora ouve a MISTURA dos stems (sem click,",
  "  guia e cover/referência) e vê quais instrumentos entram em cada parte. Multitrack",
  "  importada sem seções já é analisada sozinha. Se a música já tiver seções, o Menu",
  "  > Gerar click + guia + seções pergunta se você quer refazê-las.",
  "MUTE DO MASTER: o botão M do MASTER agora muta e desmuta (antes só mutava).",
  "FADERS 3D (estilo console): botão com relevo e frisos, trilho afundado, escala",
  "  em dB (+12 a -inf), medidor em segmentos verde/amarelo/vermelho e valor embaixo.",
  "  Duplo clique ou Ctrl/Alt + clique (Cmd no Mac) = 0 dB; Shift = ajuste fino.",
  "PAD CONTÍNUO (padrão): use seus pads longos, um por tom (C-PAD, G-PAD…).",
  "  Menu (ou botão direito no PAD) > Importar pasta de pads… copia a pasta para a Biblioteca.",
  "  O item cobre a música inteira, em loop, com fade de entrada e saída.",
  "  Também há o Pad clássico (MIDI/ReaSynth) se você preferir o som antigo.",
  "GUIA FALADA NOVA: voz gravada em português, clara (contagem 1-2-3-4 e os nomes",
  "  das seções, inclusive numeradas: Verso 3, Refrão 2, Pré-refrão…). Se não houver",
  "  o número, usa a versão simples (Verso 7 -> Verso). Sinais extras (Entra Bateria,",
  "  Todos Juntos, Repete…) tocam se o marcador tiver o mesmo nome. minha_voz continua",
  "  valendo se você gravar a sua.",
  "PAINEL REDESENHADO: visual mais profissional (tema escuro, botões arredondados,",
  "  ícones desenhados e um visor de tempo/BPM/tom no estilo de transporte de estúdio).",
  "  Todas as funções continuam no mesmo lugar (IMPORTAR, Biblioteca, Limpar, modos, fila).",
  "  A barra de título tem Minimizar, Maximizar/Restaurar e Fechar (como no Windows).",
  "  Dicas menores, com um tempinho antes de aparecer, e só as 3 primeiras vezes",
  "  em cada botão. Menu > Desligar dicas, ou Mostrar dicas de novo para recomeçar.",
  "BARRA DE PROGRESSO: ao separar trilhas ou analisar, uma barrinha no topo do painel",
  "  (ao lado do visor, embaixo dos botões L/R…Menu) vai do vermelho ao verde e mostra",
  "  a porcentagem embaixo (ex.: Separando: Nome — 31%). Se houver fila, aparece 2 de 5.",
  "  Se você fechar e abrir o painel (F9) no meio da separação, a barra reaparece.",
  "SEPARAÇÃO RÁPIDA: Menu > Separação rápida (~15% mais rápida, qualidade um pouco menor).",
  "  Desligada por padrão (qualidade normal). Quando ligada, a barrinha mostra “Separando (rápida)”.",
  "IMPORTAR: se você escolhe ou arrasta UMA música de uma pasta com várias músicas",
  "  completas (cada arquivo é uma música, ex.: pasta de casamento), entra SÓ ela.",
  "  Os irmãos não vêm junto — inclusive se a pasta já estiver dentro da Biblioteca",
  "  (Documentos/Multitracks) e tiver um mt_info.txt antigo. A pasta só é uma",
  "  multitrack se os arquivos parecerem stems (kick, bumbo, caixa, baixo, voz,",
  "  click, guia…), com duração parecida e a mesma taxa de amostragem. Senão,",
  "  cada arquivo escolhido (ou todos, se você arrastar a pasta ou clicar nela",
  "  na Biblioteca) entra como uma música à parte.",
  "IMPORTAR VÁRIOS: no + IMPORTAR (e em Biblioteca > Importar de outra pasta) dá para",
  "  escolher UM ou VÁRIOS arquivos de uma vez (Ctrl ou Shift na janela). Um arquivo",
  "  sozinho continua igual: entra no fim do setlist, com click, guia, seções, cifra",
  "  e separação automáticos. Várias músicas comuns (LR/mixes) entram em sequência,",
  "  cada uma com a própria região. Pasta de stems/multitrack: escolha qualquer arquivo",
  "  de dentro dela (ou arraste a pasta) — entra a música inteira, como sempre.",
  "  A análise e a separação rodam UMA música por vez. O painel mostra",
  "  \"Importando 2 de 5: Nome...\" e dá para cancelar o resto da fila.",
  "  Se uma falhar, as outras seguem e as falhas aparecem no fim.",
  "APAGAR MÚSICAS: o botão Limpar abre uma lista para você ESCOLHER quais multitracks apagar.",
  "  Cada linha mostra o nome, o tamanho e se a música está neste projeto. Marcar todas / Desmarcar,",
  "  e o total em MB das selecionadas. Confirmação com aviso em vermelho se alguma estiver no setlist.",
  "  Os arquivos (pasta da música, __stems e clicks gerados dela) vão para a Lixeira;",
  "  o desfazer do REAPER NÃO os restaura. Se estiver no projeto, ela sai do setlist também.",
  "  A limpeza de lixo gerado (clicks antigos, __stems órfãos e temporários) continua na mesma janela.",
  "CLICK MUDO no modo L/R: o painel avisa bem visível e um clique leva ao Studio (ensaio com click).",
  "  No modo L/R o click fica mudo de propósito (não vai para a mesa). Para OUVIR: clique em Studio",
  "  ou no aviso amarelo, ou em Ao Vivo (click num lado, banda no outro). Solo Click também destampa.",
  "LIMPAR ARQUIVOS: botão no painel (e Menu) apaga só o que o kit gerou e não está em uso neste projeto",
  "  (clicks antigos, pastas __stems de músicas que saíram do setlist e temporários), com confirmação.",
  "  O original das músicas e tudo que está no projeto não é apagado. Prefere a Lixeira do sistema.",
  "Ao gerar de novo o click de uma música, o arquivo antigo (se ninguém mais usa) vai para a Lixeira.",
  "CLICK SEMPRE: toda música comum / VS ganha click - inclusive gravação ao vivo, sem click.",
  "CLICK ACOMPANHA O ANDAMENTO: se a música acelera ou freia, o click e a grade do REAPER",
  "  seguem as batidas reais (mapa de tempo). Música de grade fixa continua exata como antes.",
  "  Gravação difícil: o painel mostra \"click aproximado - ajuste em Corrigir BPM\".",
  "  A guia falada (avisos 1 compasso antes) também segue o andamento.",
  "BIBLIOTECA AUTOMÁTICA: música adicionada pela Biblioteca também ganha click, guia, seções,",
  "  cifra e separação, igual ao + IMPORTAR.",
  "1.3.1: CORRIGIDO - a análise automática não funcionava no REAPER (lia o áudio como silêncio)",
  "  e por isso não vinham click, guia, seções, cifra nem a separação. Agora funciona.",
  "1.3.1: a separação de trilhas roda mesmo se o BPM não for encontrado; erros aparecem na tela.",
  "SEPARAR TRILHAS: música comum ou VS fechado vira BATERIA, BAIXO, GUITARRA, TECLADO, VOZ e OUTROS",
  "  (motor Demucs 4 / htdemucs_6s), alinhadas e dentro da BANDA - a original fica mutada.",
  "Automático ao importar: click + guia + seções + cifra e, em seguida, a separação.",
  "Menu: Separar trilhas, Voltar para a música original, Instalar motor de separação,",
  "  'Separar trilhas ao importar' e 'Manter a música original mutada'.",
  "Motor instalado com 1 clique (Windows e Mac Intel/Apple Silicon), só na 1ª vez.",
  "Trilhas salvas em __stems na pasta da música: reimportar não separa de novo.",
  "VS com click num lado: separa só o lado da banda.",
  "(v1.2) Click, guia falada, seções e cifra automáticos; renomear seção; corrigir BPM.",
}
M.NOME = "Mik Seifador"
M.AUTOR = "Miqueias Felix"

-------------------------------------------------------------------------------
-- CONFIGURAÇÕES (pode editar à vontade)
-------------------------------------------------------------------------------
M.CFG = {
  INTERVALO_ENTRE_MUSICAS = 3.0,   -- segundos (mínimo) de silêncio entre músicas no projeto
  NOME_FONE  = "FONE (Click/Guia)",
  NOME_BANDA = "BANDA",
  NOME_CLICK = "CLICK",
  NOME_GUIA  = "GUIA",
  NOME_PAD   = "PAD (Tom)",
  IGNORAR_PEDAL_SOLTO = true,      -- pedal MIDI manda 127 ao pisar e 0 ao soltar: ignora o 0
  TOM_MIN = -12, TOM_MAX = 12,     -- limite da transposição (semitons)
  PAD_VOLUME = 0.25,               -- volume da trilha PAD (0.25 = cerca de -12 dB)
  PAD_FADE = 2.0,                  -- fade in/out do PAD (segundos)
  PAD_FADE_BOTAO = 1.5,            -- fade ao ligar/desligar o botão PAD (segundos)
  PAD_OITAVA_BASE = 48,            -- nota MIDI base do PAD (48 = C3)
  FIM_EPS = 0.005,                 -- tolerância para detectar o fim da música
}

-- Subpastas da BANDA (ordem em que aparecem) e cores (R,G,B)
M.SUBPASTAS = {
  { id = "BATERIA",   nome = "Bateria",    cor = {200, 60, 60} },
  { id = "BAIXO",     nome = "Baixo",      cor = {225, 140, 40} },
  { id = "GUITARRAS", nome = "Guitarras",  cor = {60, 170, 90} },
  { id = "TECLAS",    nome = "Teclas",     cor = {60, 120, 220} },
  { id = "SYNTH",     nome = "Synth / FX", cor = {150, 80, 200} },
  { id = "VOZES",     nome = "Vozes (BV)", cor = {220, 90, 170} },
}
M.COR_FONE  = {255, 200, 0}
M.COR_BANDA = {70, 70, 80}
M.COR_PAD   = {40, 190, 200}

-- Regras de classificação dos stems pelo NOME DO ARQUIVO (ordem importa!).
-- "frases": sequência de palavras em qualquer lugar do nome (ex.: "VOX FX");
-- "exatas": a palavra inteira; "prefixos": começo de alguma palavra.
-- Funciona com nomes da VS (português) e da MultiTracks.com (inglês).
M.REGRAS = {
  { destino = "CLICK", exatas = {"CLICK","CLIQUE","CLIC","CLK","CLIK","METRONOMO","METRONOME","METRO","CLICKS",
      "CLICKTRACK","CLIQUES"},
    prefixos = {"CLICK","CLIQUE","METRONO"} },
  { destino = "GUIA", exatas = {"GUIA","GUIAS","GUIDE","GUIDES","CUE","CUES","CUEING","GUIDETRACK",
      "GUIDE VOICE","VOCAL GUIDE","VOICE GUIDE","GUIA VOZ","VOZ GUIA","VOICE CUES","VOCAL CUES"},
    prefixos = {"GUIA","GUIDE"} },
  -- efeitos vocais/sonoros vão pra Synth/FX (antes da regra de vozes!)
  { destino = "SYNTH", frases = {"VOX FX","VOCAL FX","VOCALS FX","VOZ FX","VOZES FX","FX VOX"} },
  { destino = "BATERIA", exatas = {"BAT","BATERIA","DRUM","DRUMS","KICK","BUMBO","CAIXA","SNARE","HH","HIHAT",
      "OH","OVERHEAD","OVERHEADS","PERC","PERCUSSAO","PERCUSSION","LOOP","LOOPS","TOMS","SURDO","PRATOS",
      "CYMBALS","ROOM","SHAKER","CONGA","CONGAS","TAMBORIM","KIT","CLAP","CLAPS","PALMAS","TOM TOMS"},
    prefixos = {"BATER","DRUM","PERCUS","KICK","SNARE","LOOP"} },
  { destino = "BAIXO", exatas = {"BAIXO","BASS","SUB","BX","SUBBASS","SYNTHBASS","BAIXOS"},
    prefixos = {"BAIXO","BASS"} },
  { destino = "GUITARRAS", exatas = {"GTR","GT","GTRS","EG","AG","EGS","AGS","VIOLAO","VIOLOES","GUITARRA",
      "GUITARRAS","GUITAR","GUITARS","ACOUSTIC","ELECTRIC","ELETRICA","ELEC","ELEC GTR","AC GTR"},
    prefixos = {"GTR","GUIT","VIOLAO","VIOLOE","ACOUST","ELECTRIC","ELETRIC","ELEC"} },
  { destino = "TECLAS", exatas = {"PIANO","PNO","KEYS","KEY","KEYBOARD","KEYBOARDS","TECLADO","TECLADOS","TECLAS",
      "RHODES","EP","WURLI","ORGAO","ORGAN","B3","HAMMOND","PAD","PADS"},
    prefixos = {"PIANO","TECLA","RHODES","ORGA","WURL","HAMMOND","KEYS","KEYBOARD"} },
  { destino = "VOZES", exatas = {"BV","BVS","BGV","BGVS","VOZ","VOZES","VOX","VOCAL","VOCALS","VOX","CORO",
      "CHOIR","BACKING","BACKINGS","BACK","SOPRANO","CONTRALTO","ALTO","TENOR","BARITONE","HARMONY","HARMONIES"},
    prefixos = {"VOCAL","BACKING","CORAL","CHOIR","HARMON"} },
  { destino = "SYNTH", exatas = {"OUTROS","OTHER","OTHERS","SINT","SYNTH","SYNTHS","FX","SFX","ARP","STRINGS","CORDAS",
      "ORQ","ORQUESTRA","ORCH","ORCHESTRA","BRASS","METAIS","SEQ","LEAD","BELL","BELLS","PLUCK","TEMA","EFEITO",
      "EFEITOS","AMBIENCE","AMBIENT","DRONE","SWELL","VIOLINO","CELLO"},
    prefixos = {"SINT","SYNTH","ORQ","ORCH","STRING","CORDA","ARPE","EFEIT"} },
}
M.DESTINO_PADRAO = "SYNTH"

-- Cores das seções (pelo começo do nome do marcador)
M.CORES_SECAO = {
  { nomes = {"PONTE","PT","BRIDGE","B","PON"},                    cor = {150, 70, 200}, desc = "Ponte" },
  { nomes = {"PRE","P","PR","PREREFRAO","PRECHORUS"},             cor = {240, 160, 40}, desc = "Pré-refrão" },
  { nomes = {"REFRAO","CHORUS","CH","R","RE","REF","C","CORO","REFRAIN"}, cor = {220, 50, 60},  desc = "Refrão" },
  { nomes = {"VERSO","VERSE","V","E","ESTROFE","VS"},             cor = {52, 120, 220}, desc = "Verso" },
  { nomes = {"INTRO","IN","I","INT","INTRODUCAO"},                cor = {110, 135, 165}, desc = "Intro" },
  { nomes = {"INST","INSTRUMENTAL","SOLO","INTERLUDIO","INTERLUDE","IT","INTER","SL","TURNAROUND",
             "BREAKDOWN","BREAK"},                                 cor = {40, 170, 110}, desc = "Instrumental" },
  { nomes = {"FINAL","FIM","OUTRO","END","ENDING","F","O","TAG","T","FN"}, cor = {95, 95, 95},  desc = "Final" },
  { nomes = {"VAMP","ESPONTANEO","ESP","ESPONTANEA","LOOP","MOMENTO"}, cor = {30, 180, 200}, desc = "Espontâneo" },
  { nomes = {"COUNT","COUNTOFF","COUNTIN","CONTAGEM","CONT"},       cor = {60, 60, 70},   desc = "Contagem" },
}
M.COR_SECAO_PADRAO = {170, 170, 170}

-- Paleta usada nas regiões (músicas)
M.PALETA_MUSICAS = {
  {52,120,220},{220,50,60},{40,170,110},{240,160,40},{150,70,200},{30,180,200},{200,90,150},{120,150,60},
}

-------------------------------------------------------------------------------
-- UTILITÁRIOS
-------------------------------------------------------------------------------
local SEP = package.config:sub(1, 1)  -- "\" no Windows
M.SEP = SEP
local OS = (reaper.GetOS and reaper.GetOS()) or ""
M.EH_WIN = SEP == "\\"
M.EH_MAC = OS:find("OSX") ~= nil or OS:find("macOS") ~= nil
-- rótulo de atalho do sistema: no Mac, Ctrl vira Cmd e Alt vira Opt
function M.atalho(s)
  if M.EH_MAC then s = s:gsub("Ctrl", "Cmd"):gsub("Alt", "Opt") end
  return s
end
-- abre uma pasta no Explorer (Windows) / Finder (Mac) / gerenciador (Linux)
function M.abrir_no_sistema(p)
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(p); return end
  if M.EH_WIN then reaper.ExecProcess('explorer "' .. p .. '"', -1)
  elseif M.EH_MAC then reaper.ExecProcess('/usr/bin/open "' .. p .. '"', -1)
  else reaper.ExecProcess('xdg-open "' .. p .. '"', -1) end
end

M.DIR = (debug.getinfo(1, "S").source:match("^@?(.*[\\/])")) or ""

-- v1.8: Menu > Como usar (guia de primeiro uso que vai junto no kit)
function M.abrir_como_usar()
  for _, nome in ipairs({ "COMO USAR - Mik Seifador.pdf", "COMO USAR - Mik Seifador.txt" }) do
    local p = M.DIR .. nome
    if reaper.file_exists(p) then M.abrir_no_sistema(p); return true end
  end
  reaper.MB("Guia rápido do Mik Seifador:\n\n" ..
    "1. Abra o painel: F9 (no Mac pode ser fn+F9) ou Ações > \"MT - Painel ao vivo\".\n" ..
    "2. Clique em + IMPORTAR no painel (não use o Arquivo > Importar do REAPER).\n" ..
    "   O projeto pode começar vazio.\n" ..
    "3. Música inteira (estéreo/VS): o kit acha o tempo, o tom, as seções, cria click e guia\n" ..
    "   e separa bateria, baixo, guitarra, teclado, voz e outros (precisa do motor de separação: Menu > Instalar).\n" ..
    "4. Acompanhe tudo na barrinha do topo (etapa, % e tempo restante).", "Como usar", 0)
  return false
end

-- Curva dos faders (estilo Pro Tools), igual no painel e no celular.
-- posição 0..1 -> dB:  1 = +12, 0.75 = 0 dB, 0.5 = -10, 0.15 = -40, 0 = -inf
function M.fader_db(x)
  x = tonumber(x) or 0
  if x <= 0 then return -math.huge end
  if x >= 1 then x = 1 end
  if x >= 0.75 then return (x - 0.75) / 0.25 * 12 end
  if x >= 0.50 then return -10 + (x - 0.5) / 0.25 * 10 end
  if x >= 0.15 then return -40 + (x - 0.15) / 0.35 * 30 end
  return -144 + math.sqrt(x / 0.15) * 104
end
-- dB -> posição 0..1 (inversa exata; acima de +12 fica no topo)
function M.fader_pos(db)
  db = tonumber(db) or -math.huge
  if db ~= db or db <= -144 then return 0 end
  if db >= 12 then return 1 end
  if db >= 0 then return 0.75 + db / 12 * 0.25 end
  if db >= -10 then return 0.5 + (db + 10) / 10 * 0.25 end
  if db >= -40 then return 0.15 + (db + 40) / 30 * 0.35 end
  local t = (db + 144) / 104
  return 0.15 * t * t
end
-- posição -> ganho (D_VOL) e ganho -> posição
function M.fader_ganho(x)
  local db = M.fader_db(x)
  if db == -math.huge then return 0 end
  return 10 ^ (db / 20)
end
function M.fader_pos_ganho(g)
  g = tonumber(g) or 0
  if g <= 0 then return 0 end
  return M.fader_pos(20 * math.log(g, 10))
end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
M.trim = trim

local ACENTOS = {
  ["á"]="A",["à"]="A",["â"]="A",["ã"]="A",["ä"]="A",["Á"]="A",["À"]="A",["Â"]="A",["Ã"]="A",["Ä"]="A",
  ["é"]="E",["è"]="E",["ê"]="E",["ë"]="E",["É"]="E",["È"]="E",["Ê"]="E",["Ë"]="E",
  ["í"]="I",["ì"]="I",["î"]="I",["ï"]="I",["Í"]="I",["Ì"]="I",["Î"]="I",["Ï"]="I",
  ["ó"]="O",["ò"]="O",["ô"]="O",["õ"]="O",["ö"]="O",["Ó"]="O",["Ò"]="O",["Ô"]="O",["Õ"]="O",["Ö"]="O",
  ["ú"]="U",["ù"]="U",["û"]="U",["ü"]="U",["Ú"]="U",["Ù"]="U",["Û"]="U",["Ü"]="U",
  ["ç"]="C",["Ç"]="C",["ñ"]="N",["Ñ"]="N",
}

-- Nomes com acento "quebrado" (ZIP extraído como CP437/CP850): Refr├úo -> REFRAO
local ACENTOS_QUEBRADOS = {
  ["\226\148\156\226\140\144"]="E",
  ["\226\148\156\226\148\130"]="O",
  ["\226\148\156\226\150\147"]="O",
  ["\226\148\156\226\148\164"]="O",
  ["\226\148\156\226\149\161"]="O",
  ["\226\148\156\226\149\162"]="O",
  ["\226\148\156\226\149\145"]="U",
  ["\226\148\156\226\149\163"]="U",
  ["\226\148\156\226\149\151"]="U",
  ["\226\148\156\226\149\157"]="U",
  ["\226\148\156\226\150\146"]="N",
  ["\226\148\156\195\173"]="A",
  ["\226\148\156\195\161"]="A",
  ["\226\148\156\195\179"]="A",
  ["\226\148\156\195\186"]="A",
  ["\226\148\156\195\177"]="A",
  ["\226\148\156\195\188"]="A",
  ["\226\148\156\195\135"]="A",
  ["\195\131\226\130\172"]="A",
  ["\226\148\156\195\169"]="A",
  ["\195\131\226\128\154"]="A",
  ["\226\148\156\195\162"]="A",
  ["\226\148\156\195\164"]="A",
  ["\195\131\226\128\158"]="A",
  ["\226\148\156\194\174"]="E",
  ["\226\148\156\194\191"]="E",
  ["\226\148\156\194\172"]="E",
  ["\226\148\156\194\189"]="E",
  ["\226\148\156\195\171"]="E",
  ["\195\131\226\128\176"]="E",
  ["\226\148\156\195\170"]="E",
  ["\226\148\156\195\168"]="E",
  ["\226\148\156\195\175"]="E",
  ["\195\131\226\128\185"]="E",
  ["\226\148\156\194\161"]="I",
  ["\226\148\156\194\188"]="I",
  ["\226\148\156\194\171"]="I",
  ["\226\148\156\194\187"]="I",
  ["\226\148\156\195\172"]="I",
  ["\226\148\156\195\174"]="I",
  ["\226\148\156\195\132"]="I",
  ["\226\148\156\195\133"]="I",
  ["\226\148\156\195\129"]="O",
  ["\226\148\156\195\130"]="O",
  ["\226\148\156\195\180"]="O",
  ["\195\131\226\128\156"]="O",
  ["\226\148\156\195\134"]="O",
  ["\195\131\226\128\153"]="O",
  ["\226\148\156\195\182"]="O",
  ["\195\131\226\128\157"]="O",
  ["\226\148\156\195\178"]="O",
  ["\195\131\226\128\162"]="O",
  ["\226\148\156\195\187"]="O",
  ["\195\131\226\128\147"]="O",
  ["\226\148\156\195\156"]="U",
  ["\226\148\156\195\150"]="U",
  ["\195\131\226\132\162"]="U",
  ["\226\148\156\194\162"]="U",
  ["\226\148\156\195\184"]="U",
  ["\195\131\226\128\186"]="U",
  ["\226\148\156\194\163"]="U",
  ["\226\148\156\194\186"]="C",
  ["\226\148\156\195\167"]="C",
  ["\195\131\226\128\161"]="C",
  ["\226\148\156\195\166"]="N",
  ["\195\131\226\128\152"]="N",
  ["\195\131\194\161"]="A",
  ["\195\131\194\160"]="A",
  ["\195\131\194\162"]="A",
  ["\195\131\194\163"]="A",
  ["\195\131\194\164"]="A",
  ["\195\131\198\146"]="A",
  ["\195\131\194\169"]="E",
  ["\195\131\194\168"]="E",
  ["\195\131\194\170"]="E",
  ["\195\131\194\171"]="E",
  ["\195\131\203\134"]="E",
  ["\195\131\197\160"]="E",
  ["\195\131\194\173"]="I",
  ["\195\131\194\172"]="I",
  ["\195\131\194\174"]="I",
  ["\195\131\194\175"]="I",
  ["\195\131\197\146"]="I",
  ["\195\131\197\189"]="I",
  ["\195\131\194\179"]="O",
  ["\195\131\194\178"]="O",
  ["\195\131\194\180"]="O",
  ["\195\131\194\181"]="O",
  ["\195\131\194\182"]="O",
  ["\195\131\194\186"]="U",
  ["\195\131\194\185"]="U",
  ["\195\131\194\187"]="U",
  ["\195\131\194\188"]="U",
  ["\195\131\197\161"]="U",
  ["\195\131\197\147"]="U",
  ["\195\131\194\167"]="C",
  ["\195\131\194\177"]="N"
}
local ACENTOS_QUEBRADOS_ORDEM = {}
for k in pairs(ACENTOS_QUEBRADOS) do ACENTOS_QUEBRADOS_ORDEM[#ACENTOS_QUEBRADOS_ORDEM + 1] = k end
table.sort(ACENTOS_QUEBRADOS_ORDEM, function(a, b) return #a > #b end)

-- Normaliza: maiúsculas, sem acento (UTF-8 ou CP1252), só letras/números separados por espaço
function M.norm(s)
  s = tostring(s or "")
  for _, k in ipairs(ACENTOS_QUEBRADOS_ORDEM) do
    local v, i = ACENTOS_QUEBRADOS[k], 1
    while true do
      local a, b = s:find(k, i, true)
      if not a then break end
      s = s:sub(1, a - 1) .. v .. s:sub(b + 1)
      i = a + #v
    end
  end
  for k, v in pairs(ACENTOS) do s = s:gsub(k, v) end
  -- diacríticos combinantes (NFD) e bytes CP1252 que restaram (EnumerateFiles no Windows)
  s = s:gsub("\204[\128-\191]", ""):gsub("\205[\128-\175]", "")
  s = s:gsub("[\128-\255]", function(ch)
    local b = ch:byte()
    local m = {
      [192]="A",[193]="A",[194]="A",[195]="A",[196]="A",[199]="C",[200]="E",[201]="E",[202]="E",[203]="E",
      [204]="I",[205]="I",[206]="I",[207]="I",[209]="N",[210]="O",[211]="O",[212]="O",[213]="O",[214]="O",
      [217]="U",[218]="U",[219]="U",[220]="U",
      [224]="A",[225]="A",[226]="A",[227]="A",[228]="A",[231]="C",[232]="E",[233]="E",[234]="E",[235]="E",
      [236]="I",[237]="I",[238]="I",[239]="I",[241]="N",[242]="O",[243]="O",[244]="O",[245]="O",[246]="O",
      [249]="U",[250]="U",[251]="U",[252]="U",
    }
    return m[b] or ""
  end)
  s = s:upper():gsub("[^%w]+", " ")
  return trim(s)
end

local function palavras(s)
  local t = {}
  for w in M.norm(s):gmatch("%S+") do t[#t + 1] = w end
  return t
end

function M.cor_nativa(rgb)
  return r.ColorToNative(rgb[1], rgb[2], rgb[3]) | 0x1000000
end

-- Mensagem rápida perto do mouse (bom pra confirmar o pedal/atalho)
function M.aviso(txt)
  local x, y = r.GetMousePosition()
  r.TrackCtl_SetToolTip(txt, x + 18, y + 18, true)
end

-- REAPER devolve floats (4.0); em Lua 5.3 o %d exige inteiro e derruba o script.
local function inteiro(n, padrao)
  n = tonumber(n)
  if not n or n ~= n then return padrao or 0 end
  if n >= 0 then return math.floor(n + 0.5) end
  return math.ceil(n - 0.5)
end
function M.inteiro(n, padrao) return inteiro(n, padrao) end

-- Log silencioso (sem popup) para o painel/motor continuarem rodando.
function M.registrar_erro(onde, err)
  local linha = os.date("%Y-%m-%d %H:%M:%S") .. "  [" .. tostring(onde or "?") .. "]  " .. tostring(err or "")
  local function append(path)
    if not path or path == "" then return false end
    local f = io.open(path, "a")
    if not f then return false end
    f:write(linha, "\n")
    f:close()
    return true
  end
  local base = r.GetResourcePath and r.GetResourcePath() or nil
  if base and SEP then append(base .. SEP .. "MikSeifador-erro.log") end
end

-- Evita criar ponto de desfazer ("ReaScript: Run") em scripts de navegação.
-- set_action_options(1) (REAPER 7.03+): se apertar o pedal duas vezes muito
-- rápido, o REAPER não pergunta "script já está rodando".
function M.sem_undo()
  if r.set_action_options then r.set_action_options(1) end
  r.defer(function() end)
end

-- Pedal MIDI: ao soltar ele manda valor 0. Retorna true se for pra ignorar.
function M.pedal_solto()
  if not M.CFG.IGNORAR_PEDAL_SOLTO then return false end
  local _, _, _, _, _, resolucao, valor = r.get_action_context()
  return (resolucao or -1) > 0 and valor == 0
end

-------------------------------------------------------------------------------
-- ESTADOS (ExtState)
-------------------------------------------------------------------------------
M.FLAGS = { "AUTO", "HOLD", "LOOP", "SOLO_CLICK", "REPETIR_CLICK", "PAD" }

function M.flag(nome) return r.GetExtState(M.SEC, nome) == "1" end

function M.set_flag(nome, ligado)
  r.SetExtState(M.SEC, nome, ligado and "1" or "0", true)
  M.sincronizar_botoes()
end

function M.get(nome, padrao)
  local v = r.GetExtState(M.SEC, nome)
  if v == "" then return padrao end
  return v
end
function M.set(nome, valor) r.SetExtState(M.SEC, nome, tostring(valor), true) end

-- Guarda o ID do script que chamou (para acender o botão da barra de ferramentas)
function M.registrar_toggle(nome)
  local _, _, secao, cmd = r.get_action_context()
  if cmd and cmd > 0 then r.SetExtState(M.SEC, "CMD_" .. nome, secao .. ":" .. cmd, false) end
end

function M.sincronizar_botoes()
  local lista = { "AUTO", "HOLD", "LOOP", "SOLO_CLICK", "REPETIR_CLICK", "PAD", "MODO_AO_VIVO", "MODO_LR", "SALTO_SUAVE" }
  for _, nome in ipairs(lista) do
    local s = r.GetExtState(M.SEC, "CMD_" .. nome)
    local secao, cmd = s:match("^(%-?%d+):(%d+)$")
    if secao then
      local estado
      if nome == "MODO_AO_VIVO" then estado = (M.modo() == "AO_VIVO")
      elseif nome == "MODO_LR" then estado = (M.modo() == "LR")
      elseif nome == "SALTO_SUAVE" then estado = M.salto_suave()
      else estado = M.flag(nome) end
      r.SetToggleCommandState(tonumber(secao), tonumber(cmd), estado and 1 or 0)
      r.RefreshToolbar2(tonumber(secao), tonumber(cmd))
    end
  end
end

-------------------------------------------------------------------------------
-- TRANSPORTE / POSIÇÃO
-------------------------------------------------------------------------------
function M.tocando()
  local ps = r.GetPlayState()
  return (ps & 1) == 1 and (ps & 2) == 0
end
function M.pausado() return (r.GetPlayState() & 2) == 2 end

function M.pos_atual()
  local ps = r.GetPlayState()
  if (ps & 1) == 1 or (ps & 2) == 2 then return r.GetPlayPosition() end
  return r.GetCursorPosition()
end

-- Vai para um ponto. Se estiver tocando, continua tocando de lá
-- (com o "Salto suave" ligado o REAPER espera o fim do compasso).
function M.ir_para(t)
  r.SetEditCurPos(t, true, true)
end

function M.play_pause()
  if M.tocando() then r.OnPauseButton() else r.OnPlayButton() end
end

-- Para e volta o cursor para o início da música atual
function M.parar()
  local m = M.musica_atual()
  r.OnStopButton()
  if m then r.SetEditCurPos(m.inicio, true, false) end
end

-- Salto suave (smooth seek) nativo do REAPER: ação 40390
M.CMD_SMOOTH_SEEK = 40390
function M.salto_suave() return r.GetToggleCommandState(M.CMD_SMOOTH_SEEK) == 1 end
function M.alternar_salto_suave()
  r.Main_OnCommand(M.CMD_SMOOTH_SEEK, 0)
  M.sincronizar_botoes()
  M.aviso("SALTO SUAVE (espera o fim do compasso): " .. (M.salto_suave() and "LIGADO" or "DESLIGADO"))
end

-------------------------------------------------------------------------------
-- TOM (tonalidade)
-------------------------------------------------------------------------------
local NOTA_BASE = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local NOMES_MAIOR = { "C","Db","D","Eb","E","F","F#","G","Ab","A","Bb","B" }
local NOMES_MENOR = { "Cm","C#m","Dm","Ebm","Em","Fm","F#m","Gm","G#m","Am","Bbm","Bm" }

-- "Bb" -> 10,false ; "F#m" -> 6,true ; inválido -> nil
function M.ler_tom(s)
  s = trim(s)
  local letra, acid, resto = s:match("^([A-Ga-g])([#b]?)(.*)$")
  if not letra then return nil end
  resto = trim(resto)
  if resto ~= "" and not (resto == "m" or resto == "min" or resto:lower() == "menor" or resto == "M"
     or resto:lower() == "maj" or resto:lower() == "maior") then return nil end
  local n = NOTA_BASE[letra:upper()]
  if acid == "#" then n = n + 1 elseif acid == "b" then n = n - 1 end
  local menor = (resto == "m" or resto == "min" or resto:lower() == "menor")
  return n % 12, menor
end

function M.nome_tom(n, menor)
  n = n % 12
  return (menor and NOMES_MENOR or NOMES_MAIOR)[n + 1]
end

-- Separa "Nome [G]" -> "Nome", "G"
function M.separar_nome_tom(nome)
  local base, tom = tostring(nome):match("^(.-)%s*%[([^%]]*)%]%s*$")
  if base then return trim(base), trim(tom) end
  return trim(nome), nil
end

-- Transposição atual (semitons) de uma música, guardada no projeto
function M.get_transp(m)
  local _, v = r.GetProjExtState(0, "MT_TOM", M.norm(m.nome))
  return tonumber(v) or 0
end
function M.set_transp_valor(m, v)
  r.SetProjExtState(0, "MT_TOM", M.norm(m.nome), tostring(v))
end

-- Tom que está soando (original + transposição) em texto
function M.tom_soando(m)
  if not m or not m.tom then return nil end
  local n, menor = M.ler_tom(m.tom)
  if not n then return m.tom end
  return M.nome_tom(n + M.get_transp(m), menor)
end

-------------------------------------------------------------------------------
-- MÚSICAS (regiões) E SEÇÕES (marcadores)
-------------------------------------------------------------------------------
function M.listar_marcadores()
  local musicas, marcas = {}, {}
  local i = 0
  while true do
    local ret, isrgn, pos, fim, nome, idx, cor = r.EnumProjectMarkers3(0, i)
    if ret == 0 then break end
    if isrgn then
      musicas[#musicas + 1] = { inicio = pos, fim = fim, nome_completo = nome, idx = idx, cor = cor, enum = i }
    else
      marcas[#marcas + 1] = { inicio = pos, nome = nome, idx = idx, cor = cor, enum = i }
    end
    i = i + 1
  end
  table.sort(musicas, function(a, b) return a.inicio < b.inicio end)
  table.sort(marcas, function(a, b) return a.inicio < b.inicio end)
  for k, m in ipairs(musicas) do
    m.n = k
    m.nome, m.tom = M.separar_nome_tom(m.nome_completo)
    if m.nome == "" then m.nome = "Música " .. k end
  end
  return musicas, marcas
end

-- Ordem do SETLIST (só os cards / anterior-próxima / AUTO).
-- Não mexe na linha do tempo. Gravada no projeto (ProjExtState), vale
-- mesmo antes de salvar; ao abrir o .RPP é reaplicada. Músicas novas
-- (ainda não listadas) entram no fim, na ordem da timeline.
function M.chave_setlist(m)
  if not m then return "" end
  return tostring(m.idx or "") .. "@" .. string.format("%.3f", tonumber(m.inicio) or 0)
end

local function ler_ordem_setlist()
  local _, v = r.GetProjExtState(0, "MT_SETLIST", "ORDEM")
  if not v or v == "" then return nil end
  local t = {}
  for p in (v .. ","):gmatch("([^,]*),") do
    p = trim(p)
    if p ~= "" then t[#t + 1] = p end
  end
  return #t > 0 and t or nil
end

function M.gravar_ordem_setlist(musicas)
  local partes = {}
  for _, m in ipairs(musicas or {}) do
    partes[#partes + 1] = M.chave_setlist(m)
  end
  r.SetProjExtState(0, "MT_SETLIST", "ORDEM", table.concat(partes, ","))
end

function M.aplicar_ordem_setlist(musicas)
  if not musicas or #musicas == 0 then return musicas or {} end
  local ordem = ler_ordem_setlist()
  if not ordem then
    for k, m in ipairs(musicas) do m.n = k end
    return musicas
  end
  local por = {}
  for _, m in ipairs(musicas) do por[M.chave_setlist(m)] = m end
  local saida, visto = {}, {}
  for _, k in ipairs(ordem) do
    local m = por[k]
    if m and not visto[m] then
      saida[#saida + 1] = m
      visto[m] = true
    end
  end
  local novas = 0
  for _, m in ipairs(musicas) do
    if not visto[m] then
      saida[#saida + 1] = m
      visto[m] = true
      novas = novas + 1
    end
  end
  for k, m in ipairs(saida) do m.n = k end
  if novas > 0 then pcall(M.gravar_ordem_setlist, saida) end
  return saida
end

function M.get_musicas()
  return M.aplicar_ordem_setlist(M.listar_marcadores())
end

-- de, para: índices 1-based da ordem atual do setlist. Não move itens/regiões.
function M.reordenar_setlist(de, para)
  if M.setlist_travado() then return false end
  de, para = tonumber(de), tonumber(para)
  local mus = M.get_musicas()
  if not de or not para or de < 1 or para < 1 or de > #mus or para > #mus or de == para then
    return false
  end
  local item = table.remove(mus, de)
  table.insert(mus, para, item)
  for k, m in ipairs(mus) do m.n = k end
  M.gravar_ordem_setlist(mus)
  return true
end

-- Trava do setlist (ProjExtState, vale sem salvar). Travado: não reordena;
-- o toque/clique no card continua trocando a música.
function M.setlist_travado()
  local _, v = r.GetProjExtState(0, "MT_SETLIST", "TRAVA")
  return v == "1"
end

function M.gravar_trava_setlist(travado)
  r.SetProjExtState(0, "MT_SETLIST", "TRAVA", travado and "1" or "0")
end

function M.alternar_trava_setlist()
  local novo = not M.setlist_travado()
  M.gravar_trava_setlist(novo)
  return novo
end

-- Sessão desta instância do REAPER (ExtState NÃO persistente). A hora é
-- gravada na primeira carga da lib e morre ao fechar o REAPER.
function M.sessao_id()
  local id = r.GetExtState(M.SEC, "SESSAO_T0")
  if not id or id == "" then
    id = string.format("%.3f", r.time_precise())
    r.SetExtState(M.SEC, "SESSAO_T0", id, false)
  end
  return id
end

function M.capa_feita_na_sessao()
  return r.GetExtState(M.SEC, "CAPA_FEITA") == M.sessao_id()
end

function M.marcar_capa_feita()
  r.SetExtState(M.SEC, "CAPA_FEITA", M.sessao_id(), false)
end

-- Música onde está o cursor. A posição é a da TIMELINE (início/fim reais),
-- mesmo se a ordem do setlist for outra.
function M.musica_atual(pos, musicas)
  musicas = musicas or M.get_musicas()
  if #musicas == 0 then return nil end
  pos = pos or M.pos_atual()
  local atual
  for _, m in ipairs(musicas) do
    if m.inicio <= pos + 0.0005 then
      if not atual or m.inicio >= atual.inicio then atual = m end
    end
  end
  return atual or musicas[1], musicas
end

-- Seções (marcadores) de uma música. Se não houver marcador no início,
-- cria uma seção virtual "Início".
function M.secoes_da_musica(m, marcas)
  if not m then return {} end
  if not marcas then local _; _, marcas = M.listar_marcadores() end
  local s = {}
  for _, mk in ipairs(marcas) do
    if mk.inicio >= m.inicio - 0.001 and mk.inicio < m.fim - 0.001 then s[#s + 1] = mk end
  end
  if #s == 0 or s[1].inicio > m.inicio + 0.05 then
    table.insert(s, 1, { inicio = m.inicio, nome = "Início", virtual = true, cor = 0 })
  end
  for k, sec in ipairs(s) do
    sec.n = k
    sec.fim = (s[k + 1] and s[k + 1].inicio) or m.fim
  end
  return s
end

function M.secao_atual(pos, secoes)
  local atual = secoes[1]
  for _, sc in ipairs(secoes) do
    if sc.inicio <= pos + 0.01 then atual = sc else break end
  end
  return atual
end

-------------------------------------------------------------------------------
-- NAVEGAÇÃO
-------------------------------------------------------------------------------
-- Vai para a música i. Se estiver tocando: PARA e posiciona (mais seguro ao vivo).
function M.ir_para_musica(i)
  local musicas = M.get_musicas()
  local m = musicas[i]
  if not m then return end
  if M.tocando() or M.pausado() then r.OnStopButton() end
  r.SetEditCurPos(m.inicio, true, false)
  if M.flag("LOOP") or M.flag("REPETIR_CLICK") then
    local secs = M.secoes_da_musica(m)
    M.definir_loop(secs[1].inicio, secs[1].fim)
  end
  M.aviso(string.format("Música %d: %s%s", m.n, m.nome, m.tom and (" [" .. (M.tom_soando(m) or m.tom) .. "]") or ""))
end

function M.proxima_musica()
  local m, musicas = M.musica_atual()
  if not m then return M.aviso("Nenhuma música no projeto") end
  if M.pos_atual() < m.inicio - 0.001 then return M.ir_para_musica(m.n) end
  if musicas[m.n + 1] then M.ir_para_musica(m.n + 1) else M.aviso("Já está na última música") end
end

function M.musica_anterior()
  local m = M.musica_atual()
  if not m then return M.aviso("Nenhuma música no projeto") end
  local pos = M.pos_atual()
  -- se já andou mais de 2 s dentro da música, volta pro começo dela
  if pos > m.inicio + 2 or m.n == 1 then M.ir_para_musica(m.n) else M.ir_para_musica(m.n - 1) end
end

function M.ir_para_secao(sec)
  if not sec then return end
  if M.flag("LOOP") or M.flag("REPETIR_CLICK") then M.definir_loop(sec.inicio, sec.fim) end
  M.ir_para(sec.inicio)
  M.aviso("Seção: " .. sec.nome)
end

function M.proxima_secao()
  local pos = M.pos_atual()
  local m = M.musica_atual(pos)
  if not m then return end
  local secs = M.secoes_da_musica(m)
  local atual = M.secao_atual(pos, secs)
  if pos < m.inicio then return M.ir_para_secao(secs[1]) end
  local prox = secs[atual.n + 1]
  if prox then M.ir_para_secao(prox) else M.aviso("Última seção da música") end
end

function M.secao_anterior()
  local pos = M.pos_atual()
  local m = M.musica_atual(pos)
  if not m then return end
  local secs = M.secoes_da_musica(m)
  local atual = M.secao_atual(pos, secs)
  local alvo = secs[atual.n - 1] or atual
  M.ir_para_secao(alvo)
end

-------------------------------------------------------------------------------
-- LOOP / SOLO CLICK / REPETIR CLICK
-------------------------------------------------------------------------------
function M.definir_loop(ini, fim)
  r.GetSet_LoopTimeRange(true, true, ini, fim, false)
end

function M.loop_na_secao_atual()
  local pos = M.pos_atual()
  local m = M.musica_atual(pos)
  if not m then return nil end
  local sec = M.secao_atual(pos, M.secoes_da_musica(m))
  M.definir_loop(sec.inicio, sec.fim)
  return sec
end

function M.alternar_loop()
  local ligar = not M.flag("LOOP")
  M.set_flag("LOOP", ligar)
  if ligar then
    local sec = M.loop_na_secao_atual()
    r.GetSetRepeat(1)
    M.aviso("LOOP LIGADO" .. (sec and (" - " .. sec.nome) or ""))
  else
    if not M.flag("REPETIR_CLICK") then r.GetSetRepeat(0) end
    M.aviso("LOOP DESLIGADO")
  end
end

function M.trilha_click() return M.achar_trilha(M.CFG.NOME_CLICK) end

-- No modo L/R (sem "L/R com click" / Studio) a pasta FONE fica muda de propósito,
-- para o click não ir para a mesa. Por isso o usuário não ouve o click no ensaio.
function M.click_mudo_pelo_modo()
  return M.modo() == "LR" and M.get("LR_COM_CLICK", "0") ~= "1"
end
function M.fone_esta_mudo()
  local fone = M.achar_fone()
  return fone and r.GetMediaTrackInfo_Value(fone, "B_MUTE") == 1 or false
end

function M.aplicar_solo_click()
  local tr = M.trilha_click()
  if not tr then return M.aviso("Trilha CLICK não encontrada") end
  local solo = M.flag("SOLO_CLICK") or M.flag("REPETIR_CLICK")
  r.SetMediaTrackInfo_Value(tr, "I_SOLO", solo and 2 or 0)  -- 2 = solo "in place"
  -- pasta FONE muda (modo L/R): o solo no filho não soa. Destampa só enquanto o solo está ligado.
  local fone = M.achar_fone()
  if fone then
    if solo then
      r.SetMediaTrackInfo_Value(fone, "B_MUTE", 0)
    elseif M.click_mudo_pelo_modo() then
      r.SetMediaTrackInfo_Value(fone, "B_MUTE", 1)
    end
  end
end

function M.alternar_solo_click()
  M.set_flag("SOLO_CLICK", not M.flag("SOLO_CLICK"))
  M.aplicar_solo_click()
  M.aviso("SOLO CLICK: " .. (M.flag("SOLO_CLICK") and "LIGADO (banda muda)" or "DESLIGADO"))
end

-- Repetir Click: só o click toca, repetindo a seção atual em loop
-- (ex.: segurar o tempo enquanto o ministro fala). Desligando, volta ao normal.
function M.alternar_repetir_click()
  local ligar = not M.flag("REPETIR_CLICK")
  M.set_flag("REPETIR_CLICK", ligar)
  M.aplicar_solo_click()
  if ligar then
    M.loop_na_secao_atual()
    r.GetSetRepeat(1)
    M.aviso("REPETIR CLICK: LIGADO")
  else
    if not M.flag("LOOP") then r.GetSetRepeat(0) end
    M.aviso("REPETIR CLICK: DESLIGADO")
  end
end

function M.alternar(nome, rotulo)
  M.set_flag(nome, not M.flag(nome))
  M.aviso((rotulo or nome) .. ": " .. (M.flag(nome) and "LIGADO" or "DESLIGADO") .. M.alerta_motor())
end

-------------------------------------------------------------------------------
-- TRILHAS / ESTRUTURA DE PASTAS
-------------------------------------------------------------------------------
function M.nome_trilha(tr)
  local _, n = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  return n
end

function M.achar_trilha(nome)
  local alvo = M.norm(nome)
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if M.norm(M.nome_trilha(tr)) == alvo then return tr end
  end
  return nil
end

function M.achar_fone()
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if M.norm(M.nome_trilha(tr)):find("^FONE") then return tr end
  end
  return nil
end

function M.descende_de(tr, pai)
  local p = r.GetParentTrack(tr)
  while p do
    if p == pai then return true end
    p = r.GetParentTrack(p)
  end
  return false
end

-- v1.8: a mesa (painel e celular) mostra só os canais com áudio dentro da
-- música atual. Todas as músicas ficam em sequência na mesma timeline, então
-- trilhas de outras músicas (stems renomeados, originais) ficam escondidas.
-- Folga de 0,25 s para um item que encosta na borda não contar.
function M.trilha_tem_item_em(tr, ini, fim)
  local folga = 0.25
  for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, k)
    local ip = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local fp = ip + r.GetMediaItemInfo_Value(it, "D_LENGTH")
    if ip < fim - folga and fp > ini + folga then return true end
  end
  return false
end

-- Filtra a lista de trilhas pela música m (sem música: devolve a lista inteira).
-- Cache por consumidor: só recalcula se mudar a música ou o projeto
-- (GetProjectStateChangeCount), para não varrer os itens a cada frame.
local _cache_mesa = {}
function M.trilhas_da_musica(id, lista_fn, m)
  if not m or not m.inicio or not m.fim or m.fim <= m.inicio then return lista_fn() end
  local chave = string.format("%.3f|%.3f|%d|%d", m.inicio, m.fim,
    r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(0) or 0, r.CountTracks(0))
  local c = _cache_mesa[id]
  if c and c.chave == chave then
    local ok = true
    for _, tr in ipairs(c.lista) do
      if not r.ValidatePtr2(0, tr, "MediaTrack*") then ok = false; break end
    end
    if ok then return c.lista, c.total end
  end
  local todas = lista_fn()
  local lista = {}
  for _, tr in ipairs(todas) do
    if M.trilha_tem_item_em(tr, m.inicio, m.fim) then lista[#lista + 1] = tr end
  end
  _cache_mesa[id] = { chave = chave, lista = lista, total = #todas }
  return lista, #todas
end

-- Procura uma trilha pelo nome somente dentro de uma pasta
function M.achar_filho(pai, nome)
  local alvo = M.norm(nome)
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if M.norm(M.nome_trilha(tr)) == alvo and M.descende_de(tr, pai) then return tr end
  end
  return nil
end

local function nova_trilha_config(tr, nome, cor)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", nome, true)
  if cor then r.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", M.cor_nativa(cor)) end
  r.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 1)
end

-- Cria uma trilha no FIM da pasta "pai" (pai vira pasta se ainda não for)
function M.inserir_filho_no_fim(pai, nome, cor)
  local ip = math.floor(r.GetMediaTrackInfo_Value(pai, "IP_TRACKNUMBER")) - 1
  local d = math.floor(r.GetMediaTrackInfo_Value(pai, "I_FOLDERDEPTH"))
  local novo
  if d ~= 1 then
    r.InsertTrackAtIndex(ip + 1, true)
    novo = r.GetTrack(0, ip + 1)
    r.SetMediaTrackInfo_Value(pai, "I_FOLDERDEPTH", 1)
    r.SetMediaTrackInfo_Value(novo, "I_FOLDERDEPTH", d - 1)
  else
    local n = r.CountTracks(0)
    local nivel, ultimo, dj, Lj = 1, nil, nil, nil
    for j = ip + 1, n - 1 do
      local dd = math.floor(r.GetMediaTrackInfo_Value(r.GetTrack(0, j), "I_FOLDERDEPTH"))
      local L = nivel - 1
      nivel = nivel + dd
      if nivel <= 0 then ultimo, dj, Lj = j, dd, L; break end
    end
    if not ultimo then -- pasta "aberta" até o fim do projeto
      ultimo = n - 1
      dj = math.floor(r.GetMediaTrackInfo_Value(r.GetTrack(0, ultimo), "I_FOLDERDEPTH"))
      Lj = nivel - 1 - dj
      if Lj < 0 then Lj = 0 end
      dj = -(Lj + 1)
    end
    r.InsertTrackAtIndex(ultimo + 1, true)
    novo = r.GetTrack(0, ultimo + 1)
    r.SetMediaTrackInfo_Value(r.GetTrack(0, ultimo), "I_FOLDERDEPTH", -Lj)
    r.SetMediaTrackInfo_Value(novo, "I_FOLDERDEPTH", dj + Lj)
  end
  nova_trilha_config(novo, nome, cor)
  return novo
end

local rampa_em_curso  -- definida mais abaixo (PAD)
-- Cria/repara: FONE (CLICK, GUIA) e BANDA (subpastas + PAD)
function M.garantir_estrutura(sem_mute_pad)
  local fone = M.achar_fone()
  if not fone then
    r.InsertTrackAtIndex(0, true)
    fone = r.GetTrack(0, 0)
    nova_trilha_config(fone, M.CFG.NOME_FONE, M.COR_FONE)
    r.SetMediaTrackInfo_Value(fone, "I_FOLDERDEPTH", 0)
  end
  if not M.achar_filho(fone, M.CFG.NOME_CLICK) then M.inserir_filho_no_fim(fone, M.CFG.NOME_CLICK, M.COR_FONE) end
  if not M.achar_filho(fone, M.CFG.NOME_GUIA) then M.inserir_filho_no_fim(fone, M.CFG.NOME_GUIA, M.COR_FONE) end

  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  if not banda then
    local n = r.CountTracks(0)
    r.InsertTrackAtIndex(n, true)
    banda = r.GetTrack(0, n)
    nova_trilha_config(banda, M.CFG.NOME_BANDA, M.COR_BANDA)
    r.SetMediaTrackInfo_Value(banda, "I_FOLDERDEPTH", 0)
  end
  for _, sp in ipairs(M.SUBPASTAS) do
    if not M.achar_filho(banda, sp.nome) then M.inserir_filho_no_fim(banda, sp.nome, sp.cor) end
  end
  local pad = M.achar_filho(banda, M.CFG.NOME_PAD)
  if not pad then
    pad = M.inserir_filho_no_fim(banda, M.CFG.NOME_PAD, M.COR_PAD)
    r.SetMediaTrackInfo_Value(pad, "D_VOL", M.CFG.PAD_VOLUME)
  end
  if not sem_mute_pad and not rampa_em_curso() then r.SetMediaTrackInfo_Value(pad, "B_MUTE", M.flag("PAD") and 0 or 1) end
  r.TrackList_AdjustWindows(false)
  return fone, banda
end

function M.subpasta(id)
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  if not banda then return nil end
  for _, sp in ipairs(M.SUBPASTAS) do
    if sp.id == id then return M.achar_filho(banda, sp.nome), sp end
  end
end

-------------------------------------------------------------------------------
-- ROTEAMENTO: AO VIVO x L/R
-------------------------------------------------------------------------------
--[[
  Solução escolhida (robusta e sem plugin): tudo vai para o MASTER, que sai
  nas saídas 1/2 da interface. A separação é feita com o PAN "duplo" (dual pan)
  das pastas:
    AO VIVO : FONE  -> canal L (saída 1)  | BANDA -> canal R (saída 2)
              (o dual pan com L e R no mesmo lado soma o estéreo em mono)
    L/R     : FONE  mudo (ou junto, se "L/R com click")
              BANDA estéreo normal nas saídas 1/2
  Não coloque no MASTER plugins que misturem os canais (reverb, imager...).
]]
function M.modo() return M.get("MODO", "AO_VIVO") end

local function dual_pan(tr, esq, dir)
  r.SetMediaTrackInfo_Value(tr, "I_PANMODE", 6)       -- 6 = dual pan
  r.SetMediaTrackInfo_Value(tr, "D_DUALPANL", esq)
  r.SetMediaTrackInfo_Value(tr, "D_DUALPANR", dir)
  r.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 1)
end

-------------------------------------------------------------------------------
-- SAÍDAS: detecta a placa de áudio e escolhe o perfil
--   2 canais : (como sempre) tudo pelo MASTER; Click+Guia saída 1, Banda saída 2
--   4 canais : Click -> saída 1 (mono) | Guia -> saída 2 (mono) | Banda (+PAD) -> 3/4 estéreo
--   Personalizado: você escolhe a saída do Click, da Guia e o par da Banda
-- Nos perfis de 4+ canais, as pastas FONE e BANDA saem por "saídas de hardware"
-- (HW out) e NÃO vão para o MASTER. Só o modo AO VIVO usa o perfil; L/R e Studio
-- continuam estéreo nas saídas 1/2.
-------------------------------------------------------------------------------
M.PERFIS_SAIDA = {
  { id = "AUTO",   nome = "Automático (pela placa)" },
  { id = "2",      nome = "2 canais (1 = Click+Guia, 2 = VS)" },
  { id = "4",      nome = "4 canais (1 = Click, 2 = Guia, 3/4 = VS estéreo)" },
  { id = "CUSTOM", nome = "Personalizado" },
}

function M.info_placa()
  local n = 0
  if r.GetNumAudioOutputs then n = tonumber(r.GetNumAudioOutputs()) or 0 end
  local canais, i = {}, 0
  while i < 64 do
    local c = r.GetOutputChannelName and r.GetOutputChannelName(i) or nil
    local tem_nome = c and c ~= ""
    if i >= n and not tem_nome then break end
    canais[i + 1] = tem_nome and c or ("Saída " .. (i + 1))
    i = i + 1
  end
  if i > n then n = i end
  local function adev(attr)
    if not r.GetAudioDeviceInfo then return "" end
    local ok, a, b = pcall(r.GetAudioDeviceInfo, attr, "")
    if not ok then ok, a, b = pcall(r.GetAudioDeviceInfo, attr) end
    if not ok then return "" end
    if type(a) == "string" then return a end
    if a and type(b) == "string" then return b end
    return ""
  end
  local modo, ident = adev("MODE"), adev("IDENT_OUT")
  if ident == "" then ident = adev("IDENT_IN") end
  local nome = ident
  if modo ~= "" and ident ~= "" and not ident:lower():find(modo:lower(), 1, true) then
    nome = modo .. " · " .. ident
  elseif modo ~= "" and ident == "" then
    nome = modo
  end
  local aviso
  local baixo = ((modo or "") .. " " .. (ident or "")):lower()
  if n > 0 and n < 4 and (baixo:find("asio4all", 1, true) or baixo:find("asio 4 all", 1, true)) then
    aviso = "O ASIO4ALL está com só " .. n .. " saída(s) no REAPER. Se a placa tem 4 ou mais, abra o painel do ASIO4ALL e ligue as saídas 3 e 4 (ou use o driver ASIO da própria placa)."
  end
  return { n = n, nome = nome, modo = modo, ident = ident, canais = canais, aviso = aviso }
end

function M.perfil_saidas() return M.get("SAIDAS_PERFIL", "AUTO") end

-- Resolve o perfil para esta placa: { perfil = "2"|"4"|"CUSTOM", click, guia, banda, aviso }
-- cfg (opcional) = { perfil, click, guia, banda } para prévia sem salvar
function M.roteamento_efetivo(info, cfg)
  info = info or M.info_placa()
  cfg = cfg or {}
  local n, p = info.n or 0, cfg.perfil or M.perfil_saidas()
  local function existe(c) return c and c >= 1 and c <= n end
  if p == "AUTO" then p = (n >= 4) and "4" or "2" end
  local aviso = info.aviso
  if p == "4" then
    if n < 4 then
      return { perfil = "2", click = 1, guia = 1, banda = 2,
        aviso = aviso or ("a placa tem só " .. n .. " saída(s): usando 2 canais (1=Click+Guia, 2=VS)") }
    end
    return { perfil = "4", click = 1, guia = 2, banda = 3, aviso = aviso }
  elseif p == "CUSTOM" then
    local c = tonumber(cfg.click or M.get("SAIDA_CLICK", "1"))
    local g = tonumber(cfg.guia or M.get("SAIDA_GUIA", "2"))
    local b = tonumber(cfg.banda or M.get("SAIDA_BANDA", "3"))
    if existe(c) and existe(g) and existe(b) and existe(b + 1) then
      return { perfil = "CUSTOM", click = c, guia = g, banda = b, aviso = aviso }
    end
    if n >= 4 then
      return { perfil = "4", click = 1, guia = 2, banda = 3,
        aviso = aviso or "as saídas personalizadas não existem nesta placa: usando 4 canais" }
    end
    return { perfil = "2", click = 1, guia = 1, banda = 2,
      aviso = aviso or "as saídas personalizadas não existem nesta placa: usando 2 canais" }
  end
  return { perfil = "2", click = 1, guia = 1, banda = 2, aviso = aviso }
end

function M.descrever_roteamento(rot, modo)
  modo = modo or M.modo()
  if modo == "LR" then
    return (M.get("LR_COM_CLICK", "0") == "1") and "Studio (estéreo + click)" or "L/R estéreo"
  end
  rot = rot or {}
  if rot.perfil == "2" then return "Ao Vivo 2 canais (1=Click+Guia  2=VS)" end
  return string.format("Ao Vivo %s (%s=Click  %s=Guia  %s/%s=VS estéreo)",
    rot.perfil == "4" and "4 canais" or "personalizado",
    tostring(inteiro(rot.click, 1)), tostring(inteiro(rot.guia, 2)),
    tostring(inteiro(rot.banda, 3)), tostring(inteiro(rot.banda, 3) + 1))
end

local function limpar_hwouts(tr)
  for i = r.GetTrackNumSends(tr, 1) - 1, 0, -1 do r.RemoveTrackSend(tr, 1, i) end
end

local function hwout(tr, src, dst)
  local i = r.CreateTrackSend(tr, nil)
  if i < 0 then return end
  r.SetTrackSendInfo_Value(tr, 1, i, "I_SRCCHAN", src)
  r.SetTrackSendInfo_Value(tr, 1, i, "I_DSTCHAN", dst)
  r.SetTrackSendInfo_Value(tr, 1, i, "I_SENDMODE", 0)   -- pós-fader (respeita volume e mute)
  r.SetTrackSendInfo_Value(tr, 1, i, "D_VOL", 1)
  r.SetTrackSendInfo_Value(tr, 1, i, "D_PAN", 0)
end

local function filhos_diretos(pai)
  local t = {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetParentTrack(tr) == pai then t[#t + 1] = tr end
  end
  return t
end

local function balanco_centro(tr)
  r.SetMediaTrackInfo_Value(tr, "I_PANMODE", 3)
  r.SetMediaTrackInfo_Value(tr, "D_PAN", 0)
end

-- ---------------------------------------------------------------------------
-- Renomeia as saídas de hardware no REAPER (aliases em reaper.ini).
-- Seção: [alias_out_<MODE>_<IDENT_OUT>]  (Preferences > Audio > Output aliasing)
-- Vale na próxima abertura do dispositivo de áudio / do REAPER.
-- ---------------------------------------------------------------------------
local function ini_ler(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local d = f:read("*a"); f:close()
  return d
end
local function ini_gravar(p, d)
  local f = io.open(p, "wb")
  if not f then return false end
  f:write(d); f:close()
  return true
end
local function ini_nl(d) return (d:find("\r\n", 1, true) and "\r\n") or "\n" end

function M.secao_alias_saidas(info)
  info = info or M.info_placa()
  local modo = tostring(info.modo or ""):gsub("[%c%]]", "")
  local ident = tostring(info.ident or info.nome or ""):gsub("[%c%]]", "")
  if modo == "" then modo = "Audio" end
  if ident == "" then ident = "Device" end
  return "alias_out_" .. modo .. "_" .. ident
end

function M.nomes_alias_saidas(rot, n)
  local nomes = {}
  for i = 1, math.max(n or 0, 0) do nomes[i] = "" end
  if not rot then return nomes end
  if rot.perfil == "2" then
    nomes[1] = "CLICK+GUIA"
    nomes[2] = "VS"
  else
    if rot.click then nomes[rot.click] = "CLICK" end
    if rot.guia then nomes[rot.guia] = "GUIA" end
    if rot.banda then nomes[rot.banda] = "VS L"; nomes[rot.banda + 1] = "VS R" end
  end
  return nomes
end

-- Escreve os aliases no reaper.ini e liga "Output channel name aliasing".
-- Devolve: ok, msg, mudou
function M.gravar_alias_saidas(rot, info)
  info = info or M.info_placa()
  rot = rot or M.roteamento_efetivo(info)
  local n = info.n or 0
  if n <= 0 then return false, "áudio fechado", false end
  local ini = r.get_ini_file and r.get_ini_file() or nil
  if not ini or ini == "" then return false, "reaper.ini não encontrado", false end
  local d = ini_ler(ini)
  if not d then return false, "não consegui ler " .. ini, false end
  local nl = ini_nl(d)
  local secao = M.secao_alias_saidas(info)
  local nomes = M.nomes_alias_saidas(rot, n)
  local linhas = { "[" .. secao .. "]" }
  for i = 1, n do linhas[#linhas + 1] = string.format("ch%d=%d", i - 1, i - 1) end
  linhas[#linhas + 1] = "map_hwnch=" .. n
  linhas[#linhas + 1] = "map_size=" .. n
  for i = 1, n do linhas[#linhas + 1] = string.format("name%d=%s", i - 1, nomes[i] or "") end
  local novo
  do
    local raw = {}
    for linha in (d .. (d:sub(-1) == "\n" and "" or nl)):gmatch("([^\n]*)\n") do
      raw[#raw + 1] = linha:gsub("\r$", "")
    end
    local ini_s, fim_s
    for i, l in ipairs(raw) do
      local s = l:match("^%[(.-)%]$")
      if s then
        if ini_s and not fim_s then fim_s = i - 1 end
        if s == secao then ini_s = i end
      end
    end
    fim_s = fim_s or (ini_s and #raw)
    local out = {}
    if ini_s then
      for i = 1, ini_s - 1 do out[#out + 1] = raw[i] end
      for _, l in ipairs(linhas) do out[#out + 1] = l end
      for i = (fim_s or #raw) + 1, #raw do out[#out + 1] = raw[i] end
    else
      for _, l in ipairs(raw) do out[#out + 1] = l end
      if out[#out] ~= "" then out[#out + 1] = "" end
      for _, l in ipairs(linhas) do out[#out + 1] = l end
    end
    -- useinnc: bit 2 = Output channel name aliasing
    local ini_r, fim_r, idx_u, val_u
    for i, l in ipairs(out) do
      local s = l:match("^%[(.-)%]$")
      if s then
        if ini_r and not fim_r then fim_r = i - 1 end
        if s:upper() == "REAPER" then ini_r = i end
      elseif ini_r and not fim_r then
        local v = l:match("^useinnc=(%-?%d+)")
        if v then idx_u, val_u = i, tonumber(v) end
      end
    end
    local novo_u = (val_u or 0) | 2
    if idx_u then
      if val_u ~= novo_u then out[idx_u] = "useinnc=" .. novo_u end
    elseif ini_r then
      table.insert(out, ini_r + 1, "useinnc=" .. novo_u)
    end
    novo = table.concat(out, nl)
    if not novo:find("\n$") then novo = novo .. nl end
  end
  if novo == d then return true, "aliases já estavam gravados", false end
  if not ini_gravar(ini, novo) then return false, "não consegui gravar " .. ini, false end
  if r.SNM_SetIntConfigVar then
    local v = 0
    if r.SNM_GetIntConfigVar then v = r.SNM_GetIntConfigVar("useinnc", 0) or 0 end
    pcall(r.SNM_SetIntConfigVar, "useinnc", v | 2)
  end
  return true, "aliases gravados em " .. secao .. " (aparecem ao reabrir o dispositivo de áudio)", true
end

function M.assinatura_roteamento(rot, modo)
  return table.concat({ modo, rot.perfil, rot.click or 0, rot.guia or 0, rot.banda or 0,
    M.get("LR_COM_CLICK", "0") }, ":")
end

function M.aplicar_modo(modo, rot)
  modo = modo or M.modo()
  if modo ~= "LR" then modo = "AO_VIVO" end
  rot = rot or M.roteamento_efetivo()
  local fone, banda = M.garantir_estrutura()
  -- limpa o que o kit coloca nas pastas FONE e BANDA
  limpar_hwouts(fone); limpar_hwouts(banda)
  r.SetMediaTrackInfo_Value(fone, "I_NCHAN", 2)
  for _, f in ipairs(filhos_diretos(fone)) do
    r.SetMediaTrackInfo_Value(f, "C_MAINSEND_OFFS", 0)
    r.SetMediaTrackInfo_Value(f, "C_MAINSEND_NCH", 0)
  end
  if modo == "LR" then
    dual_pan(fone, -1, 1)
    dual_pan(banda, -1, 1)
    local mudo = M.get("LR_COM_CLICK", "0") ~= "1"
    if mudo and (M.flag("SOLO_CLICK") or M.flag("REPETIR_CLICK")) then mudo = false end
    r.SetMediaTrackInfo_Value(fone, "B_MUTE", mudo and 1 or 0)
  elseif rot.perfil == "2" then
    -- 2 canais: tudo pelo MASTER. Click+Guia somados na saída 1, VS (banda+PAD) na saída 2.
    dual_pan(fone, -1, -1)
    dual_pan(banda, 1, 1)
    r.SetMediaTrackInfo_Value(fone, "B_MUTE", 0)
    r.SetMediaTrackInfo_Value(banda, "B_MAINSEND", 1)
  else
    -- 4+ canais: FONE com 4 canais internos (1/2 = click, 3/4 = guia)
    -- HW out: click -> 1 mono, guia -> 2 mono, VS (BANDA + PAD) -> 3/4 estéreo linkado
    -- master send DESLIGADO nessas pastas, para o VS não vazar também nas saídas 1/2
    r.SetMediaTrackInfo_Value(fone, "I_NCHAN", 4)
    local guia = M.norm(M.CFG.NOME_GUIA)
    for _, f in ipairs(filhos_diretos(fone)) do
      local eh_guia = M.norm(M.nome_trilha(f)) == guia
      r.SetMediaTrackInfo_Value(f, "C_MAINSEND_OFFS", eh_guia and 2 or 0)
      r.SetMediaTrackInfo_Value(f, "C_MAINSEND_NCH", 2)
    end
    balanco_centro(fone); balanco_centro(banda)
    r.SetMediaTrackInfo_Value(fone, "B_MAINSEND", 0)
    r.SetMediaTrackInfo_Value(banda, "B_MAINSEND", 0)
    hwout(fone, 0, 1024 + (rot.click - 1))   -- canais 1/2 (click) -> saída mono
    hwout(fone, 2, 1024 + (rot.guia - 1))    -- canais 3/4 (guia)  -> saída mono
    hwout(banda, 0, rot.banda - 1)           -- VS estéreo -> par de saídas (3/4)
    r.SetMediaTrackInfo_Value(fone, "B_MUTE", 0)
  end
  -- master estéreo, sem mono (monitoração 1/2 permanece; pastas roteadas não enviam a ele no perfil 4+)
  local master = r.GetMasterTrack(0)
  r.SetMediaTrackInfo_Value(master, "D_PAN", 0)
  r.SetMediaTrackInfo_Value(master, "D_WIDTH", 1)
  M.set("MODO", modo)
  r.SetProjExtState(0, M.SEC, "ROTEAMENTO", M.assinatura_roteamento(rot, modo))
  pcall(M.gravar_alias_saidas, rot, M.info_placa())
  M.sincronizar_botoes()
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  return rot
end

-- Chamado ~2x por segundo (motor/painel): reaplica se mudou a placa, o projeto ou o perfil
local verif_saidas = { proj = nil, chave = nil, t = 0 }
function M.verificar_saidas(forcar)
  local agora = r.time_precise()
  if not forcar and agora - verif_saidas.t < 1.0 then return end
  verif_saidas.t = agora
  local info = M.info_placa()
  if info.n <= 0 and not forcar then return end         -- áudio fechado: não mexe
  local proj = tostring(r.EnumProjects(-1))
  local rot = M.roteamento_efetivo(info)
  local chave = proj .. "|" .. (info.ident or info.nome or "") .. "|" .. info.n .. "|" .. M.assinatura_roteamento(rot, M.modo())
  if not forcar and chave == verif_saidas.chave then return end
  verif_saidas.chave = chave
  if not (M.achar_fone() and M.achar_trilha(M.CFG.NOME_BANDA)) then return end   -- projeto sem estrutura
  local _, atual = r.GetProjExtState(0, M.SEC, "ROTEAMENTO")
  if forcar or atual ~= M.assinatura_roteamento(rot, M.modo()) then
    M.aplicar_modo(M.modo(), rot)
    local txt = "Saídas: " .. M.descrever_roteamento(rot) .. (info.nome ~= "" and ("  [" .. info.nome .. "]") or "")
    if rot.aviso then txt = txt .. "\n" .. rot.aviso end
    if forcar or verif_saidas.proj == proj then
      M.aviso(txt)
    end
  end
  verif_saidas.proj = proj
end

function M.definir_perfil_saidas(perfil, click, guia, banda)
  M.set("SAIDAS_PERFIL", perfil)
  if click then M.set("SAIDA_CLICK", tostring(click)) end
  if guia then M.set("SAIDA_GUIA", tostring(guia)) end
  if banda then M.set("SAIDA_BANDA", tostring(banda)) end
  r.Undo_BeginBlock()
  local rot = M.aplicar_modo()
  r.Undo_EndBlock("Saídas: " .. M.descrever_roteamento(rot), -1)
  return rot
end

function M.modo_ao_vivo()
  r.Undo_BeginBlock()
  local rot = M.aplicar_modo("AO_VIVO")
  r.Undo_EndBlock("Modo AO VIVO", -1)
  M.aviso("MODO " .. M.descrever_roteamento(rot, "AO_VIVO"):upper() .. (rot.aviso and ("\n" .. rot.aviso) or ""))
end

function M.modo_lr()
  r.Undo_BeginBlock()
  M.aplicar_modo("LR")
  r.Undo_EndBlock("Modo L/R (banda estéreo)", -1)
  M.aviso("MODO L/R: banda estéreo nas saídas 1/2" .. (M.get("LR_COM_CLICK", "0") == "1" and " (com click)" or " (sem click)"))
end

function M.alternar_lr_com_click()
  M.set("LR_COM_CLICK", M.get("LR_COM_CLICK", "0") == "1" and "0" or "1")
  if M.modo() == "LR" then M.aplicar_modo("LR") end
end

-------------------------------------------------------------------------------
-- TRANSPOSIÇÃO (TOM - / +)
-------------------------------------------------------------------------------
-- Transpõe só a BANDA (CLICK e GUIA nunca são transpostos), mudando o pitch
-- dos itens de áudio da música atual sem mudar o andamento.
function M.aplicar_transp(m, semitons)
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  if not banda then return end
  local pad = M.achar_filho(banda, M.CFG.NOME_PAD)
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if tr ~= pad and M.descende_de(tr, banda) then
      for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
        local it = r.GetTrackMediaItem(tr, k)
        local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
        local l = r.GetMediaItemInfo_Value(it, "D_LENGTH")
        if p < m.fim - 0.001 and p + l > m.inicio + 0.001 then
          r.SetMediaItemInfo_Value(it, "B_PPITCH", 1)
          for t = 0, r.CountTakes(it) - 1 do
            local tk = r.GetTake(it, t)
            if tk and not r.TakeIsMIDI(tk) then r.SetMediaItemTakeInfo_Value(tk, "D_PITCH", semitons) end
          end
        end
      end
    end
  end
end

function M.mudar_tom(delta, absoluto)
  local m = M.musica_atual()
  if not m then return M.aviso("Nenhuma música no projeto") end
  local v = absoluto and delta or (M.get_transp(m) + delta)
  if v < M.CFG.TOM_MIN then v = M.CFG.TOM_MIN end
  if v > M.CFG.TOM_MAX then v = M.CFG.TOM_MAX end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  M.set_transp_valor(m, v)
  M.aplicar_transp(m, v)
  if m.tom then M.gerar_pad(m) end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Tom da música: " .. v .. " semitons", -1)
  local txt = string.format("TOM %s%d", v > 0 and "+" or "", v)
  if m.tom then txt = txt .. string.format("  (%s -> %s)", m.tom, M.tom_soando(m)) end
  M.aviso(m.nome .. ": " .. txt)
end
function M.tom_mais() M.mudar_tom(1) end
function M.tom_menos() M.mudar_tom(-1) end
function M.tom_zerar() M.mudar_tom(0, true) end

-- Define/renomeia o tom ORIGINAL da música atual (fica no nome da região)
function M.definir_tom()
  local m = M.musica_atual()
  if not m then return M.aviso("Nenhuma música no projeto") end
  local ok, txt = r.GetUserInputs("Tom original de: " .. m.nome, 1,
    "Tom (ex.: G  Bb  F#m),extrawidth=80", m.tom or "")
  if not ok then return end
  txt = trim(txt)
  if txt ~= "" and not M.ler_tom(txt) then
    return r.MB("Tom inválido: " .. txt .. "\nUse por exemplo: C, G, Bb, F#, Am, C#m", "Definir tom", 0)
  end
  r.Undo_BeginBlock()
  local novo = m.nome .. (txt ~= "" and (" [" .. txt .. "]") or "")
  r.SetProjectMarker3(0, m.idx, true, m.inicio, m.fim, novo, m.cor)
  m.tom = (txt ~= "" and txt) or nil
  if m.tom then M.gerar_pad(m) end
  r.Undo_EndBlock("Definir tom da música", -1)
end

-------------------------------------------------------------------------------
-- PAD NO TOM DA MÚSICA
-------------------------------------------------------------------------------
--[[
  Para cada música com tom definido, é criado um item na trilha "PAD (Tom)"
  cobrindo a música inteira:
   1) Se existir na pasta  Scripts\MultitrackAoVivo\pads\  um arquivo de áudio
      com o nome do tom (ex.: "C.wav", "C#.wav" ou "Db.wav", "Pad Bb.wav"),
      ele é usado em loop (melhor som).
   2) Senão, é criado um item MIDI (tônica + quinta + oitava) tocado pelo
      ReaSynth + ReaVerbate (nativos), que funciona em qualquer REAPER.
  O botão PAD liga/desliga (mute) a trilha. Mudando o TOM, o pad acompanha.
]]
local EXT_AUDIO = { wav = true, mp3 = true, flac = true, aif = true, aiff = true, ogg = true, m4a = true, wv = true }

-- ---------------------------------------------------------------- pacotes de pads
-- Biblioteca\_PADS\            -> arquivos soltos (pacote "(pasta _PADS)")
-- Biblioteca\_PADS\<Pacote>\   -> um pacote por subpasta (ex.: "Worship Pads")
M.PASTA_PADS = "_PADS"
local SOLFEJO = { ["do"] = 0, re = 2, mi = 4, fa = 5, sol = 7, la = 9, si = 11 }
local ACENTOS = { ["á"]="a", ["à"]="a", ["â"]="a", ["ã"]="a", ["é"]="e", ["ê"]="e", ["í"]="i", ["ó"]="o", ["ô"]="o",
  ["õ"]="o", ["ú"]="u", ["ç"]="c", ["Á"]="A", ["É"]="E", ["Í"]="I", ["Ó"]="O", ["Ú"]="U", ["♯"]="#", ["♭"]="b" }

local function sem_acento(s)
  for k, v in pairs(ACENTOS) do s = s:gsub(k, v) end
  return s
end

local QUAL_MENOR = { m = true, min = true, minor = true, menor = true, moll = true }
local QUAL_MAIOR = { M = true, maj = true, major = true, maior = true, dur = true }
local SUST = { ["#"] = 1, sharp = 1, sustenido = 1, s = 1 }
local BEMOL = { b = -1, flat = -1, bemol = -1 }

-- Lê o tom de um nome de arquivo de pad. Retorna semitom (0-11), qualidade ("menor"|"maior"|nil)
-- Ex.: "Pad D", "D Major", "Warm Pad - C#", "Eb (D#)", "Re", "Ré menor", "Sib", "Dm", "F#maj", "pad_ab_minor"
function M.tom_do_arquivo(base)
  local s = sem_acento(base)
  s = s:gsub("[_%-%.%(%)%[%]{},+]", " "):gsub("(%d)", " %1 ")
  local tk = {}
  for w in s:gmatch("%S+") do tk[#tk + 1] = w end
  local function qual(w)
    if not w then return nil end
    if QUAL_MENOR[w:lower()] or w == "m" then return "menor" end
    if QUAL_MAIOR[w] or QUAL_MAIOR[w:lower()] then return "maior" end
  end
  local function nota(i)
    local w = tk[i]
    -- notação inglesa: letra MAIÚSCULA (ou minúscula se for a palavra toda), acidente e qualidade colados
    local L, ac, resto = w:match("^([A-Ga-g])([#b]?)(.*)$")
    if L and (L:match("%u") or #w <= 2 or QUAL_MENOR[resto:lower()] or QUAL_MAIOR[resto:lower()]) then
      local ok_resto = resto == "" or qual(resto) or resto:lower() == "s" or resto:lower() == "sharp" or resto:lower() == "flat"
      if ok_resto and not (L:match("%l") and ac == "" and resto == "" and #tk > 1 and i ~= #tk and not qual(tk[i + 1])) then
        local n = NOTA_BASE[L:upper()]
        if ac == "#" or resto:lower() == "s" or resto:lower() == "sharp" then n = n + 1
        elseif ac == "b" or resto:lower() == "flat" then n = n - 1 end
        local q = qual(resto)
        local prox = tk[i + 1]
        if prox and ac == "" and SUST[prox:lower()] then n = n + 1; prox = tk[i + 2]
        elseif prox and ac == "" and BEMOL[prox:lower()] and #prox > 1 then n = n - 1; prox = tk[i + 2] end
        q = q or qual(prox)
        return n % 12, q
      end
    end
    -- solfejo: Do Re Mi Fa Sol La Si (+ # / b / sustenido / bemol / m / menor)
    local raiz, ac2, resto2 = w:lower():match("^(%a%a%a?)([#b]?)(.*)$")
    local base_s = raiz and SOLFEJO[raiz]
    if not base_s and raiz and #raiz == 3 and SOLFEJO[raiz:sub(1, 2)] then
      -- "sib", "mib", "lab" ...
      local r2 = raiz:sub(1, 2)
      if raiz:sub(3) == "b" then base_s, ac2, resto2 = SOLFEJO[r2], "b", ac2 .. resto2
      elseif raiz:sub(3) == "m" and ac2 == "" and resto2 == "" then base_s, resto2 = SOLFEJO[r2], "m" end
    end
    if base_s and (resto2 == "" or qual(resto2)) then
      local n = base_s
      if ac2 == "#" then n = n + 1 elseif ac2 == "b" then n = n - 1 end
      local prox = tk[i + 1]
      if prox and ac2 == "" and (SUST[prox:lower()] and #prox > 1 or prox == "#") then n = n + 1; prox = tk[i + 2]
      elseif prox and ac2 == "" and BEMOL[prox:lower()] and #prox > 1 then n = n - 1; prox = tk[i + 2] end
      return n % 12, qual(resto2 ~= "" and resto2 or nil) or qual(prox)
    end
  end
  for i = #tk, 1, -1 do
    local w = tk[i]:lower()
    local palavra = #w > 1 and (QUAL_MENOR[w] or QUAL_MAIOR[w] or SUST[w] or BEMOL[w])
    if not palavra or #tk == 1 then
      local n, q = nota(i)
      if n then return n, q end
    end
  end
  return nil
end

function M.pasta_pads_raiz() return M.pasta_biblioteca() .. SEP .. M.PASTA_PADS end

function M.garantir_pasta_pads()
  local p = M.pasta_pads_raiz()
  r.RecursiveCreateDirectory(p, 0)
  local leia = p .. SEP .. "LEIA-ME.txt"
  local f = io.open(leia, "r")
  if f then f:close() else
    f = io.open(leia, "w")
    if f then
      f:write("PADS DO MIK SEIFADOR\r\n====================\r\n\r\n",
        "Coloque aqui os seus pads (um arquivo por tom). Cada PACOTE pode ficar numa subpasta:\r\n",
        "   _PADS\\Worship Pads\\Pad C.wav, Pad C#.wav, Pad D.wav ...\r\n",
        "   _PADS\\Ambient\\D Major.mp3, Re.flac, Eb.ogg ...\r\n\r\n",
        "O tom é lido do nome do arquivo: C, C#, Db, D, D#, Eb ... B, ou Do, Re, Mi, Fa, Sol, La, Si\r\n",
        "(com #, b, sustenido, bemol). Menor: 'Am', 'A minor', 'La menor'.\r\n",
        "Formatos: wav, mp3, flac, ogg, aif/aiff, m4a.\r\n\r\n",
        "Padrão: Pad contínuo (pads longos, um por tom). Também: Pad clássico (MIDI/ReaSynth).\r\nNo Menu: Importar pasta de pads… (escolhe uma pasta com 12 arquivos, tipo C-PAD.mp3).\r\n",
        "No painel: Menu > Pacote de pads (ou clique com o botão direito no botão PAD).\r\n",
        "Sem arquivo para o tom, o Mik Seifador usa um pad simples do ReaSynth.\r\n")
      f:close()
    end
  end
  return p
end

function M.listar_pacotes_pads()
  local raiz = M.pasta_pads_raiz()
  local t = {}
  r.EnumerateSubdirectories(raiz, -1)
  local j = 0
  while true do
    local d = r.EnumerateSubdirectories(raiz, j)
    if not d then break end
    if d:sub(1, 1) ~= "." then t[#t + 1] = d end
    j = j + 1
  end
  table.sort(t, function(a, b) return a:lower() < b:lower() end)
  return t
end

M.PACOTE_PAD_CONTINUO = "Pad contínuo"
M.PACOTE_PAD_CLASSICO = "Pad clássico"

function M.pacote_pads()
  local p = M.get("PAD_PACOTE", M.PACOTE_PAD_CONTINUO)
  -- shimmer foi removido na v1.8; quem ainda tiver esse pacote escolhido volta ao padrão
  if p == "Shimmer" or p == "Pad shimmer" then
    M.set("PAD_PACOTE", M.PACOTE_PAD_CONTINUO)
    return M.PACOTE_PAD_CONTINUO
  end
  return p
end

function M.eh_pad_classico()
  return M.pacote_pads() == M.PACOTE_PAD_CLASSICO
end

function M.rotulo_pacote_pads(nome)
  if nome == M.PACOTE_PAD_CLASSICO then return "Pad clássico (MIDI / ReaSynth)" end
  if nome == M.PACOTE_PAD_CONTINUO then return "Pad contínuo (padrão)" end
  if not nome or nome == "" then return "(arquivos soltos na pasta _PADS)" end
  return nome
end

-- arquivos de pad de uma pasta: lista de { arq, semi, qual }
local cache_pads = {}
local function pads_da_pasta(pasta, recarregar)
  if cache_pads[pasta] and not recarregar then return cache_pads[pasta] end
  local lista = {}
  r.EnumerateFiles(pasta, -1)
  local i = 0
  while true do
    local f = r.EnumerateFiles(pasta, i)
    if not f then break end
    local base, ext = f:match("^(.*)%.([^%.]+)$")
    if base and EXT_AUDIO[ext:lower()] and f:sub(1, 2) ~= "._" then
      local n, q = M.tom_do_arquivo(base)
      if n then lista[#lista + 1] = { arq = pasta .. SEP .. f, semi = n, qual = q, nome = f } end
    end
    i = i + 1
  end
  table.sort(lista, function(a, b) return a.nome:lower() < b.nome:lower() end)
  cache_pads[pasta] = lista
  return lista
end
M.pads_da_pasta = pads_da_pasta
function M.recarregar_pads() cache_pads = {} end

local function escolher_pad(lista, semi, menor)
  local exato, raiz, relativo
  for _, p in ipairs(lista) do
    if p.semi == semi then
      if menor and p.qual == "menor" then exato = exato or p
      elseif not menor and p.qual ~= "menor" then exato = exato or p
      elseif menor then raiz = raiz or p end
    elseif menor and p.semi == (semi + 3) % 12 and p.qual ~= "menor" then relativo = relativo or p end
  end
  -- menor sem pad menor: o da mesma tônica (pads costumam ser tônica+quinta), senão o relativo maior
  return exato or raiz or relativo
end

-- Procura o pad do tom: pacote escolhido -> _PADS -> Scripts\MultitrackAoVivo\pads
-- "Pad clássico" força o pad MIDI (ReaSynth), ignorando os arquivos.
function M.arquivo_pad(semitom, menor)
  if M.eh_pad_classico and M.eh_pad_classico() then return nil end
  semitom = semitom % 12
  local pastas = {}
  local pac = M.pacote_pads()
  local raiz = M.pasta_pads_raiz()
  if pac ~= "" then pastas[#pastas + 1] = raiz .. SEP .. pac end
  pastas[#pastas + 1] = raiz
  for _, d in ipairs(M.listar_pacotes_pads()) do         -- outros pacotes, se o escolhido não tiver o tom
    if d ~= pac then pastas[#pastas + 1] = raiz .. SEP .. d end
  end
  pastas[#pastas + 1] = M.DIR .. "pads"
  for _, pasta in ipairs(pastas) do
    local p = escolher_pad(pads_da_pasta(pasta), semitom, menor)
    if p then return p.arq, pasta end
  end
  return nil
end

local function garantir_synth(tr)
  if r.TrackFX_GetCount(tr) > 0 then return end
  local fx = r.TrackFX_AddByName(tr, "ReaSynth (Cockos)", false, -1)
  if fx < 0 then fx = r.TrackFX_AddByName(tr, "ReaSynth", false, -1) end
  if fx >= 0 then
    -- ajusta para um som de "pad" (ataque e release lentos, onda suave)
    -- valores normalizados (0..1) conferidos no ReaSynth do REAPER 7
    local ajustes = {
      ["attack"] = 0.3,         -- 1500 ms
      ["decay"] = 0.2,          -- 3000 ms
      ["sustain"] = 0.5,        -- 0 dB
      ["release"] = 0.5,        -- 2500 ms
      ["square mix"] = 0, ["saw mix"] = 0, ["triangle mix"] = 1,
    }
    for p = 0, r.TrackFX_GetNumParams(tr, fx) - 1 do
      local _, nome = r.TrackFX_GetParamName(tr, fx, p, "")
      local v = ajustes[nome:lower()]
      if v then r.TrackFX_SetParamNormalized(tr, fx, p, v) end
    end
  end
  local rv = r.TrackFX_AddByName(tr, "ReaVerbate (Cockos)", false, -1)
  if rv < 0 then rv = r.TrackFX_AddByName(tr, "ReaVerbate", false, -1) end
end

function M.apagar_itens_no_intervalo(tr, ini, fim)
  for k = r.GetTrackNumMediaItems(tr) - 1, 0, -1 do
    local it = r.GetTrackMediaItem(tr, k)
    local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local l = r.GetMediaItemInfo_Value(it, "D_LENGTH")
    if p < fim - 0.001 and p + l > ini + 0.001 then r.DeleteTrackMediaItem(tr, it) end
  end
end

function M.gerar_pad(m)
  if not m or not m.tom then return false end
  local n, menor = M.ler_tom(m.tom)
  if not n then return false end
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  local tr = banda and M.achar_filho(banda, M.CFG.NOME_PAD)
  if not tr then M.garantir_estrutura(); banda = M.achar_trilha(M.CFG.NOME_BANDA); tr = M.achar_filho(banda, M.CFG.NOME_PAD) end
  if not tr then return false end
  local semi = (n + M.get_transp(m)) % 12
  M.apagar_itens_no_intervalo(tr, m.inicio, m.fim)
  local arq = M.arquivo_pad(semi, menor)
  local it
  if arq then
    it = r.AddMediaItemToTrack(tr)
    r.SetMediaItemInfo_Value(it, "D_POSITION", m.inicio)
    r.SetMediaItemInfo_Value(it, "D_LENGTH", m.fim - m.inicio)
    r.SetMediaItemInfo_Value(it, "B_LOOPSRC", 1)  -- arquivo longo: cobre a música; se acabar, entra em loop
    r.SetMediaItemInfo_Value(it, "C_BEATATTACHMODE", 0)
    local tk = r.AddTakeToMediaItem(it)
    r.SetMediaItemTake_Source(tk, r.PCM_Source_CreateFromFile(arq))
    local nome_arq = arq:match("([^\\/]+)$") or arq
    r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "PAD " .. M.nome_tom(semi, menor) .. " - " .. nome_arq, true)
  else
    garantir_synth(tr)
    it = r.CreateNewMIDIItemInProj(tr, m.inicio, m.fim, false)
    local tk = r.GetActiveTake(it)
    local p0 = r.MIDI_GetPPQPosFromProjTime(tk, m.inicio)
    local p1 = r.MIDI_GetPPQPosFromProjTime(tk, m.fim)
    local raiz = M.CFG.PAD_OITAVA_BASE + semi
    if semi > 6 then raiz = raiz - 12 end
    for _, iv in ipairs({ 0, 7, 12, 19 }) do
      r.MIDI_InsertNote(tk, false, false, p0, p1, 0, raiz + iv, iv == 19 and 60 or 85, true)
    end
    r.MIDI_Sort(tk)
    r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "PAD " .. M.nome_tom(semi, menor), true)
  end
  r.SetMediaItemInfo_Value(it, "D_FADEINLEN", M.CFG.PAD_FADE)
  r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", M.CFG.PAD_FADE)
  r.GetSetMediaItemInfo_String(it, "P_EXT:MT_PAD", M.assinatura_pad(m), true)
  r.UpdateItemInProject(it)
  return true, arq
end

-- o que o pad desta música DEVERIA ser agora (tom soando + arquivo escolhido)
function M.assinatura_pad(m)
  local n, menor = M.ler_tom(m.tom or "")
  if not n then return "" end
  local semi = (n + M.get_transp(m)) % 12
  return string.format("%d:%s:%s", semi, menor and "m" or "M", M.arquivo_pad(semi, menor) or "synth")
end

-- Confere o pad da música (troca de música / pacote / arquivos novos) e refaz se precisar
function M.conferir_pad(m)
  if not m or not m.tom then return false end
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  local tr = banda and M.achar_filho(banda, M.CFG.NOME_PAD)
  if not tr then return false end
  local esperado = M.assinatura_pad(m)
  for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, k)
    local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
    if p >= m.inicio - 0.01 and p < m.fim then
      local _, a = r.GetSetMediaItemInfo_String(it, "P_EXT:MT_PAD", "", false)
      if a == esperado then return false end
      break
    end
  end
  M.gerar_pad(m)
  return true
end

-- Fade do PAD ao ligar/desligar (rampa de volume na trilha, depois mute)
local rampa_pad = nil
rampa_em_curso = function() return rampa_pad ~= nil end
function M.rampa_pad(ligar)
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  local tr = banda and M.achar_filho(banda, M.CFG.NOME_PAD)
  if not tr then return end
  local alvo = tonumber(M.get("PAD_VOL_ALVO", "")) or M.CFG.PAD_VOLUME
  local atual = r.GetMediaTrackInfo_Value(tr, "D_VOL")
  if r.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1 then atual = 0 end
  if not ligar and atual > 0.001 and not rampa_pad then alvo = atual; M.set("PAD_VOL_ALVO", string.format("%.4f", atual)) end
  local dur = M.CFG.PAD_FADE_BOTAO or 1.5
  local t0, v0, v1 = r.time_precise(), atual, ligar and alvo or 0
  if ligar then r.SetMediaTrackInfo_Value(tr, "D_VOL", v0); r.SetMediaTrackInfo_Value(tr, "B_MUTE", 0) end
  local id = {}
  rampa_pad = id
  local function passo()
    if rampa_pad ~= id or not r.ValidatePtr(tr, "MediaTrack*") then return end
    local k = math.min(1, (r.time_precise() - t0) / dur)
    local v = v0 + (v1 - v0) * (k * k * (3 - 2 * k))
    r.SetMediaTrackInfo_Value(tr, "D_VOL", v)
    if k < 1 then r.defer(passo) return end
    rampa_pad = nil
    if not ligar then
      r.SetMediaTrackInfo_Value(tr, "B_MUTE", 1)
      r.SetMediaTrackInfo_Value(tr, "D_VOL", alvo)   -- o fader volta ao nível normal (mudo)
    end
  end
  passo()
end

function M.definir_pacote_pads(nome)
  M.set("PAD_PACOTE", nome or "")
  M.recarregar_pads()
  r.Undo_BeginBlock()
  local n = 0
  for _, m in ipairs(M.get_musicas()) do if m.tom and M.conferir_pad(m) then n = n + 1 end end
  local rot = (M.rotulo_pacote_pads and M.rotulo_pacote_pads(nome)) or (nome ~= "" and nome or "(pasta _PADS)")
  r.Undo_EndBlock("Pacote de pads: " .. rot, -1)
  M.aviso("Pacote de pads: " .. rot .. "  (" .. n .. " pad(s) atualizados)")
  return n
end

function M.descrever_pad(m)
  if not m or not m.tom then return "sem tom" end
  local n, menor = M.ler_tom(m.tom)
  if not n then return "tom inválido" end
  local semi = (n + M.get_transp(m)) % 12
  if M.eh_pad_classico and M.eh_pad_classico() then
    return M.nome_tom(semi, menor) .. ": Pad clássico (ReaSynth)"
  end
  local arq = M.arquivo_pad(semi, menor)
  return M.nome_tom(semi, menor) .. ": " .. (arq and (arq:match("([^\\/]+)$") or arq) or "ReaSynth (sem arquivo deste tom)")
end

function M.alternar_pad()
  local ligar = not M.flag("PAD")
  M.set_flag("PAD", ligar)
  r.Undo_BeginBlock()
  M.garantir_estrutura(true)  -- cria o que faltar (o mute fica por conta da rampa)
  M.rampa_pad(ligar)
  if ligar then
    local m = M.musica_atual()
    if m and m.tom then
      local banda = M.achar_trilha(M.CFG.NOME_BANDA)
      local tr = M.achar_filho(banda, M.CFG.NOME_PAD)
      local tem = false
      for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
        local it = r.GetTrackMediaItem(tr, k)
        local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
        if p >= m.inicio - 0.01 and p < m.fim then tem = true end
      end
      if not tem then M.gerar_pad(m) else M.conferir_pad(m) end
    end
  end
  r.Undo_EndBlock("PAD liga/desliga", -1)
  local m = M.musica_atual()
  local extra = ""
  if ligar and m and not m.tom then extra = "  (defina o TOM da música para gerar o pad)" end
  M.aviso("PAD: " .. (ligar and "LIGADO" or "DESLIGADO") .. extra)
end

function M.gerar_todos_pads()
  for _, m in ipairs(M.get_musicas()) do if m.tom then M.gerar_pad(m) end end
end

-------------------------------------------------------------------------------
-- CORES DAS SEÇÕES / MARCADORES
-------------------------------------------------------------------------------
function M.cor_secao_rgb(nome)
  local p = M.norm(nome):gsub("%s+", "")
  local letras = p:match("^([A-Z]+)") or ""
  -- 1º: palavra exata (ex.: "RE", "P", "I")
  for _, g in ipairs(M.CORES_SECAO) do
    for _, n in ipairs(g.nomes) do if letras == n then return g.cor, g.desc end end
  end
  -- 2º: começa com um nome longo (ex.: "REFRAOFINAL"); vale o MAIS LONGO
  local melhor, tam = nil, 0
  for _, g in ipairs(M.CORES_SECAO) do
    for _, n in ipairs(g.nomes) do
      if #n >= 3 and #n > tam and letras:sub(1, #n) == n then melhor, tam = g, #n end
    end
  end
  if melhor then return melhor.cor, melhor.desc end
  return M.COR_SECAO_PADRAO, "Seção"
end

function M.cor_secao(nome) return M.cor_nativa((M.cor_secao_rgb(nome))) end

function M.colorir_secoes()
  r.Undo_BeginBlock()
  local _, marcas = M.listar_marcadores()
  for _, mk in ipairs(marcas) do
    r.SetProjectMarker3(0, mk.idx, false, mk.inicio, 0, mk.nome, M.cor_secao(mk.nome))
  end
  r.Undo_EndBlock("Colorir seções", -1)
  r.UpdateTimeline()
end

function M.marcar_secao()
  local pos = M.pos_atual()  -- pega a posição ANTES de abrir a janela
  local m = M.musica_atual(pos)
  local sugestao = ""
  if m then sugestao = "S" .. #M.secoes_da_musica(m) end
  local ok, nome = r.GetUserInputs("Nova seção em " .. r.format_timestr_pos(pos, "", 0), 1,
    "Nome (I1 V1 P1 R1 Re2 PONTE FINAL),extrawidth=60", sugestao)
  if not ok or trim(nome) == "" then return end
  nome = trim(nome):upper()
  r.Undo_BeginBlock()
  r.AddProjectMarker2(0, false, pos, 0, nome, -1, M.cor_secao(nome))
  r.Undo_EndBlock("Marcar seção " .. nome, -1)
end

-------------------------------------------------------------------------------
-- ARQUIVO DE MARCADORES (marcadores.txt)
-------------------------------------------------------------------------------
--[[ Formato aceito (uma seção por linha, tempo relativo ao início da música):
       0:00.000  I1
       0:12.5    V1
       45.2;R1
     Também aceita export de marcadores do Audacity (início<TAB>fim<TAB>nome)
     e linhas "mm:ss nome". Linhas com # são comentários. ]]
local function ler_tempo(s)
  s = trim(s)
  local h, mi, se = s:match("^(%d+):(%d+):(%d+%.?%d*)$")
  if h then return tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(se) end
  mi, se = s:match("^(%d+):(%d+%.?%d*)$")
  if mi then return tonumber(mi) * 60 + tonumber(se) end
  if s:match("^%d+%.?%d*$") then return tonumber(s) end
  s = s:gsub(",", ".")
  if s:match("^%d+%.?%d*$") then return tonumber(s) end
  return nil
end

function M.ler_arquivo_marcadores(caminho)
  local f = io.open(caminho, "r")
  if not f then return nil end
  local lista = {}
  for linha in f:lines() do
    linha = trim(linha:gsub("^\239\187\191", ""))  -- remove BOM
    if linha ~= "" and not linha:match("^#") then
      local campos = {}
      for c in (linha .. "\t"):gmatch("([^\t;]*)[\t;]") do campos[#campos + 1] = trim(c) end
      local t, nome
      if #campos >= 3 and ler_tempo(campos[1]) and ler_tempo(campos[2]) then
        t, nome = ler_tempo(campos[1]), campos[3]
      elseif #campos >= 2 and ler_tempo(campos[1]) then
        t, nome = ler_tempo(campos[1]), campos[2]
      else
        local a, b = linha:match("^(%S+)%s+(.+)$")
        if a and ler_tempo(a) then t, nome = ler_tempo(a), b end
      end
      if t and nome and trim(nome) ~= "" then lista[#lista + 1] = { t = t, nome = trim(nome):upper() } end
    end
  end
  f:close()
  if #lista == 0 then return nil end
  table.sort(lista, function(a, b) return a.t < b.t end)
  return lista
end

local function fmt_tempo(t)
  return string.format("%d:%06.3f", math.floor(t / 60), t - math.floor(t / 60) * 60)
end
M.fmt_tempo = fmt_tempo

-- Grava as seções da música em marcadores.txt (na pasta da música). Retorna o caminho ou nil, erro
function M.gravar_marcadores(m, silencioso)
  local secs = M.secoes_da_musica(m)
  local _, pasta = r.GetProjExtState(0, "MT_PASTA", M.norm(m.nome))
  local destino
  if pasta ~= "" then destino = pasta .. SEP .. "marcadores.txt"
  else
    if silencioso then return nil end
    local proj = r.GetProjectPath("")
    destino = proj .. SEP .. m.nome:gsub("[\\/:%*%?\"<>|]", "_") .. " - marcadores.txt"
  end
  local f = io.open(destino, "w")
  if not f then return nil, destino end
  f:write("# Marcadores de: " .. m.nome .. (m.tom and (" [" .. m.tom .. "]") or "") .. "\n")
  f:write("# tempo (relativo ao início da música)   nome da seção\n")
  for _, s in ipairs(secs) do
    if not s.virtual then f:write(fmt_tempo(s.inicio - m.inicio) .. "\t" .. s.nome .. "\n") end
  end
  f:close()
  return destino
end

function M.salvar_marcadores()
  local m = M.musica_atual()
  if not m then return M.aviso("Nenhuma música no projeto") end
  local destino, erro = M.gravar_marcadores(m)
  if not destino then return r.MB("Não consegui gravar em:\n" .. tostring(erro), "Salvar marcadores", 0) end
  r.MB("Marcadores salvos em:\n" .. destino .. "\n\nNa próxima importação desta pasta eles serão carregados automaticamente.",
    "Salvar marcadores", 0)
end

-------------------------------------------------------------------------------
-- IMPORTAÇÃO DE MULTITRACK
-------------------------------------------------------------------------------
function M.classificar_stem(nome_arquivo)
  local base = nome_arquivo:gsub("%.[^%.]+$", "")
  local ws = palavras(base)
  local frase = " " .. table.concat(ws, " ") .. " "
  local set = {}
  for _, w in ipairs(ws) do set[w] = true end
  -- "SINT." "GTR1" "EG1" etc.: também testa a palavra sem números no fim
  for _, w in ipairs(ws) do local s = w:gsub("%d+$", ""); if s ~= "" then set[s] = true end end
  for _, regra in ipairs(M.REGRAS) do
    for _, f in ipairs(regra.frases or {}) do
      if frase:find(" " .. f .. " ", 1, true) then return regra.destino end
    end
    for _, e in ipairs(regra.exatas or {}) do
      if set[e] or (e:find(" ") and frase:find(" " .. e .. " ", 1, true)) then return regra.destino end
    end
    for _, p in ipairs(regra.prefixos or {}) do
      for _, w in ipairs(ws) do if w:sub(1, #p) == p then return regra.destino end end
    end
  end
  return M.DESTINO_PADRAO
end

-- Palavra curta (AG, OH, EP, BV, FX…) só conta como stem se o arquivo for
-- basicamente esse rótulo (AG.wav, BV 2.wav). Em "Jessé Aguiar" ou "Oh Senhor"
-- ela é só parte do título da música.
local function palavra_stem_curta_ok(ws, palavra)
  local extras = 0
  for _, w in ipairs(ws) do
    if w ~= palavra and not w:match("^%d+$") and #w > 1 then extras = extras + 1 end
  end
  return extras == 0
end

-- O nome do arquivo parece um STEM (kick, baixo, voz, click…) e não o título
-- de uma música completa?
function M.nome_parece_stem(nome_arquivo)
  local base = (nome_arquivo:match("([^\\/]+)$") or nome_arquivo):gsub("%.[^%.]+$", "")
  base = base:gsub("^%s*%d+%s*[%-_%.%s]%s*", "")
  local ws = palavras(base)
  if #ws == 0 then return false end
  local frase = " " .. table.concat(ws, " ") .. " "
  local set = {}
  for _, w in ipairs(ws) do
    set[w] = true
    local s = w:gsub("%d+$", "")
    if s ~= "" then set[s] = true end
  end
  for _, regra in ipairs(M.REGRAS) do
    for _, f in ipairs(regra.frases or {}) do
      if frase:find(" " .. f .. " ", 1, true) then return true end
    end
    for _, e in ipairs(regra.exatas or {}) do
      local bate = set[e] or (e:find(" ") and frase:find(" " .. e .. " ", 1, true))
      if bate then
        if e:find(" ") or #e >= 4 or palavra_stem_curta_ok(ws, e) then return true end
      end
    end
    for _, p in ipairs(regra.prefixos or {}) do
      if #p >= 3 then
        for _, w in ipairs(ws) do
          if w:sub(1, #p) == p then return true end
        end
      end
    end
  end
  return false
end

-- Nome "bonito" do stem: tira número inicial e o nome da música
function M.nome_stem(nome_arquivo, nome_musica)
  local base = nome_arquivo:gsub("%.[^%.]+$", "")
  base = base:gsub("^%s*%d+%s*[%-_%.%s]%s*", "")
  local partes = {}
  for p in (base .. " - "):gmatch("(.-)%s+%-%s+") do partes[#partes + 1] = trim(p) end
  if #partes > 1 then
    local resto = {}
    for _, p in ipairs(partes) do
      if M.norm(p) ~= M.norm(nome_musica) then resto[#resto + 1] = p end
    end
    if #resto > 0 then base = table.concat(resto, " - ") end
  end
  base = trim(base:gsub("_", " "))
  if base == "" then base = nome_arquivo end
  return base:upper()
end

-- Tenta achar tom e BPM no nome da pasta:
--   VS:               "Ousado Amor - Bb - 72bpm"   "Grande É o Senhor (G)"
--   MultiTracks.com:  "MultiTrack-Here As In Heaven-Here As In Heaven-D"  (MultiTrack-Música-Álbum-Tom)
function M.detectar_tom_bpm(nome)
  local tom, bpm
  local resto = {}
  local multitracks = false
  local s = nome:gsub("[%(%)%[%]_]", " - ")
  for parte in (s .. " - "):gmatch("(.-)%s*%-%s*") do
    parte = trim(parte)
    if parte ~= "" then
      local b = parte:match("^(%d+%.?%d*)%s*[Bb][Pp][Mm]$")
      local np = M.norm(parte)
      if np == "MULTITRACK" or np == "MULTITRACKS" or np == "MULTITRACKS COM" then multitracks = true
      elseif b and not bpm then bpm = tonumber(b)
      elseif not tom and M.ler_tom(parte) and #parte <= 4 then tom = parte
      else
        local repetido = false
        for _, x in ipairs(resto) do if M.norm(x) == np then repetido = true end end
        if not repetido then resto[#resto + 1] = parte end
      end
    end
  end
  -- MultiTracks.com: "Música-Álbum" -> fica só o nome da música
  if multitracks and #resto > 1 then resto = { resto[1] } end
  local limpo = trim(table.concat(resto, " - "))
  if limpo == "" then limpo = nome end
  return limpo, tom, bpm
end

-------------------------------------------------------------------------------
-- DESCOMPACTAR .als (Ableton = XML compactado com gzip) - Lua puro, sem DLL
-------------------------------------------------------------------------------
local LBASE = {3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258}
local LEXT  = {0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0}
local DBASE = {1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,
               8193,12289,16385,24577}
local DEXT  = {0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13}
local ORDEM_CL = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15}

-- Descompacta dados "deflate" (RFC 1951) a partir da posição 'inicio' da string
function M.inflate(dados, inicio)
  local pos, buf, nb = inicio or 1, 0, 0
  local out, n = {}, 0
  local function bits(q)
    while nb < q do
      local c = dados:byte(pos)
      if not c then error("arquivo compactado incompleto") end
      pos = pos + 1; buf = buf | (c << nb); nb = nb + 8
    end
    local v = buf & ((1 << q) - 1)
    buf = buf >> q; nb = nb - q
    return v
  end
  local function montar(lens, qtd)
    local cont, simb, offs = {}, {}, {}
    for i = 0, 15 do cont[i] = 0 end
    for i = 0, qtd - 1 do local l = lens[i] or 0; cont[l] = cont[l] + 1 end
    offs[1] = 0
    for i = 1, 14 do offs[i + 1] = offs[i] + cont[i] end
    for i = 0, qtd - 1 do
      local l = lens[i] or 0
      if l ~= 0 then simb[offs[l]] = i; offs[l] = offs[l] + 1 end
    end
    return { c = cont, s = simb }
  end
  local function decodificar(h)
    local code, first, index = 0, 0, 0
    for len = 1, 15 do
      code = code | bits(1)
      local c = h.c[len]
      if code - c < first then return h.s[index + (code - first)] end
      index = index + c; first = (first + c) << 1; code = code << 1
    end
    error("código inválido no arquivo compactado")
  end
  local function blocos(hl, hd)
    while true do
      local sym = decodificar(hl)
      if sym < 256 then n = n + 1; out[n] = sym
      elseif sym == 256 then return
      else
        sym = sym - 257
        local len = LBASE[sym + 1] + bits(LEXT[sym + 1])
        local ds = decodificar(hd)
        local dist = DBASE[ds + 1] + bits(DEXT[ds + 1])
        for _ = 1, len do n = n + 1; out[n] = out[n - dist] end
      end
    end
  end
  local fixo_l, fixo_d
  repeat
    local ultimo = bits(1)
    local tipo = bits(2)
    if tipo == 0 then
      buf, nb = 0, 0
      local len = dados:byte(pos) | (dados:byte(pos + 1) << 8)
      pos = pos + 4
      for k = 0, len - 1 do n = n + 1; out[n] = dados:byte(pos + k) end
      pos = pos + len
    elseif tipo == 1 then
      if not fixo_l then
        local l = {}
        for i = 0, 143 do l[i] = 8 end
        for i = 144, 255 do l[i] = 9 end
        for i = 256, 279 do l[i] = 7 end
        for i = 280, 287 do l[i] = 8 end
        fixo_l = montar(l, 288)
        local d = {}
        for i = 0, 29 do d[i] = 5 end
        fixo_d = montar(d, 30)
      end
      blocos(fixo_l, fixo_d)
    elseif tipo == 2 then
      local nlen, ndist, ncode = bits(5) + 257, bits(5) + 1, bits(4) + 4
      local cl = {}
      for i = 0, 18 do cl[i] = 0 end
      for i = 1, ncode do cl[ORDEM_CL[i]] = bits(3) end
      local hcl = montar(cl, 19)
      local lens, i = {}, 0
      while i < nlen + ndist do
        local sym = decodificar(hcl)
        if sym < 16 then lens[i] = sym; i = i + 1
        else
          local rep, val = 0, 0
          if sym == 16 then val = lens[i - 1] or 0; rep = 3 + bits(2)
          elseif sym == 17 then rep = 3 + bits(3)
          else rep = 11 + bits(7) end
          for _ = 1, rep do lens[i] = val; i = i + 1 end
        end
      end
      local ll, dl = {}, {}
      for k = 0, nlen - 1 do ll[k] = lens[k] end
      for k = 0, ndist - 1 do dl[k] = lens[nlen + k] end
      blocos(montar(ll, nlen), montar(dl, ndist))
    else
      error("bloco compactado inválido")
    end
  until ultimo == 1
  local partes = {}
  for k = 1, n, 4096 do
    partes[#partes + 1] = string.char(table.unpack(out, k, math.min(n, k + 4095)))
  end
  return table.concat(partes)
end

-- Descompacta um arquivo .gz (ou devolve o texto se não estiver compactado)
function M.gunzip(dados)
  if dados:byte(1) ~= 0x1f or dados:byte(2) ~= 0x8b then return dados end
  local flg = dados:byte(4)
  local pos = 11
  if flg & 4 ~= 0 then pos = pos + 2 + (dados:byte(pos) | (dados:byte(pos + 1) << 8)) end
  if flg & 8 ~= 0 then pos = dados:find("\0", pos, true) + 1 end
  if flg & 16 ~= 0 then pos = dados:find("\0", pos, true) + 1 end
  if flg & 2 ~= 0 then pos = pos + 2 end
  return M.inflate(dados, pos)
end

-------------------------------------------------------------------------------
-- LER PROJETO DO ABLETON (.als): andamento, compasso e Locators (= seções)
-------------------------------------------------------------------------------
function M.ler_als(caminho)
  local f = io.open(caminho, "rb")
  if not f then return nil, "não abriu " .. caminho end
  local bruto = f:read("a")
  f:close()
  local ok, xml = pcall(M.gunzip, bruto)
  if not ok or not xml or not xml:find("<Ableton", 1, true) then return nil, "arquivo .als inválido" end
  local info = { bpm = nil, num = 4, den = 4, locators = {} }
  -- andamento: bloco <Tempo> (Live 9+: <Manual Value=..>; Live 8: 1º FloatEvent)
  local bloco = xml:match("<Tempo>(.-)</Tempo>")
  if bloco then
    local v = bloco:match('<Manual Value="([%d%.]+)"') or bloco:match('<FloatEvent [^>]-Value="([%d%.]+)"')
    info.bpm = tonumber(v)
  end
  -- compasso: valor codificado = (numerador-1) + 99*log2(denominador)
  local bts = xml:match("<TimeSignature>(.-)</TimeSignature>")
  if bts then
    local v = tonumber(bts:match('<Manual Value="(%d+)"') or bts:match('<EnumEvent [^>]-Value="(%d+)"'))
    if v then info.num = (v % 99) + 1; info.den = math.floor(2 ^ (v // 99)) end
  end
  -- seções: <Locator> com Time em TEMPOS (beats) e Name
  local loc = xml:match("<Locators>(.-)</Locators>%s*</Locators>") or xml:match("<Locators>(.-)</Locators>") or ""
  for corpo in loc:gmatch("<Locator>(.-)</Locator>") do
    local t = tonumber(corpo:match('<Time Value="([%-%d%.eE]+)"'))
    local nome = corpo:match('<Name Value="(.-)"')
    if t and nome then
      nome = nome:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'")
      info.locators[#info.locators + 1] = { beats = t, nome = trim(nome) }
    end
  end
  table.sort(info.locators, function(a, b) return a.beats < b.beats end)
  return info
end

-- Converte os Locators do .als em lista de seções {t=segundos, nome=}
-- (tempo fixo; nomes repetidos ganham número: CHORUS 1, CHORUS 2...)
function M.secoes_do_als(info)
  if not info or not info.bpm or info.bpm <= 0 or #info.locators == 0 then return nil end
  local total = {}
  for _, l in ipairs(info.locators) do
    local k = M.norm(l.nome); total[k] = (total[k] or 0) + 1
  end
  local visto, lista = {}, {}
  for _, l in ipairs(info.locators) do
    local k = M.norm(l.nome)
    local nome = l.nome:upper()
    if total[k] > 1 then
      visto[k] = (visto[k] or 0) + 1
      nome = nome .. " " .. visto[k]
    end
    if l.beats >= 0 then lista[#lista + 1] = { t = l.beats * 60 / info.bpm, nome = nome } end
  end
  return lista
end

-------------------------------------------------------------------------------
-- DESCOBRIR PASTAS: aceita a pasta da música, a subpasta "MultiTracks", o .als
-- ou QUALQUER arquivo dentro delas -> importa TODOS os stems da multitrack
-------------------------------------------------------------------------------
local NOMES_SUBPASTA_STEMS = { MULTITRACKS = true, MULTITRACK = true, STEMS = true, TRACKS = true, AUDIO = true,
  ["AUDIO FILES"] = true, ["MULTI TRACKS"] = true, ["MULTI TRACK"] = true }
-- pastas que nunca têm stems (cache de picos, backups, arquivos do Ableton, lixo do Mac)
local PASTAS_IGNORADAS = { PEAKS = true, BACKUPS = true, BACKUP = true, ["ABLETON PROJECT INFO"] = true,
  PROCESSED = true, FREEZE = true, ["MACOSX"] = true }

local function ignorar_arquivo(f)
  return f:sub(1, 1) == "." or f:sub(1, 2) == "._"
end

local function listar_arquivos(pasta)
  r.EnumerateFiles(pasta, -1)
  local audios, txts, als = {}, {}, {}
  local i = 0
  while true do
    local f = r.EnumerateFiles(pasta, i)
    if not f then break end
    if not ignorar_arquivo(f) and f:lower() ~= "mt_info.txt" then
      local ext = (f:match("%.([^%.]+)$") or ""):lower()
      if EXT_AUDIO[ext] then audios[#audios + 1] = f
      elseif ext == "txt" or ext == "csv" then txts[#txts + 1] = f
      elseif ext == "als" then als[#als + 1] = f end
    end
    i = i + 1
  end
  table.sort(audios, function(a, b) return a:lower() < b:lower() end)
  table.sort(txts)
  return audios, txts, als
end

local function listar_subpastas(pasta)
  r.EnumerateSubdirectories(pasta, -1)
  local subs, j = {}, 0
  while true do
    local d = r.EnumerateSubdirectories(pasta, j)
    if not d then break end
    local n = M.norm(d)
    if d:sub(1, 1) ~= "." and d:sub(1, 2) ~= "__" and not PASTAS_IGNORADAS[n] then subs[#subs + 1] = d end
    j = j + 1
  end
  table.sort(subs, function(a, b) return a:lower() < b:lower() end)
  return subs
end

-- Todos os áudios da pasta e das subpastas (caminhos relativos, ex.: "Bateria\Kick.wav").
-- Se o mesmo nome de arquivo aparecer duas vezes, fica só o primeiro (o mais perto da raiz).
local function coletar_audios(pasta, prof)
  prof = prof or 4
  local lista, vistos = {}, {}
  local function varre(dir, rel, nivel)
    local a = listar_arquivos(dir)
    for _, f in ipairs(a) do
      local k = f:lower()
      if not vistos[k] then vistos[k] = true; lista[#lista + 1] = rel .. f end
    end
    if nivel < prof then
      for _, d in ipairs(listar_subpastas(dir)) do varre(dir .. SEP .. d, rel .. d .. SEP, nivel + 1) end
    end
  end
  varre(pasta, "", 0)
  return lista
end
M.coletar_audios = coletar_audios

local function pai_de(p) return p:match("^(.*)[\\/][^\\/]+$") end

local function tem_audio_em_algum_lugar(pasta)
  return #coletar_audios(pasta, 3) > 0
end

-- Subpasta "MultiTracks"/"Stems"... com áudio dentro
local function achar_sub_stems(pasta)
  for _, d in ipairs(listar_subpastas(pasta)) do
    if NOMES_SUBPASTA_STEMS[M.norm(d)] and #coletar_audios(pasta .. SEP .. d, 2) > 0 then return pasta .. SEP .. d end
  end
  return nil
end

function M.info_pasta(pasta, nivel)
  nivel = nivel or 0
  pasta = pasta:gsub("[\\/]+$", "")
  local inf = { audio = pasta, musica = pasta }
  -- escolheu a própria subpasta de stems? a música é a pasta de cima
  local nome_aqui = pasta:match("([^\\/]+)$") or ""
  if NOMES_SUBPASTA_STEMS[M.norm(nome_aqui)] and pai_de(pasta) then inf.musica = pai_de(pasta) end
  local audios_aqui, _, als_aqui = listar_arquivos(pasta)
  local sub_stems = (#audios_aqui == 0) and achar_sub_stems(pasta) or nil
  if #audios_aqui == 0 and not sub_stems and #als_aqui == 0 and nivel < 3 then
    -- pasta "de fora" (download com pasta dentro de pasta): se só tem UMA subpasta, desce nela
    local subs = listar_subpastas(pasta)
    local com_audio = {}
    for _, d in ipairs(subs) do if tem_audio_em_algum_lugar(pasta .. SEP .. d) then com_audio[#com_audio + 1] = d end end
    if #com_audio == 1 then return M.info_pasta(pasta .. SEP .. com_audio[1], nivel + 1) end
  end
  inf.audio = sub_stems or pasta
  -- TODOS os stems: os da pasta e os das subpastas (VS separada por grupos etc.)
  inf.audios = coletar_audios(inf.audio, 4)
  local _, txts = listar_arquivos(inf.audio)
  inf.txts = txts
  -- marcadores.txt pode estar na pasta da música também
  if inf.musica ~= inf.audio then
    local _, t2 = listar_arquivos(inf.musica)
    for _, t in ipairs(t2) do inf.txts[#inf.txts + 1] = ".." .. SEP .. t end
  end
  -- .als: na pasta da música, na de stems ou na de cima
  for _, p in ipairs({ inf.musica, inf.audio, pai_de(inf.musica) }) do
    if p and not inf.als_arquivo then
      local _, _, als = listar_arquivos(p)
      if als[1] then inf.als_arquivo = p .. SEP .. als[1] end
    end
  end
  if inf.als_arquivo then inf.als = M.ler_als(inf.als_arquivo) end
  local nome_pasta = inf.musica:match("([^\\/]+)$") or "Música"
  inf.nome, inf.tom, inf.bpm = M.detectar_tom_bpm(nome_pasta)
  if not inf.bpm and inf.als and inf.als.bpm then inf.bpm = inf.als.bpm end
  -- ficha da música (mt_info.txt, gravada pelo importador / biblioteca) tem prioridade
  local meta = M.ler_info(inf.musica) or (inf.audio ~= inf.musica and M.ler_info(inf.audio)) or nil
  if meta then
    inf.meta = meta
    if meta.NOME and meta.NOME ~= "" then inf.nome = meta.NOME end
    if meta.TOM and meta.TOM ~= "" then inf.tom = meta.TOM end
    if tonumber(meta.BPM) then inf.bpm = tonumber(meta.BPM) end
    if meta.ARTISTA and meta.ARTISTA ~= "" then inf.artista = meta.ARTISTA end
    local n, d = (meta.COMPASSO or ""):match("^(%d+)%s*/%s*(%d+)$")
    if n then inf.num, inf.den = tonumber(n), tonumber(d) end
    if tonumber(meta.OFFSET) then inf.offset = tonumber(meta.OFFSET) end
  end
  return inf
end

-------------------------------------------------------------------------------
-- FICHA DA MÚSICA (mt_info.txt) e BIBLIOTECA DE MULTITRACKS
-------------------------------------------------------------------------------
M.ARQ_INFO = "mt_info.txt"

function M.ler_info(pasta)
  if not pasta then return nil end
  local f = io.open(pasta .. SEP .. M.ARQ_INFO, "r")
  if not f then return nil end
  local t = {}
  for linha in f:lines() do
    linha = linha:gsub("^\239\187\191", "")
    local k, v = linha:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k then t[k:upper()] = v end
  end
  f:close()
  return t
end

function M.gravar_info(pasta, t)
  local f = io.open(pasta .. SEP .. M.ARQ_INFO, "w")
  if not f then return false end
  f:write("# Ficha da multitrack (Mik Seifador). Pode editar.\n")
  for _, k in ipairs({ "NOME", "ARTISTA", "TOM", "BPM", "COMPASSO", "OFFSET", "ANALISE", "AUDIO_INICIO", "GRADE",
    "CANAL_CLICK", "CLICK", "GUIA", "STEMS", "TIPO", "IMPORTAR_COMO", "ANDAMENTO", "CLICK_APROX", "BATIDAS" }) do
    if t[k] ~= nil and tostring(t[k]) ~= "" then f:write(k, "=", tostring(t[k]), "\n") end
  end
  f:close()
  return true
end

local function home()
  return os.getenv("USERPROFILE") or os.getenv("HOME") or ""
end

function M.pasta_biblioteca()
  local p = M.get("BIBLIOTECA", "")
  if p == "" then p = home() .. SEP .. "Documents" .. SEP .. "Multitracks" end
  return (p:gsub("[\\/]+$", ""))
end

local function existe_pasta(p)
  if not p or p == "" then return false end
  r.EnumerateFiles(p, -1); r.EnumerateSubdirectories(p, -1)
  if r.EnumerateFiles(p, 0) or r.EnumerateSubdirectories(p, 0) then return true end
  local ok, _, code = os.rename(p, p)
  return ok or code == 13
end
M.existe_pasta = existe_pasta

function M.garantir_biblioteca()
  local p = M.pasta_biblioteca()
  if not existe_pasta(p) then r.RecursiveCreateDirectory(p, 0) end
  M.garantir_pasta_pads()
  return p
end

function M.definir_pasta_biblioteca()
  local atual = M.pasta_biblioteca()
  local nova
  if r.JS_Dialog_BrowseForFolder then
    local ret, p = r.JS_Dialog_BrowseForFolder("Pasta da BIBLIOTECA de multitracks", atual)
    if ret == 1 and p and p ~= "" then nova = p end
  else
    local ok, p = r.GetUserInputs("Pasta da biblioteca", 1, "Pasta da biblioteca:,extrawidth=400", atual)
    if ok and trim(p) ~= "" then nova = trim(p) end
  end
  if nova then
    M.set("BIBLIOTECA", (nova:gsub("[\\/]+$", "")))
    M.garantir_biblioteca()
  end
  return nova
end

local function chave_caminho(p)
  p = (p or ""):gsub("[\\/]+", "/"):gsub("/$", "")
  return p:lower()
end

function M.na_biblioteca(p)
  local b = chave_caminho(M.pasta_biblioteca()) .. "/"
  return chave_caminho(p):sub(1, #b) == b
end

-- nome de pasta: "Artista - Música [Tom]" sem caracteres proibidos no Windows
function M.nome_pasta_musica(nome, artista, tom)
  local s = trim(nome or "Música")
  if artista and trim(artista) ~= "" then s = trim(artista) .. " - " .. s end
  if tom and trim(tom) ~= "" then s = s .. " [" .. trim(tom) .. "]" end
  s = s:gsub('[\\/:%*%?"<>|]', "-"):gsub("%s+", " ")
  return trim(s):gsub("%.+$", "")
end

local function sh_aspas(p) return '"' .. p .. '"' end

-- Copia uma pasta inteira (com subpastas). Retorna ok, mensagem
function M.copiar_pasta(origem, destino)
  r.RecursiveCreateDirectory(destino, 0)
  local cmd, ret
  if SEP == "\\" then
    cmd = "robocopy " .. sh_aspas(origem) .. " " .. sh_aspas(destino) .. " /E /R:1 /W:1 /NP /NFL /NDL /NJH /NJS"
    ret = r.ExecProcess(cmd, 0)
    local code = tonumber((ret or ""):match("^(%-?%d+)")) or 99
    if code >= 8 then return false, "robocopy falhou (código " .. code .. ")" end
  else
    cmd = "/bin/cp -R " .. sh_aspas(origem .. "/.") .. " " .. sh_aspas(destino)
    ret = r.ExecProcess(cmd, 0)
    local code = tonumber((ret or ""):match("^(%-?%d+)")) or 99
    if code ~= 0 then return false, "cópia falhou: " .. tostring(ret) end
  end
  local a = coletar_audios(origem, 4)
  local b = coletar_audios(destino, 4)
  if #b < #a then return false, string.format("cópia incompleta (%d de %d áudios)", #b, #a) end
  return true
end

-- Leva a pasta da música para a biblioteca. modo = "mover" | "copiar"
-- Retorna: nova_pasta (ou nil), mensagem
function M.levar_para_biblioteca(origem, nome_destino, modo)
  local bib = M.garantir_biblioteca()
  local destino = bib .. SEP .. nome_destino
  local k = 2
  while existe_pasta(destino) do destino = bib .. SEP .. nome_destino .. " (" .. k .. ")"; k = k + 1 end
  if modo == "mover" then
    local ok = os.rename(origem, destino)
    if ok then return destino, "movida" end
    -- outro disco / arquivo em uso: copia e mantém o original
    local ok2, err = M.copiar_pasta(origem, destino)
    if ok2 then return destino, "copiada (não deu para mover; o original ficou onde estava)" end
    return nil, err
  end
  local ok2, err = M.copiar_pasta(origem, destino)
  if ok2 then return destino, "copiada" end
  return nil, err
end

-- Lista as músicas da biblioteca: { pasta, nome, artista, tom, bpm, rotulo }
function M.listar_biblioteca()
  local bib = M.pasta_biblioteca()
  local lista = {}
  for _, d in ipairs(listar_subpastas(bib)) do
    if d:sub(1, 1) ~= "_" then
      local p = bib .. SEP .. d
      local meta = M.ler_info(p) or {}
      local nome, tom, bpm = M.detectar_tom_bpm(d)
      local artista
      if not meta.NOME then
        -- "Artista - Música [Tom]"
        local a, n = d:gsub("%s*%[[^%]]*%]%s*$", ""):match("^(.-)%s+%-%s+(.+)$")
        if a then artista, nome = a, n end
        local t = d:match("%[([^%]]+)%]%s*$")
        if t and M.ler_tom(t) then tom = t end
      end
      local item = { pasta = p, nome = meta.NOME or nome or d, artista = meta.ARTISTA or artista,
        tom = (meta.TOM ~= "" and meta.TOM) or tom, bpm = tonumber(meta.BPM) or bpm, compasso = meta.COMPASSO }
      item.rotulo = item.nome .. (item.artista and (" - " .. item.artista) or "")
      lista[#lista + 1] = item
    end
  end
  table.sort(lista, function(a, b) return a.rotulo:lower() < b.rotulo:lower() end)
  return lista
end

-- Um clique na biblioteca: põe a música no fim do setlist
function M.adicionar_da_biblioteca(item)
  -- Pasta de músicas completas (mesmo com mt_info.txt antigo): cada arquivo
  -- entra como uma música. Não trata a pasta da Biblioteca como uma multitrack.
  if not M.pasta_parece_multitrack(item.pasta) then
    local audios_aqui = listar_arquivos(item.pasta)
    if #audios_aqui > 1 then
      local lista = {}
      for _, f in ipairs(audios_aqui) do lista[#lista + 1] = item.pasta .. SEP .. f end
      return M.importar_varias(lista)
    end
  end
  local inf = M.info_pasta(item.pasta)
  if #inf.audios == 0 then return r.MB("Nenhum áudio em:\n" .. item.pasta, "Biblioteca", 0) end
  local ok, msg, inicio_mus = M.importar_pasta(item.pasta, { info = inf })
  if not ok then r.MB(msg, "Biblioteca", 0); return ok end
  -- v1.8: ao adicionar da Biblioteca, mesma função do menu (click+guia+seções+cifra)
  if inicio_mus and M.analise_auto() then
    local nome = (inf.nome and inf.nome ~= "") and inf.nome or "Música"
    local resumo = "Adicionada da Biblioteca: " .. nome
    local feito, res2 = M.automatico_apos_importar(inicio_mus, inf, nome, resumo, "Biblioteca")
    if not feito then M.aviso((res2 or resumo):gsub("\n+", " | ")) end
    return ok
  end
  r.ShowConsoleMsg("")
  r.ShowConsoleMsg(msg .. "\n")
  return ok
end

local function pasta_existe(p)
  local ok = r.EnumerateFiles(p, 0) or r.EnumerateSubdirectories(p, 0)
  return ok ~= nil
end

-- Escolhe a PASTA da multitrack.
--  * com a extensão js_ReaScriptAPI: janela de escolher PASTA de verdade
--  * sem ela: escolha QUALQUER arquivo dentro da pasta (stem, .als, capa...) e a
--    pasta inteira é importada
-- Retorna: pasta, erro
function M.escolher_pasta()
  local ultima = M.get("ULTIMA_PASTA", "")
  local bib = M.garantir_biblioteca()
  if existe_pasta(bib) then ultima = bib end
  if r.JS_Dialog_BrowseForFolder then
    local ret, pasta = r.JS_Dialog_BrowseForFolder("Escolha a PASTA da multitrack (todos os stems dela serão importados)", ultima)
    if ret == 1 and pasta and pasta ~= "" then return pasta end
    return nil
  end
  local ok, arq = r.GetUserFileNameForRead(ultima,
    "Escolha QUALQUER arquivo dentro da pasta da multitrack - TODOS os stems da pasta serão importados", M.EH_MAC and "" or "*.*")
  if not ok or not arq or arq == "" then return nil end
  local ext = (arq:match("%.([^%.\\/]+)$") or ""):lower()
  if ext == "zip" or ext == "rar" or ext == "7z" then
    return nil, "Esse arquivo é compactado (." .. ext .. ").\n\nExtraia primeiro (botão direito > Extrair tudo) e depois "
      .. "escolha qualquer arquivo dentro da pasta extraída."
  end
  -- escolheu uma pasta? (alguns sistemas deixam) senão, a pasta do arquivo
  if pasta_existe(arq) and not arq:match("%.[^%.\\/]+$") then return arq end
  return arq:match("^(.*)[\\/][^\\/]*$"), nil, arq
end

-- Interpreta o retorno de JS_Dialog_BrowseForOpenFiles:
--   1 arquivo  = caminho completo
--   vários     = pasta + nomes, separados por \0 (Windows) ou quebra de linha
function M.parse_lista_arquivos_dialogo(s)
  if not s or s == "" then return {} end
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  local toks = {}
  if s:find("\0", 1, true) then
    for tok in s:gmatch("[^\0]+") do
      tok = trim(tok)
      if tok ~= "" then toks[#toks + 1] = tok end
    end
  else
    for tok in s:gmatch("[^\n]+") do
      tok = trim(tok)
      if tok ~= "" then toks[#toks + 1] = tok end
    end
  end
  if #toks == 0 then return {} end
  if #toks == 1 then return { toks[1] } end
  local prim, segundo = toks[1], toks[2]
  local segundo_tem_caminho = segundo:find("[\\/]")
  if existe_pasta(prim) and not segundo_tem_caminho then
    local sep = prim:find("\\") and "\\" or (prim:find("/") and "/" or SEP)
    if prim:sub(-1):match("[\\/]") then sep = "" end
    local lista = {}
    for i = 2, #toks do lista[#lista + 1] = prim .. sep .. toks[i] end
    return lista
  end
  return toks
end

local FILTRO_AUDIO_JS = "Audio (wav, mp3, flac, m4a...)\0*.wav;*.WAV;*.mp3;*.MP3;*.flac;*.FLAC;*.aif;*.AIF;*.aiff;*.AIFF;*.ogg;*.OGG;*.m4a;*.M4A;*.wv\0Todos os arquivos\0*.*\0\0"
-- v1.8: no macOS o filtro no formato do Windows (e o "*.*") deixa as músicas CINZA/bloqueadas
-- no seletor. Lá passamos filtro vazio (= todos os arquivos) e conferimos a extensão depois.
local function filtro_js() return M.EH_MAC and "" or FILTRO_AUDIO_JS end
local function filtro_nativo() return M.EH_MAC and "" or "*.*" end
M.filtro_js, M.filtro_nativo = filtro_js, filtro_nativo

-- Janela do + IMPORTAR: um ou vários arquivos (Ctrl/Shift). Sem js_ReaScriptAPI,
-- cai no seletor nativo de UM arquivo (GetUserFileNameForRead). Cancelou = nil.
-- Retorna lista de caminhos e, se houver, um aviso (ex.: um .zip no meio).
function M.escolher_para_importar()
  local ultima = M.get("ULTIMA_PASTA", "")
  local bib = M.garantir_biblioteca()
  if existe_pasta(bib) then ultima = bib end
  local titulo = "Importar música: escolha um ou vários arquivos (Ctrl ou Shift para vários)"
  if r.JS_Dialog_BrowseForOpenFiles then
    local ret, nomes = r.JS_Dialog_BrowseForOpenFiles(titulo, ultima, "", filtro_js(), true)
    if not ret or ret == 0 or not nomes or nomes == "" then return nil end
    local lista = M.parse_lista_arquivos_dialogo(nomes)
    if #lista == 0 then return nil end
    local pai = pai_de(lista[1])
    if pai then M.set("ULTIMA_PASTA", pai) end
    return lista
  end
  local ok, arq = r.GetUserFileNameForRead(ultima,
    "Escolha o arquivo da música (ou qualquer arquivo dentro da pasta da multitrack)", filtro_nativo())
  if not ok or not arq or arq == "" then return nil end
  local ext = (arq:match("%.([^%.\\/]+)$") or ""):lower()
  if ext == "zip" or ext == "rar" or ext == "7z" then
    return nil, "Esse arquivo é compactado (." .. ext .. ").\n\nExtraia primeiro (botão direito > Extrair tudo) e depois "
      .. "escolha qualquer arquivo dentro da pasta extraída."
  end
  if pasta_existe(arq) and not arq:match("%.[^%.\\/]+$") then return { arq } end
  local pai = pai_de(arq)
  if pai then M.set("ULTIMA_PASTA", pai) end
  return { arq }
end

-- Fim do conteúdo do projeto (itens + regiões)
local function fim_do_projeto()
  local fim = 0
  for i = 0, r.CountMediaItems(0) - 1 do
    local it = r.GetMediaItem(0, i)
    local e = r.GetMediaItemInfo_Value(it, "D_POSITION") + r.GetMediaItemInfo_Value(it, "D_LENGTH")
    if e > fim then fim = e end
  end
  for _, m in ipairs(M.get_musicas()) do if m.fim > fim then fim = m.fim end end
  return fim
end

-- Início do próximo compasso depois de t (mantém a grade alinhada)
local function proximo_compasso(t)
  local _, compasso = r.TimeMap2_timeToBeats(0, t)
  local ini = r.TimeMap2_beatsToTime(0, 0, compasso)
  if ini < t - 0.0001 then ini = r.TimeMap2_beatsToTime(0, 0, compasso + 1) end
  return ini
end

local function arquivo_marcadores_na_pasta(pasta, arquivos_txt)
  -- preferência: marcadores.txt / markers.txt ; depois qualquer .txt/.csv válido
  for _, f in ipairs(arquivos_txt) do
    local n = M.norm(f)
    if n == "MARCADORES TXT" or n == "MARKERS TXT" or n == "MARCADORES CSV" or n == "MARKERS CSV" then
      local l = M.ler_arquivo_marcadores(pasta .. SEP .. f)
      if l then return l, f end
    end
  end
  for _, f in ipairs(arquivos_txt) do
    local l = M.ler_arquivo_marcadores(pasta .. SEP .. f)
    if l then return l, f end
  end
  return nil
end

-- Importa os "cues" gravados dentro dos WAV (se houver) como marcadores
local function importar_cues(itens, ini, fim)
  if #itens == 0 then return end
  r.SelectAllMediaItems(0, false)
  for _, it in ipairs(itens) do r.SetMediaItemSelected(it, true) end
  r.Main_OnCommand(40692, 0) -- Item: Import item media cues as project markers
  r.SelectAllMediaItems(0, false)
  -- regiões criadas pelos cues viram marcadores (regiões são reservadas p/ músicas)
  local mus, marcas = M.listar_marcadores()
  for k = #mus, 1, -1 do
    local g = mus[k]
    if g.inicio >= ini - 0.001 and g.fim <= fim + 0.01 then
      r.DeleteProjectMarker(0, g.idx, true)
      r.AddProjectMarker2(0, false, g.inicio, 0, g.nome_completo, -1, 0)
    end
  end
  -- remove marcadores duplicados (click e guia com os mesmos cues)
  mus, marcas = M.listar_marcadores()
  local ultimo = nil
  local apagar = {}
  for _, mk in ipairs(marcas) do
    if mk.inicio >= ini - 0.001 and mk.inicio < fim then
      if ultimo and math.abs(mk.inicio - ultimo) < 0.05 then apagar[#apagar + 1] = mk.enum else ultimo = mk.inicio end
    end
  end
  table.sort(apagar, function(a, b) return a > b end)
  for _, e in ipairs(apagar) do r.DeleteProjectMarkerByIndex(0, e) end
end

-- Importa uma pasta. Retorna true/false e mensagem.
-- opcoes = { nome=, tom=, bpm=, silencioso=bool }

-------------------------------------------------------------------------------
-- Capa da música (YouTube, em segundo plano, sem travar o painel)
-------------------------------------------------------------------------------
-- Ao importar ou abrir uma música sem capa.jpg (nem artwork/cover), dispara
-- buscar_capa.py: yt-dlp ytsearch1: "artista - música", miniatura
-- maxresdefault (fallback hqdefault), recorte quadrado central, grava
-- capa.jpg na pasta da música. Sem internet ou sem resultado: placeholder
-- no painel, sem popup e sem arquivo quebrado.

local function _capa_nome_arquivo(pasta)
  return (pasta or "") .. SEP .. "capa.jpg"
end

function M.arquivo_capa(pasta)
  if not pasta or pasta == "" then return nil end
  local a = _capa_nome_arquivo(pasta)
  if r.file_exists(a) then return a end
  return nil
end

function M.consulta_capa(nome, artista)
  local s = tostring(nome or "")
  s = s:gsub("^%d+%.%s*", "")
  s = s:gsub("%s*%-%s*LETRA%s*$", "")
  s = s:gsub("%s*%-%s*PLAYBACK%s*$", "")
  s = s:gsub("%s*%-%s*INSTRUMENTAL%s*$", "")
  s = s:gsub("%s*%-%s*CONTRATO%s*$", "")
  s = s:gsub("%s*%[[^%]]*%]%s*$", "")
  s = s:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  local art = tostring(artista or "")
  art = art:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if art ~= "" then
    local baixa = s:lower()
    if not baixa:find(art:lower(), 1, true) then
      s = art .. " - " .. s
    end
  end
  return s
end

local function _capa_tem_imagem(pasta)
  if not pasta or pasta == "" then return false end
  if r.file_exists(_capa_nome_arquivo(pasta)) then return true end
  local i = 0
  while true do
    local f = r.EnumerateFiles(pasta, i)
    if not f then break end
    local ext = (f:match("%.([%w]+)$") or ""):lower()
    if ext == "jpg" or ext == "jpeg" or ext == "png" or ext == "webp" then
      local n = f:lower()
      if n:find("cover", 1, true) or n:find("capa", 1, true) or n:find("artwork", 1, true)
         or n:find("folder", 1, true) or n:find("album", 1, true) then
        return true
      end
    end
    i = i + 1
  end
  return false
end
M.tem_capa = _capa_tem_imagem

local function _capa_trabalho()
  local base
  if M.EH_WIN then
    base = (os.getenv("LOCALAPPDATA") or ((os.getenv("USERPROFILE") or "C:") .. "\\AppData\\Local")) .. "\\MikSeifador\\capas"
  else
    base = (os.getenv("HOME") or "") .. "/Library/Application Support/MikSeifador/capas"
  end
  r.RecursiveCreateDirectory(base, 0)
  return base
end

local function _capa_chave(pasta)
  local s = chave_caminho(pasta or "")
  s = s:gsub("[^%w]+", "_")
  if #s > 80 then s = s:sub(-80) end
  return s
end

local function _capa_script()
  local a = (M.DIR or "") .. "separador" .. SEP .. "buscar_capa.py"
  if r.file_exists(a) then return a end
  local b = (M.DIR or "") .. "buscar_capa.py"
  if r.file_exists(b) then return b end
  return a
end

local function _capa_python()
  local py = M.motor_python and M.motor_python() or ""
  if py ~= "" and r.file_exists(py) then return py end
  if py ~= "" then
    local alt = py:gsub("pythonw%.exe", "python.exe")
    if alt ~= py and r.file_exists(alt) then return alt end
  end
  return nil
end

local function _capa_ler_status(arq)
  local f = io.open(arq, "r")
  if not f then return nil, nil, nil end
  local est = (f:read("*l") or ""):gsub("%s+$", "")
  local det = (f:read("*l") or ""):gsub("%s+$", "")
  f:close()
  local mtime = 0
  -- idade aproximada: se o arquivo existe, o tick decide pelo texto e por um
  -- carimbo ISO no detalhe; usamos também o horário do sistema via time_precise
  -- gravado em linha 3 quando possível
  local f2 = io.open(arq, "rb")
  if f2 then
    local n = f2:seek("end") or 0
    f2:close()
    mtime = n
  end
  return est, det, mtime
end

local capa_fila = { ocupado_ate = 0, visto = {} }
local capa_bib_feita = false

local function _capa_ainda_rodando(st_arq)
  local est, det = _capa_ler_status(st_arq)
  if est == "run" then
    -- se o status ficou preso, o próximo pedido (depois de 90 s) recomeça
    return true
  end
  return false
end

function M.pedir_capa_pasta(pasta, nome, artista)
  if not pasta or pasta == "" then return false end
  pasta = pasta:gsub("[\\/]+$", "")
  if M.norm and M.PASTA_STEMS and M.norm(pasta:match("([^\\/]+)$") or "") == M.norm(M.PASTA_STEMS) then
    pasta = pasta:match("^(.*)[\\/][^\\/]+$") or pasta
  end
  if _capa_tem_imagem(pasta) then return false end
  local busca = M.consulta_capa(nome or (pasta:match("([^\\/]+)$") or ""), artista)
  if not busca or busca == "" then return false end
  local agora = r.time_precise()
  local chave = _capa_chave(pasta)
  local visto = capa_fila.visto[chave]
  if visto and (agora - visto.t) < 2 then return false end
  local trab = _capa_trabalho()
  local st = trab .. SEP .. chave .. ".status"
  local est, det = _capa_ler_status(st)
  if est == "ok" and _capa_tem_imagem(pasta) then return false end
  if est == "falhou" then
    -- não martela o YouTube: espera uns 30 min (time_precise é desde o boot)
    if visto and (agora - visto.t) < 1800 then return false end
  end
  if est == "run" then
    if visto and (agora - visto.t) < 90 then return false end
  end
  if agora < (capa_fila.ocupado_ate or 0) then
    -- um por vez; o tick tenta de novo
    return false
  end
  local script = _capa_script()
  local py = _capa_python()
  if not py or not r.file_exists(script) then
    capa_fila.visto[chave] = { t = agora, est = "sem_motor" }
    return false
  end
  local ped = trab .. SEP .. chave .. ".pedido.txt"
  local logp = trab .. SEP .. "capa_busca.log"
  local fh = io.open(ped, "w")
  if not fh then return false end
  fh:write("pasta=" .. pasta .. "\n")
  fh:write("busca=" .. busca .. "\n")
  fh:write("status=" .. st .. "\n")
  fh:write("log=" .. logp .. "\n")
  fh:close()
  local stf = io.open(st, "w")
  if stf then stf:write("run\n" .. busca .. "\n"); stf:close() end
  local cmd
  if M.EH_WIN then
    cmd = '"' .. py .. '" -X utf8 "' .. script .. '" --pedido "' .. ped .. '"'
  else
    cmd = string.format("%q %q --pedido %q", py, script, ped)
  end
  pcall(r.ExecProcess, cmd, -1)
  capa_fila.ocupado_ate = agora + 70
  capa_fila.visto[chave] = { t = agora, est = "run" }
  return true
end

function M.pedir_capa_da_musica(m)
  if not m then return false end
  local pasta = M.pasta_da_musica and M.pasta_da_musica(m)
  if not pasta or pasta == "" then return false end
  return M.pedir_capa_pasta(pasta, m.nome, m.artista)
end

function M.buscar_capas_biblioteca()
  if not M.listar_biblioteca then return 0 end
  local n = 0
  for _, it in ipairs(M.listar_biblioteca()) do
    if it.pasta and M.pedir_capa_pasta(it.pasta, it.nome, it.artista) then
      n = n + 1
      break -- um por vez
    end
  end
  return n
end

function M.tick_capas(musicas)
  local agora = r.time_precise()
  if musicas then
    for _, m in ipairs(musicas) do
      M.pedir_capa_da_musica(m)
    end
  elseif M.get_musicas then
    for _, m in ipairs(M.get_musicas()) do
      M.pedir_capa_da_musica(m)
    end
  end
  if not capa_bib_feita then
    -- na 1ª passagem (e enquanto houver fila), tenta a biblioteca
    local n = M.buscar_capas_biblioteca()
    if n == 0 then
      -- ou todas já têm capa, ou estão em espera; marca feito só se nenhuma ficou pendente de 1ª vez
      capa_bib_feita = true
      -- mas ainda reabre a varredura de vez em quando para as que falharam / novas
    end
  elseif math.floor(agora / 20) ~= math.floor((agora - 0.5) / 20) then
    capa_bib_feita = false
  end
end

function M.importar_pasta(pasta, opcoes)
  opcoes = opcoes or {}
  local inf = opcoes.info or M.info_pasta(pasta)
  pasta = inf.audio                      -- onde estão os stems
  local audios, txts = inf.audios, inf.txts
  if #audios == 0 then return false, "Nenhum arquivo de áudio encontrado em:\n" .. inf.musica end

  local nome = opcoes.nome or inf.nome
  local tom = opcoes.tom or inf.tom
  local bpm = opcoes.bpm or inf.bpm
  local num, den = 4, 4
  if inf.als and inf.als.num then num, den = inf.als.num, inf.als.den end
  if inf.num then num, den = inf.num, inf.den end
  if opcoes.num then num, den = opcoes.num, opcoes.den or den end
  num, den = inteiro(num, 4), inteiro(den, 4)
  if den < 1 then den = 4 end
  if num < 1 then num = 4 end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  M.garantir_estrutura()

  -- posição: início do próximo compasso após o fim do projeto + intervalo
  local fim_atual = fim_do_projeto()
  local inicio = 0
  if fim_atual > 0 then inicio = proximo_compasso(fim_atual + M.CFG.INTERVALO_ENTRE_MUSICAS) end
  -- música já analisada antes (mt_info.txt): áudio deslocado e grade no lugar salvo
  local meta = inf.meta or {}
  local audio_ini = math.max(0, tonumber(meta.AUDIO_INICIO) or 0)
  local grade = math.max(0, tonumber(meta.GRADE) or 0)
  if bpm and bpm > 0 then
    r.SetTempoTimeSigMarker(0, -1, inicio + grade, -1, -1, bpm, num, den, false)
    r.UpdateTimeline()
  end

  local fim = inicio
  local itens_fone = {}
  local relatorio = {}
  local n_ok = 0
  local offset = tonumber(opcoes.offset or inf.offset) or 0   -- corta o começo (alinha o 1º tempo na grade)
  -- o click/guia "principal" (nome exato CLICK / CLICK TRACK / GUIA / GUIDE) vai primeiro
  local function prioridade(f)
    local b = M.norm((f:match("([^\\/]+)$") or f):gsub("%.[^%.]+$", ""))
    if b == "CLICK" or b == "CLICK TRACK" or b == "CLIQUE" or b == "GUIA" or b == "GUIDE" or b == "CUE"
      or b:find("^GUIDE ") or b:find("^GUIA ") then return 0 end
    return 1
  end
  local ordem = {}
  for i, f in ipairs(audios) do ordem[i] = f end
  table.sort(ordem, function(a, b)
    local pa, pb = prioridade(a), prioridade(b)
    if pa ~= pb then return pa < pb end
    return a:lower() < b:lower()
  end)
  local usadas = {}   -- trilhas que já receberam um stem NESTA música (nunca empilhar 2 stems na mesma)
  for _, f in ipairs(ordem) do
    local caminho = f                         -- relativo (pode ter subpasta)
    f = caminho:match("([^\\/]+)$") or caminho  -- só o nome do arquivo
    local destino = M.classificar_stem(f)
    local tr
    if destino == "CLICK" or destino == "GUIA" then
      local fone = M.achar_fone()
      tr = M.achar_filho(fone, destino == "CLICK" and M.CFG.NOME_CLICK or M.CFG.NOME_GUIA)
      if tr and usadas[tr] then
        -- 2º click/guia da mesma música (ex.: INT CLK, NAT CLK): trilha própria dentro do FONE
        local nome_tr = M.nome_stem(f, nome)
        tr = M.achar_filho(fone, nome_tr)
        if not tr or usadas[tr] then tr = M.inserir_filho_no_fim(fone, nome_tr .. ((tr and usadas[tr]) and " 2" or ""), nil) end
      end
    else
      local pasta_tr, sp = M.subpasta(destino)
      local nome_tr = M.nome_stem(f, nome)
      tr = M.achar_filho(pasta_tr, nome_tr)
      if tr and usadas[tr] then
        local k = 2
        while M.achar_filho(pasta_tr, nome_tr .. " " .. k) and usadas[M.achar_filho(pasta_tr, nome_tr .. " " .. k)] do k = k + 1 end
        nome_tr = nome_tr .. " " .. k
        tr = M.achar_filho(pasta_tr, nome_tr)
      end
      if not tr then tr = M.inserir_filho_no_fim(pasta_tr, nome_tr, sp.cor) end
    end
    usadas[tr] = true
    local src = r.PCM_Source_CreateFromFile(pasta .. SEP .. caminho)
    local len = src and r.GetMediaSourceLength(src) or 0
    if src and len > offset then
      len = len - offset
      local it = r.AddMediaItemToTrack(tr)
      r.SetMediaItemInfo_Value(it, "D_POSITION", inicio + audio_ini)
      r.SetMediaItemInfo_Value(it, "D_LENGTH", len)
      r.SetMediaItemInfo_Value(it, "C_BEATATTACHMODE", 0) -- base de tempo: TEMPO (não segue BPM)
      local tk = r.AddTakeToMediaItem(it)
      r.SetMediaItemTake_Source(tk, src)
      if offset > 0 then r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", offset) end
      r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", f, true)
      r.UpdateItemInProject(it)
      if inicio + audio_ini + len > fim then fim = inicio + audio_ini + len end
      if destino == "CLICK" or destino == "GUIA" then itens_fone[#itens_fone + 1] = it end
      relatorio[#relatorio + 1] = string.format("  %-28s -> %s", caminho, destino)
      n_ok = n_ok + 1
    else
      relatorio[#relatorio + 1] = string.format("  %-28s -> ERRO ao abrir", caminho)
    end
  end

  -- seções
  -- prioridade: marcadores.txt (salvo por você) > .als do Ableton > cues dos WAV
  local lista, arq_mk = arquivo_marcadores_na_pasta(pasta, txts)
  if not lista and inf.als then
    lista = M.secoes_do_als(inf.als)
    if lista then arq_mk = "Ableton (" .. (inf.als_arquivo:match("([^\\/]+)$") or ".als") .. ")" end
  end
  local origem_secoes = "nenhuma (use MARCAR SEÇÃO)"
  if lista then
    for _, s in ipairs(lista) do
      local ts = math.max(0, s.t - offset)
      if ts < fim - inicio then
        r.AddProjectMarker2(0, false, inicio + ts, 0, s.nome, -1, M.cor_secao(s.nome))
      end
    end
    origem_secoes = arq_mk
  else
    local antes = select(2, r.CountProjectMarkers(0))
    importar_cues(itens_fone, inicio, fim)
    local depois = select(2, r.CountProjectMarkers(0))
    if depois > antes then origem_secoes = "cues do arquivo de áudio" end
    -- colore os marcadores importados
    local _, marcas = M.listar_marcadores()
    for _, mk in ipairs(marcas) do
      if mk.inicio >= inicio - 0.001 and mk.inicio < fim then
        r.SetProjectMarker3(0, mk.idx, false, mk.inicio, 0, mk.nome:upper(), M.cor_secao(mk.nome))
      end
    end
  end

  -- região da música
  local n_mus = #M.get_musicas()
  local cor = M.cor_nativa(M.PALETA_MUSICAS[(n_mus % #M.PALETA_MUSICAS) + 1])
  local nome_regiao = nome .. ((tom and tom ~= "") and (" [" .. tom .. "]") or "")
  r.AddProjectMarker2(0, true, inicio, fim, nome_regiao, -1, cor)
  r.SetProjExtState(0, "MT_PASTA", M.norm(nome), inf.musica)
  M.set_transp_valor({ nome = nome }, 0)

  -- PAD no tom
  if tom and tom ~= "" then
    local m = M.musica_atual(inicio + 0.01)
    if m then M.gerar_pad(m) end
  end

  M.aplicar_modo()
  r.Main_OnCommand(40047, 0) -- Peaks: Build any missing peaks
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.UpdateTimeline()
  r.Undo_EndBlock("Importar multitrack: " .. nome, -1)
  M.set("ULTIMA_PASTA", pasta:match("^(.*)[\\/][^\\/]*$") or pasta)

  local msg = string.format("Música importada: %s\nTom: %s   BPM: %s  (%s/%s)\nInício no projeto: %s\nSeções: %s\n\nStems importados: %s de %s\n%s",
    nome_regiao, tom or "(não definido)", bpm and tostring(bpm) or "(não definido)",
    tostring(inteiro(num, 4)), tostring(inteiro(den, 4)),
    fmt_tempo(inicio), origem_secoes, tostring(inteiro(n_ok, 0)), tostring(inteiro(#audios, 0)), table.concat(relatorio, "\n"))
  pcall(M.pedir_capa_pasta, inf.musica, nome, (inf and (inf.artista or inf.ARTISTA)))
  return true, msg, inicio
end

function M.importar_interativo()
  local pasta, erro = M.escolher_pasta()
  if erro then return r.MB(erro, "Importar multitrack", 0) end
  if not pasta then return end
  local inf = M.info_pasta(pasta)
  -- Escolheu um arquivo dentro de uma subpasta de GRUPO (ex.: VS\Bateria\Kick.wav)?
  -- Oferece importar a pasta de cima (a multitrack inteira).
  local pai = pai_de(inf.musica)
  local nome_sub = inf.musica:match("([^\\/]+)$") or ""
  if pai and not inf.als_arquivo and M.classificar_stem(nome_sub) ~= M.DESTINO_PADRAO then
    local irmas = 0
    for _, d in ipairs(listar_subpastas(pai)) do
      if d ~= nome_sub and #coletar_audios(pai .. SEP .. d, 2) > 0 then irmas = irmas + 1 end
    end
    if irmas > 0 then
      local inf_pai = M.info_pasta(pai)
      local q = r.MB(string.format("A pasta \"%s\" parece ser só um grupo da multitrack.\n\n"
        .. "SIM = importar a multitrack INTEIRA (\"%s\", %d stems)\nNÃO = importar só \"%s\" (%d stems)",
        nome_sub, pai:match("([^\\/]+)$") or pai, #inf_pai.audios, nome_sub, #inf.audios), "Importar multitrack", 3)
      if q == 2 then return end          -- cancelar
      if q == 6 then inf = inf_pai end   -- sim
    end
  end
  if #inf.audios == 0 then
    return r.MB("Nenhum arquivo de áudio (wav, mp3, flac...) encontrado em:\n" .. pasta
      .. "\n\nnem nas subpastas dela.", "Importar multitrack", 0)
  end
  -- confirma mostrando TODOS os stems que vão entrar
  local linhas, max = {}, 40
  for i, f in ipairs(inf.audios) do
    if i > max then linhas[#linhas + 1] = string.format("   ... e mais %d", #inf.audios - max); break end
    linhas[#linhas + 1] = "   " .. f
  end
  local resp_ok = r.MB(string.format("Pasta: %s\n\nEncontrei %d stems - TODOS serão importados:\n%s%s\n\nContinuar?",
    inf.audio, #inf.audios, table.concat(linhas, "\n"),
    inf.als_arquivo and ("\n\nSeções/BPM do Ableton: " .. (inf.als_arquivo:match("([^\\/]+)$") or "")) or ""),
    "Importar multitrack", 1)
  if resp_ok ~= 1 then return end
  local nome, tom, bpm = inf.nome, inf.tom, inf.bpm
  local compasso = inf.num and (inf.num .. "/" .. inf.den) or ((inf.als and inf.als.num) and (inf.als.num .. "/" .. inf.als.den)) or "4/4"
  local ok, resp = r.GetUserInputs("Importar multitrack", 5,
    "Nome da música:,Artista (opcional):,Tom original (ex.: G  Bb  F#m):,BPM (para pular por compasso):,Compasso (4/4  6/8  3/4):,extrawidth=200,separator=|",
    (nome or "") .. "|" .. (inf.artista or "") .. "|" .. (tom or "") .. "|" .. (bpm and tostring(bpm) or "") .. "|" .. compasso)
  if not ok then return end
  local n2, a2, t2, b2, c2 = resp:match("^(.-)|(.-)|(.-)|(.-)|(.-)$")
  n2, a2, t2, b2, c2 = trim(n2), trim(a2), trim(t2), trim(b2), trim(c2)
  if t2 ~= "" and not M.ler_tom(t2) then
    r.MB("Tom inválido: " .. t2 .. "\nA música será importada sem tom (use DEFINIR TOM depois).", "Importar", 0)
    t2 = ""
  end
  local avisos = {}
  if t2 == "" then avisos[#avisos + 1] = "- sem TOM: o PAD não será criado (use DEFINIR TOM depois)" end
  if b2 == "" then avisos[#avisos + 1] = "- sem BPM: o salto suave e a grade usam o andamento da música anterior" end
  if #avisos > 0 then
    if r.MB("Atenção:\n" .. table.concat(avisos, "\n") .. "\n\nImportar assim mesmo?", "Importar multitrack", 1) ~= 1 then return end
  end
  local cn, cd = c2:match("^(%d+)%s*/%s*(%d+)$")
  local nome_final = (n2 ~= "" and n2) or nome
  -- Biblioteca: mover / copiar / usar no lugar
  local pasta_musica = inf.musica
  if not M.na_biblioteca(pasta_musica) then
    local nome_dest = M.nome_pasta_musica(nome_final, a2, t2)
    local q = r.MB("Esta multitrack está fora da sua Biblioteca:\n" .. M.pasta_biblioteca() ..
      "\n\nSIM = MOVER a pasta para a biblioteca (recomendado)\nNÃO = COPIAR para a biblioteca (o original fica)\n" ..
      "CANCELAR = usar no lugar onde está\n\nNome na biblioteca: " .. nome_dest, "Importar multitrack", 3)
    if q == 6 or q == 7 then
      local nova, como = M.levar_para_biblioteca(pasta_musica, nome_dest, q == 6 and "mover" or "copiar")
      if not nova then
        if r.MB("Não consegui levar para a biblioteca:\n" .. tostring(como) .. "\n\nImportar do lugar original?", "Importar", 1) ~= 1 then return end
      else
        pasta_musica = nova
        inf = M.info_pasta(nova)
      end
    end
  end
  M.atualizar_info(pasta_musica, { NOME = nome_final, ARTISTA = a2, TOM = t2, BPM = b2:gsub(",", "."),
    COMPASSO = cn and (cn .. "/" .. cd) or nil, OFFSET = inf.offset })
  local sucesso, msg = M.importar_pasta(inf.audio, {
    info = inf,
    nome = nome_final,
    tom = (t2 ~= "" and t2) or nil,
    bpm = tonumber((b2:gsub(",", "."))),
    num = tonumber(cn), den = tonumber(cd),
  })
  r.ShowConsoleMsg("") -- limpa
  if sucesso then r.ShowConsoleMsg(msg .. "\n") else r.MB(msg, "Importar multitrack", 0) end
end

-------------------------------------------------------------------------------
-- IMPORTAR RÁPIDO (botão IMPORTAR do painel, Ctrl+Shift+I, arrastar e soltar)
--  * escolhe a pasta (ou recebe a pasta solta no painel)
--  * subpasta de grupo (VS\Bateria...)? sobe sozinho para a multitrack inteira
--  * nome / tom / BPM / compasso: detectados (mt_info.txt, .als, nome da pasta)
--  * só pergunta o TOM, e só se não achou (vazio = importa sem tom)
--  * COPIA para a Biblioteca (o original não é mexido) e mostra um "pronto!"
-- O fluxo antigo, com todas as perguntas, continua em M.importar_interativo
-- (Menu > Importar (avançado)...).
-------------------------------------------------------------------------------
local function mesma_pasta(a, b) return chave_caminho(a) == chave_caminho(b) end

-- Escolheu uma subpasta de GRUPO da multitrack (ex.: VS\Bateria)? devolve a info da
-- multitrack inteira (pasta de cima). Só sobe quando tem certeza: a pasta de cima não
-- é a Biblioteca, a maioria das pastas irmãs com áudio tem nome de grupo e a de cima
-- tem mais stems.
local function subir_para_multitrack(inf)
  local pai = pai_de(inf.musica)
  if not pai or pai == "" or inf.als_arquivo or inf.meta then return inf end
  if mesma_pasta(pai, M.pasta_biblioteca()) then return inf end
  local nome_sub = inf.musica:match("([^\\/]+)$") or ""
  if M.classificar_stem(nome_sub) == M.DESTINO_PADRAO then return inf end
  local com_audio, grupos = 0, 0
  for _, d in ipairs(listar_subpastas(pai)) do
    if #coletar_audios(pai .. SEP .. d, 2) > 0 then
      com_audio = com_audio + 1
      if M.classificar_stem(d) ~= M.DESTINO_PADRAO then grupos = grupos + 1 end
    end
  end
  if com_audio < 2 or grupos * 2 < com_audio then return inf end
  local inf_pai = M.info_pasta(pai)
  if #inf_pai.audios > #inf.audios then return inf_pai end
  return inf
end

-- Caminho solto no painel (pasta ou arquivo) -> pasta da música. Retorna pasta, erro
function M.pasta_do_caminho(c)
  c = (trim(c or ""):gsub("[\\/]+$", ""))
  if c == "" then return nil end
  r.EnumerateFiles(c, -1); r.EnumerateSubdirectories(c, -1)
  if r.EnumerateFiles(c, 0) or r.EnumerateSubdirectories(c, 0) then return c end
  local ext = (c:match("%.([^%.\\/]+)$") or ""):lower()
  if ext == "zip" or ext == "rar" or ext == "7z" then
    return nil, "\"" .. (c:match("([^\\/]+)$") or c) .. "\" é compactado (." .. ext .. "). Extraia primeiro."
  end
  if ext ~= "" then return pai_de(c) end  -- arquivo: usa a pasta dele
  return c                                -- pasta vazia: o importador avisa
end

-- Importa UMA multitrack do jeito simples.
-- pasta = nil abre a janela de escolher pasta.
-- opcoes.silencioso = não mostra mensagens (usado ao importar várias de uma vez)
-- Retorna: ok, mensagem, nome_da_musica
-- Depois de importar uma música comum / VS fechado (1 áudio): click, guia, seções,
-- cifra e separação automáticos. Usado pelo + IMPORTAR e (v1.4) pela Biblioteca.
-- Devolve: feito (true = a análise vai mostrar o resultado sozinha), resumo
function M.automatico_apos_importar(inicio_mus, inf, nome, resumo, titulo, opcoes)
  opcoes = opcoes or {}
  local m = M.musica_atual(inicio_mus + 0.01)
  if m and inf.meta and inf.meta.ANALISE == "1" then
    -- já analisada antes: só recoloca click/guia/cifra (sem reanalisar)
    r.Undo_BeginBlock()
    local ok_r, partes = M.restaurar_extras(m, inf.meta, inf.musica)
    r.Undo_EndBlock("Click/guia/cifra: " .. nome, -1)
    if ok_r and partes ~= "" then resumo = resumo .. "\n\nRecolocados da análise salva: " .. partes end
    if not opcoes.sem_separar and M.separacao_auto() and (M.motor_instalado() or M.motor_instalando() or inf.meta.STEMS == "1") then
      local oks, como = M.separar_musica(m, { silencioso = true, automatico = true })
      if oks then resumo = resumo .. "\nTrilhas separadas (bateria, baixo, guitarra, teclado, voz, outros): " .. tostring(como) end
    elseif not opcoes.sem_separar and M.separacao_auto() then
      -- v1.8: antes, sem o motor, não separava e não avisava
      M.anotar_sem_motor(m)
      resumo = resumo .. "\n\nTrilhas: NÃO separadas - falta instalar o motor de separação (Menu > Instalar motor de separação)."
      r.defer(function() M.oferecer_motor_pendentes() end)
    end
    pcall(M.recuperar_marcadores_faltando, m)
    return false, resumo
  elseif m then
    -- Mesma função do menu "Gerar click + guia + seções + cifra", em pcall, sem popup.
    -- Seções já existentes (ALS, marcadores.txt) são mantidas.
    local op_auto = {
      silencioso = true,
      refazer_secoes = false,
      musica = m,
      inicio = inicio_mus,
      separar = M.separacao_auto() and not opcoes.sem_separar,
    }
    do
      local n, d = opcoes.num, opcoes.den
      if (not n or not d) and inf and inf.num then n, d = inf.num, inf.den or d end
      if (not n or not d) and inf and inf.als then n, d = inf.als.num or n, inf.als.den or d end
      if (not n or not d) and inf and inf.meta and inf.meta.COMPASSO then
        n, d = M.ler_compasso_txt(inf.meta.COMPASSO, n, d)
      end
      if n then op_auto.num, op_auto.bpb = n, n end
      if d then op_auto.den = d end
      if n and d then op_auto.compasso = n .. "/" .. d end
      if opcoes.bpm then op_auto.bpm = opcoes.bpm end
    end
    local okp, okf, err = pcall(M.analisar_musica_atual, op_auto)
    if not okp then
      r.ShowConsoleMsg("[Mik Seifador] automático após importar falhou: " .. tostring(okf) .. "\n")
    elseif okf == false then
      r.ShowConsoleMsg("[Mik Seifador] automático após importar: " .. tostring(err or okf) .. "\n")
    end
    pcall(M.recuperar_marcadores_faltando, m)
    return true, resumo
  end
  return false, resumo
end

-- Recupera seções se a música ficou só com a região (ex.: crash no meio da análise).
-- Fontes: marcadores.txt / markers.txt, .als do Ableton, cues dos WAV. Não apaga
-- marcadores que já existam. Roda sozinha no tick (parado) e após importar.
local _rec_mk_ok, _rec_mk_t = {}, 0
function M.recuperar_marcadores_faltando(m)
  if not m then return false end
  local secs = M.secoes_da_musica(m)
  local n = 0
  for _, s in ipairs(secs or {}) do
    if not s.virtual then n = n + 1 end
  end
  if n > 0 then return false, n end
  local _, pasta = r.GetProjExtState(0, "MT_PASTA", M.norm(m.nome))
  if not pasta or pasta == "" then return false end
  local lista
  lista = M.ler_arquivo_marcadores(pasta .. SEP .. "marcadores.txt")
    or M.ler_arquivo_marcadores(pasta .. SEP .. "markers.txt")
  if not lista then
    local ok_i, inf = pcall(M.info_pasta, pasta)
    if ok_i and inf then
      if inf.als then lista = M.secoes_do_als(inf.als) end
      if not lista and inf.txts then
        lista = select(1, arquivo_marcadores_na_pasta(pasta, inf.txts))
      end
    end
  end
  if not lista or #lista == 0 then return false end
  local colocados = 0
  for _, s in ipairs(lista) do
    local ts = m.inicio + math.max(0, tonumber(s.t) or 0)
    if ts < (m.fim or ts + 1) - 0.01 then
      r.AddProjectMarker2(0, false, ts, 0, s.nome, -1, M.cor_secao(s.nome))
      colocados = colocados + 1
    end
  end
  return colocados > 0, colocados
end

function M.verificar_marcadores_auto()
  if r.GetPlayState() ~= 0 then return end
  local agora = r.time_precise()
  if agora - _rec_mk_t < 2 then return end
  _rec_mk_t = agora
  for _, m in ipairs(M.get_musicas()) do
    local chave = M.norm(m.nome) .. "|" .. string.format("%.3f", m.inicio or 0)
    local secs = M.secoes_da_musica(m)
    local n = 0
    for _, s in ipairs(secs or {}) do
      if not s.virtual then n = n + 1 end
    end
    if n > 0 then
      _rec_mk_ok[chave] = nil  -- tem seções; se sumirem depois, tenta de novo
    elseif _rec_mk_ok[chave] ~= "sem-fonte" then
      local ok, feito = pcall(M.recuperar_marcadores_faltando, m)
      if not (ok and feito) then _rec_mk_ok[chave] = "sem-fonte" end
    end
  end
end

function M.importar_rapido(pasta, opcoes)
  opcoes = opcoes or {}
  local titulo = "Importar música"
  local function falha(msg)
    if not opcoes.silencioso then r.MB(msg, titulo, 0) end
    return false, msg
  end
  if not pasta or pasta == "" then
    local lista, erro = M.escolher_para_importar()
    if erro and (not lista or #lista == 0) then return falha(erro) end
    if not lista or #lista == 0 then return false end  -- cancelou
    if #lista > 1 then
      local como = M.decidir_varios_arquivos(lista)
      if como == "cancelar" then return false end
      if como == "multitrack" then return M.importar_multitrack_arquivos(lista, opcoes) end
      return M.importar_varias(lista, como == "musicas")
    end
    local c = lista[1]
    local ext = (c:match("%.([^%.\\/]+)$") or ""):lower()
    if ext == "zip" or ext == "rar" or ext == "7z" then
      return falha("Esse arquivo é compactado (." .. ext .. ").\n\nExtraia primeiro (botão direito > Extrair tudo) e depois "
        .. "escolha qualquer arquivo dentro da pasta extraída.")
    end
    -- um arquivo de música avulso (ex.: mp3 no Downloads): importa só ele
    if M.eh_musica_solta(c) then return M.importar_arquivo(c, opcoes) end
    -- arquivo dentro de uma pasta de multitrack (ou a própria pasta): importa a pasta
    local p, err2 = M.pasta_do_caminho(c)
    if err2 then return falha(err2) end
    pasta = p or c
  end
  pasta = (pasta:gsub("[\\/]+$", ""))
  -- Pasta com várias músicas completas (não é pacote de stems): cada arquivo
  -- vira uma música. Nunca junta os irmãos numa única região.
  if not opcoes.forcar_multitrack and not M.pasta_parece_multitrack(pasta) then
    local audios_aqui = listar_arquivos(pasta)
    if #audios_aqui > 1 then
      local lista = {}
      for _, f in ipairs(audios_aqui) do lista[#lista + 1] = pasta .. SEP .. f end
      return M.importar_varias(lista)
    end
  end
  local inf = subir_para_multitrack(M.info_pasta(pasta))
  if opcoes.forcar_multitrack then inf = M.info_pasta(pasta) end
  local function filtrar(i)
    if not opcoes.so_arquivos then return i end
    local fica = {}
    for _, f in ipairs(i.audios) do
      if opcoes.so_arquivos[(f:match("([^\\/]+)$") or f):lower()] then fica[#fica + 1] = f end
    end
    if #fica > 0 then i.audios = fica end
    return i
  end
  inf = filtrar(inf)
  if #inf.audios == 0 then
    return falha("Nenhum arquivo de áudio (wav, mp3, flac...) encontrado em:\n" .. pasta .. "\n\nnem nas subpastas dela.")
  end
  local nome = (inf.nome and inf.nome ~= "") and inf.nome or "Música"
  local tom = inf.tom
  if tom and not M.ler_tom(tom) then tom = nil end
  -- v1.8: qualquer importação (1 arquivo, multitrack ou com .als) dispara
  -- a mesma função do menu, logo de cara, se a análise automática estiver ligada.
  local auto = M.analise_auto()
  local auto_mt = false
  -- única pergunta: o TOM, e só se não foi detectado (na análise automática o tom é detectado)
  if not tom and not auto then
    while true do
      local ok, txt = r.GetUserInputs("Tom de: " .. nome .. "  (vazio = sem tom)", 1,
        "Tom original (ex.: G  Bb  F#m),extrawidth=120", "")
      if not ok then return false end         -- cancelou
      txt = trim(txt)
      if txt == "" then break end
      if M.ler_tom(txt) then tom = txt; break end
      r.MB("Tom inválido: " .. txt .. "\n\nExemplos: C  G  Bb  F#  Am  C#m\n(ou deixe vazio para importar sem tom)", titulo, 0)
    end
  end
  local compasso = inf.num and (inf.num .. "/" .. inf.den)
    or ((inf.als and inf.als.num) and (inf.als.num .. "/" .. inf.als.den)) or nil
  local ficha = { NOME = nome, ARTISTA = inf.artista, TOM = tom, BPM = inf.bpm, COMPASSO = compasso, OFFSET = inf.offset }
  -- Só marca TIPO=STEMS quando a pasta realmente parece um pacote de stems.
  -- Pasta de músicas completas (mesmo dentro da Biblioteca) não recebe essa marca.
  if #inf.audios > 1 and (opcoes.forcar_multitrack or M.pasta_parece_multitrack(inf.audio or pasta)) then ficha.TIPO = "STEMS" end
  if opcoes.forcar_multitrack then ficha.IMPORTAR_COMO = "MULTITRACK" end
  -- Biblioteca: COPIA (seguro: o original fica intacto). Já está na biblioteca? usa no lugar.
  local nota_bib = ""
  if M.na_biblioteca(inf.musica) then
    M.atualizar_info(inf.musica, ficha)
  else
    local nome_dest = M.nome_pasta_musica(nome, inf.artista, tom)
    local ja = M.pasta_biblioteca() .. SEP .. nome_dest
    local nova, como
    if existe_pasta(ja) and #coletar_audios(ja, 4) > 0 and #coletar_audios(ja, 4) == #coletar_audios(inf.musica, 4) then
      nova = ja                               -- já foi copiada antes: não duplica
    else
      nova, como = M.levar_para_biblioteca(inf.musica, nome_dest, "copiar")
    end
    if nova then
      M.atualizar_info(nova, ficha)
      local inf_nova = M.info_pasta(nova)
      if #inf_nova.audios > 0 then
        -- .als que estava na pasta "de cima" (fora da cópia): continua valendo
        if not inf_nova.als and inf.als then inf_nova.als, inf_nova.als_arquivo = inf.als, inf.als_arquivo end
        inf = filtrar(inf_nova)
        nota_bib = "\n\nCopiada para a Biblioteca (o original não foi mexido)."
      end
    else
      nota_bib = "\n\nNão deu para copiar para a Biblioteca (" .. tostring(como) .. "); usei a pasta original."
    end
  end
  local sucesso, msg, inicio_mus = M.importar_pasta(inf.audio, {
    info = inf, nome = nome, tom = tom, bpm = inf.bpm, num = inf.num, den = inf.den,
  })
  if not sucesso then return falha(msg) end
  local n_ok, n_tot = msg:match("Stems importados: (%d+) de (%d+)")
  local secoes = msg:match("Seções: ([^\n]*)") or "-"
  local rotulo = nome .. (tom and (" [" .. tom .. "]") or "")
  local resumo = string.format("Pronto! Música importada no fim do setlist:\n\n%s\nTom: %s    BPM: %s\nStems: %s de %s    Seções: %s%s",
    rotulo, tom or "(sem tom)", inf.bpm and tostring(inf.bpm) or "(sem BPM)", n_ok or "?", n_tot or "?", secoes, nota_bib)
  local sem_secoes = secoes:find("^nenhuma") ~= nil
  -- v1.8: se a análise automática for rodar (menu click+guia+seções+cifra),
  -- ela já gera o que faltar; não antecipa com completar_click_guia.
  if #inf.audios > 1 and inicio_mus and not auto then
    local m_cg = M.musica_atual(inicio_mus + 0.01)
    if m_cg then
      local bpm_ok = (inf.bpm and inf.bpm > 0) or inf.als or (inf.meta and inf.meta.ANALISE == "1")
      local cg = M.click_guia_da_musica(m_cg)
      if not bpm_ok and not cg.CLICK and M.analise_auto() and not sem_secoes then
        -- BPM desconhecido: a análise acha o andamento (mantém seções e áudio no lugar)
        local op_a = { sem_separar = true, nao_mover = true }
        for k, v in pairs(opcoes) do if op_a[k] == nil then op_a[k] = v end end
        opcoes = op_a
        auto = true
      else
        r.Undo_BeginBlock()
        local txt = M.completar_click_guia(m_cg, { sem_click = (not bpm_ok) and "BPM desconhecido: use Menu > Analisar" or nil })
        r.Undo_EndBlock("Click/guia da multitrack: " .. nome, -1)
        M.aplicar_modo()
        resumo = resumo .. "\n\n" .. txt
      end
    end
  end
  if auto_mt and sem_secoes and inicio_mus then
    -- multitrack sem seções: análise (click se faltar, guia, SEÇÕES, cifra), sem separar
    local op_mt = {}
    for k, v in pairs(opcoes) do op_mt[k] = v end
    op_mt.sem_separar = true
    auto = true
    opcoes = op_mt
  end
  if auto and inicio_mus then
    local feito, res2 = M.automatico_apos_importar(inicio_mus, inf, nome, resumo, titulo, opcoes)
    resumo = res2 or resumo
    if feito then return true, resumo, rotulo end
  end
  if not opcoes.silencioso then r.MB(resumo, titulo, 0) end
  return true, resumo, rotulo
end

-- v1.8: + IMPORTAR com vários arquivos escolhidos. Devolve "multitrack", "musicas",
-- "auto" (deixa a detecção decidir) ou "cancelar".
--  * todos da MESMA pasta e a pasta parece multitrack -> multitrack (sem perguntar)
--  * todos da mesma pasta, NÃO detectada, mas a maioria tem nome de stem -> pergunta
function M.decidir_varios_arquivos(lista)
  if #lista < 2 then return "auto" end
  local pasta0 = pai_de(lista[1])
  local n_audio, n_stem = 0, 0
  for _, c in ipairs(lista) do
    local p = pai_de(c)
    if not p or not pasta0 or chave_caminho(p) ~= chave_caminho(pasta0) then return "auto" end
    local ext = (c:match("%.([^%.\\/]+)$") or ""):lower()
    if EXT_AUDIO[ext] then
      n_audio = n_audio + 1
      if M.nome_parece_stem(c:match("([^\\/]+)$") or c) then n_stem = n_stem + 1 end
    end
  end
  if n_audio < 2 then return "auto" end
  local meta = M.ler_info(pasta0)
  local como = meta and (meta.IMPORTAR_COMO or ""):upper() or ""
  if como == "MULTITRACK" then return "multitrack" end
  if como == "MUSICAS" then return "musicas" end
  if M.pasta_parece_multitrack(pasta0) then return "multitrack" end
  if n_stem >= 2 and n_stem >= math.ceil(n_audio * 0.5) then
    local q = r.MB(string.format("Você escolheu %d arquivos da mesma pasta e eles parecem STEMS de uma música só "
      .. "(ex.: %s).\n\nSIM = importar como UMA multitrack (VS)\nNÃO = importar cada arquivo como uma música separada",
      n_audio, lista[1]:match("([^\\/]+)$") or lista[1]), "Importar", 3)
    if q == 2 then return "cancelar" end
    return q == 6 and "multitrack" or "musicas"
  end
  return "musicas"
end

-- v1.8: importa os arquivos escolhidos (stems de UMA pasta) como UMA multitrack
function M.importar_multitrack_arquivos(lista, opcoes, pasta_inteira)
  local pasta = lista and lista[1] and pai_de(lista[1])
  if not pasta then return false end
  local sel, n = {}, 0
  for _, c in ipairs(lista) do
    local nm = (c:match("([^\\/]+)$") or c):lower()
    if not sel[nm] then sel[nm] = true; n = n + 1 end
  end
  local o = {}
  for k, v in pairs(opcoes or {}) do o[k] = v end
  o.forcar_multitrack = true
  -- escolheu TODOS os áudios da pasta? então não precisa filtrar
  local todos = listar_arquivos(pasta) or {}
  if n < #todos and not pasta_inteira then o.so_arquivos = sel end
  return M.importar_rapido(pasta, o)
end

-- v1.8: + IMPORTAR > Multitrack (pasta): escolhe a PASTA e importa como UMA multitrack
function M.importar_multitrack_pasta()
  local pasta, erro = M.escolher_pasta()
  if erro then return r.MB(erro, "Importar multitrack", 0) end
  if not pasta or pasta == "" then return false end
  pasta = (pasta:gsub("[\\/]+$", ""))
  -- sem JS_Dialog_BrowseForFolder o seletor devolve a pasta do arquivo escolhido
  if #coletar_audios(pasta, 3) == 0 then
    return r.MB("Nenhum arquivo de áudio (wav, mp3, flac...) encontrado em:\n" .. pasta, "Importar multitrack", 0)
  end
  return M.importar_rapido(pasta, { forcar_multitrack = true })
end

-- Importa várias pastas/arquivos (ex.: soltos no painel) em sequência, do jeito rápido.
function M.importar_varias(caminhos, so_musicas)
  local pastas, vistas, erros = {}, {}, {}
  local avulsos = {}
  for _, c in ipairs(caminhos or {}) do
    local p, erro = M.pasta_do_caminho(c)
    local ext_c = (trim(c or ""):match("%.([^%.\\/]+)$") or ""):lower()
    if so_musicas and p and EXT_AUDIO[ext_c] then
      avulsos[#avulsos + 1] = trim(c)   -- o usuário disse: cada arquivo é uma música
    elseif p and p ~= (trim(c or ""):gsub("[\\/]+$", "")) and M.eh_musica_solta(trim(c)) then
      avulsos[#avulsos + 1] = trim(c)   -- arquivo de música solto: importa só ele
    elseif p then
      local k = chave_caminho(p)
      if not vistas[k] then vistas[k] = true; pastas[#pastas + 1] = p end
    elseif erro then
      erros[#erros + 1] = erro
    end
  end
  if #pastas == 0 and #avulsos == 0 then
    if #erros > 0 then r.MB(table.concat(erros, "\n"), "Importar música", 0) end
    return false
  end
  if #pastas == 1 and #avulsos == 0 and #erros == 0 then return M.importar_rapido(pastas[1]) end
  if #avulsos == 1 and #pastas == 0 and #erros == 0 then return M.importar_arquivo(avulsos[1]) end
  local linhas, n_ok = {}, 0
  for _, a in ipairs(avulsos) do
    local ok, msg, rotulo = M.importar_arquivo(a, { silencioso = true })
    local nome_a = a:match("([^\\/]+)$") or a
    if ok then n_ok = n_ok + 1; linhas[#linhas + 1] = "OK   " .. (rotulo or nome_a)
    else linhas[#linhas + 1] = "ERRO " .. nome_a .. ": " .. ((msg or "cancelada"):match("^[^\n]*") or "") end
  end
  for _, p in ipairs(pastas) do
    local ok, msg, rotulo = M.importar_rapido(p, { silencioso = true })
    local nome_p = p:match("([^\\/]+)$") or p
    if ok then
      n_ok = n_ok + 1
      linhas[#linhas + 1] = "OK   " .. (rotulo or nome_p)
    elseif msg then
      linhas[#linhas + 1] = "ERRO " .. nome_p .. ": " .. (msg:match("^[^\n]*") or msg)
    else
      linhas[#linhas + 1] = "---  " .. nome_p .. " (cancelada)"
    end
  end
  for _, e in ipairs(erros) do linhas[#linhas + 1] = "ERRO " .. e end
  if n_ok > 0 and M.numerar_fila_importacao then M.numerar_fila_importacao() end
  local n_tot = #pastas + #avulsos + #erros
  local nota_fila = ""
  if M.analise_ocupada() then
    nota_fila = "\n\nMúsicas comuns: click, guia, seções, cifra e separação uma de cada vez "
      .. "(o painel mostra \"Importando 2 de 5: ...\"; dá para cancelar o resto da fila)."
  end
  r.MB(string.format("Importadas %d de %d músicas (no fim do setlist):\n\n%s%s", n_ok, n_tot,
    table.concat(linhas, "\n"), nota_fila),
    "Importar música", 0)
  return n_ok > 0
end

-------------------------------------------------------------------------------
-- MÚSICA COMUM / VS FECHADO: CLICK, GUIA, SEÇÕES e CIFRA automáticos
-------------------------------------------------------------------------------
--[[
  Ao importar UMA música comum (um arquivo só: mp3, wav...) ou um VS fechado,
  o kit analisa o áudio (mt_analise.lua, Lua puro, dentro do REAPER) e:
    * acha o BPM e o 1º tempo do compasso e alinha a grade do REAPER;
    * gera o CLICK (trilha CLICK do FONE) - num VS com click num lado (L/R),
      usa o click que já existe (separa os lados) e não cria outro;
    * divide a música em SEÇÕES (blocos de 4/8 compassos) com nomes sugeridos;
    * gera a GUIA falada ("um, dois, três, quatro", "Verso", "Refrão"...) um
      compasso antes de cada seção (arquivos em guia_voz\, troque pela sua voz
      em guia_voz\minha_voz\);
    * detecta a CIFRA (acordes) -> trilha CIFRA + painel + cifra.txt na pasta.
  Tudo fica salvo na pasta da música (mt_info.txt, marcadores.txt, cifra.txt):
  na próxima importação nada é reanalisado.
  Desligar: Menu > Análise automática ao importar.
]]
M.PASTA_VOZ = "guia_voz"
M.NOME_CIFRA = "CIFRA"
M.ARQ_CIFRA = "cifra.txt"

function M.analise_auto() return M.get("ANALISE_AUTO", "1") ~= "0" end
function M.alternar_analise_auto()
  M.set("ANALISE_AUTO", M.analise_auto() and "0" or "1")
  M.aviso("Análise automática ao importar: " .. (M.analise_auto() and "LIGADA" or "DESLIGADA"))
end

local MOD_ANALISE = nil
local function analise_mod()
  if not MOD_ANALISE then MOD_ANALISE = dofile(M.DIR .. "mt_analise.lua") end
  return MOD_ANALISE
end

-- ---------- arquivos de voz da guia ----------
-- Pacote gravado em português (guia_voz\). A chave ignora acento, maiúscula
-- e pontuação: "Pré Refrão 2", "PRE-REFRAO 2" e "pre_refrao_2" caem no mesmo arquivo.
-- Seção numerada (VERSO 3) usa o arquivo com número; se não houver (Verso 7),
-- cai no arquivo simples (Verso). Marcadores com o nome de um aviso extra
-- (ENTRA BATERIA, TODOS JUNTOS, REPETE, PAUSA…) disparam o arquivo correspondente.
local VOZ_POR_TIPO = { ["Intro"] = "intro", ["Verso"] = "verso", ["Pré-refrão"] = "pre_refrao", ["Refrão"] = "refrao",
  ["Ponte"] = "ponte", ["Instrumental"] = "instrumental", ["Final"] = "final", ["Espontâneo"] = "espontaneo" }
local VOZ_PALAVRA = { SOLO = "solo", INTERLUDIO = "interludio", INTERLUDE = "interludio",
  TAG = "tag", CODA = "coda",
  BREAK = "break", BREAKDOWN = "breakdown",
  VIRADA = "virada", OUTRO = "outro",
  REPETE = "repete", REPEAT = "repete", REPETIR = "repete",
  TURNAROUND = "turnaround",
  VAMP = "vamp" }
-- Prefere um.wav … seis.wav (curtos, cabem num tempo). Cai em 1.wav … 6.wav se não houver.
M.VOZ_CONTAGEM = { "um", "dois", "tres", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez", "onze", "doze" }
M.VOZ_CONTAGEM_ALT = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12" }

-- sinonimos (já normalizados, sem espaço/acento) -> chave do arquivo
local SINONIMOS_GUIA = {
  UM = "1", DOIS = "2", TRES = "3", QUATRO = "4", CINCO = "5", SEIS = "6",
  PRECHORUS = "PREREFRAO", PRE = "PREREFRAO", PREREFRAO = "PREREFRAO",
  CHORUS = "REFRAO", REFRAIN = "REFRAO", CORO = "CORO",
  VERSE = "VERSO", ESTROFE = "VERSO",
  BRIDGE = "PONTE",
  INTERLUDE = "INTERLUDIO",
  ENDING = "FINAL",
  OUTRO = "SAIDA",
  TAG = "CODA",
  VIRADA = "TURNAROUND",
  BREAKDOWN = "INSTRUMENTAL", BREAK = "INSTRUMENTAL",
  ESPONTANEO = "ADORACAOLIVRE", ESPONTANEA = "ADORACAOLIVRE",
  MOMENTO = "MINISTRACAO",
  POSTCHORUS = "POSREFRAO", POSREFRAO = "POSREFRAO",
  INTRODUCAO = "INTRODUCAO",  -- arquivo próprio; "INTRO" casa com Intro.wav
}

function M.chave_guia(s)
  return (M.norm(s):gsub("%s+", ""))
end

local cache_guia
function M.recarregar_guia() cache_guia = nil end

-- Pontua um arquivo de voz contra a chave pedida (preferir o mais específico).
-- "REFRÃO 1" deve ganhar Refrão 1.wav, não o genérico REFRAO.wav.
local ALT_CONTAGEM_CURTA = { um = true, dois = true, tres = true, quatro = true, cinco = true, seis = true,
  sete = true, oito = true, nove = true, dez = true, onze = true, doze = true }
local function pontuar_voz(k_arq, caminho, k_pedido)
  if not k_arq or k_arq == "" or not k_pedido or k_pedido == "" then return -1 end
  local pts = 0
  if k_arq == k_pedido then pts = pts + 100 end
  local pr, pn = k_pedido:match("^(.-)(%d+)$")
  local ar, an = k_arq:match("^(.-)(%d+)$")
  if pr and ar and pr == ar and pn == an then pts = pts + 80 end
  if pr and k_arq == pr then pts = pts + 12 end
  if ar and k_pedido == ar then pts = pts + 8 end
  if #k_pedido > 0 and k_arq:sub(1, #k_pedido) == k_pedido and #k_arq > #k_pedido then pts = pts + 20 end
  local nome = (caminho or ""):match("([^\\/]+)$") or ""
  pts = pts + math.min(#nome, 80) / 200
  local low = (caminho or ""):lower()
  -- clipes minúsculos minúsculos-nome (refrao.wav, pre_refrao.wav: palavra cortada)
  -- perdem para o arquivo completo com acento (Refrão.wav) quando a chave empata.
  local so_nome = nome:gsub("%.[^%.]+$", "")
  if so_nome == so_nome:lower() and so_nome:find("^[%l_%d]+$") and not ALT_CONTAGEM_CURTA[so_nome] then
    pts = pts - 1
  end
  if low:find("minha_voz", 1, true) then pts = pts + 50 end
  return pts
end

local function indice_guia()
  if cache_guia then return cache_guia end
  local idx = {}
  local function registrar(k, novo)
    if not k or k == "" then return end
    local velho = idx[k]
    if not velho then idx[k] = novo; return end
    local nome_n = novo:match("([^\\/]+)$") or novo
    local nome_v = velho:match("([^\\/]+)$") or velho
    local low_n, low_v = novo:lower(), velho:lower()
    if low_n:find("minha_voz", 1, true) and not low_v:find("minha_voz", 1, true) then
      idx[k] = novo
    elseif low_v:find("minha_voz", 1, true) and not low_n:find("minha_voz", 1, true) then
      -- mantém a voz do usuário
    else
      local bn = nome_n:gsub("%.[^%.]+$", "")
      local bv = nome_v:gsub("%.[^%.]+$", "")
      local curto_n = (bn == bn:lower()) and not ALT_CONTAGEM_CURTA[bn]
      local curto_v = (bv == bv:lower()) and not ALT_CONTAGEM_CURTA[bv]
      if curto_v and not curto_n then idx[k] = novo
      elseif curto_n == curto_v and #nome_n > #nome_v then idx[k] = novo end
    end
  end
  local function adicionar(pasta)
    if not pasta or pasta == "" then return end
    r.EnumerateFiles(pasta, -1)
    local i = 0
    while true do
      local f = r.EnumerateFiles(pasta, i)
      if not f then break end
      if f:sub(1, 2) ~= "._" then
        local base, ext = f:match("^(.*)%.([^%.]+)$")
        if base and EXT_AUDIO[ext:lower()] then
          registrar(M.chave_guia(base), pasta .. SEP .. f)
        end
      end
      i = i + 1
    end
  end
  local base = M.DIR .. M.PASTA_VOZ .. SEP
  adicionar(base)
  adicionar(base .. "minha_voz")  -- a voz do usuário tem prioridade
  cache_guia = idx
  return idx
end

local function melhor_voz(chave)
  if not chave or chave == "" then return nil, nil, -1 end
  local idx = indice_guia()
  local pedido = M.chave_guia(chave)
  if pedido == "" then pedido = tostring(chave) end
  local best_k, best_f, best_p = nil, nil, -1
  for k_arq, caminho in pairs(idx) do
    local pts = pontuar_voz(k_arq, caminho, pedido)
    if pts > best_p then best_p, best_k, best_f = pts, k_arq, caminho end
  end
  if best_p >= 80 then return best_f, best_k, best_p end
  if idx[pedido] then return idx[pedido], pedido, 100 end
  if best_p > 10 then return best_f, best_k, best_p end
  return nil, nil, -1
end

local function resolver_guia(chave)
  if not chave or chave == "" then return nil end
  local f = melhor_voz(chave)
  if f then return f end
  local k = M.chave_guia(chave)
  local raiz = k:match("^(.-)%d+$")
  if raiz and raiz ~= "" then
    local f2 = melhor_voz(raiz)
    if f2 then return f2 end
  end
  local sin = SINONIMOS_GUIA[k] or (raiz and SINONIMOS_GUIA[raiz])
  if sin then return (melhor_voz(sin)) end
  return nil
end

local ALT_CONTAGEM = {
  um = "1", dois = "2", tres = "3", quatro = "4", cinco = "5", seis = "6",
  sete = "7", oito = "8", nove = "9", dez = "10", onze = "11", doze = "12",
  ["1"] = "um", ["2"] = "dois", ["3"] = "tres", ["4"] = "quatro", ["5"] = "cinco", ["6"] = "seis",
  ["7"] = "sete", ["8"] = "oito", ["9"] = "nove", ["10"] = "dez", ["11"] = "onze", ["12"] = "doze",
}
function M.arquivo_voz(chave)
  if not chave then return nil end
  local by_idx = resolver_guia(chave)
  if by_idx then return by_idx end
  local base = M.DIR .. M.PASTA_VOZ .. SEP
  local function procurar_exato(ch)
    if not ch or ch == "" then return nil end
    for _, p in ipairs({ base .. "minha_voz" .. SEP, base }) do
      for _, ext in ipairs({ "wav", "mp3", "ogg", "flac", "aif" }) do
        local f = p .. ch .. "." .. ext
        if r.file_exists(f) then return f end
      end
    end
    return nil
  end
  local achou = procurar_exato(chave)
  if achou then return achou end
  local alt = ALT_CONTAGEM[M.chave_guia(chave)] or ALT_CONTAGEM[chave]
  if alt then
    local f = resolver_guia(alt) or procurar_exato(alt)
    if f then return f end
  end
  return nil
end

-- chave (nome normalizado) do arquivo de voz para o nome da seção
-- "VERSO 3" -> Verso 3.wav; "VERSO 7" -> Verso.wav; "ENTRA BATERIA" -> Entra Bateria.wav
function M.voz_da_secao(nome)
  if not nome or nome == "" then return nil end
  local _, desc = M.cor_secao_rgb(nome)
  if desc == "Contagem" then return "contagem" end

  local idx = indice_guia()
  local function tem(ch)
    return ch and ch ~= "" and idx[ch] and ch or nil
  end

  local k = M.chave_guia(nome)
  local _, k_melhor = melhor_voz(k)
  if k_melhor and pontuar_voz(k_melhor, (indice_guia()[k_melhor] or ""), k) >= 80 then
    return k_melhor
  end
  if tem(k) then return k end

  local raiz, num = k:match("^(.-)(%d+)$")

  -- "R 2" / "V 3" / "REFRÃO 1": tipo + número antes do genérico (REFRAO.wav)
  if desc then
    local d = M.chave_guia(desc)
    if num and tem(d .. num) then return d .. num end
    local sin = SINONIMOS_GUIA[d]
    if sin and num and tem(sin .. num) then return sin .. num end
    if tem(d) and not num then return d end
    if sin and tem(sin) and not num then return sin end
  end
  if num then
    if desc then
      local d = M.chave_guia(desc)
      if tem(d .. num) then return d .. num end
    end
  end

  local w = M.norm(nome):match("^(%w+)") or ""
  local alias = VOZ_PALAVRA[w] or SINONIMOS_GUIA[w]
  if alias then
    local a = M.chave_guia(alias)
    if num and tem(a .. num) then return a .. num end
    if tem(a) then return a end
    local sin = SINONIMOS_GUIA[a] or SINONIMOS_GUIA[M.chave_guia(alias)]
    if sin and tem(sin) then return sin end
  end
  if tem(w) then return w end
  if SINONIMOS_GUIA[k] and tem(SINONIMOS_GUIA[k]) then return SINONIMOS_GUIA[k] end
  if raiz and SINONIMOS_GUIA[raiz] and tem(SINONIMOS_GUIA[raiz]) then return SINONIMOS_GUIA[raiz] end
  if raiz and tem(raiz) then return raiz end
  return nil
end

-- ---------- itens gerados pelo kit (marcados com P_EXT:MT_GERADO) ----------
local function tipo_gerado(it)
  local _, v = r.GetSetMediaItemInfo_String(it, "P_EXT:MT_GERADO", "", false)
  if v == "" then return nil end
  return v
end
local function marcar_gerado(it, tipo) r.GetSetMediaItemInfo_String(it, "P_EXT:MT_GERADO", tipo, true) end

local function itens_no_intervalo(tr, ini, fim)
  local l = {}
  if not tr then return l end
  for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
    local it = r.GetTrackMediaItem(tr, k)
    local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
    if p >= ini - 0.01 and p < fim - 0.001 then l[#l + 1] = it end
  end
  return l
end

local function apagar_gerados(tr, ini, fim, tipo)
  for _, it in ipairs(itens_no_intervalo(tr, ini, fim)) do
    local g = tipo_gerado(it)
    if g and (not tipo or g == tipo) then r.DeleteTrackMediaItem(tr, it) end
  end
end

local function tem_item_proprio(tr, ini, fim)
  for _, it in ipairs(itens_no_intervalo(tr, ini, fim)) do
    if not tipo_gerado(it) then return true end
  end
  return false
end

local function tem_gerado(tr, ini, fim, tipo)
  for _, it in ipairs(itens_no_intervalo(tr, ini, fim)) do
    if tipo_gerado(it) == tipo then return true end
  end
  return false
end

-- v1.8: a música já tem CLICK / GUIA próprios (vindos da multitrack ou colocados por você)?
-- Olha a trilha CLICK/GUIA do FONE e QUALQUER trilha com nome de click/guia (click, clic,
-- metronomo, metro, CLK / guia, guide, cues, guide voice, vocal guide). Numa multitrack
-- também olha o nome do arquivo/take. Itens gerados pelo kit não contam.
local function classe_click_guia(nome)
  nome = (tostring(nome or ""):match("([^\\/]+)$") or ""):gsub("%.[^%.]+$", "")
  if not nome:find("%w") then return nil end
  local c = M.classificar_stem(nome)
  if c == "CLICK" or c == "GUIA" then return c end
  return nil
end
M.classe_click_guia = classe_click_guia

-- multitrack = 2 ou mais áudios próprios na música (fora PAD, cifra e trilhas separadas pelo kit)
function M.eh_multitrack(m)
  if not m then return false end
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  local pad = banda and M.achar_filho(banda, M.CFG.NOME_PAD)
  local cif = M.achar_trilha(M.NOME_CIFRA)
  local n = 0
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if tr ~= pad and tr ~= cif then
      for _, it in ipairs(itens_no_intervalo(tr, m.inicio, m.fim)) do
        local tk = r.GetActiveTake(it)
        local _, stem = r.GetSetMediaItemInfo_String(it, "P_EXT:MT_STEM", "", false)
        if tk and stem ~= "1" and not tipo_gerado(it) and not r.TakeIsMIDI(tk) then
          n = n + 1
          if n >= 2 then return true end
        end
      end
    end
  end
  return false
end

function M.click_guia_da_musica(m)
  local achou = {}
  if not m then return achou end
  local fone = M.achar_fone()
  local tr_click = fone and M.achar_filho(fone, M.CFG.NOME_CLICK)
  local tr_guia = fone and M.achar_filho(fone, M.CFG.NOME_GUIA)
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  local pad = banda and M.achar_filho(banda, M.CFG.NOME_PAD)
  local cif = M.achar_trilha(M.NOME_CIFRA)
  local mt = nil
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if tr ~= pad and tr ~= cif and tr ~= fone then
      local _, nome_tr = r.GetTrackName(tr)
      local tipo_tr = (tr == tr_click and "CLICK") or (tr == tr_guia and "GUIA") or classe_click_guia(nome_tr)
      for _, it in ipairs(itens_no_intervalo(tr, m.inicio, m.fim)) do
        local tk = r.GetActiveTake(it)
        local _, stem = r.GetSetMediaItemInfo_String(it, "P_EXT:MT_STEM", "", false)
        if tk and stem ~= "1" and not tipo_gerado(it) and not r.TakeIsMIDI(tk) then
          local _, nome_tk = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
          local tipo = tipo_tr
          if not tipo then
            if mt == nil then mt = M.eh_multitrack(m) end
            if mt then
              local src = r.GetMediaItemTake_Source(tk)
              local arq = src and r.GetMediaSourceFileName(src, "") or ""
              tipo = classe_click_guia(nome_tk) or classe_click_guia(arq)
            end
          end
          if tipo and not achou[tipo] then
            achou[tipo] = { it = it, tr = tr, nome = (nome_tk ~= "" and nome_tk) or nome_tr }
          end
        end
      end
    end
  end
  return achou
end

local function trilha_fone(nome)
  local fone = M.achar_fone()
  if not fone then M.garantir_estrutura(); fone = M.achar_fone() end
  return fone and M.achar_filho(fone, nome)
end

function M.trilha_cifra(criar)
  local tr = M.achar_trilha(M.NOME_CIFRA)
  if tr or not criar then return tr end
  r.InsertTrackAtIndex(0, false)
  tr = r.GetTrack(0, 0)
  r.GetSetMediaTrackInfo_String(tr, "P_NAME", M.NOME_CIFRA, true)
  r.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", M.cor_nativa({ 90, 90, 115 }))
  r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
  r.SetMediaTrackInfo_Value(tr, "B_MUTE", 1)
  r.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", 28)
  return tr
end

local function musica_por_idx(idx)
  for _, m in ipairs(M.get_musicas()) do if m.idx == idx then return m end end
  return nil
end

-- áudio principal da música (o mais longo da BANDA, sem o PAD)
function M.item_principal(m)
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  if not banda then return nil end
  local pad = M.achar_filho(banda, M.CFG.NOME_PAD)
  local melhor, lmax = nil, 0
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if tr ~= pad and M.descende_de(tr, banda) then
      for _, it in ipairs(itens_no_intervalo(tr, m.inicio, m.fim)) do
        local tk = r.GetActiveTake(it)
        local l = r.GetMediaItemInfo_Value(it, "D_LENGTH")
        local _, stem = r.GetSetMediaItemInfo_String(it, "P_EXT:MT_STEM", "", false)
        if tk and stem ~= "1" and not r.TakeIsMIDI(tk) and l > lmax then melhor, lmax = it, l end
      end
    end
  end
  return melhor
end

-- v1.8: multitrack (VS aberto, vários stems na BANDA). A análise passa a ouvir a
-- MISTURA dos stems (antes ouvia só o item mais longo - às vezes a "cover"/referência
-- ou um stem sozinho - e as seções saíam todas "VERSO 1, VERSO 2..."). Também mede
-- quais instrumentos tocam em cada compasso (ajuda a achar verso/refrão/ponte).
-- Fica de fora: PAD, trilhas separadas pelo kit (MT_STEM), itens gerados, itens
-- mutados e arquivos de referência (cover, original, demo, mixdown...).
M.PALAVRAS_REFERENCIA = { "COVER", "REFERENCIA", "REFERENCE", "ORIGINAL", "DEMO", "MIXDOWN",
  "FULL MIX", "MIX FINAL", "MASTER MIX", "GUIA", "GUIDE", "CLICK", "CLIQUE", "CUE", "METRONOMO" }
function M.eh_referencia(nome)
  local n = " " .. M.norm(nome) .. " "
  for _, w in ipairs(M.PALAVRAS_REFERENCIA) do
    if n:find(" " .. w .. " ", 1, true) then return true end
  end
  return false
end

function M.fontes_analise_multitrack(m)
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  if not banda then return nil end
  local pad = M.achar_filho(banda, M.CFG.NOME_PAD)
  local lista = {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if tr ~= pad and M.descende_de(tr, banda) then
      for _, it in ipairs(itens_no_intervalo(tr, m.inicio, m.fim)) do
        local tk = r.GetActiveTake(it)
        local _, stem = r.GetSetMediaItemInfo_String(it, "P_EXT:MT_STEM", "", false)
        if tk and stem ~= "1" and not tipo_gerado(it) and not r.TakeIsMIDI(tk)
           and r.GetMediaItemInfo_Value(it, "B_MUTE") ~= 1
           and r.GetMediaItemInfo_Value(it, "D_LENGTH") > 5 then
          local _, nome_tk = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
          local src = r.GetMediaItemTake_Source(tk)
          local arq = src and r.GetMediaSourceFileName(src, "") or ""
          local _, nome_tr = r.GetTrackName(tr)
          lista[#lista + 1] = { it = it, tk = tk, src = src,
            ref = M.eh_referencia(nome_tk) or M.eh_referencia((arq:match("([^\\/]+)$") or arq):gsub("%.[^%.]+$", ""))
              or M.eh_referencia(nome_tr) }
        end
      end
    end
  end
  local stems = {}
  for _, f in ipairs(lista) do if not f.ref then stems[#stems + 1] = f end end
  if #stems < 2 then return nil end
  while #stems > 24 do table.remove(stems) end   -- limite de segurança (velocidade)
  return stems
end

-- v1.8: MUTE do MASTER. No REAPER, ler B_MUTE da trilha master nem sempre devolve
-- o estado real (vem 0 mesmo mutado), então o botão mutava de novo em vez de desmutar.
-- O estado certo do master vem de GetMasterMuteSoloFlags (bit 1 = mudo).
function M.master_mudo()
  if r.GetMasterMuteSoloFlags then
    local ok, f = pcall(r.GetMasterMuteSoloFlags)
    if ok and type(f) == "number" then return (f & 1) == 1 end
  end
  return r.GetMediaTrackInfo_Value(r.GetMasterTrack(0), "B_MUTE") == 1
end

function M.mutar_master(mudo)
  local master = r.GetMasterTrack(0)
  if mudo == nil then mudo = not M.master_mudo() end
  r.SetMediaTrackInfo_Value(master, "B_MUTE", mudo and 1 or 0)
  if M.master_mudo() ~= mudo then
    r.Main_OnCommand(14, 0)          -- Track: Toggle mute for master track
  end
  r.TrackList_AdjustWindows(false)
  return M.master_mudo()
end

-- ---------- tempo da música ----------
local function compasso_em(t)
  local num, den, bpm = r.TimeMap_GetTimeSigAtTime(0, t + 0.001)
  if not bpm or bpm <= 0 then bpm = r.TimeMap_GetDividedBpmAtTime(t + 0.001) end
  num = (num and num > 0) and num or 4
  den = (den and den > 0) and den or 4
  return bpm, num, den
end

local function apagar_tempos(ini, fim)
  for i = r.CountTempoTimeSigMarkers(0) - 1, 0, -1 do
    local _, tp = r.GetTempoTimeSigMarker(0, i)
    if tp >= ini - 0.001 and tp < fim - 0.001 then r.DeleteTempoTimeSigMarker(0, i) end
  end
end

-- v1.4: grava o mapa de tempo da música (lista {t, bpm, num, den}; num = 0 = sem
-- mudar o compasso) SEM mexer no resto do projeto: o que vem depois (músicas
-- seguintes, itens, marcadores, regiões e os tempos delas) volta exatamente para
-- onde estava, mesmo que o projeto use "timebase" em batidas.
local function escrever_mapa(m, marcas)
  local ini = m.inicio
  local itens, mks, depois = {}, {}, {}
  for i = 0, r.CountMediaItems(0) - 1 do
    local it = r.GetMediaItem(0, i)
    local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
    if p >= ini - 0.001 then itens[#itens + 1] = { it, p, r.GetMediaItemInfo_Value(it, "D_LENGTH") } end
  end
  local i = 0
  while true do
    local ret, isrgn, pos, fim, nome, idx, cor = r.EnumProjectMarkers3(0, i)
    if ret == 0 then break end
    if pos >= ini - 0.001 then mks[#mks + 1] = { idx, isrgn, pos, fim, nome, cor } end
    i = i + 1
  end
  for k = 0, r.CountTempoTimeSigMarkers(0) - 1 do
    local _, tp, _, _, bpm, num, den, lin = r.GetTempoTimeSigMarker(0, k)
    if tp >= m.fim - 0.001 then depois[#depois + 1] = { tp, bpm, num, den, lin } end
  end
  for k = r.CountTempoTimeSigMarkers(0) - 1, 0, -1 do
    local _, tp = r.GetTempoTimeSigMarker(0, k)
    if tp >= ini - 0.001 then r.DeleteTempoTimeSigMarker(0, k) end
  end
  for _, mk in ipairs(marcas) do
    if mk.t >= ini - 0.001 and mk.t < m.fim - 0.001 then
      r.SetTempoTimeSigMarker(0, -1, mk.t, -1, -1, mk.bpm, mk.num or 0, mk.den or 0, false)
    end
  end
  for _, d in ipairs(depois) do r.SetTempoTimeSigMarker(0, -1, d[1], -1, -1, d[2], d[3], d[4], d[5]) end
  for _, x in ipairs(itens) do
    if math.abs(r.GetMediaItemInfo_Value(x[1], "D_POSITION") - x[2]) > 0.0005 then r.SetMediaItemInfo_Value(x[1], "D_POSITION", x[2]) end
    if math.abs(r.GetMediaItemInfo_Value(x[1], "D_LENGTH") - x[3]) > 0.0005 then r.SetMediaItemInfo_Value(x[1], "D_LENGTH", x[3]) end
  end
  i = 0
  local atuais = {}
  while true do
    local ret, isrgn, pos, fim, _, idx = r.EnumProjectMarkers3(0, i)
    if ret == 0 then break end
    atuais[(isrgn and "R" or "M") .. idx] = { pos, fim }
    i = i + 1
  end
  for _, mk in ipairs(mks) do
    local a = atuais[(mk[2] and "R" or "M") .. mk[1]]
    if a and (math.abs(a[1] - mk[3]) > 0.0005 or (mk[2] and math.abs(a[2] - mk[4]) > 0.0005)) then
      r.SetProjectMarker3(0, mk[1], mk[2], mk[3], mk[4], mk[5], mk[6])
    end
  end
  r.UpdateTimeline()
end

-- Interpreta "4/4", "6/8", "3/4"... Devolve num, den.
function M.ler_compasso_txt(s, num0, den0)
  local n, d = tostring(s or ""):match("(%d+)%s*/%s*(%d+)")
  return tonumber(n) or num0 or 4, tonumber(d) or den0 or 4
end

-- Duração do compasso em semínimas (QN): 4/4=4, 3/4=3, 6/8=3, 12/8=6
function M.qn_por_compasso(num, den)
  num = num or 4; den = den or 4
  if den <= 0 then den = 4 end
  return num * 4 / den
end

-- Início do compasso que contém t (mapa de tempo real: 6/8, BPM fracionário, mudanças).
-- Devolve t0, meas, cml (QN no compasso), num, den
function M.inicio_do_compasso(t)
  t = t or 0
  if r.TimeMap2_timeToBeats and r.TimeMap2_beatsToTime then
    local beats, meas, cml = r.TimeMap2_timeToBeats(0, t)
    meas = math.floor((tonumber(meas) or 0) + 1e-9)
    local t0 = r.TimeMap2_beatsToTime(0, 0, meas)
    local bpm, num, den = compasso_em((t0 or t) + 1e-6)
    return t0 or t, meas, tonumber(cml) or M.qn_por_compasso(num, den), num, den
  end
  local bpm, num, den = compasso_em(t)
  return t, 0, M.qn_por_compasso(num, den), num, den
end

-- n compassos depois (n < 0: antes) de t, pelo mapa de tempo (qualquer compasso).
-- Se t está na barra, -1 = início do compasso anterior (aviso "1 compasso antes").
function M.deslocar_compassos(t, n)
  n = n or 0
  if r.TimeMap2_timeToBeats and r.TimeMap2_beatsToTime then
    local t0, meas = M.inicio_do_compasso(t)
    if math.abs(t - t0) >= 0.002 then
      -- t cai no meio do compasso: n=-1 vai para o início deste; n=-2 para o anterior
      if n < 0 then n = n + 1 end
    end
    local x = r.TimeMap2_beatsToTime(0, 0, meas + n)
    if x then return x end
  end
  local bpm, num, den = compasso_em(t)
  return t + n * M.qn_por_compasso(num, den) * 60 / bpm
end

-- j-ésimo pulso (1..ncount) igualmente espaçado no compasso que começa em t_comp
function M.pulso_no_compasso(t_comp, j, ncount)
  ncount = math.max(1, ncount or 4)
  j = j or 1
  if r.TimeMap2_beatsToTime then
    local t0, meas, cml = M.inicio_do_compasso((t_comp or 0) + 1e-7)
    if cml and cml > 0 then
      local x = r.TimeMap2_beatsToTime(0, (j - 1) * cml / ncount, meas)
      if x then return x end
    end
  end
  local t1 = M.deslocar_compassos(t_comp, 1)
  return (t_comp or 0) + (j - 1) * ((t1 or (t_comp + 1)) - (t_comp or 0)) / ncount
end

-- n semínimas (QN) depois (n < 0: antes) de t, seguindo o mapa (4/4, 6/8, BPM variável)
function M.deslocar_batidas(t, n)
  if r.TimeMap2_timeToBeats and r.TimeMap2_beatsToTime then
    local _, _, _, cheias = r.TimeMap2_timeToBeats(0, t)
    if cheias then
      local x = r.TimeMap2_beatsToTime(0, cheias + n)
      if x then return x end
    end
  end
  local bpm = compasso_em(t)
  if n < 0 then bpm = compasso_em(t + n * 60 / bpm - 0.001) end
  return t + n * 60 / bpm
end
local function deslocar_batidas(t, n) return M.deslocar_batidas(t, n) end

-- ---------- CLICK: um arquivo de 8 compassos gerado aqui mesmo, em loop ----------
local function pacote_click(freq, amp, sr)
  local n = math.floor(0.045 * sr)
  local t = {}
  for i = 0, n - 1 do
    local x = i / sr
    local env = math.exp(-x * 95) * math.min(1, i / 12)
    local v = amp * env * (math.sin(2 * math.pi * freq * x) * 0.8 + math.sin(2 * math.pi * freq * 2.01 * x) * 0.2)
    local q = math.floor(v * 32767 + 0.5)
    if q > 32767 then q = 32767 elseif q < -32768 then q = -32768 end
    t[#t + 1] = string.pack("<i2", q)
  end
  return table.concat(t), n
end

function M.arquivo_click(bpm, bpb, den)
  den = den or 4
  local pasta = M.DIR .. "click_gerado"
  r.RecursiveCreateDirectory(pasta, 0)
  local nome = string.format("click_%s_%s_%s.wav", (string.format("%.3f", bpm):gsub("%.", "_")), tostring(inteiro(bpb, 4)), tostring(inteiro(den, 4)))
  local caminho = pasta .. SEP .. nome
  if r.file_exists(caminho) then return caminho end
  local sr = 44100
  local barras = 8
  -- pulso na unidade do denominador (em 6/8: colcheia = 60/bpm * 4/8)
  local beat = (60 / bpm) * (4 / den)
  local total = math.floor(barras * bpb * beat * sr + 0.5)
  local acento, na = pacote_click(1760, 0.85, sr)
  local normal, nn = pacote_click(1175, 0.55, sr)
  local f = io.open(caminho, "wb")
  if not f then return nil end
  f:write("RIFF", string.pack("<I4", 36 + total * 2), "WAVE", "fmt ",
    string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, sr, sr * 2, 2, 16), "data", string.pack("<I4", total * 2))
  local escrito = 0
  for j = 0, barras * bpb - 1 do
    local p = math.floor(j * beat * sr + 0.5)
    if p > escrito then f:write(string.rep("\0\0", p - escrito)); escrito = p end
    local pac, n = normal, nn
    if j % bpb == 0 then pac, n = acento, na end
    if escrito + n > total then n = total - escrito; pac = pac:sub(1, n * 2) end
    f:write(pac); escrito = escrito + n
  end
  if total > escrito then f:write(string.rep("\0\0", total - escrito)) end
  f:close()
  return caminho
end

-- Gera o click da música de 'ini' (1º compasso) até 'fim'
function M.gerar_click(m, ini, fim, bpm, bpb, den)
  local tr = trilha_fone(M.CFG.NOME_CLICK)
  if not tr then return false, "trilha CLICK não encontrada" end
  apagar_gerados(tr, m.inicio, math.max(m.fim, fim), "CLICK")
  if M.click_guia_da_musica(m).CLICK then return false, "a música já tem click" end
  den = den or 4
  local arq = M.arquivo_click(bpm, bpb, den)
  if not arq then return false, "não consegui gravar o arquivo de click" end
  local B = M.qn_por_compasso(bpb, den) * 60 / bpm
  local nbar = math.ceil((fim - ini) / B - 0.01)
  local it = r.AddMediaItemToTrack(tr)
  r.SetMediaItemInfo_Value(it, "D_POSITION", ini)
  r.SetMediaItemInfo_Value(it, "D_LENGTH", nbar * B)
  r.SetMediaItemInfo_Value(it, "B_LOOPSRC", 1)
  r.SetMediaItemInfo_Value(it, "C_BEATATTACHMODE", 0)
  local tk = r.AddTakeToMediaItem(it)
  r.SetMediaItemTake_Source(tk, r.PCM_Source_CreateFromFile(arq))
  r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", string.format("CLICK %g BPM (gerado)", bpm), true)
  marcar_gerado(it, "CLICK")
  r.UpdateItemInProject(it)
  return true, ini + nbar * B
end

-- v1.4: CLICK que ACOMPANHA o andamento (música ao vivo / sem click): um arquivo
-- com cada batida no lugar exato. batidas = { {t = tempo no projeto, forte = bool}, ... }
function M.arquivo_click_batidas(batidas, chave)
  local pasta = M.DIR .. "click_gerado"
  r.RecursiveCreateDirectory(pasta, 0)
  local h = 5381
  for _, b in ipairs(batidas) do
    local q = math.floor((b.t - batidas[1].t) * 10000 + 0.5) + (b.forte and 7 or 0)
    h = (h * 33 + q) % 4294967291
  end
  for c in tostring(chave or ""):gmatch(".") do h = (h * 33 + c:byte()) % 4294967291 end
  local caminho = pasta .. SEP .. string.format("click_var_%08x.wav", h)
  if r.file_exists(caminho) then return caminho end
  local sr = 22050
  local acento, na = pacote_click(1760, 0.85, sr)
  local normal, nn = pacote_click(1175, 0.55, sr)
  local t0 = batidas[1].t
  local total = math.floor((batidas[#batidas].t - t0) * sr + 0.5) + na + 1
  local f = io.open(caminho, "wb")
  if not f then return nil end
  f:write("RIFF", string.pack("<I4", 36 + total * 2), "WAVE", "fmt ",
    string.pack("<I4I2I2I4I4I2I2", 16, 1, 1, sr, sr * 2, 2, 16), "data", string.pack("<I4", total * 2))
  local escrito = 0
  for _, b in ipairs(batidas) do
    local p = math.floor((b.t - t0) * sr + 0.5)
    if p > escrito then f:write(string.rep("\0\0", p - escrito)); escrito = p end
    if p >= escrito then
      local pac, n = normal, nn
      if b.forte then pac, n = acento, na end
      if escrito + n > total then n = total - escrito; pac = pac:sub(1, n * 2) end
      f:write(pac); escrito = escrito + n
    end
  end
  if total > escrito then f:write(string.rep("\0\0", total - escrito)) end
  f:close()
  return caminho
end

-- Mapa de tempo + CLICK a partir das batidas reais (tempos no projeto; bat[1] = 1º
-- tempo do 1º compasso com música). Devolve: ok, info, T (1ª barra da grade), B0
function M.aplicar_batidas(m, bat, bpb, fim_click, aprox, den)
  bpb = bpb or 4
  den = den or 4
  if den <= 0 then den = 4 end
  local num = bpb
  if not bat or #bat < 4 then return false, "batidas insuficientes" end
  local iv = {}
  for k = 2, math.min(#bat, 5) do iv[#iv + 1] = bat[k] - bat[k - 1] end
  table.sort(iv)
  local p0 = iv[math.floor((#iv + 1) / 2)]
  -- Se o pulso detectado é a unidade do denominador (ex.: colcheias em 6/8 com bpb=6),
  -- o BPM do REAPER (semínimas por minuto) é 60 / (intervalo * den/4).
  local function bpm_qn(intervalo)
    if intervalo <= 0 then return 120 end
    if den >= 8 and num == bpb then return 60 / (intervalo * den / 4) end
    return 60 / intervalo
  end
  local B0 = bpb * p0
  local D = bat[1]
  local T = math.max(m.inicio, D - B0 * math.floor((D - m.inicio) / B0 + 0.01))
  -- mapa de tempo: grade fixa até a 1ª batida, depois 1 marcador por batida (num/den reais)
  local marcas = {}
  if T < D - 0.001 then marcas[#marcas + 1] = { t = T, bpm = bpm_qn(p0), num = num, den = den } end
  local ultimo = #bat
  while ultimo > 2 and bat[ultimo - 1] > fim_click do ultimo = ultimo - 1 end
  for k = 1, ultimo - 1 do
    local mk = { t = bat[k], bpm = bpm_qn(bat[k + 1] - bat[k]) }
    if k == 1 and T >= D - 0.001 then mk.num, mk.den = num, den end
    marcas[#marcas + 1] = mk
  end
  escrever_mapa(m, marcas)
  -- batidas do click: 1 compasso de contagem + as batidas reais (+ continua no fim)
  local cl = {}
  for j = bpb, 1, -1 do
    local t = D - j * p0
    if t >= math.max(m.inicio, T) - 0.0005 then cl[#cl + 1] = { t = t, forte = (j == bpb) } end
  end
  local k = 1
  local t = D
  local per = p0
  while t < fim_click - 0.001 do
    cl[#cl + 1] = { t = t, forte = ((k - 1) % bpb == 0) }
    if bat[k + 1] then per = bat[k + 1] - bat[k]; t = bat[k + 1] else t = t + per end
    k = k + 1
  end
  if #cl < 2 then return false, "música curta demais para o click", T, B0 end
  local tr = trilha_fone(M.CFG.NOME_CLICK)
  if not tr then return false, "trilha CLICK não encontrada", T, B0 end
  local clicks_antigos = M.arquivos_fonte_gerados(tr, m.inicio, m.fim, "CLICK")
  apagar_gerados(tr, m.inicio, m.fim, "CLICK")
  if M.click_guia_da_musica(m).CLICK then return false, "a música já tem click", T, B0 end
  local arq = M.arquivo_click_batidas(cl, m.nome)
  if not arq then return false, "não consegui gravar o arquivo de click", T, B0 end
  M.soltar_clicks_antigos(clicks_antigos, arq)
  local src = r.PCM_Source_CreateFromFile(arq)
  local it = r.AddMediaItemToTrack(tr)
  r.SetMediaItemInfo_Value(it, "D_POSITION", cl[1].t)
  r.SetMediaItemInfo_Value(it, "D_LENGTH", (cl[#cl].t - cl[1].t) + 0.1)
  r.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
  r.SetMediaItemInfo_Value(it, "C_BEATATTACHMODE", 0)
  local tk = r.AddTakeToMediaItem(it)
  r.SetMediaItemTake_Source(tk, src)
  local media = 60 * (#cl - 1) / (cl[#cl].t - cl[1].t)
  r.GetSetMediaItemTakeInfo_String(tk, "P_NAME",
    string.format("CLICK ~%d BPM (acompanha o andamento%s)", math.floor(media + 0.5), aprox and ", aproximado" or ""), true)
  marcar_gerado(it, "CLICK")
  r.UpdateItemInProject(it)
  return true, #cl, T, B0
end

-- v1.4: aviso discreto no painel quando o click é aproximado
function M.click_aproximado(m)
  if not m then return false end
  local _, v = r.GetProjExtState(0, "MT_CLICK_APROX", M.norm(m.nome))
  return v == "1"
end
local function marcar_aproximado(m, sim)
  r.SetProjExtState(0, "MT_CLICK_APROX", M.norm(m.nome), sim and "1" or "")
end

-- VS fechado com click num lado: o mesmo áudio vai pro CLICK (só aquele lado)
-- e o item da banda passa a tocar só o outro lado
function M.separar_click_vs(m, it, lado)
  local tr = trilha_fone(M.CFG.NOME_CLICK)
  if not tr or not it then return false end
  apagar_gerados(tr, m.inicio, m.fim, "CLICK_VS")
  local tk = r.GetActiveTake(it)
  local src = r.GetMediaItemTake_Source(tk)
  local arq = r.GetMediaSourceFileName(src, "")
  local novo = r.AddMediaItemToTrack(tr)
  r.SetMediaItemInfo_Value(novo, "D_POSITION", r.GetMediaItemInfo_Value(it, "D_POSITION"))
  r.SetMediaItemInfo_Value(novo, "D_LENGTH", r.GetMediaItemInfo_Value(it, "D_LENGTH"))
  r.SetMediaItemInfo_Value(novo, "C_BEATATTACHMODE", 0)
  local tk2 = r.AddTakeToMediaItem(novo)
  r.SetMediaItemTake_Source(tk2, r.PCM_Source_CreateFromFile(arq))
  r.SetMediaItemTakeInfo_Value(tk2, "D_STARTOFFS", r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS"))
  r.SetMediaItemTakeInfo_Value(tk2, "I_CHANMODE", lado == "L" and 3 or 4)   -- 3 = só esquerdo, 4 = só direito
  r.SetMediaItemTakeInfo_Value(tk, "I_CHANMODE", lado == "L" and 4 or 3)
  r.GetSetMediaItemTakeInfo_String(tk2, "P_NAME", "CLICK do VS (lado " .. lado .. ")", true)
  r.GetSetMediaItemInfo_String(it, "P_EXT:MT_CANAL", lado, true)
  marcar_gerado(novo, "CLICK_VS")
  r.UpdateItemInProject(novo)
  return true
end

local function desfazer_click_vs(m, it)
  local tr = trilha_fone(M.CFG.NOME_CLICK)
  if tr then apagar_gerados(tr, m.inicio, m.fim, "CLICK_VS") end
  if it then
    local _, lado = r.GetSetMediaItemInfo_String(it, "P_EXT:MT_CANAL", "", false)
    if lado ~= "" then
      r.SetMediaItemTakeInfo_Value(r.GetActiveTake(it), "I_CHANMODE", 0)
      r.GetSetMediaItemInfo_String(it, "P_EXT:MT_CANAL", "", true)
    end
  end
end

-- ---------- GUIA falada ----------
-- so_se_gerada = só refaz se a guia desta música já foi gerada pelo kit
-- Regra da contagem falada, pela fórmula do compasso naquele trecho.
--   Simples (2/4, 3/4, 4/4, e outros com den 2 ou 4): conta o numerador em semínimas.
--   Compostos (6/8, 9/8, 12/8): conta o pulso pontuado (6/8 = "um, dois").
--     Se a semínima pontuada estiver lenta (BPM pontuado < 60, ou seja, cada pulso
--     dura mais de 1 s), conta em colcheias (6/8 = um..seis) — fica mais natural.
--   Irregulares (5/8, 7/8, ...): conta em colcheias (o numerador).
function M.regra_contagem(num, den, bpm)
  num = math.floor((tonumber(num) or 4) + 0.5)
  den = math.floor((tonumber(den) or 4) + 0.5)
  if num < 1 then num = 4 end
  if den <= 0 then den = 4 end
  bpm = tonumber(bpm) or 120
  local tipo, ncount, pulso
  if den >= 8 and (num % 3 == 0) then
    local bpm_pont = bpm * 2 / 3  -- BPM da semínima pontuada (1,5 semínima)
    if bpm_pont < 60 then
      tipo, ncount, pulso = "composto-lento", num, "colcheia"
    else
      tipo, ncount, pulso = "composto", math.floor(num / 3 + 0.5), "pontuado"
    end
  elseif den >= 8 then
    tipo, ncount, pulso = "irregular", num, "colcheia"
  else
    tipo, ncount, pulso = "simples", num, "seminima"
  end
  ncount = math.min(math.max(1, ncount or 4), #M.VOZ_CONTAGEM)
  return ncount, tipo, pulso
end

-- Plano da guia: lista { t, chave, rotulo, arq, src_len, playrate, len, limite, tipo }
-- tipo = "contagem" | "secao". Não escreve no projeto.
function M.plano_guia(m)
  if not m then return nil, "sem musica" end
  if M.click_guia_da_musica(m).GUIA then return nil, "a música já tem guia" end
  local secs = M.secoes_da_musica(m)
  local contar_antes = nil
  if M.eh_multitrack(m) then
    local tem_contagem, primeira = false, nil
    for _, s in ipairs(secs) do
      if not s.virtual then
        primeira = primeira or s
        if M.voz_da_secao(s.nome) == "contagem" then tem_contagem = true end
      end
    end
    if primeira and not tem_contagem then contar_antes = primeira end
  end
  local plano = {}
  local function acrescentar(chave, t, rotulo, limite, tipo)
    if not chave or t < m.inicio - 0.001 then return end
    local arq = M.arquivo_voz(chave)
    if not arq then return end
    local src_len = 0.4
    if r.PCM_Source_CreateFromFile then
      local src = r.PCM_Source_CreateFromFile(arq)
      if src then
        local len, isqn = r.GetMediaSourceLength(src)
        src_len = tonumber(len) or src_len
        if isqn and r.TimeMap2_timeToBeats and r.TimeMap2_beatsToTime then
          local _, _, _, q0 = r.TimeMap2_timeToBeats(0, t)
          local t1 = r.TimeMap2_beatsToTime(0, (q0 or 0) + src_len)
          src_len = (t1 or t) - t
        end
      end
    end
    if src_len <= 0 then src_len = 0.01 end
    local playrate, len = 1, src_len
    -- só a CONTAGEM é encurtada (cabe no pulso). Fala de seção toca inteira,
    -- mesmo passando do compasso (pode sobrepor o próximo item, sem cortar).
    if (tipo or "secao") == "contagem" and limite and limite > t + 0.05 and src_len > (limite - t) + 0.005 then
      -- sample maior que o pulso/compasso: acelera preservando o pitch (B_PPITCH)
      playrate = src_len / (limite - t)
      len = limite - t
    end
    plano[#plano + 1] = {
      t = math.max(m.inicio, t), chave = chave, rotulo = rotulo, arq = arq,
      src_len = src_len, playrate = playrate, len = len, limite = limite, tipo = tipo or "secao",
    }
  end
  local function contar_no_compasso(t0)
    local bpm_c, num_c, den_c = compasso_em(t0 + 1e-6)
    local ncount = M.regra_contagem(num_c, den_c, bpm_c)
    local t_fim = M.deslocar_compassos(t0, 1)
    for j = 1, ncount do
      local tj = M.pulso_no_compasso(t0, j, ncount)
      local prox = (j < ncount) and M.pulso_no_compasso(t0, j + 1, ncount) or t_fim
      acrescentar(M.VOZ_CONTAGEM[j], tj, tostring(j), prox, "contagem")
    end
  end
  local anterior_contagem = false
  for _, s in ipairs(secs) do
    if not s.virtual then
      local chave = M.voz_da_secao(s.nome)
      if s == contar_antes then
        local t1 = M.deslocar_compassos(s.inicio, -1)
        if t1 >= m.inicio - 0.01 then
          contar_no_compasso(t1)
          anterior_contagem = true
        end
      end
      if chave == "contagem" then
        contar_no_compasso(s.inicio)
        anterior_contagem = true
      else
        if chave and not anterior_contagem then
          local t_aviso = M.deslocar_compassos(s.inicio, -1)
          acrescentar(chave, t_aviso, s.nome, s.inicio, "secao")
        end
        anterior_contagem = false
      end
    end
  end
  return plano
end

local function aplicar_plano_guia(tr, plano)
  local n = 0
  for _, p in ipairs(plano or {}) do
    local src = r.PCM_Source_CreateFromFile(p.arq)
    if src then
      local it = r.AddMediaItemToTrack(tr)
      local tk = r.AddTakeToMediaItem(it)
      r.SetMediaItemTake_Source(tk, src)
      if r.SetMediaItemTakeInfo_Value then
        r.SetMediaItemTakeInfo_Value(tk, "D_PLAYRATE", p.playrate or 1)
        r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", 0)
        pcall(r.SetMediaItemTakeInfo_Value, tk, "B_PPITCH", ((p.playrate or 1) > 1.001) and 1 or 0)
      end
      r.SetMediaItemInfo_Value(it, "D_POSITION", p.t)
      r.SetMediaItemInfo_Value(it, "D_LENGTH", p.len)
      r.SetMediaItemInfo_Value(it, "C_BEATATTACHMODE", 0)
      r.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
      r.SetMediaItemInfo_Value(it, "D_FADEINLEN", 0)
      r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", 0)
      pcall(r.SetMediaItemInfo_Value, it, "D_FADEINLEN_AUTO", 0)
      pcall(r.SetMediaItemInfo_Value, it, "D_FADEOUTLEN_AUTO", 0)
      r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "GUIA: " .. p.rotulo, true)
      marcar_gerado(it, "GUIA")
      r.UpdateItemInProject(it)
      n = n + 1
    end
  end
  return n
end

function M.gerar_guia(m, so_se_gerada)
  local tr = trilha_fone(M.CFG.NOME_GUIA)
  if not tr then return false, "trilha GUIA não encontrada" end
  if so_se_gerada and not tem_gerado(tr, m.inicio, m.fim, "GUIA") then return false end
  if M.click_guia_da_musica(m).GUIA then
    apagar_gerados(tr, m.inicio, m.fim, "GUIA")
    return false, "a música já tem guia"
  end
  local plano, err = M.plano_guia(m)
  if not plano then return false, err end
  apagar_gerados(tr, m.inicio, m.fim, "GUIA")
  local n = aplicar_plano_guia(tr, plano)
  return true, n
end

local function itens_guia_gerados(m)
  local tr = trilha_fone(M.CFG.NOME_GUIA)
  local L = {}
  if not tr or not m then return L end
  for _, it in ipairs(itens_no_intervalo(tr, m.inicio, m.fim)) do
    if tipo_gerado(it) == "GUIA" then
      local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      local tk = r.GetActiveTake(it)
      local nome, src_len, src, rate = "", 0, "", 1
      if tk then
        local _, nm = r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
        nome = nm or ""
        if r.GetMediaItemTakeInfo_Value then
          rate = tonumber(r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")) or 1
        end
        local s = r.GetMediaItemTake_Source(tk)
        if s then
          src_len = tonumber((r.GetMediaSourceLength(s))) or 0
          if r.GetMediaSourceFileName then src = r.GetMediaSourceFileName(s) or "" end
        end
      end
      L[#L + 1] = { t = pos, len = len, nome = nome, src_len = src_len, src = src, playrate = rate, it = it }
    end
  end
  table.sort(L, function(a, b) return a.t < b.t end)
  return L
end

-- Compara a guia atual com o plano (mapa de tempo real). Devolve nil se está ok, ou o motivo.
function M.guia_desatualizada(m)
  if not m then return nil end
  if M.click_guia_da_musica(m).GUIA then return nil end  -- guia que veio na multitrack: não mexe
  local atuais = itens_guia_gerados(m)
  if #atuais == 0 then return nil end  -- não inventa guia onde nunca houve
  local plano, err = M.plano_guia(m)
  if not plano then return nil end
  if #plano == 0 then return nil end
  if #atuais ~= #plano then
    return "quantidade " .. tostring(#atuais) .. " ~= " .. tostring(#plano)
  end
  for i, p in ipairs(plano) do
    local a = atuais[i]
    if math.abs(a.t - p.t) > 0.02 then
      return "posicao " .. tostring(p.rotulo)
    end
    if math.abs(a.len - p.len) > 0.03 then
      return "comprimento " .. tostring(p.rotulo)
    end
    if math.abs((a.playrate or 1) - (p.playrate or 1)) > 0.05 then
      return "playrate " .. tostring(p.rotulo)
    end
    local ka = M.chave_guia((a.src or ""):match("([^\\/]+)%.[^%.]+$") or a.src or "")
    local kp = M.chave_guia((p.arq or ""):match("([^\\/]+)%.[^%.]+$") or p.chave or "")
    if kp ~= "" and ka ~= "" and ka ~= kp then
      -- genérico no lugar do específico (REFRAO vs REFRAO1) é erro
      local raizp = kp:match("^(.-)%d+$")
      if raizp and ka == raizp then return "sample genérico " .. tostring(p.rotulo) end
      if ka ~= raizp then return "sample " .. tostring(p.rotulo) end
    end
  end
  return nil
end

local function copiar_arquivo(src, dst)
  local i = io.open(src, "rb")
  if not i then return false end
  local dados = i:read("*a"); i:close()
  if not dados then return false end
  local o = io.open(dst, "wb")
  if not o then return false end
  o:write(dados); o:close()
  return true
end

function M.arquivo_projeto()
  if not r.EnumProjects then return "" end
  local a, b = r.EnumProjects(-1)
  if type(b) == "string" and b ~= "" then return b end
  if type(a) == "string" and a:match("%.[Rr][Pp][Pp]$") then return a end
  return ""
end

local function reaper_parado()
  return (r.GetPlayState() or 0) == 0
end

-- Pausado (2) também vale para regenerar a guia: o Mik costuma "parar"
-- com pause, e GetPlayState()==0 só acontece no stop completo.
-- Nunca altera durante play (1) ou gravação (4). Gravar o .RPP continua
-- só no stop completo (reaper_parado).
local function reaper_pode_alterar_guia()
  local st = r.GetPlayState() or 0
  return st == 0 or st == 2
end

-- Grava o .RPP só se: parado, sem alterações do usuário pendentes (estava limpo
-- antes da correção) e o arquivo do projeto está na Biblioteca (Documentos\Multitracks).
-- Sempre faz backup .bak-guia-auto-AAAAMMDD antes. Sem diálogo.
local function talvez_gravar_rpp_biblioteca(dirty_antes)
  if dirty_antes and dirty_antes ~= 0 then return "memoria (alterações do usuário não salvas)" end
  if not reaper_parado() then return "memoria (não está parado)" end
  local fn = M.arquivo_projeto()
  if fn == "" then return "memoria (projeto sem arquivo)" end
  if not M.na_biblioteca(fn) then return "memoria (RPP fora da biblioteca)" end
  local bak = fn:gsub("%.[Rr][Pp][Pp]$", "") .. ".bak-guia-auto-" .. os.date("%Y%m%d")
  if not copiar_arquivo(fn, bak) then bak = "(backup falhou)" end
  local ok = true
  if r.Main_SaveProject then
    -- forceSaveAs=false: grava no caminho atual, sem janela
    pcall(function() r.Main_SaveProject(0, false) end)
  elseif r.Main_SaveProjectEx then
    ok = r.Main_SaveProjectEx(0, fn, 0)
  end
  return "rpp " .. fn .. " backup=" .. bak
end

local estado_guia = { chave = nil, pendente = false, t = 0 }

local function chave_setlist_guia()
  local proj = tostring((r.EnumProjects and r.EnumProjects(-1)) or "")
  local fn = M.arquivo_projeto()
  local partes = { proj, fn }
  local mus = M.get_musicas and M.get_musicas() or {}
  for _, m in ipairs(mus) do
    partes[#partes + 1] = tostring(m.nome) .. "@" .. string.format("%.3f", m.inicio) .. "-" .. string.format("%.3f", m.fim)
  end
  local atual = M.musica_atual()
  partes[#partes + 1] = "cur=" .. (atual and tostring(atual.n or atual.nome) or "")
  -- mudanças de andamento/compasso no projeto
  if r.CountTempoTimeSigMarkers then
    local n = r.CountTempoTimeSigMarkers(0) or 0
    partes[#partes + 1] = "mk=" .. tostring(math.floor(n + 0.5))
    if n > 0 and r.GetTempoTimeSigMarker then
      local ultimo = math.floor(n - 0.5)
      local ok, tpos, _, _, bpm, num, den = r.GetTempoTimeSigMarker(0, math.max(0, ultimo))
      partes[#partes + 1] = string.format("%.3f:%s:%s/%s", tonumber(tpos) or 0, tostring(bpm), tostring(num), tostring(den))
    end
  end
  return table.concat(partes, "|")
end

-- Chamado pelo motor (e pelo painel, se o motor não estiver ligado).
-- Nunca durante o play/gravação: espera parar. Sem diálogo, sem tooltip.
-- Só suja o projeto se realmente regenerar. Verificação sozinha não grava nada.
function M.verificar_guia_auto(forcar)
  local agora = r.time_precise and r.time_precise() or 0
  if not forcar and agora - (estado_guia.t or 0) < 0.4 then return end
  estado_guia.t = agora
  if not reaper_pode_alterar_guia() then
    estado_guia.pendente = true
    return
  end
  local chave = chave_setlist_guia()
  if not forcar and not estado_guia.pendente and chave == estado_guia.chave then return end
  estado_guia.pendente = false
  local mus = M.get_musicas and M.get_musicas() or {}
  if #mus == 0 then estado_guia.chave = chave; return end
  local dirty_antes = 0
  if r.IsProjectDirty then dirty_antes = r.IsProjectDirty(0) or 0 end
  local corrigiu = false
  for _, m in ipairs(mus) do
    -- v1.8: o click segue a fórmula de compasso de cada trecho (mapa de tempo)
    local okc, errc = pcall(M.corrigir_click_compasso, m)
    if not okc then pcall(M.registrar_erro, "click-compasso", errc) end
    local motivo = M.guia_desatualizada(m)
    if motivo then
      local ok, n = M.gerar_guia(m)
      if ok then corrigiu = true end
    end
  end
  if corrigiu then
    talvez_gravar_rpp_biblioteca(dirty_antes)
  end
  estado_guia.chave = chave_setlist_guia()
end


-- ---------- CIFRA ----------
local NOTA_PC = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
local NOMES_BR = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }
local function transpor_nota(n, semi)
  local l, ac = n:match("^([A-G])([#b]?)$")
  if not l then return n end
  local pc = NOTA_PC[l] + (ac == "#" and 1 or (ac == "b" and -1 or 0))
  return NOMES_BR[((pc + semi) % 12) + 1]
end
function M.transpor_acorde(nome, semi)
  if not semi or semi == 0 or not nome then return nome end
  local raiz, resto = nome:match("^([A-G][#b]?)(.*)$")
  if not raiz then return nome end
  local qual, baixo = resto:match("^(.-)/([A-G][#b]?)$")
  if baixo then return transpor_nota(raiz, semi) .. qual .. "/" .. transpor_nota(baixo, semi) end
  return transpor_nota(raiz, semi) .. resto
end

-- lista = { {t = tempo no projeto, nome = "G"} ... }
function M.gerar_cifra_itens(m, lista, fim)
  local tr = M.trilha_cifra(true)
  apagar_gerados(tr, m.inicio, math.max(m.fim, fim or 0), "CIFRA")
  fim = fim or m.fim
  local n = 0
  for i, c in ipairs(lista) do
    local t1 = (lista[i + 1] and lista[i + 1].t) or fim
    if t1 > c.t + 0.01 and c.t >= m.inicio - 0.01 then
      local it = r.AddMediaItemToTrack(tr)
      r.SetMediaItemInfo_Value(it, "D_POSITION", c.t)
      r.SetMediaItemInfo_Value(it, "D_LENGTH", t1 - c.t)
      r.GetSetMediaItemInfo_String(it, "P_NOTES", c.nome, true)
      marcar_gerado(it, "CIFRA")
      n = n + 1
    end
  end
  return n
end

-- acordes da música (para o painel), com cache
local cache_cifra = { chave = nil, lista = {} }
function M.acordes_da_musica(m)
  local tr = M.achar_trilha(M.NOME_CIFRA)
  if not tr or not m then return {} end
  local chave = table.concat({ r.GetProjectStateChangeCount(0), m.inicio, m.fim }, ":")
  if cache_cifra.chave == chave then return cache_cifra.lista end
  local l = {}
  for _, it in ipairs(itens_no_intervalo(tr, m.inicio, m.fim)) do
    local _, txt = r.GetSetMediaItemInfo_String(it, "P_NOTES", "", false)
    txt = trim(txt or "")
    if txt ~= "" then l[#l + 1] = { t = r.GetMediaItemInfo_Value(it, "D_POSITION"), nome = txt } end
  end
  table.sort(l, function(a, b) return a.t < b.t end)
  cache_cifra.chave, cache_cifra.lista = chave, l
  return l
end

-- acorde atual e o próximo (já no tom que está soando)
function M.acorde_em(pos, m)
  local l = M.acordes_da_musica(m)
  if #l == 0 then return nil end
  local atual, prox = nil, nil
  for i, c in ipairs(l) do
    if c.t <= pos + 0.03 then atual = c; prox = l[i + 1] else break end
  end
  if not atual then prox = l[1] end
  local semi = M.get_transp(m)
  return atual and M.transpor_acorde(atual.nome, semi), prox and M.transpor_acorde(prox.nome, semi), prox and prox.t
end

function M.ler_cifra(caminho)
  local f = io.open(caminho, "r")
  if not f then return nil end
  local l = {}
  for linha in f:lines() do
    linha = trim(linha:gsub("^\239\187\191", ""))
    if linha ~= "" and not linha:match("^#") then
      local a, b = linha:match("^(%S+)%s+(%S+)")
      local t = a and ler_tempo(a)
      if t and b then l[#l + 1] = { t = t, nome = b } end
    end
  end
  f:close()
  table.sort(l, function(a, b) return a.t < b.t end)
  return #l > 0 and l or nil
end

local function gravar_cifra(pasta, m, lista, bpm, bpb, den)
  if not pasta or pasta == "" then return nil end
  den = den or 4
  local caminho = pasta .. SEP .. M.ARQ_CIFRA
  local f = io.open(caminho, "w")
  if not f then return nil end
  f:write("# Cifra de: " .. m.nome .. (m.tom and (" [" .. m.tom .. "]") or "") .. "   (gerada pelo Mik Seifador - pode corrigir)\n")
  f:write(string.format("# BPM %g   compasso %s/%s\n", bpm, tostring(inteiro(bpb, 4)), tostring(inteiro(den, 4))))
  f:write("# tempo (relativo ao início da música)   acorde\n")
  for _, c in ipairs(lista) do f:write(fmt_tempo(c.t - m.inicio), "\t", c.nome, "\n") end
  -- versão "para tocar": uma linha por seção, um | por compasso
  local secs = M.secoes_da_musica(m)
  local B = M.qn_por_compasso(bpb, den) * 60 / bpm
  f:write("\n# ---- por seção (| = compasso) ----\n")
  for _, s in ipairs(secs) do
    local nb = math.max(1, math.floor((s.fim - s.inicio) / B + 0.5))
    local partes = {}
    for b = 0, nb - 1 do
      local t0, t1 = s.inicio + b * B, s.inicio + (b + 1) * B
      local nomes, ultimo = {}, nil
      for _, c in ipairs(lista) do
        if c.t <= t0 + 0.05 then ultimo = c.nome end
      end
      if ultimo then nomes[1] = ultimo end
      for _, c in ipairs(lista) do
        if c.t > t0 + 0.05 and c.t < t1 - 0.05 and c.nome ~= nomes[#nomes] then nomes[#nomes + 1] = c.nome end
      end
      partes[#partes + 1] = (#nomes > 0) and table.concat(nomes, " ") or "-"
    end
    f:write("# ", s.nome, ":  | ", table.concat(partes, " | "), " |\n")
  end
  f:close()
  return caminho
end

-- ---------- ficha (mt_info.txt) com mescla ----------
function M.atualizar_info(pasta, novos)
  if not pasta or pasta == "" then return false end
  local t = M.ler_info(pasta) or {}
  for k, v in pairs(novos) do t[k] = v end
  return M.gravar_info(pasta, t)
end

-- v1.4: batidas (andamento variável) salvas na ficha, relativas ao início do áudio
function M.batidas_texto(bat, P, ate)
  local l = {}
  for k, t in ipairs(bat) do
    l[#l + 1] = string.format("%.4f", t - P)
    if t > ate + 2 and k > 4 then break end
  end
  return table.concat(l, ",")
end
local function ler_batidas(txt, P)
  local l = {}
  for x in tostring(txt or ""):gmatch("[^,%s]+") do
    local v = tonumber(x)
    if v then l[#l + 1] = P + v end
  end
  return l
end

-- Gera click / guia / cifra a partir do que está salvo (sem analisar de novo)
function M.restaurar_extras(m, meta, pasta)
  if not m or not meta or meta.ANALISE ~= "1" then return false end
  local bpm, bpb, den0 = compasso_em(m.inicio + (tonumber(meta.GRADE) or 0))
  local nb, den = M.ler_compasso_txt(meta.COMPASSO, bpb, den0 or 4)
  local ini = m.inicio + (tonumber(meta.GRADE) or 0)
  local partes = {}
  local it = M.item_principal(m)
  local bat = (meta.ANDAMENTO == "VARIAVEL") and ler_batidas(meta.BATIDAS, m.inicio + (tonumber(meta.AUDIO_INICIO) or 0)) or {}
  if meta.CANAL_CLICK == "L" or meta.CANAL_CLICK == "R" then
    if M.separar_click_vs(m, it, meta.CANAL_CLICK) then partes[#partes + 1] = "click do VS (lado " .. meta.CANAL_CLICK .. ")" end
  elseif #bat >= 8 then
    local fim = it and (r.GetMediaItemInfo_Value(it, "D_POSITION") + r.GetMediaItemInfo_Value(it, "D_LENGTH")) or m.fim
    if M.aplicar_batidas(m, bat, nb, math.min(fim, m.fim, bat[#bat] + 0.01), meta.CLICK_APROX == "1", den) then
      partes[#partes + 1] = "click (acompanha o andamento)"
    end
    marcar_aproximado(m, meta.CLICK_APROX == "1")
  elseif meta.CLICK ~= "0" then
    local fim = it and (r.GetMediaItemInfo_Value(it, "D_POSITION") + r.GetMediaItemInfo_Value(it, "D_LENGTH")) or m.fim
    if M.gerar_click(m, ini, math.min(fim, m.fim), bpm, nb, den) then partes[#partes + 1] = "click" end
  end
  if meta.GUIA ~= "0" then
    local ok = M.gerar_guia(m)
    if ok then partes[#partes + 1] = "guia" end
  end
  local cif = pasta and M.ler_cifra(pasta .. SEP .. M.ARQ_CIFRA)
  if cif then
    for _, c in ipairs(cif) do c.t = c.t + m.inicio end
    M.gerar_cifra_itens(m, cif, m.fim)
    partes[#partes + 1] = "cifra"
  end
  return true, table.concat(partes, ", ")
end

-- ---------- aplica o resultado da análise no projeto ----------
local function itens_da_musica(m)
  local l = {}
  local banda = M.achar_trilha(M.CFG.NOME_BANDA)
  local pad = banda and M.achar_filho(banda, M.CFG.NOME_PAD)
  local cif = M.achar_trilha(M.NOME_CIFRA)
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if tr ~= pad and tr ~= cif then
      for _, it in ipairs(itens_no_intervalo(tr, m.inicio, m.fim)) do
        if not tipo_gerado(it) then l[#l + 1] = it end
      end
    end
  end
  return l
end

-- v1.8: fim do áudio da música (itens próprios), limitado à região
local function fim_audio(m)
  local f = m.inicio
  for _, x in ipairs(itens_da_musica(m)) do
    local e = r.GetMediaItemInfo_Value(x, "D_POSITION") + r.GetMediaItemInfo_Value(x, "D_LENGTH")
    if e > f then f = e end
  end
  if f <= m.inicio + 1 then f = m.fim end
  return math.min(f, m.fim)
end

-- v1.8: CLICK do kit na música INTEIRA seguindo o mapa de tempo do REAPER
-- (mudanças de BPM e de compasso inclusive). Começa no 1º compasso dentro da região.
function M.gerar_click_mapa(m, ini, fim)
  local tr = trilha_fone(M.CFG.NOME_CLICK)
  if not tr then return false, "trilha CLICK não encontrada" end
  local antigos = M.arquivos_fonte_gerados(tr, m.inicio, m.fim, "CLICK")
  apagar_gerados(tr, m.inicio, m.fim, "CLICK")
  if M.click_guia_da_musica(m).CLICK then return false, "a música já tem click" end
  if not (r.TimeMap2_timeToBeats and r.TimeMap2_beatsToTime) then return false, "REAPER sem mapa de tempo" end
  ini = ini or m.inicio
  fim = fim or fim_audio(m)
  local bim, med = r.TimeMap2_timeToBeats(0, ini)
  local t0 = ini
  if bim and bim > 0.01 then t0 = r.TimeMap2_beatsToTime(0, 0, med + 1) end
  local _, _, _, qn = r.TimeMap2_timeToBeats(0, t0 + 1e-7)
  qn = math.floor(qn + 0.5)
  local cl, guarda = {}, 0
  local t = t0
  while t < fim - 0.001 and guarda < 50000 do
    local b, _, cml = r.TimeMap2_timeToBeats(0, t + 1e-6)
    b = b or 0
    -- 1º tempo do compasso (fórmula do mapa de tempo = a mesma que o painel mostra)
    cl[#cl + 1] = { t = t, forte = b < 0.05 or (cml and cml > 0 and b > cml - 0.05) or false }
    local _, _, den = compasso_em(t)
    qn = qn + 4 / (den > 0 and den or 4)
    t = r.TimeMap2_beatsToTime(0, qn)
    guarda = guarda + 1
  end
  if #cl < 2 then return false, "música curta demais para o click" end
  local arq = M.arquivo_click_batidas(cl, (m.nome or "") .. "|mapa")
  if not arq then return false, "não consegui gravar o arquivo de click" end
  M.soltar_clicks_antigos(antigos, arq)
  local it = r.AddMediaItemToTrack(tr)
  r.SetMediaItemInfo_Value(it, "D_POSITION", cl[1].t)
  r.SetMediaItemInfo_Value(it, "D_LENGTH", (cl[#cl].t - cl[1].t) + 0.1)
  r.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
  r.SetMediaItemInfo_Value(it, "C_BEATATTACHMODE", 0)
  local tk = r.AddTakeToMediaItem(it)
  r.SetMediaItemTake_Source(tk, r.PCM_Source_CreateFromFile(arq))
  local bpm0 = compasso_em(cl[1].t)
  r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", string.format("CLICK %g BPM (gerado, segue o mapa de tempo)",
    math.floor(bpm0 * 100 + 0.5) / 100), true)
  marcar_gerado(it, "CLICK")
  r.UpdateItemInProject(it)
  return true, #cl
end

-- v1.8: CONFERÊNCIA DO CLICK pela fórmula de compasso. Fonte única: o mapa de
-- tempo do projeto (gravado pela análise, lido pelo painel e pela guia). O
-- acento (tempo 1 forte, resto fraco) do click gerado pelo kit tem de cair
-- exatamente no 1º tempo de cada compasso, em cada trecho (6/8, 7/8, mudanças
-- no meio da música...). Click que veio na multitrack não é mexido.
local cache_click_wav = {}

-- Lê um WAV PCM 16 bits gerado pelo kit e devolve os clicks { t (s no arquivo), forte }.
local function ler_clicks_wav(arq)
  if not arq or arq == "" then return nil end
  local c = cache_click_wav[arq]
  if c then return c end
  local f = io.open(arq, "rb")
  if not f then return nil end
  local d = f:read("*a"); f:close()
  if not d or #d < 44 or d:sub(1, 4) ~= "RIFF" or d:sub(9, 12) ~= "WAVE" then return nil end
  local up = string.unpack
  local pos, sr, ch, bits, ini, tam = 13, nil, 1, nil, nil, 0
  while pos + 8 <= #d do
    local id, sz = d:sub(pos, pos + 3), up("<I4", d, pos + 4)
    if id == "fmt " then
      local fmt
      fmt, ch, sr = up("<I2I2I4", d, pos + 8)
      bits = up("<I2", d, pos + 22)
      if fmt ~= 1 then return nil end
    elseif id == "data" then
      ini = pos + 8; tam = math.min(sz, #d - ini + 1); break
    end
    pos = pos + 8 + sz + (sz % 2)
  end
  if not ini or bits ~= 16 or not sr or sr <= 0 or not ch or ch < 1 then return nil end
  local passo = 2 * ch
  local n = math.floor(tam / passo)
  local lim, forte_min = 0.12 * 32767, 0.68 * 32767
  local janela, pacote = math.floor(0.012 * sr), math.floor(0.045 * sr)
  local L = {}
  local i = 0
  while i < n do
    -- pula o silêncio (zeros) direto no C
    local b = d:find("[^%z]", ini + i * passo)
    if not b or b >= ini + n * passo then break end
    i = math.floor((b - ini) / passo)
    local v = up("<i2", d, ini + i * passo)
    if v > lim or v < -lim then
      local i0 = math.max(0, i - 8)
      local pico = 0
      for j = i0, math.min(n - 1, i0 + janela) do
        local w = up("<i2", d, ini + j * passo)
        if w < 0 then w = -w end
        if w > pico then pico = w end
      end
      L[#L + 1] = { t = i0 / sr, forte = pico > forte_min }
      i = i0 + pacote
    else
      i = i + 1
    end
  end
  c = { clicks = L, dur = n / sr }
  cache_click_wav[arq] = c
  return c
end

-- Clicks de um item (no tempo do projeto), respeitando offset, playrate e loop.
local function clicks_do_item(it)
  local tk = r.GetActiveTake(it)
  if not tk or r.TakeIsMIDI(tk) then return nil end
  local src = r.GetMediaItemTake_Source(tk)
  local arq = src and r.GetMediaSourceFileName(src, "") or ""
  local w = ler_clicks_wav(arq)
  if not w or w.dur <= 0 then return nil end
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
  local offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") or 0
  local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE") or 1
  if rate <= 0 then rate = 1 end
  local loop = r.GetMediaItemInfo_Value(it, "B_LOOPSRC") == 1
  if loop then offs = offs % w.dur end
  local L, k = {}, 0
  repeat
    local base = k * w.dur
    for _, c in ipairs(w.clicks) do
      local s = (base + c.t - offs) / rate
      if s >= -0.0005 and s < len - 0.0005 then L[#L + 1] = { t = pos + s, forte = c.forte } end
    end
    k = k + 1
  until not loop or (k * w.dur - offs) / rate >= len or k > 20000
  return L, arq
end

-- nil = click coerente com a fórmula (ou não é do kit); senão motivo, info
-- info = { ini = início do 1º compasso com click, fim = último click, erros, total }
function M.click_fora_do_compasso(m)
  if not m or not (r.TimeMap2_timeToBeats and r.TimeMap2_beatsToTime) then return nil end
  if M.click_guia_da_musica(m).CLICK then return nil end  -- click da multitrack: mantém
  local tr = trilha_fone(M.CFG.NOME_CLICK)
  if not tr then return nil end
  local cl = {}
  for _, it in ipairs(itens_no_intervalo(tr, m.inicio, m.fim)) do
    if tipo_gerado(it) == "CLICK" then
      local L = clicks_do_item(it)
      if not L then return nil end  -- arquivo que não sei ler: não mexe
      for _, c in ipairs(L) do
        if c.t >= m.inicio - 0.05 and c.t < m.fim then cl[#cl + 1] = c end
      end
    end
  end
  if #cl < 2 then return nil end
  table.sort(cl, function(a, b) return a.t < b.t end)
  local tol = 0.012
  local erros, primeiro = 0, nil
  -- 1) acento só no 1º tempo e 1º tempo sempre acentuado
  for _, c in ipairs(cl) do
    local t0 = M.inicio_do_compasso(c.t + tol)
    local no_um = math.abs(c.t - t0) <= tol
    if c.forte ~= no_um then
      erros = erros + 1
      if not primeiro then
        local _, num, den = compasso_em(c.t)
        primeiro = string.format("%.2f s (%s/%s): click %s %s", c.t, tostring(num), tostring(den),
          c.forte and "forte" or "fraco", no_um and "no 1º tempo" or "fora do 1º tempo")
      end
    end
  end
  -- 2) nenhum 1º tempo sem click entre o primeiro e o último click
  local _, med = r.TimeMap2_timeToBeats(0, cl[1].t + tol)
  med = math.floor((tonumber(med) or 0) + 1e-9)
  local j, guarda = 1, 0
  while guarda < 20000 do
    guarda = guarda + 1
    local ts = r.TimeMap2_beatsToTime(0, 0, med)
    if not ts or ts > cl[#cl].t + tol then break end
    if ts >= cl[1].t - tol then
      while j < #cl and cl[j].t < ts - tol do j = j + 1 end
      if math.abs(cl[j].t - ts) > tol then
        erros = erros + 1
        if not primeiro then primeiro = string.format("%.2f s: 1º tempo do compasso sem click", ts) end
      end
    end
    med = med + 1
  end
  local info = { ini = M.inicio_do_compasso(cl[1].t + tol), fim = cl[#cl].t, erros = erros, total = #cl }
  if erros > 0 then return primeiro or "acento fora do compasso", info end
  return nil, info
end

-- Regera o click da música pelo mapa de tempo, no mesmo trecho que ele já ocupa.
function M.corrigir_click_compasso(m)
  local motivo, info = M.click_fora_do_compasso(m)
  if not motivo then return false, nil end
  local ini = math.max(m.inicio, (info and info.ini) or m.inicio)
  local fim = info and info.fim and (info.fim + 0.01) or nil
  local ok, n = M.gerar_click_mapa(m, ini, fim)
  return ok, motivo, n
end

-- v1.8: multitrack: mantém o click/guia que vierem nela; o que faltar o kit gera
-- (click pelo mapa de tempo, guia falada com contagem + todas as seções). Sem duplicar.
-- opcoes.sem_click = não gerar click (BPM desconhecido). Devolve texto, achados
function M.completar_click_guia(m, opcoes)
  opcoes = opcoes or {}
  local cg = M.click_guia_da_musica(m)
  local l = {}
  if cg.CLICK then
    local tr = trilha_fone(M.CFG.NOME_CLICK)
    if tr then apagar_gerados(tr, m.inicio, m.fim, "CLICK") end
    l[#l + 1] = "Click: já vem na multitrack (" .. tostring(cg.CLICK.nome) .. ") - mantido"
  elseif opcoes.sem_click then
    l[#l + 1] = "Click: não gerado (" .. tostring(opcoes.sem_click) .. ")"
  else
    local ok, n = M.gerar_click_mapa(m)
    l[#l + 1] = ok and "Click: gerado pelo kit na música inteira (segue o mapa de tempo)" or ("Click: não gerado (" .. tostring(n) .. ")")
  end
  if cg.GUIA then
    local tr = trilha_fone(M.CFG.NOME_GUIA)
    if tr then apagar_gerados(tr, m.inicio, m.fim, "GUIA") end
    l[#l + 1] = "Guia: já vem na multitrack (" .. tostring(cg.GUIA.nome) .. ") - mantida"
  else
    local ok, n = M.gerar_guia(m)
    l[#l + 1] = ok and string.format("Guia: gerada pelo kit (%d avisos: contagem e seções)", tonumber(n) or 0)
      or ("Guia: não gerada (" .. tostring(n) .. ")")
  end
  return table.concat(l, "\n"), cg
end

function M.aplicar_analise(m, it, res, op)
  op = op or {}
  local bpb = res.bpb or 4
  local num, den = bpb, 4
  if res.num and res.num > 0 then num = res.num end
  if res.den and res.den > 0 then den = res.den end
  if op.bpb and op.bpb > 0 then bpb, num = op.bpb, op.bpb end
  if op.num and op.num > 0 then num, bpb = op.num, op.num end
  if op.den and op.den > 0 then den = op.den end
  if op.compasso or (res and res.compasso) then
    local nn, dd = M.ler_compasso_txt(op.compasso or res.compasso, num, den)
    num, den = nn, dd
    if not op.bpb and not res.bpb then bpb = num end
  end
  num, den, bpb = inteiro(num, 4), inteiro(den, 4), inteiro(bpb, 4)
  if den < 1 then den = 4 end
  if num < 1 then num, bpb = 4, 4 end
  local bpm = res.bpm
  local B = M.qn_por_compasso(num, den) * 60 / bpm
  local rate = r.GetMediaItemTakeInfo_Value(r.GetActiveTake(it), "D_PLAYRATE")
  if not rate or rate <= 0 then rate = 1 end
  -- v1.4: o click SEMPRE sai. Grade fixa (exata, como antes) ou, se o andamento
  -- varia (ao vivo), batidas reais + mapa de tempo que acompanha a música.
  local variavel = res.variavel and res.beats and res.k_primeiro and (#res.beats - res.k_primeiro) >= 8 and not res.canal_click
  local firme = (not variavel) and (res.andamento_firme or (op.bpm and op.bpm > 0)) and true or false
  local aprox = (not res.canal_click) and ((variavel and res.aproximado) or (not variavel and not firme)) and true or false
  local P = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local d1 = res.downbeat / rate
  if variavel then
    -- compasso inicial = mediana das 4 primeiras batidas reais
    local iv = {}
    for k = res.k_primeiro + 1, math.min(#res.beats, res.k_primeiro + 4) do iv[#iv + 1] = (res.beats[k] - res.beats[k - 1]) / rate end
    table.sort(iv)
    B = bpb * iv[math.floor((#iv + 1) / 2)]
    d1 = res.beats[res.k_primeiro] / rate
  end

  -- apaga o que o kit gerou antes nesta música
  for _, nome in ipairs({ M.CFG.NOME_CLICK, M.CFG.NOME_GUIA }) do
    local tr = trilha_fone(nome)
    if tr then apagar_gerados(tr, m.inicio, m.fim) end
  end
  apagar_gerados(M.trilha_cifra(false), m.inicio, m.fim)

  -- desloca o áudio para o 1º tempo cair num compasso inteiro (com 1 compasso de contagem)
  local s = 0
  local itens = itens_da_musica(m)
  local fim_itens = m.fim
  for _, x in ipairs(itens) do
    local e = r.GetMediaItemInfo_Value(x, "D_POSITION") + r.GetMediaItemInfo_Value(x, "D_LENGTH")
    if e > fim_itens then fim_itens = e end
  end
  if (firme or variavel) and not op.nao_mover then
    local k = math.max(1, math.ceil((P + d1 - m.inicio) / B - 1e-6))
    s = m.inicio + k * B - (P + d1)
    if s > B - 0.002 then s = 0 end
    -- próxima na TIMELINE (espaço na linha do tempo), não no setlist
    local prox
    do
      local mus_t = M.listar_marcadores()
      for _, x in ipairs(mus_t) do
        if x.inicio > m.inicio + 0.001 then prox = x; break end
      end
    end
    if s > 0.0005 and prox and fim_itens + s > prox.inicio - 0.5 then s = 0 end   -- sem espaço: não mexe
    if s > 0.0005 then
      for _, x in ipairs(itens) do
        r.SetMediaItemInfo_Value(x, "D_POSITION", r.GetMediaItemInfo_Value(x, "D_POSITION") + s)
      end
    else
      s = 0
    end
  end
  P = P + s
  local D = P + d1                                         -- 1º tempo do 1º compasso com música
  local bat = nil                                          -- batidas reais (andamento variável)
  if variavel then
    bat = {}
    for k = res.k_primeiro, #res.beats do bat[#bat + 1] = P + res.beats[k] / rate end
    D = bat[1]
    local iv = {}
    for k = 2, math.min(#bat, 5) do iv[#iv + 1] = bat[k] - bat[k - 1] end
    table.sort(iv)
    B = bpb * iv[math.floor((#iv + 1) / 2)]
  end
  local T = D - B * math.floor((D - m.inicio) / B + 1e-6)  -- 1ª barra dentro da região
  local fim_novo = math.max(m.fim + s, fim_itens + s)
  local fim_som = P + (res.fim_som or res.duracao) / rate

  -- região (fim) e tom
  local tom = m.tom
  if (not tom or tom == "") and res.tom_pc then tom = M.nome_tom(res.tom_pc, res.tom_menor) end
  local nome_reg = m.nome .. ((tom and tom ~= "") and (" [" .. tom .. "]") or "")
  r.SetProjectMarker3(0, m.idx, true, m.inicio, fim_novo, nome_reg, m.cor)
  m = musica_por_idx(m.idx) or m

  -- grade do REAPER (+ click que acompanha o andamento)
  local ok_var, info_var
  if variavel then
    ok_var, info_var, T = M.aplicar_batidas(m, bat, bpb, math.min(fim_som + B, m.fim), aprox, den)
    T = T or D
  else
    escrever_mapa(m, { { t = T, bpm = bpm, num = num, den = den } })
  end

  -- seções
  local _, marcas = M.listar_marcadores()
  local existentes = {}
  for _, mk in ipairs(marcas) do
    if mk.inicio >= m.inicio - 0.001 and mk.inicio < m.fim - 0.001 then existentes[#existentes + 1] = mk end
  end
  local _, ja_analisada = r.GetProjExtState(0, "MT_ANALISADA", M.norm(m.nome))
  local gerar_secoes = res.secoes and (#existentes == 0 or ja_analisada == "1" or op.refazer_secoes)
  local nomes_secoes = {}
  if gerar_secoes then
    local novos = {}
    if D - B >= m.inicio - 0.002 then
      novos[#novos + 1] = { t = math.max(m.inicio, D - B), nome = "CONTAGEM" }
    end
    for _, sc in ipairs(res.secoes) do
      local tsec = (variavel and sc.t) and (P + sc.t / rate) or (D + sc.compasso * B)
      if tsec < fim_novo - 0.01 then novos[#novos + 1] = { t = tsec, nome = sc.nome } end
    end
    local ok_mk, err_mk = pcall(function()
      for k = #existentes, 1, -1 do r.DeleteProjectMarker(0, existentes[k].idx, false) end
      for _, sc in ipairs(novos) do
        r.AddProjectMarker2(0, false, sc.t, 0, sc.nome, -1, M.cor_secao(sc.nome))
        nomes_secoes[#nomes_secoes + 1] = sc.nome
      end
    end)
    if not ok_mk then
      M.registrar_erro("aplicar_analise-secoes", err_mk)
      nomes_secoes = {}
      for _, mk in ipairs(existentes) do
        pcall(r.AddProjectMarker2, 0, false, mk.inicio, 0, mk.nome, -1, M.cor_secao(mk.nome))
        nomes_secoes[#nomes_secoes + 1] = mk.nome
      end
    else
      r.SetProjExtState(0, "MT_ANALISADA", M.norm(m.nome), "1")
    end
  else
    for _, mk in ipairs(existentes) do nomes_secoes[#nomes_secoes + 1] = mk.nome end
  end

  -- click
  local info_click
  local it_click = nil
  if res.canal_click then
    local lado = res.canal_click == 1 and "L" or "R"
    M.separar_click_vs(m, it, lado)
    info_click = "usei o click do próprio VS (lado " .. lado .. ")"
    it_click = lado
  elseif variavel then
    if ok_var then
      info_click = string.format("gerado - ACOMPANHA o andamento da gravação (%d a %d BPM)",
        math.floor((res.bpm_min or bpm) + 0.5), math.floor((res.bpm_max or bpm) + 0.5))
    else
      info_click = "não gerado (" .. tostring(info_var) .. ")"
    end
  else
    local ok, msg = M.gerar_click(m, T, math.min(fim_som + B, m.fim), bpm, bpb, den)
    info_click = ok and "gerado" or ("não gerado (" .. tostring(msg) .. ")")
    if not ok and msg == "a música já tem click" then info_click = "já vem na multitrack/música - mantido" end
  end
  if aprox then info_click = info_click .. "\n   click aproximado - ajuste em Menu > Corrigir BPM se precisar" end
  marcar_aproximado(m, aprox)

  -- guia (se falhar, as seções/marcadores já foram gravados e ficam)
  local info_guia
  do
    local ok_g, a, b = pcall(M.gerar_guia, m)
    if not ok_g then
      M.registrar_erro("gerar_guia", a)
      info_guia = "não gerada (erro na guia; seções mantidas)"
    else
      info_guia = a and (tostring(b) .. " avisos falados") or ("não gerada (" .. tostring(b) .. ")")
      if not a and b == "a música já tem guia" then info_guia = "já vem na multitrack/música - mantida" end
    end
  end

  -- cifra
  local pasta = select(2, r.GetProjExtState(0, "MT_PASTA", M.norm(m.nome)))
  local info_cifra = "-"
  local lista = {}
  for _, c in ipairs(res.acordes or {}) do lista[#lista + 1] = { t = P + c.t / rate, nome = c.nome } end
  if #lista > 0 then
    local ok_c, err_c = pcall(M.gerar_cifra_itens, m, lista, math.min(fim_som, m.fim))
    if not ok_c then
      M.registrar_erro("gerar_cifra_itens", err_c)
    end
    local ok_a, arq = pcall(gravar_cifra, pasta, m, lista, bpm, num, den)
    if not ok_a then
      M.registrar_erro("gravar_cifra", arq)
      arq = nil
    end
    info_cifra = string.format("%s acordes%s", tostring(inteiro(#lista, 0)), arq and " (cifra.txt na pasta da música)" or "")
  end

  -- PAD no tom
  if tom and tom ~= "" then M.gerar_pad(musica_por_idx(m.idx) or m) end

  -- salva tudo na pasta (próxima importação não reanalisa)
  if pasta ~= "" then
    M.atualizar_info(pasta, {
      NOME = m.nome, TOM = tom, BPM = bpm, COMPASSO = num .. "/" .. den, ANALISE = "1",
      AUDIO_INICIO = string.format("%.6f", P - m.inicio), GRADE = string.format("%.6f", T - m.inicio),
      CANAL_CLICK = it_click or "", CLICK = it_click and "0" or "1", GUIA = "1",
      ANDAMENTO = variavel and "VARIAVEL" or "", CLICK_APROX = aprox and "1" or "",
      BATIDAS = variavel and M.batidas_texto(bat, P, math.min(fim_som + B, m.fim)) or "",
    })
    M.gravar_marcadores(musica_por_idx(m.idx) or m, true)
  end

  local alt = ""
  if res.alternativas and #res.alternativas > 0 then
    local l = {}
    for _, a in ipairs(res.alternativas) do l[#l + 1] = string.format("%g", math.floor(a.bpm * 10 + 0.5) / 10) end
    alt = "   (se estiver no dobro/metade: Menu > Corrigir BPM, ex.: " .. table.concat(l, " ou ") .. ")"
  end
  local bpm_txt = variavel and string.format("~%g (ao vivo: varia de %d a %d)", bpm,
    math.floor((res.bpm_min or bpm) + 0.5), math.floor((res.bpm_max or bpm) + 0.5)) or string.format("%g", bpm)
  local msg = string.format("BPM: %s%s\nTom provável: %s\nClick: %s\nGuia: %s\nSeções: %s\nCifra: %s",
    bpm_txt, alt, tom or "-", info_click, info_guia,
    (#nomes_secoes > 0) and table.concat(nomes_secoes, ", ") or "-", info_cifra)
  return true, msg
end

-- ---------- fila de análise (roda aos poucos, sem travar o REAPER) ----------
local fila = {}
local rodando = nil
local fila_ativa = false
local relatorio_fila = {}

local function status(txt)
  r.SetExtState(M.SEC, "ANALISE_STATUS", txt .. "|" .. string.format("%.3f", r.time_precise()), false)
end

-- texto para o painel ("Analisando: Nome  45%") ou nil
function M.analise_status()
  local v = r.GetExtState(M.SEC, "ANALISE_STATUS")
  local txt, t = v:match("^(.*)|([%d%.]+)$")
  if txt and r.time_precise() - (tonumber(t) or 0) < 3 then return txt end
  return M.separacao_status and M.separacao_status() or nil
end

-- IMPORTANTE (v1.3.1): no REAPER, GetAudioAccessorSamples DENTRO de uma coroutine
-- devolve só zeros (o áudio parecia "sem batida" e a análise falhava sempre).
-- Por isso a LEITURA do áudio e a parte que mexe no projeto rodam fora da coroutine
-- (aos poucos, em vários ciclos do defer); só o cálculo puro (A.finalizar) fica na coroutine.
local function preparar_job(job)
  local m = musica_por_idx(job.idx)
  if not m then return false, "Música não encontrada no projeto." end
  job.nome = m.nome
  local it = M.item_principal(m)
  if not it then return false, "A música não tem áudio na BANDA." end
  local tk = r.GetActiveTake(it)
  if not tk or r.TakeIsMIDI(tk) then return false, "O áudio principal não é um arquivo de áudio." end
  desfazer_click_vs(m, it)
  local pitch = r.GetMediaItemTakeInfo_Value(tk, "D_PITCH")
  if pitch ~= 0 then
    r.SetMediaItemTakeInfo_Value(tk, "D_PITCH", 0)
    job.restaurar = function() r.SetMediaItemTakeInfo_Value(tk, "D_PITCH", pitch) end
  end
  -- v1.4: original MUTADO (depois de separar trilhas): o REAPER entrega silêncio de
  -- item mutado, então desmuta só durante a leitura (parado) e muta de volta
  if r.GetMediaItemInfo_Value(it, "B_MUTE") == 1 then
    if (r.GetPlayState() & 1) == 1 then
      return false, "A música original está mutada (trilhas separadas) e o REAPER está tocando.\nDê STOP e peça a análise de novo (leva poucos segundos)."
    end
    r.SetMediaItemInfo_Value(it, "B_MUTE", 0)
    local ant = job.restaurar
    job.restaurar = function() r.SetMediaItemInfo_Value(it, "B_MUTE", 1); if ant then ant() end end
  end
  local A = analise_mod()
  local src = r.GetMediaItemTake_Source(tk)
  local nch = math.max(1, math.min(2, r.GetMediaSourceNumChannels(src)))
  local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
  if not rate or rate <= 0 then rate = 1 end
  local dur = r.GetMediaItemInfo_Value(it, "D_LENGTH") * rate
  job.it, job.A, job.nch = it, A, nch
  job.BL = 16384
  job.total = math.floor(dur * A.SR)
  job.lidos = 0
  job.pico = 0
  -- v1.8: multitrack -> analisa a mistura dos stems (tempo 0 = início do item principal)
  local fontes = M.fontes_analise_multitrack(m)
  if fontes then
    local P = r.GetMediaItemInfo_Value(it, "D_POSITION")
    local fim_max = P + dur / rate
    job.fontes = {}
    for _, f in ipairs(fontes) do
      local fr = r.GetMediaItemTakeInfo_Value(f.tk, "D_PLAYRATE")
      if not fr or fr <= 0 then fr = 1 end
      local fp = r.GetMediaItemInfo_Value(f.it, "D_POSITION")
      local fl = r.GetMediaItemInfo_Value(f.it, "D_LENGTH")
      if fp + fl > fim_max then fim_max = fp + fl end
      local fnch = math.max(1, math.min(2, r.GetMediaSourceNumChannels(f.src)))
      local acc = r.CreateTakeAudioAccessor(f.tk)
      if acc then
        job.fontes[#job.fontes + 1] = { acc = acc, nch = fnch, desloc = fp - P, fr = fr,
          len = fl * fr, energia = {} }
      end
    end
    if #job.fontes >= 2 then
      job.nch = 2
      job.BL = 4096                                   -- pedaços menores: não trava o REAPER
      job.total = math.floor(math.max(dur, (fim_max - P) * rate) * A.SR)
      job.buf = r.new_array(job.BL * 2)
      job.st = A.novo(2)
      job.QF = math.floor(A.SR / 4)                   -- 4 medidas de energia por segundo
      job.rate = rate
      return true
    end
    for _, f in ipairs(job.fontes) do pcall(r.DestroyAudioAccessor, f.acc) end
    job.fontes = nil
  end
  job.acc = r.CreateTakeAudioAccessor(tk)
  job.st = A.novo(nch)
  job.buf = r.new_array(job.BL * nch)
  return true
end

local function fechar_fontes(job)
  if not job.fontes then return end
  for _, f in ipairs(job.fontes) do
    if f.acc then pcall(r.DestroyAudioAccessor, f.acc); f.acc = nil end
  end
end

-- lê um pedaço da MISTURA dos stems (multitrack) e mede a energia de cada stem
local function ler_mistura(job, n)
  local A, buf = job.A, job.buf
  local mix = {}
  for k = 1, n * 2 do mix[k] = 0 end
  local t_ini = job.lidos / A.SR
  local QF = job.QF
  for _, f in ipairs(job.fontes) do
    local t0 = (t_ini / (job.rate or 1) - f.desloc) * f.fr   -- tempo dentro do item deste stem
    if f.acc and t0 + n / A.SR > 0 and t0 < f.len then
      buf.clear()
      r.GetAudioAccessorSamples(f.acc, A.SR, f.nch, t0, n, buf)
      local t = buf.table(1, n * f.nch)
      local e = f.energia
      local fn = f.nch
      for j = 0, n - 1 do
        local a = t[j * fn + 1] or 0
        local b = (fn == 2) and (t[j * fn + 2] or 0) or a
        mix[j * 2 + 1] = mix[j * 2 + 1] + a
        mix[j * 2 + 2] = mix[j * 2 + 2] + b
        local q = (job.lidos + j) // QF + 1
        e[q] = (e[q] or 0) + (a * a + b * b) * 0.5
      end
    end
  end
  return mix
end

local function atividade_dos_stems(job)
  if not job.fontes or not job.QF then return nil end
  local nq = job.total // job.QF + 1
  local at = { fps = job.A.SR / job.QF, stems = {} }
  for _, f in ipairs(job.fontes) do
    local e = {}
    for q = 1, nq do e[q] = (f.energia[q] or 0) / job.QF end
    at.stems[#at.stems + 1] = e
  end
  return at
end

-- lê um pedaço do áudio (fora da coroutine). Retorna true quando terminou de ler.
local function ler_pedaco(job, ate)
  local A, nch, buf = job.A, job.nch, job.buf
  while job.lidos < job.total do
    local n = math.min(job.BL, job.total - job.lidos)
    local t
    if job.fontes then
      t = ler_mistura(job, n)
    else
      buf.clear()
      r.GetAudioAccessorSamples(job.acc, A.SR, nch, job.lidos / A.SR, n, buf)
      t = buf.table(1, n * nch)
    end
    if job.pico < 1e-6 then
      for k = 1, #t, 7 do local v = t[k]; if v > job.pico then job.pico = v elseif -v > job.pico then job.pico = -v end end
    end
    A.processar(job.st, t, n)
    job.lidos = job.lidos + n
    if r.time_precise() > ate then break end
  end
  job.prog = 0.45 * job.lidos / math.max(1, job.total)
  if job.lidos >= job.total then
    if job.acc then r.DestroyAudioAccessor(job.acc); job.acc = nil end
    fechar_fontes(job)
    if job.restaurar then job.restaurar(); job.restaurar = nil end
    return true
  end
  return false
end

-- aplica o resultado no projeto (fora da coroutine)
local function aplicar_job(job, res)
  local m = musica_por_idx(job.idx)
  if not m then return false, "A música foi apagada durante a análise." end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok_ap, ok, msg = pcall(M.aplicar_analise, m, job.it, res, job.op)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.UpdateTimeline()
  r.Undo_EndBlock("Click + guia + seções + cifra: " .. m.nome, -1)
  if not ok_ap then
    M.registrar_erro("aplicar_analise", ok)
    pcall(M.recuperar_marcadores_faltando, m)
    return false, "A análise encontrou um erro, mas a música e as seções foram mantidas.\n" .. tostring(ok)
  end
  return ok, msg
end

-- separação depois da análise (dando certo OU NÃO: separar não precisa do BPM)
local function separar_depois(job, ok, msg)
  if not (job.op and job.op.separar) then return msg end
  local m = musica_por_idx(job.idx)
  if not m then return msg end
  if M.motor_instalado() then
    local oks, como = M.separar_musica(m, { silencioso = true, automatico = true })
    if oks then
      return tostring(msg) .. "\n\nTrilhas: separando BATERIA, BAIXO, GUITARRA, TECLADO, VOZ e OUTROS (" .. tostring(como) ..
        "). Acompanhe no painel (\"Separando...\"); aviso ao terminar."
    end
    return tostring(msg) .. "\n\nTrilhas: não deu para separar (" .. tostring(como) .. ")."
  end
  if M.motor_instalando() then
    local oks = M.separar_musica(m, { silencioso = true })
    if oks then
      return tostring(msg) .. "\n\nTrilhas: na fila, separo assim que o motor de separação terminar de instalar."
    end
  end
  -- v1.8: antes ficava calado aqui (a música não era separada e ninguém avisava)
  M.anotar_sem_motor(m)
  return tostring(msg) .. "\n\nTrilhas: NÃO separadas - o motor de separação (bateria, baixo, guitarra, teclado, voz, outros) " ..
    "ainda não está instalado neste computador.\nInstale com 1 clique: Menu > Instalar motor de separação."
end

local function terminar(job, ok, msg)
  if job.restaurar then pcall(job.restaurar); job.restaurar = nil end
  local titulo = "Análise: " .. (job.nome or "música")
  if job.ao_terminar then
    local okcb, e = pcall(job.ao_terminar, ok, msg)
    if not okcb then r.MB(tostring(e), titulo, 0) end
  elseif job.silencioso then
    relatorio_fila[#relatorio_fila + 1] = (ok and "OK   " or "ERRO ") .. (job.nome or "?") ..
      (ok and "" or (": " .. tostring(msg)))
  else
    r.MB((ok and "Pronto!\n\n" or "Não deu certo:\n\n") .. tostring(msg), titulo, 0)
  end
end

-- v1.8: nome da etapa na barrinha ("Analisando Música  45% · tom")
local function etapa_job(job)
  local f = job.fase
  if f == "preparar" then return "preparando" end
  if f == "ler" then return "lendo o áudio" end
  if f == "calcular" then
    local q = ((job.prog or 0.45) - 0.45) / 0.5
    if q < 0.35 then return "tempo (BPM)" end
    if q < 0.72 then return "batidas e compasso" end
    if q < 0.85 then return "acordes e tom" end
    return "seções"
  end
  if f == "aplicar" then return "gerando click, guia e cifra" end
  return nil
end
M._etapa_job = etapa_job

local function texto_status_job(job, pct, extra)
  extra = extra or ""
  local nome = job.nome or "música"
  local et = (pct ~= nil) and etapa_job(job) or nil
  if et then extra = " · " .. et .. extra end
  if job.lote_total and job.lote_total > 1 then
    local meio
    if job.fase == "esperar_sep" then
      meio = "  (separando trilhas...)"
    elseif pct ~= nil then
      meio = string.format("  %d%%", pct)
    else
      meio = "..."
    end
    return string.format("Importando %d de %d: %s%s%s", job.lote_i or 1, job.lote_total, nome, meio, extra)
  end
  if job.fase == "esperar_sep" then
    return "Separando " .. nome .. "..." .. extra
  end
  if pct ~= nil then
    return string.format("Analisando %s  %d%%%s", nome, pct, extra)
  end
  return "Analisando " .. nome .. extra
end

local function passo()
  if not rodando then
    rodando = table.remove(fila, 1)
    if not rodando then
      fila_ativa = false
      r.DeleteExtState(M.SEC, "ANALISE_STATUS", false)
      if #relatorio_fila > 0 then
        local txt = table.concat(relatorio_fila, "\n")
        relatorio_fila = {}
        r.MB("Click, guia, seções e cifra:\n\n" .. txt .. "\n\nPara renomear uma seção: duplo clique nela no painel.",
          "Análise automática", 0)
      end
      if M.oferecer_motor_pendentes then M.oferecer_motor_pendentes() end
      return
    end
    rodando.prog = 0
    rodando.fase = "preparar"
  end
  local job = rodando
  local t0 = r.time_precise()
  local okp, e1, e2, e3 = pcall(function()
    if job.fase == "preparar" then
      local ok, msg = preparar_job(job)
      if not ok then return "fim", false, msg end
      job.fase = "ler"
    end
    if job.fase == "ler" then
      if ler_pedaco(job, t0 + 0.05) then
        if job.pico < 1e-6 then
          return "fim", false, "O áudio veio em silêncio (o REAPER não conseguiu ler o arquivo). Tente converter para WAV."
        end
        job.fase = "calcular"
        local A, st, op = job.A, job.st, job.op
        local at = atividade_dos_stems(job)
        if at then
          local op2 = {}
          for k, v in pairs(op or {}) do op2[k] = v end
          op2.atividade = at
          op = op2
          job.fontes = nil                     -- libera a memória (energias já copiadas)
        end
        job.co = coroutine.create(function()
          return A.finalizar(st, op, function(q) coroutine.yield(0.45 + 0.5 * q) end)
        end)
      end
      return "segue"
    end
    if job.fase == "calcular" then
      while true do
        local ok, a, b = coroutine.resume(job.co)
        if not ok then return "fim", false, "Erro na análise: " .. tostring(a) end
        if coroutine.status(job.co) == "dead" then
          job.st = nil
          if not a then return "fim", false, b end
          job.res = a
          job.fase = "aplicar"
          return "segue"
        end
        job.prog = tonumber(a) or job.prog
        if r.time_precise() - t0 > 0.05 then return "segue" end
      end
    end
    if job.fase == "aplicar" then
      local ok, msg = aplicar_job(job, job.res)
      return "fim", ok, msg
    end
    if job.fase == "esperar_sep" then
      if M.separacao_ocupada and M.separacao_ocupada() then return "segue" end
      job.fase = "esperar_sep_ok"
      return "fim", job.ok_final, job.msg_final
    end
    return "fim", false, "estado inválido: " .. tostring(job.fase)
  end)
  local estado, ok, msg = e1, e2, e3
  if not okp then estado, ok, msg = "fim", false, "Erro na análise: " .. tostring(e1) end
  if estado == "fim" then
    if job.acc then pcall(r.DestroyAudioAccessor, job.acc); job.acc = nil end
    fechar_fontes(job)
    if job.restaurar then pcall(job.restaurar); job.restaurar = nil end
    if not job.ja_separa then
      job.ja_separa = true
      msg = separar_depois(job, ok, msg)
      job.ok_final, job.msg_final = ok, msg
    else
      ok, msg = job.ok_final or ok, job.msg_final or msg
    end
    -- espera a Demucs desta música terminar antes de analisar a próxima
    if job.fase ~= "esperar_sep_ok" and job.op and job.op.separar
        and M.separacao_ocupada and M.separacao_ocupada() then
      job.fase = "esperar_sep"
      status(texto_status_job(job))
    else
      rodando = nil
      status((ok and "Pronto: " or "Análise falhou: ") .. (job.nome or ""))
      if not ok then
        r.ShowConsoleMsg("[Mik Seifador] Análise de \"" .. tostring(job.nome) .. "\" falhou: " .. tostring(msg) .. "\n")
      end
      terminar(job, ok, msg)
    end
  else
    local extra = ""
    if #fila > 0 and not (job.lote_total and job.lote_total > 1) then
      extra = string.format("  (+%d na fila)", #fila)
    end
    status(texto_status_job(job, math.floor((job.prog or 0) * 100 + 0.5), extra))
  end
  r.defer(passo)
end

-- Coloca a música (região) na fila de análise.
-- op = { bpm = forçado, bpb/num, den, compasso = "6/8", refazer_secoes = bool }
-- ao_terminar(ok, msg) opcional; silencioso = junta o resultado num relatório só
function M.analisar_musica(m, op, ao_terminar, silencioso)
  if not m then return false end
  fila[#fila + 1] = { idx = m.idx, nome = m.nome, op = op or {}, ao_terminar = ao_terminar, silencioso = silencioso }
  status("Analisando " .. m.nome .. "  0% · na fila")
  if not fila_ativa then
    fila_ativa = true
    r.defer(passo)
  end
  return true
end

function M.analise_ocupada() return fila_ativa end

-- Depois de importar várias, numera a fila para o painel ("Importando 2 de 5: ...")
function M.numerar_fila_importacao()
  local n = #fila + (rodando and 1 or 0)
  if n == 0 then return 0 end
  local i = 1
  if rodando then
    rodando.lote_i, rodando.lote_total = 1, n
    i = 2
  end
  for _, job in ipairs(fila) do
    job.lote_i, job.lote_total = i, n
    i = i + 1
  end
  local j = rodando or fila[1]
  if j then status(texto_status_job(j, math.floor((j.prog or 0) * 100 + 0.5))) end
  return n
end

function M.tamanho_fila_analise()
  return #fila + (rodando and 1 or 0)
end

-- Cancela só o RESTO da fila; a música que já está rodando termina.
function M.pode_cancelar_fila_importacao()
  return #fila > 0
end

function M.cancelar_fila_importacao()
  if #fila == 0 then return end
  local n = #fila
  for _, j in ipairs(fila) do
    relatorio_fila[#relatorio_fila + 1] = "---  " .. (j.nome or "?") .. " (fila cancelada)"
  end
  fila = {}
  M.aviso("Fila cancelada: " .. n .. " música(s) não serão analisadas. A atual continua.")
end

-- Menu: "Gerar click + guia + seções + cifra (música atual)"
-- op.silencioso / op.sem_popup: mesma função, sem diálogo (usado ao importar).
-- No automático, as seções já marcadas são MANTIDAS (nunca apaga marcadores).
function M.analisar_musica_atual(op)
  op = op or { refazer_secoes = false }
  local silencioso = op.silencioso or op.sem_popup
  local m = op.musica or M.musica_atual(op.inicio and (op.inicio + 0.01) or nil)
  if not m then
    if silencioso then return false, "Nenhuma música no projeto" end
    return M.aviso("Nenhuma música no projeto")
  end
  if not M.item_principal(m) then
    if silencioso then return false, "sem áudio na BANDA" end
    return r.MB("Esta música não tem áudio na BANDA para analisar.", "Click + guia + seções", 0)
  end
  -- v1.8: a música já tem seções (ex.: vieram do marcadores.txt de uma análise antiga)?
  -- Antes elas eram mantidas em silêncio e parecia que a análise "não gerava as seções".
  if not op.refazer_secoes then
    local _, marcas = M.listar_marcadores()
    local n = 0
    for _, mk in ipairs(marcas) do
      if mk.inicio >= m.inicio - 0.001 and mk.inicio < m.fim - 0.001 then n = n + 1 end
    end
    if n > 0 then
      if silencioso then
        op.refazer_secoes = false  -- importa: mantém as seções
      else
        local q = r.MB(string.format("\"%s\" já tem %d seções marcadas.\n\n"
          .. "SIM = refazer as seções com a análise (apaga as atuais)\n"
          .. "NÃO = manter as seções atuais (refaz só click, guia e cifra)", m.nome, n),
          "Click + guia + seções", 3)
        if q == 2 then return end
        if q == 6 then op.refazer_secoes = true end
      end
    end
  end
  local ao
  if silencioso then
    ao = function(ok, msg)
      if not ok then
        r.ShowConsoleMsg("[Mik Seifador] Análise de \"" .. tostring(m.nome) .. "\" falhou: " .. tostring(msg) .. "\n")
      end
      pcall(M.recuperar_marcadores_faltando, M.musica_atual(m.inicio + 0.01) or m)
    end
  end
  M.analisar_musica(m, op, ao, silencioso and true or nil)
  if not silencioso then
    M.aviso("Analisando " .. m.nome .. "... (o resultado aparece ao terminar)")
  end
  return true
end

-- Menu: "Corrigir BPM / compasso..." (dobro/metade/manual) e refaz tudo
function M.corrigir_bpm()
  local m = M.musica_atual()
  if not m then return M.aviso("Nenhuma música no projeto") end
  local bpm, num, den = compasso_em(m.inicio + 0.01)
  bpm = math.floor(bpm * 100 + 0.5) / 100
  local ok, txt = r.GetUserInputs(string.format("Corrigir andamento: %s (agora %g - metade %g, dobro %g)",
      m.nome, bpm, bpm / 2, bpm * 2), 2,
    "BPM certo (vazio = automático),Compasso (4/4  6/8  3/4),extrawidth=80",
    string.format("%g,%s/%s", bpm, tostring(inteiro(num, 4)), tostring(inteiro(den, 4))))
  if not ok then return end
  local a, b = txt:match("^([^,]*),(.*)$")
  local novo = tonumber((trim(a or ""):gsub(",", ".")))
  local n, d = M.ler_compasso_txt(b, 4, 4)
  if n < 2 or n > 16 then n = 4 end
  if d ~= 2 and d ~= 4 and d ~= 8 and d ~= 16 then d = 4 end
  if novo and (novo < 30 or novo > 260) then return r.MB("BPM fora do normal: " .. tostring(novo), "Corrigir BPM", 0) end
  M.analisar_musica(m, { bpm = novo, bpb = n, num = n, den = d, compasso = n .. "/" .. d, refazer_secoes = true })
  M.aviso("Refazendo click, guia, seções e cifra de " .. m.nome .. "...")
end

-- Renomear uma seção (duplo clique no painel ou Menu). Atualiza a guia e salva.
function M.renomear_secao(sec)
  local pos = M.pos_atual()
  local m = M.musica_atual(pos)
  if not m then return M.aviso("Nenhuma música no projeto") end
  local secs = M.secoes_da_musica(m)
  if sec then
    for _, s in ipairs(secs) do if math.abs(s.inicio - sec.inicio) < 0.01 and not s.virtual then sec = s end end
  else
    sec = M.secao_atual(pos, secs)
  end
  if not sec or sec.virtual or not sec.idx then
    return r.MB("Este trecho ainda não é uma seção.\nUse MARCAR SEÇÃO (tecla M) para criar uma.", "Renomear seção", 0)
  end
  local ok, nome = r.GetUserInputs("Renomear seção (" .. sec.nome .. ")", 1,
    "Novo nome (INTRO VERSO 1 PRÉ-REFRÃO REFRÃO 2 PONTE SOLO FINAL),extrawidth=160", sec.nome)
  if not ok or trim(nome) == "" then return end
  nome = trim(nome):upper()
  r.Undo_BeginBlock()
  r.SetProjectMarker3(0, sec.idx, false, sec.inicio, 0, nome, M.cor_secao(nome))
  M.gerar_guia(m, true)
  r.Undo_EndBlock("Renomear seção: " .. nome, -1)
  r.UpdateTimeline()
  M.gravar_marcadores(m, true)
  M.aviso("Seção renomeada: " .. nome)
end

-------------------------------------------------------------------------------
-- SEPARAR TRILHAS (bateria, baixo, guitarra, teclado, voz, outros) - v1.3
-------------------------------------------------------------------------------
--[[
  Usa um "motor" de separação fora do REAPER (Python + Demucs 4 / htdemucs_6s),
  instalado UMA vez em:
    Windows: %LOCALAPPDATA%\MikSeifador\motor
    Mac:     ~/Library/Application Support/MikSeifador/motor
  O REAPER chama o motor sem travar (ExecProcess sem esperar) e acompanha pelo
  arquivo status.txt. Quando termina, entram 4 trilhas na BANDA (BATERIA, BAIXO,
  VOZ, OUTROS) alinhadas com a música original (que fica MUTADA, não apagada).
  As trilhas ficam salvas em <pasta da música>\__stems (não separa de novo).
  Estado dos pedidos: ProjExtState "MT_SEPARAR" (vale para painel e scripts).
]]
M.PASTA_STEMS = "__stems"
M.STEMS_SEPARADOS = { "Bateria", "Baixo", "Guitarra", "Teclado", "Voz", "Outros" }
local SEC_SEP = "MT_SEPARAR"

function M.separacao_auto() return M.get("SEPARAR_AUTO", "1") ~= "0" end
function M.alternar_separacao_auto()
  M.set("SEPARAR_AUTO", M.separacao_auto() and "0" or "1")
  M.aviso("Separar trilhas ao importar: " .. (M.separacao_auto() and "LIGADO" or "DESLIGADO"))
end
function M.mutar_original() return M.get("SEP_MUTAR_ORIGINAL", "1") ~= "0" end
function M.alternar_mutar_original()
  M.set("SEP_MUTAR_ORIGINAL", M.mutar_original() and "0" or "1")
  M.aviso("Música original depois de separar: " .. (M.mutar_original() and "MUTADA" or "TOCANDO junto"))
end
-- Padrão DESLIGADO: qualidade normal (shifts=1, overlap=0.25). Ligada: mais rápida, um pouco menos qualidade.
function M.separacao_rapida() return M.get("SEP_RAPIDA", "0") == "1" end
function M.alternar_separacao_rapida()
  M.set("SEP_RAPIDA", M.separacao_rapida() and "0" or "1")
  M.aviso("Separação rápida: " .. (M.separacao_rapida()
    and "LIGADA (~15% mais rápida, qualidade um pouco menor)"
    or "DESLIGADA (qualidade normal)"))
end
-- Qualidade máxima (cascata tipo Stem Splitter). Padrão ligado só se o teste local
-- provou ser melhor; "Separação rápida" continua forçando só o htdemucs_6s.
function M.separacao_qualidade() return M.get("SEP_QUALIDADE", "0") == "1" end
function M.alternar_separacao_qualidade()
  M.set("SEP_QUALIDADE", M.separacao_qualidade() and "0" or "1")
  M.aviso("Qualidade máxima (tipo Stem Splitter): " .. (M.separacao_qualidade()
    and "LIGADA (melhor isolamento da voz, mais lenta)"
    or "DESLIGADA (só htdemucs_6s, mais rápida)"))
end

function M.motor_dir()
  if M.EH_WIN then
    return (os.getenv("LOCALAPPDATA") or ((os.getenv("USERPROFILE") or "C:") .. "\\AppData\\Local")) .. "\\MikSeifador\\motor"
  end
  return (os.getenv("HOME") or "") .. "/Library/Application Support/MikSeifador/motor"
end
function M.motor_python()
  if M.EH_WIN then return M.motor_dir() .. "\\venv\\Scripts\\pythonw.exe" end
  return M.motor_dir() .. "/venv/bin/python"
end
function M.motor_instalado()
  return r.file_exists(M.motor_python()) and r.file_exists(M.motor_dir() .. SEP .. "versao.txt")
end
local function dir_separador() return M.DIR .. "separador" .. SEP end

local function ler_linha(arq)
  local f = io.open(arq, "r")
  if not f then return nil end
  local s = f:read("*l"); f:close()
  return s and trim(s) or nil
end
local function gravar_texto(arq, txt)
  local f = io.open(arq, "w")
  if not f then return false end
  f:write(txt); f:close()
  return true
end

-- lê "PROGRESSO 0.42 texto" / "OK ..." / "ERRO texto"
local function ler_status(arq)
  local s = ler_linha(arq)
  if not s or s == "" then return nil end
  if s:sub(1, 2) == "OK" then return "OK", 1, s:sub(4) end
  if s:sub(1, 4) == "ERRO" then return "ERRO", 0, trim(s:sub(5)) end
  local p, txt = s:match("^PROGRESSO%s+([%d%.]+)%s*(.*)$")
  if p then return "PROG", tonumber(p) or 0, txt end
  return nil
end

local function status_sep(txt)
  r.SetExtState(M.SEC, "SEP_STATUS", txt .. "|" .. string.format("%.3f", r.time_precise()), false)
end

-- ---------- instalar o motor ----------
function M.motor_instalando()
  return r.GetExtState(M.SEC, "MOTOR_INSTALANDO") == "1"
end

-- Tem pedido de separação na fila ou rodando (Demucs), ou o motor está instalando
function M.separacao_ocupada()
  if M.motor_instalando() then return true end
  local i = 0
  while true do
    local ok, k, v = r.EnumProjExtState(0, SEC_SEP, i)
    if not ok or not k or k == "" then break end
    i = i + 1
    if v and (v:sub(1, 7) == "RODANDO" or v:sub(1, 4) == "FILA") then return true end
  end
  return false
end

function M.instalar_motor(sem_perguntar)
  if M.motor_instalando() then return M.aviso("O motor de separação já está sendo instalado...") end
  if not sem_perguntar then
    local txt = "Instalar o MOTOR DE SEPARAÇÃO de trilhas?\n\n" ..
      "Ele separa qualquer música (ou VS fechado) em BATERIA, BAIXO, GUITARRA, TECLADO, VOZ e OUTROS.\n\n" ..
      "- Baixa uns 1 GB da internet (só desta vez) e ocupa uns 1,5 GB.\n" ..
      "- Leva de 5 a 15 minutos, dependendo da internet. Pode continuar usando o REAPER.\n" ..
      "- Fica em: " .. M.motor_dir() .. "\n\n" ..
      "Instalar agora?"
    if r.MB(txt, "Mik Seifador - Separar trilhas", 4) ~= 6 then return false end
  end
  local base = M.motor_dir()
  r.RecursiveCreateDirectory(base, 0)
  os.remove(base .. SEP .. "instalacao.txt")
  local ds = dir_separador()
  local cmd
  if M.EH_WIN then
    cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' .. ds .. 'instalar_motor.ps1"'
  else
    cmd = '/bin/bash "' .. ds .. 'instalar_motor.sh"'
  end
  r.SetExtState(M.SEC, "MOTOR_INSTALANDO", "1", false)
  r.SetExtState(M.SEC, "MOTOR_INST_T0", string.format("%.0f", os.time()), false)
  r.ExecProcess(cmd, -1)
  status_sep("Instalando o motor de separação...")
  M.aviso("Instalando o motor de separação (aviso ao terminar)...")
  M.garantir_poll_separacao()
  return true
end

local function conferir_instalacao()
  if not M.motor_instalando() then return end
  local est, p, txt = ler_status(M.motor_dir() .. SEP .. "instalacao.txt")
  if est == "OK" then
    r.DeleteExtState(M.SEC, "MOTOR_INSTALANDO", false)
    status_sep("Motor de separação instalado!")
    local n = 0
    local i = 0
    while true do
      local ok = r.EnumProjExtState(0, SEC_SEP, i)
      if not ok then break end
      n = n + 1; i = i + 1
    end
    r.MB("Motor de separação instalado!\n\n" ..
      (n > 0 and ("Separando agora: " .. n .. " música(s). Aviso ao terminar.\n\n") or "") ..
      "Para separar uma música: Menu > Separar trilhas (bateria, baixo, guitarra, teclado, voz).\n" ..
      "Ao importar uma música comum / VS fechado, ela já é separada sozinha.", "Mik Seifador", 0)
  elseif est == "ERRO" then
    r.DeleteExtState(M.SEC, "MOTOR_INSTALANDO", false)
    r.MB("A instalação do motor de separação não deu certo:\n\n" .. tostring(txt) ..
      "\n\nConfira a internet e tente de novo: Menu > Instalar motor de separação.\n" ..
      "Detalhes: " .. M.motor_dir() .. SEP .. "instalacao.log", "Mik Seifador", 0)
  elseif est == "PROG" then
    status_sep(string.format("Instalando motor %d%%: %s", math.floor(p * 100 + 0.5), txt))
  else
    local t0 = tonumber(r.GetExtState(M.SEC, "MOTOR_INST_T0"))
    if t0 and os.time() - t0 > 180 then
      -- v1.8: o instalador nem começou (antes ficava "Instalando..." para sempre)
      r.DeleteExtState(M.SEC, "MOTOR_INSTALANDO", false)
      r.MB("A instalação do motor de separação não começou (3 minutos sem resposta).\n\n" ..
        M.instrucoes_motor_manual() .. "\n\nDepois de instalar, use Menu > Separar trilhas na música.",
        "Mik Seifador", 0)
    else
      status_sep("Instalando o motor de separação...")
    end
  end
end

-- ---------- pedidos ----------
local function item_original(m)
  return M.item_principal(m)
end

local function stems_prontos(saida)
  for _, n in ipairs(M.STEMS_SEPARADOS) do
    if not r.file_exists(saida .. SEP .. n .. ".flac") then return false end
  end
  local s = ler_linha(saida .. SEP .. "status.txt") or ""
  return s:sub(1, 2) == "OK"
end

-- acha a música pelo nome (se houver 2 com o mesmo nome, a mais perto do início guardado)
local function musica_por_nome(nome, inicio)
  local melhor, dist = nil, math.huge
  inicio = tonumber(inicio)
  for _, m in ipairs(M.get_musicas()) do
    if m.nome == nome then
      local d = inicio and math.abs(m.inicio - inicio) or 0
      if d < dist then melhor, dist = m, d end
    end
  end
  return melhor
end

local function lancar(saida, nome, entrada, canal, inicio)
  local base = M.motor_dir()
  r.RecursiveCreateDirectory(base .. SEP .. "pedidos", 0)
  r.RecursiveCreateDirectory(saida, 0)
  local pedido = base .. SEP .. "pedidos" .. SEP .. string.format("pedido_%d_%04d.txt", os.time(), math.random(0, 9999))
  local rapido = M.separacao_rapida and M.separacao_rapida() or false
  local modelo = "htdemucs_6s"
  if (not rapido) and M.separacao_qualidade and M.separacao_qualidade() then
    modelo = "qualidade"
  end
  gravar_texto(pedido, "entrada=" .. entrada .. "\nsaida=" .. saida .. "\ncanal=" .. canal
    .. "\nmodelo=" .. modelo .. "\nrapido=" .. (rapido and "1" or "0") .. "\n")
  os.remove(saida .. SEP .. "status.txt")
  gravar_texto(saida .. SEP .. "status.txt", "PROGRESSO 0.00 Iniciando o motor...\n")
  local cmd = '"' .. M.motor_python() .. '" "' .. dir_separador() .. 'separar.py" "' .. pedido .. '"'
  r.ExecProcess(cmd, -1)
  r.SetExtState(M.SEC, "SEP_LANCADO", saida .. "|" .. string.format("%.0f", os.time()), false)
  r.SetProjExtState(0, SEC_SEP, saida, table.concat({
    "RODANDO", nome, entrada, canal, inicio or "", rapido and "rapido" or "normal",
  }, "|"))
end

-- coloca as 6 trilhas separadas na BANDA, alinhadas com o áudio original
function M.inserir_stems(m, saida)
  local it = item_original(m)
  if not it then return false, "a música não tem áudio na BANDA" end
  local tk = r.GetActiveTake(it)
  local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(it, "D_LENGTH")
  local offs = r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS")
  local rate = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
  local pitch = r.GetMediaItemTakeInfo_Value(tk, "D_PITCH")
  local ppitch = r.GetMediaItemInfo_Value(it, "B_PPITCH")
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  M.garantir_estrutura()
  -- apaga trilhas separadas antigas desta música
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    for k = r.GetTrackNumMediaItems(tr) - 1, 0, -1 do
      local x = r.GetTrackMediaItem(tr, k)
      local _, st = r.GetSetMediaItemInfo_String(x, "P_EXT:MT_STEM", "", false)
      if st == "1" then
        local p = r.GetMediaItemInfo_Value(x, "D_POSITION")
        if p >= m.inicio - 0.01 and p < m.fim then r.DeleteTrackMediaItem(tr, x) end
      end
    end
  end
  local n = 0
  for _, nome in ipairs(M.STEMS_SEPARADOS) do
    local arq = saida .. SEP .. nome .. ".flac"
    local src = r.PCM_Source_CreateFromFile(arq)
    if src and r.GetMediaSourceLength(src) > 0 then
      local destino = M.classificar_stem(nome .. ".flac")
      local pasta_tr, sp = M.subpasta(destino)
      local nome_tr = nome:upper()
      local tr = M.achar_filho(pasta_tr, nome_tr) or M.inserir_filho_no_fim(pasta_tr, nome_tr, sp.cor)
      local novo = r.AddMediaItemToTrack(tr)
      r.SetMediaItemInfo_Value(novo, "D_POSITION", pos)
      r.SetMediaItemInfo_Value(novo, "D_LENGTH", len)
      r.SetMediaItemInfo_Value(novo, "C_BEATATTACHMODE", 0)
      r.SetMediaItemInfo_Value(novo, "B_PPITCH", ppitch)
      local tk2 = r.AddTakeToMediaItem(novo)
      r.SetMediaItemTake_Source(tk2, src)
      r.SetMediaItemTakeInfo_Value(tk2, "D_STARTOFFS", offs)
      r.SetMediaItemTakeInfo_Value(tk2, "D_PLAYRATE", rate)
      r.SetMediaItemTakeInfo_Value(tk2, "D_PITCH", pitch)
      r.GetSetMediaItemTakeInfo_String(tk2, "P_NAME", nome .. " (separada)", true)
      r.GetSetMediaItemInfo_String(novo, "P_EXT:MT_STEM", "1", true)
      r.UpdateItemInProject(novo)
      n = n + 1
    end
  end
  if n > 0 then
    r.GetSetMediaItemInfo_String(it, "P_EXT:MT_ORIGINAL", "1", true)
    r.SetMediaItemInfo_Value(it, "B_MUTE", M.mutar_original() and 1 or 0)
    r.UpdateItemInProject(it)
  end
  M.aplicar_modo()
  r.Main_OnCommand(40047, 0) -- picos
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Separar trilhas: " .. m.nome, -1)
  local pasta = select(2, r.GetProjExtState(0, "MT_PASTA", M.norm(m.nome)))
  if pasta ~= "" then M.atualizar_info(pasta, { STEMS = n > 0 and "1" or nil }) end
  return n > 0, n
end

local function tempo_txt(seg)
  seg = tonumber(seg) or 0
  if seg >= 60 then return string.format("%d min %02d s", math.floor(seg / 60), math.floor(seg % 60)) end
  return string.format("%d s", math.floor(seg + 0.5))
end

-- confere os pedidos (chamado pelo motor/painel a cada ~1 s). Seguro chamar de vários scripts.
-- v1.8: separações que não rodaram por falta do motor (para avisar UMA vez, com 1 clique)
local motor_pendentes = {}
function M.anotar_sem_motor(m)
  if not m then return end
  for _, x in ipairs(motor_pendentes) do
    if x.nome == m.nome and math.abs((x.inicio or 0) - (m.inicio or 0)) < 0.5 then return end
  end
  motor_pendentes[#motor_pendentes + 1] = { nome = m.nome, inicio = m.inicio }
end
function M.motor_pendentes() return motor_pendentes end

local function separar_pendentes(lista)
  local n = 0
  for _, x in ipairs(lista) do
    local m = musica_por_nome(x.nome, x.inicio)
    if m and M.separar_musica(m, { silencioso = true }) then n = n + 1 end
  end
  return n
end

function M.instrucoes_motor_manual()
  local ds = dir_separador()
  if M.EH_MAC then
    return "Instalar pelo Terminal (Mac): abra o app Terminal e cole:\n" ..
      '  /bin/bash "' .. ds .. 'instalar_motor.sh"\n' ..
      "Precisa de internet. Registro: " .. M.motor_dir() .. "/instalacao.log"
  end
  return "Instalar manualmente (Windows): botão direito em\n  " .. ds .. "instalar_motor.ps1\n" ..
    "> Executar com o PowerShell. Registro: " .. M.motor_dir() .. "\\instalacao.log"
end

function M.oferecer_motor_pendentes()
  if #motor_pendentes == 0 then return end
  local lista = motor_pendentes
  motor_pendentes = {}
  if M.motor_instalado() or M.motor_instalando() then
    separar_pendentes(lista)
    return
  end
  local nomes = {}
  for i, x in ipairs(lista) do
    if i > 6 then nomes[#nomes + 1] = string.format("  ... e mais %d", #lista - 6); break end
    nomes[#nomes + 1] = "  - " .. x.nome
  end
  if M.get("SEP_NAO_PERGUNTAR", "0") == "1" then
    M.aviso("Trilhas NÃO separadas (falta o motor): Menu > Instalar motor de separação")
    return
  end
  local resp = r.MB("A separação automática das trilhas (BATERIA, BAIXO, GUITARRA, TECLADO, VOZ e OUTROS) não rodou em:\n\n" ..
    table.concat(nomes, "\n") .. "\n\n" ..
    "Motivo: o MOTOR DE SEPARAÇÃO ainda não está instalado neste computador.\n" ..
    "Ele é instalado uma vez só: baixa uns 1 GB (precisa de internet) e leva de 5 a 15 minutos.\n" ..
    "Fica em: " .. M.motor_dir() .. "\n\n" ..
    "Sim = instalar agora e separar estas músicas assim que terminar\n" ..
    "Não = agora não (depois: Menu > Instalar motor de separação)\n" ..
    "Cancelar = não perguntar mais", "Mik Seifador - Instalar motor de separação", 3)
  if resp == 6 then
    if M.instalar_motor(true) then separar_pendentes(lista) end
  elseif resp == 2 then
    M.set("SEP_NAO_PERGUNTAR", "1")
    M.aviso("Ok. Para separar depois: Menu > Instalar motor de separação.")
  end
end

local motor_nao_iniciou
-- o Python do motor não deu sinal de vida em 3 min (separar.py escreve "Carregando o motor" logo ao abrir)
local LIMITE_INICIO_MOTOR = 180
motor_nao_iniciou = function(saida)
  local v = r.GetExtState(M.SEC, "SEP_LANCADO")
  local s, t = v:match("^(.*)|(%d+)$")
  if s ~= saida or not tonumber(t) then return false end
  return os.time() - tonumber(t) > LIMITE_INICIO_MOTOR
end

function M.avisar_motor_nao_iniciou(p)
  local txt = "O motor de separação não chegou a iniciar para \"" .. tostring(p.nome) .. "\" (3 minutos sem resposta).\n\n" ..
    "Causas comuns: a instalação do motor ficou incompleta" ..
    (M.EH_MAC and ", ou o macOS bloqueou o Python do motor (Ajustes do Sistema > Privacidade e Segurança > \"Abrir Mesmo Assim\")" or
      ", ou o antivírus bloqueou o Python do motor") .. ".\n\n" ..
    "Sim = reinstalar o motor agora e tentar separar de novo\nNão = deixar para depois\n\n" ..
    M.instrucoes_motor_manual()
  if r.MB(txt, "Mik Seifador - Separar trilhas", 4) == 6 then
    local m = musica_por_nome(p.nome, p.inicio)
    if M.instalar_motor(true) and m then M.separar_musica(m, { silencioso = true, refazer = true }) end
  end
end

function M.verificar_separacoes()
  conferir_instalacao()
  pcall(M.resgatar_separacao_ativa)
  local pedidos, i = {}, 0
  while true do
    local ok, k, v = r.EnumProjExtState(0, SEC_SEP, i)
    if not ok then break end
    pedidos[#pedidos + 1] = { saida = k, v = v }
    i = i + 1
  end
  if #pedidos == 0 then return false end
  local rodando = nil
  local fila = {}
  for _, p in ipairs(pedidos) do
    local estado, nome, entrada, canal, inicio = p.v:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|?([^|]*)")
    p.estado, p.nome, p.entrada, p.canal, p.inicio = estado, nome, entrada, canal, inicio
    if estado == "RODANDO" then rodando = p elseif estado == "FILA" then fila[#fila + 1] = p end
  end
  if rodando then
    local est, prog, txt = ler_status(rodando.saida .. SEP .. "status.txt")
    if est == "OK" then
      r.SetProjExtState(0, SEC_SEP, rodando.saida, "")       -- tira da lista ANTES de inserir (sem duplicar)
      local m = musica_por_nome(rodando.nome, rodando.inicio)
      local seg = (txt or ""):match("^([%d%.]+)")
      if m then
        local ok, n = M.inserir_stems(m, rodando.saida)
        status_sep("Trilhas separadas: " .. rodando.nome)
        if ok then
          M.aviso("Trilhas separadas: " .. rodando.nome .. " (" .. tempo_txt(seg) .. ")")
          if #fila == 0 and not M.tocando() then   -- tocando ao vivo: só o aviso discreto
            r.MB("Pronto! " .. rodando.nome .. " foi separada em " .. tempo_txt(seg) .. ":\n\n" ..
              "  BATERIA, BAIXO, GUITARRA, TECLADO, VOZ e OUTROS  (dentro da BANDA)\n\n" ..
              "A música original ficou " .. (M.mutar_original() and "MUTADA" or "tocando junto") ..
              " (não foi apagada).\nAs trilhas ficam salvas em " .. M.PASTA_STEMS .. " na pasta da música.",
              "Separar trilhas", 0)
          end
        else
          r.MB("Separei, mas não consegui colocar as trilhas: " .. tostring(n), "Separar trilhas", 0)
        end
      end
    elseif est == "ERRO" then
      r.SetProjExtState(0, SEC_SEP, rodando.saida, "")
      r.MB("Não deu para separar " .. rodando.nome .. ":\n\n" .. tostring(txt) ..
        "\n\nDetalhes: " .. rodando.saida .. SEP .. "erro.txt" ..
        "\n\nSe o erro se repetir em todas as músicas: Menu > Instalar motor de separação (reinstala).",
        "Separar trilhas", 0)
    elseif est == "PROG" and (prog or 0) < 0.001 and (txt or ""):find("^Iniciando o motor")
        and motor_nao_iniciou(rodando.saida) then
      -- v1.8: o Python do motor nem chegou a abrir (no Mac: bloqueio do sistema, motor incompleto...).
      -- Antes a barrinha ficava parada em "Iniciando o motor..." para sempre. Não mata nada.
      r.SetProjExtState(0, SEC_SEP, rodando.saida, "")
      r.DeleteExtState(M.SEC, "SEP_LANCADO", false)
      gravar_texto(rodando.saida .. SEP .. "status.txt", "ERRO o motor de separação não iniciou\n")
      M.avisar_motor_nao_iniciou(rodando)
    else
      status_sep(string.format("Separando %s  %d%%%s", rodando.nome, math.floor((prog or 0) * 100 + 0.5),
        (#fila > 0) and string.format("  (+%d na fila)", #fila) or ""))
    end
    return true
  end
  -- nada rodando: começa o próximo da fila (só uma separação por vez, para não pesar)
  if #fila > 0 and M.motor_instalado() and not M.motor_instalando() then
    local p = fila[1]
    lancar(p.saida, p.nome, p.entrada, p.canal, p.inicio)
    status_sep("Separando " .. p.nome .. "  0%")
  elseif #fila > 0 and not M.motor_instalando() and not M.motor_instalado() then
    -- motor sumiu/foi apagado: limpa a fila, mas AVISA (antes era calado)
    for _, p in ipairs(fila) do
      r.SetProjExtState(0, SEC_SEP, p.saida, "")
      local m = musica_por_nome(p.nome, p.inicio)
      if m then M.anotar_sem_motor(m) end
    end
    r.defer(function() M.oferecer_motor_pendentes() end)
  end
  return true
end

-- mantém a conferência rodando mesmo sem o painel/motor abertos (ex.: script avulso).
-- Se o painel ou o motor_ao_vivo estiverem abertos, eles já conferem (M.tick).
local poll_ativo = false
local function tick_conferindo()
  return r.time_precise() - (tonumber(r.GetExtState(M.SEC, "SEP_TICK_HB")) or 0) < 2.5
end
M.tick_conferindo = tick_conferindo
function M.garantir_poll_separacao()
  if poll_ativo then return end
  poll_ativo = true
  local ultimo = 0
  local function loop()
    local agora = r.time_precise()
    if agora - ultimo >= 1.0 then
      ultimo = agora
      if tick_conferindo() then poll_ativo = false; return end
      local tem = M.verificar_separacoes() or M.motor_instalando()
      if not tem then poll_ativo = false; return end
    end
    r.defer(loop)
  end
  r.defer(loop)
end

-- chamado pelo M.tick (painel ou motor_ao_vivo), no máximo 1x por segundo
local ultima_conferencia = 0
function M.conferir_separacoes_tick()
  local agora = r.time_precise()
  if agora - ultima_conferencia < 1.0 then return end
  ultima_conferencia = agora
  r.SetExtState(M.SEC, "SEP_TICK_HB", string.format("%.3f", agora), false)
  M.verificar_separacoes()
end

-- texto do painel enquanto separa/instala
function M.separacao_status()
  local v = r.GetExtState(M.SEC, "SEP_STATUS")
  local txt, t = v:match("^(.*)|([%d%.]+)$")
  if txt and r.time_precise() - (tonumber(t) or 0) < 4 then return txt end
  return nil
end

-- Cor da barrinha: vermelho em 0% → amarelo no meio → verde em 100%.
function M.cor_progresso_rgb(p)
  p = math.max(0, math.min(1, tonumber(p) or 0))
  local function lerp(a, b, t) return a + (b - a) * t end
  local r, g, b
  if p < 0.5 then
    local t = p * 2
    r, g, b = lerp(229, 242, t), lerp(72, 178, t), lerp(77, 58, t)
  else
    local t = (p - 0.5) * 2
    r, g, b = lerp(242, 61, t), lerp(178, 220, t), lerp(58, 132, t)
  end
  return math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5)
end

function M.cor_progresso(p)
  local r, g, b = M.cor_progresso_rgb(p)
  return (r << 24) | (g << 16) | (b << 8) | 0xFF
end

function M.fmt_tempo_restante(seg)
  seg = tonumber(seg)
  if not seg or seg < 0 or seg > 24 * 3600 then return nil end
  if seg < 15 then return "poucos segundos"
  elseif seg < 50 then return "cerca de " .. math.max(15, math.floor((seg + 5) / 10) * 10) .. " s"
  elseif seg < 90 then return "cerca de 1 min"
  else
    local m = math.floor((seg + 30) / 60)
    if m < 2 then return "cerca de 1 min" end
    return "cerca de " .. m .. " min"
  end
end

-- Estimativa de tempo restante a partir da evolução do progresso (sobrevive ao F9).
local function eta_de_progresso(chave, p)
  if not chave or not p or p <= 0 or p >= 0.999 then return nil end
  local agora = r.time_precise()
  local mem = r.GetExtState(M.SEC, "PROG_ETA")
  local k0, p0, t0 = mem:match("^(.-)|([%d%.]+)|([%d%.]+)$")
  if k0 ~= chave or not p0 or not t0 or p + 0.002 < (tonumber(p0) or 0) then
    r.SetExtState(M.SEC, "PROG_ETA", string.format("%s|%.4f|%.3f", chave, p, agora), false)
    return nil
  end
  p0, t0 = tonumber(p0) or 0, tonumber(t0) or agora
  local dt, dp = agora - t0, p - p0
  if dt < 5 or dp < 0.02 then return nil end
  local eta = M.fmt_tempo_restante((1 - p) / (dp / dt))
  if dt > 25 then
    r.SetExtState(M.SEC, "PROG_ETA", string.format("%s|%.4f|%.3f", chave, p, agora), false)
  end
  return eta
end

local function montar_info_prog(tipo, nome, prog, opts)
  opts = opts or {}
  prog = math.max(0, math.min(1, tonumber(prog) or 0))
  local pct = math.floor(prog * 100 + 0.5)
  if pct > 100 then pct = 100 end
  nome = trim(nome or "")
  local info = {
    tipo = tipo, nome = nome, prog = prog, pct = pct,
    pronto = opts.pronto and true or false,
    pode_cancelar = opts.pode_cancelar and true or false,
    fila_n = opts.fila_n, fila_total = opts.fila_total, eta = opts.eta,
    rapido = opts.rapido and true or false,
  }
  -- v1.8: etapa atual ("tom", "seções", "Carregando o modelo"...) para a barrinha
  local et = trim(tostring(opts.etapa or "")):gsub("%.%.%.$", ""):gsub("…$", "")
  if et ~= "" and not info.pronto then info.etapa = et end
  if info.pronto then
    info.frase = "Pronto ✓" .. (nome ~= "" and ("  " .. nome) or "")
    info.prog, info.pct = 1, 100
    return info
  end
  local acao = (tipo == "instalacao" and "Instalando")
    or (tipo == "analise" and "Analisando")
    or (info.rapido and "Separando (rápida)" or "Separando")
  if nome ~= "" then
    info.frase = string.format("%s: %s — %d%%", acao, nome, pct)
  else
    info.frase = string.format("%s — %d%%", acao, pct)
  end
  if opts.fila_n and opts.fila_total and opts.fila_total > 1 then
    info.fila = string.format("%d de %d", opts.fila_n, opts.fila_total)
  end
  return info
end

local function pedidos_ext_sep()
  local lista, i = {}, 0
  while true do
    local ok, k, v = r.EnumProjExtState(0, SEC_SEP, i)
    if not ok or not k or k == "" then break end
    i = i + 1
    if v and v ~= "" then
      local partes, i2 = {}, 0
      for x in (v .. "|"):gmatch("([^|]*)|") do
        i2 = i2 + 1
        partes[i2] = x
      end
      local estado, nome, entrada, canal, inicio, modo = partes[1], partes[2], partes[3], partes[4], partes[5], partes[6]
      lista[#lista + 1] = {
        saida = k, v = v, estado = estado, nome = nome, entrada = entrada,
        canal = canal, inicio = inicio,
        rapido = (modo == "rapido" or modo == "1"),
      }
    end
  end
  return lista
end

local function ler_pedido_motor(arq)
  local f = io.open(arq, "r")
  if not f then return nil end
  local t = {}
  for linha in f:lines() do
    local k, v = linha:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k then t[k:lower()] = v end
  end
  f:close()
  if not t.saida or t.saida == "" then return nil end
  return t
end

-- Reencontra uma separação que já estava rodando (pythonw) quando o painel
-- reabriu no F9: lê __stems/status.txt das músicas do projeto e os pedidos do motor.
-- NÃO lança outro processo — só registra o que já está em andamento.
function M.resgatar_separacao_ativa()
  local lista = pedidos_ext_sep()
  for _, p in ipairs(lista) do
    if p.estado == "RODANDO" then
      local est, prog = ler_status(p.saida .. SEP .. "status.txt")
      if est == "PROG" or est == "OK" or est == "ERRO" then return p, est, prog end
      return p, "PROG", 0
    end
  end
  local achados = {}
  local function considera(saida, nome, entrada, canal, inicio, rapido)
    if not saida or saida == "" then return end
    local chave = chave_caminho(saida)
    if achados[chave] then return end
    local est, prog, txt = ler_status(saida .. SEP .. "status.txt")
    if est == "PROG" then
      if txt and txt:find("rápida", 1, true) then rapido = true end
      achados[chave] = true
      r.SetProjExtState(0, SEC_SEP, saida, table.concat({
        "RODANDO", nome or "Música", entrada or "", canal or "ambos", inicio or "",
        rapido and "rapido" or "normal",
      }, "|"))
      return { saida = saida, nome = nome or "Música", estado = "RODANDO",
        entrada = entrada, canal = canal, inicio = inicio, rapido = rapido and true or false }, est, prog, txt
    end
  end
  -- 1) pedidos do motor (arquivo do pythonw em andamento)
  local ped = M.motor_dir() .. SEP .. "pedidos"
  if existe_pasta(ped) then
    r.EnumerateFiles(ped, -1)
    local i = 0
    while true do
      local f = r.EnumerateFiles(ped, i)
      if not f then break end
      i = i + 1
      if f:find("^pedido_") and f:lower():find("%.txt$") then
        local pedi = ler_pedido_motor(ped .. SEP .. f)
        if pedi then
          local nome = (pedi.entrada or ""):match("([^\\/]+)$") or "Música"
          nome = nome:gsub("%.[^%.]+$", "")
          local rap_ped = (pedi.rapido or ""):lower()
          rap_ped = (rap_ped == "1" or rap_ped == "sim" or rap_ped == "true" or rap_ped == "rapido")
          local hit, est, prog = considera(pedi.saida, nome, pedi.entrada, pedi.canal or "ambos", "", rap_ped)
          if hit then return hit, est, prog end
        end
      end
    end
  end
  -- 2) __stems/status.txt das músicas que estão no projeto
  if M.get_musicas then
    for _, m in ipairs(M.get_musicas()) do
      local pasta = M.pasta_da_musica and M.pasta_da_musica(m)
      if pasta and pasta ~= "" then
        local hit, est, prog = considera(pasta .. SEP .. M.PASTA_STEMS, m.nome, "", "ambos",
          m.inicio and string.format("%.3f", m.inicio) or "")
        if hit then return hit, est, prog end
      end
    end
  end
  return nil
end

local function info_separacao_atual()
  local p, est, prog = M.resgatar_separacao_ativa()
  local fila_n, fila_total
  local lista = pedidos_ext_sep()
  local nfila = 0
  for _, q in ipairs(lista) do if q.estado == "FILA" then nfila = nfila + 1 end end
  if p and (est == "PROG" or (est == nil and p.estado == "RODANDO")) then
    prog = tonumber(prog) or 0
    if nfila > 0 then fila_n, fila_total = 1, nfila + 1 end
    local rap = p.rapido and true or false
    local txts
    if p.saida then
      txts = select(3, ler_status(p.saida .. SEP .. "status.txt"))
      if not rap and txts and txts:find("rápida", 1, true) then rap = true end
    end
    return montar_info_prog("separacao", p.nome, prog, {
      fila_n = fila_n, fila_total = fila_total,
      eta = eta_de_progresso(p.saida or p.nome, prog),
      rapido = rap, etapa = txts,
    })
  end
  return nil, p, est, nfila
end

local function texto_tem_rapida(txt)
  return txt and (txt:find("rápida", 1, true) or txt:find("%(rapida%)") or txt:find("Separando %(rápida%)")) and true or false
end

local function etapa_do_texto(txt)
  local e = txt and txt:match("%d+%%%s*·%s*(.-)%s*$")
  if not e then return nil end
  e = e:gsub("%s*%(%+%d+ na fila%)%s*$", "")
  return e ~= "" and e or nil
end

local function info_de_texto_status(txt, pode_cancelar)
  local function fecha(info)
    if info and not info.pronto and (info.tipo == "separacao") and texto_tem_rapida(txt) then
      info.rapido = true
      if info.frase then
        info.frase = info.frase:gsub("^Separando:", "Separando (rápida):"):gsub("^Separando —", "Separando (rápida) —")
      end
    end
    return info
  end

  if not txt or txt == "" then return nil end
  if txt:find("^Pronto") or txt:find("^Trilhas separadas") or txt:find("instalado") then
    local nome = txt:match("[Pp]ronto[:!]%s*(.-)%s*$") or txt:match("Trilhas separadas:%s*(.-)%s*$")
    return fecha(montar_info_prog("pronto", nome or "", 1, { pronto = true }))
  end
  if txt:find("[Ff]alhou") or txt:find("^Não deu") then return nil end
  local i, n, nome, pct = txt:match("^Importando (%d+) de (%d+):%s*(.-)%s+(%d+)%%")
  if i then
    return fecha(montar_info_prog("analise", nome, (tonumber(pct) or 0) / 100, {
      fila_n = tonumber(i), fila_total = tonumber(n), pode_cancelar = pode_cancelar,
      etapa = etapa_do_texto(txt),
    }))
  end
  i, n, nome = txt:match("^Importando (%d+) de (%d+):%s*(.-)%s*$")
  if i then
    -- "Importando 2 de 5: Nome  (separando trilhas...)"
    nome = (nome or ""):gsub("%s*%(.*%)%s*$", "")
    local sep, _, _ = info_separacao_atual()
    if sep then
      sep.fila_n, sep.fila_total = tonumber(i), tonumber(n)
      sep.fila = string.format("%d de %d", sep.fila_n, sep.fila_total)
      sep.pode_cancelar = pode_cancelar
      return fecha(sep)
    end
    return fecha(montar_info_prog("separacao", trim(nome), 0, {
      fila_n = tonumber(i), fila_total = tonumber(n), pode_cancelar = pode_cancelar,
    }))
  end
  local inst, rest = txt:match("^Instalando motor%s+(%d+)%%%s*:?%s*(.*)$")
  if inst then
    return fecha(montar_info_prog("instalacao", "motor de separação", (tonumber(inst) or 0) / 100, { etapa = rest }))
  end
  if txt:find("^Instalando") then
    return fecha(montar_info_prog("instalacao", "motor de separação", 0, {}))
  end
  nome, pct = txt:match("^Analisando%s+(.-)%s+(%d+)%%%s*")
  if nome then
    nome = nome:gsub("%s+%+%d+ na fila%s*$", "")
    return fecha(montar_info_prog("analise", nome, (tonumber(pct) or 0) / 100, {
      pode_cancelar = pode_cancelar, etapa = etapa_do_texto(txt),
    }))
  end
  nome, pct = txt:match("^Separando%s+(.-)%s+(%d+)%%%s*")
  if nome then
    nome = nome:gsub("%s+%+%d+ na fila%s*$", "")
    return fecha(montar_info_prog("separacao", trim(nome), (tonumber(pct) or 0) / 100, {
      pode_cancelar = pode_cancelar,
    }))
  end
  nome = txt:match("^Separando%s+(.-)%.%.%.") or txt:match("^Analisando%s+(.-)$")
  if nome then
    local tipo = txt:find("^Separando") and "separacao" or "analise"
    return fecha(montar_info_prog(tipo, trim(nome), 0, { pode_cancelar = pode_cancelar }))
  end
  return nil
end

-- Fonte única para a barrinha do painel: separação em andamento (status.txt),
-- análise, instalação do motor, ou "Pronto ✓" por alguns segundos.
function M.progresso_trabalho()
  local pode = M.pode_cancelar_fila_importacao and M.pode_cancelar_fila_importacao() or false
  local sep = info_separacao_atual()
  if sep then
    sep.pode_cancelar = pode
    return sep
  end
  local ana = M.analise_status and M.analise_status()
  -- analise_status cai na separação se a análise já expirou; preferimos o texto cru
  local cru = r.GetExtState(M.SEC, "ANALISE_STATUS")
  local txt_a, t_a = cru:match("^(.*)|([%d%.]+)$")
  if txt_a and r.time_precise() - (tonumber(t_a) or 0) < 3 then
    local info = info_de_texto_status(txt_a, pode)
    if info then
      if info.tipo == "analise" then
        info.eta = eta_de_progresso("analise:" .. (info.nome or ""), info.prog)
      end
      return info
    end
  end
  local inst = M.motor_instalando and M.motor_instalando()
  if inst then
    local est, p, tx = ler_status(M.motor_dir() .. SEP .. "instalacao.txt")
    if est == "PROG" then
      return montar_info_prog("instalacao", "motor de separação", p or 0,
        { eta = eta_de_progresso("motor", p or 0), etapa = tx })
    end
    local info = info_de_texto_status(M.separacao_status() or "Instalando o motor de separação...", false)
    return info or montar_info_prog("instalacao", "motor de separação", 0, {})
  end
  local txt_s = M.separacao_status and M.separacao_status()
  if txt_s then
    local info = info_de_texto_status(txt_s, pode)
    if info then return info end
  end
  if ana then
    return info_de_texto_status(ana, pode)
  end
  return nil
end

-- Pede a separação de uma música (região).
-- opcoes.silencioso = sem mensagens; opcoes.perguntar_instalar = oferece instalar o motor
function M.separar_musica(m, opcoes)
  opcoes = opcoes or {}
  local titulo = "Separar trilhas"
  if not m then return false, "nenhuma música" end
  local it = item_original(m)
  if not it then
    if not opcoes.silencioso then r.MB("Esta música não tem áudio na BANDA para separar.", titulo, 0) end
    return false, "sem áudio"
  end
  local tk = r.GetActiveTake(it)
  if not tk or r.TakeIsMIDI(tk) then return false, "o áudio principal não é um arquivo de áudio" end
  local entrada = r.GetMediaSourceFileName(r.GetMediaItemTake_Source(tk), "")
  if entrada == "" then return false, "não achei o arquivo de áudio" end
  local pasta = select(2, r.GetProjExtState(0, "MT_PASTA", M.norm(m.nome)))
  if pasta == "" then pasta = entrada:match("^(.*)[\\/][^\\/]+$") or "" end
  local saida = pasta .. SEP .. M.PASTA_STEMS
  -- VS com click num lado: separa só o lado da banda
  local _, lado_click = r.GetSetMediaItemInfo_String(it, "P_EXT:MT_CANAL", "", false)
  if lado_click == "" then
    local meta = M.ler_info(pasta) or {}
    lado_click = meta.CANAL_CLICK or ""
  end
  local canal = (lado_click == "L" and "R") or (lado_click == "R" and "L") or "ambos"
  -- já separada antes (mesmo arquivo)? só recoloca
  if stems_prontos(saida) then
    local f = io.open(saida .. SEP .. "separacao.txt", "r")
    local info = f and f:read("*a") or ""; if f then f:close() end
    local base = entrada:match("([^\\/]+)$") or entrada
    if info:find(base, 1, true) and not opcoes.refazer then
      local ok, n = M.inserir_stems(m, saida)
      if not opcoes.silencioso then
        M.aviso(ok and ("Trilhas separadas recolocadas: " .. m.nome) or ("Erro: " .. tostring(n)))
      end
      return ok, "recolocadas"
    end
  end
  local atual = select(2, r.GetProjExtState(0, SEC_SEP, saida))
  if atual ~= "" then
    if not opcoes.silencioso then M.aviso(m.nome .. " já está sendo separada...") end
    return true, "já na fila"
  end
  if not M.motor_instalado() then
    if M.motor_instalando() then
      r.SetProjExtState(0, SEC_SEP, saida, table.concat({ "FILA", m.nome, entrada, canal, string.format("%.3f", m.inicio) }, "|"))
      M.garantir_poll_separacao()
      return true, "na fila (instalando o motor)"
    end
    if opcoes.silencioso and not opcoes.perguntar_instalar then return false, "motor não instalado" end
    if M.get("SEP_NAO_PERGUNTAR", "0") == "1" and opcoes.automatico then return false, "motor não instalado" end
    local resp = r.MB("Para separar BATERIA, BAIXO, GUITARRA, TECLADO, VOZ e OUTROS é preciso instalar o motor de separação " ..
      "(uma vez só, ~1 GB de download).\n\nInstalar agora?\n\n" ..
      "Sim = instalar e separar \"" .. m.nome .. "\" no fim\nNão = agora não" ..
      (opcoes.automatico and "\nCancelar = não perguntar mais ao importar" or ""),
      titulo, opcoes.automatico and 3 or 4)
    if resp == 2 then M.set("SEP_NAO_PERGUNTAR", "1"); return false, "não perguntar" end
    if resp ~= 6 then return false, "não instalado" end
    r.SetProjExtState(0, SEC_SEP, saida, table.concat({ "FILA", m.nome, entrada, canal, string.format("%.3f", m.inicio) }, "|"))
    M.instalar_motor(true)
    return true, "instalando o motor"
  end
  r.SetProjExtState(0, SEC_SEP, saida, table.concat({ "FILA", m.nome, entrada, canal, string.format("%.3f", m.inicio) }, "|"))
  M.verificar_separacoes()
  M.garantir_poll_separacao()
  if not opcoes.silencioso then
    M.aviso("Separando " .. m.nome .. " (bateria, baixo, guitarra, teclado, voz, outros)... aviso ao terminar")
  end
  return true, "separando"
end

-- Menu: "Separar trilhas (bateria, baixo, guitarra, teclado, voz)" na música atual
-- Salva o projeto atual (botão SALVAR do painel / Ctrl+S). Grava tudo o que está
-- no projeto: fórmula identificada (mapa de tempo), click/guia gerados, setlist,
-- trilhas. Projeto sem nome ainda: abre o "Salvar como" do REAPER.
-- Devolve ok, mensagem.
function M.salvar_projeto()
  local _, antes = r.EnumProjects(-1, "")
  local sem_nome = (antes or "") == ""
  if sem_nome then
    r.Main_OnCommand(40022, 0) -- File: Save project as...
  else
    r.Main_SaveProject(0, false)
  end
  local _, depois_fn = r.EnumProjects(-1, "")
  if (depois_fn or "") == "" then return false, "Projeto não foi salvo (cancelado)" end
  if r.IsProjectDirty and r.IsProjectDirty(0) ~= 0 then return false, "Projeto não foi salvo" end
  return true, "Projeto salvo"
end

function M.separar_musica_atual()
  local m = M.musica_atual()
  if not m then return M.aviso("Nenhuma música no projeto") end
  local pasta = select(2, r.GetProjExtState(0, "MT_PASTA", M.norm(m.nome)))
  local saida = pasta ~= "" and (pasta .. SEP .. M.PASTA_STEMS) or nil
  if saida and stems_prontos(saida) then
    local resp = r.MB(m.nome .. " já foi separada antes.\n\nSim = separar de novo\nNão = só recolocar as trilhas salvas",
      "Separar trilhas", 3)
    if resp == 2 then return end
    return M.separar_musica(m, { refazer = (resp == 6) })
  end
  return M.separar_musica(m, {})
end

-- Desfaz: apaga as trilhas separadas desta música e desmuta a original
function M.desfazer_separacao()
  local m = M.musica_atual()
  if not m then return M.aviso("Nenhuma música no projeto") end
  r.Undo_BeginBlock()
  local n = 0
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    for k = r.GetTrackNumMediaItems(tr) - 1, 0, -1 do
      local x = r.GetTrackMediaItem(tr, k)
      local p = r.GetMediaItemInfo_Value(x, "D_POSITION")
      if p >= m.inicio - 0.01 and p < m.fim then
        local _, st = r.GetSetMediaItemInfo_String(x, "P_EXT:MT_STEM", "", false)
        local _, og = r.GetSetMediaItemInfo_String(x, "P_EXT:MT_ORIGINAL", "", false)
        if st == "1" then r.DeleteTrackMediaItem(tr, x); n = n + 1
        elseif og == "1" then r.SetMediaItemInfo_Value(x, "B_MUTE", 0) end
      end
    end
  end
  r.Undo_EndBlock("Voltar para a música original: " .. m.nome, -1)
  r.UpdateArrange()
  M.aviso(n > 0 and ("Voltou para a música original: " .. m.nome) or "Esta música não tem trilhas separadas")
end

-- ---------- música solta (um arquivo) ----------
local function copiar_arquivo(a, b)
  local fa = io.open(a, "rb")
  if not fa then return false end
  local fb = io.open(b, "wb")
  if not fb then fa:close(); return false end
  while true do
    local bloco = fa:read(1048576)
    if not bloco then break end
    fb:write(bloco)
  end
  fa:close(); fb:close()
  return true
end

-- Importa uma pasta com 12 pads (C, C#, D… ou C-PAD.mp3, Pad G.wav, D#.flac)
-- para Biblioteca\_PADS\Pad contínuo e deixa esse pacote como o atual.
function M.importar_pasta_pads(pasta)
  if not pasta or pasta == "" then
    local ultima = M.pasta_pads_raiz()
    if r.JS_Dialog_BrowseForFolder then
      local ret, p = r.JS_Dialog_BrowseForFolder(
        "Escolha a pasta com os pads (um arquivo por tom: C-PAD.mp3, Pad G.wav, D#.flac…)", ultima)
      if ret ~= 1 or not p or p == "" then return false end
      pasta = p
    else
      local ok, arq = r.GetUserFileNameForRead(ultima,
        "Escolha qualquer arquivo de pad dentro da pasta (C-PAD, Pad G, D#…)", M.EH_MAC and "" or "*.*")
      if not ok or not arq or arq == "" then return false end
      pasta = pai_de(arq) or arq
    end
  end
  pasta = (pasta:gsub("[\\/]+$", ""))
  local lista = pads_da_pasta(pasta, true)
  local por = {}
  for _, p in ipairs(lista) do
    if not por[p.semi] then por[p.semi] = p end
  end
  local n = 0
  for _ in pairs(por) do n = n + 1 end
  if n == 0 then
    r.MB("Não achei arquivos de pad com o tom no nome.\n\nExemplos: C-PAD.mp3, Pad G.wav, D#.flac, A#-PAD.mp3.",
      "Importar pasta de pads", 0)
    return false, "nenhum tom reconhecido"
  end
  local dest = M.garantir_pasta_pads() .. SEP .. (M.PACOTE_PAD_CONTINUO or "Pad contínuo")
  r.RecursiveCreateDirectory(dest, 0)
  local copiados, falhas = 0, {}
  for semi, p in pairs(por) do
    local ext = (p.arq:match("%.([^%.]+)$") or "wav"):lower()
    local nome = "Pad " .. M.nome_tom(semi) .. "." .. ext
    if copiar_arquivo(p.arq, dest .. SEP .. nome) then
      copiados = copiados + 1
    else
      falhas[#falhas + 1] = nome
    end
  end
  M.recarregar_pads()
  M.definir_pacote_pads(M.PACOTE_PAD_CONTINUO or "Pad contínuo")
  local msg = string.format("Pronto! Copiei %d tons para o pacote \"%s\" (o original não foi mexido).\n\n"
    .. "Este é o pad padrão. O item cobre a música inteira, em loop, com fade.",
    copiados, M.PACOTE_PAD_CONTINUO or "Pad contínuo")
  if n < 12 then
    msg = msg .. string.format("\n\nAtenção: só encontrei %d de 12 tons. Os que faltarem usam outro pacote ou o Pad clássico.", n)
  end
  if #falhas > 0 then msg = msg .. "\n\nNão copiei: " .. table.concat(falhas, ", ") end
  r.MB(msg, "Importar pasta de pads", 0)
  return copiados > 0, dest, copiados
end

-- Duração e taxa de amostragem de um arquivo (via PCM source do REAPER).
function M.info_audio_arquivo(caminho)
  if not caminho or caminho == "" or not r.PCM_Source_CreateFromFile then return nil end
  local src = r.PCM_Source_CreateFromFile(caminho)
  if not src then return nil end
  local len = r.GetMediaSourceLength(src)
  len = tonumber(len) or 0
  local sr = 0
  if r.GetMediaSourceSampleRate then
    local s = r.GetMediaSourceSampleRate(src)
    sr = tonumber(s) or 0
  end
  if len <= 0 then return nil end
  return { duracao = len, sr = sr }
end

-- Tolerância (segundos): stems da mesma música quase sempre cabem nisso.
M.TOLERANCIA_DURACAO_STEMS = 6

-- A pasta é um PACOTE DE STEMS / uma multitrack (e não um monte de músicas completas)?
-- Critérios: projeto Ableton (.als), subpasta MultiTracks/Stems, OU os arquivos
-- parecem stems (nomes típicos) com duração parecida e a mesma sample rate.
-- mt_info.txt sozinho NÃO basta (o kit escreve essa ficha sozinho).
function M.pasta_parece_multitrack(pasta)
  if not pasta or pasta == "" then return false end
  pasta = pasta:gsub("[\\/]+$", "")
  -- NÃO confiar só na existência de mt_info.txt: o kit grava essa ficha
  -- até em pasta de músicas completas (ex.: Documentos/Multitracks\\MUSICAS
  -- DO CASAMENTO). Só um TIPO=STEMS (ou MULTITRACK=1) conta, e ainda assim
  -- os arquivos têm que parecer stems (abaixo). Sem isso, a ficha é ignorada.
  local meta_ficha = M.ler_info(pasta)
  local ficha_pede_stems = meta_ficha and (
    (meta_ficha.TIPO or ""):upper() == "STEMS"
    or (meta_ficha.MULTITRACK or "") == "1"
  )
  -- v1.8: escolha EXPLÍCITA no + IMPORTAR (Multitrack / Música) vale sempre
  local como = meta_ficha and (meta_ficha.IMPORTAR_COMO or ""):upper() or ""
  if como == "MULTITRACK" then return true end
  if como == "MUSICAS" then return false end
  local audios, _, als = listar_arquivos(pasta)
  if als and #als > 0 then return true end
  local nome_aqui = pasta:match("([^\\/]+)$") or ""
  if NOMES_SUBPASTA_STEMS[M.norm(nome_aqui)] and audios and #audios >= 2 then return true end
  if achar_sub_stems(pasta) then return true end
  local lista = audios
  if not lista or #lista < 2 then
    lista = coletar_audios(pasta, 3)
  end
  if not lista or #lista < 2 then return false end
  local n, n_stem, n_click = #lista, 0, 0
  local durs, srs = {}, {}
  for _, f in ipairs(lista) do
    local nome = f:match("([^\\/]+)$") or f
    if M.nome_parece_stem(nome) then
      n_stem = n_stem + 1
      local dest = M.classificar_stem(nome)
      if dest == "CLICK" or dest == "GUIA" then n_click = n_click + 1 end
    end
    local inf = M.info_audio_arquivo(pasta .. SEP .. f)
    if inf then
      durs[#durs + 1] = inf.duracao
      if inf.sr and inf.sr > 0 then srs[#srs + 1] = inf.sr end
    end
  end
  local maioria = n_stem >= 2 and n_stem >= math.ceil(n * 0.5)
  local vs_com_click = n_click >= 1 and n <= 4 and n_stem >= 1
  -- Ficha antiga ou TIPO=STEMS sem os arquivos parecerem stems: não é multitrack.
  if not maioria and not vs_com_click then return false end
  if #durs >= 2 then
    local mn, mx = durs[1], durs[1]
    for _, d in ipairs(durs) do
      if d < mn then mn = d end
      if d > mx then mx = d end
    end
    if (mx - mn) > (M.TOLERANCIA_DURACAO_STEMS or 6) then return false end
  end
  if #srs >= 2 then
    local sr0 = srs[1]
    for _, s in ipairs(srs) do if s ~= sr0 then return false end end
  end
  -- Chegou aqui pelos arquivos (nomes + duração + sample rate).
  -- A ficha antiga é ignorada; ficha_pede_stems não atropela este resultado.
  return true
end

-- O arquivo escolhido/solto é uma música avulsa (e não um stem de multitrack)?
-- Se a pasta NÃO parece um pacote de stems, importa SÓ este arquivo — nunca os irmãos.
function M.eh_musica_solta(arq)
  local ext = (arq:match("%.([^%.\\/]+)$") or ""):lower()
  if not EXT_AUDIO[ext] then return false end
  local pasta = pai_de(arq)
  if not pasta then return true end
  return not M.pasta_parece_multitrack(pasta)
end

function M.importar_arquivo(arq, opcoes)
  local base = (arq:match("([^\\/]+)$") or "Música"):gsub("%.[^%.]+$", "")
  local nome, tom = M.detectar_tom_bpm(base)
  local bib = M.garantir_biblioteca()
  local destino = bib .. SEP .. M.nome_pasta_musica(nome, nil, tom)
  local nome_arq = arq:match("([^\\/]+)$")
  if not (existe_pasta(destino) and r.file_exists(destino .. SEP .. nome_arq)) then
    local k = 2
    local d0 = destino
    while existe_pasta(destino) do destino = d0 .. " (" .. k .. ")"; k = k + 1 end
    r.RecursiveCreateDirectory(destino, 0)
    if not copiar_arquivo(arq, destino .. SEP .. nome_arq) then
      local msg = "Não consegui copiar para a Biblioteca:\n" .. arq
      if not (opcoes and opcoes.silencioso) then r.MB(msg, "Importar música", 0) end
      return false, msg
    end
  end
  return M.importar_rapido(destino, opcoes)
end

-------------------------------------------------------------------------------
-- MOTOR AO VIVO (AUTO / HOLD / LOOP que acompanha)
-------------------------------------------------------------------------------
--[[
  Regras no fim de cada música (enquanto toca):
    HOLD ligado  -> para e volta para o INÍCIO DA MESMA música (tem prioridade)
    AUTO ligado  -> pula o intervalo e já toca a PRÓXIMA música
    nenhum dos 2 -> para e deixa o cursor no início da PRÓXIMA (pronto pro play)
  LOOP / REPETIR CLICK: usa o loop nativo do REAPER (sem falhas); se você pular
  para outra seção, o loop passa a ser a nova seção.
]]
local estado_motor = { ultimo_pos = nil, ultimo_sync = 0 }

function M.motor_ativo()
  local hb = tonumber(r.GetExtState(M.SEC, "MOTOR_HB")) or 0
  return (r.time_precise() - hb) < 1.0
end

function M.alerta_motor()
  if M.motor_ativo() then return "" end
  return "\n(atenção: motor_ao_vivo.lua não está rodando)"
end

function M.tick()
  local ok, err = xpcall(M._tick, debug.traceback)
  if not ok then M.registrar_erro("tick", err) end
end

function M._tick()
  local agora = r.time_precise()
  M.conferir_separacoes_tick()
  if agora - estado_motor.ultimo_sync > 0.5 then
    estado_motor.ultimo_sync = agora
    M.sincronizar_botoes()
    M.verificar_saidas()
    M.verificar_guia_auto()
    M.verificar_marcadores_auto()
    pcall(M.tick_capas)
    -- PAD: ao trocar de música (ou a cada 3 s) confere se o pad é o do tom/pacote certo
    local m = M.musica_atual()
    if m and m.tom and (m.n ~= estado_motor.pad_musica or agora - (estado_motor.pad_t or 0) > 3) then
      estado_motor.pad_musica, estado_motor.pad_t = m.n, agora
      M.conferir_pad(m)
    end
  end
  if not M.tocando() then estado_motor.ultimo_pos = nil; return end
  local pos = r.GetPlayPosition()
  local ant = estado_motor.ultimo_pos
  estado_motor.ultimo_pos = pos
  if not ant then return end

  local loop_on = (M.flag("LOOP") or M.flag("REPETIR_CLICK")) and r.GetSetRepeat(-1) == 1
  if loop_on then
    local ls, le = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
    if pos < ls - 0.05 or pos > le + 0.05 then
      local m = M.musica_atual(pos)
      if m then
        local sec = M.secao_atual(pos, M.secoes_da_musica(m))
        M.definir_loop(sec.inicio, sec.fim)
      end
    end
    return
  end

  local dif = pos - ant
  if dif <= 0 or dif > 0.75 then return end -- pulo manual, não é fim natural
  local musicas = M.get_musicas()
  for i, m in ipairs(musicas) do
    if ant < m.fim - M.CFG.FIM_EPS and pos >= m.fim - M.CFG.FIM_EPS then
      local prox = musicas[i + 1]
      if M.flag("HOLD") then
        r.OnStopButton()
        r.SetEditCurPos(m.inicio, true, false)
      elseif M.flag("AUTO") then
        if prox then
          if prox.inicio - pos > 0.05 then r.SetEditCurPos(prox.inicio, true, true) end
        else
          r.OnStopButton()
        end
      else
        r.OnStopButton()
        r.SetEditCurPos(prox and prox.inicio or m.inicio, true, false)
      end
      estado_motor.ultimo_pos = nil
      break
    end
  end
end

-- Usado pelo painel: roda o motor só se o motor_ao_vivo.lua não estiver ativo

-------------------------------------------------------------------------------
-- LIMPAR ARQUIVOS gerados pelo kit que não estão em uso neste projeto
-------------------------------------------------------------------------------
-- Só mexe em: click_gerado\ (click_*.wav e picos), pastas __stems de músicas
-- que não estão no setlist, e pedidos temporários do motor. Nunca apaga o
-- original da música, guia_voz, pads, scripts, o motor instalado, nem nada
-- que um item deste projeto esteja usando.

local function chave_eq_ou_dentro(caminho, raiz)
  local c, z = chave_caminho(caminho), chave_caminho(raiz)
  return c == z or c:sub(1, #z + 1) == z .. "/"
end

local function tamanho_arquivo(p)
  local f = io.open(p, "rb")
  if not f then return 0 end
  local n = f:seek("end") or 0
  f:close()
  return n
end

local function listar_nomes(pasta, pastas)
  if not pasta or pasta == "" then return {} end
  if pastas then r.EnumerateSubdirectories(pasta, -1) else r.EnumerateFiles(pasta, -1) end
  local t, i = {}, 0
  while true do
    local n = pastas and r.EnumerateSubdirectories(pasta, i) or r.EnumerateFiles(pasta, i)
    if not n then break end
    t[#t + 1] = n
    i = i + 1
  end
  return t
end

local function tamanho_pasta(pasta)
  local n = 0
  for _, f in ipairs(listar_nomes(pasta, false)) do n = n + tamanho_arquivo(pasta .. SEP .. f) end
  for _, d in ipairs(listar_nomes(pasta, true)) do n = n + tamanho_pasta(pasta .. SEP .. d) end
  return n
end

local function apagar_arvore(pasta)
  for _, f in ipairs(listar_nomes(pasta, false)) do os.remove(pasta .. SEP .. f) end
  for _, d in ipairs(listar_nomes(pasta, true)) do apagar_arvore(pasta .. SEP .. d) end
  os.remove(pasta)
  if existe_pasta(pasta) then
    if M.EH_WIN then r.ExecProcess('cmd.exe /c rmdir /s /q "' .. pasta .. '"', 8000)
    else os.execute('rm -rf "' .. pasta:gsub('"', '\\"') .. '"') end
  end
  return not existe_pasta(pasta)
end

function M.pasta_click_gerado()
  return (M.DIR or "") .. "click_gerado"
end

function M.arquivos_fonte_gerados(tr, ini, fim, tipo)
  local t = {}
  for _, it in ipairs(itens_no_intervalo(tr, ini, fim)) do
    if (not tipo) or tipo_gerado(it) == tipo then
      local tk = r.GetActiveTake(it)
      local src = tk and r.GetMediaItemTake_Source(tk)
      local arq = src and (r.GetMediaSourceFileName(src, "") or "") or ""
      if arq ~= "" then t[#t + 1] = arq end
    end
  end
  return t
end

local function arquivos_usados_no_projeto()
  -- files: caminhos exatos dos itens. dirs: pastas de música / __stems em uso
  -- (NÃO marca click_gerado inteiro — senão um click usado protegeria os antigos).
  local uso = { files = {}, dirs = {} }
  local function marca_dir(p)
    if p and p ~= "" then uso.dirs[chave_caminho(p)] = true end
  end
  local function marca_arq(arq)
    uso.files[chave_caminho(arq)] = true
    local dir = arq:match("^(.*)[\\/][^\\/]+$")
    if not dir then return end
    if M.norm(dir:match("([^\\/]+)$") or "") == M.norm(M.PASTA_STEMS) then
      marca_dir(dir)
      marca_dir(dir:match("^(.*)[\\/][^\\/]+$"))
    elseif M.na_biblioteca and M.na_biblioteca(dir) then
      marca_dir(dir)
    end
  end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
      local it = r.GetTrackMediaItem(tr, k)
      local tk = r.GetActiveTake(it)
      local src = tk and r.GetMediaItemTake_Source(tk)
      local arq = src and (r.GetMediaSourceFileName(src, "") or "") or ""
      if arq ~= "" then marca_arq(arq) end
    end
  end
  if M.get_musicas then
    for _, m in ipairs(M.get_musicas()) do
      local pasta = select(2, r.GetProjExtState(0, "MT_PASTA", M.norm(m.nome)))
      if pasta and pasta ~= "" then marca_dir(pasta) end
    end
  end
  return uso
end

local function caminho_em_uso(caminho, uso)
  local c = chave_caminho(caminho)
  if uso.files and uso.files[c] then return true end
  if uso.dirs then
    for p in pairs(uso.dirs) do
      if c == p or c:sub(1, #p + 1) == p .. "/" then return true end
    end
  end
  return false
end

-- Só caminhos gerados pelo kit, em pastas conhecidas, com nome esperado.
function M.caminho_seguro_para_apagar(caminho, eh_pasta)
  if not caminho or caminho == "" then return false end
  local nome = caminho:match("([^\\/]+)$") or ""
  local click_dir = M.pasta_click_gerado()
  if chave_eq_ou_dentro(caminho, click_dir) and chave_caminho(caminho) ~= chave_caminho(click_dir) then
    local low = nome:lower()
    if eh_pasta then return low == "peaks" end
    if low:match("^click[_%-].+%.wav$") then return true end
    if low:match("%.reapeaks$") and low:match("click") then return true end
    return false
  end
  if eh_pasta and M.norm(nome) == M.norm(M.PASTA_STEMS) then
    local pai = caminho:match("^(.*)[\\/][^\\/]+$")
    local bib = M.pasta_biblioteca()
    if pai and chave_eq_ou_dentro(pai, bib) and chave_caminho(pai) ~= chave_caminho(bib) then
      return true
    end
    return false
  end
  local pedidos = M.motor_dir() .. SEP .. "pedidos"
  if chave_eq_ou_dentro(caminho, pedidos) and chave_caminho(caminho) ~= chave_caminho(pedidos) then
    return (nome:lower():match("^pedido_.*%.txt$") ~= nil) and not eh_pasta
  end
  return false
end

local function fmt_mb(n)
  if n >= 1024 * 1024 then return string.format("%.1f MB", n / (1024 * 1024)) end
  if n >= 1024 then return string.format("%.0f KB", n / 1024) end
  return string.format("%d bytes", n)
end

function M.listar_lixo()
  local uso = arquivos_usados_no_projeto()
  local itens, bytes = {}, 0
  local function add(caminho, tipo, rotulo, eh_pasta, extra)
    if not M.caminho_seguro_para_apagar(caminho, eh_pasta) then return end
    if caminho_em_uso(caminho, uso) then return end
    local n = eh_pasta and tamanho_pasta(caminho) or tamanho_arquivo(caminho)
    if extra then n = n + extra end
    itens[#itens + 1] = { caminho = caminho, tipo = tipo, rotulo = rotulo, bytes = n, pasta = eh_pasta and true or false }
    bytes = bytes + n
  end

  -- clicks antigos (e o arquivo de pico ao lado, se houver)
  local cdir = M.pasta_click_gerado()
  for _, f in ipairs(listar_nomes(cdir, false)) do
    local arq = cdir .. SEP .. f
    local pico = cdir .. SEP .. "peaks" .. SEP .. f .. ".reapeaks"
    local extra = r.file_exists(pico) and tamanho_arquivo(pico) or 0
    add(arq, "click", f, false, extra)
  end

  -- __stems de músicas da biblioteca que não estão neste projeto
  local bib = M.pasta_biblioteca()
  for _, d in ipairs(listar_nomes(bib, true)) do
    if d ~= M.PASTA_PADS and d:sub(1, 1) ~= "." then
      local stems = bib .. SEP .. d .. SEP .. M.PASTA_STEMS
      if existe_pasta(stems) then
        add(stems, "stems", d, true, 0)
      end
    end
  end

  -- pedidos temporários do motor (se não há separação andando)
  if not (M.separacao_status and M.separacao_status()) then
    local ped = M.motor_dir() .. SEP .. "pedidos"
    for _, f in ipairs(listar_nomes(ped, false)) do
      add(ped .. SEP .. f, "temp", f, false, 0)
    end
  end

  local n_click, n_stems, n_temp, b_click, b_stems, b_temp = 0, 0, 0, 0, 0, 0
  for _, it in ipairs(itens) do
    if it.tipo == "click" then n_click = n_click + 1; b_click = b_click + it.bytes
    elseif it.tipo == "stems" then n_stems = n_stems + 1; b_stems = b_stems + it.bytes
    else n_temp = n_temp + 1; b_temp = b_temp + it.bytes end
  end
  return {
    itens = itens, bytes = bytes, qtd = #itens,
    n_click = n_click, n_stems = n_stems, n_temp = n_temp,
    b_click = b_click, b_stems = b_stems, b_temp = b_temp,
    fmt_mb = fmt_mb,
  }
end

local function enviar_para_lixeira(caminho, eh_pasta)
  if not caminho or caminho == "" then return false end
  if not M.caminho_seguro_para_apagar(caminho, eh_pasta) then return false end
  local ok = false
  if M.EH_WIN then
    local api = eh_pasta and "DeleteDirectory" or "DeleteFile"
    local ps = caminho:gsub("'", "''")
    local cmd = 'powershell.exe -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::' ..
      api .. "('" .. ps .. "', 2, 1)\""
    r.ExecProcess(cmd, 20000)
    ok = eh_pasta and (not existe_pasta(caminho)) or (not r.file_exists(caminho))
  elseif M.EH_MAC then
    local posix = caminho:gsub("\\", "\\\\"):gsub('"', '\\"')
    r.ExecProcess('/usr/bin/osascript -e "tell application \\"Finder\\" to delete POSIX file \\"' .. posix .. '\\""', 20000)
    ok = eh_pasta and (not existe_pasta(caminho)) or (not r.file_exists(caminho))
  end
  if not ok then
    if eh_pasta then ok = apagar_arvore(caminho)
    else ok = (os.remove(caminho) and true) or (not r.file_exists(caminho)) end
  end
  return ok
end

local function apagar_pico_do_click(arq)
  local nome = arq:match("([^\\/]+)$") or ""
  local dir = arq:match("^(.*)[\\/][^\\/]+$") or ""
  local pico = dir .. SEP .. "peaks" .. SEP .. nome .. ".reapeaks"
  if r.file_exists(pico) and M.caminho_seguro_para_apagar(pico, false) then
    enviar_para_lixeira(pico, false)
  end
end

function M.soltar_clicks_antigos(lista, manter)
  if not lista then return end
  local uso = arquivos_usados_no_projeto()
  if manter then uso.files[chave_caminho(manter)] = true end
  for _, arq in ipairs(lista) do
    local nome = (arq:match("([^\\/]+)$") or ""):lower()
    if nome:match("^click_var_.*%.wav$") and M.caminho_seguro_para_apagar(arq, false) and not caminho_em_uso(arq, uso) then
      enviar_para_lixeira(arq, false)
      apagar_pico_do_click(arq)
    end
  end
end

function M.apagar_lixo(rel)
  rel = rel or M.listar_lixo()
  local ok, falhou, bytes = 0, 0, 0
  for _, it in ipairs(rel.itens) do
    if M.caminho_seguro_para_apagar(it.caminho, it.pasta) then
      local deu = enviar_para_lixeira(it.caminho, it.pasta)
      if deu and it.tipo == "click" then apagar_pico_do_click(it.caminho) end
      if deu then ok = ok + 1; bytes = bytes + (it.bytes or 0) else falhou = falhou + 1 end
    else
      falhou = falhou + 1
    end
  end
  return ok, falhou, bytes
end

function M.limpar_arquivos()
  local rel = M.listar_lixo()
  if rel.qtd == 0 then
    r.MB("Nada para limpar.\n\nSó apago arquivos que o próprio kit gerou e que não estão em uso neste projeto:\n" ..
      "- clicks antigos (arquivos em click_gerado)\n" ..
      "- pastas __stems de músicas que não estão neste setlist\n" ..
      "- temporários do motor de separação\n\n" ..
      "O original das músicas e tudo que este projeto está usando não é apagado.",
      "Limpar arquivos", 0)
    return false, "vazio"
  end
  local linhas = { "Encontrei arquivos gerados pelo Mik Seifador que não estão em uso neste projeto:", "" }
  if rel.n_click > 0 then
    linhas[#linhas + 1] = rel.n_click == 1
      and ("  • 1 click antigo (" .. fmt_mb(rel.b_click) .. ")")
      or string.format("  • %d clicks antigos (%s)", rel.n_click, fmt_mb(rel.b_click))
  end
  if rel.n_stems > 0 then
    linhas[#linhas + 1] = rel.n_stems == 1
      and ("  • 1 pasta __stems de música fora do setlist (" .. fmt_mb(rel.b_stems) .. ")")
      or string.format("  • %d pastas __stems de músicas fora do setlist (%s)", rel.n_stems, fmt_mb(rel.b_stems))
    linhas[#linhas + 1] = "    (se a música voltar para o setlist, a separação roda de novo)"
  end
  if rel.n_temp > 0 then
    linhas[#linhas + 1] = rel.n_temp == 1
      and ("  • 1 temporário (" .. fmt_mb(rel.b_temp) .. ")")
      or string.format("  • %d temporários (%s)", rel.n_temp, fmt_mb(rel.b_temp))
  end
  linhas[#linhas + 1] = ""
  linhas[#linhas + 1] = string.format("Total: %d %s, %s.", rel.qtd, rel.qtd == 1 and "item" or "itens", fmt_mb(rel.bytes))
  linhas[#linhas + 1] = ""
  linhas[#linhas + 1] = "O original das músicas e tudo que está neste projeto NÃO será apagado."
  linhas[#linhas + 1] = "Os arquivos vão para a Lixeira (quando o sistema permitir)."
  linhas[#linhas + 1] = ""
  linhas[#linhas + 1] = "Enviar para a Lixeira agora?"
  linhas[#linhas + 1] = "Sim = limpar     Não = cancelar"
  if r.MB(table.concat(linhas, "\n"), "Limpar arquivos", 4) ~= 6 then return false, "cancelado" end
  local ok, falhou, bytes = M.apagar_lixo(rel)
  if falhou == 0 then
    r.MB((ok == 1 and ("Pronto! 1 item enviado para a Lixeira (" .. fmt_mb(bytes) .. " liberados).") or string.format("Pronto! %d itens enviados para a Lixeira (%s liberados).", ok, fmt_mb(bytes))), "Limpar arquivos", 0)
  else
    r.MB(string.format("Limpei %d %s (%s).\n%d não puderam ser apagados (arquivo aberto?).", ok, ok == 1 and "item" or "itens", fmt_mb(bytes), falhou), "Limpar arquivos", 0)
  end
  M.aviso(string.format("Limpeza: %d %s, %s", ok, ok == 1 and "item" or "itens", fmt_mb(bytes)))
  return true, ok, falhou, bytes
end


-------------------------------------------------------------------------------
-- APAGAR MÚSICAS (v1.6) + janela de escolha (lista com checkbox)
-------------------------------------------------------------------------------
-- O botão Limpar abre uma lista de todas as músicas que o kit conhece
-- (Biblioteca + setlist). Você marca quais apagar. Também dá para limpar
-- só o lixo gerado (clicks antigos, __stems órfãos, temporários).
-- Pastas compartilhadas (Downloads, Documentos, a raiz da Biblioteca...)
-- NUNCA são apagadas: nesses casos só saem os arquivos daquela música.

local SIDECARS_MUSICA = { "mt_info.txt", "cifra.txt", "marcadores.txt" }

local function nome_ultima(p)
  return (p or ""):match("([^\\/]+)$") or ""
end

local function pai_de_caminho(p)
  return (p or ""):match("^(.*)[\\/][^\\/]+$")
end

function M.fmt_mb(n)
  return fmt_mb(n or 0)
end

-- Pastas que nunca podem ser apagadas (raiz do usuário, Downloads, Biblioteca...).
function M.pasta_protegida(pasta)
  if not pasta or pasta == "" then return true end
  local c = chave_caminho(pasta)
  if c == "" or c == "/" or c:match("^%a:$") then return true end
  local function eq(p)
    return p and p ~= "" and chave_caminho(p) == c
  end
  local h = home()
  if eq(h) then return true end
  if eq(M.pasta_biblioteca()) then return true end
  if eq(M.DIR) or chave_eq_ou_dentro(M.DIR, pasta) then return true end
  if M.motor_dir and (eq(M.motor_dir()) or chave_eq_ou_dentro(M.motor_dir(), pasta)) then return true end
  if r.GetResourcePath and eq(r.GetResourcePath()) then return true end
  local conhecidas = {
    DOWNLOADS = true, DESKTOP = true, DOCUMENTS = true, DOCUMENTOS = true,
    ["AREA DE TRABALHO"] = true, MUSIC = true, MUSICAS = true, MUSICA = true,
    VIDEOS = true, PICTURES = true, IMAGENS = true, IMAGES = true,
    ONEDRIVE = true, DROPBOX = true, ["GOOGLE DRIVE"] = true, ICLOUD = true,
    APPLICATIVOS = true, APPS = true, PROGRAMS = true, ["PROGRAM FILES"] = true,
    WINDOWS = true, SYSTEM32 = true, APPDATA = true, ["APPLICATION SUPPORT"] = true,
    LIBRARY = true, USERS = true, USUARIOS = true, MULTITRACKS = true,
    _PADS = true, PADS = true,
  }
  -- nome conhecido (Downloads, Documentos, Desktop, Multitracks, _PADS...): nunca apagar a pasta inteira
  if conhecidas[M.norm(nome_ultima(pasta))] then return true end
  -- filho direto da home / OneDrive com nome conhecido já coberto; também
  -- protege "Área de Trabalho" etc. mesmo com acentuação no disco
  if h ~= "" then
    for _, sub in ipairs({ "Downloads", "Desktop", "Documents", "Documentos",
      "Music", "Música", "Musicas", "Pictures", "Imagens", "Videos", "Vídeos",
      "OneDrive", "Dropbox" }) do
      if eq(h .. SEP .. sub) then return true end
    end
  end
  return false
end

local function eh_pasta_do_kit_nao_musica(pasta)
  if not pasta then return true end
  if chave_eq_ou_dentro(pasta, M.pasta_click_gerado()) then return true end
  if chave_eq_ou_dentro(pasta, (M.DIR or "") .. "guia_voz") then return true end
  if chave_eq_ou_dentro(pasta, (M.DIR or "") .. "pads") then return true end
  if M.pasta_pads_raiz and chave_eq_ou_dentro(pasta, M.pasta_pads_raiz()) then return true end
  return false
end

function M.pasta_da_musica(m)
  if not m then return nil end
  local pasta = select(2, r.GetProjExtState(0, "MT_PASTA", M.norm(m.nome)))
  if pasta and pasta ~= "" then
    pasta = pasta:gsub("[\\/]+$", "")
    if M.norm(nome_ultima(pasta)) == M.norm(M.PASTA_STEMS) then pasta = pai_de_caminho(pasta) or pasta end
    if pasta ~= "" and not eh_pasta_do_kit_nao_musica(pasta) then return pasta end
  end
  local it = M.item_principal(m)
  if not it then return nil end
  local tk = r.GetActiveTake(it)
  local src = tk and r.GetMediaItemTake_Source(tk)
  local arq = src and (r.GetMediaSourceFileName(src, "") or "") or ""
  local dir = pai_de_caminho(arq)
  if dir and M.norm(nome_ultima(dir)) == M.norm(M.PASTA_STEMS) then dir = pai_de_caminho(dir) end
  if dir and dir ~= "" and not eh_pasta_do_kit_nao_musica(dir) then return dir end
  return nil
end

local function arquivos_sobrepostos_da_musica(m)
  local t = {}
  if not m then return t end
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    for k = 0, r.GetTrackNumMediaItems(tr) - 1 do
      local it = r.GetTrackMediaItem(tr, k)
      local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local l = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      if p < m.fim - 0.001 and p + l > m.inicio + 0.001 then
        local tk = r.GetActiveTake(it)
        local src = tk and r.GetMediaItemTake_Source(tk)
        local arq = src and (r.GetMediaSourceFileName(src, "") or "") or ""
        if arq ~= "" then t[#t + 1] = arq end
      end
    end
  end
  return t
end

local function clicks_var_da_musica(m)
  local t, visto = {}, {}
  local raiz = M.pasta_click_gerado()
  for _, arq in ipairs(arquivos_sobrepostos_da_musica(m)) do
    if chave_eq_ou_dentro(arq, raiz) then
      local n = (nome_ultima(arq) or ""):lower()
      if n:match("^click_var_.*%.wav$") and not visto[chave_caminho(arq)] then
        visto[chave_caminho(arq)] = true
        t[#t + 1] = arq
      end
    end
  end
  return t
end

local function pico_do_arquivo(arq)
  local dir, nome = pai_de_caminho(arq), nome_ultima(arq)
  if not dir or nome == "" then return nil end
  local a = dir .. SEP .. "peaks" .. SEP .. nome .. ".reapeaks"
  if r.file_exists(a) then return a end
  local b = dir .. SEP .. nome .. ".reapeaks"
  if r.file_exists(b) then return b end
  return nil
end

local function tamanho_com_pico(arq)
  local n = tamanho_arquivo(arq)
  local pico = pico_do_arquivo(arq)
  if pico then n = n + tamanho_arquivo(pico) end
  return n
end

-- Monta o que pode ser apagado desta música (pastas dedicadas e/ou arquivos soltos).
local function alvos_da_musica(info)
  local alvos, bytes = {}, 0
  local visto = {}
  info.soltos_ok = info.soltos_ok or {}
  local function add(caminho, eh_pasta, rotulo)
    if not caminho or caminho == "" then return end
    local k = chave_caminho(caminho)
    if visto[k] then return end
    visto[k] = true
    local n = eh_pasta and (existe_pasta(caminho) and tamanho_pasta(caminho) or 0) or (r.file_exists(caminho) and tamanho_com_pico(caminho) or 0)
    alvos[#alvos + 1] = { caminho = caminho, pasta = eh_pasta and true or false, rotulo = rotulo or nome_ultima(caminho), bytes = n }
    bytes = bytes + n
    if not eh_pasta then info.soltos_ok[k] = true end
  end

  local pasta = info.pasta
  if pasta and pasta ~= "" and existe_pasta(pasta) then
    if M.pasta_protegida(pasta) or eh_pasta_do_kit_nao_musica(pasta) then
      -- pasta compartilhada: só os arquivos desta música
      if info.m then
        for _, arq in ipairs(arquivos_sobrepostos_da_musica(info.m)) do
          if chave_eq_ou_dentro(arq, pasta) and not eh_pasta_do_kit_nao_musica(pai_de_caminho(arq) or arq) then
            add(arq, false, nome_ultima(arq))
          end
        end
      end
      for _, nome in ipairs(SIDECARS_MUSICA) do
        local f = pasta .. SEP .. nome
        if r.file_exists(f) then add(f, false, nome) end
      end
      local stems = pasta .. SEP .. M.PASTA_STEMS
      if existe_pasta(stems) then add(stems, true, M.PASTA_STEMS) end
    else
      add(pasta, true, nome_ultima(pasta))
    end
  end
  for _, arq in ipairs(info.clicks or {}) do add(arq, false, nome_ultima(arq)) end
  return alvos, bytes
end

function M.listar_musicas_para_apagar()
  local lista, visto = {}, {}
  local function id_de(pasta, nome, inicio)
    if pasta and pasta ~= "" then return chave_caminho(pasta) end
    return "proj:" .. M.norm(nome or "") .. ":" .. tostring(inicio or 0)
  end
  local function achar(id)
    for _, it in ipairs(lista) do if it.id == id then return it end end
  end

  for _, b in ipairs(M.listar_biblioteca()) do
    local id = id_de(b.pasta, b.nome)
    if not visto[id] then
      visto[id] = true
      lista[#lista + 1] = {
        id = id, nome = b.nome, rotulo = b.rotulo or b.nome, pasta = b.pasta,
        tom = b.tom, bpm = b.bpm, na_biblioteca = true, no_projeto = false,
        m = nil, clicks = {}, alvos = {}, bytes = 0,
      }
    end
  end

  for _, m in ipairs(M.get_musicas()) do
    local pasta = M.pasta_da_musica(m)
    local id = id_de(pasta, m.nome, m.inicio)
    local it = achar(id)
    if not it and pasta then it = achar(id_de(pasta, m.nome)) end
    if not it then
      -- tenta casar pelo nome normalizado com item da biblioteca sem pasta igual
      for _, x in ipairs(lista) do
        if M.norm(x.nome) == M.norm(m.nome) and not x.no_projeto then it = x; break end
      end
    end
    if not it then
      it = {
        id = id, nome = m.nome, rotulo = m.nome_completo or m.nome, pasta = pasta,
        tom = m.tom, na_biblioteca = false, no_projeto = true,
        m = m, clicks = {}, alvos = {}, bytes = 0,
      }
      lista[#lista + 1] = it
      visto[it.id] = true
    end
    it.no_projeto = true
    it.m = m
    it.inicio, it.fim = m.inicio, m.fim
    if pasta and (not it.pasta or it.pasta == "") then it.pasta = pasta end
    it.clicks = clicks_var_da_musica(m)
  end

  for _, it in ipairs(lista) do
    it.alvos, it.bytes = alvos_da_musica(it)
    it.protegida = it.pasta and M.pasta_protegida(it.pasta) or false
  end
  table.sort(lista, function(a, b)
    if a.no_projeto ~= b.no_projeto then return a.no_projeto end
    return (a.rotulo or a.nome or ""):lower() < (b.rotulo or b.nome or ""):lower()
  end)
  return lista
end

function M.apagar_musica_do_projeto(m)
  if not m then return 0 end
  local n = 0
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    local antes = r.GetTrackNumMediaItems(tr)
    M.apagar_itens_no_intervalo(tr, m.inicio, m.fim)
    n = n + (antes - r.GetTrackNumMediaItems(tr))
  end
  -- marcadores da música (não a região ainda)
  local _, marcas = M.listar_marcadores()
  for i = #marcas, 1, -1 do
    local mk = marcas[i]
    if mk.inicio >= m.inicio - 0.001 and mk.inicio < m.fim - 0.001 and not mk.virtual then
      r.DeleteProjectMarker(0, mk.idx, false)
    end
  end
  if m.idx then r.DeleteProjectMarker(0, m.idx, true) end
  apagar_tempos(m.inicio, m.fim)
  local chave = M.norm(m.nome)
  r.SetProjExtState(0, "MT_PASTA", chave, "")
  r.SetProjExtState(0, "MT_TOM", chave, "")
  r.SetProjExtState(0, "MT_CLICK_APROX", chave, "")
  r.SetProjExtState(0, "MT_ANALISADA", chave, "")
  return n
end

-- Envia para a Lixeira (Windows/Mac) ou apaga, depois de o chamador já ter
-- conferido que o caminho é permitido. Não usa a lista estreita do "lixo gerado".
local function enviar_para_lixeira_livre(caminho, eh_pasta)
  if not caminho or caminho == "" then return false end
  if eh_pasta and M.pasta_protegida(caminho) then return false end
  local ok = false
  if M.EH_WIN then
    local api = eh_pasta and "DeleteDirectory" or "DeleteFile"
    local ps = caminho:gsub("'", "''")
    local cmd = 'powershell.exe -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::' ..
      api .. "('" .. ps .. "', 2, 1)\""
    r.ExecProcess(cmd, 20000)
    ok = eh_pasta and (not existe_pasta(caminho)) or (not r.file_exists(caminho))
  elseif M.EH_MAC then
    local posix = caminho:gsub("\\", "\\\\"):gsub('"', '\\"')
    r.ExecProcess('/usr/bin/osascript -e "tell application \\"Finder\\" to delete POSIX file \\"' .. posix .. '\\""', 20000)
    ok = eh_pasta and (not existe_pasta(caminho)) or (not r.file_exists(caminho))
  end
  if not ok then
    if eh_pasta then ok = apagar_arvore(caminho)
    else
      local pico = pico_do_arquivo(caminho)
      ok = (os.remove(caminho) and true) or (not r.file_exists(caminho))
      if pico then os.remove(pico) end
    end
  elseif not eh_pasta then
    local pico = pico_do_arquivo(caminho)
    if pico then enviar_para_lixeira_livre(pico, false) end
  end
  return ok
end

-- Arquivo avulso só pode sair se for desta música: sidecar, __stems, click_var,
-- ou áudio referenciado no projeto (info.m) dentro da pasta dela.
local function arquivo_avulso_ok(caminho, info)
  info = info or {}
  if info.soltos_ok and info.soltos_ok[chave_caminho(caminho)] then return true end
  local nome = (nome_ultima(caminho) or ""):lower()
  if chave_eq_ou_dentro(caminho, M.pasta_click_gerado()) then
    return nome:match("^click_var_.*%.wav$") or (nome:match("%.reapeaks$") and nome:find("click", 1, true))
  end
  local pai = pai_de_caminho(caminho)
  if M.norm(nome_ultima(pai or "")) == M.norm(M.PASTA_STEMS) then
    local song = pai_de_caminho(pai)
    return info.pasta and song and chave_caminho(song) == chave_caminho(info.pasta)
  end
  for _, sc in ipairs(SIDECARS_MUSICA) do
    if nome == sc:lower() and info.pasta and pai and chave_caminho(pai) == chave_caminho(info.pasta) then return true end
  end
  if info.m and info.pasta then
    for _, arq in ipairs(arquivos_sobrepostos_da_musica(info.m)) do
      if chave_caminho(arq) == chave_caminho(caminho) and chave_eq_ou_dentro(arq, info.pasta) then return true end
    end
  end
  return false
end

-- Um alvo é permitido se está na lista explícita, ou dentro de uma pasta
-- dedicada (não protegida) que também está na lista — e passa nas regras duras.
local function alvo_permitido(caminho, alvos, info)
  if not caminho or caminho == "" then return false end
  if eh_pasta_do_kit_nao_musica(caminho) and not chave_eq_ou_dentro(caminho, M.pasta_click_gerado()) then return false end
  local eh_pasta = existe_pasta(caminho) and not (r.file_exists(caminho) and not existe_pasta(caminho))
  -- existe_pasta também é true para pastas; file_exists para arquivos. Pastas protegidas nunca.
  -- Usamos o flag do alvo mais abaixo.
  local c = chave_caminho(caminho)
  local na_lista = false
  local como_pasta = false
  for _, a in ipairs(alvos) do
    local k = chave_caminho(a.caminho)
    if c == k then
      na_lista = true
      como_pasta = a.pasta and true or false
      break
    end
    if a.pasta and chave_eq_ou_dentro(caminho, a.caminho) and not M.pasta_protegida(a.caminho) then
      na_lista = true
      como_pasta = false -- arquivo/subpasta dentro de pasta dedicada
      break
    end
  end
  if not na_lista then return false end
  if como_pasta then return not M.pasta_protegida(caminho) end
  -- arquivo: se a pasta-mãe é protegida (Downloads...) só os arquivos desta música
  local pai = pai_de_caminho(caminho)
  if pai and M.pasta_protegida(pai) then return arquivo_avulso_ok(caminho, info or {}) end
  if chave_eq_ou_dentro(caminho, M.pasta_click_gerado()) then return arquivo_avulso_ok(caminho, info or {}) end
  -- dentro de pasta dedicada já aceita acima
  return true
end

function M.apagar_alvos_da_musica(info)
  local alvos = info.alvos or select(1, alvos_da_musica(info))
  local ok, falhou, bytes = 0, 0, 0
  -- pastas primeiro? melhor arquivos soltos e clicks, depois pastas
  table.sort(alvos, function(a, b)
    if a.pasta ~= b.pasta then return not a.pasta end
    return #chave_caminho(a.caminho) > #chave_caminho(b.caminho)
  end)
  for _, a in ipairs(alvos) do
    if not alvo_permitido(a.caminho, alvos, info) then
      falhou = falhou + 1
    else
      local deu = enviar_para_lixeira_livre(a.caminho, a.pasta)
      if deu then ok = ok + 1; bytes = bytes + (a.bytes or 0) else falhou = falhou + 1 end
    end
  end
  return ok, falhou, bytes
end

-- selecionadas = lista de itens de listar_musicas_para_apagar
-- opcoes.incluir_lixo = também roda a limpeza de lixo gerado
-- opcoes.sem_undo / opcoes.silencioso para testes
function M.apagar_musicas_escolhidas(selecionadas, opcoes)
  opcoes = opcoes or {}
  selecionadas = selecionadas or {}
  if #selecionadas == 0 and not opcoes.incluir_lixo then return false, "vazio" end
  if not opcoes.sem_undo then r.Undo_BeginBlock() end
  -- se alguma música do setlist está tocando, para
  if M.tocando and (M.tocando() or M.pausado()) then
    local pos = M.pos_atual and M.pos_atual() or 0
    for _, it in ipairs(selecionadas) do
      if it.no_projeto and it.inicio and it.fim and pos >= it.inicio - 0.001 and pos < it.fim then
        r.OnStopButton()
        break
      end
    end
  end
  -- tira do projeto ANTES de apagar os arquivos (itens deixam de apontar para eles)
  local n_proj, n_ok, n_falhou, bytes = 0, 0, 0, 0
  for _, it in ipairs(selecionadas) do
    if it.no_projeto and it.m then
      M.apagar_musica_do_projeto(it.m)
      n_proj = n_proj + 1
    end
  end
  for _, it in ipairs(selecionadas) do
    local o, f, b = M.apagar_alvos_da_musica(it)
    n_ok, n_falhou, bytes = n_ok + o, n_falhou + f, bytes + b
  end
  local lixo_ok, lixo_falhou, lixo_bytes = 0, 0, 0
  if opcoes.incluir_lixo then
    lixo_ok, lixo_falhou, lixo_bytes = M.apagar_lixo()
    n_ok, n_falhou, bytes = n_ok + lixo_ok, n_falhou + lixo_falhou, bytes + lixo_bytes
  end
  if not opcoes.sem_undo then r.Undo_EndBlock("Mik Seifador: apagar músicas", -1) end
  if r.UpdateArrange then r.UpdateArrange() end
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  if not opcoes.silencioso then
    local txt
    if n_falhou == 0 then
      txt = string.format("Pronto! %d %s enviadas para a Lixeira (%s).",
        #selecionadas, #selecionadas == 1 and "música" or "músicas", fmt_mb(bytes))
      if n_proj > 0 then txt = txt .. "\n" .. (n_proj == 1 and "1 música saiu do setlist." or (n_proj .. " músicas saíram do setlist.")) end
      if opcoes.incluir_lixo then txt = txt .. "\nLixo gerado também foi limpo." end
      txt = txt .. "\n\nO desfazer do REAPER não restaura os arquivos."
    else
      txt = string.format("Apaguei %d item(ns) (%s).\n%d não puderam ser apagados (arquivo aberto?).", n_ok, fmt_mb(bytes), n_falhou)
    end
    r.MB(txt, "Limpar arquivos", 0)
    M.aviso(string.format("Apagadas %d músicas, %s", #selecionadas, fmt_mb(bytes)))
  end
  return true, n_ok, n_falhou, bytes, n_proj
end


function M.tick_se_sem_motor()
  if not M.motor_ativo() then M.tick() end
end

-------------------------------------------------------------------------------
-- ESTADO RESUMIDO (para o painel)
-------------------------------------------------------------------------------
function M.estado()
  local e = {}
  e.pos = M.pos_atual()
  e.tocando = M.tocando()
  e.pausado = M.pausado()
  local mus, marcas = M.listar_marcadores()
  e.marcas = marcas
  e.musicas = M.aplicar_ordem_setlist(mus)
  e.musica = nil
  if #e.musicas > 0 then e.musica = M.musica_atual(e.pos, e.musicas) end
  if e.musica then
    e.secoes = M.secoes_da_musica(e.musica, e.marcas)
    e.secao = M.secao_atual(e.pos, e.secoes)
    e.transp = M.get_transp(e.musica)
    e.tom = M.tom_soando(e.musica)
  else
    e.secoes = {}
    e.transp = 0
  end
  e.bpm = r.TimeMap_GetDividedBpmAtTime(e.pos)
  e.modo = M.modo()
  e.setlist_travado = M.setlist_travado()
  return e
end

-------------------------------------------------------------------------------
-- ATUALIZAÇÃO AUTOMÁTICA (mt_atualizar.lua, GitHub mikgp6/mik-seifador)
-- Ao abrir o painel, no máximo 1x por dia e sem travar, compara a build local
-- (build.txt) com a do manifest.json publicado. Sem internet: silêncio.
-------------------------------------------------------------------------------
local _upd = nil
function M.atualizador()
  if _upd == nil then
    _upd = false
    local ok, f = pcall(dofile, M.DIR .. "mt_atualizar.lua")
    if ok and type(f) == "function" then
      local ok2, u = pcall(f, M)
      if ok2 and type(u) == "table" then _upd = u
      else pcall(M.registrar_erro, "atualizar-carga", u) end
    elseif not ok then pcall(M.registrar_erro, "atualizar-carga", f) end
  end
  return _upd or nil
end
function M.build()
  local u = M.atualizador()
  return u and u.build_local() or M.BUILD
end
-- manual = true: avisa também "já é a mais nova" / "sem internet"
function M.procurar_atualizacoes(manual)
  local u = M.atualizador()
  if not u then return false end
  return u.procurar(manual ~= false)
end
function M.atualizar_agora()
  local u = M.atualizador()
  if not u then return false end
  return u.atualizar()
end
function M.atualizacao_disponivel()
  local u = M.atualizador()
  return u and u.disponivel() or nil
end
function M.atualizacao_estado()
  local u = M.atualizador()
  return u and u.estado or nil
end
function M.atualizador_tick(ao_avisar)
  local u = M.atualizador()
  if not u then return end
  if ao_avisar then u.ao_avisar = ao_avisar end
  u.tick()
end

pcall(M.sessao_id)
return M
