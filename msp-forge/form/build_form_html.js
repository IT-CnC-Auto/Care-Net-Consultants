// CNC MSP FORGE | FRM-DSL-01 v2.0.0 | HTML onboarding form generator
// Reads fields.json (the single source of truth shared with the Supabase
// intake schema and the document placeholder map) and emits a self contained
// index.html. Field names in the form ARE the variable names in Supabase and
// in the document templates: company_registered_name in the form becomes
// msp_client.registered_name and the {company_registered_name} placeholder in
// the generated pack.

const fs = require('fs');
const path = require('path');

const spec = JSON.parse(fs.readFileSync(path.join(__dirname, 'fields.json'), 'utf8'));

function esc(s) {
  return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function inputFor(name, f) {
  const req = f.required ? ' data-required="1"' : '';
  switch (f.type) {
    case 'textarea':
      return `<textarea name="${name}" rows="3"${req}></textarea>`;
    case 'checkbox':
      return `<label class="check"><input type="checkbox" name="${name}" value="true"${req}><span></span></label>`;
    case 'date':
      return `<input type="date" name="${name}"${req}>`;
    case 'number':
      return `<input type="number" name="${name}" min="0"${req}>`;
    case 'file':
      return `<input type="file" name="${name}" data-file="1"${req}>`;
    case 'signature':
      return `<input type="text" name="${name}" placeholder="Type your full name as signature"${req}>`;
    default:
      return `<input type="text" name="${name}"${req}>`;
  }
}

function fieldRow(name, f) {
  const reqMark = f.required ? ' <em>(required)</em>' : '';
  return `<div class="field"><label for="${name}">${esc(f.label)}${reqMark}</label>${inputFor(name, f)}</div>`;
}

let sectionsHtml = '';
for (const s of spec.sections) {
  let inner = '';
  if (s.intro) inner += `<p class="intro">${esc(s.intro)}</p>`;
  for (const f of s.fields || []) inner += fieldRow(f.name, f);
  for (const rep of s.repeats || []) {
    inner += `<h3>${esc(rep.title)}</h3><div class="repeat" data-prefix="${rep.prefix}" data-max="${rep.count}">`;
    // First block rendered; further blocks cloned by script up to data-max.
    inner += `<fieldset class="repeat-block" data-index="1"><legend>${esc(rep.prefix)} 1</legend>`;
    for (const f of rep.fields) {
      inner += fieldRow(`${rep.prefix}_1_${f.name}`, { ...f, required: false });
    }
    inner += `</fieldset></div><button type="button" class="add" data-target="${rep.prefix}">Add another</button>`;
  }
  sectionsHtml += `<section><h2>${s.no}. ${esc(s.title)}</h2>${inner}</section>`;
}

const html = `<!doctype html>
<html lang="en-ZA">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CNC Medical Surveillance Onboarding</title>
<style>
  :root { --red: #ED1B24; --charcoal: #1A1A1A; }
  * { box-sizing: border-box; }
  body { font-family: Arial, Helvetica, sans-serif; color: var(--charcoal); margin: 0; background: #f7f7f7; }
  header { background: var(--charcoal); color: #fff; padding: 28px 16px; text-align: center; }
  header .brand { color: var(--red); font-weight: bold; letter-spacing: 1px; font-size: 22px; }
  header .tagline { font-size: 13px; opacity: .85; margin-top: 6px; font-style: italic; }
  main { max-width: 860px; margin: 0 auto; padding: 24px 16px 80px; }
  section { background: #fff; border-radius: 8px; padding: 20px 24px; margin: 18px 0; box-shadow: 0 1px 3px rgba(0,0,0,.08); }
  h2 { color: var(--red); font-size: 17px; border-bottom: 2px solid var(--red); padding-bottom: 8px; }
  h3 { font-size: 14px; margin: 18px 0 8px; }
  .intro { font-size: 13px; color: #444; font-style: italic; }
  .field { margin: 12px 0; }
  .field label { display: block; font-size: 13px; margin-bottom: 4px; font-weight: bold; }
  .field label em { font-weight: normal; color: var(--red); font-style: normal; font-size: 12px; }
  input[type=text], input[type=number], input[type=date], textarea {
    width: 100%; padding: 9px 10px; border: 1px solid #ccc; border-radius: 5px; font-family: inherit; font-size: 14px; }
  input:focus, textarea:focus { outline: 2px solid var(--red); border-color: var(--red); }
  fieldset.repeat-block { border: 1px solid #ddd; border-radius: 6px; margin: 10px 0; padding: 8px 14px; }
  legend { font-size: 12px; color: #666; text-transform: capitalize; }
  button.add { background: #fff; color: var(--red); border: 1px solid var(--red); border-radius: 5px; padding: 7px 14px; cursor: pointer; font-size: 13px; }
  button.add:hover { background: var(--red); color: #fff; }
  .submit-bar { text-align: center; margin-top: 28px; }
  button.submit { background: var(--red); color: #fff; border: none; border-radius: 6px; padding: 14px 44px; font-size: 16px; font-weight: bold; cursor: pointer; }
  button.submit:disabled { opacity: .5; cursor: wait; }
  .notice { padding: 14px 16px; border-radius: 6px; margin: 16px 0; font-size: 14px; display: none; }
  .notice.ok { background: #e8f7ec; border: 1px solid #2e8b57; display: block; }
  .notice.err { background: #fdeaea; border: 1px solid var(--red); display: block; }
  .hp { position: absolute; left: -9999px; }
  footer { text-align: center; font-size: 12px; color: #777; padding: 24px; }
</style>
</head>
<body>
<header>
  <div class="brand">CARE NET CONSULTANTS (PTY) LTD</div>
  <div>Medical Surveillance Plan: Client Onboarding</div>
  <div class="tagline">Your Partner in Workplace Health</div>
</header>
<main>
  <p>This form gathers the information Care Net Consultants (Pty) Ltd requires to design an accurate, client specific Medical Surveillance Plan for your organisation. Care Net designs your Plan based entirely on the information you provide here and does not independently conduct your workplace risk assessment. Do not enter any employee identity number, any name linked to a medical condition, or other personal information about an identifiable individual anywhere in this form.</p>
  <form id="intake" novalidate>
    <input class="hp" type="text" name="website" tabindex="-1" autocomplete="off">
    ${sectionsHtml}
    <div id="notice" class="notice"></div>
    <div class="submit-bar"><button class="submit" type="submit">Submit onboarding form</button></div>
  </form>
</main>
<footer>Proudly prepared by the Care Net Consultants Team. Your Partner in Workplace Health.</footer>
<script>
(function () {
  var repeatSpecs = ${JSON.stringify(
    spec.sections.flatMap(s => (s.repeats || []).map(r => ({ prefix: r.prefix, max: r.count, fields: r.fields.map(f => ({ name: f.name, label: f.label, type: f.type })) })))
  )};

  function fieldHtml(prefix, i, f) {
    var name = prefix + '_' + i + '_' + f.name;
    var input;
    if (f.type === 'textarea') input = '<textarea name="' + name + '" rows="3"></textarea>';
    else if (f.type === 'date') input = '<input type="date" name="' + name + '">';
    else if (f.type === 'number') input = '<input type="number" name="' + name + '" min="0">';
    else input = '<input type="text" name="' + name + '">';
    return '<div class="field"><label>' + f.label + '</label>' + input + '</div>';
  }

  document.querySelectorAll('button.add').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var prefix = btn.getAttribute('data-target');
      var spec = repeatSpecs.find(function (r) { return r.prefix === prefix; });
      var wrap = document.querySelector('.repeat[data-prefix="' + prefix + '"]');
      var n = wrap.querySelectorAll('.repeat-block').length + 1;
      if (n > spec.max) { alert('Maximum of ' + spec.max + ' entries. Please describe further items in the additional detail box.'); return; }
      var fs = document.createElement('fieldset');
      fs.className = 'repeat-block';
      fs.innerHTML = '<legend>' + prefix + ' ' + n + '</legend>' + spec.fields.map(function (f) { return fieldHtml(prefix, n, f); }).join('');
      wrap.appendChild(fs);
    });
  });

  var form = document.getElementById('intake');
  var notice = document.getElementById('notice');
  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    notice.className = 'notice';
    var data = {};
    var missing = [];
    form.querySelectorAll('input, textarea').forEach(function (el) {
      if (!el.name || el.name === 'website') return;
      if (el.type === 'checkbox') { data[el.name] = el.checked ? 'true' : ''; return; }
      if (el.type === 'file') { return; }
      data[el.name] = el.value.trim();
      if (el.getAttribute('data-required') && !el.value.trim()) missing.push(el.name);
    });
    if (form.querySelector('.hp input, input.hp') && form.querySelector('input[name=website]').value) return;
    if (missing.length) {
      notice.className = 'notice err';
      notice.textContent = 'Please complete the required fields: ' + missing.join(', ');
      window.scrollTo({ top: notice.offsetTop - 80, behavior: 'smooth' });
      return;
    }
    if (!data.consent_processing) {
      notice.className = 'notice err';
      notice.textContent = 'The POPIA processing consent in Section 10 is required before this form can be submitted.';
      return;
    }
    data.docuseal_submission_id = 'WEB-' + Date.now().toString(36).toUpperCase();
    var btn = form.querySelector('button.submit');
    btn.disabled = true;
    fetch('/api/intake', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    }).then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
      .then(function (res) {
        btn.disabled = false;
        if (res.ok && res.j.reference) {
          notice.className = 'notice ok';
          notice.textContent = 'Thank you. Your submission has been received under reference ' + res.j.reference +
            (res.j.status === 'triage' ? '. A Care Net consultant will contact you to confirm some details before your Plan is drafted.' : '. Your Medical Surveillance Plan drafting process has begun.');
          form.querySelectorAll('input, textarea, button').forEach(function (el) { el.disabled = true; });
        } else if (res.ok && res.j.status === 'rejected') {
          notice.className = 'notice err';
          notice.textContent = 'Your submission could not be accepted: ' + (res.j.reason || 'it appears to contain personal information that must not be entered here, or required consent is missing. Please review and resubmit.');
        } else {
          notice.className = 'notice err';
          notice.textContent = 'A processing error occurred. Please try again, or contact your Care Net consultant.';
        }
        window.scrollTo({ top: notice.offsetTop - 80, behavior: 'smooth' });
      })
      .catch(function () {
        btn.disabled = false;
        notice.className = 'notice err';
        notice.textContent = 'A network error occurred. Please try again.';
      });
  });
})();
</script>
</body>
</html>
`;

fs.writeFileSync(path.join(__dirname, 'index.html'), html);
console.log(`index.html written (${html.length} bytes)`);
