// Creates a realistic demo group and prints its URL.
// Usage: node scripts/seed-demo.js [baseUrl]   (server must be running)

const base = process.argv[2] ?? 'http://127.0.0.1:4173';

async function call(method, path, body) {
  const res = await fetch(base + path, { method, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const json = await res.json();
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${json.error}`);
  return json;
}

const g = await call('POST', '/api/groups', { name: 'Lisbon long weekend', currency: 'EUR', members: ['Ana', 'Ben', 'Cleo Park', 'Dev'] });
const [A, B, C, D] = g.members.map((m) => m.id);
const all = [A, B, C, D].map((memberId) => ({ memberId }));
const day = (offset) => {
  const d = new Date();
  d.setDate(d.getDate() - offset);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

const entries = [
  { title: 'Apartment in Alfama, 3 nights', amount: '612.00', paidBy: C, category: 'stay', date: day(3), split: { mode: 'equal', participants: all } },
  { title: 'Airport taxi', amount: '38.40', paidBy: B, category: 'transport', date: day(3), split: { mode: 'equal', participants: all } },
  { title: 'Pingo Doce groceries', amount: '86.75', paidBy: A, category: 'groceries', date: day(2), split: { mode: 'exact', participants: [{ memberId: A, value: '30' }, { memberId: B, value: '30.75' }, { memberId: C, value: '26' }] } },
  { title: 'Pasteis de nata run', amount: '14.40', paidBy: D, category: 'food', date: day(2), note: 'Manteigaria', split: { mode: 'equal', participants: [{ memberId: A }, { memberId: D }] } },
  { title: 'Tram 28 day passes', amount: '25.60', paidBy: B, category: 'transport', date: day(2), split: { mode: 'equal', participants: all } },
  { title: 'Fado night', amount: '180.00', paidBy: B, category: 'fun', date: day(1), split: { mode: 'percent', participants: [{ memberId: A, value: 25 }, { memberId: B, value: 25 }, { memberId: C, value: 25 }, { memberId: D, value: 25 }] } },
  { title: 'Dinner at Taberna', amount: '184.50', paidBy: A, category: 'food', date: day(0), split: { mode: 'shares', participants: [{ memberId: A, value: 2 }, { memberId: B, value: 1 }, { memberId: C, value: 1 }, { memberId: D, value: 1 }] } },
  { kind: 'transfer', amount: '100', paidBy: D, to: C, date: day(1) },
];
for (const e of entries) await call('POST', `/api/groups/${g.id}/entries`, e);
console.log(`${base}/g/${g.id}`);
