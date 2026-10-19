import test from 'node:test';
import assert from 'node:assert/strict';
import { esc, renderBody, when } from './web/poem.js';

test('escapes html', () => assert.equal(esc('<b>&"'), '&lt;b&gt;&amp;&quot;'));
test('stanzas and line breaks', () => {
  assert.equal(renderBody('a\nb\n\nc'), '<p>a<br>b</p><p>c</p>');
  assert.equal(renderBody('  x  \n\n\n  y '), '<p>x  </p><p>  y</p>');
});
test('relative dates', () => {
  const now = Date.UTC(2026, 8, 9);
  assert.equal(when(new Date(now - 3600e3).toISOString(), now), 'today');
  assert.equal(when(new Date(now - 90000e3).toISOString(), now), 'yesterday');
  assert.equal(when(new Date(now - 5 * 86400e3).toISOString(), now), '5 days ago');
});
