/* =====================================================================
   cnc-hsf-links.js :: links from the File pages to the letterhead
   examples and the legislation backgrounds (contract 12.7)
   Version: 1.1 | 24/09/2026 | CNC HSF FORGE
   1.1: instrument links use the clean address /legislation#<slug>, and
        every link stays on the File pages (contract 15.1).

   Needs, loaded before it:
     /hsf/examples.js            window.CNC_HSF_EXAMPLES (hsf/build_examples.mjs)
     /hsf/legislation-index.js   window.CNC_LEGISLATION_INDEX (hsf/build_legislation.py)

   window.CNCHsfLinks.exampleHtml(section, cls)
       "See an example on Care Net letterhead" for the section, linking to its
       PDF, with the Word version beside it. Empty when the section has no
       generated example, so nothing shows until the files exist.
   window.CNCHsfLinks.link(root)
       Links every instrument name in the text under root to
       /legislation#<slug>. Whole names only, never inside a word, never
       inside a link, button, summary, form control, code or heading.
   window.CNCHsfLinks.watch(root)
       link(root) now and again whenever the content under root changes (the
       builder and the sample re render their cards).
   Every link carries data-cta, so cnc-tracking.js counts it.
   ===================================================================== */
(function (w, d) {
  'use strict';
  if (w.CNCHsfLinks) return;

  var EX = Array.isArray(w.CNC_HSF_EXAMPLES) ? w.CNC_HSF_EXAMPLES : [];
  var IDX = Array.isArray(w.CNC_LEGISLATION_INDEX) ? w.CNC_LEGISLATION_INDEX : [];
  var esc = function (s) { return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); };

  /* One small stylesheet, shared by every page that loads this script. The
     example links use a doubled class so a page rule such as ".card p" cannot
     change their size (the same 12.5 px everywhere), and each link is at least
     24 px tall, the WCAG 2.2 AA target size, because they stand on their own
     rather than inside a sentence. */
  var css = d.createElement('style');
  css.textContent = ''
    + 'a.cnc-leg{color:inherit;text-decoration:underline;text-decoration-style:dotted;text-decoration-color:#C5141B;text-underline-offset:2px}'
    + 'a.cnc-leg:hover,a.cnc-leg:focus-visible{color:#C5141B;text-decoration-style:solid}'
    + '.cnc-ex.cnc-ex{display:flex;flex-wrap:wrap;align-items:center;gap:4px 12px;margin:8px 0 0;font-size:12.5px;line-height:1.45}'
    + '.cnc-ex.cnc-ex a{display:inline-flex;align-items:center;min-height:24px;color:#C5141B;font-weight:700;overflow-wrap:anywhere}'
    + '.cnc-ex.cnc-ex a.alt{font-weight:600}'
    + '.cnc-vh{position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;border:0}'
    + '.cnc-ex.cnc-ex a:focus-visible,a.cnc-leg:focus-visible{outline:3px solid #1A1A1A;outline-offset:2px}';
  (d.head || d.documentElement).appendChild(css);

  function examplesFor(section) {
    return EX.filter(function (e) { return e && e.section === section && (e.pdf || e.docx); });
  }
  function exampleHtml(section, cls) {
    var list = examplesFor(section);
    if (!list.length) return '';
    return list.map(function (e) {
      var main = e.pdf || e.docx, kind = e.pdf ? 'pdf' : 'docx';
      var title = 'Example for Section ' + section + ': ' + e.title + (e.pdf ? ' (PDF)' : ' (Word)');
      return '<p class="cnc-ex' + (cls ? ' ' + esc(cls) : '') + '">'
        + '<a href="' + esc(main) + '" target="_blank" rel="noopener" title="' + esc(title) + '" data-cta="hsf_example_' + kind + ':' + esc(section) + '">See an example on Care Net letterhead<span class="cnc-vh">: ' + esc(e.title) + ', PDF</span></a>'
        + (e.pdf && e.docx ? '<a class="alt" href="' + esc(e.docx) + '" download data-cta="hsf_example_docx:' + esc(section) + '">Word version<span class="cnc-vh"> of ' + esc(e.title) + '</span></a>' : '')
        + '</p>';
    }).join('');
  }

  /* ---- instrument names -> slug, longest name first so a longer name wins. */
  var bySlug = {}, names = [];
  IDX.forEach(function (e) {
    (e.names || []).forEach(function (n) { if (n && !bySlug[n]) { bySlug[n] = e.slug; names.push(n); } });
  });
  names.sort(function (a, b) { return b.length - a.length; });
  var reSrc = names.map(function (n) { return n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'); }).join('|');
  var RE = null;
  try { RE = reSrc ? new RegExp('(?<![A-Za-z0-9])(?:' + reSrc + ')(?![A-Za-z0-9])', 'g') : null; }
  catch (e) { RE = null; /* a browser without lookbehind: leave the text as it is */ }

  var SKIP = { A: 1, BUTTON: 1, SUMMARY: 1, SCRIPT: 1, STYLE: 1, OPTION: 1, SELECT: 1, TEXTAREA: 1, INPUT: 1, LABEL: 1, CODE: 1, H1: 1, H2: 1, H3: 1, TITLE: 1, NOSCRIPT: 1 };
  function skipped(node, root) {
    for (var p = node.parentNode; p && p !== root.parentNode; p = p.parentNode) {
      if (p.nodeType === 1 && (SKIP[p.nodeName] || (p.hasAttribute && p.hasAttribute('data-no-leg')))) return true;
    }
    return false;
  }
  function link(root) {
    if (!RE || !root) return 0;
    var walker = d.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    var todo = [], n;
    while ((n = walker.nextNode())) {
      if (!n.nodeValue || n.nodeValue.length < 4) continue;
      RE.lastIndex = 0;
      if (RE.test(n.nodeValue) && !skipped(n, root)) todo.push(n);
    }
    todo.forEach(function (node) {
      var text = node.nodeValue, frag = d.createDocumentFragment(), last = 0, m;
      RE.lastIndex = 0;
      while ((m = RE.exec(text))) {
        if (m.index > last) frag.appendChild(d.createTextNode(text.slice(last, m.index)));
        var slug = bySlug[m[0]];
        var a = d.createElement('a');
        a.className = 'cnc-leg';
        a.href = '/legislation#' + slug;
        a.setAttribute('data-cta', 'legislation_background:' + slug);
        a.title = 'What ' + m[0] + ' covers, in plain words';
        a.textContent = m[0];
        frag.appendChild(a);
        last = m.index + m[0].length;
      }
      if (last < text.length) frag.appendChild(d.createTextNode(text.slice(last)));
      node.parentNode.replaceChild(frag, node);
    });
    return todo.length;
  }
  function watch(root) {
    if (!root) return;
    link(root);
    if (!w.MutationObserver) return;
    var queued = false;
    new MutationObserver(function () {
      if (queued) return;
      queued = true;
      setTimeout(function () { queued = false; link(root); }, 0);
    }).observe(root, { childList: true, subtree: true });
  }

  w.CNCHsfLinks = { exampleHtml: exampleHtml, examplesFor: examplesFor, link: link, watch: watch };
})(window, document);
