/* =====================================================================
   cnc-secnav.js :: right-side navigator band
   Version: 1.0 | Owner: Kc (CNC brand and front end)

   Marks the current page in the band, and hides the band once the footer
   comes into view so it never sits over the sign-off.

   FRONT END ONLY. It reads nothing and sends nothing anywhere.
   ===================================================================== */
(function () {
  var nav = document.querySelector('.cnc-secnav');
  if (!nav) return;

  /* Mark the page we are on, and stop it linking to itself. */
  var here = (location.pathname.split('/').pop() || 'index.html');
  [].forEach.call(nav.querySelectorAll('a'), function (a) {
    var target = (a.getAttribute('href') || '').split('#')[0].split('?')[0].split('/').pop() || 'index.html';
    if (target === here) {
      a.classList.add('is-current');
      a.setAttribute('aria-current', 'page');
      a.addEventListener('click', function (e) { e.preventDefault(); });
    }
  });

  /* Give way to the footer, so the band never covers the sign-off. */
  var foot = document.querySelector('.ah-stamp') || document.querySelector('footer');
  if (!foot) return;
  function spy() {
    var r = foot.getBoundingClientRect();
    nav.classList.toggle('cnc-hid', r.top < window.innerHeight * 0.75);
  }
  var queued = false;
  window.addEventListener('scroll', function () {
    if (!queued) { queued = true; requestAnimationFrame(function () { spy(); queued = false; }); }
  }, { passive: true });
  window.addEventListener('resize', spy);
  spy();
})();
