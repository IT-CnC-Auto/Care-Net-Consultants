/* CNC | Bee-Inspect: copy, prices, links and UTM rules for the banners and the
   Bee-Inspect pages. One source: /js/cnc-ad.js (the banners), /bee-inspect,
   /bee-inspect/sample-report and /get-app read everything they show about
   price and links from here. No page types a price.
   Version 1.1 | 25/09/2026 | Bee-Inspect P2 (hsf/BEE-INSPECT-BUILD-PROMPT.md
   A3 and B8, applied under hsf/BUILD-CONTRACT.md 16). Version 1.0 (P1,
   24/09/2026) sent every call to action to WhatsApp until /bee-inspect existed.

   House rules for every visible string (checked by test/api/bee-inspect-ads.test.js
   and test/api/bee-inspect-pages.test.js): South African British English; no
   dash or hyphen punctuation in prose (the names Bee-Inspect and Bee-Matched
   keep theirs); rand as R299,00; never "compliant" or "guarantee"; no internal
   system names; AI "assists"; a competent person reviews and signs. Nothing
   here links to a Medical Surveillance Plan page.

   P2 changes: every primary call to action opens /bee-inspect (cnc-ad.js adds
   the UTM rules of utm below); AD-01 carries "See a sample report" to
   /bee-inspect/sample-report; the WhatsApp route stays on the product page as
   the fallback (links.whatsapp_fallback).

   STUBS (each marked stub: true below):
   1. "Open Bee-Inspect" for subscribers has no app or web desk address yet
      (P3 and P4); it asks a sales executive meanwhile.
   2. VAT: shown as "VAT to be confirmed" until Chantelle confirms
      {{vat_inclusive}}.
   3. The apps are not in the stores (the Director registers the Apple and
      Google developer accounts, contract 16.4): app.ios_url, app.android_url,
      app.ios_app_id and app.android_package are null, so no store badge, no
      store link and no smart app banner is shown anywhere.
   4. The desktop QR with claim code is parked until P3 (claim-code-create and
      claim-code-redeem); /get-app and /claim/{code} say so.
   5. Subscriber state and the per tenant hide or rebrand toggle are hooks in
      cnc-ad.js fed by subscriber_stub and tenant_stub below until P3 supplies
      company_subscription and ad_config.
   6. Storage packs beyond the included 10 GB wait for {{rate_card}}.
   7. The Inspection reports list in Section F reads an empty list
      (inspection_reports_stub) until P3 fills it from the database. */
