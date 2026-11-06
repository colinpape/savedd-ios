import { verifyEvent } from 'nostr-tools/pure';

// Same trust root and event namespaces as feature/partner-program's
// src/lib/saveddProtocol.ts, usePartners.ts, and partners.ts.
export const OWNER = 'c45041618951bb6012ac23f5cdf3d740465f2d640be841fd9bb1d0733370cd3c';
const RELAYS = [
  'wss://savedd-sip-relay.savedd-sip-relay.workers.dev/',
  'wss://relay.ditto.pub/',
  'wss://relay-na1.metanomalist.com/',
  'wss://relay.primal.net/',
  'wss://test-sip-relay.sip-01test.workers.dev/',
  'wss://sip-relay-2.sip-booster-relay.workers.dev/',
  'wss://sip-relay-3.uncaged-sip.workers.dev/',
  'wss://sip-relay-4.sip-relay-4.workers.dev/',
  'wss://jskitty.cat/nostr',
  'wss://search.nos.today/',
  'wss://relay.nostr.band/',
  'wss://relay.noswhere.com/',
  'wss://relay.pocketnostr.com/',
  'wss://relay.damus.io/',
];
const ADMIN = 'savedd:admin-roles';
const LEGACY_ADMIN = 'presearchstr:admin-roles';
const DIRECTORY = 'savedd:partners';
const HEX = /^[0-9a-f]{64}$/;
const RESERVED = new Set(('about admin api assets bookmarks build community dashboard docs explore goodbye heaven index instances network partners policy protocol remoteloginsuccess settings www').split(' '));
const dTag = event => event.tags.find(tag => tag[0] === 'd')?.[1];
const latest = events => events.sort((a, b) => b.created_at - a.created_at || a.id.localeCompare(b.id))[0];

function authentic(event) {
  try {
    return event.kind === 30078 && event.created_at <= Math.floor(Date.now() / 1000) + 300
      && verifyEvent(event);
  } catch { return false; }
}

export function trustedAuthors(events, owner = OWNER) {
  const signed = events.filter(e => e.pubkey === owner && authentic(e));
  const canonical = latest(signed.filter(e => dTag(e) === ADMIN));
  const legacy = latest(signed.filter(e => dTag(e) === LEGACY_ADMIN));
  function read(event) {
    try { const list = JSON.parse(event.content); return Array.isArray(list) ? list.filter(k => typeof k === 'string' && HEX.test(k)) : null; }
    catch { return null; }
  }
  return new Set([owner, ...(read(canonical) ?? read(legacy) ?? [])]);
}

export function resolveDirectory(events, trusted) {
  const signed = events.filter(e => trusted.has(e.pubkey) && authentic(e) && dTag(e) === DIRECTORY);
  const event = latest(signed);
  if (!event) return [];
  let rows;
  try { rows = JSON.parse(event.content).partners; } catch { return []; }
  if (!Array.isArray(rows)) return [];
  const keys = new Set(), slugs = new Set(), partners = [];
  for (const row of rows) {
    if (!row || typeof row !== 'object') continue;
    const slug = typeof row.slug === 'string' ? row.slug.trim().toLowerCase().replace(/^\/+|\/+$/g, '') : '';
    const pubkey = typeof row.pubkey === 'string' ? row.pubkey.toLowerCase() : '';
    const name = typeof row.name === 'string' ? row.name.trim().replace(/\s+/g, ' ').slice(0, 60) : '';
    if (slug.length < 2 || slug.length > 32 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)
      || RESERVED.has(slug) || !HEX.test(pubkey) || !name || slugs.has(slug) || keys.has(pubkey)) continue;
    slugs.add(slug); keys.add(pubkey); partners.push({ slug, pubkey, name });
    if (partners.length === 200) break;
  }
  return partners;
}

function queryRelay(url, filter) {
  return new Promise(resolve => {
    let socket, timer, finished = false, received = 0;
    const events = [], sub = 'savedd-ios-directory';
    const finish = complete => {
      if (finished) return;
      finished = true; clearTimeout(timer);
      try { if (socket?.readyState === 1) socket.send(JSON.stringify(['CLOSE', sub])); socket?.close(); } catch { /* closed */ }
      resolve({ events, complete });
    };
    timer = setTimeout(() => finish(false), 5000);
    try {
      socket = new WebSocket(url);
      socket.onopen = () => socket.send(JSON.stringify(['REQ', sub, filter]));
      socket.onerror = () => finish(false);
      socket.onclose = () => finish(false);
      socket.onmessage = ({ data }) => {
        if (typeof data !== 'string' || data.length > 1_000_000 || ++received > 512) { finish(false); return; }
        try {
          const message = JSON.parse(data);
          if (message[1] !== sub) return;
          if (message[0] === 'EOSE') { finish(true); return; }
          const event = message[2];
          if (message[0] === 'EVENT' && event?.kind === 30078 && filter.authors.includes(event.pubkey)
              && filter['#d'].includes(dTag(event)) && authentic(event)) events.push(event);
        } catch { /* ignore malformed frames */ }
      };
    } catch { finish(false); }
  });
}

async function query(filter) {
  const results = await Promise.all(RELAYS.map(url => queryRelay(url, filter)));
  if (!results.some(r => r.complete)) throw new Error('Directory unavailable');
  return results.flatMap(r => r.events);
}

export async function loadDirectory() {
  const roles = await query({ kinds: [30078], authors: [OWNER], '#d': [ADMIN, LEGACY_ADMIN], limit: 8 });
  const trusted = trustedAuthors(roles);
  const events = await query({ kinds: [30078], authors: [...trusted], '#d': [DIRECTORY], limit: 20 });
  return resolveDirectory(events, trusted);
}

if (globalThis.webkit?.messageHandlers?.partnerDirectory) {
  loadDirectory().then(partners => {
    globalThis.webkit.messageHandlers.partnerDirectory.postMessage({ status: 'ready', partners });
  }).catch(() => {
    globalThis.webkit.messageHandlers.partnerDirectory.postMessage({ status: 'error' });
  });
}
