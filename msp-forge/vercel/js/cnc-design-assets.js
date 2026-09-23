/* =====================================================================
   cnc-design-assets.js :: designer mode for every Care Net page
   Version: 1.0 | 23/09/2026 | HSF FORGE build contract, section 6
   Load: <script src="/js/cnc-design-assets.js" defer></script> before </body>.

   OFF BY DEFAULT. Unless the address carries ?design=1 or #design this
   script reads nothing, adds nothing and loads nothing: no stylesheet, no
   markup, no listeners beyond one hashchange check. Visitors and
   Lighthouse see no difference.

   ON (?design=1 or #design):
     1. Reads the page's specification block
          <script type="application/json" id="cnc-asset-spec">
            {"page": "...", "assets": [{id, block, purpose, type, formats,
             width, height, ratio, max_kb, colour, alt, file_name, delivery,
             status, notes}, ...]}
          </script>
     2. Outlines every element marked data-asset="<id>" and pins a numbered
        label to it (numbering from 1, in the order of the specification).
     3. Opens a panel listing every asset with its full specification, a
        Show on page button, and Copy JSON for one asset or the whole page.
   It never throws: a missing or broken block is reported in the panel.
   The panel lives in a shadow root so page styles cannot reach it, and it
   works from the keyboard (Tab through it, Escape hides it).
   hsf/build_asset_manifest.py reads the same blocks to write
   DESIGNER-ASSETS.md and vercel/design/assets.json.
   ===================================================================== */