window.HSF_ADS = (function () {
  'use strict';
  var WA_NUMBER = '27600702723';
  function wa(text) { return 'https://wa.me/' + WA_NUMBER + '?text=' + encodeURIComponent(text); }
  /* A banner's call to action: the Bee-Inspect page, in a new tab so the File
     stays open. cnc-ad.js adds the UTM rules (utm below) as it draws the link. */
  var PAGE_TAB = ': opens the Bee-Inspect page in a new tab';
  function primary(label, aria) {
    return { label: label, aria: aria + PAGE_TAB, href: '/bee-inspect' };
  }
  var ARIA_WA = ': opens WhatsApp with a Care Net sales executive';

  return {
    version: 'HSF-ADS-1.1',
    as_at: '25/09/2026',
    product: 'Bee-Inspect',
    eyebrow: 'Bee-Inspect add on',
    brand: { red: '#ED1B24', deep_red: '#B7141A', ink: '#0F0F0F', gold: '#F0A32B' },

    /* B8. Amounts in rand as numbers; the pages format them R1 150,00. */
    price: {
      base_zar: 299,
      extra_company_zar: 199,
      vat_inclusive: null,
      stub: true,
      stub_note: 'VAT treatment pending Chantelle ({{vat_inclusive}}).',
      vat_line: 'VAT to be confirmed.',
      line: 'From R299,00 a month. Extra company R199,00 a month. VAT to be confirmed.',
      short: 'From R299,00 a month. VAT to be confirmed.',
      plans: [
        {
          id: 'base',
          name: 'Bee-Inspect',
          zar_month: 299,
          wallet_zar_month: 150,
          storage_gb: 10,
          includes: [
            'One auditor and your first company',
            'Unlimited inspections and template reports',
            'An AI Wallet with R150,00 of value every month',
            '10 GB of storage for photos and voice notes'
          ]
        },
        {
          id: 'extra_company',
          name: 'Each extra company',
          zar_month: 199,
          wallet_zar_month: 100,
          storage_gb: 10,
          includes: [
            'Another company under the same auditor',
            'An AI Wallet with R100,00 of value every month',
            'Another 10 GB of storage for that company'
          ]
        }
      ],
      wallet: {
        topups: [
          { zar: 99, value_zar: 99 },
          { zar: 249, value_zar: 260 },
          { zar: 499, value_zar: 550 },
          { zar: 999, value_zar: 1150 }
        ],
        auto_topup: { zar: 99, below_zar: 20, opt_in: true },
        included_rolls_months: 1,
        purchased_lasts_months: 12,
        photo_tagging_free_per_report: 50,
        points: [
          'The AI Wallet holds rand, never tokens or credits. You see every amount in rand.',
          'Before anything is paid from the AI Wallet, Bee-Inspect shows the estimate in rand. You pay the actual cost afterwards, and if that comes in more than a quarter above the estimate, you pay the estimate instead.',
          'Value included with your subscription rolls over for one month. Top ups you buy last 12 months.',
          'Automatic top up is off unless you switch it on: then R99,00 is added when the balance drops below R20,00.',
          'Photo tagging is free for up to 50 photos per report.',
          'At R0,00 nothing stops: capturing inspections and template reports still work. Only what is paid from the AI Wallet waits for a top up.'
        ]
      },
      storage: {
        included_gb: 10,
        packs: null,
        stub: true,
        stub_note: 'Storage pack prices wait for {{rate_card}}.',
        points: [
          '10 GB for each company on your subscription.',
          'You are told at 80% and 95% full. At 100%, new photos and voice notes wait, while viewing and syncing carry on.',
          'Extra storage: price to be confirmed.'
        ]
      }
    },

    /* A4: on any Bee-Inspect destination link, never on wa.me. */
    utm: {
      utm_source: 'hsf_builder',
      utm_medium: 'in_product_banner',
      utm_campaign: 'bee_inspect_addon',
      utm_content: '{ad_id}_{variant}',
      never_on_hosts: ['wa.me', 'api.whatsapp.com']
    },

    links: {
      whatsapp_number: WA_NUMBER,
      product_page: { href: '/bee-inspect' },
      sample_report: { href: '/bee-inspect/sample-report', label: 'See a sample report', aria: 'See a sample Bee-Inspect report' + PAGE_TAB.replace('the Bee-Inspect page', 'it') },
      get_app: { href: '/get-app' },
      /* The product page keeps the WhatsApp route as its fallback (never a UTM on wa.me). */
      whatsapp_fallback: {
        label: 'WhatsApp a sales executive',
        aria: 'WhatsApp a sales executive about Bee-Inspect' + ARIA_WA,
        href: wa('Hello Care Net, I would like to know more about Bee-Inspect, the inspection and risk assessment add on for my Health and Safety File.')
      },
      /* /get-app: until the apps are released, a sales executive lets you know. */
      notify_me: {
        label: 'Tell me when it is ready',
        aria: 'Tell me when the Bee-Inspect app is ready' + ARIA_WA,
        href: wa('Hello Care Net, please let me know when the Bee-Inspect app is in the App Store and Google Play.')
      },
      open_app: {
        label: 'Open Bee-Inspect',
        aria: 'Open Bee-Inspect' + ARIA_WA,
        href: wa('Hello Care Net, I use Bee-Inspect and need the link to open it.'),
        stub: true,
        stub_note: 'No app or web desk address yet (P3 and P4); a sales executive helps meanwhile.'
      }
    },

    /* Hooks fed by stubs until P3 (company_subscription, ad_config). */
    subscriber_stub: false,
    tenant_stub: { hidden: false, brand: null },

    /* /get-app reads these. Null until the Director registers the store
       accounts (contract 16.4): no badge, no store link, no smart app banner. */
    app: {
      ios_url: null,
      android_url: null,
      ios_app_id: null,
      android_package: null,
      web_desk_url: null,
      stub: true,
      stub_note: 'Store addresses and app ids wait for the Apple and Google developer accounts ({{store_publisher}}, {{apple_team_id}}, {{android_sha256}}).',
      coming_soon: 'The Bee-Inspect app is coming to the App Store and Google Play.'
    },

    /* The Inspection reports list in Section F of the builder: empty until P3
       reads Issued reports from the database. */
    inspection_reports_stub: [],

    dismiss_days: 14,
    max_per_screen: 2,

    /* Words for the controls every banner carries. */
    ui: {
      dismiss_label: 'Hide this Bee-Inspect message for 14 days',
      collapse_label: 'Make this Bee-Inspect message smaller',
      show_label: 'Show',
      show_aria: 'Show the Bee-Inspect message',
      how_label: 'How it works',
      how_steps: [
        'The competent person walks the site with Bee-Inspect on a phone, capturing findings, photos and voice notes.',
        'AI assists with the draft report. Nothing is issued until the competent person reviews and signs it.',
        'The signed report files into Section F of this File.'
      ],
      subscriber_headline: 'Your Bee-Inspect reports file here',
      subscriber_body: 'Each report you sign in Bee-Inspect files into Section F of this File.'
    },

    ads: {
      'AD-01': {
        where: 'hsf-builder Section F card, at the top',
        when: 'Always on the File view; the gaps variant when Section F has outstanding or expired items',
        mobile: 'inline',
        collapses: true,
        headline: 'Inspect it on your phone. File it here.',
        headline_gaps: '{n} inspection records outstanding',
        headline_gaps_one: '1 inspection record outstanding',
        body: 'Walk the site with Bee-Inspect on a phone. AI assists with the risk assessment report, the competent person signs it, and it lands in Section F.',
        strip: 'Bee-Inspect files signed inspections here.',
        primary: primary('Add Bee-Inspect', 'Add Bee-Inspect'),
        secondary: 'sample_report'
      },
      'AD-02': {
        where: 'hsf-builder First File guide, the Section F step',
        when: 'Guide open',
        mobile: 'inline',
        kind: 'tip',
        tip: 'Tip: Bee-Inspect can do these inspections on a phone, and each signed report files into Section F.',
        primary: primary('See Bee-Inspect', 'See Bee-Inspect')
      },
      'AD-03': {
        where: 'hsf-builder Gap report tab, after the Section F gaps',
        when: 'Section F gaps above 0',
        mobile: 'inline',
        headline: 'Close {n} gaps in Section F',
        headline_one: 'Close 1 gap in Section F',
        body: 'Bee-Inspect turns your Section F gaps into an inspection checklist on the competent person’s phone, and each signed report files back into Section F.',
        primary: primary('Turn gaps into a checklist', 'Turn Section F gaps into a Bee-Inspect checklist')
      },
      'AD-04': {
        where: 'hsf-builder compliance strip',
        when: 'Outstanding plus expired above 0; desktop only (hidden under 768 pixels)',
        mobile: 'hidden',
        kind: 'strip',
        text: '{n} items are outstanding or expired. The inspections among them can be done with Bee-Inspect.',
        text_one: '1 item is outstanding or expired. If it is an inspection, Bee-Inspect can do it.',
        primary: primary('See Bee-Inspect', 'See Bee-Inspect')
      },
      'AD-05': {
        where: 'hsf-builder Sign off readiness, beside the Bee-Matched recruitment box',
        when: 'Always on the File view',
        mobile: 'inline',
        collapses: true,
        kind: 'twin',
        headline: 'Their tool on site',
        body: 'Bee-Matched finds the competent person. Bee-Inspect is their tool on site: they inspect on a phone and sign the report into Section F.',
        strip: 'Bee-Inspect: the competent person’s tool on site.',
        primary: primary('Add Bee-Inspect', 'Add Bee-Inspect')
      },
      'AD-06': {
        where: 'health-and-safety-file, below the two ways to take the File',
        when: 'Always',
        mobile: 'inline',
        headline: 'The File is free. The risk assessment is Bee-Inspect.',
        body: 'Build your File here at no charge. When a site needs inspecting, the competent person walks it with Bee-Inspect on a phone, AI assists with the report, and the signed report files into Section F.',
        primary: primary('See Bee-Inspect', 'See Bee-Inspect')
      },
      'AD-07': {
        where: 'hsf-builder demonstration, directly after the Section F card',
        when: 'Demonstration (?demo=1) on the File view',
        mobile: 'inline',
        headline: 'This is where Bee-Inspect fills Section F',
        body: 'In a real File, each report a competent person signs in Bee-Inspect files into Section F by itself. This demonstration shows where it lands.',
        primary: primary('See Bee-Inspect', 'See Bee-Inspect')
      },
      'AD-08': {
        where: 'portal, the Health and Safety Files card',
        when: 'Signed in with at least one File (and the demonstration portal)',
        mobile: 'inline',
        headline: 'Your File is built. Keep it current.',
        body: 'Inspections and risk assessments need doing again. Bee-Inspect puts them on the competent person’s phone, and each signed report files into Section F of your File.',
        primary: primary('Add Bee-Inspect', 'Add Bee-Inspect')
      },
      'AD-09': { where: 'Export success page', parked: true, parked_until: '{{export_page_decision}}', note: 'Card and QR; the export page is not built.' },
      'AD-10': { where: 'File ready or nurture email', parked: true, parked_until: 'marketing consent and {{email_platform}}', note: 'Deep link to get the app; marketing consent only.' }
    }
  };
})();
