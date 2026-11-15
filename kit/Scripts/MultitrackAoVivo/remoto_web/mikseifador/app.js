/* Mik Seifador Remoto — controle pelo celular (Android / iPhone)
   Criado por Miqueias Felix (2026). Fala com o painel/motor do Mik Seifador pela
   interface web do REAPER: lê o estado (ExtState) e manda comandos para uma fila. */
(function () {
  "use strict";
  var SEC = "MikSeifadorRemoto";
  var N_SLOTS = 32;
  var POLL_MS = 90;
  var $ = function (id) { return document.getElementById(id); };

  // ---------------------------------------------------------------- estado
  var S = null;            // estado lento (setlist, seções, trilhas)
  var F = null;            // estado rápido
  var seq = -1, waveKey = null, wave = null, biblio = null, blN = -1;
  var querState = true, querWave = false, querBiblio = false;
  var avN = -1;
  var tF = 0, tPos = 0;    // hora local em que chegou o FAST e posição dele
  var ultimaResposta = 0, ultimaFast = "", fastMudou = 0;
  var fila = [];           // comandos SET a enviar
  var volPend = {};        // fader -> posição pendente (agrupa arrastes)
  var panPend = {};
  var toque = {};          // canal -> hora do último toque local (não pula enquanto arrasta)
  var slot = Math.floor(Math.random() * N_SLOTS);
  var prefixo = Math.random().toString(36).slice(2, 6);
  var nCmd = 0, ping = 0, ultimoPing = 0;
  var emVoo = false;

  function dec(s) { try { return decodeURIComponent(s); } catch (e) { return s; } }
  function decObj(o) {
    if (typeof o === "string") return dec(o);
    if (Array.isArray(o)) { for (var i = 0; i < o.length; i++) o[i] = decObj(o[i]); return o; }
    if (o && typeof o === "object") { var r = {}; for (var k in o) r[dec(k)] = decObj(o[k]); return r; }
    return o;
  }
  function unesc(v) { return String(v).replace(/\\t/g, "\t").replace(/\\n/g, "\n").replace(/\\\\/g, "\\"); }
  function parseJSON(v) { if (!v) return null; try { return decObj(JSON.parse(unesc(v))); } catch (e) { return null; } }
  function mmss(t) { if (!(t > 0)) t = 0; var m = Math.floor(t / 60), s = Math.floor(t % 60); return m + ":" + (s < 10 ? "0" : "") + s; }
  function esc(s) { return String(s == null ? "" : s).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }

  // ---------------------------------------------------------------- comandos
  function cmd(nome) {
    var args = Array.prototype.slice.call(arguments, 1);
    var id = prefixo + (++nCmd).toString(36);
    var v = id + "|" + nome;
    for (var i = 0; i < args.length; i++) v += "|" + encodeURIComponent(String(args[i]));
    fila.push("SET/EXTSTATE/" + SEC + "/C" + slot + "/" + encodeURIComponent(v));
    slot = (slot + 1) % N_SLOTS;
    vibrar(8);
    agendar(0);
  }
  window.mikCmd = cmd;
  function vibrar(ms) { if (navigator.vibrate) try { navigator.vibrate(ms); } catch (e) {} }

  // ---------------------------------------------------------------- rede
  var timer = null;
  function agendar(ms) { if (timer) clearTimeout(timer); timer = setTimeout(poll, ms); }
  function poll() {
    timer = null;
    if (emVoo) return;
    var partes = [];
    for (var id in volPend) { cmdDireto("vol", id, volPend[id].toFixed(4)); }
    volPend = {};
    for (var id2 in panPend) { cmdDireto("pan", id2, panPend[id2].toFixed(2)); }
    panPend = {};
    partes = fila.splice(0, 40);
    var agora = Date.now();
    if (agora - ultimoPing > 900) { ultimoPing = agora; partes.push("SET/EXTSTATE/" + SEC + "/PING/" + (++ping)); }
    partes.push("GET/EXTSTATE/" + SEC + "/FAST");
    if (querState) partes.push("GET/EXTSTATE/" + SEC + "/STATE");
    if (querWave) partes.push("GET/EXTSTATE/" + SEC + "/WAVE");
    if (querBiblio) partes.push("GET/EXTSTATE/" + SEC + "/BIBLIO");
    partes.push("TRANSPORT");
    emVoo = true;
    var ctrl = window.AbortController ? new AbortController() : null;
    var to = setTimeout(function () { if (ctrl) ctrl.abort(); }, 4000);
    fetch("/_/" + partes.join(";"), { cache: "no-store", credentials: "same-origin", signal: ctrl ? ctrl.signal : undefined })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.text(); })
      .then(function (txt) { clearTimeout(to); emVoo = false; resposta(txt); agendar(fila.length ? 0 : POLL_MS); })
      .catch(function () { clearTimeout(to); emVoo = false; semConexao(); agendar(1000); });
  }
  function cmdDireto(nome) {
    var args = Array.prototype.slice.call(arguments, 1);
    var id = prefixo + (++nCmd).toString(36);
    var v = id + "|" + nome;
    for (var i = 0; i < args.length; i++) v += "|" + encodeURIComponent(String(args[i]));
    fila.push("SET/EXTSTATE/" + SEC + "/C" + slot + "/" + encodeURIComponent(v));
    slot = (slot + 1) % N_SLOTS;
  }

  function resposta(txt) {
    ultimaResposta = Date.now();
    var linhas = txt.split("\n"), temTransport = false;
    for (var i = 0; i < linhas.length; i++) {
      var tk = linhas[i].split("\t");
      if (tk[0] === "EXTSTATE" && tk[1] === SEC) {
        var chave = tk[2], valor = tk.slice(3).join("\t");
        if (chave === "FAST") recebeFast(valor);
        else if (chave === "STATE") { var st = parseJSON(valor); if (st) { S = st; querState = false; montar(); } }
        else if (chave === "WAVE") { var w = parseJSON(valor); if (w) { wave = decodeWave(w.d || ""); waveKey = w.k; querWave = false; desenharOnda(); } }
        else if (chave === "BIBLIO") { var b = parseJSON(valor); if (b) { biblio = b; querBiblio = false; if (folhaAtual === "biblio") abrirBiblio(); } }
      } else if (tk[0] === "TRANSPORT") temTransport = true;
    }
    var semLua = !F || Date.now() - fastMudou > 3500;
    if (semLua && temTransport) mostrarConexao("Abra o Mik Seifador no REAPER", "O REAPER respondeu, mas o painel (F9) ou o motor ao vivo não estão rodando.", true);
    else esconderConexao();
  }
  function recebeFast(v) {
    if (v !== ultimaFast) { ultimaFast = v; fastMudou = Date.now(); }
    var f = parseJSON(v);
    if (!f) return;
    F = f; tF = performance.now(); tPos = f.t;
    if (f.q !== seq) { seq = f.q; querState = true; }
    if (f.w && f.w !== waveKey) querWave = true;
    if (f.bl !== blN) { if (blN >= 0 && folhaAtual === "biblio") querBiblio = true; blN = f.bl; }
    if (f.av && f.av[0] !== avN) { if (avN >= 0 && f.av[1]) toast(f.av[1]); avN = f.av[0]; }
    atualizar();
  }
  function semConexao() {
    mostrarConexao("Sem conexão com o REAPER", "Confira se o celular está no mesmo Wi-Fi do computador e se o REAPER está aberto. Tentando de novo…", false);
  }
  function mostrarConexao(t, p, aviso) {
    var c = $("conexao"); $("con-tit").textContent = t; $("con-txt").textContent = p;
    c.className = aviso ? "aviso" : ""; c.hidden = false;
  }
  function esconderConexao() { $("conexao").hidden = true; }

  // ---------------------------------------------------------------- toast
  var toastT = null;
  function toast(t) {
    var el = $("toast"); el.textContent = t; el.classList.add("ver");
    clearTimeout(toastT); toastT = setTimeout(function () { el.classList.remove("ver"); }, 2600);
  }

  // ---------------------------------------------------------------- forma de onda
  var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
  function decodeWave(d) { var a = new Array(d.length); for (var i = 0; i < d.length; i++) a[i] = Math.max(0, B64.indexOf(d[i])) / 63; return a; }

  // ---------------------------------------------------------------- utilidades de cor
  function hexRGB(h, padrao) {
    h = h || padrao || "#4ec8e8";
    var n = parseInt(h.slice(1), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  }
  function rgb(c, f, a) {
    f = f == null ? 1 : f;
    var r = Math.min(255, Math.round(c[0] * f)), g = Math.min(255, Math.round(c[1] * f)), b = Math.min(255, Math.round(c[2] * f));
    return a == null ? "rgb(" + r + "," + g + "," + b + ")" : "rgba(" + r + "," + g + "," + b + "," + a + ")";
  }

  // ---------------------------------------------------------------- posição interpolada
  function posAgora() {
    if (!F) return 0;
    if (F.pl === 1) return tPos + (performance.now() - tF) / 1000 * (F.rate || 1);
    return F.t;
  }
  function musicaAtual() { if (!S || !F) return null; for (var i = 0; i < S.mus.length; i++) if (S.mus[i].n === F.m) return S.mus[i]; return null; }

  // ---------------------------------------------------------------- layout compacto (celular)
  var LAYOUT_KEY = "mikseifador_layout";
  var LIMIAR = 820;
  var painelAberto = null;
  function telaCelular() {
    var w = window.innerWidth, h = window.innerHeight;
    return w <= LIMIAR || (h <= 520 && w <= 1400);
  }
  function prefereCompleto() {
    try { return localStorage.getItem(LAYOUT_KEY) === "completo"; } catch (e) { return false; }
  }
  function ehCompacto() { return document.body.classList.contains("compacto"); }
  function aplicarLayout() {
    var cel = telaCelular();
    var compacto = cel && !prefereCompleto();
    document.body.classList.toggle("estreito", cel);
    var mudou = ehCompacto() !== compacto;
    document.body.classList.toggle("compacto", compacto);
    if (!compacto) fecharPainel(true);
    if (mudou) {
      quadro._sujoOnda = true;
      setTimeout(function () { if (!ehCompacto()) desenharOnda(); atualizarSeek(); }, 40);
    }
  }
  function definirLayout(modo) {
    try { localStorage.setItem(LAYOUT_KEY, modo); } catch (e) {}
    aplicarLayout();
    redimensionar();
    toast(modo === "completo" ? "Layout completo (igual ao painel)" : "Layout compacto (ao vivo)");
  }
  function setTxt(id, t) { var el = $(id); if (el) el.textContent = t; }
  function fecharPainel(manterVeu) {
    if (painelAberto) {
      var ph = $(painelAberto.id + "-ph");
      if (ph && ph.parentNode) ph.parentNode.insertBefore(painelAberto, ph);
      painelAberto = null;
    }
    document.body.classList.remove("ver-setlist", "ver-mixer");
    var sh = $("sheet-extra"); if (sh) sh.hidden = true;
    if (!manterVeu && !folhaAtual) $("veu").hidden = true;
  }
  function abrirPainel(nome) {
    fecharFolha();
    fecharPainel(true);
    var el = $(nome === "mixer" ? "mixer" : "setlist");
    if (!el) return;
    painelAberto = el;
    $("sheet-tit").textContent = nome === "mixer" ? "Mixer" : "Setlist";
    $("sheet-corpo").appendChild(el);
    $("sheet-extra").hidden = false;
    $("veu").hidden = false;
    document.body.classList.add(nome === "mixer" ? "ver-mixer" : "ver-setlist");
    if (nome === "mixer") setTimeout(redimensionar, 40);
  }
  function montarSeek() {
    var box = $("seek-marcas"); if (!box) return;
    var m = musicaAtual(), h = "";
    if (m && S && S.secs) {
      var dur = Math.max(0.001, m.fim - m.ini);
      S.secs.forEach(function (s) {
        var l = Math.max(0, (s.ini - m.ini) / dur * 100);
        var w = Math.max(0.5, (s.fim - s.ini) / dur * 100);
        h += '<i style="left:' + l + "%;width:" + w + "%;background:" + esc(s.cor || "#4ec8e8") + '"></i>';
      });
    }
    box.innerHTML = h;
  }
  function atualizarSeek() {
    var m = musicaAtual();
    var fill = $("seek-fill"), cur = $("seek-cursor");
    if (!m) {
      if (fill) fill.style.width = "0";
      if (cur) cur.style.left = "0";
      setTxt("cp-tempo", "0:00 / 0:00");
      return;
    }
    var dur = Math.max(0.001, m.fim - m.ini);
    var pos = posAgora();
    var k = Math.max(0, Math.min(1, (pos - m.ini) / dur));
    if (fill) fill.style.width = (k * 100).toFixed(3) + "%";
    if (cur) cur.style.left = (k * 100).toFixed(3) + "%";
    var txt = mmss(pos - m.ini) + " / " + mmss(dur);
    setTxt("cp-tempo", txt);
    var lcd = $("lcd-tempo"); if (lcd && ehCompacto()) lcd.textContent = txt;
  }
  function seekEm(ev, el) {
    var m = musicaAtual(); if (!m) return;
    var r = el.getBoundingClientRect();
    var f = (ev.clientX - r.left) / Math.max(1, r.width);
    var t = m.ini + Math.max(0, Math.min(1, f)) * (m.fim - m.ini);
    cmd("seek", t.toFixed(3));
    if (F) { F.t = t; tPos = t; tF = performance.now(); }
    atualizarSeek();
  }

  // ---------------------------------------------------------------- montar (estado lento)
  var canais = {};       // id -> { el, fd, pan, valores }
  // capa animada: some quando chega o 1º estado do REAPER (mínimo 1,6 s), ao tocar, ou depois de 7 s
  var capaT0 = Date.now(), capaFeita = false;
  function capaFechar() {
    if (capaFeita) return; capaFeita = true;
    var el = document.getElementById("capa"); if (!el) return;
    var falta = Math.max(0, 1600 - (Date.now() - capaT0));
    setTimeout(function () { el.classList.add("sai"); setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 500); }, falta);
  }
  (function () {
    var el = document.getElementById("capa"); if (!el) return;
    el.addEventListener("click", function () { capaT0 = 0; capaFechar(); });
    setTimeout(capaFechar, 7000);
  })();

  function montar() {
    capaFechar();
    if (!S) return;
    $("versao").textContent = S.v || "";
    // setlist
    var sl = $("setlist"), h = "";
    var travado = !!S.trava;
    sl.classList.toggle("travado", travado);
    var svgTrava = travado
      ? '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="11" width="12" height="10" rx="2"/><path d="M8.2 11V8.2a3.8 3.8 0 0 1 7.6 0V11" fill="none" stroke="currentColor" stroke-width="2.2"/><circle cx="12" cy="16" r="1.4" fill="#0c0e12"/></svg>'
      : '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="11" width="12" height="10" rx="2"/><path d="M15.8 11V8.2a3.8 3.8 0 0 0-7.6 0" fill="none" stroke="currentColor" stroke-width="2.2"/><circle cx="12" cy="16" r="1.4" fill="#0c0e12"/></svg>';
    h += '<button type="button" class="trava-set' + (travado ? " on" : "") + '" data-cmd="strava" title="' +
      (travado ? "Setlist travado — toque para destravar" : "Travar o setlist (não deixa arrastar os cards)") +
      '" aria-label="Trava do setlist">' + svgTrava + "</button>";
    if (!S.mus.length) h += '<div class="vazio">Setlist vazio — importe as músicas no computador (botão IMPORTAR do painel).</div>';
    S.mus.forEach(function (m) {
      var c = hexRGB(m.cor, "#4ec8e8");
      var bg = m.capa ? "background-image:url('" + esc(m.capa) + "')" :
        "background:linear-gradient(135deg," + rgb(c, .8) + "," + rgb(c, .42) + " 55%," + rgb(c, .2) + ")";
      h += '<button class="card' + (m.capa ? " com-capa" : "") + '" data-mus="' + m.n + '"><span class="bg" style="' + bg + '"></span>' +
        '<span class="nome">' + esc(m.nome) + '</span><span class="n">' + m.n + "</span>" + (m.tom ? '<span class="t">' + esc(m.tom) + "</span>" : "") +
        '<span class="brilho"></span></button>';
    });
    sl.innerHTML = h;
    // seções
    var sc = $("secoes"), hs = "";
    (S.secs || []).forEach(function (s) {
      var c = hexRGB(s.cor, "#aaaaaa");
      hs += '<button class="sec" data-sec="' + s.n + '" style="background:linear-gradient(180deg,' + rgb(c, 1.18) + "," + rgb(c, .95) + " 50%," + rgb(c, .78) + ')">' +
        esc(s.nome) + '<i class="pg"></i><svg class="lp" viewBox="0 0 24 24"><path fill="#fff" d="M17 7H8a5 5 0 0 0 0 10h1v-2.4H8a2.6 2.6 0 0 1 0-5.2h9V12l4-3.6L17 5z"/></svg></button>';
    });
    sc.innerHTML = hs;
    // tom
    montarSeek();
    // mixer
    var ids = (S.ch || []).map(function (c) { return c.id + "|" + c.nome + "|" + c.cor; }).join(";");
    if (ids !== montar._ids) { montar._ids = ids; montarMixer(); }
    desenharOnda();
    atualizar();
  }

  function montarMixer() {
    var st = $("mix-stems"), dir = $("mix-dir"), mst = $("mix-master");
    st.innerHTML = ""; dir.innerHTML = ""; mst.innerHTML = ""; canais = {};
    var temStem = false;
    (S.ch || []).forEach(function (c) {
      var el = document.createElement("div");
      el.className = "canal" + (c.g === "m" ? " master" : "");
      var cor = c.cor || (c.g === "s" ? "#4ec8e8" : "#4ec8e8");
      el.innerHTML = '<i class="cor" style="background:' + esc(cor) + ';box-shadow:0 0 6px ' + esc(cor) + '"></i><div class="nm">' + esc(c.nome) + "</div>" +
        '<canvas class="pan"></canvas><div class="ms"><button class="m">M</button>' + (c.g === "m" ? "" : '<button class="s">S</button>') + "</div>" +
        '<canvas class="fd"></canvas>';
      (c.g === "s" ? st : (c.g === "m" ? mst : dir)).appendChild(el);
      if (c.g === "s") temStem = true;
      var o = { id: c.id, el: el, cor: cor, nome: c.nome, p: 0.75, pk: [-90, -90], pkv: [-90, -90], mute: 0, solo: 0, pan: 0, master: c.g === "m",
        fd: el.querySelector("canvas.fd"), pc: el.querySelector("canvas.pan"), sujo: true };
      canais[c.id] = o;
      ligarFader(o); ligarPan(o);
      el.querySelector(".m").addEventListener("click", function () { o.mute = o.mute ? 0 : 1; toque[o.id + "m"] = Date.now(); cmd("mute", o.id, o.mute); atualizarMS(o); });
      var bs = el.querySelector(".s");
      if (bs) bs.addEventListener("click", function () { o.solo = o.solo ? 0 : 1; toque[o.id + "s"] = Date.now(); cmd("solo", o.id, o.solo); atualizarMS(o); });
    });
    if (!temStem) st.innerHTML = '<div class="vazio" style="width:240px;align-self:center">Nenhum stem na pasta BANDA</div>';
    redimensionar();
  }
  function atualizarMS(o) {
    o.el.querySelector(".m").classList.toggle("on", !!o.mute);
    var s = o.el.querySelector(".s"); if (s) s.classList.toggle("on", !!o.solo);
  }

  // ---------------------------------------------------------------- curva do fader (estilo Pro Tools, igual ao painel)
  // posição 0..1: 1 = +12 dB, 0.75 = 0 dB, 0.5 = -10, 0.15 = -40, 0 = -inf
  function pos2db(x) {
    if (!(x > 0)) return -Infinity;
    if (x >= 1) x = 1;
    if (x >= 0.75) return (x - 0.75) / 0.25 * 12;
    if (x >= 0.5) return -10 + (x - 0.5) / 0.25 * 10;
    if (x >= 0.15) return -40 + (x - 0.15) / 0.35 * 30;
    return -144 + Math.sqrt(x / 0.15) * 104;
  }
  function db2pos(db) {
    if (!(db > -144)) return 0;
    if (db >= 12) return 1;
    if (db >= 0) return 0.75 + db / 12 * 0.25;
    if (db >= -10) return 0.5 + (db + 10) / 10 * 0.25;
    if (db >= -40) return 0.15 + (db + 40) / 30 * 0.35;
    var t = (db + 144) / 104; return 0.15 * t * t;
  }
  window.MikFader = { pos2db: pos2db, db2pos: db2pos };
  var ESCALA = [12, 6, 0, -5, -10, -20, -40];
  function dbTxt(p) { var db = pos2db(p); if (!(db > -99)) return "-inf"; return (db > 0 ? "+" : "") + db.toFixed(1); }

  // ---------------------------------------------------------------- fader v3: fino e realista 3D (canvas) — mesmo desenho do painel
  var DPR = Math.min(3, window.devicePixelRatio || 1);
  function geoFader(o) {
    var w = o.fd.clientWidth, h = o.fd.clientHeight;
    var baixo = (ehCompacto() && window.innerHeight <= 520) ? 16 : 30;
    var CAP_W = 20, CAP_H = 15, fy1 = 8 + CAP_H / 2, fy2 = h - baixo;
    return { w: w, h: h, fy1: fy1, fy2: fy2, fh: Math.max(20, fy2 - fy1), tx: Math.floor(w / 2 - 8) + .5, CAP_W: CAP_W, CAP_H: CAP_H };
  }
  function vgrad(x, y1, y2, paradas) { var g = x.createLinearGradient(0, y1, 0, y2); paradas.forEach(function (p) { g.addColorStop(p[0], p[1]); }); return g; }
  function hgrad(x, x1, x2, paradas) { var g = x.createLinearGradient(x1, 0, x2, 0); paradas.forEach(function (p) { g.addColorStop(p[0], p[1]); }); return g; }
  // medidor como no painel: -60..+6 dB linear; ciano, lavanda (> -6) e vermelho (> -0,5)
  function medFrac(db) { var f = (db + 60) / 66; return f < 0 ? 0 : (f > 1 ? 1 : f); }
  function desenharFader(o, agora) {
    var cv = o.fd, g = geoFader(o);
    if (!g.w || !g.h) return;
    if (cv.width !== Math.round(g.w * DPR) || cv.height !== Math.round(g.h * DPR)) { cv.width = Math.round(g.w * DPR); cv.height = Math.round(g.h * DPR); }
    var x = cv.getContext("2d"); x.setTransform(DPR, 0, 0, DPR, 0, 0); x.clearRect(0, 0, g.w, g.h);
    var fx = g.tx, fy1 = g.fy1, fy2 = g.fy2, fh = g.fh, cy = Math.floor(fy2 - o.p * fh) + .5;
    // trilho fino afundado: canaleta com lábio claro, fenda de 4 px com sombra interna
    var t1 = fy1 - 4, t2 = fy2 + 4;
    rr(x, fx - 5, t1 - 2, 10, t2 - t1 + 4, 5); x.fillStyle = "#0a0c10"; x.fill();
    x.lineWidth = 1; x.strokeStyle = "rgba(255,255,255,.12)"; ln(x, fx - 4, t2 + 2.5, fx + 5, t2 + 2.5);
    x.strokeStyle = "rgba(255,255,255,.06)"; ln(x, fx + 5.5, t1, fx + 5.5, t2 + 1);
    rr(x, fx - 2, t1, 4, t2 - t1, 2); x.fillStyle = "#000"; x.fill();
    x.fillStyle = vgrad(x, t1, t1 + 12, [[0, "rgba(0,0,0,1)"], [1, "rgba(0,0,0,0)"]]); x.fillRect(fx - 2, t1, 4, 12);
    x.strokeStyle = "rgba(255,255,255,.055)"; ln(x, fx + 1.5, t1 + 3, fx + 1.5, t2 - 1);
    if (o.p > 0) {
      x.fillStyle = "rgba(78,200,232,.07)"; x.fillRect(fx - 3, cy, 6, t2 - 1 - cy);
      x.fillStyle = "rgba(78,200,232,.44)"; x.fillRect(fx - 1, cy, 2, t2 - 1 - cy);
    }
    // marca de 0 dB: risco gravado com ponto ciano
    var un = Math.floor(fy2 - db2pos(0) * fh) + .5;
    x.strokeStyle = "rgba(0,0,0,.7)"; ln(x, fx - 8, un, fx + 8, un);
    x.strokeStyle = "#6a7382"; ln(x, fx - 8, un + 1, fx + 8, un + 1);
    x.save(); x.shadowColor = "rgba(78,200,232,.9)"; x.shadowBlur = 4; x.beginPath(); x.arc(fx - 9.5, un + .5, 1.3, 0, 7); x.fillStyle = "#4ec8e8"; x.fill(); x.restore();
    // medidores: 2 barras finas (4 px) em vidro, degradê, brilho e divisões de LED
    var Y_LAV = fy2 - medFrac(-6) * fh, Y_RED = fy2 - medFrac(-0.5) * fh;
    for (var ch = 0; ch < 2; ch++) {
      var mx = fx + 11.5 + ch * 6, frac = medFrac(o.pkv[ch] > -89 ? o.pkv[ch] : -90);
      rr(x, mx - 1, fy1 - 1, 6, fh + 2, 2); x.fillStyle = "#06070a"; x.fill();
      x.fillStyle = "#020304"; x.fillRect(mx, fy1, 4, fh);
      x.strokeStyle = "rgba(255,255,255,.09)"; ln(x, mx - .5, fy2 + 1.5, mx + 4.5, fy2 + 1.5);
      x.fillStyle = "rgba(78,200,232,.08)"; x.fillRect(mx, Y_LAV, 4, fy2 - Y_LAV);
      x.fillStyle = "rgba(142,216,236,.08)"; x.fillRect(mx, Y_RED, 4, Y_LAV - Y_RED);
      x.fillStyle = "rgba(229,72,77,.09)"; x.fillRect(mx, fy1, 4, Y_RED - fy1);
      if (frac > 0) {
        var ytop = fy2 - frac * fh;
        [[Y_LAV, fy2, "78,200,232"], [Y_RED, Y_LAV, "142,216,236"], [fy1, Y_RED, "229,72,77"]].forEach(function (f) {
          var a = Math.max(f[0], ytop), b = f[1]; if (b <= a) return;
          x.fillStyle = "rgba(" + f[2] + ",.17)"; x.fillRect(mx - 1.5, a - 1, 7, b - a + 1);
          x.fillStyle = hgrad(x, mx, mx + 4, [[0, "rgba(" + f[2] + ",1)"], [1, "rgba(" + f[2] + ",.72)"]]); x.fillRect(mx, a, 4, b - a);
        });
        x.fillStyle = "rgba(255,255,255,.75)"; x.fillRect(mx, ytop, 4, 1);
      }
      x.fillStyle = "rgba(2,3,4,.5)"; for (var yy = fy2 - 3; yy >= fy1; yy -= 3) x.fillRect(mx, yy, 4, 1);
      x.fillStyle = hgrad(x, mx, mx + 2, [[0, "rgba(255,255,255,.08)"], [1, "rgba(255,255,255,0)"]]); x.fillRect(mx, fy1, 2, fh);
    }
    // botão fino de metal escovado: sombra macia (cresce ao arrastar), chanfro, reflexo e linha-guia ciano
    var W = g.CAP_W, H = g.CAP_H, cx1 = fx - W / 2, cx2 = fx + W / 2, cy1 = cy - H / 2, cy2 = cy + H / 2;
    var ativo = o.arrastando, lev = ativo ? 1.7 : 1;
    x.save(); x.shadowColor = "rgba(0,0,0," + (ativo ? .85 : .72) + ")"; x.shadowBlur = 7 * lev; x.shadowOffsetX = 2.5 * lev; x.shadowOffsetY = 5 * lev;
    rr(x, cx1, cy1, W, H, 3); x.fillStyle = "#222"; x.fill(); x.restore();
    x.save(); x.shadowColor = "rgba(0,0,0,.75)"; x.shadowBlur = 2; x.shadowOffsetY = 1.5;
    rr(x, cx1, cy1, W, H, 3); x.fillStyle = "#0c0e12"; x.fill(); x.restore();
    rr(x, cx1, cy1, W, H, 3);
    x.fillStyle = vgrad(x, cy1, cy2, ativo ? [[0, "#fff"], [.5, "#cdd2db"], [1, "#6c717b"]] : [[0, "#f1f3f7"], [.5, "#b4bac4"], [1, "#5a5f69"]]); x.fill();
    x.save(); rr(x, cx1, cy1, W, H, 3); x.clip();
    for (var k = 1; k < H - 1; k += 2) { x.fillStyle = (k % 4 === 1) ? "rgba(255,255,255,.08)" : "rgba(0,0,0,.1)"; x.fillRect(cx1 + 1.5, cy1 + k, W - 3, .6); }
    x.fillStyle = hgrad(x, cx1, cx2, [[0, "rgba(255,255,255,.18)"], [.38, "rgba(255,255,255,0)"], [.38, "rgba(0,0,0,0)"], [1, "rgba(0,0,0,.33)"]]); x.fillRect(cx1, cy1, W, H);
    x.fillStyle = "rgba(78,200,232,.25)"; x.fillRect(cx1, cy - 1.8, W, 3.6);
    x.save(); x.shadowColor = "rgba(78,200,232,.9)"; x.shadowBlur = 3; x.fillStyle = "#5ad6f5"; x.fillRect(cx1 + 1.5, cy - .6, W - 3, 1.2); x.restore();
    x.restore();
    x.fillStyle = "rgba(255,255,255,.88)"; x.fillRect(cx1 + 2, cy1 + .8, W - 4, .8);
    rr(x, cx1, cy1, W, H, 3); x.strokeStyle = "#14161a"; x.lineWidth = 1; x.stroke();
    x.strokeStyle = "rgba(255,255,255,.38)"; ln(x, cx1 + 1.5, cy1 + 2, cx1 + 1.5, cy2 - 2);
    x.strokeStyle = "rgba(0,0,0,.7)"; ln(x, cx1 + 2, cy2 - 1.5, cx2 - 2, cy2 - 1.5);
    // valor em dB (mesma posição de antes)
    var vy1 = g.h - 18, vy2 = g.h - 4;
    rr(x, 4, vy1, g.w - 8, vy2 - vy1, 3); x.fillStyle = "#08090c"; x.fill();
    x.strokeStyle = "#000"; ln(x, 5, vy1 + .5, g.w - 5, vy1 + .5); x.strokeStyle = "rgba(255,255,255,.1)"; ln(x, 5, vy2 - .5, g.w - 5, vy2 - .5);
    x.fillStyle = "#9fe3b4"; x.textAlign = "center"; x.textBaseline = "middle"; x.font = "600 10px 'SF Mono',Menlo,Consolas,monospace";
    x.fillText(dbTxt(o.p), g.w / 2, (vy1 + vy2) / 2 + .5);
  }
  function rr(x, a, b, w, h, r) {
    x.beginPath(); x.moveTo(a + r, b); x.lineTo(a + w - r, b); x.quadraticCurveTo(a + w, b, a + w, b + r); x.lineTo(a + w, b + h - r);
    x.quadraticCurveTo(a + w, b + h, a + w - r, b + h); x.lineTo(a + r, b + h); x.quadraticCurveTo(a, b + h, a, b + h - r); x.lineTo(a, b + r); x.quadraticCurveTo(a, b, a + r, b); x.closePath();
  }
  function ln(x, a, b, c, d) { x.beginPath(); x.moveTo(a, b); x.lineTo(c, d); x.stroke(); }

  function desenharPan(o) {
    var cv = o.pc, s = 28;
    if (cv.width !== s * DPR) { cv.width = s * DPR; cv.height = s * DPR; }
    var x = cv.getContext("2d"); x.setTransform(DPR, 0, 0, DPR, 0, 0); x.clearRect(0, 0, s, s);
    var c = s / 2, r = 11;
    x.beginPath(); x.arc(c, c + 1.5, r, 0, 7); x.fillStyle = "rgba(0,0,0,.6)"; x.fill();
    var gr = x.createRadialGradient(c - 4, c - 5, 2, c, c, r);
    gr.addColorStop(0, o.panAtivo ? "#4a5466" : "#3b4352"); gr.addColorStop(1, "#1a1e27");
    x.beginPath(); x.arc(c, c, r, 0, 7); x.fillStyle = gr; x.fill();
    x.strokeStyle = "rgba(78,200,232,.65)"; x.lineWidth = 1.5; x.stroke();
    var ang = (-135 + (o.pan + 1) / 2 * 270 - 90) * Math.PI / 180;
    x.strokeStyle = "#8ed8ec"; x.lineWidth = 2; x.lineCap = "round"; ln(x, c, c, c + Math.cos(ang) * (r - 2.5), c + Math.sin(ang) * (r - 2.5));
  }

  // toque duplo
  function duplo(o, chave) { var t = Date.now(), d = t - (o[chave] || 0) < 320; o[chave] = d ? 0 : t; return d; }
  function ligarFader(o) {
    var cv = o.fd, x0 = 0, y0 = 0, p0 = 0, pend = false;
    cv.addEventListener("pointerdown", function (ev) {
      if (duplo(o, "_tFd")) { o.p = db2pos(0); toque[o.id] = Date.now(); cmd("vol0", o.id); desenharFader(o); o.arrastando = false; pend = false; return; }
      // espera a direção: vertical = volume, horizontal = rola a faixa (não captura ainda)
      pend = true; o.arrastando = false; x0 = ev.clientX; y0 = ev.clientY; p0 = o.p;
    });
    cv.addEventListener("pointermove", function (ev) {
      if (pend) {
        var dx = ev.clientX - x0, dy = ev.clientY - y0;
        if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
        pend = false;
        if (Math.abs(dx) >= Math.abs(dy)) return; // rolagem horizontal da faixa
        o.arrastando = true;
        try { cv.setPointerCapture(ev.pointerId); } catch (e) {}
        ev.preventDefault();
        desenharFader(o);
      }
      if (!o.arrastando) return;
      ev.preventDefault();
      var g = geoFader(o);
      var p = Math.max(0, Math.min(1, p0 - (ev.clientY - y0) / g.fh));
      if (p !== o.p) { o.p = p; volPend[o.id] = p; toque[o.id] = Date.now(); desenharFader(o); if (!emVoo) agendar(0); }
    });
    var fim = function () {
      pend = false;
      if (o.arrastando) { o.arrastando = false; toque[o.id] = Date.now(); desenharFader(o); }
    };
    cv.addEventListener("pointerup", fim); cv.addEventListener("pointercancel", fim);
  }
  function ligarPan(o) {
    var cv = o.pc, x0 = 0, y0 = 0, v0 = 0;
    cv.addEventListener("pointerdown", function (ev) {
      ev.preventDefault();
      if (duplo(o, "_tPan")) { o.pan = 0; panPend[o.id] = 0; toque[o.id + "p"] = Date.now(); desenharPan(o); agendar(0); return; }
      cv.setPointerCapture(ev.pointerId); o.panAtivo = true; x0 = ev.clientX; y0 = ev.clientY; v0 = o.pan; desenharPan(o);
    });
    cv.addEventListener("pointermove", function (ev) {
      if (!o.panAtivo) return;
      var v = Math.max(-1, Math.min(1, v0 + ((ev.clientX - x0) - (ev.clientY - y0)) * 0.012));
      if (Math.abs(v) < 0.04) v = 0;
      if (v !== o.pan) { o.pan = v; panPend[o.id] = v; toque[o.id + "p"] = Date.now(); desenharPan(o); if (!emVoo) agendar(0); }
    });
    var fim = function () { o.panAtivo = false; toque[o.id + "p"] = Date.now(); desenharPan(o); };
    cv.addEventListener("pointerup", fim); cv.addEventListener("pointercancel", fim);
  }

  // ---------------------------------------------------------------- atualizar (estado rápido)
  function liga(el, on) { if (el) el.classList.toggle("on", !!on); }
  function atualizar() {
    if (!S || !F) return;
    var m = musicaAtual();
    var tocando = F.pl === 1, pausado = F.pl === 2;
    $("bt-play").classList.toggle("tocando", tocando);
    var playCp = $("bt-play-cp"); if (playCp) playCp.classList.toggle("tocando", tocando);
    document.querySelectorAll("[data-flag]").forEach(function (b) { liga(b, S.f && S.f[b.getAttribute("data-flag")]); });
    var modo = S.modo === "LR" ? (S.lrc ? "STUDIO" : "LR") : S.modo;
    document.querySelectorAll("[data-modo]").forEach(function (b) { liga(b, b.getAttribute("data-modo") === modo); });
    // tom
    var mudou = (S.tr || 0) !== 0;
    $("bt-tom").classList.toggle("mudou", mudou);
    $("tom-val").textContent = m ? (S.tom || "--") : "--";
    $("tom-rot").textContent = mudou ? "Tom " + (S.tr > 0 ? "+" : "") + S.tr : "Tom";
    // BPM
    var bpm = (F.bpm || 0) * (F.rate || 1);
    var bt = F.bpm > 0 ? (Math.abs(bpm - Math.round(bpm)) < 0.05 ? String(Math.round(bpm)) : bpm.toFixed(1)) : "--";
    $("lcd-bpm").textContent = bt; $("bpm-val").textContent = bt;
    $("bpm-val").classList.toggle("taxa", Math.abs((F.rate || 1) - 1) > 0.0005);
    $("lcd-tom").textContent = m ? (S.tom || "--") : "--";
    $("sig-val").textContent = F.sig || "4/4";
    // status
    var dot = $("lcd-dot"); dot.className = tocando ? "tocando" : (pausado ? "pausado" : "");
    var sec = null; (S.secs || []).forEach(function (s) { if (s.n === F.s) sec = s; });
    $("lcd-txt").textContent = (tocando ? "TOCANDO" : (pausado ? "PAUSADO" : "PARADO")) + "  " +
      (m ? m.n + ". " + m.nome : "Nenhuma música") + (sec && m ? "  ·  " + sec.nome : "");
    $("saida-txt").textContent = (S.saida ? "Saída: " + S.saida : "") + "   " + (S.motor ? "Motor: ON" : "Motor: painel");
    setTxt("cp-musica", m ? m.nome : "Nenhuma música");
    setTxt("cp-secao", sec ? sec.nome : (m ? "—" : "Importe uma música no computador"));
    setTxt("cp-bpm", bt);
    setTxt("cp-tom", m ? (S.tom || "--") : "--");
    setTxt("cp-txt", tocando ? "TOCANDO" : (pausado ? "PAUSADO" : "PARADO"));
    var cdot = $("cp-dot"); if (cdot) cdot.className = tocando ? "tocando" : (pausado ? "pausado" : "");
    var ctom = $("cp-bt-tom"); if (ctom) ctom.classList.toggle("mudou", mudou);
    var bpmCp = $("cp-bpm"); if (bpmCp) bpmCp.classList.toggle("taxa", Math.abs((F.rate || 1) - 1) > 0.0005);
    atualizarSeek();
    // setlist
    var btTrava = $("setlist") && $("setlist").querySelector(".trava-set");
    if (btTrava) {
      var travado = !!S.trava;
      btTrava.classList.toggle("on", travado);
      btTrava.title = travado ? "Setlist travado — toque para destravar" : "Travar o setlist (não deixa arrastar os cards)";
      if ($("setlist")) $("setlist").classList.toggle("travado", travado);
    }
    document.querySelectorAll(".card").forEach(function (c) {
      var at = +c.getAttribute("data-mus") === F.m;
      if (at && !c.classList.contains("atual")) { c.classList.add("atual"); try { c.scrollIntoView({ inline: "nearest", block: "nearest", behavior: "smooth" }); } catch (e) {} }
      else if (!at) c.classList.remove("atual");
    });
    // seções
    var loopOn = S.f && (S.f.LOOP || S.f.REPETIR_CLICK);
    document.querySelectorAll(".sec").forEach(function (b) {
      var n = +b.getAttribute("data-sec"), s = (S.secs || [])[n - 1];
      b.classList.toggle("atual", n === F.s);
      b.classList.toggle("loop", !!(loopOn && s && Math.abs(F.ls - s.ini) < 0.01 && Math.abs(F.le - s.fim) < 0.05));
    });
    // progresso
    var pr = F.pr, pb = $("prog");
    if (pr) {
      var progAntes = pb.hidden;
      pb.hidden = false;
      $("prog-fill").style.width = Math.round(Math.max(0, Math.min(1, pr.p || 0)) * 100) + "%";
      var acao = pr.tipo === "instalacao" ? "Instalando" : (pr.tipo === "analise" ? "Analisando" : (pr.rap ? "Separando (rápida)" : "Separando"));
      $("prog-linha").textContent = pr.ok ? (pr.frase || "Pronto ✓") : acao + (pr.nome ? ": " + pr.nome : "") + " — " + (pr.pct || 0) + "%";
      var sub = []; if (pr.et && !pr.ok) sub.push(pr.et); if (pr.fila) sub.push(pr.fila); if (pr.eta && !pr.ok) sub.push("resta " + pr.eta);
      $("prog-sub").textContent = sub.join("  ·  ");
      $("prog-cancelar").hidden = !pr.can;
    } else {
      var progAntes = pb.hidden;
      pb.hidden = true;
    }
    if (typeof progAntes !== "undefined" && progAntes !== pb.hidden) setTimeout(ajustarAlturaFader, 40);
    // mixer
    var agora = Date.now();
    (F.ch || []).forEach(function (v) {
      var o = canais[v[0]]; if (!o) return;
      if (!o.arrastando && !(o.id in volPend) && agora - (toque[o.id] || 0) > 700 && Math.abs(o.p - v[1]) > 0.0004) { o.p = v[1]; o.sujo = true; }
      o.pk[0] = v[2]; o.pk[1] = v[3];
      if (agora - (toque[o.id + "m"] || 0) > 700) o.mute = v[4];
      if (agora - (toque[o.id + "s"] || 0) > 700) o.solo = v[5];
      if (!o.panAtivo && !(o.id in panPend) && agora - (toque[o.id + "p"] || 0) > 700 && o.pan !== v[6]) { o.pan = v[6]; desenharPan(o); }
      atualizarMS(o);
    });
  }

  // ---------------------------------------------------------------- forma de onda + régua de seções
  function desenharOnda() {
    var cv = $("onda"), w = cv.clientWidth, h = cv.clientHeight;
    if (!w || !h) return;
    if (cv.width !== Math.round(w * DPR) || cv.height !== Math.round(h * DPR)) { cv.width = Math.round(w * DPR); cv.height = Math.round(h * DPR); }
    var x = cv.getContext("2d"); x.setTransform(DPR, 0, 0, DPR, 0, 0); x.clearRect(0, 0, w, h);
    var m = musicaAtual(); if (!m) { x.fillStyle = "#5c6574"; x.font = "13px sans-serif"; x.textAlign = "center"; x.fillText("Nenhuma música", w / 2, h / 2); return; }
    var dur = Math.max(0.001, m.fim - m.ini), pos = posAgora(), lane = 22, wh = h - lane - 4;
    var px = function (t) { return 6 + (t - m.ini) / dur * (w - 12); };
    // loop
    if (S.f && (S.f.LOOP || S.f.REPETIR_CLICK) && F.le > F.ls && F.le > m.ini && F.ls < m.fim) {
      x.fillStyle = "rgba(78,200,232,.12)"; x.fillRect(px(F.ls), 0, px(F.le) - px(F.ls), wh);
    }
    // onda
    var xp = px(pos);
    if (wave && wave.length) {
      var n = wave.length, bw = (w - 12) / n, mid = wh / 2 + 2;
      for (var i = 0; i < n; i++) {
        var xx = 6 + i * bw, a = Math.max(0.02, wave[i]) * (wh / 2 - 4);
        x.fillStyle = xx < xp ? "#f4f1ea" : "#5a6270";
        x.fillRect(xx, mid - a, Math.max(1, bw - 0.6), a * 2);
      }
    } else {
      x.fillStyle = "#3a424e"; x.fillRect(6, wh / 2 + 1, w - 12, 2);
    }
    // seções (faixa de arranjo)
    (S.secs || []).forEach(function (s) {
      var c = hexRGB(s.cor, "#aaaaaa"), x1 = px(s.ini) + 1, x2 = px(s.fim) - 1, at = s.n === F.s;
      x.fillStyle = rgb(c, at ? 1 : 0.6); rr(x, x1, h - lane, Math.max(3, x2 - x1), lane - 3, 4); x.fill();
      if (at) { x.strokeStyle = "#fff"; x.lineWidth = 1.5; x.stroke(); }
      x.strokeStyle = "rgba(255,255,255,.18)"; x.lineWidth = 1; ln(x, x1, 0, x1, wh);
      if (x2 - x1 > 24) { x.fillStyle = "#fff"; x.font = "600 10px sans-serif"; x.textAlign = "left"; x.textBaseline = "middle"; x.save(); x.beginPath(); x.rect(x1, h - lane, x2 - x1 - 2, lane); x.clip(); x.fillText(s.nome, x1 + 4, h - lane / 2 - 1); x.restore(); }
    });
    // cursor
    x.strokeStyle = "#4ec8e8"; x.lineWidth = 2; ln(x, xp, 0, xp, h - 2);
    x.fillStyle = "#4ec8e8"; x.beginPath(); x.moveTo(xp - 5, 0); x.lineTo(xp + 5, 0); x.lineTo(xp, 6); x.fill();
    // tempo
    $("lcd-tempo").textContent = mmss(pos - m.ini) + " / " + mmss(dur);
  }
  // tocar na onda = ir para aquele ponto
  $("onda").addEventListener("pointerup", function (ev) {
    var m = musicaAtual(); if (!m) return;
    var r = this.getBoundingClientRect(), f = (ev.clientX - r.left - 6) / (r.width - 12);
    var t = m.ini + Math.max(0, Math.min(1, f)) * (m.fim - m.ini);
    cmd("seek", t.toFixed(3));
    if (F) { F.t = t; tPos = t; tF = performance.now(); }
  });

  // ---------------------------------------------------------------- animação (cursor, medidores)
  function quadro() {
    var agora = performance.now();
    if (S && F) {
      var m = musicaAtual();
      if (ehCompacto()) { atualizarSeek(); quadro._sujoOnda = false; }
      else if (F.pl === 1 || quadro._sujoOnda) { desenharOnda(); quadro._sujoOnda = false; }
      else if (m) $("lcd-tempo").textContent = mmss(F.t - m.ini) + " / " + mmss(m.fim - m.ini);
      // progresso dentro da seção atual
      var pos = posAgora();
      document.querySelectorAll(".sec.atual .pg").forEach(function (el) {
        var s = (S.secs || [])[F.s - 1]; if (!s) return;
        var k = Math.max(0, Math.min(1, (pos - s.ini) / Math.max(0.001, s.fim - s.ini)));
        el.style.width = "calc((100% - 10px) * " + k.toFixed(3) + ")";
      });
      for (var id in canais) {
        var o = canais[id], mudou = o.sujo;
        for (var ch = 0; ch < 2; ch++) {
          var alvo = o.pk[ch], v = o.pkv[ch];
          var nv = alvo > v ? alvo : Math.max(alvo, v - 0.9);
          if (Math.abs(nv - v) > 0.05) { o.pkv[ch] = nv; mudou = true; }
        }
        if (mudou) { o.sujo = false; desenharFader(o); }
      }
    }
    requestAnimationFrame(quadro);
  }

  // ---------------------------------------------------------------- tamanho dos canais
  function ajustarAlturaFader() {
    var hc;
    if (ehCompacto()) {
      var mix = $("mixer"), tit = mix && mix.querySelector(".mix-titulos");
      var sc = $("mix-scroll");
      var avail = 0;
      if (sc && sc.clientHeight) avail = sc.clientHeight;
      else if (mix && mix.clientHeight) avail = mix.clientHeight - (tit && tit.offsetHeight ? tit.offsetHeight : 16) - 10;
      /* nunca maior que o espaço visível: na 1.9b o mínimo de 150px cortava o fader em paisagem baixa */
      hc = avail > 0 ? avail : 180;
    } else {
      var vh = window.innerHeight, land = window.innerWidth > vh;
      hc = land ? Math.max(250, Math.min(380, vh - 70)) : Math.max(280, Math.min(400, Math.round(vh * 0.46)));
    }
    document.documentElement.style.setProperty("--h-canal", hc + "px");
    for (var id in canais) { canais[id].sujo = true; if (!ehCompacto()) desenharPan(canais[id]); }
  }
  function redimensionar() {
    aplicarLayout();
    ajustarAlturaFader();
    quadro._sujoOnda = true;
    setTimeout(function () { ajustarAlturaFader(); if (!ehCompacto()) desenharOnda(); }, 50);
  }
  window.addEventListener("resize", redimensionar);
  window.addEventListener("orientationchange", function () { setTimeout(redimensionar, 250); });

  // ---------------------------------------------------------------- botões (delegação)
  document.addEventListener("click", function (ev) {
    var b = ev.target.closest("[data-cmd]");
    if (b) { var a = b.getAttribute("data-arg"); if (a != null) cmd(b.getAttribute("data-cmd"), a); else cmd(b.getAttribute("data-cmd")); return; }
    var c = ev.target.closest("[data-mus]");
    if (c) {
      if (window._mikSetlistIgnorarClick) { window._mikSetlistIgnorarClick = false; return; }
      cmd("mus", c.getAttribute("data-mus"));
      return;
    }
  });
  $("prog-cancelar").addEventListener("click", function () { cmd("cancelar"); });
  $("bt-tom").addEventListener("click", function () { abrirTom(); });
  $("bt-menu").addEventListener("click", function () { abrirMenu(); });
  var cpTom = $("cp-bt-tom"); if (cpTom) cpTom.addEventListener("click", function () { abrirTom(); });
  var menuCp = $("bt-menu-cp"); if (menuCp) menuCp.addEventListener("click", function () { abrirMenu(); });
  var slCp = $("bt-setlist-cp"); if (slCp) slCp.addEventListener("click", function () { abrirPainel("setlist"); });
  var verCo = $("bt-ver-completo"); if (verCo) verCo.addEventListener("click", function () { definirLayout("completo"); });
  var verCp = $("bt-ver-compacto"); if (verCp) verCp.addEventListener("click", function () { definirLayout("compacto"); });
  var shF = $("sheet-fechar"); if (shF) shF.addEventListener("click", function () { fecharPainel(); });
  (function () {
    var el = $("seek-fino"); if (!el) return;
    var arr = false;
    el.addEventListener("pointerdown", function (ev) { arr = true; try { el.setPointerCapture(ev.pointerId); } catch (e) {} seekEm(ev, el); });
    el.addEventListener("pointermove", function (ev) { if (arr) seekEm(ev, el); });
    var fim = function () { arr = false; };
    el.addEventListener("pointerup", fim); el.addEventListener("pointercancel", fim);
  })();

  // seções: toque = pular; segurar = loop / renomear
  (function () {
    var tmr = null, alvo = null, longo = false;
    var box = $("secoes");
    box.addEventListener("pointerdown", function (ev) {
      alvo = ev.target.closest(".sec"); if (!alvo) return; longo = false;
      tmr = setTimeout(function () { longo = true; vibrar(25); abrirSecao(+alvo.getAttribute("data-sec")); }, 480);
    });
    var cancela = function () { clearTimeout(tmr); };
    box.addEventListener("pointerleave", cancela); box.addEventListener("pointercancel", cancela);
    box.addEventListener("pointerup", function (ev) {
      clearTimeout(tmr);
      var b = ev.target.closest(".sec");
      if (b && b === alvo && !longo) cmd("sec", b.getAttribute("data-sec"));
      alvo = null;
    });
    box.addEventListener("contextmenu", function (ev) { ev.preventDefault(); });
  })();
  // PAD: segurar = pacote de pads (botão do painel completo e o do modo compacto)
  function ligarPadLongo(b) {
    if (!b || b._padLongo) return;
    b._padLongo = true;
    var t = null, longo = false;
    b.addEventListener("pointerdown", function () { longo = false; t = setTimeout(function () { longo = true; vibrar(25); abrirPads(); }, 480); });
    b.addEventListener("pointerup", function () { clearTimeout(t); });
    b.addEventListener("pointercancel", function () { clearTimeout(t); });
    b.addEventListener("click", function (ev) { if (longo) { ev.stopImmediatePropagation(); ev.preventDefault(); } }, true);
    b.addEventListener("contextmenu", function (ev) { ev.preventDefault(); });
  }
  ligarPadLongo($("bt-pad"));
  ligarPadLongo($("bt-pad-cp"));

  // setlist: toque = ir para a música; toque longo + arrastar = trocar a ordem (não mexe na timeline)
  // com o setlist travado, o arraste não começa; o toque no card ainda troca a música
  (function () {
    var box = $("setlist"); if (!box) return;
    var tmr = null, alvo = null, longo = false, arr = false, fromN = 0, over = null, x0 = 0, y0 = 0;
    function estaTravado() { return !!(S && S.trava); }
    function limparOver() { if (over) { over.classList.remove("soltar"); over = null; } }
    function fim() {
      clearTimeout(tmr);
      if (arr && over && alvo) {
        var para = +over.getAttribute("data-mus");
        if (para && para !== fromN) { cmd("sord", fromN, para); window._mikSetlistIgnorarClick = true; }
      } else if (longo) {
        window._mikSetlistIgnorarClick = true;
      }
      if (alvo) alvo.classList.remove("arrastando");
      limparOver();
      alvo = null; arr = false; longo = false;
    }
    box.addEventListener("pointerdown", function (ev) {
      if (ev.target.closest && ev.target.closest(".trava-set")) return;
      var c = ev.target.closest(".card"); if (!c) return;
      alvo = c; longo = false; arr = false; fromN = +c.getAttribute("data-mus");
      x0 = ev.clientX; y0 = ev.clientY;
      if (estaTravado()) return;
      try { c.setPointerCapture(ev.pointerId); } catch (e) {}
      tmr = setTimeout(function () {
        if (estaTravado()) return;
        longo = true; arr = true; vibrar(25);
        if (alvo) alvo.classList.add("arrastando");
      }, 450);
    });
    box.addEventListener("pointermove", function (ev) {
      if (!alvo) return;
      var dx = ev.clientX - x0, dy = ev.clientY - y0;
      if (!longo && (dx * dx + dy * dy) > 80) { clearTimeout(tmr); }
      if (!arr) return;
      if (ev.cancelable) ev.preventDefault();
      var vis = alvo.style.visibility;
      alvo.style.visibility = "hidden";
      var el = document.elementFromPoint(ev.clientX, ev.clientY);
      alvo.style.visibility = vis;
      var dest = el && el.closest ? el.closest("#setlist .card") : null;
      if (dest === alvo) dest = null;
      if (over && over !== dest) over.classList.remove("soltar");
      over = dest || null;
      if (over) over.classList.add("soltar");
    });
    box.addEventListener("pointerup", fim);
    box.addEventListener("pointercancel", fim);
    box.addEventListener("contextmenu", function (ev) { ev.preventDefault(); });
  })();

  // ---------------------------------------------------------------- folhas
  var folhaAtual = null;
  function abrirFolha(nome, html) {
    fecharPainel(true);
    folhaAtual = nome;
    var f = $("folha"); f.innerHTML = '<div class="alca"></div>' + html; f.hidden = false; $("veu").hidden = false;
    f.scrollTop = 0;
  }
  function fecharFolha() {
    folhaAtual = null; $("folha").hidden = true;
    if (!painelAberto) $("veu").hidden = true;
  }
  $("veu").addEventListener("click", function () { fecharFolha(); fecharPainel(); });
  $("folha").addEventListener("click", function (ev) {
    var b = ev.target.closest("[data-acao]");
    if (!b) return;
    var a = b.getAttribute("data-acao"), arg = b.getAttribute("data-arg");
    if (a === "fechar") return fecharFolha();
    if (a === "biblio") return abrirBiblio(true);
    if (a === "pads") return abrirPads();
    if (a === "tomdef") return abrirTomOriginal();
    if (a === "renomear") return abrirRenomear(+arg);
    if (a === "renatual") return F && F.s ? abrirRenomear(F.s) : toast("Nenhuma seção");
    if (a === "layout") { definirLayout(ehCompacto() ? "completo" : "compacto"); return fecharFolha(); }
    if (a === "telacheia") { telaCheia(); return fecharFolha(); }
    if (a === "acordado") { manterAcordado(); return; }
    if (a === "badd") { cmd("badd", arg); toast("Adicionando ao fim do setlist…"); return fecharFolha(); }
    if (a === "cmd") { cmd(arg); if (!b.hasAttribute("data-fica")) fecharFolha(); return; }
    if (a === "cmd2") { cmd(arg, b.getAttribute("data-arg2")); if (!b.hasAttribute("data-fica")) fecharFolha(); return; }
  });
  function item(acao, arg, titulo, sub, extra) {
    return '<button class="item" data-acao="' + acao + '"' + (arg != null ? ' data-arg="' + esc(arg) + '"' : "") + (extra || "") + "><span>" + esc(titulo) +
      (sub ? "<small>" + esc(sub) + "</small>" : "") + "</span></button>";
  }
  function chave(arg, titulo, on, sub) {
    return '<button class="item' + (on ? " on" : "") + '" data-acao="cmd" data-arg="' + arg + '" data-fica><span>' + esc(titulo) + (sub ? "<small>" + esc(sub) + "</small>" : "") + '</span><i class="sw"></i></button>';
  }
  function abrirMenu() {
    if (!S) return;
    var f = S.f || {};
    var h = "<h3>Menu</h3>" +
      "<h4>Músicas</h4>" + item("biblio", null, "Biblioteca de multitracks…", "1 toque põe a música no fim do setlist") +
      "<h4>Seções</h4>" + item("cmd", "marcar", "Marcar seção aqui") + item("cmd", "salvar", "Salvar marcadores") +
      item("renatual", null, "Renomear seção atual…") + item("cmd", "colorir", "Colorir seções") + item("tomdef", null, "Definir tom original…") +
      "<h4>Análise</h4>" + item("cmd", "analisar", "Gerar click + guia + seções + cifra", "da música atual") +
      chave("t_aa", "Análise automática ao importar", f.aa) +
      "<h4>Separação de trilhas</h4>" + item("cmd", "separar", "Separar trilhas (bateria, baixo, voz)", S.mi ? "Motor de separação: instalado" : "Na 1ª vez instala o motor (~1 GB)") +
      item("cmd", "desfazer", "Voltar para a música original", "tira as trilhas separadas") +
      chave("t_sa", "Separar trilhas ao importar", f.sa) + chave("t_mo", "Manter a original mutada depois de separar", f.mo) +
      chave("t_sr", "Separação rápida", f.sr, "~15% mais rápida, qualidade um pouco menor") +
      (S.mi ? "" : item("cmd", "motor", S.minst ? "Instalando o motor de separação…" : "Instalar motor de separação…", "confirme no computador")) +
      "<h4>Ao vivo</h4>" + chave("suave", "Salto suave (pula no fim do compasso)", f.suave) + chave("loopclick", "Repetir click (Loop Click)", f.REPETIR_CLICK) +
      item("pads", null, "Pacote de pads…", S.padd || "") + item("cmd", "reparar", "Reparar estrutura / roteamento") +
      "<h4>Este celular</h4>" +
      item("layout", null, ehCompacto() ? "Ver completo" : "Ver compacto (ao vivo)",
        ehCompacto() ? "Mostra a mesma interface do painel do computador" : "Botões grandes para usar no palco") +
      item("telacheia", null, "Tela cheia") + item("acordado", null, "Manter a tela ligada", "enquanto esta página estiver aberta") +
      '<p class="nota">Importar, Limpar músicas e Saídas de áudio ficam no computador (precisam escolher arquivos e a placa). ' +
      "Tudo o mais acontece em tempo real nos dois: o que você faz aqui aparece no PC e vice-versa.</p>" + item("fechar", null, "Fechar");
    abrirFolha("menu", h);
  }
  function abrirTom() {
    if (!S) return;
    var t = S.tom || "--", tr = S.tr || 0;
    abrirFolha("tom", "<h3>Tom (só a banda)</h3><div class=\"tom-grande\">" + esc(t) + "</div><p class=\"nota\" style=\"text-align:center\">" +
      (tr ? "Transposto " + (tr > 0 ? "+" : "") + tr + " semitom(ns)" + (S.tomo ? " — original " + esc(S.tomo) : "") : (S.tomo ? "Tom original" : "Esta música não tem tom definido")) +
      '</p><div class="linha-bts"><button class="b3d" data-acao="cmd" data-arg="tommenos" data-fica>−</button><button class="b3d" data-acao="cmd" data-arg="tommais" data-fica>+</button>' +
      '<button class="b3d" data-acao="cmd" data-arg="tomzero" data-fica>Original</button></div>' + item("tomdef", null, "Definir tom original…") +
      '<p class="nota">Click e guia não mudam de tom.</p>' + item("fechar", null, "Fechar"));
  }
  var TONS = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"];
  function abrirTomOriginal() {
    var h = "<h3>Tom original da música</h3><h4>Maior</h4><div class=\"tons\">";
    TONS.forEach(function (t) { h += '<button class="b3d" data-acao="cmd2" data-arg="tomdef" data-arg2="' + t + '">' + t + "</button>"; });
    h += "</div><h4>Menor</h4><div class=\"tons\">";
    TONS.forEach(function (t) { h += '<button class="b3d" data-acao="cmd2" data-arg="tomdef" data-arg2="' + t + 'm">' + t + "m</button>"; });
    h += "</div>" + '<button class="item" data-acao="cmd2" data-arg="tomdef" data-arg2=""><span>Sem tom</span></button>' + item("fechar", null, "Cancelar");
    abrirFolha("tomdef", h);
  }
  function abrirSecao(n) {
    var s = S && (S.secs || [])[n - 1]; if (!s) return;
    var loopOn = S.f && (S.f.LOOP || S.f.REPETIR_CLICK) && F && Math.abs(F.ls - s.ini) < 0.01 && Math.abs(F.le - s.fim) < 0.05;
    abrirFolha("secao", "<h3>" + esc(s.nome) + "</h3>" +
      '<button class="item" data-acao="cmd2" data-arg="sec" data-arg2="' + n + '"><span>Ir para esta seção</span></button>' +
      '<button class="item" data-acao="cmd2" data-arg="sloop" data-arg2="' + n + '"><span>' + (loopOn && S.f.LOOP ? "Desligar o loop" : "Repetir (loop) esta seção") + "</span></button>" +
      (s.vt ? "" : item("renomear", n, "Renomear…")) + item("fechar", null, "Fechar"));
  }
  var NOMES = ["INTRO", "VERSO 1", "VERSO 2", "PRÉ-REFRÃO", "REFRÃO", "REFRÃO 2", "PONTE", "SOLO", "INSTRUMENTAL", "INTERLÚDIO", "FINAL", "TAG"];
  function abrirRenomear(n) {
    var s = S && (S.secs || [])[n - 1]; if (!s) return;
    if (s.vt) return toast("Este trecho ainda não é uma seção (use Marcar seção)");
    var h = "<h3>Renomear seção</h3><input type=\"text\" id=\"ren-txt\" value=\"" + esc(s.nome) + "\" autocomplete=\"off\" autocapitalize=\"characters\">" +
      '<div class="linha-bts" style="margin-top:10px">';
    NOMES.forEach(function (x) { h += '<button class="chip" data-nome="' + esc(x) + '">' + esc(x) + "</button>"; });
    h += '</div><div class="linha-bts"><button class="b3d" id="ren-ok">Salvar</button><button class="b3d" data-acao="fechar">Cancelar</button></div>';
    abrirFolha("renomear", h);
    var inp = $("ren-txt");
    document.querySelectorAll("#folha [data-nome]").forEach(function (b) { b.addEventListener("click", function () { inp.value = b.getAttribute("data-nome"); }); });
    $("ren-ok").addEventListener("click", function () { var v = inp.value.trim(); if (v) { cmd("sren", n, v); fecharFolha(); } });
  }
  function abrirPads() {
    if (!S) return;
    var h = "<h3>Pacote de pads</h3>";
    (S.pads || []).forEach(function (p) {
      h += '<button class="item' + (p === S.pac ? " sel" : "") + '" data-acao="cmd2" data-arg="pacote" data-arg2="' + esc(p) + '"><span>' + esc(p) + "</span></button>";
    });
    h += '<button class="item' + (S.pac === "" ? " sel" : "") + '" data-acao="cmd2" data-arg="pacote" data-arg2=""><span>(arquivos soltos na pasta _PADS)</span></button>';
    h += '<p class="nota">Esta música: ' + esc(S.padd || "") + "</p>" + item("cmd", "rpads", "Recarregar pads") + item("fechar", null, "Fechar");
    abrirFolha("pads", h);
  }
  function abrirBiblio(pedir) {
    if (pedir) { biblio = null; querBiblio = true; cmd("biblio"); }
    var h = '<h3>Biblioteca de multitracks</h3><input type="search" id="bib-busca" placeholder="Buscar…" autocomplete="off">' + '<div id="bib-lista" style="margin-top:8px">';
    if (!biblio) h += '<p class="nota">Carregando…</p>';
    else if (!biblio.length) h += '<p class="nota">A biblioteca está vazia.</p>';
    else biblio.forEach(function (b) {
      h += '<button class="item" data-acao="badd" data-arg="' + esc(b.p) + '" data-busca="' + esc(((b.nome || "") + " " + (b.art || "")).toLowerCase()) + '"><span>' + esc(b.nome) +
        "<small>" + esc([b.art, b.tom, b.bpm ? b.bpm + " BPM" : ""].filter(Boolean).join(" · ")) + "</small></span></button>";
    });
    h += "</div>" + item("fechar", null, "Fechar");
    var busca = folhaAtual === "biblio" && $("bib-busca") ? $("bib-busca").value : "";
    abrirFolha("biblio", h);
    var inp = $("bib-busca"); inp.value = busca;
    var filtrar = function () { var q = inp.value.toLowerCase(); document.querySelectorAll("#bib-lista [data-busca]").forEach(function (b) { b.style.display = b.getAttribute("data-busca").indexOf(q) >= 0 ? "" : "none"; }); };
    inp.addEventListener("input", filtrar); filtrar();
  }

  // ---------------------------------------------------------------- tela cheia / tela ligada
  function telaCheia() {
    var d = document.documentElement;
    var f = d.requestFullscreen || d.webkitRequestFullscreen;
    if (f) try { f.call(d); } catch (e) {}
    else toast("No iPhone: Compartilhar > Adicionar à Tela de Início");
  }
  var trava = null;
  function manterAcordado() {
    if (navigator.wakeLock && window.isSecureContext) {
      navigator.wakeLock.request("screen").then(function (l) { trava = l; toast("A tela vai ficar ligada"); }).catch(function () { toast("Não deu: ajuste o bloqueio automático do celular"); });
    } else toast("Este navegador não deixa (página sem HTTPS). Ajuste o bloqueio automático da tela do celular.");
  }
  document.addEventListener("visibilitychange", function () { if (!document.hidden) { agendar(0); if (trava) manterAcordado(); } });

  // ---------------------------------------------------------------- início
  redimensionar();
  requestAnimationFrame(quadro);
  poll();
})();
