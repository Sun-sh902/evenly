// Pure ledger logic: turn split instructions into per-member shares, compute
// balances, and suggest the fewest practical transfers to settle a group.

import { allocate, toMinor } from './money.js';

export const SPLIT_MODES = ['equal', 'exact', 'shares', 'percent'];

export class ValidationError extends Error {
  constructor(message, field) {
    super(message);
    this.field = field;
    this.status = 400;
  }
}

/**
 * Resolve a split into concrete integer shares.
 * @param {number} amount total in minor units
 * @param {{mode:string, participants:{memberId:string, value?:any}[]}} split
 * @param {number} digits currency minor digits (used for exact mode parsing)
 * @returns {{memberId:string, share:number, weight:number|null}[]}
 */
export function resolveSplit(amount, split, digits) {
  if (!split || typeof split !== 'object') throw new ValidationError('split is required', 'split');
  const { mode, participants } = split;
  if (!SPLIT_MODES.includes(mode)) throw new ValidationError(`split.mode must be one of ${SPLIT_MODES.join(', ')}`, 'split.mode');
  if (!Array.isArray(participants) || participants.length === 0) {
    throw new ValidationError('choose at least one person to split with', 'split.participants');
  }
  const seen = new Set();
  for (const p of participants) {
    if (!p || typeof p.memberId !== 'string') throw new ValidationError('each participant needs a memberId', 'split.participants');
    if (seen.has(p.memberId)) throw new ValidationError('a person appears twice in the split', 'split.participants');
    seen.add(p.memberId);
  }

  if (mode === 'equal') {
    const parts = allocate(amount, participants.map(() => 1));
    return participants.map((p, i) => ({ memberId: p.memberId, share: parts[i], weight: null }));
  }

  if (mode === 'exact') {
    const shares = participants.map((p) => {
      const v = p.value === 0 || p.value === '0' ? 0 : toMinor(p.value, digits);
      if (v === null) throw new ValidationError('every exact amount must be a valid number', 'split.participants');
      return v;
    });
    const sum = shares.reduce((a, b) => a + b, 0);
    if (sum !== amount) throw new ValidationError('exact amounts must add up to the total', 'split.participants');
    return participants.map((p, i) => ({ memberId: p.memberId, share: shares[i], weight: null }));
  }

  // shares and percent are both weight based
  const weights = participants.map((p) => {
    const w = Number(p.value);
    if (!Number.isFinite(w) || w < 0 || w > 1e6) throw new ValidationError(`every ${mode === 'percent' ? 'percentage' : 'share'} must be a non-negative number`, 'split.participants');
    return w;
  });
  const total = weights.reduce((a, b) => a + b, 0);
  if (mode === 'percent' && Math.abs(total - 100) > 1e-6) throw new ValidationError('percentages must add up to 100', 'split.participants');
  if (total <= 0) throw new ValidationError('at least one share must be greater than zero', 'split.participants');
  const parts = allocate(amount, weights);
  return participants.map((p, i) => ({ memberId: p.memberId, share: parts[i], weight: weights[i] }));
}

/**
 * Net balance per member. Positive = the group owes them, negative = they owe.
 */
export function computeBalances(members, entries) {
  const bal = new Map(members.map((m) => [m.id, { memberId: m.id, paid: 0, owed: 0, net: 0 }]));
  for (const e of entries) {
    const payer = bal.get(e.paidBy);
    if (payer) {
      payer.paid += e.amount;
      payer.net += e.amount;
    }
    for (const s of e.shares) {
      const row = bal.get(s.memberId);
      if (!row) continue;
      row.owed += s.share;
      row.net -= s.share;
    }
  }
  return [...bal.values()];
}

/**
 * Greedy settle: repeatedly match the largest debtor with the largest creditor.
 * Produces at most n-1 transfers and always clears every balance.
 */
export function suggestTransfers(balances) {
  const creditors = balances.filter((b) => b.net > 0).map((b) => ({ id: b.memberId, amt: b.net }));
  const debtors = balances.filter((b) => b.net < 0).map((b) => ({ id: b.memberId, amt: -b.net }));
  const out = [];
  const byAmt = (a, b) => b.amt - a.amt || (a.id < b.id ? -1 : 1);
  while (creditors.length && debtors.length) {
    creditors.sort(byAmt);
    debtors.sort(byAmt);
    const c = creditors[0];
    const d = debtors[0];
    const amt = Math.min(c.amt, d.amt);
    out.push({ from: d.id, to: c.id, amount: amt });
    c.amt -= amt;
    d.amt -= amt;
    if (c.amt === 0) creditors.shift();
    if (d.amt === 0) debtors.shift();
  }
  return out;
}
