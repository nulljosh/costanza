// Shared by app.html and test.mjs. Pure functions only.
export const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// A poem is text. Blank lines split stanzas, single newlines keep line breaks.
export const renderBody = (body) =>
  body.trim().split(/\n\s*\n/).map((st) => `<p>${esc(st).split('\n').join('<br>')}</p>`).join('');

export const when = (iso, now = Date.now()) => {
  const d = Math.floor((now - new Date(iso)) / 86400000);
  return d < 1 ? 'today' : d === 1 ? 'yesterday' : d < 30 ? `${d} days ago` : new Date(iso).toLocaleDateString('en', { month: 'short', day: 'numeric', year: 'numeric' });
};

export const slug = (id) => `#/p/${id}`;
