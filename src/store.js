// SQLite backed persistence using Node's built-in driver (no native deps).

import { DatabaseSync } from 'node:sqlite';
import { randomBytes } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { CURRENCIES, digitsFor, isCurrency, toMinor, fromMinor } from './money.js';
import { ValidationError, resolveSplit, computeBalances, suggestTransfers } from './ledger.js';

export const LIMITS = { groupName: 60, memberName: 32, title: 80, note: 280, members: 50 };
export const CATEGORIES = ['general', 'food', 'groceries', 'transport', 'stay', 'fun', 'utilities', 'shopping'];
const KINDS = ['expense', 'transfer'];

export class NotFoundError extends Error {
  constructor(message) {
    super(message);
    this.status = 404;
  }
}

export class ConflictError extends Error {
  constructor(message) {
    super(message);
    this.status = 409;
  }
}

const ALPHABET = '23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';
export function newId(len = 12) {
  const bytes = randomBytes(len);
  let s = '';
  for (let i = 0; i < len; i++) s += ALPHABET[bytes[i] % ALPHABET.length];
  return s;
}

function cleanText(value, field, max, { required = true } = {}) {
  if (value === undefined || value === null || value === '') {
    if (required) throw new ValidationError(`${field} is required`, field);
    return '';
  }
  if (typeof value !== 'string') throw new ValidationError(`${field} must be text`, field);
  const v = value.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim();
  if (required && !v) throw new ValidationError(`${field} is required`, field);
  if (v.length > max) throw new ValidationError(`${field} must be at most ${max} characters`, field);
  return v;
}

function cleanDate(value) {
  if (value === undefined || value === null || value === '') {
    // Default to the server's local calendar day. Using the UTC date here put
    // evening expenses on tomorrow for anyone west of Greenwich.
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
  }
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new ValidationError('date must be YYYY-MM-DD', 'date');
  const d = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== value) throw new ValidationError('date is not a real calendar day', 'date');
  return value;
}

