/* Shared first-run onboarding. Copy this file verbatim into any app that needs it.
   Usage, after the app knows its auth state:

     Onboarding.start({
       key: 'sparkjar',                 // localStorage namespace, one per app
       signedIn: isLoggedIn(),          // omit to auto-detect a stored session
       slides: [{ title, body, art }],  // art is an inline SVG string, optional
       onDone: () => openSignup()       // optional, fires on finish (not skip)
     });

   Shows once per browser. Set localStorage['<key>_onboarded'] = '' to replay. */
(function (global) {
  'use strict';

  var CSS = [
    '.ob-veil{position:fixed;inset:0;z-index:9999;display:flex;align-items:center;justify-content:center;',
    'background:var(--bg,#111);font-family:var(--font,-apple-system,BlinkMacSystemFont,system-ui,"Helvetica Neue",Helvetica,Arial,sans-serif)}',
    '.ob-card{width:100%;max-width:420px;padding:32px 24px calc(24px + env(safe-area-inset-bottom));display:flex;flex-direction:column;gap:24px;text-align:center}',
    '.ob-art{height:180px;display:flex;align-items:center;justify-content:center;color:var(--accent,#3B82F6)}',
    '.ob-art svg{max-width:100%;max-height:100%}',
    '.ob-h{margin:0;font-size:26px;line-height:1.2;font-weight:700;color:var(--text,#e8e8f0)}',
    '.ob-p{margin:0;font-size:16px;line-height:1.5;color:var(--text2,rgba(232,232,240,.6))}',
    '.ob-slide{display:flex;flex-direction:column;gap:16px;animation:ob-in .28s cubic-bezier(.4,0,.2,1)}',
    '@keyframes ob-in{from{opacity:0;transform:translateX(16px)}to{opacity:1;transform:none}}',
    '.ob-dots{display:flex;gap:8px;justify-content:center}',
    '.ob-dot{width:7px;height:7px;border-radius:999px;background:var(--text3,rgba(232,232,240,.35));transition:background .2s,width .2s}',
    '.ob-dot[data-on]{width:22px;background:var(--accent,#3B82F6)}',
    '.ob-row{display:flex;flex-direction:column;gap:10px}',
    '.ob-next{appearance:none;border:0;border-radius:999px;padding:14px 20px;font:inherit;font-size:16px;font-weight:600;',
    'background:var(--accent,#3B82F6);color:#fff;cursor:pointer}',
    '.ob-skip{appearance:none;border:0;background:none;font:inherit;font-size:15px;padding:10px;color:var(--text2,rgba(232,232,240,.6));cursor:pointer}',
    '.ob-next:focus-visible,.ob-skip:focus-visible{outline:2px solid var(--accent,#3B82F6);outline-offset:3px}',
    '@media (prefers-reduced-motion:reduce){.ob-slide{animation:none}}'
  ].join('');

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  /* When the host app does not pass signedIn, look for a session left behind by the
     usual suspects: an explicit key list, a Supabase auth token, or a *_token entry. */
  function detectSignedIn(authKeys) {
    try {
      var i, k;
      if (authKeys) {
        for (i = 0; i < authKeys.length; i++) if (localStorage.getItem(authKeys[i])) return true;
        return false;
      }
      for (i = 0; i < localStorage.length; i++) {
        k = localStorage.key(i);
        if (/^sb-.*-auth-token$/.test(k) || /(^|_)token$/.test(k)) {
          if (localStorage.getItem(k)) return true;
        }
      }
    } catch (e) { return true; } // no storage means no way to remember; stay out of the way
    return false;
  }

  function start(opts) {
    var slides = (opts && opts.slides) || [];
    var key = (opts && opts.key) || 'app';
    var flag = key + '_onboarded';
    var signedIn = opts.signedIn;
    if (signedIn === undefined) signedIn = detectSignedIn(opts.authKeys);
    if (!slides.length || signedIn) return false;
    try { if (localStorage.getItem(flag)) return false; } catch (e) { return false; }

    var i = 0;
    var style = el('style');
    style.textContent = CSS;
    document.head.appendChild(style);

    var veil = el('div', 'ob-veil');
    veil.setAttribute('role', 'dialog');
    veil.setAttribute('aria-modal', 'true');
    veil.setAttribute('aria-label', 'Welcome');
    var card = el('div', 'ob-card');
    var slide = el('div', 'ob-slide');
    var dots = el('div', 'ob-dots');
    var next = el('button', 'ob-next');
    var skip = el('button', 'ob-skip', 'Skip');
    next.type = skip.type = 'button';

    card.appendChild(slide);
    card.appendChild(dots);
    var row = el('div', 'ob-row');
    row.appendChild(next);
    row.appendChild(skip);
    card.appendChild(row);
    veil.appendChild(card);

    function close(finished) {
      try { localStorage.setItem(flag, '1'); } catch (e) {}
      veil.remove();
      style.remove();
      document.removeEventListener('keydown', onKey);
      if (finished && opts.onDone) opts.onDone();
    }

    function onKey(e) {
      if (e.key === 'Escape') close(false);
      else if (e.key === 'ArrowRight' || e.key === 'Enter') next.click();
      else if (e.key === 'ArrowLeft' && i > 0) { i -= 2; next.click(); }
    }

    function render() {
      var s = slides[i];
      slide.replaceChildren();
      if (s.art) {
        var art = el('div', 'ob-art');
        art.innerHTML = s.art; // trusted: slides are authored in the app's own source
        slide.appendChild(art);
      }
      slide.appendChild(el('h2', 'ob-h', s.title));
      slide.appendChild(el('p', 'ob-p', s.body));
      dots.replaceChildren();
      for (var d = 0; d < slides.length; d++) {
        var dot = el('span', 'ob-dot');
        if (d === i) dot.setAttribute('data-on', '');
        dots.appendChild(dot);
      }
      var last = i === slides.length - 1;
      next.textContent = last ? (opts.finishLabel || 'Get started') : 'Next';
      skip.style.visibility = last ? 'hidden' : 'visible';
    }

    next.addEventListener('click', function () {
      if (i >= slides.length - 1) return close(true);
      i++;
      render();
    });
    skip.addEventListener('click', function () { close(false); });
    document.addEventListener('keydown', onKey);

    render();
    document.body.appendChild(veil);
    next.focus();
    return true;
  }

  global.Onboarding = { start: start };
})(window);
