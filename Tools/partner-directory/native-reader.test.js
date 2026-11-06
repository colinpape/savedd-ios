import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { webcrypto } from 'node:crypto';
import { finalizeEvent, generateSecretKey, getPublicKey } from 'nostr-tools/pure';

test('native verification bundle initializes without browser networking or timers', () => {
  const sandbox = { TextEncoder, TextDecoder, Uint8Array, ArrayBuffer, DataView, crypto: webcrypto,
    WebSocket() { throw new Error('Native networking must be used'); },
    setTimeout() { throw new Error('Background page timers must not be used'); }
  };
  vm.runInNewContext(readFileSync(new URL('../../Savedd/PartnerDirectory.js', import.meta.url), 'utf8'), sandbox);
  assert.equal(typeof sandbox.SaveddPartnerReader.trustedAuthors, 'function');
  assert.equal(typeof sandbox.SaveddPartnerReader.resolveDirectory, 'function');

  const key = generateSecretKey(), pubkey = getPublicKey(key);
  const partner = { slug: 'example', pubkey, name: 'Example Partner' };
  const event = finalizeEvent({ kind: 30078, created_at: Math.floor(Date.now() / 1000),
    tags: [['d', 'savedd:partners']], content: JSON.stringify({ partners: [partner] }) }, key);
  sandbox.eventJSON = JSON.stringify(event);
  sandbox.author = pubkey;
  const result = vm.runInContext('SaveddPartnerReader.resolveDirectory([JSON.parse(eventJSON)], [author])', sandbox);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), [partner]);
  assert.deepEqual(JSON.parse(JSON.stringify(vm.runInContext('SaveddPartnerReader.resolveDirectory([JSON.parse(eventJSON)], [])', sandbox))), []);
});
