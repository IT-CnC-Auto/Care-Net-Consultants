/* =====================================================================
   cnc-bee.js :: what the Bee-Inspect pages draw from /hsf/ads.js
   Version 1.0 | 25/09/2026 | Bee-Inspect P2 (hsf/BEE-INSPECT-BUILD-PROMPT.md
   A3 and B8, applied under hsf/BUILD-CONTRACT.md 16)

   Loaded after /hsf/ads.js on /bee-inspect, /bee-inspect/sample-report,
   /get-app and /claim/{code}. Every price, link and store address comes from
   window.HSF_ADS: nothing here types a price. Plain script, no dependencies,
   no storage, no cookie, sends nothing.

   window.CNCBee = {
     zar(n)                 R1 150,00 (no break space for thousands)
     links(root)            fills a[data-bee-link="<name>"] from HSF_ADS.links
     price(root)            fills [data-bee-price="line|short|vat_line"]
     pricing(root)          the plans, the AI Wallet top ups and points, storage
     detect(ua, platform, touchPoints)  'ios' | 'android' | 'desktop'
     route(device, app)     {action: 'store', url} when a store address is set
                            for that device, else {action: 'wait', reason}
     getApp(doc, nav, loc)  the /get-app router (stub while the addresses are null)
     claimCode(pathname)    {valid, code} for /claim/{code}; the code is never
                            written into the page
   }
   ===================================================================== */
