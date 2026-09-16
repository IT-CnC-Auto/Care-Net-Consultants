/* =====================================================================
   cnc-journey.js :: the journey's browser-side memory
   Version: 1.0 | Owner: Kc (CNC brand and front end)

   Two things are remembered on the visitor's own device:

     the sign on details   company, contact person, email, phone, typed on
                           the landing page, so the assessment can pre-fill
                           them instead of asking twice
     an assessment draft   everything typed into the assessment, so closing
                           the page does not throw away 30 to 45 minutes

   FRONT END ONLY. Nothing here talks to an endpoint. Everything lives in
   this browser's localStorage and never leaves the device.

   WHAT THIS DOES NOT DO, and what Od would need to change:
     A draft lives in one browser on one device. Start on the office desktop
     and you cannot finish on a laptop at home. Surviving that needs the
     draft stored server side, which means a new endpoint and somewhere to
     put it. Until then the page says plainly where the draft is kept.

   POPIA: a draft holds company and contact details, so it is the visitor's
   own data on the visitor's own machine. It is cleared the moment the
   assessment is submitted, and there is a Discard button on every page that
   shows one.
   ===================================================================== */
(function (w) {
  'use strict';

  var DETAILS  = 'cnc_signon_details';   /* what was typed on the landing page */
  var REGISTRY = 'cnc_msp_drafts';       /* the list of drafts, so any page can find them */
  var DRAFT    = 'cnc_msp_draft_';       /* one entry per assessment token */

  /* Storage throws in a private window with site data blocked, and is simply
     absent in some embedded browsers. Every access is wrapped so the journey
     carries on without it rather than breaking. */
  function read(key) {
    try { return JSON.parse(w.localStorage.getItem(key) || 'null'); } catch (e) { return null; }
  }
  function write(key, val) {
    try { w.localStorage.setItem(key, JSON.stringify(val)); return true; } catch (e) { return false; }
  }
  function drop(key) { try { w.localStorage.removeItem(key); } catch (e) {} }

  /* Is storage usable at all? Pages ask this before promising to remember. */
  function available() {
    try {
      var k = '__cnc_probe__';
      w.localStorage.setItem(k, '1'); w.localStorage.removeItem(k);
      return true;
    } catch (e) { return false; }
  }

  var CNCJourney = {
    available: available,

    /* ---- the details typed on the landing page ---- */
    setDetails: function (d) { return write(DETAILS, d); },
    getDetails: function () { return read(DETAILS); },
    clearDetails: function () { drop(DETAILS); },

    /* ---- one assessment draft, keyed by its access token ---- */
    saveDraft: function (token, payload) {
      if (!token) return false;
      var entry = {
        token: token,
        savedAt: new Date().toISOString(),
        counts: payload.counts || {},
        values: payload.values || {},
      };
      if (!write(DRAFT + token, entry)) return false;

      /* Keep the registry in step so the landing page can offer a resume
         without knowing the token. Newest first, and only one per token. */
      var reg = read(REGISTRY) || [];
      reg = reg.filter(function (r) { return r && r.token !== token; });
      reg.unshift({
        token: token,
        company: payload.company || '',
        savedAt: entry.savedAt,
        filled: payload.filled || 0,
      });
      write(REGISTRY, reg.slice(0, 5));
      return true;
    },

    getDraft: function (token) { return token ? read(DRAFT + token) : null; },

    clearDraft: function (token) {
      if (!token) return;
      drop(DRAFT + token);
      var reg = read(REGISTRY) || [];
      write(REGISTRY, reg.filter(function (r) { return r && r.token !== token; }));
    },

    /* The most recent draft, for the "pick up where you left off" card.
       A registry row whose draft has gone is dropped rather than offered. */
    latestDraft: function () {
      var reg = read(REGISTRY) || [];
      for (var i = 0; i < reg.length; i++) {
        var r = reg[i];
        if (r && r.token && read(DRAFT + r.token)) return r;
      }
      if (reg.length) write(REGISTRY, []);
      return null;
    },

    /* "3 minutes ago", for showing when a draft was last saved. */
    ago: function (iso) {
      var then = Date.parse(iso);
      if (!then) return '';
      var mins = Math.floor((Date.now() - then) / 60000);
      if (mins < 1) return 'just now';
      if (mins === 1) return '1 minute ago';
      if (mins < 60) return mins + ' minutes ago';
      var hrs = Math.floor(mins / 60);
      if (hrs === 1) return '1 hour ago';
      if (hrs < 24) return hrs + ' hours ago';
      var days = Math.floor(hrs / 24);
      return days === 1 ? 'yesterday' : days + ' days ago';
    },
  };

  w.CNCJourney = CNCJourney;
})(window);
