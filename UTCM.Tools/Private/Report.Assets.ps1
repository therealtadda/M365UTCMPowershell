function Get-UTCMReportCss {
    # Shared stylesheet for the UTCM HTML reports. No external resources, no inline style attributes needed.
    [CmdletBinding()]
    param()

    $css = @'
:root{color-scheme:light dark;--bg:#ffffff;--fg:#1b1f24;--muted:#4b5563;--line:#cfd6dd;--panel:#f3f5f7;--accent:#0b5cad;--focus:#0b5cad;
--added-bg:#e3f4e8;--added-fg:#0b4a1f;--missing-bg:#fde8e6;--missing-fg:#82190f;--changed-bg:#fff2cf;--changed-fg:#5e4200;--code-bg:#f0f2f4}
@media (prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--muted:#a6b0bb;--line:#363d46;--panel:#161b22;--accent:#79b8ff;--focus:#79b8ff;
--added-bg:#12301c;--added-fg:#86e8a6;--missing-bg:#3f1814;--missing-fg:#ffb8b0;--changed-bg:#3a2e0a;--changed-fg:#f5d37a;--code-bg:#161b22}}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
@media (prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,Arial,sans-serif}
.wrap{max-width:1400px;margin:0 auto;padding:16px}
a{color:var(--accent)}
code,pre{font-family:ui-monospace,SFMono-Regular,Consolas,"Liberation Mono",monospace}
:focus-visible{outline:3px solid var(--focus);outline-offset:2px}
.sr-only{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
.copy-ta{position:fixed;left:0;top:0;width:1px;height:1px;opacity:0}
.skip{position:absolute;left:-999px;top:0;background:var(--bg);padding:8px;z-index:10}
.skip:focus{left:8px;top:8px}
h1{font-size:1.6rem;margin:0 0 4px}
h2{font-size:1.2rem;margin:20px 0 8px}
.meta{color:var(--muted);margin:4px 0;overflow-wrap:anywhere}
.note{color:var(--muted);font-size:.9rem;margin:4px 0}
.topnav{display:flex;flex-wrap:wrap;gap:6px 16px;margin:10px 0;padding:8px 0;border-bottom:1px solid var(--line)}
.cards{list-style:none;padding:0;margin:12px 0;display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px}
.card{border:1px solid var(--line);border-radius:8px;padding:10px 12px;background:var(--panel)}
.card .n{display:block;font-size:1.8rem;font-weight:700;line-height:1.1}
.card .l{color:var(--muted);font-size:.85rem}
.card.k-added{border-left:6px solid var(--added-fg)}
.card.k-missing{border-left:6px dashed var(--missing-fg)}
.card.k-changed{border-left:6px double var(--changed-fg)}
.dist{list-style:none;padding:0;margin:6px 0;display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:10px 32px}
.dist li{display:grid;grid-template-columns:1fr 3em;gap:2px 8px;align-items:center}
.dist .dn{grid-column:1 / -1;min-width:0;overflow-wrap:anywhere}
.dist .bar{display:block;width:100%;height:14px}
.dist .bar-bg{fill:var(--panel);stroke:var(--line);stroke-width:.6;vector-effect:non-scaling-stroke}
.dist .bar-fg{fill:var(--accent)}
.dist .dc{text-align:right;font-variant-numeric:tabular-nums}
.toolbar{display:flex;flex-wrap:wrap;gap:10px 14px;align-items:flex-end;margin:12px 0;padding:10px;border:1px solid var(--line);border-radius:8px;background:var(--panel)}
.fld{display:flex;flex-direction:column;gap:2px;font-size:.85rem;color:var(--muted)}
.fld.chk{flex-direction:row;align-items:center;gap:6px;color:var(--fg)}
input[type=search],select{font:inherit;color:var(--fg);background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:6px 8px;min-height:36px;max-width:100%}
input[type=search]{width:100%}
.fld.search{flex:1 1 20em}
.rtable thead th .thl{display:inline-block;padding:2px 4px;min-height:24px;font-weight:700}
button{font:inherit;color:var(--fg);background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:6px 10px;min-height:36px;cursor:pointer}
button:hover{background:var(--panel)}
button[aria-pressed=true]{border-color:var(--accent);box-shadow:inset 0 0 0 1px var(--accent);font-weight:600}
.chips{display:flex;flex-wrap:wrap;gap:6px}
.menu{position:relative}
.menu>summary{cursor:pointer;border:1px solid var(--line);border-radius:6px;padding:6px 10px;min-height:36px;background:var(--bg);list-style:none}
.menu>summary::-webkit-details-marker{display:none}
.menu .menu-body{position:absolute;z-index:5;margin-top:4px;padding:10px;border:1px solid var(--line);border-radius:8px;background:var(--bg);display:flex;flex-direction:column;gap:6px;min-width:12em;box-shadow:0 4px 14px rgba(0,0,0,.25)}
.menu .menu-body label{display:flex;gap:6px;align-items:center}
.count{margin:8px 0;color:var(--muted)}
.empty{padding:16px;border:1px dashed var(--line);border-radius:8px;margin:12px 0}
.empty.ok{border-style:solid;background:var(--added-bg);color:var(--added-fg)}
.rtable{width:100%;border-collapse:collapse;margin:6px 0}
.rtable th,.rtable td{padding:8px 10px;text-align:left;vertical-align:top;border-bottom:1px solid var(--line);overflow-wrap:anywhere}
.rtable thead th{position:sticky;top:0;background:var(--panel);z-index:2;white-space:nowrap}
.rtable thead th .sortbtn{border:0;background:transparent;padding:2px 4px;min-height:24px;font-weight:700}
.rtable thead th[aria-sort=ascending] .sortbtn::after{content:" \25B2"}
.rtable thead th[aria-sort=descending] .sortbtn::after{content:" \25BC"}
.rtable tbody.item tr.detail td{padding-top:0;border-bottom:2px solid var(--line)}
.rtable .nm{font-weight:600;overflow-wrap:anywhere}
.rtable .idl{display:block;color:var(--muted);font-size:.85rem;overflow-wrap:anywhere}
.filtered-out,.pg-hidden{display:none}
.badge{display:inline-flex;gap:.35em;align-items:center;padding:1px 9px;border-radius:999px;font-weight:600;font-size:.85rem;white-space:nowrap}
.st-added{background:var(--added-bg);color:var(--added-fg);border:2px solid var(--added-fg)}
.st-missing{background:var(--missing-bg);color:var(--missing-fg);border:2px dashed var(--missing-fg)}
.st-changed{background:var(--changed-bg);color:var(--changed-fg);border:3px double var(--changed-fg)}
details>summary{cursor:pointer}
details.rawwrap{margin-top:8px}
pre.raw{background:var(--code-bg);padding:8px;border-radius:6px;white-space:pre-wrap;overflow-wrap:anywhere;max-height:420px;overflow:auto;font-size:.85rem;margin:4px 0}
.tablewrap{overflow-x:auto;max-width:100%}
.props{border-collapse:collapse;width:100%;font-size:.9rem;margin:6px 0}
.props th,.props td{padding:4px 8px;border:1px solid var(--line);text-align:left;vertical-align:top}
.props thead th{background:var(--panel)}
.props .path{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-weight:600;overflow-wrap:anywhere}
.props .v{display:inline-block;max-width:100%;max-height:12em;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere}
.props .absent{color:var(--muted);font-style:italic}
.pst{white-space:nowrap;font-weight:600}
.copybtn{min-height:24px;padding:0 6px;margin-left:6px;font-size:.75rem}
.chg-print{display:none}
.scope.changed-only .prop[data-st=unchanged]{display:none}
.scope.hc-id [data-col=id],.scope.hc-type [data-col=type],.scope.hc-workload [data-col=workload],.scope.hc-changes [data-col=changes],.scope.hc-preview [data-col=preview]{display:none}
.pager{display:flex;flex-wrap:wrap;gap:8px 12px;align-items:center;margin:6px 0 14px}
.pager .pg{color:var(--muted)}
.wl-group{margin:10px 0;border:1px solid var(--line);border-radius:8px;padding:0 10px}
.wl-group>summary{padding:8px 0;font-weight:700}
.wl-group .gc{font-weight:400;color:var(--muted)}
html:not(.js) .needs-js{display:none}
[hidden]{display:none !important}
@media (max-width:640px){
.wrap{padding:10px}
.rtable,.rtable tbody.item,.rtable tr,.rtable td{display:block}
.rtable thead{position:absolute;left:-9999px}
.rtable tbody.item{border:1px solid var(--line);border-radius:8px;margin:0 0 10px;padding:4px 6px}
.rtable tr.main td{display:flex;gap:8px;border:0;padding:3px 4px}
.rtable tr.main td>*{min-width:0}
.rtable tr.main td::before{content:attr(data-label);min-width:6.5em;color:var(--muted);font-weight:600}
.rtable tbody.item tr.detail td{border-bottom:0}
.toolbar{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;align-items:stretch}
.toolbar .fld.search,.toolbar .chips,.toolbar .fld.chk{grid-column:1 / -1}
.menu .menu-body{position:static;box-shadow:none;min-width:0}
.fld,input[type=search]{width:100%}
button,select,.menu>summary{min-height:44px}
}
@media (forced-colors:active){.badge{forced-color-adjust:none;border-color:ButtonText;color:ButtonText;background:ButtonFace}.dist .bar-fg{fill:Highlight}.dist .bar-bg{fill:Canvas;stroke:CanvasText}}
@media print{
body{background:#fff;color:#000;font-size:11pt}
.needs-js,.toolbar,.pager,.topnav,.skip,.copybtn,.menu,.count{display:none !important}
.wrap{max-width:none;padding:0}
.pg-hidden{display:table-row-group}
.filtered-out{display:none !important}
.rtable thead{display:table-header-group}
.rtable thead th{position:static}
.rtable tbody.item{break-inside:avoid}
.rtable tr.detail details,.rawwrap{display:none !important}
.chg-print{display:block;margin:0;padding-left:18px;font-size:.85rem}
.scope.changed-only .prop[data-st=unchanged]{display:none}
.wl-group{border:0;padding:0}
.badge,.card,.st-added,.st-missing,.st-changed{-webkit-print-color-adjust:exact;print-color-adjust:exact}
a[href^=http]::after{content:" (" attr(href) ")";font-size:.8em;color:#444}
#current-state{break-before:page}
}
'@
    return ($css -replace "`r`n", "`n").Trim()
}

function Get-UTCMReportScript {
    # Shared, dependency-free client script (ES2017-safe). Operates on the report markup contract.
    [CmdletBinding()]
    param()

    $js = @'
(function () {
  'use strict';
  var doc = document;
  doc.documentElement.classList.add('js');

  var STATUS_RANK = { Changed: 0, Missing: 1, Added: 2 };
  var SIZES = [25, 50, 100, 250];
  var SORT_KEYS = ['status', 'name', 'type', 'workload', 'changes'];
  var COLS = ['id', 'type', 'workload', 'changes', 'preview'];
  var collator = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });
  var liveEl = doc.getElementById('live');
  var currentSection = '';
  var scopes = [];

  function q1(sel, ctx) { return (ctx || doc).querySelector(sel); }
  function qa(sel, ctx) { return Array.prototype.slice.call((ctx || doc).querySelectorAll(sel)); }
  function announce(msg) {
    if (!liveEl) { return; }
    liveEl.textContent = '';
    setTimeout(function () { liveEl.textContent = msg; }, 30);
  }
  function mk(tag, attrs, text) {
    var n = doc.createElement(tag);
    if (attrs) { Object.keys(attrs).forEach(function (k) { n.setAttribute(k, attrs[k]); }); }
    if (text !== undefined) { n.textContent = text; }
    return n;
  }

  /* ---------- clipboard & downloads ---------- */
  function copyText(text, btn) {
    function done(ok) {
      announce(ok ? 'Copied to clipboard' : 'Copy failed. Select the text and copy it manually.');
      if (btn) {
        var old = btn.textContent;
        btn.textContent = ok ? 'Copied' : 'Failed';
        setTimeout(function () { btn.textContent = old; }, 1200);
      }
    }
    function fallback() {
      var ta = mk('textarea', { 'aria-hidden': 'true', tabindex: '-1', 'class': 'copy-ta' });
      ta.value = text;
      doc.body.appendChild(ta);
      ta.select();
      var ok = false;
      try { ok = doc.execCommand('copy'); } catch (e) { ok = false; }
      doc.body.removeChild(ta);
      done(ok);
    }
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(function () { done(true); }, fallback);
    } else {
      fallback();
    }
  }
  function csvCell(v) {
    var text = String(v === null || v === undefined ? '' : v);
    if (/^[ \t\r\n]*[=+\-@]|^[\t\r\n]/.test(text)) { text = "'" + text; }
    return '"' + text.replace(/"/g, '""') + '"';
  }
  function toCsv(headers, rows) {
    var out = [headers.map(csvCell).join(',')];
    rows.forEach(function (r) { out.push(r.map(csvCell).join(',')); });
    return out.join('\r\n') + '\r\n';
  }
  function safeName(n) { return String(n).replace(/[^A-Za-z0-9._-]/g, '_').slice(0, 120); }
  function saveFile(name, mime, text) {
    var blob = new Blob([text], { type: mime });
    var url = URL.createObjectURL(blob);
    var a = mk('a', { href: url, download: name });
    doc.body.appendChild(a);
    a.click();
    setTimeout(function () { URL.revokeObjectURL(url); doc.body.removeChild(a); }, 1000);
  }

  /* ---------- scope (one toolbar + its lists) ---------- */
  function Scope(el, index) {
    var self = this;
    this.el = el;
    this.prefix = index === 0 ? '' : 'c.';
    this.dlName = safeName(el.getAttribute('data-dlname') || 'utcm-report');
    this.dlMode = el.getAttribute('data-download') || 'dom';
    this.islandId = el.getAttribute('data-island') || '';
    this.groupable = el.getAttribute('data-groupable') === '1';
    this.presorted = el.getAttribute('data-presorted') === '1';
    this.defaults = {
      q: '', st: '', wl: '', ty: '',
      so: el.getAttribute('data-sort') || 'name', di: 'asc',
      sz: 50, gr: this.groupable, co: el.classList.contains('changed-only'), hc: []
    };
    this.state = JSON.parse(JSON.stringify(this.defaults));
    this.tokens = [];
    this.dirty = true;
    this.first = true;
    this.items = qa('tbody.item', el).map(function (tb) {
      return {
        el: tb, list: null, match: true, raw: null,
        dn: tb.getAttribute('data-name') || '',
        name: (tb.getAttribute('data-name') || '').toLowerCase(),
        id: tb.getAttribute('data-id') || '',
        type: tb.getAttribute('data-type') || '',
        workload: tb.getAttribute('data-workload') || '',
        status: tb.getAttribute('data-status') || '',
        changes: parseInt(tb.getAttribute('data-changes') || '0', 10),
        rows: (tb.getAttribute('data-rows') || '').split(',').filter(Boolean).map(Number)
      };
    });
    this.items.forEach(function (it) { it.search = (it.id + ' ' + it.dn + ' ' + it.type + ' ' + it.workload).toLowerCase(); });
    this.lists = qa('[data-list]', el).map(function (l) {
      return { el: l, table: q1('table', l), group: l.getAttribute('data-group') || '',
               flat: l.hasAttribute('data-flat'), pager: q1('[data-pager]', l), page: 1, items: [], matchCount: 0 };
    });
    this.countEl = q1('[data-count]', el);
    this.emptyEl = q1('[data-empty]', el);
    this.bind();
    el.addEventListener('keydown', function (e) { if (e.key === 'Escape') { var m = q1('.menu[open]', el); if (m) { m.removeAttribute('open'); } } });
    self.syncControls();
  }

  function ord(a, b) { return a < b ? -1 : (a > b ? 1 : 0); }

  Scope.prototype.cmp = function (a, b) {
    var k = this.state.so, d = this.state.di === 'desc' ? -1 : 1, r = 0;
    if (k === 'status') { r = (STATUS_RANK[a.status] || 0) - (STATUS_RANK[b.status] || 0); }
    else if (k === 'changes') { r = a.changes - b.changes; }
    else if (k === 'type') { r = collator.compare(a.type, b.type); }
    else if (k === 'workload') { r = collator.compare(a.workload, b.workload); }
    else { r = ord(a.name, b.name); }
    // Name then id use ordinal comparison, the same order the server uses for presorted markup
    if (r === 0) { r = ord(a.name, b.name); }
    if (r === 0) { r = ord(a.id, b.id); }
    return r * d;
  };

  Scope.prototype.rawText = function (it) {
    if (it.raw === null) {
      it.raw = qa('.raw', it.el).map(function (n) { return n.textContent; }).join('\n').toLowerCase();
    }
    return it.raw;
  };

  Scope.prototype.matches = function (it) {
    var s = this.state;
    if (s.st && it.status !== s.st) { return false; }
    if (s.wl && it.workload !== s.wl) { return false; }
    if (s.ty && it.type !== s.ty) { return false; }
    for (var i = 0; i < this.tokens.length; i++) {
      var t = this.tokens[i];
      if (it.search.indexOf(t) === -1 && this.rawText(it).indexOf(t) === -1) { return false; }
    }
    return true;
  };

  Scope.prototype.listFor = function (it) {
    var grouped = this.groupable && this.state.gr;
    for (var i = 0; i < this.lists.length; i++) {
      var l = this.lists[i];
      if (grouped ? (!l.flat && l.group === it.workload) : l.flat) { return l; }
    }
    return null;
  };

  Scope.prototype.render = function (userAction) {
    var self = this, s = this.state;
    this.tokens = s.q.toLowerCase().split(/\s+/).filter(Boolean);
    var grouped = this.groupable && s.gr;
    // Server-sorted markup already matches the default view: skip the first sort and DOM move.
    var useDom = this.first && this.presorted && s.so === this.defaults.so && s.di === 'asc' &&
                 (!this.groupable || s.gr === this.defaults.gr);
    qa('[data-grouped-wrap]', this.el).forEach(function (n) { n.hidden = !grouped; });
    qa('[data-flat-wrap]', this.el).forEach(function (n) { n.hidden = grouped; });
    if (this.dirty) { this.sorted = useDom ? this.items.slice() : this.items.slice().sort(this.cmp.bind(this)); }
    this.lists.forEach(function (l) { l.items = []; });
    this.sorted.forEach(function (it) { var l = self.listFor(it); it.list = l; if (l) { l.items.push(it); } });
    if (this.dirty) {
      if (!useDom) {
        this.lists.forEach(function (l) {
          var frag = doc.createDocumentFragment();
          l.items.forEach(function (it) { frag.appendChild(it.el); });
          l.table.appendChild(frag);
        });
      }
      this.dirty = false;
    }
    var total = this.items.length, matched = 0, flatShown = '';
    this.lists.forEach(function (l) {
      var ms = [];
      l.items.forEach(function (it) { it.match = self.matches(it); if (it.match) { ms.push(it); } });
      l.matchCount = ms.length;
      var pages = Math.max(1, Math.ceil(ms.length / s.sz));
      if (l.page > pages) { l.page = pages; }
      var start = (l.page - 1) * s.sz, end = start + s.sz, idx = 0;
      l.items.forEach(function (it) {
        if (!it.match) { it.el.classList.add('filtered-out'); it.el.classList.remove('pg-hidden'); return; }
        it.el.classList.remove('filtered-out');
        var hidden = idx < start || idx >= end;
        it.el.classList.toggle('pg-hidden', hidden);
        if (!hidden && !it.btn) { addCopyButtons(it.el); it.btn = true; }
        idx++;
      });
      matched += ms.length;
      var g = l.el.closest('details.wl-group');
      if (g) {
        var gc = q1('.gc', g);
        if (gc) { gc.textContent = '(' + (ms.length === l.items.length ? l.items.length : ms.length + ' of ' + l.items.length) + ')'; }
        g.hidden = l.items.length === 0 || (ms.length === 0 && (self.tokens.length > 0 || s.st || s.wl || s.ty));
      }
      if (l.flat && ms.length > s.sz && !(self.groupable && s.gr)) {
        flatShown = ' (showing ' + (start + 1) + '\u2013' + Math.min(end, ms.length) + ')';
      }
      self.buildPager(l, pages);
    });
    if (this.countEl) {
      this.countEl.textContent = (matched === total ? total + ' items' : matched + ' of ' + total + ' items match') + flatShown;
    }
    if (this.emptyEl) { this.emptyEl.hidden = matched > 0 || total === 0; }
    this.syncControls();
    if (userAction && this.countEl) { announce(this.countEl.textContent); }
    this.first = false;
  };

  Scope.prototype.buildPager = function (l, pages) {
    var self = this, p = l.pager;
    if (!p) { return; }
    while (p.firstChild) { p.removeChild(p.firstChild); }
    if (l.matchCount <= SIZES[0]) { return; }
    var nav = mk('nav', { 'class': 'pager', 'aria-label': 'Pagination' });
    var prev = mk('button', { type: 'button', 'data-pg': 'prev' }, 'Previous');
    var next = mk('button', { type: 'button', 'data-pg': 'next' }, 'Next');
    prev.disabled = l.page <= 1; next.disabled = l.page >= pages;
    nav.appendChild(prev);
    nav.appendChild(mk('span', { 'class': 'pg' }, 'Page ' + l.page + ' of ' + pages));
    nav.appendChild(next);
    var lab = mk('label', { 'class': 'fld chk' }, 'Rows per page ');
    var sel = mk('select', { 'data-pgsize': '1', 'aria-label': 'Rows per page' });
    SIZES.forEach(function (n) { var o = mk('option', { value: String(n) }, String(n)); if (n === self.state.sz) { o.selected = true; } sel.appendChild(o); });
    lab.appendChild(sel);
    nav.appendChild(lab);
    p.appendChild(nav);
    p._list = l;
  };

  Scope.prototype.syncControls = function () {
    var s = this.state, el = this.el;
    var qEl = q1('[data-f=q]', el); if (qEl && qEl.value !== s.q) { qEl.value = s.q; }
    ['wl:workload', 'ty:type', 'so:sort'].forEach(function (pair) {
      var kv = pair.split(':'), sel = q1('[data-f=' + kv[1] + ']', el);
      if (sel) { sel.value = s[kv[0]]; }
    });
    qa('.chip', el).forEach(function (c) { c.setAttribute('aria-pressed', c.getAttribute('data-status') === s.st && s.st ? 'true' : 'false'); });
    var co = q1('[data-f=changed]', el); if (co) { co.checked = s.co; }
    var gr = q1('[data-f=group]', el); if (gr) { gr.checked = s.gr; }
    el.classList.toggle('changed-only', !!s.co);
    COLS.forEach(function (c) { el.classList.toggle('hc-' + c, s.hc.indexOf(c) !== -1); });
    qa('[data-col-toggle]', el).forEach(function (cb) { cb.checked = s.hc.indexOf(cb.getAttribute('data-col-toggle')) === -1; });
    qa('thead th', el).forEach(function (th) {
      var b = q1('.sortbtn', th);
      if (b) { th.setAttribute('aria-sort', b.getAttribute('data-sort') === s.so ? (s.di === 'desc' ? 'descending' : 'ascending') : 'none'); }
    });
  };

  Scope.prototype.change = function (mutate, userAction) {
    mutate(this.state);
    this.lists.forEach(function (l) { l.page = 1; });
    this.render(userAction !== false);
    writeHash();
  };

  Scope.prototype.download = function (kind) {
    var filtered = /filtered$/.test(kind), fmt = kind.split('-')[0];
    var items = this.items.filter(function (it) { return !filtered || it.match; });
    var base = this.dlName + (filtered ? '-filtered' : '');
    if (this.dlMode === 'island') {
      var data = JSON.parse((doc.getElementById(this.islandId) || { textContent: '{"rows":[]}' }).textContent);
      var idx = [];
      items.forEach(function (it) { it.rows.forEach(function (r) { idx.push(r); }); });
      idx.sort(function (a, b) { return a - b; });
      var rows = idx.map(function (i) { return data.rows[i]; }).filter(Boolean);
      if (fmt === 'csv') {
        saveFile(base + '.csv', 'text/csv;charset=utf-8', toCsv(['Id', 'DisplayName', 'Type', 'DriftType', 'NormalizedData'],
          rows.map(function (r) { return [r.Id, r.DisplayName, r.Type, r.DriftType, r.NormalizedData]; })));
      } else {
        saveFile(base + '.json', 'application/json', JSON.stringify(rows, null, 2));
      }
      return;
    }
    var recs = items.map(function (it) {
      var pre = q1('.raw', it.el), text = pre ? pre.textContent : '', parsed = null, compact = text;
      try { parsed = JSON.parse(text); compact = JSON.stringify(parsed); } catch (e) { parsed = text; }
      return { it: it, parsed: parsed, compact: compact };
    });
    if (fmt === 'csv') {
      saveFile(base + '.csv', 'text/csv;charset=utf-8', toCsv(['Id', 'DisplayName', 'Type', 'Workload', 'Data'],
        recs.map(function (r) { return [r.it.id, r.it.dn, r.it.type, r.it.workload, r.compact]; })));
    } else {
      saveFile(base + '.json', 'application/json', JSON.stringify(recs.map(function (r) {
        return { id: r.it.id, displayName: r.it.dn, type: r.it.type, workload: r.it.workload, data: r.parsed };
      }), null, 2));
    }
  };

  Scope.prototype.bind = function () {
    var self = this, el = this.el, timer = null;
    el.addEventListener('input', function (e) {
      if (e.target.matches('[data-f=q]')) {
        clearTimeout(timer);
        var v = e.target.value.slice(0, 200);
        timer = setTimeout(function () { self.change(function (s) { s.q = v; }); }, 150);
      }
    });
    el.addEventListener('change', function (e) {
      var t = e.target, f = t.getAttribute('data-f');
      if (f === 'workload') { self.change(function (s) { s.wl = t.value; }); }
      else if (f === 'type') { self.change(function (s) { s.ty = t.value; }); }
      else if (f === 'sort') { self.change(function (s) { s.so = t.value; s.di = 'asc'; self.dirty = true; }); }
      else if (f === 'changed') { self.change(function (s) { s.co = t.checked; }); }
      else if (f === 'group') { self.change(function (s) { s.gr = t.checked; self.dirty = true; }); }
      else if (t.hasAttribute('data-col-toggle')) {
        var c = t.getAttribute('data-col-toggle');
        self.change(function (s) {
          s.hc = s.hc.filter(function (x) { return x !== c; });
          if (!t.checked) { s.hc.push(c); }
        }, false);
      } else if (t.hasAttribute('data-pgsize')) {
        self.change(function (s) { s.sz = parseInt(t.value, 10) || 50; });
      }
    });
    el.addEventListener('click', function (e) {
      var t = e.target.closest('button');
      if (!t || !el.contains(t)) { return; }
      if (t.classList.contains('chip')) {
        var st = t.getAttribute('data-status');
        self.change(function (s) { s.st = s.st === st ? '' : st; });
      } else if (t.classList.contains('sortbtn')) {
        var key = t.getAttribute('data-sort');
        self.change(function (s) {
          if (s.so === key) { s.di = s.di === 'asc' ? 'desc' : 'asc'; } else { s.so = key; s.di = 'asc'; }
          self.dirty = true;
        });
      } else if (t.hasAttribute('data-pg')) {
        var pager = t.closest('[data-pager]'), l = pager && pager._list;
        if (l) { l.page += t.getAttribute('data-pg') === 'next' ? 1 : -1; self.render(true); }
      } else if (t.classList.contains('copybtn')) {
        var holder = t.closest('.cp'), v = holder && q1('.v', holder);
        if (v) { copyText(v.textContent, t); }
      } else if (t.getAttribute('data-act') === 'clear') {
        self.change(function (s) { var d = self.defaults; s.q = d.q; s.st = d.st; s.wl = d.wl; s.ty = d.ty; });
      } else if (t.getAttribute('data-act') === 'copylink') {
        copyText(location.href, t);
      } else if (t.getAttribute('data-act') === 'expand' || t.getAttribute('data-act') === 'collapse') {
        var open = t.getAttribute('data-act') === 'expand';
        self.items.forEach(function (it) {
          if (!it.match || it.el.classList.contains('pg-hidden')) { return; }
          qa('tr.detail details', it.el).forEach(function (d) { if (d.parentElement.tagName === 'TD') { d.open = open; } });
        });
      } else if (t.getAttribute('data-act') === 'groups-open' || t.getAttribute('data-act') === 'groups-close') {
        var o = t.getAttribute('data-act') === 'groups-open';
        qa('details.wl-group', el).forEach(function (g) { g.open = o; });
      } else if (t.hasAttribute('data-dl')) {
        self.download(t.getAttribute('data-dl'));
        var menu = t.closest('.menu'); if (menu) { menu.removeAttribute('open'); }
      }
    });
  };

  /* ---------- URL hash state ---------- */
  function parseHash() {
    var raw = location.hash.replace(/^#/, ''), i = raw.indexOf('?');
    var section = i === -1 ? raw : raw.slice(0, i), qs = i === -1 ? '' : raw.slice(i + 1), params = {};
    try { section = decodeURIComponent(section); } catch (e) { section = ''; }
    qs.split('&').forEach(function (pair) {
      if (!pair) { return; }
      var kv = pair.split('=');
      try { params[decodeURIComponent(kv[0])] = decodeURIComponent((kv[1] || '').replace(/\+/g, ' ')); } catch (e) { /* ignore malformed */ }
    });
    return { section: section, params: params };
  }

  function optionValues(scope, name) {
    var sel = q1('[data-f=' + name + ']', scope.el);
    return sel ? qa('option', sel).map(function (o) { return o.value; }) : [];
  }

  function applyParams(scope, params) {
    var d = scope.defaults, s = scope.state, p = scope.prefix;
    function get(k) { return Object.prototype.hasOwnProperty.call(params, p + k) ? params[p + k] : null; }
    var v;
    s.q = (v = get('q')) !== null ? v.slice(0, 200) : d.q;
    var statuses = qa('.chip', scope.el).map(function (c) { return c.getAttribute('data-status'); });
    s.st = (v = get('st')) !== null && statuses.indexOf(v) !== -1 ? v : d.st;
    s.wl = (v = get('wl')) !== null && optionValues(scope, 'workload').indexOf(v) !== -1 ? v : d.wl;
    s.ty = (v = get('ty')) !== null && optionValues(scope, 'type').indexOf(v) !== -1 ? v : d.ty;
    var sorts = optionValues(scope, 'sort');
    s.so = (v = get('so')) !== null && SORT_KEYS.indexOf(v) !== -1 && sorts.indexOf(v) !== -1 ? v : d.so;
    s.di = (v = get('di')) === 'desc' ? 'desc' : d.di;
    s.sz = (v = parseInt(get('sz'), 10)) && SIZES.indexOf(v) !== -1 ? v : d.sz;
    s.gr = scope.groupable && (v = get('gr')) !== null ? v === '1' : d.gr;
    s.co = (v = get('co')) !== null ? v === '1' : d.co;
    var available = qa('[data-col-toggle]', scope.el).map(function (c) { return c.getAttribute('data-col-toggle'); });
    s.hc = (v = get('hc')) !== null ? v.split(',').filter(function (c) { return COLS.indexOf(c) !== -1 && available.indexOf(c) !== -1; }) : d.hc.slice();
    scope.dirty = true;
  }

  function serialize() {
    var parts = [];
    scopes.forEach(function (sc) {
      var d = sc.defaults, s = sc.state;
      function add(k, v) { parts.push(encodeURIComponent(sc.prefix + k) + '=' + encodeURIComponent(v)); }
      if (s.q !== d.q) { add('q', s.q); }
      if (s.st !== d.st) { add('st', s.st); }
      if (s.wl !== d.wl) { add('wl', s.wl); }
      if (s.ty !== d.ty) { add('ty', s.ty); }
      if (s.so !== d.so) { add('so', s.so); }
      if (s.di !== d.di) { add('di', s.di); }
      if (s.sz !== d.sz) { add('sz', s.sz); }
      if (s.gr !== d.gr) { add('gr', s.gr ? '1' : '0'); }
      if (s.co !== d.co) { add('co', s.co ? '1' : '0'); }
      if (s.hc.join(',') !== d.hc.join(',')) { add('hc', s.hc.join(',')); }
    });
    return parts.join('&');
  }

  function writeHash() {
    var qs = serialize(), h = (currentSection || qs) ? '#' + currentSection + (qs ? '?' + qs : '') : '';
    try { history.replaceState(null, '', location.pathname + location.search + h); } catch (e) { /* ignore */ }
  }

  function scrollToSection(section) {
    var t = section && doc.getElementById(section);
    if (t) { t.scrollIntoView(); }
  }

  /* ---------- init ---------- */
  function addCopyButtons(root) {
    qa('.cp', root).forEach(function (s) {
      if (s.querySelector('.copybtn')) { return; }
      s.appendChild(mk('button', { type: 'button', 'class': 'copybtn', 'aria-label': s.classList.contains('cp-id') ? 'Copy ID' : 'Copy value' }, 'Copy'));
    });
  }
  qa('[data-scope]').forEach(function (el, i) { scopes.push(new Scope(el, i)); });

  var initial = parseHash();
  currentSection = doc.getElementById(initial.section) ? initial.section : '';
  scopes.forEach(function (sc) { applyParams(sc, initial.params); sc.render(false); });
  if (currentSection) { scrollToSection(currentSection); }

  window.addEventListener('hashchange', function () {
    var h = parseHash();
    currentSection = doc.getElementById(h.section) ? h.section : '';
    if (Object.keys(h.params).length) {
      scopes.forEach(function (sc) { applyParams(sc, h.params); sc.render(false); });
    }
    scrollToSection(currentSection);
    writeHash();
  });

  qa('a[data-nav]').forEach(function (a) {
    a.addEventListener('click', function () { currentSection = (a.getAttribute('href') || '').replace(/^#/, ''); setTimeout(writeHash, 0); });
  });

  var opened = [];
  window.addEventListener('beforeprint', function () {
    opened = [];
    qa('details.wl-group').forEach(function (g) { if (!g.open) { g.open = true; opened.push(g); } });
  });
  window.addEventListener('afterprint', function () { opened.forEach(function (g) { g.open = false; }); opened = []; });
})();
'@
    return ($js -replace "`r`n", "`n").Trim()
}
