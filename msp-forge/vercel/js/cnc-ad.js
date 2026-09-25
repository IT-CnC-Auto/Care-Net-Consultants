/* cnc-ad.js v1.1 25/09/2026 Bee-Inspect banners (contract 16.3, BUILD-STATE.md); copy in /hsf/ads.js */
(function (w, d) {
'use strict';
var A = w.HSF_ADS, KEY = 'cnc_bee_ads_v1', DAY = 864e5;
var S = { sub: !!(A && A.subscriber_stub), hidden: !!(A && A.tenant_stub && A.tenant_stub.hidden), brand: null, slots: [], seen: {} };
var near = null, look = null, live = null;
function flag() { return !!(w.CNC_FLAGS && w.CNC_FLAGS.bee_inspect_ads); }
function enabled() { return flag() && !!A && !S.hidden; }
function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }
/* visible text: Bee-Inspect and Bee-Matched never break at their hyphen */
function tx(s) { return esc(s).replace(/Bee-/g, 'Bee&#8209;'); }
function band(n) { if (n == null || isNaN(n)) return 'na'; n = Number(n); return n <= 0 ? '0' : n <= 2 ? '1to2' : n <= 5 ? '3to5' : '6plus'; }

function readStore() { try { return JSON.parse(w.localStorage.getItem(KEY) || '{}') || {}; } catch (e) { return {}; } }
function writeStore(o) { try { w.localStorage.setItem(KEY, JSON.stringify(o)); } catch (e) { /* private mode */ } }
function stored(id) { var o = readStore(), x = o[id]; if (x && x.u > Date.now()) return x.m; if (x) { delete o[id]; writeStore(o); } return null; }
function remember(id, m) { var o = readStore(); if (m) o[id] = { m: m, u: Date.now() + (A.dismiss_days || 14) * DAY }; else delete o[id]; writeStore(o); }

function page() { var p = (location.pathname || '/').replace(/\.html$/, '').replace(/\/+$/, ''); return p || '/'; }
function track(ev, e) {
  if (!enabled()) return;
  var body = JSON.stringify({ event: ev, ad_id: e.id, variant: variant(e), page: page(), industry: e.ctx.industry || null, f_band: e.ctx.fBand || 'na' });
  var url = ((w.CNC_CONFIG && w.CNC_CONFIG.apiBase) || '') + '/api/hsf-events';
  try {
    if (w.fetch) w.fetch(url, { method: 'POST', body: body, keepalive: true, credentials: 'omit', headers: { 'Content-Type': 'application/json' } }).catch(function () {});
    else if (navigator.sendBeacon) navigator.sendBeacon(url, new Blob([body], { type: 'application/json' }));
  } catch (x) { /* never in the way */ }
}

/* ---- links */
function withUtm(href, id, v) {
  var u, U = A.utm || {};
  try { u = new URL(href, location.href); } catch (e) { return href; }
  if ((U.never_on_hosts || []).indexOf(u.hostname) !== -1 || !/^https?:$/.test(u.protocol)) return href;
  ['utm_source', 'utm_medium', 'utm_campaign'].forEach(function (k) { u.searchParams.set(k, U[k]); });
  u.searchParams.set('utm_content', id + '_' + v);
  return u.origin === location.origin ? u.pathname + u.search + u.hash : u.href;
}

/* ---- what a banner shows */
function kind(e) { var ad = A.ads[e.id]; return e.strip || ad.kind === 'strip' ? 'strip' : ad.kind === 'tip' ? 'tip' : 'full'; }
function variant(e) {
  if (e.ctx.variant) return e.ctx.variant;
  if (e.strip) return 'strip';
  if (S.sub) return 'sub';
  var ad = A.ads[e.id], n = Number(e.ctx.n) || 0;
  return ad.kind === 'tip' ? 'tip' : ad.kind === 'strip' ? 'count' : (ad.headline_gaps || ad.headline_one) && n > 0 ? 'gaps' : 'base';
}
function fillN(t, n) { return String(t || '').replace('{n}', String(n)); }
function bee(s) {
  return '<svg class="cnc-ad-bee" viewBox="0 0 40 40" width="' + s + '" height="' + s + '" aria-hidden="true">'
    + '<path d="M18 9 15 4M22 9l3-5" stroke="#F0A32B" stroke-width="1.6" fill="none" stroke-linecap="round"/>'
    + '<ellipse cx="13" cy="15" rx="8" ry="5.5" transform="rotate(-28 13 15)" fill="#fff" opacity=".88"/>'
    + '<ellipse cx="27" cy="15" rx="8" ry="5.5" transform="rotate(28 27 15)" fill="#fff" opacity=".88"/>'
    + '<ellipse cx="20" cy="25" rx="9" ry="11" fill="#F0A32B"/>'
    + '<path d="M11.4 22h17.2M11.2 27h17.6M13.4 32h13.2" stroke="#0F0F0F" stroke-width="2.6"/>'
    + '<circle cx="20" cy="12" r="4.2" fill="#0F0F0F" stroke="#F0A32B" stroke-width="1"/></svg>';
}
function link(e, cls, q) {
  var ad = A.ads[e.id], p = q || (S.sub ? A.links.open_app : ad.primary), v = variant(e);
  var href = p.stub || /^https:\/\/wa\.me\//.test(p.href) ? p.href : withUtm(p.href, e.id, v);
  return '<a class="' + cls + '" href="' + esc(href) + '" target="_blank" rel="noopener" aria-label="' + esc(p.aria || p.label)
    + '" data-cta="bee_inspect_' + e.id.replace('-', '').toLowerCase() + (q ? '_sample' : '') + '" data-go>' + tx(p.label) + '</a>';
}
function html(e) {
  var ad = A.ads[e.id], U = A.ui, k = kind(e), n = Number(e.ctx.n) || 0, v = variant(e);
  var x = '<button type="button" class="cnc-ad-x" data-x aria-label="' + esc(ad.collapses ? U.collapse_label : U.dismiss_label) + '"><span aria-hidden="true">&times;</span></button>';
  var lbl = ' aria-label="' + esc(A.eyebrow) + '"';
  if (k === 'strip') {
    var t = e.strip ? ad.strip : S.sub ? U.subscriber_body : fillN(n === 1 ? ad.text_one : ad.text, n);
    return '<aside class="cnc-ad cnc-ad--strip' + (e.strip ? ' cnc-ad--fold' : '') + '"' + lbl + '>' + bee(26) + '<p class="cnc-ad-s">' + tx(t) + '</p>'
      + (e.strip ? '<button type="button" class="cnc-ad-show" data-show aria-label="' + esc(U.show_aria) + '">' + esc(U.show_label) + '</button>'
        : link(e, 'cnc-ad-lk') + x) + '</aside>';
  }
  if (k === 'tip') {
    return '<aside class="cnc-ad cnc-ad--tip"' + lbl + '>' + bee(26) + '<div class="cnc-ad-tx"><p class="cnc-ad-s">' + tx(S.sub ? U.subscriber_body : ad.tip) + '</p>'
      + '<details class="cnc-ad-how"><summary>' + esc(U.how_label) + '</summary><ol>' + U.how_steps.map(function (s) { return '<li>' + tx(s) + '</li>'; }).join('') + '</ol></details>'
      + link(e, 'cnc-ad-lk') + '</div>' + x + '</aside>';
  }
  var h = S.sub ? U.subscriber_headline : v === 'gaps' ? fillN(n === 1 ? (ad.headline_gaps_one || ad.headline_one) : (ad.headline_gaps || ad.headline), n) : ad.headline;
  return '<aside class="cnc-ad cnc-ad--full"' + lbl + ' data-v="' + esc(v) + '">' + bee(44)
    + '<div class="cnc-ad-tx"><p class="cnc-ad-eb">' + esc((S.brand && S.brand.label) || A.eyebrow) + '</p>'
    + '<p class="cnc-ad-h">' + tx(h) + '</p><p class="cnc-ad-b">' + tx(S.sub ? U.subscriber_body : ad.body) + '</p>'
    + (S.sub ? '' : '<p class="cnc-ad-p">' + esc(A.price.line) + '</p>') + '</div>'
    + '<div class="cnc-ad-ac">' + link(e, 'cnc-ad-go btn') + (!S.sub && ad.secondary ? link(e, 'cnc-ad-2', A.links[ad.secondary]) : '') + '</div>' + x + '</aside>';
}

/* ---- slots */
var SLOT = /\bcnc-ad-slot(--\w+)?\b/g;
function clear(el) { el.hidden = true; el.innerHTML = ''; el.className = el.className.replace(SLOT, '').trim(); }
function drop(el) { S.slots = S.slots.filter(function (e) { return e.el !== el && e.el.isConnected; }); }
function box(el) { var r = el.getBoundingClientRect(); return r.width || r.height ? r : null; }
/* true; false: two already share a screen with it; null: not displayed */
function room(e) {
  var a = box(e.el), H = w.innerHeight || 800, n = 0;
  if (!a) return null;
  S.slots.forEach(function (o) { var b; if (o !== e && o.shown && o.el.isConnected && (b = box(o.el)) && Math.max(a.top - b.bottom, b.top - a.bottom) < H) n++; });
  return n < (A.max_per_screen || 2);
}
function setClass(e) {
  var el = e.el, ad = A.ads[e.id];
  el.className = el.className.replace(SLOT, '').trim() + ' cnc-ad-slot cnc-ad-slot--' + kind(e) + (ad.mobile === 'hidden' ? ' cnc-ad-slot--desk' : '');
}
function fill(e) {
  var el = e.el;
  setClass(e);
  el.innerHTML = html(e);
  el.hidden = false; e.shown = true;
  var b = el.firstChild;
  if (S.brand && S.brand.accent) b.style.setProperty('--a', S.brand.accent);
  on(b, '[data-go]', function () { track('ad_click', e); });
  on(b, '[data-x]', function () { dismiss(e); });
  on(b, '[data-show]', function () { remember(e.id, null); e.strip = false; fill(e); focus(el, '[data-x]'); });
  if (!S.seen[e.id]) { if (look) look.observe(b); else seen(e); }
}
function on(b, q, f) { var x = b.querySelector(q); if (x) x.addEventListener('click', f); }
function focus(el, sel) { var f = el.querySelector(sel); if (f) f.focus(); }
function say(t) {
  if (!live) { live = d.createElement('div'); live.className = 'cnc-ad-vh'; live.setAttribute('aria-live', 'polite'); d.body.appendChild(live); }
  live.textContent = ''; setTimeout(function () { live.textContent = t; }, 50);
}
function dismiss(e) {
  var ad = A.ads[e.id];
  track('ad_dismiss', e);
  if (ad.collapses) { remember(e.id, 'c'); e.strip = true; fill(e); focus(e.el, '[data-show]'); return; }
  remember(e.id, 'd'); drop(e.el); clear(e.el);
  say('Bee-Inspect message hidden for ' + (A.dismiss_days || 14) + ' days.');
}
function seen(e) { if (S.seen[e.id]) return; S.seen[e.id] = 1; track('ad_impression', e); }
function entry(el) { for (var i = 0; i < S.slots.length; i++) if (S.slots[i].el === el) return S.slots[i]; return null; }
function arrive(e) {
  if (!e.el.isConnected || S.slots.indexOf(e) === -1) return;
  var r = room(e);
  if (r === false) { drop(e.el); clear(e.el); } else if (r) fill(e);
}
if (w.IntersectionObserver) {
  near = new IntersectionObserver(function (list) {
    list.forEach(function (x) { if (x.isIntersecting) { near.unobserve(x.target); var e = entry(x.target); if (e) arrive(e); } });
  }, { rootMargin: '600px 0px' });
  look = new IntersectionObserver(function (list) {
    list.forEach(function (x) { if (x.isIntersecting && x.intersectionRatio >= 0.5) { look.unobserve(x.target); var e = entry(x.target.parentNode); if (e) seen(e); } });
  }, { threshold: 0.5 });
}

function render(el, id, ctx) {
  if (!el) return false;
  drop(el);
  if (near) near.unobserve(el);
  var ad = A && A.ads[id];
  if (!enabled() || !ad || ad.parked) { clear(el); return false; }
  var m = stored(id);
  if (m && !ad.collapses) { clear(el); return false; }
  var e = { el: el, id: id, ctx: ctx || {}, strip: !!(m && ad.collapses), shown: false };
  el.setAttribute('data-cnc-ad', id);
  setClass(e);
  el.hidden = false;
  var r = room(e);
  if (r === false) { clear(el); return false; }
  S.slots.push(e);
  if (near && (r === null || box(el).top > (w.innerHeight || 800) + 600)) near.observe(el); else fill(e);
  return true;
}
function place(ref, pos, id, ctx) {
  if (!ref || !enabled()) return null;
  var el = d.createElement('div');
  ref.insertAdjacentElement(pos, el);
  if (render(el, id, ctx)) return el;
  el.remove(); return null;
}
function again() { S.slots.slice().forEach(function (e) { if (!e.el.isConnected) return drop(e.el); if (!enabled()) { drop(e.el); clear(e.el); } else if (e.shown) fill(e); }); }
function setSubscriber(b) { S.sub = !!b; again(); }
function configure(o) {
  o = o || {};
  if ('hidden' in o) S.hidden = !!o.hidden;
  if ('brand' in o) {
    var b = o.brand || null;
    S.brand = b ? { accent: /^#[0-9a-f]{6}$/i.test(b.accent || '') ? b.accent : null, label: typeof b.label === 'string' ? b.label.slice(0, 40) : null } : null;
  }
  again();
}
function auto() { if (!enabled()) return; d.querySelectorAll('[data-cnc-ad-slot]').forEach(function (el) { render(el, el.getAttribute('data-cnc-ad-slot'), {}); }); }

w.CNCAds = { render: render, place: place, enabled: enabled, band: band, withUtm: withUtm, setSubscriber: setSubscriber, configure: configure, track: track, _state: S };
if (d.readyState === 'loading') d.addEventListener('DOMContentLoaded', auto); else auto();
})(window, document);
