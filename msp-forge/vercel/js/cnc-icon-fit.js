/* cnc-icon-fit.js :: Version 1.0 :: 23 September 2026
   Makes every industry icon fill its box at the same size.

   The industry icon SVGs were exported with different amounts of empty space
   around the red circle, so at one box size some circles look much smaller than
   others. For each <img data-fit-icon> this script fetches the SVG, measures the
   artwork's real bounds, crops the viewBox to them and swaps the image for the
   cleaned inline SVG. The tile's box then decides the size, and every circle
   matches the largest one.

   Safety: the inline copy keeps only drawing elements. Scripts, foreignObject,
   event handler attributes and external references are removed before it
   touches the page. If the fetch fails (for example no CORS on the image host)
   the original <img> stays, so nothing breaks.

   The lasting fix is at the source: the icon set should be re-exported with the
   viewBox tight to the circle (see the asset spec notes). Then this script only
   confirms what is already true. */
(function () {
  'use strict';
  var cache = {};
  /* Measured fallback (24/09/2026, from the live grid): these ten icons draw a
     42 px circle where the other seven draw 62 to 64 px in the same box. They
     are scaled up by 64/42 at once, so the grid matches even when the icon host
     does not allow the page to read the SVG for the exact crop below. When the
     crop succeeds the inline SVG replaces the image and needs no scaling. */
  var SMALL = /cnc-medical-surveillance-(agriculture-and-forestry|cleaning-and-hygiene-services|construction|hospitality-and-food-service|manufacturing|mining-and-quarrying|security-services|telecommunications-and-tower-work|transport-and-logistics|waste-management)-icon\.svg/;
  var SCALE = 64 / 42;
  function prescale(img) {
    var url = img.getAttribute('src') || '';
    img.style.transform = SMALL.test(url) ? 'scale(' + SCALE.toFixed(3) + ')' : '';
    img.style.transformOrigin = 'center';
  }
  var ALLOWED = /^(svg|g|path|circle|ellipse|rect|line|polyline|polygon|defs|lineargradient|radialgradient|stop|clippath|mask|use|symbol|title|desc|style)$/i;

  function clean(node) {
    var kids = Array.prototype.slice.call(node.children || []);
    kids.forEach(function (k) {
      if (!ALLOWED.test(k.localName)) { k.remove(); return; }
      Array.prototype.slice.call(k.attributes).forEach(function (a) {
        var n = a.name.toLowerCase();
        var v = String(a.value || '');
        if (n.indexOf('on') === 0) k.removeAttribute(a.name);
        else if ((n === 'href' || n === 'xlink:href') && v.charAt(0) !== '#') k.removeAttribute(a.name);
        else if (/url\(\s*['"]?(?!#)/i.test(v)) k.removeAttribute(a.name);
      });
      if (k.localName.toLowerCase() === 'style' && /@import|url\(\s*['"]?(?!#)/i.test(k.textContent)) k.remove();
      else clean(k);
    });
  }

  function load(url) {
    if (!cache[url]) {
      cache[url] = fetch(url, { mode: 'cors', credentials: 'omit' })
        .then(function (r) { if (!r.ok) throw new Error('icon ' + r.status); return r.text(); })
        .then(function (text) {
          var doc = new DOMParser().parseFromString(text, 'image/svg+xml');
          var svg = doc.documentElement;
          if (!svg || svg.localName !== 'svg' || doc.querySelector('parsererror')) throw new Error('not svg');
          clean(svg);
          Array.prototype.slice.call(svg.attributes).forEach(function (a) {
            if (a.name.toLowerCase().indexOf('on') === 0) svg.removeAttribute(a.name);
          });
          // Measure the drawn artwork off screen.
          var host = document.createElement('div');
          host.style.cssText = 'position:absolute;left:-9999px;top:0;width:200px;height:200px;visibility:hidden';
          var live = document.importNode(svg, true);
          live.setAttribute('width', '200'); live.setAttribute('height', '200');
          host.appendChild(live); document.body.appendChild(host);
          var box = null;
          try { box = live.getBBox(); } catch (e) { box = null; }
          host.remove();
          if (!box || !(box.width > 0) || !(box.height > 0)) throw new Error('no bounds');
          var side = Math.max(box.width, box.height);
          var x = box.x - (side - box.width) / 2;
          var y = box.y - (side - box.height) / 2;
          svg.setAttribute('viewBox', [x, y, side, side].map(function (n) { return Math.round(n * 1000) / 1000; }).join(' '));
          svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
          return new XMLSerializer().serializeToString(svg);
        });
    }
    return cache[url];
  }

  function fit(img) {
    if (!img) return;
    prescale(img);
    if (img.dataset.fitIcon === 'scale' || img.dataset.fitDone) return;
    img.dataset.fitDone = '1';
    var url = img.currentSrc || img.src;
    if (!url || !/\.svg(\?|$)/i.test(url)) return;
    load(url).then(function (markup) {
      var wrap = document.createElement('span');
      wrap.innerHTML = markup;
      var svg = wrap.firstElementChild;
      if (!svg) return;
      svg.removeAttribute('width'); svg.removeAttribute('height');
      svg.style.display = 'block';
      svg.setAttribute('aria-hidden', img.getAttribute('alt') ? 'false' : 'true');
      svg.setAttribute('focusable', 'false');
      if (img.getAttribute('alt')) { svg.setAttribute('role', 'img'); svg.setAttribute('aria-label', img.getAttribute('alt')); }
      Array.prototype.slice.call(img.attributes).forEach(function (a) {
        if (/^data-|^class$|^id$/.test(a.name)) svg.setAttribute(a.name, a.value);
      });
      img.replaceWith(svg);
    }).catch(function () { /* keep the original image */ });
  }

  function run(root) {
    Array.prototype.forEach.call((root || document).querySelectorAll('img[data-fit-icon]'), fit);
  }

  window.CNCIconFit = { run: run, fit: fit };
  var mo = new MutationObserver(function (list) {
    list.forEach(function (m) {
      Array.prototype.forEach.call(m.addedNodes, function (n) {
        if (n.nodeType !== 1) return;
        if (n.matches && n.matches('img[data-fit-icon]')) fit(n);
        else if (n.querySelectorAll) run(n);
      });
      if (m.type === 'attributes' && m.target.matches && m.target.matches('img[data-fit-icon]')) {
        delete m.target.dataset.fitDone; fit(m.target);
      }
    });
  });
  function start() { run(document); mo.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] }); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
