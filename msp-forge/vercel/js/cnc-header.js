/* =====================================================================
   cnc-header.js :: mobile menu behaviour for the CNC site header
   Version: 1.0 | Owner: Kc (CNC brand and front end)

   FRONT END ONLY. It toggles classes and clones the two call to action
   buttons into the mobile menu. It reads nothing, stores nothing and
   sends nothing anywhere.

   Lifted from the live site's hamburger so the menu opens and closes the
   same way here as it does on carenetconsultants.co.za.
   ===================================================================== */
(function () {
  var nav = document.querySelector('.cnc-mainnav');
  if (!nav || nav.dataset.burger) return;
  nav.dataset.burger = '1';

  var mwrap = nav.querySelector('.mwrap');
  var topUl = mwrap && mwrap.querySelector(':scope > ul');
  if (!mwrap || !topUl) return;

  /* Hamburger button, injected so the markup stays clean on every page */
  var burger = document.createElement('button');
  burger.className = 'cnc-burger';
  burger.type = 'button';
  burger.setAttribute('aria-label', 'Open menu');
  burger.setAttribute('aria-expanded', 'false');
  burger.setAttribute('aria-controls', 'cnc-nav-list');
  burger.innerHTML = '<span></span><span></span><span></span>';
  mwrap.insertBefore(burger, topUl);
  if (!topUl.id) topUl.id = 'cnc-nav-list';

  burger.addEventListener('click', function () {
    var open = nav.classList.toggle('open');
    burger.setAttribute('aria-expanded', open ? 'true' : 'false');
    burger.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
  });

  /* If the header carries call to action buttons, mirror them into the mobile
     menu so they are not out of reach on a phone. The utility row that held
     them was removed on Kc's instruction, so this is a no-op as things stand
     and costs nothing; it starts working again the moment buttons come back. */
  function addAction(btn, opts) {
    if (!btn) return;
    opts = opts || {};
    var li = document.createElement('li');
    li.className = 'mobile-only nav-action' +
      (opts.btn ? ' nav-action-btn' : '') +
      (opts.top ? ' nav-action-top' : '');
    var a = document.createElement('a');
    a.textContent = (btn.textContent || '').trim();
    a.href = btn.getAttribute('href') || '#';
    if (btn.getAttribute('target')) a.target = btn.getAttribute('target');
    if (btn.getAttribute('rel')) a.rel = btn.getAttribute('rel');
    a.addEventListener('click', function () { nav.classList.remove('open'); });
    li.appendChild(a);
    topUl.appendChild(li);
  }
  var cta = document.querySelector('.cnc-navcta');
  if (cta) {
    var links = cta.querySelectorAll('a');
    addAction(links[0], { top: true });
    addAction(links[1], { btn: true });
  }

  /* Close the menu on Escape, and when the viewport grows back to desktop */
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && nav.classList.contains('open')) {
      nav.classList.remove('open');
      burger.setAttribute('aria-expanded', 'false');
      burger.setAttribute('aria-label', 'Open menu');
      burger.focus();
    }
  });
  var MQ = window.matchMedia('(max-width:1219px)');
  function onChange(ev) {
    if (!ev.matches) {
      nav.classList.remove('open');
      burger.setAttribute('aria-expanded', 'false');
      burger.setAttribute('aria-label', 'Open menu');
    }
  }
  if (MQ.addEventListener) MQ.addEventListener('change', onChange);
  else if (MQ.addListener) MQ.addListener(onChange);
})();