export function openStore(file = ':memory:') {
  if (file !== ':memory:') mkdirSync(dirname(file), { recursive: true });
  const db = new DatabaseSync(file);
  db.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS groups (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      currency TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      revision INTEGER NOT NULL DEFAULT 1
    );
    CREATE TABLE IF NOT EXISTS members (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      position INTEGER NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS members_group ON members(group_id);
    CREATE TABLE IF NOT EXISTS entries (
      id TEXT PRIMARY KEY,
      group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      category TEXT NOT NULL,
      amount INTEGER NOT NULL,
      paid_by TEXT NOT NULL REFERENCES members(id),
      split_mode TEXT NOT NULL,
      date TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS entries_group ON entries(group_id, date);
    CREATE TABLE IF NOT EXISTS shares (
      entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
      member_id TEXT NOT NULL REFERENCES members(id),
      share INTEGER NOT NULL,
      weight REAL,
      PRIMARY KEY (entry_id, member_id)
    );
  `);

  // Migration for databases created before the revision column existed.
  if (!db.prepare('PRAGMA table_info(groups)').all().some((c) => c.name === 'revision')) {
    db.exec('ALTER TABLE groups ADD COLUMN revision INTEGER NOT NULL DEFAULT 1');
  }

  const q = {
    insertGroup: db.prepare('INSERT INTO groups (id, name, currency, created_at, updated_at) VALUES (?, ?, ?, ?, ?)'),
    getGroup: db.prepare('SELECT * FROM groups WHERE id = ?'),
    updateGroup: db.prepare('UPDATE groups SET name = ?, currency = ?, updated_at = ?, revision = revision + 1 WHERE id = ?'),
    touchGroup: db.prepare('UPDATE groups SET updated_at = ?, revision = revision + 1 WHERE id = ?'),
    deleteGroup: db.prepare('DELETE FROM groups WHERE id = ?'),
    insertMember: db.prepare('INSERT INTO members (id, group_id, name, position, created_at) VALUES (?, ?, ?, ?, ?)'),
    members: db.prepare('SELECT * FROM members WHERE group_id = ? ORDER BY position'),
    getMember: db.prepare('SELECT * FROM members WHERE id = ? AND group_id = ?'),
    renameMember: db.prepare('UPDATE members SET name = ? WHERE id = ?'),
    deleteMember: db.prepare('DELETE FROM members WHERE id = ?'),
    memberUsage: db.prepare(`SELECT
      (SELECT COUNT(*) FROM entries WHERE paid_by = ?) + (SELECT COUNT(*) FROM shares WHERE member_id = ?) AS n`),
    maxPosition: db.prepare('SELECT COALESCE(MAX(position), -1) AS p FROM members WHERE group_id = ?'),
    insertEntry: db.prepare(`INSERT INTO entries
      (id, group_id, kind, title, note, category, amount, paid_by, split_mode, date, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`),
    updateEntry: db.prepare(`UPDATE entries SET kind = ?, title = ?, note = ?, category = ?, amount = ?, paid_by = ?,
      split_mode = ?, date = ?, updated_at = ? WHERE id = ? AND group_id = ?`),
    getEntry: db.prepare('SELECT * FROM entries WHERE id = ? AND group_id = ?'),
    deleteEntry: db.prepare('DELETE FROM entries WHERE id = ? AND group_id = ?'),
    entries: db.prepare('SELECT * FROM entries WHERE group_id = ? ORDER BY date DESC, created_at DESC, rowid DESC'),
    groupShares: db.prepare('SELECT s.* FROM shares s JOIN entries e ON e.id = s.entry_id WHERE e.group_id = ?'),
    insertShare: db.prepare('INSERT INTO shares (entry_id, member_id, share, weight) VALUES (?, ?, ?, ?)'),
    deleteShares: db.prepare('DELETE FROM shares WHERE entry_id = ?'),
  };

  function tx(fn) {
    db.exec('BEGIN IMMEDIATE');
    try {
      const r = fn();
      db.exec('COMMIT');
      return r;
    } catch (err) {
      db.exec('ROLLBACK');
      throw err;
    }
  }

  function requireGroup(id) {
    const g = typeof id === 'string' ? q.getGroup.get(id) : undefined;
    if (!g) throw new NotFoundError('group not found');
    return g;
  }

  function assertUniqueName(groupId, name, exceptId) {
    const clash = q.members.all(groupId).find((m) => m.id !== exceptId && m.name.toLowerCase() === name.toLowerCase());
    if (clash) throw new ConflictError(`someone called "${name}" is already in this group`);
  }

  function addMemberRow(groupId, rawName, now) {
    const name = cleanText(rawName, 'member name', LIMITS.memberName);
    assertUniqueName(groupId, name);
    if (q.members.all(groupId).length >= LIMITS.members) throw new ValidationError(`a group can have at most ${LIMITS.members} people`, 'members');
    const id = newId(10);
    q.insertMember.run(id, groupId, name, q.maxPosition.get(groupId).p + 1, now);
    return id;
  }

  function normalizeEntry(groupId, currency, input) {
    if (!input || typeof input !== 'object') throw new ValidationError('body must be an object');
    const kind = input.kind ?? 'expense';
    if (!KINDS.includes(kind)) throw new ValidationError('kind must be expense or transfer', 'kind');
    const digits = digitsFor(currency);
    const amount = toMinor(input.amount, digits);
    if (amount === null || amount <= 0) {
      throw new ValidationError(digits ? `amount must be a positive number with up to ${digits} decimals` : 'amount must be a positive whole number', 'amount');
    }
    const memberIds = new Set(q.members.all(groupId).map((m) => m.id));
    if (!memberIds.has(input.paidBy)) throw new ValidationError('paidBy must be someone in this group', 'paidBy');

    let split = input.split;
    let title;
    let category;
    if (kind === 'transfer') {
      const to = input.to ?? split?.participants?.[0]?.memberId;
      if (!memberIds.has(to)) throw new ValidationError('transfer needs a recipient in this group', 'to');
      if (to === input.paidBy) throw new ValidationError('cannot pay yourself', 'to');
      split = { mode: 'equal', participants: [{ memberId: to }] };
      title = cleanText(input.title, 'title', LIMITS.title, { required: false }) || 'Settlement';
      category = 'transfer';
    } else {
      title = cleanText(input.title, 'title', LIMITS.title);
      category = input.category ?? 'general';
      if (!CATEGORIES.includes(category)) throw new ValidationError(`category must be one of ${CATEGORIES.join(', ')}`, 'category');
    }
    const shares = resolveSplit(amount, split, digits);
    for (const s of shares) {
      if (!memberIds.has(s.memberId)) throw new ValidationError('split includes someone who is not in this group', 'split.participants');
    }
    return {
      kind,
      title,
      note: cleanText(input.note, 'note', LIMITS.note, { required: false }),
      category,
      amount,
      paidBy: input.paidBy,
      mode: split.mode,
      date: cleanDate(input.date),
      shares,
    };
  }

  function writeShares(entryId, shares) {
    q.deleteShares.run(entryId);
    for (const s of shares) q.insertShare.run(entryId, s.memberId, s.share, s.weight);
  }

  function snapshot(groupId) {
    const g = requireGroup(groupId);
    const digits = digitsFor(g.currency);
    const members = q.members.all(g.id).map((m) => ({ id: m.id, name: m.name }));
    const sharesByEntry = new Map();
    for (const s of q.groupShares.all(g.id)) {
      if (!sharesByEntry.has(s.entry_id)) sharesByEntry.set(s.entry_id, []);
      sharesByEntry.get(s.entry_id).push({ memberId: s.member_id, share: s.share, weight: s.weight });
    }
    const order = new Map(members.map((m, i) => [m.id, i]));
    const entries = q.entries.all(g.id).map((e) => ({
      id: e.id,
      kind: e.kind,
      title: e.title,
      note: e.note,
      category: e.category,
      amount: e.amount,
      paidBy: e.paid_by,
      splitMode: e.split_mode,
      date: e.date,
      createdAt: e.created_at,
      updatedAt: e.updated_at,
      shares: (sharesByEntry.get(e.id) ?? []).sort((a, b) => order.get(a.memberId) - order.get(b.memberId)),
    }));
    const balances = computeBalances(members, entries);
    const spent = entries.filter((e) => e.kind === 'expense');
    const totalSpent = spent.reduce((a, e) => a + e.amount, 0);
    const byCategory = {};
    for (const e of spent) byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    return {
      id: g.id,
      name: g.name,
      currency: g.currency,
      digits,
      createdAt: g.created_at,
      updatedAt: g.updated_at,
      revision: g.revision,
      members,
      entries,
      balances,
      transfers: suggestTransfers(balances),
      stats: { totalSpent, expenseCount: spent.length, byCategory, settled: balances.every((b) => b.net === 0) },
      display: { totalSpent: fromMinor(totalSpent, digits) },
    };
  }

  return {
    db,
    close: () => db.close(),

    createGroup(input) {
      if (!input || typeof input !== 'object') throw new ValidationError('body must be an object');
      const name = cleanText(input.name, 'name', LIMITS.groupName);
      const currency = input.currency ?? 'USD';
      if (!isCurrency(currency)) throw new ValidationError(`currency must be one of ${Object.keys(CURRENCIES).join(', ')}`, 'currency');
      const names = input.members ?? [];
      if (!Array.isArray(names)) throw new ValidationError('members must be a list of names', 'members');
      if (names.length < 1) throw new ValidationError('add at least one person', 'members');
      if (names.length > LIMITS.members) throw new ValidationError(`a group can have at most ${LIMITS.members} people`, 'members');
      const id = newId(12);
      const now = new Date().toISOString();
      tx(() => {
        q.insertGroup.run(id, name, currency, now, now);
        for (const n of names) addMemberRow(id, n, now);
      });
      return snapshot(id);
    },

    getGroup: (id) => snapshot(id),

    /** Cheap lookup used for conditional GETs (ETag) without building a snapshot. */
    groupRevision(id) {
      return requireGroup(id).revision;
    },

    updateGroup(id, input) {
      const g = requireGroup(id);
      const name = input?.name === undefined ? g.name : cleanText(input.name, 'name', LIMITS.groupName);
      let currency = g.currency;
      if (input?.currency !== undefined && input.currency !== g.currency) {
        if (!isCurrency(input.currency)) throw new ValidationError('unsupported currency', 'currency');
        if (digitsFor(input.currency) !== digitsFor(g.currency) && q.entries.all(id).length) {
          throw new ConflictError('cannot switch to a currency with different decimals once expenses exist');
        }
        currency = input.currency;
      }
      q.updateGroup.run(name, currency, new Date().toISOString(), id);
      return snapshot(id);
    },

    deleteGroup(id) {
      requireGroup(id);
      q.deleteGroup.run(id);
    },

    addMember(groupId, input) {
      requireGroup(groupId);
      const now = new Date().toISOString();
      const memberId = tx(() => {
        const mid = addMemberRow(groupId, input?.name, now);
        q.touchGroup.run(now, groupId);
        return mid;
      });
      return { memberId, group: snapshot(groupId) };
    },

    renameMember(groupId, memberId, input) {
      requireGroup(groupId);
      if (!q.getMember.get(memberId, groupId)) throw new NotFoundError('person not found');
      const name = cleanText(input?.name, 'member name', LIMITS.memberName);
      assertUniqueName(groupId, name, memberId);
      q.renameMember.run(name, memberId);
      q.touchGroup.run(new Date().toISOString(), groupId);
      return snapshot(groupId);
    },

    removeMember(groupId, memberId) {
      requireGroup(groupId);
      if (!q.getMember.get(memberId, groupId)) throw new NotFoundError('person not found');
      if (q.memberUsage.get(memberId, memberId).n > 0) {
        throw new ConflictError('this person is part of existing expenses; remove or edit those first');
      }
      if (q.members.all(groupId).length <= 1) throw new ConflictError('a group needs at least one person');
      q.deleteMember.run(memberId);
      q.touchGroup.run(new Date().toISOString(), groupId);
      return snapshot(groupId);
    },

    addEntry(groupId, input) {
      const g = requireGroup(groupId);
      const e = normalizeEntry(g.id, g.currency, input);
      const id = newId(12);
      const now = new Date().toISOString();
      tx(() => {
        q.insertEntry.run(id, g.id, e.kind, e.title, e.note, e.category, e.amount, e.paidBy, e.mode, e.date, now, now);
        writeShares(id, e.shares);
        q.touchGroup.run(now, g.id);
      });
      return { entryId: id, group: snapshot(g.id) };
    },

    updateEntry(groupId, entryId, input) {
      const g = requireGroup(groupId);
      if (!q.getEntry.get(entryId, g.id)) throw new NotFoundError('expense not found');
      const e = normalizeEntry(g.id, g.currency, input);
      const now = new Date().toISOString();
      tx(() => {
        q.updateEntry.run(e.kind, e.title, e.note, e.category, e.amount, e.paidBy, e.mode, e.date, now, entryId, g.id);
        writeShares(entryId, e.shares);
        q.touchGroup.run(now, g.id);
      });
      return snapshot(g.id);
    },

    deleteEntry(groupId, entryId) {
      const g = requireGroup(groupId);
      if (!q.getEntry.get(entryId, g.id)) throw new NotFoundError('expense not found');
      tx(() => {
        q.deleteEntry.run(entryId, g.id);
        q.touchGroup.run(new Date().toISOString(), g.id);
      });
      return snapshot(g.id);
    },

    exportCsv(groupId) {
      const s = snapshot(groupId);
      const names = new Map(s.members.map((m) => [m.id, m.name]));
      const esc = (v) => {
        let t = String(v);
        if (/^[=+\-@\t\r]/.test(t)) t = `'${t}`; // neutralise spreadsheet formulas
        return /[",\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t;
      };
      const header = ['date', 'kind', 'title', 'category', 'amount', 'currency', 'paid_by', ...s.members.map((m) => `share_${m.name}`)];
      const rows = [...s.entries].reverse().map((e) => {
        const share = new Map(e.shares.map((x) => [x.memberId, x.share]));
        return [
          e.date, e.kind, e.title, e.category, fromMinor(e.amount, s.digits), s.currency, names.get(e.paidBy),
          ...s.members.map((m) => fromMinor(share.get(m.id) ?? 0, s.digits)),
        ];
      });
      return [header, ...rows].map((r) => r.map(esc).join(',')).join('\n') + '\n';
    },
  };
}
