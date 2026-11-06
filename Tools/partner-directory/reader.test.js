import test from 'node:test';
import assert from 'node:assert/strict';
import { finalizeEvent, generateSecretKey, getPublicKey } from 'nostr-tools/pure';
import { trustedAuthors, resolveDirectory } from './reader.js';

const ownerKey = generateSecretKey(), owner = getPublicKey(ownerKey);
const adminKey = generateSecretKey(), admin = getPublicKey(adminKey);
const attackerKey = generateSecretKey(), attacker = getPublicKey(attackerKey);
const now = Math.floor(Date.now() / 1000);
function event(key, d, content, offset = 0) {
  return finalizeEvent({ kind: 30078, created_at: now + offset, tags: [['d', d]], content: JSON.stringify(content) }, key);
}
const partner = { slug: 'a-creator', pubkey: getPublicKey(generateSecretKey()), name: 'A Creator' };

test('owner-approved admin can publish the partner directory', () => {
  const authors = trustedAuthors([event(ownerKey, 'savedd:admin-roles', [admin])], owner);
  assert.deepEqual(resolveDirectory([event(adminKey, 'savedd:partners', { partners: [partner] })], authors), [partner]);
});

test('spoofed roles, untrusted directories, and modified signatures cannot redirect referrals', () => {
  const spoof = event(attackerKey, 'savedd:admin-roles', [attacker]);
  const authors = trustedAuthors([spoof], owner);
  const tampered = JSON.parse(JSON.stringify(event(ownerKey, 'savedd:partners', { partners: [partner] })));
  tampered.content = JSON.stringify({ partners: [{ ...partner, pubkey: attacker }] });
  assert.deepEqual(resolveDirectory([tampered, event(attackerKey, 'savedd:partners', { partners: [partner] })], authors), []);
});

test('canonical admin removal wins over legacy roles, and newest directory can remove partners', () => {
  const roles = [event(ownerKey, 'presearchstr:admin-roles', [admin]), event(ownerKey, 'savedd:admin-roles', [], -1)];
  assert.equal(trustedAuthors(roles, owner).has(admin), false);
  const old = event(ownerKey, 'savedd:partners', { partners: [partner] }, -10);
  const removed = event(ownerKey, 'savedd:partners', { partners: [] });
  assert.deepEqual(resolveDirectory([old, removed], new Set([owner])), []);
});

test('malformed, duplicate, and reserved entries are rejected; names are bounded', () => {
  const rows = [partner, partner, { ...partner, slug: 'admin', pubkey: attacker }, null,
    { slug: 'other', pubkey: attacker, name: '  Another   Creator  ' }, { slug: 'bad code', name: 'Bad', pubkey: owner }];
  assert.deepEqual(resolveDirectory([event(ownerKey, 'savedd:partners', { partners: rows })], new Set([owner])),
    [partner, { slug: 'other', pubkey: attacker, name: 'Another Creator' }]);
});
