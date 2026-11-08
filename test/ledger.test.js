import { test } from 'node:test';
import assert from 'node:assert/strict';
import { toMinor, fromMinor, allocate } from '../src/money.js';
import { resolveSplit, computeBalances, suggestTransfers, ValidationError } from '../src/ledger.js';

test('toMinor parses decimals safely', () => {
  assert.equal(toMinor('12.34'), 1234);
  assert.equal(toMinor('12.3'), 1230);
  assert.equal(toMinor('12'), 1200);
  assert.equal(toMinor('1,234.50'), 123450);
  assert.equal(toMinor(0.1 + 0.2), 30);
  assert.equal(toMinor(19.99), 1999);
  assert.equal(toMinor('500', 0), 500);
  assert.equal(toMinor('5.5', 0), null);
  assert.equal(toMinor('12.345'), null);
  assert.equal(toMinor('-3'), null);
  assert.equal(toMinor('abc'), null);
  assert.equal(toMinor(''), null);
  assert.equal(toMinor(NaN), null);
  assert.equal(toMinor(Infinity), null);
  assert.equal(toMinor({}), null);
});

test('fromMinor formats', () => {
  assert.equal(fromMinor(1234), '12.34');
  assert.equal(fromMinor(5), '0.05');
  assert.equal(fromMinor(-1050), '-10.50');
  assert.equal(fromMinor(700, 0), '700');
});

test('allocate always sums to the total', () => {
  assert.deepEqual(allocate(100, [1, 1, 1]), [34, 33, 33]);
  assert.deepEqual(allocate(1000, [1, 2, 1]), [250, 500, 250]);
  assert.deepEqual(allocate(1, [1, 1]), [1, 0]);
  assert.deepEqual(allocate(0, [1, 2]), [0, 0]);
  // extreme weight ratios and huge totals still sum exactly
  for (const [total, w] of [[99999999999999, [1e6, 1e-9, 3]], [1e14 - 1, [999999.99, 0.01, 7.77]], [7, [1e-12, 1e-12]]]) {
    assert.equal(allocate(total, w).reduce((a, b) => a + b, 0), total);
  }
  for (let i = 0; i < 500; i++) {
    const total = Math.floor(Math.random() * 1e7);
    const weights = Array.from({ length: 1 + Math.floor(Math.random() * 9) }, () => Math.random() * 10 + 0.01);
    const parts = allocate(total, weights);
    assert.equal(parts.reduce((a, b) => a + b, 0), total);
    assert.ok(parts.every((p) => p >= 0 && Number.isInteger(p)));
  }
});

test('resolveSplit modes', () => {
  const ps = [{ memberId: 'a' }, { memberId: 'b' }, { memberId: 'c' }];
  assert.deepEqual(resolveSplit(1000, { mode: 'equal', participants: ps }, 2).map((s) => s.share), [334, 333, 333]);
  assert.deepEqual(
    resolveSplit(1000, { mode: 'exact', participants: [{ memberId: 'a', value: '2.50' }, { memberId: 'b', value: '7.50' }] }, 2).map((s) => s.share),
    [250, 750],
  );
  assert.deepEqual(
    resolveSplit(900, { mode: 'shares', participants: [{ memberId: 'a', value: 2 }, { memberId: 'b', value: 1 }] }, 2).map((s) => s.share),
    [600, 300],
  );
  assert.deepEqual(
    resolveSplit(1000, { mode: 'percent', participants: [{ memberId: 'a', value: 70 }, { memberId: 'b', value: 30 }] }, 2).map((s) => s.share),
    [700, 300],
  );
});

test('resolveSplit rejects bad input', () => {
  const bad = [
    null,
    { mode: 'magic', participants: [{ memberId: 'a' }] },
    { mode: 'equal', participants: [] },
    { mode: 'equal', participants: [{ memberId: 'a' }, { memberId: 'a' }] },
    { mode: 'exact', participants: [{ memberId: 'a', value: '1.00' }] },
    { mode: 'exact', participants: [{ memberId: 'a', value: 'x' }] },
    { mode: 'shares', participants: [{ memberId: 'a', value: 0 }] },
    { mode: 'shares', participants: [{ memberId: 'a', value: -1 }] },
    { mode: 'percent', participants: [{ memberId: 'a', value: 50 }] },
  ];
  for (const split of bad) assert.throws(() => resolveSplit(1000, split, 2), ValidationError, JSON.stringify(split));
});

test('balances sum to zero and transfers settle everyone (randomised)', () => {
  for (let round = 0; round < 300; round++) {
    const n = 2 + Math.floor(Math.random() * 8);
    const members = Array.from({ length: n }, (_, i) => ({ id: `m${i}` }));
    const entries = [];
    for (let k = 0; k < 1 + Math.floor(Math.random() * 20); k++) {
      const amount = 1 + Math.floor(Math.random() * 100000);
      const parts = members.filter(() => Math.random() > 0.4);
      if (!parts.length) parts.push(members[0]);
      const shares = resolveSplit(amount, { mode: 'equal', participants: parts.map((m) => ({ memberId: m.id })) }, 2);
      entries.push({ amount, paidBy: members[Math.floor(Math.random() * n)].id, shares });
    }
    const balances = computeBalances(members, entries);
    assert.equal(balances.reduce((a, b) => a + b.net, 0), 0);
    const transfers = suggestTransfers(balances);
    assert.ok(transfers.length <= n - 1);
    const net = new Map(balances.map((b) => [b.memberId, b.net]));
    for (const t of transfers) {
      assert.ok(t.amount > 0);
      net.set(t.from, net.get(t.from) + t.amount);
      net.set(t.to, net.get(t.to) - t.amount);
    }
    assert.ok([...net.values()].every((v) => v === 0));
  }
});
