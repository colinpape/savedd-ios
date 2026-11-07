import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const swift = readFileSync(new URL('../../Savedd/OnboardingStore.swift', import.meta.url), 'utf8');
const template = swift.split('"""')[1];
const settings = { version: 1, theme: 'light', privacyMode: true, languageFilter: ['fr'], referralCode: 'a-creator' };
const script = template.replace('\\(webPayload)', JSON.stringify(settings));
function context(origin = 'https://savedd.com', frame = false) {
  const values = new Map();
  const window = {}; window.top = frame ? {} : window;
  return { values, window, location: { origin }, localStorage: {
    getItem: k => values.get(k) ?? null, setItem: (k, v) => values.set(k, v)
  } };
}
test('website receives theme, result language and privacy before startup, preserving unrelated settings', () => {
  const ctx = context();
  ctx.values.set('savedd:app-config', JSON.stringify({ theme: 'dark', autoIndex: false, mapsProvider: 'osm' }));
  ctx.values.set('savedd:referrer', 'existing-first-touch');
  vm.runInNewContext(script, ctx);
  assert.deepEqual(JSON.parse(ctx.values.get('savedd:app-config')), {
    theme: 'light', autoIndex: false, mapsProvider: 'osm', languageFilter: ['fr'], privacyMode: true
  });
  assert.equal(ctx.values.get('savedd:referrer'), 'existing-first-touch');
  assert.equal(JSON.parse(ctx.values.get('savedd:ios-onboarding')).referralCode, 'a-creator');
});
test('external websites and subframes never receive onboarding data', () => {
  for (const ctx of [context('https://example.com'), context('https://savedd.com.evil.test'), context('http://savedd.com'), context('https://savedd.com', true)]) {
    vm.runInNewContext(script, ctx); assert.equal(ctx.values.size, 0);
  }
});
test('page navigation does not overwrite subsequent website preference changes', () => {
  const ctx = context(); vm.runInNewContext(script, ctx);
  ctx.values.set('savedd:app-config', '{"theme":"dark"}');
  vm.runInNewContext(script, ctx);
  assert.equal(ctx.values.get('savedd:app-config'), '{"theme":"dark"}');
});
test('redirected www site receives the saved dark or light choice and other preferences', () => {
  for (const theme of ['dark', 'light']) {
    const ctx = context('https://www.savedd.com');
    ctx.values.set('savedd:app-config', JSON.stringify({ theme: theme === 'dark' ? 'light' : 'dark', mapsProvider: 'osm' }));
    const redirectedScript = template.replace('\\(webPayload)', JSON.stringify({ ...settings, theme }));
    vm.runInNewContext(redirectedScript, ctx);
    const saved = JSON.parse(ctx.values.get('savedd:app-config'));
    assert.equal(saved.theme, theme);
    assert.equal(saved.privacyMode, true);
    assert.deepEqual(saved.languageFilter, ['fr']);
    assert.equal(saved.mapsProvider, 'osm');
  }
});
test('www lookalikes, non-HTTPS origins, alternate ports and www subframes receive nothing', () => {
  for (const ctx of [context('https://www.savedd.com.evil.test'), context('http://www.savedd.com'),
    context('https://www.savedd.com:8443'), context('https://www.savedd.com', true)]) {
    vm.runInNewContext(script, ctx);
    assert.equal(ctx.values.size, 0);
  }
});
