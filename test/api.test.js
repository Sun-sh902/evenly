// End-to-end acceptance tests against a real HTTP server on a random port.

import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { createApp } from '../src/app.js';

let base;
let server;
let dir;

before(async () => {
  dir = mkdtempSync(join(tmpdir(), 'evenly-test-'));
  ({ server } = createApp({ dbFile: join(dir, 'test.db'), limits: null }));
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((r) => server.close(r));
  rmSync(dir, { recursive: true, force: true });
});

async function api(method, path, body, headers = {}) {
  const res = await fetch(base + path, {
    method,
    headers: body !== undefined ? { 'Content-Type': 'application/json', ...headers } : headers,
    body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = JSON.parse(text); } catch { /* not json */ }
  return { status: res.status, json, text, headers: res.headers };
}

const byName = (g) => Object.fromEntries(g.members.map((m) => [m.name, m.id]));
const net = (g, id) => g.balances.find((b) => b.memberId === id).net;

test('health and meta', async () => {
  assert.deepEqual((await api('GET', '/api/health')).json, { ok: true });
  const meta = await api('GET', '/api/meta');
  assert.equal(meta.status, 200);
  assert.ok(meta.json.currencies.USD);
  assert.ok(meta.json.categories.includes('food'));
});

test('full trip flow: create, spend, split every way, settle to zero', async () => {
  const created = await api('POST', '/api/groups', { name: '  Lisbon   trip ', currency: 'EUR', members: ['Ana', 'Ben', 'Cleo'] });
  assert.equal(created.status, 201);
  let g = created.json;
  assert.equal(g.name, 'Lisbon trip');
  assert.equal(g.currency, 'EUR');
  assert.match(g.id, /^[\w]{12}$/);
  const m = byName(g);

  // equal split with remainder
  let r = await api('POST', `/api/groups/${g.id}/entries`, {
    title: 'Dinner', amount: '100', paidBy: m.Ana, category: 'food', date: '2026-10-01',
    split: { mode: 'equal', participants: [{ memberId: m.Ana }, { memberId: m.Ben }, { memberId: m.Cleo }] },
  });
  assert.equal(r.status, 201);
  g = r.json.group;
  assert.deepEqual(g.entries[0].shares.map((s) => s.share), [3334, 3333, 3333]);

  // exact split
  r = await api('POST', `/api/groups/${g.id}/entries`, {
    title: 'Taxi', amount: 30.5, paidBy: m.Ben, category: 'transport', date: '2026-10-02',
    split: { mode: 'exact', participants: [{ memberId: m.Ben, value: '10.50' }, { memberId: m.Cleo, value: '20' }] },
  });
  assert.equal(r.status, 201);

  // shares split
  r = await api('POST', `/api/groups/${g.id}/entries`, {
    title: 'Apartment', amount: '450.00', paidBy: m.Cleo, category: 'stay', date: '2026-10-01',
    split: { mode: 'shares', participants: [{ memberId: m.Ana, value: 1 }, { memberId: m.Ben, value: 1 }, { memberId: m.Cleo, value: 1 }] },
  });
  assert.equal(r.status, 201);

  // percent split
  r = await api('POST', `/api/groups/${g.id}/entries`, {
    title: 'Museum', amount: '40', paidBy: m.Ana, category: 'fun', date: '2026-10-03',
    split: { mode: 'percent', participants: [{ memberId: m.Ana, value: 25 }, { memberId: m.Ben, value: 75 }] },
  });
  assert.equal(r.status, 201);
  g = r.json.group;

  assert.equal(g.stats.totalSpent, 10000 + 3050 + 45000 + 4000);
  assert.equal(g.stats.expenseCount, 4);
  assert.equal(g.stats.byCategory.stay, 45000);
  assert.equal(g.display.totalSpent, '620.50');
  assert.equal(g.balances.reduce((a, b) => a + b.net, 0), 0);
  // entries are newest date first
  assert.deepEqual(g.entries.map((e) => e.date), ['2026-10-03', '2026-10-02', '2026-10-01', '2026-10-01']);

  // Ana paid 100 + 40, owes 33.34 + 150 + 10 = 193.34 -> net -53.34
  assert.equal(net(g, m.Ana), 14000 - 19334);
  assert.equal(g.stats.settled, false);
  assert.ok(g.transfers.length >= 1 && g.transfers.length <= 2);

  // record every suggested transfer as a settlement
  for (const t of g.transfers) {
    const amount = (t.amount / 100).toFixed(2);
    r = await api('POST', `/api/groups/${g.id}/entries`, { kind: 'transfer', paidBy: t.from, to: t.to, amount });
    assert.equal(r.status, 201, r.text);
    assert.equal(r.json.group.entries.find((e) => e.id === r.json.entryId).title, 'Settlement');
  }
  g = (await api('GET', `/api/groups/${g.id}`)).json;
  assert.equal(g.stats.settled, true);
  assert.deepEqual(g.transfers, []);
  assert.ok(g.balances.every((b) => b.net === 0));
  // settlements do not count as spending
  assert.equal(g.stats.totalSpent, 62050);
});

test('editing and deleting expenses recalculates balances', async () => {
  let g = (await api('POST', '/api/groups', { name: 'Flat', members: ['Dee', 'Eli'] })).json;
  const m = byName(g);
  const split = { mode: 'equal', participants: [{ memberId: m.Dee }, { memberId: m.Eli }] };
  const add = await api('POST', `/api/groups/${g.id}/entries`, { title: 'Rent', amount: '2000', paidBy: m.Dee, split });
  const eid = add.json.entryId;
  assert.equal(net(add.json.group, m.Eli), -100000);

  const upd = await api('PUT', `/api/groups/${g.id}/entries/${eid}`, { title: 'Rent (Nov)', amount: '1800', paidBy: m.Eli, split, category: 'utilities' });
  assert.equal(upd.status, 200);
  g = upd.json;
  assert.equal(g.entries[0].title, 'Rent (Nov)');
  assert.equal(g.entries[0].category, 'utilities');
  assert.equal(net(g, m.Dee), -90000);

  const del = await api('DELETE', `/api/groups/${g.id}/entries/${eid}`);
  assert.equal(del.status, 200);
  assert.equal(del.json.entries.length, 0);
  assert.ok(del.json.balances.every((b) => b.net === 0));

  assert.equal((await api('DELETE', `/api/groups/${g.id}/entries/${eid}`)).status, 404);
  assert.equal((await api('PUT', `/api/groups/${g.id}/entries/nope`, { title: 'x', amount: 1, paidBy: m.Dee, split })).status, 404);
});

test('members: add, rename, uniqueness, guarded removal', async () => {
  let g = (await api('POST', '/api/groups', { name: 'Club', members: ['Fay'] })).json;
  const fay = g.members[0].id;

  const add = await api('POST', `/api/groups/${g.id}/members`, { name: 'Gus' });
  assert.equal(add.status, 201);
  const gus = add.json.memberId;
  assert.equal(add.json.group.members.length, 2);

  assert.equal((await api('POST', `/api/groups/${g.id}/members`, { name: 'gus' })).status, 409);
  assert.equal((await api('POST', `/api/groups/${g.id}/members`, { name: '   ' })).status, 400);
  assert.equal((await api('POST', `/api/groups/${g.id}/members`, { name: 'x'.repeat(33) })).status, 400);

  const ren = await api('PATCH', `/api/groups/${g.id}/members/${gus}`, { name: 'Gustav' });
  assert.equal(ren.status, 200);
  assert.ok(ren.json.members.some((m) => m.name === 'Gustav'));
  assert.equal((await api('PATCH', `/api/groups/${g.id}/members/${gus}`, { name: 'Fay' })).status, 409);

  await api('POST', `/api/groups/${g.id}/entries`, {
    title: 'Snacks', amount: '9', paidBy: fay, split: { mode: 'equal', participants: [{ memberId: fay }, { memberId: gus }] },
  });
  const blocked = await api('DELETE', `/api/groups/${g.id}/members/${gus}`);
  assert.equal(blocked.status, 409);

  const hal = (await api('POST', `/api/groups/${g.id}/members`, { name: 'Hal' })).json.memberId;
  const removed = await api('DELETE', `/api/groups/${g.id}/members/${hal}`);
  assert.equal(removed.status, 200);
  assert.equal(removed.json.members.length, 2);
  assert.equal((await api('DELETE', `/api/groups/${g.id}/members/${hal}`)).status, 404);

  // members of another group are rejected in splits
  const other = (await api('POST', '/api/groups', { name: 'Other', members: ['Ivy'] })).json;
  const cross = await api('POST', `/api/groups/${g.id}/entries`, {
    title: 'X', amount: '5', paidBy: fay, split: { mode: 'equal', participants: [{ memberId: other.members[0].id }] },
  });
  assert.equal(cross.status, 400);
  assert.equal(cross.json.field, 'split.participants');
});

test('group validation', async () => {
  const cases = [
    [{}, 'name'],
    [{ name: 'A', members: [] }, 'members'],
    [{ name: 'A', members: 'Bob' }, 'members'],
    [{ name: 'A', currency: 'XYZ', members: ['B'] }, 'currency'],
    [{ name: 'x'.repeat(61), members: ['B'] }, 'name'],
    [{ name: 'A', members: Array.from({ length: 51 }, (_, i) => `P${i}`) }, 'members'],
    [{ name: 42, members: ['B'] }, 'name'],
  ];
  for (const [body, field] of cases) {
    const r = await api('POST', '/api/groups', body);
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.equal(r.json.field, field, JSON.stringify(body));
  }
  assert.equal((await api('POST', '/api/groups', { name: 'A', members: ['Bo', 'bo'] })).status, 409);
});

test('entry validation', async () => {
  const g = (await api('POST', '/api/groups', { name: 'V', currency: 'JPY', members: ['Jo', 'Ki'] })).json;
  const m = byName(g);
  const split = { mode: 'equal', participants: [{ memberId: m.Jo }, { memberId: m.Ki }] };
  const base = { title: 'Ramen', amount: '1500', paidBy: m.Jo, split };
  const cases = [
    [{ ...base, amount: '15.5' }, 'amount'], // JPY has no decimals
    [{ ...base, amount: '0' }, 'amount'],
    [{ ...base, amount: '-5' }, 'amount'],
    [{ ...base, amount: null }, 'amount'],
    [{ ...base, title: '' }, 'title'],
    [{ ...base, paidBy: 'ghost' }, 'paidBy'],
    [{ ...base, category: 'yachts' }, 'category'],
    [{ ...base, date: '2026-02-30' }, 'date'],
    [{ ...base, date: 'yesterday' }, 'date'],
    [{ ...base, kind: 'gift' }, 'kind'],
    [{ ...base, split: { mode: 'equal', participants: [] } }, 'split.participants'],
    [{ ...base, split: { mode: 'exact', participants: [{ memberId: m.Jo, value: '1000' }] } }, 'split.participants'],
    [{ kind: 'transfer', amount: '100', paidBy: m.Jo, to: m.Jo }, 'to'],
    [{ kind: 'transfer', amount: '100', paidBy: m.Jo }, 'to'],
  ];
  for (const [body, field] of cases) {
    const r = await api('POST', `/api/groups/${g.id}/entries`, body);
    assert.equal(r.status, 400, JSON.stringify(body));
    assert.equal(r.json.field, field, JSON.stringify(body));
  }
  const ok = await api('POST', `/api/groups/${g.id}/entries`, base);
  assert.equal(ok.status, 201);
  assert.deepEqual(ok.json.group.entries[0].shares.map((s) => s.share), [750, 750]);
  assert.equal(ok.json.group.digits, 0);
});

test('no daily limit: 200 expenses in one go', async () => {
  const g = (await api('POST', '/api/groups', { name: 'Busy', members: ['A', 'B', 'C'] })).json;
  const ids = g.members.map((m) => m.id);
  const split = { mode: 'equal', participants: ids.map((memberId) => ({ memberId })) };
  for (let i = 0; i < 200; i++) {
    const r = await api('POST', `/api/groups/${g.id}/entries`, { title: `Item ${i}`, amount: '1.00', paidBy: ids[i % 3], split });
    assert.equal(r.status, 201);
  }
  const final = (await api('GET', `/api/groups/${g.id}`)).json;
  assert.equal(final.entries.length, 200);
  assert.equal(final.balances.reduce((a, b) => a + b.net, 0), 0);
});

test('group update and currency guard', async () => {
  const g = (await api('POST', '/api/groups', { name: 'Cur', currency: 'USD', members: ['A'] })).json;
  let r = await api('PATCH', `/api/groups/${g.id}`, { name: 'Renamed', currency: 'EUR' });
  assert.equal(r.status, 200);
  assert.equal(r.json.name, 'Renamed');
  assert.equal(r.json.currency, 'EUR');
  await api('POST', `/api/groups/${g.id}/entries`, { title: 'x', amount: '1', paidBy: g.members[0].id, split: { mode: 'equal', participants: [{ memberId: g.members[0].id }] } });
  r = await api('PATCH', `/api/groups/${g.id}`, { currency: 'JPY' });
  assert.equal(r.status, 409);
  r = await api('PATCH', `/api/groups/${g.id}`, { currency: 'GBP' });
  assert.equal(r.status, 200);
});

test('delete group', async () => {
  const g = (await api('POST', '/api/groups', { name: 'Gone', members: ['A'] })).json;
  assert.equal((await api('DELETE', `/api/groups/${g.id}`)).status, 204);
  assert.equal((await api('GET', `/api/groups/${g.id}`)).status, 404);
  assert.equal((await api('DELETE', `/api/groups/${g.id}`)).status, 404);
});

test('csv export escapes formulas and quotes', async () => {
  const g = (await api('POST', '/api/groups', { name: 'CSV', members: ['Ann', 'Bo'] })).json;
  const m = byName(g);
  await api('POST', `/api/groups/${g.id}/entries`, {
    title: '=HYPERLINK("x"), dinner', amount: '10', paidBy: m.Ann, date: '2026-01-01',
    split: { mode: 'equal', participants: [{ memberId: m.Ann }, { memberId: m.Bo }] },
  });
  const r = await api('GET', `/api/groups/${g.id}/export.csv`);
  assert.equal(r.status, 200);
  assert.match(r.headers.get('content-type'), /text\/csv/);
  assert.match(r.headers.get('content-disposition'), /attachment/);
  const lines = r.text.trim().split('\n');
  assert.equal(lines[0], 'date,kind,title,category,amount,currency,paid_by,share_Ann,share_Bo');
  assert.equal(lines[1], `2026-01-01,expense,"'=HYPERLINK(""x""), dinner",general,10.00,USD,Ann,5.00,5.00`);
});

test('protocol errors', async () => {
  assert.equal((await api('GET', '/api/groups/doesnotexist')).status, 404);
  assert.equal((await api('GET', '/api/nothing')).status, 404);
  const wrong = await api('PUT', '/api/groups');
  assert.equal(wrong.status, 405);
  assert.equal(wrong.headers.get('allow'), 'POST');
  assert.equal((await api('POST', '/api/groups', '{not json')).status, 400);
  assert.equal((await api('POST', '/api/groups', '{"name":"x"}', { 'Content-Type': 'text/plain' })).status, 415);
  const huge = await api('POST', '/api/groups', JSON.stringify({ name: 'x', pad: 'y'.repeat(70000) }));
  assert.equal(huge.status, 413);
  const r = await api('GET', '/api/health');
  assert.equal(r.headers.get('x-content-type-options'), 'nosniff');
  assert.ok(r.headers.get('content-security-policy').includes("default-src 'self'"));
});

test('static frontend and traversal protection', async () => {
  const home = await api('GET', '/');
  assert.equal(home.status, 200);
  assert.match(home.headers.get('content-type'), /text\/html/);
  assert.match(home.text, /<title>Evenly/);
  const deep = await api('GET', '/g/abc123');
  assert.equal(deep.status, 200);
  assert.match(deep.text, /<title>Evenly/);
  const js = await api('GET', '/app.js');
  assert.equal(js.status, 200);
  const cached = await api('GET', '/app.js', undefined, { 'If-Modified-Since': js.headers.get('last-modified') });
  assert.equal(cached.status, 304);
  assert.equal((await api('GET', '/styles.css')).status, 200);
  assert.equal((await api('GET', '/%2e%2e/package.json')).status, 404);
  assert.equal((await api('GET', '/..%2fsrc%2fapp.js')).status, 404);
  assert.equal((await api('GET', '/missing.png')).status, 404);
  assert.equal((await api('GET', '/%E0%A4%A')).status, 400);
});

test('data persists across restarts', async () => {
  const file = join(dir, 'persist.db');
  let app = createApp({ dbFile: file });
  const g = app.store.createGroup({ name: 'Keep', members: ['A', 'B'] });
  app.store.addEntry(g.id, { title: 'T', amount: '12', paidBy: g.members[0].id, split: { mode: 'equal', participants: g.members.map((m) => ({ memberId: m.id })) } });
  app.store.close();
  app = createApp({ dbFile: file });
  const again = app.store.getGroup(g.id);
  assert.equal(again.entries.length, 1);
  assert.equal(again.balances[0].net, 600);
  app.store.close();
});

test('etag lets clients poll cheaply and revision tracks every change', async () => {
  const g = (await api('POST', '/api/groups', { name: 'Poll', members: ['A', 'B'] })).json;
  assert.equal(g.revision, 1);
  const first = await api('GET', `/api/groups/${g.id}`);
  const etag = first.headers.get('etag');
  assert.match(etag, /^W\/"/);
  assert.equal((await api('GET', `/api/groups/${g.id}`, undefined, { 'If-None-Match': etag })).status, 304);

  const added = await api('POST', `/api/groups/${g.id}/members`, { name: 'C' });
  assert.equal(added.json.group.revision, 2);
  const changed = await api('GET', `/api/groups/${g.id}`, undefined, { 'If-None-Match': etag });
  assert.equal(changed.status, 200);
  assert.notEqual(changed.headers.get('etag'), etag);

  const renamed = await api('PATCH', `/api/groups/${g.id}`, { name: 'Poll 2' });
  assert.equal(renamed.json.revision, 3);
  assert.equal((await api('GET', '/api/groups/nope', undefined, { 'If-None-Match': etag })).status, 404);
});

test('rate limiting returns 429 with Retry-After', async () => {
  const app = createApp({ limits: { writesPerMinute: 5, groupsPerHour: 2 } });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${app.server.address().port}`;
  const post = (path, body) => fetch(url + path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  try {
    assert.equal((await post('/api/groups', { name: 'a', members: ['x'] })).status, 201);
    const second = await (await post('/api/groups', { name: 'b', members: ['x'] })).json();
    const third = await post('/api/groups', { name: 'c', members: ['x'] });
    assert.equal(third.status, 429);
    assert.ok(Number(third.headers.get('retry-after')) > 0);
    // reads are never limited
    for (let i = 0; i < 20; i++) assert.equal((await fetch(`${url}/api/health`)).status, 200);
    // the per-minute write budget (5) is now nearly spent: 3 used, 2 left
    assert.equal((await post(`/api/groups/${second.id}/members`, { name: 'y' })).status, 201);
    assert.equal((await post(`/api/groups/${second.id}/members`, { name: 'z' })).status, 201);
    assert.equal((await post(`/api/groups/${second.id}/members`, { name: 'w' })).status, 429);
  } finally {
    await new Promise((r) => app.server.close(r));
  }
});

test('opens databases created before the revision column existed', () => {
  const file = join(dir, 'legacy.db');
  const legacy = new DatabaseSync(file);
  legacy.exec(`CREATE TABLE groups (id TEXT PRIMARY KEY, name TEXT NOT NULL, currency TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
    INSERT INTO groups VALUES ('legacyGroup1', 'Old', 'USD', '2025-01-01T00:00:00Z', '2025-01-01T00:00:00Z');`);
  legacy.close();
  const app = createApp({ dbFile: file });
  try {
    const g = app.store.getGroup('legacyGroup1');
    assert.equal(g.revision, 1);
    assert.equal(app.store.addMember(g.id, { name: 'New' }).group.revision, 2);
  } finally {
    app.store.close();
  }
});

test('a missing date defaults to the local calendar day, not UTC', async () => {
  const g = (await api('POST', '/api/groups', { name: 'Dates', members: ['A'] })).json;
  const r = await api('POST', `/api/groups/${g.id}/entries`, {
    title: 'No date', amount: '1', paidBy: g.members[0].id, split: { mode: 'equal', participants: [{ memberId: g.members[0].id }] },
  });
  const now = new Date();
  const local = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  assert.equal(r.json.group.entries[0].date, local);
});
