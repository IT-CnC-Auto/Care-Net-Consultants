/* =====================================================================
   cnc-secnav.js :: right-side navigator band
   Version: 2.0 | Owner: Kc (CNC brand and front end)

   Handles both kinds of link the band can carry:
     in-page anchors  smooth scroll, and the section in view is marked
     page links       the page you are on is marked, and does not link to itself

   The band also gives way to the footer on scroll, so it never sits over
   the sign-off.

   FRONT END ONLY. It reads nothing and sends nothing anywhere.
   ===================================================================== */
(function () {
  var nav = document.querySelector('.cnc-secnav');
  if (!nav) return;

  var links   = [].slice.call(nav.querySelectorAll('a'));
  var anchors = [];   /* {a, sec} for in-page links whose target exists */

  /* The header is sticky, so a section scrolled to the very top would sit
     underneath it. Measure the header rather than guessing, because its
     height changes with the menu breakpoint. */
  function headerOffset() {
    var h = document.querySelector('.cnc-sitehead');
    return (h ? h.getBoundingClientRect().height : 0) + 18;
  }

  var here = (location.pathname.split('/').pop() || 'index.html');

  links.forEach(function (a) {
    var href = a.getAttribute('href') || '';

    if (href.charAt(0) === '#' && href.length > 1) {
      var sec = document.querySelector(href);
      if (!sec) return;                      /* never leave a dead link in the band */
      anchors.push({ a: a, sec: sec });
      a.addEventListener('click', function (e) {
        e.preventDefault();
        var y = sec.getBoundingClientRect().top + window.scrollY - headerOffset();
        window.scrollTo({ top: Math.max(0, y), behavior: 'smooth' });
      });
      return;
    }

    var target = href.split('#')[0].split('?')[0].split('/').pop() || 'index.html';
    if (target === here) {
      a.classList.add('is-current');
      a.setAttribute('aria-current', 'page');
      a.addEventListener('click', function (e) { e.preventDefault(); });
    }
  });

  var foot = document.querySelector('.ah-stamp') || document.querySelector('footer');

  function spy() {
    /* Mark the section currently in view: the last one whose top has passed
       a line a third of the way down the viewport. */
    if (anchors.length) {
      var line = window.scrollY + headerOffset() + window.innerHeight * 0.30;
      var cur = null;
      anchors.forEach(function (o) {
        if (o.sec.getBoundingClientRect().top + window.scrollY <= line) cur = o;
      });
      /* At the very bottom of the page the last section is the one being read,
         even if its top never crosses the line on a short final section. */
      if (window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 2) {
        cur = anchors[anchors.length - 1];
      }
      anchors.forEach(function (o) { o.a.classList.toggle('is-active', o === cur); });
    }
    if (foot) {
      nav.classList.toggle('cnc-hid', foot.getBoundingClientRect().top < window.innerHeight * 0.75);
    }
  }

  var queued = false;
  window.addEventListener('scroll', function () {
    if (!queued) { queued = true; requestAnimationFrame(function () { spy(); queued = false; }); }
  }, { passive: true });
  window.addEventListener('resize', spy);
  spy();
})();