(function (w, d) {
  'use strict';
  if (w.__cncDesignAssets) return;
  w.__cncDesignAssets = true;

  var SPEC_ID = 'cnc-asset-spec';
  var ROOT_ID = 'cnc-da-root';
  var LAYER_ID = 'cnc-da-layer';
  var CSS_ID = 'cnc-da-css';

  /* Resolve the stylesheet next to this script, so it also works when the
     pages are served from a sub path inside MyClinicOnline. */
  var CSS_HREF = (function () {
    var fallback = '/css/cnc-design-assets.css';
    try {
      var s = d.currentScript;
      if (s && s.src) {
        var out = s.src.replace(/\/js\/cnc-design-assets\.js(?:[?#].*)?$/, '/css/cnc-design-assets.css');
        if (out !== s.src) return out;
      }
    } catch (e) { /* fall through */ }
    return fallback;
  })();

  function wanted() {
    try {
      if (new URLSearchParams(w.location.search).get('design') === '1') return true;
    } catch (e) { /* very old browser */ }
    return w.location.hash === '#design';
  }

  var state = null;

  function warn(msg) { if (w.console) w.console.warn('cnc-design-assets: ' + msg); }

  function safe(fn) {
    return function () {
      try { return fn.apply(this, arguments); } catch (e) { warn(e && e.message ? e.message : String(e)); }
    };
  }

  /* ------------------------------------------------------------- data */
  var KNOWN = ['id', 'block', 'purpose', 'type', 'formats', 'width', 'height', 'ratio', 'max_kb',
    'colour', 'alt', 'file_name', 'delivery', 'status', 'notes'];

  function readSpec() {
    var el = d.getElementById(SPEC_ID);
    if (!el) {
      return { raw: null, page: w.location.pathname, assets: [],
        problems: ['This page has no asset specification block (a script element with id cnc-asset-spec).'] };
    }
    var j;
    try { j = JSON.parse(el.textContent || ''); } catch (e) {
      return { raw: null, page: w.location.pathname, assets: [],
        problems: ['The asset specification block is not valid JSON: ' + (e && e.message ? e.message : 'parse error') + '.'] };
    }
    var problems = [];
    if (!j || typeof j !== 'object' || Array.isArray(j)) {
      return { raw: null, page: w.location.pathname, assets: [],
        problems: ['The asset specification block must be a JSON object with "page" and "assets".'] };
    }
    var list = Array.isArray(j.assets) ? j.assets : [];
    if (!Array.isArray(j.assets)) problems.push('The specification has no "assets" list.');
    var assets = [];
    var seen = {};
    for (var i = 0; i < list.length; i++) {
      var a = list[i];
      if (!a || typeof a !== 'object' || Array.isArray(a)) { problems.push('Entry ' + (i + 1) + ' is not an object and was skipped.'); continue; }
      var id = a.id == null ? '' : String(a.id).trim();
      if (!id) { problems.push('Entry ' + (i + 1) + ' has no id and was skipped.'); continue; }
      if (seen[id]) { problems.push('The id "' + id + '" appears more than once; only the first entry is used.'); continue; }
      seen[id] = true;
      assets.push({ n: assets.length + 1, id: id, data: a });
    }
    return { raw: j, page: j.page ? String(j.page) : w.location.pathname, assets: assets, problems: problems };
  }

  function collectSlots(root) {
    var map = {};
    var order = [];
    var nodes = d.querySelectorAll('[data-asset]');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (root && root.contains(el)) continue;
      var id = (el.getAttribute('data-asset') || '').trim();
      if (!id) continue;
      if (!map[id]) { map[id] = []; order.push(id); }
      map[id].push(el);
    }
    return { map: map, order: order };
  }

  function isShown(el) {
    if (!el || !el.isConnected) return false;
    if (!el.getClientRects || el.getClientRects().length === 0) return false;
    var r = el.getBoundingClientRect();
    return r.width > 0 || r.height > 0;
  }

  function fmt(v) {
    if (v == null || v === '') return '';
    if (Array.isArray(v)) return v.map(function (x) { return String(x); }).join(', ');
    if (typeof v === 'object') { try { return JSON.stringify(v); } catch (e) { return String(v); } }
    return String(v);
  }

  function sizeText(a) {
    var wd = a.width, ht = a.height;
    if (wd == null && ht == null) return '';
    return (wd == null ? 'any' : String(wd)) + ' \u00d7 ' + (ht == null ? 'any' : String(ht)) + ' px';
  }

  function statusOf(a) {
    var s = String(a.status || '').toLowerCase();
    return s === 'existing' || s === 'needed' ? s : 'unknown';
  }

  /* ------------------------------------------------------------ DOM helpers */
  function h(doc, tag, attrs, kids) {
    var el = doc.createElement(tag);
    if (attrs) {
      for (var k in attrs) {
        if (!Object.prototype.hasOwnProperty.call(attrs, k) || attrs[k] == null || attrs[k] === false) continue;
        if (k === 'text') el.textContent = attrs[k];
        else if (k === 'className') el.className = attrs[k];
        else el.setAttribute(k, attrs[k] === true ? '' : String(attrs[k]));
      }
    }
    if (kids) {
      for (var i = 0; i < kids.length; i++) {
        var c = kids[i];
        if (c == null || c === false) continue;
        el.appendChild(typeof c === 'string' ? doc.createTextNode(c) : c);
      }
    }
    return el;
  }

  function copyText(text) {
    if (w.navigator && w.navigator.clipboard && w.isSecureContext) {
      return w.navigator.clipboard.writeText(text).then(function () { return true; }, function () { return legacyCopy(text); });
    }
    return Promise.resolve(legacyCopy(text));
  }

  function legacyCopy(text) {
    var ta = d.createElement('textarea');
    ta.value = text;
    ta.setAttribute('readonly', '');
    ta.style.position = 'fixed';
    ta.style.top = '-1000px';
    ta.style.opacity = '0';
    d.body.appendChild(ta);
    var ok = false;
    try { ta.select(); ok = d.execCommand('copy'); } catch (e) { ok = false; }
    d.body.removeChild(ta);
    return ok;
  }

  /* ------------------------------------------------------------ build */
  function start() {
    if (state || !d.body) return;
    var spec = readSpec();
    var byId = {};
    for (var i = 0; i < spec.assets.length; i++) byId[spec.assets[i].id] = spec.assets[i];

    state = {
      spec: spec, byId: byId, slots: { map: {}, order: [] }, marked: [], labels: [],
      labelsOn: true, raf: 0, timer: 0, mo: null, rescanTimer: 0, listeners: []
    };

    /* Page side styles: slot outlines and the label layer. */
    if (!d.getElementById(CSS_ID)) {
      var link = h(d, 'link', { id: CSS_ID, rel: 'stylesheet', href: CSS_HREF });
      (d.head || d.documentElement).appendChild(link);
    }

    var layer = h(d, 'div', { id: LAYER_ID, className: 'cnc-da-layer', 'aria-hidden': 'true' });
    d.body.appendChild(layer);
    state.layer = layer;

    buildPanel();
    scanSlots();
    reposition();

    function onMove() {
      if (!state || state.raf) return;
      state.raf = w.requestAnimationFrame(function () { if (state) { state.raf = 0; reposition(); } });
    }
    listen(w, 'scroll', onMove, { capture: true, passive: true });
    listen(w, 'resize', onMove, { passive: true });
    state.timer = w.setInterval(safe(reposition), 800);

    if (w.MutationObserver) {
      state.mo = new MutationObserver(function (records) {
        if (!state) return;
        for (var i = 0; i < records.length; i++) {
          var t = records[i].target;
          if (t === state.layer || state.layer.contains(t) || (state.host && (t === state.host || state.host.contains(t)))) continue;
          w.clearTimeout(state.rescanTimer);
          state.rescanTimer = w.setTimeout(safe(function () { if (state) { scanSlots(); reposition(); } }), 250);
          return;
        }
      });
      state.mo.observe(d.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-asset', 'hidden'] });
    }

    w.CNCDesignAssets = {
      active: true,
      spec: spec.raw,
      slotIds: function () { return state ? state.slots.order.slice() : []; },
      open: function () { setCollapsed(false); },
      close: function () { setCollapsed(true); }
    };
  }

  function listen(target, type, fn, opts) {
    target.addEventListener(type, fn, opts);
    state.listeners.push([target, type, fn, opts]);
  }

  function stop() {
    if (!state) return;
    var s = state;
    state = null;
    s.listeners.forEach(function (l) { l[0].removeEventListener(l[1], l[2], l[3]); });
    if (s.mo) s.mo.disconnect();
    w.clearInterval(s.timer);
    w.clearTimeout(s.rescanTimer);
    if (s.raf) w.cancelAnimationFrame(s.raf);
    unmark(s);
    [s.layer, s.host, d.getElementById(CSS_ID)].forEach(function (n) { if (n && n.parentNode) n.parentNode.removeChild(n); });
    d.documentElement.classList.remove('cnc-da-nolabels');
    w.CNCDesignAssets = { active: false };
  }

  function unmark(s) {
    s.marked.forEach(function (el) {
      el.classList.remove('cnc-da-slot', 'cnc-da-needed', 'cnc-da-existing', 'cnc-da-unknown', 'cnc-da-orphan', 'cnc-da-flash');
      el.removeAttribute('data-cnc-da-n');
    });
    s.marked = [];
  }

  /* Find every slot, mark it, and lay a numbered label over it. */
  function scanSlots() {
    unmark(state);
    state.slots = collectSlots(state.host);
    state.layer.textContent = '';
    state.labels = [];
    var order = state.slots.order;
    for (var i = 0; i < order.length; i++) {
      var id = order[i];
      var a = state.byId[id];
      var els = state.slots.map[id];
      for (var j = 0; j < els.length; j++) {
        var el = els[j];
        var kind = a ? statusOf(a.data) : 'orphan';
        el.classList.add('cnc-da-slot', 'cnc-da-' + kind);
        el.setAttribute('data-cnc-da-n', a ? String(a.n) : '?');
        state.marked.push(el);
        var label = h(d, 'span', { className: 'cnc-da-label cnc-da-label-' + kind },
          [h(d, 'b', { text: a ? String(a.n) : '?' }), ' ' + (a ? id : id + ' (no spec)')]);
        state.layer.appendChild(label);
        state.labels.push({ el: el, label: label });
      }
    }
    updateSlotInfo();
  }

  function reposition() {
    if (!state) return;
    var vw = w.innerWidth, vh = w.innerHeight;
    for (var i = 0; i < state.labels.length; i++) {
      var it = state.labels[i];
      if (!state.labelsOn || !isShown(it.el)) { it.label.hidden = true; continue; }
      var r = it.el.getBoundingClientRect();
      if (r.bottom < 0 || r.top > vh || r.right < 0 || r.left > vw) { it.label.hidden = true; continue; }
      it.label.hidden = false;
      var x = Math.max(4, Math.min(r.left + 4, vw - 40));
      var y = Math.max(4, r.top + 4);
      it.label.style.transform = 'translate(' + Math.round(x) + 'px,' + Math.round(y) + 'px)';
    }
  }

  /* ------------------------------------------------------------ panel */
  function buildPanel() {
    var host = h(d, 'div', { id: ROOT_ID });
    d.body.insertBefore(host, d.body.firstChild);
    state.host = host;
    var root = host.attachShadow ? host.attachShadow({ mode: 'open' }) : host;
    state.root = root;
    var doc = d;
    var spec = state.spec;

    var needed = 0, existing = 0;
    spec.assets.forEach(function (a) {
      var s = statusOf(a.data);
      if (s === 'needed') needed++;
      else if (s === 'existing') existing++;
    });

    var status = h(doc, 'p', { className: 'live', role: 'status', 'aria-live': 'polite' });
    state.status = status;

    var copyAll = h(doc, 'button', { type: 'button', className: 'btn btn-red', text: 'Copy page JSON', disabled: !spec.raw });
    copyAll.addEventListener('click', safe(function () {
      doCopy(JSON.stringify(spec.raw, null, 2), 'The whole page specification');
    }));

    var filter = h(doc, 'select', { id: 'cnc-da-filter' }, [
      h(doc, 'option', { value: 'all', text: 'All assets (' + spec.assets.length + ')' }),
      h(doc, 'option', { value: 'needed', text: 'Needed (' + needed + ')' }),
      h(doc, 'option', { value: 'existing', text: 'Existing (' + existing + ')' })
    ]);
    filter.addEventListener('change', safe(function () { applyFilter(filter.value); }));

    var labelsBtn = h(doc, 'button', { type: 'button', className: 'btn btn-line', 'aria-pressed': 'true', text: 'Slot labels shown' });
    labelsBtn.addEventListener('click', safe(function () {
      state.labelsOn = !state.labelsOn;
      labelsBtn.setAttribute('aria-pressed', state.labelsOn ? 'true' : 'false');
      labelsBtn.textContent = state.labelsOn ? 'Slot labels shown' : 'Slot labels hidden';
      d.documentElement.classList.toggle('cnc-da-nolabels', !state.labelsOn);
      reposition();
    }));

    var hideBtn = h(doc, 'button', { type: 'button', className: 'btn btn-line', 'aria-expanded': 'true', 'aria-controls': 'cnc-da-panel', text: 'Hide panel' });
    hideBtn.addEventListener('click', safe(function () { setCollapsed(true); }));

    var summary = spec.assets.length + (spec.assets.length === 1 ? ' asset' : ' assets') +
      ', ' + needed + ' needed, ' + existing + ' existing';

    var problems = spec.problems.slice();
    var problemBox = h(doc, 'div', { className: 'notice', hidden: problems.length ? null : true, id: 'cnc-da-problems' });
    state.problemBox = problemBox;

    var list = h(doc, 'ol', { className: 'list', id: 'cnc-da-list' });
    spec.assets.forEach(function (a) { list.appendChild(card(doc, a)); });
    state.list = list;

    var empty = h(doc, 'p', { className: 'empty', text: 'No assets are listed for this page yet.', hidden: spec.assets.length ? true : null });

    var orphanBox = h(doc, 'section', { className: 'orphans', 'aria-labelledby': 'cnc-da-orph-h', hidden: true },
      [h(doc, 'h3', { id: 'cnc-da-orph-h', text: 'Slots on this page with no specification entry' }), h(doc, 'ul', {})]);
    state.orphanBox = orphanBox;

    var fallback = h(doc, 'div', { className: 'fallback', hidden: true }, [
      h(doc, 'label', { 'for': 'cnc-da-fallback', text: 'The browser blocked copying. Select this text and copy it yourself.' }),
      h(doc, 'textarea', { id: 'cnc-da-fallback', readonly: true, rows: '8' })
    ]);
    state.fallback = fallback;

    var panel = h(doc, 'aside', { className: 'panel', id: 'cnc-da-panel', 'aria-labelledby': 'cnc-da-title' }, [
      h(doc, 'div', { className: 'head' }, [
        h(doc, 'p', { className: 'eyebrow', text: 'Designer mode' }),
        h(doc, 'h2', { id: 'cnc-da-title', text: 'Asset specification' }),
        h(doc, 'p', { className: 'meta' }, ['Page ', h(doc, 'code', { text: spec.page }), ': ' + summary + '.']),
        h(doc, 'div', { className: 'tools' }, [
          copyAll,
          h(doc, 'label', { className: 'filter', 'for': 'cnc-da-filter' }, ['Show ']),
          filter,
          labelsBtn,
          hideBtn
        ]),
        status
      ]),
      problemBox,
      fallback,
      list,
      empty,
      orphanBox,
      h(doc, 'p', { className: 'foot', text: 'Numbers match the labels on the page and DESIGNER-ASSETS.md. Supply every format listed for an asset, at the pixel size shown and at or under its maximum file size, named as under File name and delivered to the path under Delivery.' })
    ]);
    state.panel = panel;
    state.hideBtn = hideBtn;

    var tab = h(doc, 'button', { type: 'button', className: 'tab', hidden: true, 'aria-expanded': 'false', 'aria-controls': 'cnc-da-panel',
      text: 'Show asset panel (' + spec.assets.length + ')' });
    tab.addEventListener('click', safe(function () { setCollapsed(false); }));
    state.tab = tab;

    panel.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' || e.key === 'Esc') { e.preventDefault(); safe(setCollapsed)(true); }
    });

    root.appendChild(h(doc, 'link', { rel: 'stylesheet', href: CSS_HREF }));
    root.appendChild(panel);
    root.appendChild(tab);
    renderProblems();
  }

  function renderProblems(extra) {
    var box = state.problemBox;
    var all = state.spec.problems.concat(extra || []);
    box.textContent = '';
    if (!all.length) { box.hidden = true; return; }
    box.appendChild(h(d, 'p', { className: 'notice-h', text: all.length === 1 ? 'One thing to check' : all.length + ' things to check' }));
    var ul = h(d, 'ul', {});
    all.forEach(function (p) { ul.appendChild(h(d, 'li', { text: p })); });
    box.appendChild(ul);
    box.hidden = false;
  }

  function row(doc, label, value, code) {
    var v = fmt(value);
    var dd = v
      ? h(doc, 'dd', {}, [code ? h(doc, 'code', { text: v }) : v])
      : h(doc, 'dd', { className: 'none', text: 'Not specified' });
    return h(doc, 'div', { className: 'row' }, [h(doc, 'dt', { text: label }), dd]);
  }

  function card(doc, a) {
    var x = a.data;
    var st = statusOf(x);
    var pill = h(doc, 'span', { className: 'pill pill-' + st, text: st === 'needed' ? 'Needed' : (st === 'existing' ? 'Existing' : 'Status not set') });
    var dl = h(doc, 'dl', { className: 'spec' }, [
      row(doc, 'Block', x.block),
      row(doc, 'Purpose', x.purpose),
      row(doc, 'Type', x.type),
      row(doc, 'Formats', x.formats),
      row(doc, 'Size', sizeText(x)),
      row(doc, 'Ratio', x.ratio),
      row(doc, 'Maximum file size', x.max_kb == null || x.max_kb === '' ? '' : fmt(x.max_kb) + ' KB'),
      row(doc, 'Colour', x.colour),
      row(doc, 'Alt text', x.alt),
      row(doc, 'File name', x.file_name, true),
      row(doc, 'Delivery', x.delivery, true),
      row(doc, 'Notes', x.notes)
    ]);
    /* Anything else in the entry is shown too, so the panel always carries
       the full specification. */
    Object.keys(x).forEach(function (k) {
      if (KNOWN.indexOf(k) !== -1) return;
      var label = k.replace(/_/g, ' ');
      dl.appendChild(row(doc, label.charAt(0).toUpperCase() + label.slice(1), x[k]));
    });
    var onPage = h(doc, 'dd', { text: 'Checking...' });
    dl.appendChild(h(doc, 'div', { className: 'row' }, [h(doc, 'dt', { text: 'On this page' }), onPage]));

    var showBtn = h(doc, 'button', { type: 'button', className: 'btn btn-line', text: 'Show on page' });
    showBtn.addEventListener('click', safe(function () { showSlot(a); }));
    var copyBtn = h(doc, 'button', { type: 'button', className: 'btn btn-line', text: 'Copy JSON' });
    copyBtn.addEventListener('click', safe(function () {
      doCopy(JSON.stringify(x, null, 2), 'Asset ' + a.n + ' (' + a.id + ')');
    }));

    var li = h(doc, 'li', { className: 'card', 'data-status': st, 'data-id': a.id }, [
      h(doc, 'div', { className: 'card-head' }, [
        h(doc, 'span', { className: 'num', 'aria-hidden': 'true', text: String(a.n) }),
        h(doc, 'h3', {}, [h(doc, 'span', { className: 'sr', text: 'Asset ' + a.n + ': ' }), a.id]),
        pill
      ]),
      dl,
      h(doc, 'div', { className: 'card-actions' }, [showBtn, copyBtn])
    ]);
    a.ui = { onPage: onPage, showBtn: showBtn, li: li };
    return li;
  }

  /* Fill in "On this page" for every card and list slots with no entry. */
  function updateSlotInfo() {
    var map = state.slots.map;
    var missing = [];
    state.spec.assets.forEach(function (a) {
      if (!a.ui) return;
      var els = map[a.id] || [];
      var shown = els.filter(isShown);
      var text;
      if (!els.length) {
        text = 'No slot found. Mark the element with data-asset="' + a.id + '".';
        missing.push(a.id);
      } else {
        text = els.length + (els.length === 1 ? ' slot' : ' slots');
        if (shown.length) {
          var r = shown[0].getBoundingClientRect();
          text += ', shown at ' + Math.round(r.width) + ' \u00d7 ' + Math.round(r.height) + ' CSS px on this screen';
        } else {
          text += ', not visible right now (for example a meta tag or a hidden state)';
        }
        var src = els[0].currentSrc || els[0].getAttribute('src') || els[0].getAttribute('content') || '';
        if (src) text += '. Current file: ' + src;
      }
      a.ui.onPage.textContent = text;
      a.ui.onPage.className = els.length ? '' : 'warn';
    });

    var orphans = state.slots.order.filter(function (id) { return !state.byId[id]; });
    var ul = state.orphanBox.querySelector('ul');
    ul.textContent = '';
    orphans.forEach(function (id) {
      ul.appendChild(h(d, 'li', {}, [h(d, 'code', { text: id }), ' is marked on the page but has no entry in the specification.']));
    });
    state.orphanBox.hidden = orphans.length === 0;
  }

  function applyFilter(v) {
    var shown = 0;
    state.spec.assets.forEach(function (a) {
      if (!a.ui) return;
      var st = statusOf(a.data);
      var on = v === 'all' || st === v;
      a.ui.li.hidden = !on;
      if (on) shown++;
    });
    say(shown + (shown === 1 ? ' asset' : ' assets') + ' listed.');
  }

  function showSlot(a) {
    var els = (state.slots.map[a.id] || []).filter(isShown);
    if (!els.length) {
      say('Asset ' + a.n + ' has no visible slot on the page right now.');
      return;
    }
    var el = els[0];
    var reduce = w.matchMedia && w.matchMedia('(prefers-reduced-motion: reduce)').matches;
    try { el.scrollIntoView({ block: 'center', behavior: reduce ? 'auto' : 'smooth' }); } catch (e) { el.scrollIntoView(); }
    el.classList.add('cnc-da-flash');
    w.setTimeout(function () { el.classList.remove('cnc-da-flash'); }, 1800);
    say('Asset ' + a.n + ' (' + a.id + ') is outlined on the page.');
  }

  function doCopy(text, what) {
    copyText(text).then(function (ok) {
      if (!state) return;
      if (ok) {
        state.fallback.hidden = true;
        say(what + ' was copied as JSON.');
      } else {
        var ta = state.fallback.querySelector('textarea');
        ta.value = text;
        state.fallback.hidden = false;
        ta.focus();
        ta.select();
        say('Copying was blocked, so the JSON is shown in a box at the top of the panel.');
      }
    });
  }

  function say(msg) {
    if (!state) return;
    state.status.textContent = '';
    w.setTimeout(function () { if (state) state.status.textContent = msg; }, 30);
  }

  function setCollapsed(on) {
    if (!state) return;
    state.panel.hidden = !!on;
    state.tab.hidden = !on;
    state.hideBtn.setAttribute('aria-expanded', on ? 'false' : 'true');
    if (on) state.tab.focus();
    else state.hideBtn.focus();
  }

  /* ------------------------------------------------------------ wiring */
  function boot() {
    try { start(); } catch (e) {
      warn(e && e.message ? e.message : String(e));
      try { stop(); } catch (e2) { /* nothing more to undo */ }
    }
  }

  if (wanted()) {
    if (d.readyState === 'loading') d.addEventListener('DOMContentLoaded', boot);
    else boot();
  }

  w.addEventListener('hashchange', function () {
    var on = wanted();
    if (on && !state) boot();
    else if (!on && state) safe(stop)();
  });
})(window, document);