(function (w) {
  'use strict';
  var A = w.HSF_ADS || null;
  var NBSP = ' ';

  function zar(n) {
    var v = Number(n);
    if (!isFinite(v)) return '';
    var p = v.toFixed(2).split('.');
    return 'R' + p[0].replace(/\B(?=(\d{3})+(?!\d))/g, NBSP) + ',' + p[1];
  }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return '&#' + c.charCodeAt(0) + ';'; }); }
  /* Visible text: Bee-Inspect and Bee-Matched never break at their hyphen. */
  function tx(s) { return esc(s).replace(/Bee-/g, 'Bee&#8209;'); }
  /* A rand amount in text never breaks across two lines. */
  function keep(s) { return tx(s).replace(/R\d{1,3}(?: \d{3})*,\d{2}/g, function (m) { return '<span class="nb">' + m + '</span>'; }); }
  function all(root, sel) { return Array.prototype.slice.call((root || w.document).querySelectorAll(sel)); }
  /* Only this site, https or WhatsApp: anything else in the data is ignored. */
  function safeHref(h) {
    h = String(h || '');
    return /^\/[a-z0-9\/_-]*(?:\?[^"'<>\s]*)?$/i.test(h) || /^https:\/\/wa\.me\/\d+(?:\?[^"'<>\s]*)?$/.test(h) || /^https:\/\/[a-z0-9.-]+\.[a-z]{2,}(?:\/[^"'<>\s]*)?$/i.test(h) ? h : null;
  }

  function links(root) {
    if (!A || !A.links) return 0;
    var n = 0;
    all(root, 'a[data-bee-link]').forEach(function (a) {
      var l = A.links[a.getAttribute('data-bee-link')];
      var h = l && safeHref(l.href);
      if (!h) return;
      a.setAttribute('href', h);
      if (l.aria) a.setAttribute('aria-label', l.aria);
      if (/^https:/.test(h)) { a.setAttribute('target', '_blank'); a.setAttribute('rel', 'noopener'); }
      n++;
    });
    return n;
  }

  function price(root) {
    if (!A || !A.price) return 0;
    var n = 0;
    all(root, '[data-bee-price]').forEach(function (el) {
      var t = A.price[el.getAttribute('data-bee-price')];
      if (typeof t === 'string') { el.innerHTML = keep(t); n++; }
    });
    return n;
  }

  function pricing(root) {
    if (!A || !A.price) return false;
    var P = A.price, d = root || w.document;
    var plans = d.getElementById('bi-plans');
    if (plans && Array.isArray(P.plans)) {
      plans.innerHTML = P.plans.map(function (p, i) {
        return '<div class="card plan' + (i === 0 ? ' featured' : '') + '"><span class="tag paid">' + (i === 0 ? 'Subscription' : 'Add a company') + '</span>'
          + '<h3>' + tx(p.name) + '</h3><b class="amt">' + zar(p.zar_month) + ' <small>a month</small></b>'
          + '<p class="vat">' + tx(P.vat_line) + '</p>'
          + '<ul class="tick">' + (p.includes || []).map(function (x) { return '<li>' + keep(x) + '</li>'; }).join('') + '</ul></div>';
      }).join('');
    }
    var W = P.wallet || {};
    var tb = d.getElementById('bi-topups');
    if (tb && Array.isArray(W.topups)) {
      tb.innerHTML = W.topups.map(function (t) {
        var extra = Number(t.value_zar) - Number(t.zar);
        return '<tr><td>' + zar(t.zar) + '</td><td>' + zar(t.value_zar) + '</td><td class="' + (extra > 0 ? 'more' : '') + '">'
          + (extra > 0 ? zar(extra) + ' more' : 'Same value') + '</td></tr>';
      }).join('');
    }
    var wp = d.getElementById('bi-wallet-points');
    if (wp && Array.isArray(W.points)) wp.innerHTML = W.points.map(function (x) { return '<li>' + keep(x) + '</li>'; }).join('');
    var sp = d.getElementById('bi-storage-points');
    if (sp && P.storage && Array.isArray(P.storage.points)) sp.innerHTML = P.storage.points.map(function (x) { return '<li>' + keep(x) + '</li>'; }).join('');
    return true;
  }

  /* ---- /get-app */
  function detect(ua, platform, touchPoints) {
    ua = String(ua || ''); platform = String(platform || '');
    if (/android/i.test(ua)) return 'android';
    if (/iphone|ipad|ipod/i.test(ua)) return 'ios';
    /* iPadOS presents itself as a Mac; a touch screen gives it away. */
    if (/Macintosh|MacIntel/.test(ua + ' ' + platform) && Number(touchPoints) > 1) return 'ios';
    return 'desktop';
  }
  function route(device, app) {
    app = app || {};
    var url = device === 'ios' ? app.ios_url : device === 'android' ? app.android_url : null;
    if (url && /^https:\/\/(?:apps\.apple\.com|play\.google\.com)\//.test(String(url))) return { action: 'store', url: String(url) };
    return { action: 'wait', reason: device === 'desktop' ? 'desktop' : 'not_released' };
  }
  var DEVICE_LINE = {
    ios: 'You are on an iPhone or iPad. Once the app is released, this page opens the App Store for you.',
    android: 'You are on an Android phone. Once the app is released, this page opens Google Play for you.',
    desktop: 'You are on a computer. Once the app is released, this page shows a code to scan with your phone, so the app signs in to the same account and File.'
  };
  function getApp(doc, nav, loc) {
    doc = doc || w.document; nav = nav || w.navigator || {}; loc = loc || w.location;
    var device = detect(nav.userAgent, nav.platform, nav.maxTouchPoints);
    var r = route(device, A && A.app);
    var line = doc.getElementById('ga-device');
    if (r.action === 'store') {
      if (line) line.textContent = 'Opening the store for you.';
      try { loc.replace(r.url); } catch (e) { /* the links below still work */ }
    } else if (line) {
      line.textContent = DEVICE_LINE[device];
    }
    var s = doc.getElementById('ga-status');
    if (s && A && A.app && A.app.coming_soon) s.textContent = A.app.coming_soon;
    return { device: device, route: r };
  }

  /* ---- /claim/{code}: a stub until claim-code-redeem (P3). The shape is 6 to
     12 letters or digits; it is checked here and never written into the page. */
  var CLAIM_RE = /^[A-Za-z0-9]{6,12}$/;
  function claimCode(pathname) {
    var m = /^\/claim\/([^\/?#]*)\/?$/.exec(String(pathname || ''));
    if (!m) return { valid: false, code: null };
    var raw;
    try { raw = decodeURIComponent(m[1]); } catch (e) { return { valid: false, code: null }; }
    return CLAIM_RE.test(raw) ? { valid: true, code: raw.toUpperCase() } : { valid: false, code: null };
  }

  w.CNCBee = { zar: zar, links: links, price: price, pricing: pricing, detect: detect, route: route, getApp: getApp,
    claimCode: claimCode, CLAIM_RE: CLAIM_RE, DEVICE_LINE: DEVICE_LINE, _lib: { esc: esc, safeHref: safeHref, keep: keep } };
})(window);
