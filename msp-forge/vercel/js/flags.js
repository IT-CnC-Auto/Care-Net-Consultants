/* =====================================================================
   flags.js :: feature flags for the Health and Safety File site
   Version: 1.1 | 25/09/2026 | Bee-Inspect P1 and P2 (hsf/BUILD-CONTRACT.md 16)

   window.CNC_FLAGS = { bee_inspect_ads, welcome_hook }

   bee_inspect_ads  The Bee-Inspect add on banners (js/cnc-ad.js). ON for
                    staging and local hosts (*.vercel.app, localhost,
                    127.0.0.1), OFF on every other host until the Director
                    switches it on here.
   welcome_hook     First template inspection free plus an R20,00 AI Wallet
                    credit. OFF everywhere (open input: welcome_hook).

   Testing override: ?flags=bee_inspect_ads:0 or ?flags=bee_inspect_ads:1,
   a comma list of name:0|1 pairs. Only the names above are read; anything
   else in the list is ignored. Nothing is stored.

   Load it in <head>, before css/cnc-ad.css is used (it sets the class
   cnc-ads-on on <html> while the banners are on). Plain script, no
   dependencies, safe to include twice (the first copy wins).

   While bee_inspect_ads is on (html.cnc-ads-on):
   - menu items marked <li data-flag="bee_inspect_ads"> show (css/cnc-header.css);
   - a page that is public only once the flag is on carries, in <head> BEFORE
     this script, <meta name="robots" content="noindex" data-noindex-unless="bee_inspect_ads">.
     The tag is removed here when that flag is on for this host, so the page
     is indexable exactly where the flag is on and noindex everywhere else
     (and for any reader that runs no script). When the Director switches the
     flag on for production, also drop the tag from those pages in the same
     release, so a crawler that does not run scripts sees the same answer.
   ===================================================================== */
(function (w) {
  'use strict';
  if (w.CNC_FLAGS && w.CNC_FLAGS.__cnc === 1) return;

  var NAMES = ['bee_inspect_ads', 'welcome_hook'];

  function isStagingHost(host) {
    host = String(host || '').toLowerCase();
    return host === 'localhost' || host === '127.0.0.1' || /\.vercel\.app$/.test(host);
  }

  /* "a:1,b:0" -> {a: true, b: false}; unknown names and bad pairs dropped. */
  function parse(raw) {
    var out = {};
    String(raw || '').split(',').forEach(function (pair) {
      var m = /^\s*([a-z_]{1,40})\s*:\s*([01])\s*$/.exec(pair);
      if (m && NAMES.indexOf(m[1]) !== -1) out[m[1]] = m[2] === '1';
    });
    return out;
  }

  function compute(loc) {
    var host = loc && loc.hostname;
    var flags = { bee_inspect_ads: isStagingHost(host), welcome_hook: false };
    var q = '';
    try { q = new URLSearchParams((loc && loc.search) || '').get('flags') || ''; } catch (e) { q = ''; }
    var o = parse(q);
    for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) flags[k] = o[k];
    return flags;
  }

  var flags = compute(w.location);
  /* Banner slots take up room only while the banners are on (css/cnc-ad.css),
     so a page with the flag off lays out exactly as before. Loaded in <head>,
     before first paint, so the reserved room never moves anything. */
  try { if (flags.bee_inspect_ads && w.document) w.document.documentElement.classList.add('cnc-ads-on'); } catch (e) { /* no document */ }
  /* noindex unless the named flag is on (see above). */
  function robots(doc) {
    var removed = 0;
    try {
      var list = doc.querySelectorAll('meta[data-noindex-unless]');
      for (var i = 0; i < list.length; i++) {
        var m = list[i], name = m.getAttribute('data-noindex-unless');
        if (NAMES.indexOf(name) !== -1 && flags[name] === true && m.parentNode) { m.parentNode.removeChild(m); removed++; }
      }
    } catch (e) { /* no document */ }
    return removed;
  }
  robots(w.document);
  Object.defineProperty(flags, '__cnc', { value: 1, enumerable: false });
  /* For the tests: the pure parts, not enumerable. */
  Object.defineProperty(flags, '_lib', { value: { parse: parse, compute: compute, isStagingHost: isStagingHost, robots: robots, NAMES: NAMES }, enumerable: false });
  w.CNC_FLAGS = Object.freeze(flags);
})(typeof window !== 'undefined' ? window : globalThis);
