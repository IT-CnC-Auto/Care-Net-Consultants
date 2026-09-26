/* =====================================================================
   cnc-tracking.js :: Care Net Consultants consent and call to action tracking
   Version: 1.0 | 23/09/2026 | HSF FORGE build contract, section 6
   Load order: at the end of <head>, straight after /js/cnc-config.js.

   What it does, in order:
     1. Google consent mode defaults to denied, using the same keys and the
        same storage key (cnc_consent_v1, 12 months) as the loader on
        medical-surveillance-plans.html, so one choice carries everywhere.
        If that page's own loader has already run, it is left alone.
     2. Google Tag Manager loads only when CNC_CONFIG.gtmId is set AND the
        visitor has accepted. The ID is pending, so today nothing loads.
     3. If there is no stored choice and the page has no element with the
        id "consent" (the page's own bar), it shows the shared consent bar.
     4. Any element carrying data-cta="<name>" pushes
        {event: 'cnc_cta_click', cta: name, page: location.pathname}
        to the dataLayer when clicked. Only the pathname is sent, never the
        query string or the hash, and never anything a visitor typed.

   It never pushes personal information: no email, name, phone number,
   form value, URL query or user ID ever reaches the dataLayer from here.
   Safe to include twice: the second copy does nothing.
   ===================================================================== */
