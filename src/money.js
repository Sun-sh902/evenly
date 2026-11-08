// Money helpers. All amounts are stored as integer minor units (e.g. cents).

export const CURRENCIES = {
  USD: { symbol: '$', digits: 2 },
  EUR: { symbol: '€', digits: 2 },
  GBP: { symbol: '£', digits: 2 },
  CAD: { symbol: 'CA$', digits: 2 },
  AUD: { symbol: 'A$', digits: 2 },
  CHF: { symbol: 'CHF ', digits: 2 },
  CNY: { symbol: '¥', digits: 2 },
  HKD: { symbol: 'HK$', digits: 2 },
  SGD: { symbol: 'S$', digits: 2 },
  INR: { symbol: '₹', digits: 2 },
  MXN: { symbol: 'MX$', digits: 2 },
  BRL: { symbol: 'R$', digits: 2 },
  SEK: { symbol: 'kr ', digits: 2 },
  JPY: { symbol: '¥', digits: 0 },
  KRW: { symbol: '₩', digits: 0 },
};

export function isCurrency(code) {
  return typeof code === 'string' && Object.hasOwn(CURRENCIES, code);
}

export function digitsFor(code) {
  return CURRENCIES[code]?.digits ?? 2;
}

/**
 * Parse a user supplied decimal amount (string or number) into integer minor units.
 * Returns null when the input is not a valid, positive amount with at most `digits` decimals.
 */
export function toMinor(input, digits = 2) {
  if (typeof input === 'number') {
    if (!Number.isFinite(input)) return null;
    input = input.toFixed(Math.max(digits, 0) + 2).replace(/0+$/, '').replace(/\.$/, '');
  }
  if (typeof input !== 'string') return null;
  const s = input.trim().replace(/,/g, '');
  const re = digits > 0 ? new RegExp(`^\\d{1,12}(\\.\\d{1,${digits}})?$`) : /^\d{1,12}$/;
  if (!re.test(s)) return null;
  const [whole, frac = ''] = s.split('.');
  const minor = Number(whole) * 10 ** digits + Number((frac + '0'.repeat(digits)).slice(0, digits) || 0);
  return Number.isSafeInteger(minor) ? minor : null;
}

export function fromMinor(minor, digits = 2) {
  const sign = minor < 0 ? '-' : '';
  const abs = Math.abs(minor);
  if (digits === 0) return sign + String(abs);
  const base = 10 ** digits;
  return `${sign}${Math.floor(abs / base)}.${String(abs % base).padStart(digits, '0')}`;
}

/**
 * Split `total` minor units across weights using the largest remainder method so
 * the parts always sum exactly to the total. Ties go to the earlier entry.
 */
export function allocate(total, weights) {
  const sum = weights.reduce((a, b) => a + b, 0);
  if (sum <= 0) throw new Error('weights must sum to a positive number');
  const raw = weights.map((w) => (total * w) / sum);
  const parts = raw.map(Math.floor);
  let left = total - parts.reduce((a, b) => a + b, 0);
  const order = raw
    .map((r, i) => ({ i, frac: r - Math.floor(r) }))
    .sort((a, b) => b.frac - a.frac || a.i - b.i);
  for (let k = 0; left > 0; k = (k + 1) % order.length, left--) parts[order[k].i] += 1;
  // Floating point can, in theory, make the floors overshoot; take the excess back
  // from the entries with the smallest fractional parts so the sum stays exact.
  for (let k = order.length - 1; left < 0; k = (k - 1 + order.length) % order.length) {
    if (parts[order[k].i] > 0) { parts[order[k].i] -= 1; left++; }
  }
  return parts;
}
