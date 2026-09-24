/* =====================================================================
   cnc-config.js :: Care Net Consultants shared front end settings
   Version: 1.0 | 23/09/2026 | HSF FORGE build contract, section 6
   Load order: first script at the end of <head>, before cnc-tracking.js.

   Every page reads its settings from here and nowhere else, so the same
   pages can be served from Vercel today and from inside MyClinicOnline
   (MCO) later by changing this one file, or by setting
   window.CNC_CONFIG_OVERRIDES before this file loads.

   PUBLIC BY DESIGN. The publishable key below is the anon key that every
   page already carries; row level security decides what it can read.
   No server secret (service role key, MCO token, API key) ever goes in
   this file or in any other file served to a browser.

   PENDING VALUES (never invented, left null until confirmed):
     1. gtmId         Google Tag Manager container ID. Not known. While it
                      is null, cnc-tracking.js loads no tag at all.
     2. mcoPortalUrl  MyClinicOnline portal and single sign on address.
                      Pending the MCO interface contract (HSF-3).
     3. recruitmentPortalUrl
                      Care Net Recruitment Portal address (contract 12.5).
                      Not known. While it is null, the "Onboard a registered
                      Health and Safety practitioner" call to action asks a
                      sales executive on WhatsApp instead.
   ===================================================================== */
(function (w) {
  'use strict';

  /* Safe to include twice: the first copy wins. */
  if (w.CNC_CONFIG && w.CNC_CONFIG.__cnc === 1) return;

  var base = {
    /* Supabase project (see hsf/BUILD-CONTRACT.md section 1). */
    supabaseUrl: 'https://pboebfnujzffgwctsplw.supabase.co',
    publishableKey: 'sb_publishable_E6ebjt_HJy5RN6MzM6fsdg_I1VbB1aj',

    /* PENDING: Google Tag Manager container ID is not known. Keep null.
       Never type a made up ID here; tracking stays fully off while null. */
    gtmId: null,

    /* The only verified WhatsApp number. */
    whatsapp: '27600702723',
    whatsappDisplay: '27 60 070 2723',
    whatsappUrl: 'https://wa.me/27600702723',

    mainSite: 'https://www.carenetconsultants.co.za',
    privacyUrl: 'https://www.carenetconsultants.co.za/privacy-policy',

    /* 'supabase' (email one time link) today. 'mco_sso' is a stub that
       refuses to run until the MCO interface contract (HSF-3) is agreed. */
    authProvider: 'supabase',

    /* PENDING (HSF-3): MyClinicOnline portal and single sign on address. */
    mcoPortalUrl: null,

    /* PENDING (contract 12.5): the Care Net Recruitment Portal address is
       not known. Keep null; never type a guessed address here. Once set,
       the recruitment call to action opens it with
       ?source=hsf&need=<signatory|appointment>&industry=<code>. */
    recruitmentPortalUrl: null,

    /* Prefix for /api/... calls. Empty means the same origin as the page,
       which is what keeps the pages portable into MCO hosting. */
    apiBase: '',

    /* Shared cookie choice. Same key as medical-surveillance-plans.html so
       one choice carries across every page. */
    consentStorageKey: 'cnc_consent_v1'
  };

  /* Keys a host may override (for example MCO hosting sets apiBase and
     authProvider). Anything else in the overrides is ignored. */
  var OVERRIDABLE = ['supabaseUrl', 'publishableKey', 'gtmId', 'mainSite',
    'privacyUrl', 'authProvider', 'mcoPortalUrl', 'recruitmentPortalUrl', 'apiBase'];

  var o = w.CNC_CONFIG_OVERRIDES;
  if (o && typeof o === 'object') {
    for (var i = 0; i < OVERRIDABLE.length; i++) {
      var k = OVERRIDABLE[i];
      if (Object.prototype.hasOwnProperty.call(o, k)) base[k] = o[k];
    }
  }

  /* Record which values are still pending so pages can say so plainly. */
  base.pending = {
    gtmId: base.gtmId == null,
    mcoPortalUrl: base.mcoPortalUrl == null,
    recruitmentPortalUrl: base.recruitmentPortalUrl == null
  };

  Object.defineProperty(base, '__cnc', { value: 1, enumerable: false });
  Object.freeze(base.pending);
  w.CNC_CONFIG = Object.freeze(base);
})(typeof window !== 'undefined' ? window : globalThis);