(function (w, d) {
  'use strict';
  if (w.__cncTracking) return;
  w.__cncTracking = true;

  var CFG = w.CNC_CONFIG || {};
  var KEY = CFG.consentStorageKey || 'cnc_consent_v1';
  var DEFAULT_PRIVACY = 'https://www.carenetconsultants.co.za/privacy-policy';
  var TWELVE_MONTHS = 365 * 24 * 60 * 60 * 1000;
  var GTM_RE = /^GTM-[A-Z0-9]{4,12}$/;
  var BAR_TEXT = 'We use cookies to understand how the site is used. ' +
    'Tracking stays off until you accept, and your information is handled under POPIA.';

  /* ------------------------------------------------------------ storage */
  function readStored() {
    var s = null;
    try { s = JSON.parse(w.localStorage.getItem(KEY) || 'null'); } catch (e) { s = null; }
    if (!s || typeof s !== 'object' || typeof s.savedAt !== 'number') return null;
    if ((Date.now() - s.savedAt) > TWELVE_MONTHS) {
      try { w.localStorage.removeItem(KEY); } catch (e) { /* storage blocked */ }
      return null;
    }
    return { analytics: !!s.analytics, marketing: !!s.marketing, savedAt: s.savedAt };
  }

  function writeStored(c) {
    try {
      w.localStorage.setItem(KEY, JSON.stringify({ analytics: c.analytics, marketing: c.marketing, savedAt: c.savedAt }));
    } catch (e) { /* storage blocked: the choice still holds for this page view */ }
  }

  function consentUpdate(c) {
    return {
      analytics_storage: c.analytics ? 'granted' : 'denied',
      ad_storage: c.marketing ? 'granted' : 'denied',
      ad_user_data: c.marketing ? 'granted' : 'denied',
      ad_personalization: c.marketing ? 'granted' : 'denied'
    };
  }

  /* ------------------------------------------------ consent mode defaults */
  /* The medical-surveillance-plans.html loader defines gtag and sets one of
     these two flags. When it has run, its defaults stand. */
  var pageLoaderRan = typeof w.gtag === 'function' &&
    (w.__cncConsent != null || w.__cncConsentPending === true);

  w.dataLayer = w.dataLayer || [];
  if (typeof w.gtag !== 'function') {
    w.gtag = function () { w.dataLayer.push(arguments); };
  }
  function gtag() { w.gtag.apply(w, arguments); }

  var current = readStored();

  if (!pageLoaderRan) {
    gtag('consent', 'default', {
      ad_storage: 'denied', ad_user_data: 'denied', ad_personalization: 'denied',
      analytics_storage: 'denied', functionality_storage: 'granted',
      security_storage: 'granted', wait_for_update: 500
    });
    if (current) {
      gtag('consent', 'update', consentUpdate(current));
      w.__cncConsent = current;
    } else {
      w.__cncConsentPending = true;
    }
  }

  /* ---------------------------------------------------- Tag Manager */
  var gtmLoaded = false;
  function loadGTM() {
    if (gtmLoaded) return;
    var id = CFG.gtmId;
    if (id == null || id === '') return;               /* pending: nothing loads */
    if (!current || !current.analytics) return;         /* never before consent */
    if (typeof id !== 'string' || !GTM_RE.test(id)) {
      if (w.console) w.console.warn('cnc-tracking: CNC_CONFIG.gtmId is not a GTM container ID, so no tag was loaded.');
      return;
    }
    gtmLoaded = true;
    if (d.querySelector('script[data-cnc-gtm]')) return;
    w.dataLayer.push({ 'gtm.start': new Date().getTime(), event: 'gtm.js' });
    var s = d.createElement('script');
    s.async = true;
    s.src = 'https://www.googletagmanager.com/gtm.js?id=' + encodeURIComponent(id);
    s.setAttribute('data-cnc-gtm', '1');
    (d.head || d.documentElement).appendChild(s);
  }

  function announce() {
    try {
      w.dispatchEvent(new CustomEvent('cnc:consent', {
        detail: { analytics: !!(current && current.analytics), marketing: !!(current && current.marketing) }
      }));
    } catch (e) { /* very old browser: nothing listens anyway */ }
  }

  /* A choice made on this page through the shared bar or the public API. */
  function choose(analytics, marketing) {
    current = { analytics: !!analytics, marketing: !!marketing, savedAt: Date.now() };
    writeStored(current);
    gtag('consent', 'update', consentUpdate(current));
    w.__cncConsent = current;
    w.__cncConsentPending = false;
    hideBar();
    loadGTM();
    announce();
  }

  /* A choice made somewhere else: the page's own bar (it has already told
     gtag) or another tab (it has not). */
  function syncFromStorage(tellGtag) {
    var s = readStored();
    if (!s) return;
    if (current && current.savedAt === s.savedAt &&
        current.analytics === s.analytics && current.marketing === s.marketing) return;
    current = s;
    if (tellGtag) gtag('consent', 'update', consentUpdate(current));
    w.__cncConsent = current;
    w.__cncConsentPending = false;
    hideBar();
    loadGTM();
    announce();
  }

  /* ------------------------------------------------------- shared bar */
  var BAR_ID = 'cnc-consent';
  var STYLE_ID = 'cnc-consent-style';
  var CSS =
    '.cnc-consent-bar{position:fixed;left:16px;right:16px;bottom:16px;z-index:2147480000;max-width:760px;margin:0 auto;' +
      'box-sizing:border-box;background:#fff;color:#1A1A1A;border:1px solid #E5E5E5;border-radius:14px;' +
      'box-shadow:0 18px 40px rgba(0,0,0,.18);padding:16px 18px;display:flex;flex-wrap:wrap;gap:12px;' +
      'align-items:center;justify-content:space-between;font:400 14px/1.5 Inter,Arial,Helvetica,sans-serif;text-align:left}' +
    '.cnc-consent-bar[hidden]{display:none}' +
    '.cnc-consent-bar p{margin:0;flex:1 1 300px;font-size:14px;line-height:1.5;color:#1A1A1A}' +
    '.cnc-consent-bar a{color:#C5141B;font-weight:600;text-decoration:underline;text-underline-offset:2px}' +
    '.cnc-consent-actions{display:flex;gap:10px;flex:0 0 auto;margin:0}' +
    '.cnc-consent-btn{box-sizing:border-box;margin:0;min-height:44px;min-width:104px;padding:11px 20px;border-radius:8px;' +
      'border:2px solid #1A1A1A;font:700 14px/1 Montserrat,Arial,Helvetica,sans-serif;letter-spacing:.01em;cursor:pointer;' +
      'text-transform:none;width:auto}' +
    '.cnc-consent-decline{background:#fff;color:#1A1A1A}' +
    '.cnc-consent-decline:hover{background:#1A1A1A;color:#fff}' +
    '.cnc-consent-accept{background:#C5141B;border-color:#C5141B;color:#fff}' +
    '.cnc-consent-accept:hover{background:#A81016;border-color:#A81016}' +
    '.cnc-consent-bar a:focus-visible,.cnc-consent-btn:focus-visible{outline:3px solid #1A1A1A;outline-offset:2px}' +
    '@media (max-width:480px){.cnc-consent-actions{width:100%}.cnc-consent-btn{flex:1 1 0}}' +
    '@media print{.cnc-consent-bar{display:none}}';

  function safePrivacyUrl() {
    var u = CFG.privacyUrl;
    if (typeof u === 'string' && (/^https:\/\//i.test(u) || /^\/(?!\/)/.test(u))) return u;
    return DEFAULT_PRIVACY;
  }

  function buildBar() {
    if (!d.getElementById(STYLE_ID)) {
      var st = d.createElement('style');
      st.id = STYLE_ID;
      st.textContent = CSS;
      (d.head || d.documentElement).appendChild(st);
    }
    var bar = d.createElement('section');
    bar.id = BAR_ID;
    bar.className = 'cnc-consent-bar';
    bar.setAttribute('role', 'region');
    bar.setAttribute('aria-label', 'Cookie and privacy notice');

    var p = d.createElement('p');
    p.appendChild(d.createTextNode(BAR_TEXT + ' '));
    var a = d.createElement('a');
    a.href = safePrivacyUrl();
    a.textContent = 'Read our Privacy Policy';
    p.appendChild(a);
    p.appendChild(d.createTextNode('.'));

    var row = d.createElement('div');
    row.className = 'cnc-consent-actions';
    var no = d.createElement('button');
    no.type = 'button';
    no.className = 'cnc-consent-btn cnc-consent-decline';
    no.textContent = 'Decline';
    no.addEventListener('click', function () { choose(false, false); });
    var yes = d.createElement('button');
    yes.type = 'button';
    yes.className = 'cnc-consent-btn cnc-consent-accept';
    yes.textContent = 'Accept';
    yes.addEventListener('click', function () { choose(true, true); });
    row.appendChild(no);
    row.appendChild(yes);

    bar.appendChild(p);
    bar.appendChild(row);
    d.body.appendChild(bar);
    return bar;
  }

  function showBar() {
    if (!d.body) return;
    /* The page carries its own bar (medical-surveillance-plans.html): use it. */
    var own = d.getElementById('consent');
    if (own) { own.style.display = ''; return; }
    var bar = d.getElementById(BAR_ID) || buildBar();
    bar.hidden = false;
  }

  function hideBar() {
    var bar = d.getElementById(BAR_ID);
    if (!bar) return;
    var hadFocus = bar.contains(d.activeElement);
    if (bar.parentNode) bar.parentNode.removeChild(bar);
    if (hadFocus) {
      /* Do not strand keyboard users on a removed button. */
      var main = d.getElementById('main') || d.querySelector('main');
      if (main) {
        if (!main.hasAttribute('tabindex')) main.setAttribute('tabindex', '-1');
        try { main.focus({ preventScroll: true }); } catch (e) { main.focus(); }
      }
    }
  }

  function onReady(fn) {
    if (d.readyState === 'loading') d.addEventListener('DOMContentLoaded', fn);
    else fn();
  }

  onReady(function () {
    if (current) { loadGTM(); return; }
    if (d.getElementById('consent')) return;   /* the page's own bar handles it */
    showBar();
  });

  /* ---------------------------------------------- call to action clicks */
  function cleanName(v) {
    if (v == null) return null;
    v = String(v);
    /* Belt and braces: a name must never carry an email address or a
       telephone number, so either one replaces the whole name. */
    if (v.indexOf('@') !== -1 || /\d{7,}/.test(v.replace(/[\s_.()+-]/g, ''))) return 'redacted';
    v = v.replace(/[^A-Za-z0-9 _.:\/-]/g, '_').replace(/\s+/g, ' ').trim().slice(0, 64);
    return v || null;
  }

  function pushCta(name) {
    var cta = cleanName(name);
    if (!cta) return;
    w.dataLayer.push({ event: 'cnc_cta_click', cta: cta, page: w.location.pathname });
  }

  /* Capture phase, so a page handler that stops propagation cannot hide a
     click from tracking. Keyboard activation fires click as well. */
  d.addEventListener('click', function (e) {
    var t = e.target;
    if (t && t.nodeType !== 1) t = t.parentElement;
    if (!t || !t.closest) return;
    var el = t.closest('[data-cta]');
    if (el) pushCta(el.getAttribute('data-cta'));
    if (t.closest('[data-consent-open]')) { e.preventDefault(); showBar(); }
  }, true);

  /* The page's own bar (id consent) writes storage and tells gtag in its own
     click handler; this bubble phase listener runs after it and catches up. */
  d.addEventListener('click', function (e) {
    var t = e.target;
    if (t && t.nodeType !== 1) t = t.parentElement;
    if (t && t.closest && t.closest('#consent-accept, #consent-decline')) {
      w.setTimeout(function () { syncFromStorage(false); }, 0);
    }
  }, false);

  /* A choice made in another tab. */
  w.addEventListener('storage', function (e) {
    if (e.key === KEY) syncFromStorage(true);
  });

  /* ------------------------------------------------------- public API */
  w.CNCTracking = {
    version: '1.0',
    consent: function () {
      return current ? { analytics: current.analytics, marketing: current.marketing } : null;
    },
    accept: function () { choose(true, true); },
    decline: function () { choose(false, false); },
    /* Reopen the choice, for example from a "Cookie settings" footer link.
       Markup alone also works: any element with data-consent-open. */
    openPreferences: showBar,
    trackCta: pushCta,
    gtmLoaded: function () { return gtmLoaded; }
  };
})(window, document);
