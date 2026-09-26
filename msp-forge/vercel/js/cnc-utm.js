/* =====================================================================
   cnc-utm.js :: campaign tags kept through the sign in link
   Version 1.0 | 25/09/2026 | Bee-Inspect P2 (hsf/BEE-INSPECT-BUILD-PROMPT.md
   A3 "keep UTM through magic link; store on first sign in", applied under
   hsf/BUILD-CONTRACT.md 16). Does nothing unless CNC_FLAGS.bee_inspect_ads
   is on (js/flags.js).

   window.CNCUtm = { capture, read, query, report }
   capture()   On load: the utm_source, utm_medium, utm_campaign, utm_content
               and utm_term of the landing address are kept in sessionStorage
               (first party, this tab only, gone when the tab closes). A value
               that is not 1 to 64 letters, digits, dots, underscores or
               hyphens is dropped, so an email address or markup is never kept.
   query()     "?utm_source=...&..." for the sign in link's return address,
               so the tags survive the one time link, which usually opens in a
               new tab where this tab's sessionStorage is not available.
   report(p)   At the first sign in of a visit that carries tags, hands them
               to Care Net once: POST /api/hsf-events {event:
               'attribution_seen', page, utm_*}. No cookie goes with it and
               nothing about the person: the tags say which link brought the
               visit, never who made it. The same tags are reported once, even
               when two tabs sign in (localStorage remembers the last set sent).

   No third party, no cookie. Every storage call sits in try/catch: private
   browsing or blocked storage simply means nothing is kept.
   ===================================================================== */
(function (w) {
  'use strict';
  if (w.CNCUtm) return;
  var KEY = 'cnc_utm_v1';
  var SENT = 'cnc_utm_sent_v1';
  var NAMES = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term'];
  var RE = /^[A-Za-z0-9._-]{1,64}$/;

  function on() { return !!(w.CNC_FLAGS && w.CNC_FLAGS.bee_inspect_ads); }
  function store(kind) { try { return w[kind] || null; } catch (e) { return null; } }
  function clean(o) {
    if (!o || typeof o !== 'object') return null;
    var out = {}, n = 0;
    NAMES.forEach(function (k) { if (typeof o[k] === 'string' && RE.test(o[k])) { out[k] = o[k]; n++; } });
    return n ? out : null;
  }
  function fromSearch(search) {
    var q, o = {};
    try { q = new URLSearchParams(search || ''); } catch (e) { return null; }
    NAMES.forEach(function (k) { var v = q.get(k); if (v !== null) o[k] = v; });
    return clean(o);
  }
  function read() {
    var s = store('sessionStorage');
    if (!s) return null;
    try { return clean(JSON.parse(s.getItem(KEY) || 'null')); } catch (e) { return null; }
  }
  function capture(loc) {
    if (!on()) return null;
    var t = fromSearch((loc || w.location || {}).search);
    if (t) { var s = store('sessionStorage'); try { if (s) s.setItem(KEY, JSON.stringify(t)); } catch (e) { /* not kept */ } }
    return t || read();
  }
  function query(t) {
    if (!on()) return '';
    t = clean(t) || read();
    if (!t) return '';
    var p = [];
    NAMES.forEach(function (k) { if (t[k]) p.push(k + '=' + encodeURIComponent(t[k])); });
    return '?' + p.join('&');
  }
  function report(page) {
    if (!on()) return false;
    var t = read() || fromSearch((w.location || {}).search);
    if (!t) return false;
    var sig = JSON.stringify(t), l = store('localStorage');
    try { if (l && l.getItem(SENT) === sig) return false; } catch (e) { /* carry on */ }
    try { if (l) l.setItem(SENT, sig); } catch (e) { /* carry on */ }
    var body = { event: 'attribution_seen', page: page };
    NAMES.forEach(function (k) { body[k] = t[k] || null; });
    var url = ((w.CNC_CONFIG && w.CNC_CONFIG.apiBase) || '') + '/api/hsf-events';
    try {
      w.fetch(url, { method: 'POST', body: JSON.stringify(body), keepalive: true, credentials: 'omit', headers: { 'Content-Type': 'application/json' } })
        .catch(function () { /* never in the way */ });
    } catch (e) { /* never in the way */ }
    return true;
  }

  w.CNCUtm = { capture: capture, read: read, query: query, report: report, NAMES: NAMES, _lib: { fromSearch: fromSearch, clean: clean, RE: RE } };
  capture();
})(window);
