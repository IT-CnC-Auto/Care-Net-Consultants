/* CNC | Bee-Inspect add on banners: copy, prices, links and UTM rules.
   Version 1.0 | 24/09/2026 | Bee-Inspect P1 (hsf/BEE-INSPECT-BUILD-PROMPT.md
   A1, A2 and A4, applied under hsf/BUILD-CONTRACT.md 16.3).

   Read by /js/cnc-ad.js. No page types any of this; change it here.

   House rules for every visible string (checked by test/api/bee-inspect-ads.test.js):
   South African British English; no dash or hyphen punctuation in prose (the
   names Bee-Inspect and Bee-Matched keep theirs); rand as R299,00; never
   "compliant" or "guarantee"; no internal system names; AI "assists"; a
   competent person reviews and signs. Banners never link to a Medical
   Surveillance Plan page.

   STUBS (each marked stub: true below):
   1. Every primary call to action opens WhatsApp with a sales executive
      (wa.me/27600702723) and a prefilled Bee-Inspect message, with no UTM
      (UTMs never go on wa.me). P2 builds /bee-inspect and each becomes
      future_href with the UTM rules in utm.
   2. "See a sample report" is withheld until P2 builds /bee-inspect/sample-report.
   3. "Open Bee-Inspect" for subscribers has no app or web desk address yet
      (P3 and P4); it asks a sales executive meanwhile.
   4. VAT: shown as "VAT to be confirmed" until Chantelle confirms
      {{vat_inclusive}}.
   5. The desktop QR with claim code is parked until P3 (claim-code-create);
      no space is reserved for it.
   6. Subscriber state and the per tenant hide or rebrand toggle are hooks in
      cnc-ad.js fed by subscriber_stub and tenant_stub below until P3 supplies
      company_subscription and ad_config. */
window.HSF_ADS = (function () {
  'use strict';
  var WA_NUMBER = '27600702723';
  function wa(text) { return 'https://wa.me/' + WA_NUMBER + '?text=' + encodeURIComponent(text); }
  var STUB_NOTE = 'WhatsApp a sales executive until P2 builds /bee-inspect; then the link becomes future_href with the UTM rules.';
  function primary(label, aria, message, ref) {
    return {
      label: label,
      aria: aria,
      href: wa(message + ' (ref ' + ref + ')'),
      stub: true,
      stub_note: STUB_NOTE,
      future_href: '/bee-inspect'
    };
  }
  var ASK = 'Hello Care Net, I would like to know more about Bee-Inspect, the inspection and risk assessment add on for my Health and Safety File.';
  var ADD = 'Hello Care Net, I would like to add Bee-Inspect to my Health and Safety File. Please tell me how.';
  var ARIA_WA = ': opens WhatsApp with a Care Net sales executive';

  return {
    version: 'HSF-ADS-1.0',
    as_at: '24/09/2026',
    product: 'Bee-Inspect',
    eyebrow: 'Bee-Inspect add on',
    brand: { red: '#ED1B24', deep_red: '#B7141A', ink: '#0F0F0F', gold: '#F0A32B' },

    price: {
      base_zar: 299,
      extra_company_zar: 199,
      vat_inclusive: null,
      stub: true,
      stub_note: 'VAT treatment pending Chantelle ({{vat_inclusive}}).',
      line: 'From R299,00 a month. Extra company R199,00 a month. VAT to be confirmed.',
      short: 'From R299,00 a month. VAT to be confirmed.'
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
      product_page: { href: null, future_href: '/bee-inspect', stub: true, stub_note: 'Built in P2.' },
      sample_report: { href: null, future_href: '/bee-inspect/sample-report', withheld_until: 'P2', stub: true, stub_note: 'See a sample report is not shown until P2.' },
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
        primary: primary('Add Bee-Inspect', 'Add Bee-Inspect' + ARIA_WA, ADD, 'AD-01')
      },
      'AD-02': {
        where: 'hsf-builder First File guide, the Section F step',
        when: 'Guide open',
        mobile: 'inline',
        kind: 'tip',
        tip: 'Tip: Bee-Inspect can do these inspections on a phone, and each signed report files into Section F.',
        primary: primary('Ask about Bee-Inspect', 'Ask about Bee-Inspect' + ARIA_WA, ASK, 'AD-02')
      },
      'AD-03': {
        where: 'hsf-builder Gap report tab, after the Section F gaps',
        when: 'Section F gaps above 0',
        mobile: 'inline',
        headline: 'Close {n} gaps in Section F',
        headline_one: 'Close 1 gap in Section F',
        body: 'Bee-Inspect turns your Section F gaps into an inspection checklist on the competent person’s phone, and each signed report files back into Section F.',
        primary: primary('Turn gaps into a checklist', 'Turn Section F gaps into a Bee-Inspect checklist' + ARIA_WA,
          'Hello Care Net, I would like to turn the gaps in Section F of my Health and Safety File into a Bee-Inspect checklist.', 'AD-03')
      },
      'AD-04': {
        where: 'hsf-builder compliance strip',
        when: 'Outstanding plus expired above 0; desktop only (hidden under 768 pixels)',
        mobile: 'hidden',
        kind: 'strip',
        text: '{n} items are outstanding or expired. The inspections among them can be done with Bee-Inspect.',
        text_one: '1 item is outstanding or expired. If it is an inspection, Bee-Inspect can do it.',
        primary: primary('Ask about Bee-Inspect', 'Ask about Bee-Inspect' + ARIA_WA, ASK, 'AD-04')
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
        primary: primary('Add Bee-Inspect', 'Add Bee-Inspect' + ARIA_WA, ADD, 'AD-05')
      },
      'AD-06': {
        where: 'health-and-safety-file, below the two ways to take the File',
        when: 'Always',
        mobile: 'inline',
        headline: 'The File is free. The risk assessment is Bee-Inspect.',
        body: 'Build your File here at no charge. When a site needs inspecting, the competent person walks it with Bee-Inspect on a phone, AI assists with the report, and the signed report files into Section F.',
        primary: primary('Ask about Bee-Inspect', 'Ask about Bee-Inspect' + ARIA_WA, ASK, 'AD-06')
      },
      'AD-07': {
        where: 'hsf-builder demonstration, directly after the Section F card',
        when: 'Demonstration (?demo=1) on the File view',
        mobile: 'inline',
        headline: 'This is where Bee-Inspect fills Section F',
        body: 'In a real File, each report a competent person signs in Bee-Inspect files into Section F by itself. This demonstration shows where it lands.',
        primary: primary('Ask about Bee-Inspect', 'Ask about Bee-Inspect' + ARIA_WA, ASK, 'AD-07')
      },
      'AD-08': {
        where: 'portal, the Health and Safety Files card',
        when: 'Signed in with at least one File (and the demonstration portal)',
        mobile: 'inline',
        headline: 'Your File is built. Keep it current.',
        body: 'Inspections and risk assessments need doing again. Bee-Inspect puts them on the competent person’s phone, and each signed report files into Section F of your File.',
        primary: primary('Add Bee-Inspect', 'Add Bee-Inspect' + ARIA_WA, ADD, 'AD-08')
      },
      'AD-09': { where: 'Export success page', parked: true, parked_until: '{{export_page_decision}}', note: 'Card and QR; the export page is not built.' },
      'AD-10': { where: 'File ready or nurture email', parked: true, parked_until: 'marketing consent and {{email_platform}}', note: 'Deep link to get the app; marketing consent only.' }
    }
  };
})();
