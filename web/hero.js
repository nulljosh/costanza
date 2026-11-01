// Hero wall: the Co-Stanza feed. Real poems from the network first, then a few house poems to fill the wall;
// each card writes its poem in line by line, holds, and moves on. Strangers' text, so textContent only.
(function () {
  var wall = document.getElementById('pwall'); if (!wall) return;
  var still = matchMedia('(prefers-reduced-motion: reduce)').matches;
  var n = innerWidth <= 560 ? 3 : innerWidth <= 900 ? 6 : 9;
  var HOUSE = [ // ponytail: shown only to pad the wall while the network is small; labelled "house poem", never a fake user
    ['Tuesday', 'The kettle clicks off.\nI forgot why I stood up.\nThe tea is good though.'],
    ['Inbox', 'Forty unread.\nI read one, about a sale.\nI feel accomplished.'],
    ['Lunch', 'Ate at my desk again.\nThe crumbs know my secrets.\nThey will not tell.'],
    ['Plans', 'I had a plan at nine.\nAt ten it had a plan for me.\nWe both took a nap.'],
    ['Parking', 'Circled the block twice.\nFound a spot, then the sign.\nWalked home, enlightened.'],
    ['Group chat', 'Someone said "lol".\nNo one knows what about.\nWe all agree anyway.'],
    ['Rain', 'Forecast said sunny.\nI wore the good shoes.\nThe sky had other notes.'],
    ['Gym', 'Signed up in January.\nThe card is a bookmark now.\nI read a lot.'],
    ['Leftovers', 'Third day of the soup.\nIt has opinions about me.\nI eat it anyway.'],
    ['Alarm', 'Snooze, snooze, snooze.\nA whole relationship\nwith a button.']
  ].map(function (p) { return { title: p[0], body: p[1], pen: 'House poem' }; });
  var poems = HOUSE.slice(), k = 0;
  var el = function (t, c, x) { var e = document.createElement(t); if (c) e.className = c; if (x != null) e.textContent = x; return e; };
  var wait = function (ms) { return new Promise(function (r) { setTimeout(r, still ? 0 : ms); }); };
  var cards = [];
  for (var i = 0; i < n; i++) {
    var a = wall.appendChild(el('article', 'pc')), h = a.appendChild(el('div', 'pc-hd')), c = { a: a };
    h.appendChild(el('i')); c.pen = h.appendChild(el('span'));
    c.title = a.appendChild(el('div', 'pc-title')); c.body = a.appendChild(el('div', 'pc-body')); cards.push(c);
  }
  function play(c, j) {
    var p = poems[k++ % poems.length], lines = p.body.split('\n').filter(function (l) { return l.trim(); }).slice(0, 5);
    c.pen.textContent = p.pen; c.title.textContent = p.title || 'Untitled'; c.body.textContent = '';
    return lines.reduce(function (q, l) { return q.then(function () { var s = el('span', '', l + '\n'); c.body.appendChild(s); return wait(700); }); }, wait(300))
      .then(function () { return wait(3200 + j * 180); });
  }
  var start = function () { cards.forEach(function (c, j) { if (still) { play(c, j); return; } wait(j * 260).then(function loop() { return play(c, j).then(loop); }); }); };
  // Real poems from the network, newest first; they lead the wall.
  fetch('https://api.jaybulb.com/rest/stanza_poems?select=title,body,pen_name&order=created_at.desc&limit=20')
    .then(function (r) { return r.ok ? r.json() : []; })
    .then(function (rows) { var real = (rows || []).filter(function (r) { return r.body; }).map(function (r) { return { title: r.title, body: r.body, pen: r.pen_name || 'Anonymous' }; }); poems = real.concat(HOUSE); })
    .catch(function () {}).then(start);
})();

// Hero parallax: the wall drifts at 0.45, the copy lifts at 0.2 and fades. Off under reduced motion.
(function () {
  var bg = document.querySelector('.hero-bg'), copy = document.querySelector('.hero-copy');
  if (!bg || matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  var t = 0;
  addEventListener('scroll', function () {
    if (t) return;
    t = requestAnimationFrame(function () {
      t = 0; var y = scrollY, h = innerHeight; if (y > h * 1.2) return;
      bg.style.setProperty('--py', (y * .45) + 'px');
      copy.style.transform = 'translate3d(0,' + (y * .2) + 'px,0)'; copy.style.opacity = Math.max(0, 1 - y / (h * .7));
    });
  }, { passive: true });
})();
