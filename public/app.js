// Evenly frontend: a dependency free single page app.

const LOCALE = 'en-US';
const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
const view = $('#view');
const sheet = $('#sheet');

const state = { meta: null, group: null, filter: 'all', query: '', draft: [] };

/* ---------------------------------------------------------------- theme */
const THEME_KEY = 'evenly.theme';
function storageGet(k, fallback) { try { const v = localStorage.getItem(k); return v === null ? fallback : JSON.parse(v); } catch { return fallback; } }
function storageSet(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* private mode */ } }
function applyTheme(t) { if (t) document.documentElement.dataset.theme = t; else delete document.documentElement.dataset.theme; }
applyTheme(storageGet(THEME_KEY, null));
$('#themeToggle').addEventListener('click', () => {
  const current = document.documentElement.dataset.theme || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  const next = current === 'dark' ? 'light' : 'dark';
  applyTheme(next);
  storageSet(THEME_KEY, next);
});
addEventListener('scroll', () => $('.topbar').classList.toggle('scrolled', scrollY > 4), { passive: true });

/* ---------------------------------------------------------------- icons */
const ICONS = {
  general: '<path d="M6 3h12v18l-3-2-3 2-3-2-3 2V3Z"/><path d="M9 8h6M9 12h6"/>',
  food: '<path d="M7 3v8a2 2 0 0 0 2 2v8M11 3v8a2 2 0 0 1-2 2M17 21V3c-2 1-3 4-3 7s1 4 3 4"/>',
  groceries: '<path d="M4 8h16l-1.5 11a2 2 0 0 1-2 1.7h-9A2 2 0 0 1 5.5 19L4 8Z"/><path d="M9 8 12 3l3 5M10 12v5M14 12v5"/>',
  transport: '<path d="M5 17V11l2-5h10l2 5v6"/><path d="M3 17h18M7.5 17v2M16.5 17v2M5 11h14"/><circle cx="8" cy="14" r=".6"/><circle cx="16" cy="14" r=".6"/>',
  stay: '<path d="M3 20V9M3 15h18v5M21 15v-3a3 3 0 0 0-3-3h-7v6"/><circle cx="7" cy="12" r="1.8"/>',
  fun: '<path d="M4 8a2 2 0 0 0 0 4v4h16v-4a2 2 0 0 1 0-4V4H4v4Z" transform="translate(0 2)"/><path d="M14 6v12" stroke-dasharray="2 2"/>',
  utilities: '<path d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z"/>',
  shopping: '<path d="M5 8h14l-1 13H6L5 8Z"/><path d="M9 8V6a3 3 0 0 1 6 0v2"/>',
  transfer: '<path d="M4 8h14l-3-3M20 16H6l3 3"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/>',
  download: '<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.3-4.3"/>',
  arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  pencil: '<path d="M4 20h4L19 9l-4-4L4 16v4Z"/><path d="m13.5 6.5 4 4"/>',
  trash: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
  sparkle: '<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z"/>',
  alert: '<circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5M12 16.5v.01"/>',
  party: '<path d="M4 20 9 7l8 8-13 5Z"/><path d="M14 4c1 1 1 2 0 3M19 9c-1-1-2-1-3 0M17 3v2M21 7h-2"/>',
};
const icon = (name, cls = '') => `<svg class="i ${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name] ?? ICONS.general}</svg>`;

const CATEGORY_META = {
  general: { label: 'General', color: '#7a7f8c' },
  food: { label: 'Food & drink', color: '#d9822b' },
  groceries: { label: 'Groceries', color: '#5f9a2c' },
  transport: { label: 'Transport', color: '#2f7fd8' },
  stay: { label: 'Stay', color: '#8d5bd6' },
  fun: { label: 'Fun', color: '#d0467f' },
  utilities: { label: 'Bills', color: '#c8a21a' },
  shopping: { label: 'Shopping', color: '#2b9bb0' },
  transfer: { label: 'Settlement', color: '#1d8a63' },
};

/* -------------------------------------------------------------- helpers */
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

function money(minor, group = state.group, { sign = false } = {}) {
  const digits = group?.digits ?? 2;
  const value = minor / 10 ** digits;
  const s = new Intl.NumberFormat(LOCALE, { style: 'currency', currencyDisplay: 'narrowSymbol', currency: group?.currency ?? 'USD', minimumFractionDigits: digits, maximumFractionDigits: digits }).format(Math.abs(value));
  if (!sign) return (minor < 0 ? '-' : '') + s;
  return minor > 0 ? `+${s}` : minor < 0 ? `-${s}` : s;
}

function currencySymbol(code) {
  const part = new Intl.NumberFormat(LOCALE, { style: 'currency', currencyDisplay: 'narrowSymbol', currency: code }).formatToParts(0).find((p) => p.type === 'currency');
  return part?.value ?? code;
}

function toMinor(input, digits) {
  const s = String(input ?? '').trim().replace(/,/g, '');
  const re = digits > 0 ? new RegExp(`^\\d{1,12}(\\.\\d{1,${digits}})?$`) : /^\d{1,12}$/;
  if (!re.test(s)) return null;
  const [w, f = ''] = s.split('.');
  return Number(w) * 10 ** digits + Number((f + '0'.repeat(digits)).slice(0, digits) || 0);
}
const fromMinor = (m, d) => (d ? (m / 10 ** d).toFixed(d) : String(m));

function allocate(total, weights) {
  const sum = weights.reduce((a, b) => a + b, 0);
  if (sum <= 0) return weights.map(() => 0);
  const raw = weights.map((w) => (total * w) / sum);
  const parts = raw.map(Math.floor);
  let left = total - parts.reduce((a, b) => a + b, 0);
  const order = raw.map((r, i) => ({ i, f: r - Math.floor(r) })).sort((a, b) => b.f - a.f || a.i - b.i);
  for (let k = 0; left > 0; k = (k + 1) % order.length, left--) parts[order[k].i] += 1;
  return parts;
}

const PALETTE = ['#2f7fd8', '#d0573b', '#1d8a63', '#8d5bd6', '#c98a12', '#d0467f', '#2b9bb0', '#6b7d26', '#b5562b', '#4c63d2'];
function memberColor(id) {
  const idx = state.group?.members.findIndex((m) => m.id === id) ?? -1;
  if (idx >= 0) return PALETTE[idx % PALETTE.length];
  let h = 0;
  for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return PALETTE[h % PALETTE.length];
}
function initials(name) {
  const parts = String(name).trim().split(/\s+/);
  return ((parts[0]?.[0] ?? '') + (parts.length > 1 ? parts.at(-1)[0] : parts[0]?.[1] ?? '')).toUpperCase();
}
const avatar = (m, cls = '') => `<span class="avatar ${cls}" style="--c:${memberColor(m.id)}" title="${esc(m.name)}" aria-hidden="true">${esc(initials(m.name))}</span>`;
const memberById = (id) => state.group?.members.find((m) => m.id === id) ?? { id, name: 'Someone' };

function todayISO() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function dayLabel(iso) {
  const today = todayISO();
  const y = new Date(); y.setDate(y.getDate() - 1);
  const yISO = `${y.getFullYear()}-${String(y.getMonth() + 1).padStart(2, '0')}-${String(y.getDate()).padStart(2, '0')}`;
  if (iso === today) return 'Today';
  if (iso === yISO) return 'Yesterday';
  const d = new Date(`${iso}T00:00:00Z`);
  const sameYear = d.getUTCFullYear() === new Date().getFullYear();
  return d.toLocaleDateString(LOCALE, { weekday: 'short', month: 'short', day: 'numeric', ...(sameYear ? {} : { year: 'numeric' }), timeZone: 'UTC' });
}
function relTime(iso) {
  const diff = (Date.now() - new Date(iso).getTime()) / 1000;
  if (diff < 60) return 'just now';
  const rtf = new Intl.RelativeTimeFormat(LOCALE, { numeric: 'auto' });
  for (const [s, unit] of [[86400 * 365, 'year'], [86400 * 30, 'month'], [86400 * 7, 'week'], [86400, 'day'], [3600, 'hour'], [60, 'minute']]) {
    if (diff >= s) return rtf.format(-Math.floor(diff / s), unit);
  }
  return 'just now';
}

async function api(method, path, body, headers = {}) {
  const res = await fetch(path, {
    method,
    headers: body ? { 'Content-Type': 'application/json', ...headers } : headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 304) return null;
  const data = res.status === 204 ? null : await res.json().catch(() => null);
  if (!res.ok) {
    const err = new Error(data?.error ?? `Request failed (${res.status})`);
    err.status = res.status;
    err.field = data?.field;
    throw err;
  }
  return data;
}

function toast(message, kind = 'ok') {
  const el = document.createElement('div');
  el.className = `toast ${kind}`;
  el.innerHTML = `${icon(kind === 'error' ? 'alert' : 'check')}<span>${esc(message)}</span>`;
  $('#toasts').append(el);
  setTimeout(() => { el.classList.add('out'); el.addEventListener('animationend', () => el.remove(), { once: true }); }, 2600);
}

function capitalise(msg) { return msg ? msg[0].toUpperCase() + msg.slice(1) : msg; }

/* recent groups (per browser convenience only) */
const RECENT_KEY = 'evenly.recent';
function rememberGroup(g) {
  const list = storageGet(RECENT_KEY, []).filter((r) => r.id !== g.id);
  list.unshift({ id: g.id, name: g.name, currency: g.currency, members: g.members.map((m) => m.name).slice(0, 6), count: g.members.length, total: g.stats.totalSpent, digits: g.digits, seen: new Date().toISOString() });
  storageSet(RECENT_KEY, list.slice(0, 12));
}
function forgetGroup(id) { storageSet(RECENT_KEY, storageGet(RECENT_KEY, []).filter((r) => r.id !== id)); }

/* --------------------------------------------------------------- router */
function navigate(path, { replace = false } = {}) {
  if (replace) history.replaceState(null, '', path); else history.pushState(null, '', path);
  route();
}
document.addEventListener('click', (e) => {
  const a = e.target.closest('a[data-link]');
  if (!a || e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
  e.preventDefault();
  navigate(a.getAttribute('href'));
});
addEventListener('popstate', route);

async function route() {
  if (sheet.open) sheet.close();
  clearTimeout(syncTimer);
  const path = location.pathname;
  const m = path.match(/^\/g\/([\w-]+)\/?$/);
  $('#newGroupLink').hidden = !m;
  scrollTo({ top: 0 });
  if (path === '/') return renderHome();
  if (m) return loadGroup(m[1]);
  renderNotFound('This page does not exist.');
}

function renderNotFound(message) {
  document.title = 'Not found - Evenly';
  view.innerHTML = `<div class="wrap notfound rise"><div><h1>Nothing here</h1><p>${esc(message)}</p><a class="btn btn-primary" href="/" data-link>Start a new group</a></div></div>`;
}

/* ----------------------------------------------------------------- home */
function renderHome() {
  document.title = 'Evenly - split costs, keep friends';
  state.group = null;
  const recent = storageGet(RECENT_KEY, []);
  const currencies = Object.keys(state.meta?.currencies ?? { USD: 1, EUR: 1, GBP: 1 });
  const guess = guessCurrency(currencies);
  view.innerHTML = `
  <div class="wrap">
    <section class="hero">
      <div class="rise">
        <span class="eyebrow"><span class="dot"></span>Free, open, and without a daily cap</span>
        <h1>Split the bill,<br><em>not the friendship.</em></h1>
        <p class="lede">Track shared costs for trips, flats and dinners. Nobody signs up, nobody installs anything, and nobody hits a limit after three expenses. Share one link and the whole group is in.</p>
        <ul class="proof">
          <li>${icon('check')}No accounts</li>
          <li>${icon('check')}Unlimited expenses</li>
          <li>${icon('check')}Fewest possible payments</li>
          <li>${icon('check')}CSV export</li>
        </ul>
      </div>
      <form class="create-card rise rise-2" id="createForm" novalidate>
        <h2>Start a group</h2>
        <p>Takes ten seconds. You can add more people later.</p>
        <div class="form-grid">
          <div class="row-2">
            <label class="field"><span class="label">Group name</span>
              <input class="input" name="name" maxlength="60" placeholder="Lisbon trip" autocomplete="off" required>
            </label>
            <label class="field"><span class="label">Currency</span>
              <select class="select" name="currency">${currencies.map((c) => `<option ${c === guess ? 'selected' : ''}>${c}</option>`).join('')}</select>
            </label>
          </div>
          <div class="field">
            <label class="label" for="peopleInput">People</label>
            <div class="chip-input" id="chipBox">
              <input id="peopleInput" maxlength="32" placeholder="Type a name, press Enter" autocomplete="off">
            </div>
            <span class="hint">Add yourself too. Press Enter or comma after each name.</span>
          </div>
          <div class="error-text" id="createError" role="alert"></div>
          <button class="btn btn-primary btn-block" type="submit" style="--h:50px">Create group ${icon('arrow')}</button>
        </div>
      </form>
    </section>

    <section class="how">
      <div class="how-item rise rise-2"><div class="step">1</div><h3>Make a group</h3><p>Name it, add the people. That's the whole setup.</p></div>
      <div class="how-item rise rise-3"><div class="step">2</div><h3>Log what you spend</h3><p>Split equally, by exact amounts, by shares or by percent. Pennies always add up.</p></div>
      <div class="how-item rise rise-4"><div class="step">3</div><h3>Settle in fewer moves</h3><p>Evenly works out the smallest set of payments so everyone ends at zero.</p></div>
    </section>

    ${recent.length ? `
    <section class="recent">
      <div class="section-title"><h2>Your groups</h2><span class="muted" style="font-size:13px">Saved on this device</span></div>
      <div class="recent-grid">
        ${recent.map((r) => `
          <a class="recent-item" href="/g/${esc(r.id)}" data-link>
            <div class="name">${esc(r.name)}</div>
            <div class="meta">
              <span class="avatar-stack">${r.members.slice(0, 4).map((n, i) => `<span class="avatar sm" style="--c:${PALETTE[i % PALETTE.length]}">${esc(initials(n))}</span>`).join('')}</span>
              <span>${money(r.total ?? 0, { currency: r.currency, digits: r.digits ?? 2 })} · ${esc(relTime(r.seen))}</span>
            </div>
          </a>`).join('')}
      </div>
    </section>` : ''}
  </div>`;

  state.draft = [];
  const box = $('#chipBox');
  const input = $('#peopleInput');
  const err = $('#createError');
  const drawChips = () => {
    $$('.chip', box).forEach((c) => c.remove());
    state.draft.forEach((name, i) => {
      const chip = document.createElement('span');
      chip.className = 'chip';
      chip.innerHTML = `<span class="avatar sm" style="--c:${PALETTE[i % PALETTE.length]}">${esc(initials(name))}</span>${esc(name)}<button type="button" aria-label="Remove ${esc(name)}">${icon('x')}</button>`;
      chip.querySelector('button').addEventListener('click', () => { state.draft.splice(i, 1); drawChips(); input.focus(); });
      box.insertBefore(chip, input);
    });
    input.placeholder = state.draft.length ? 'Add another' : 'Type a name, press Enter';
  };
  const commit = () => {
    // Accept pasted lists such as "Ana, Ben; Cleo" as well as one name at a time.
    const names = input.value.split(/[,;\n]/).map((n) => n.replace(/\s+/g, ' ').trim().slice(0, 32)).filter(Boolean);
    if (!names.length) { input.value = ''; return true; }
    const dupes = [];
    for (const name of names) {
      if (state.draft.some((n) => n.toLowerCase() === name.toLowerCase())) dupes.push(name);
      else state.draft.push(name);
    }
    input.value = '';
    err.textContent = dupes.length ? `${dupes.join(', ')} ${dupes.length > 1 ? 'are' : 'is'} already on the list.` : '';
    drawChips();
    return true;
  };
  input.addEventListener('input', () => { if (/[,;\n]/.test(input.value)) commit(); });
  box.addEventListener('click', (e) => { if (e.target === box) input.focus(); });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ',') { e.preventDefault(); commit(); }
    else if (e.key === 'Backspace' && !input.value && state.draft.length) { state.draft.pop(); drawChips(); }
  });
  input.addEventListener('blur', commit);

  $('#createForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const form = e.currentTarget;
    if (!commit()) return;
    const name = form.name.value.trim();
    form.name.classList.toggle('invalid', !name);
    if (!name) { err.textContent = 'Give your group a name.'; form.name.focus(); return; }
    if (!state.draft.length) { err.textContent = 'Add at least one person.'; input.focus(); return; }
    const btn = form.querySelector('button[type=submit]');
    btn.disabled = true;
    try {
      const g = await api('POST', '/api/groups', { name, currency: form.currency.value, members: state.draft });
      rememberGroup(g);
      navigate(`/g/${g.id}`);
      toast('Group created. Share the link with everyone.');
    } catch (ex) {
      err.textContent = capitalise(ex.message);
      btn.disabled = false;
    }
  });
}

function guessCurrency(list) {
  try {
    const region = new Intl.Locale(navigator.language).maximize().region;
    const map = { US: 'USD', GB: 'GBP', CA: 'CAD', AU: 'AUD', JP: 'JPY', KR: 'KRW', CN: 'CNY', HK: 'HKD', SG: 'SGD', IN: 'INR', MX: 'MXN', BR: 'BRL', CH: 'CHF', SE: 'SEK' };
    const euro = ['DE', 'FR', 'ES', 'IT', 'NL', 'PT', 'IE', 'AT', 'BE', 'FI', 'GR'];
    const c = euro.includes(region) ? 'EUR' : map[region];
    return list.includes(c) ? c : 'USD';
  } catch { return 'USD'; }
}

/* ------------------------------------------------------------- identity */
// Which member this browser belongs to. Purely a per-device convenience.
const meKey = (gid) => `evenly.me.${gid}`;
function myId(g = state.group) {
  const id = g ? storageGet(meKey(g.id), null) : null;
  return g?.members.some((m) => m.id === id) ? id : null;
}
function setMe(id) {
  storageSet(meKey(state.group.id), id);
  renderGroup(false);
}
const youTag = (id) => (id && id === myId() ? ' <span class="you">you</span>' : '');

/* ------------------------------------------------------------ live sync */
// Poll for changes made by other people. The server answers 304 when nothing
// changed, so an idle tab costs almost nothing.
const SYNC_MS = 12_000;
let syncTimer = null;
function scheduleSync() {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(syncNow, SYNC_MS);
}
function isBusy() {
  const el = document.activeElement;
  return sheet.open || (el && view.contains(el) && (el.tagName === 'INPUT' || el.isContentEditable));
}
async function syncNow() {
  const g = state.group;
  if (!g || document.hidden) return scheduleSync();
  if (isBusy()) return scheduleSync();
  try {
    const fresh = await api('GET', `/api/groups/${g.id}`, undefined, { 'If-None-Match': `W/"${g.id}-${g.revision}"` });
    if (fresh && state.group?.id === fresh.id && fresh.revision > state.group.revision && !isBusy()) {
      setGroup(fresh);
      toast('Updated with the latest changes');
    }
  } catch (ex) {
    if (ex.status === 404 && state.group?.id === g.id) { forgetGroup(g.id); renderNotFound('This group was deleted.'); return; }
  }
  scheduleSync();
}
document.addEventListener('visibilitychange', () => { if (!document.hidden && state.group) syncNow(); });

/* ---------------------------------------------------------------- group */
async function loadGroup(id) {
  if (state.group?.id !== id) view.innerHTML = '<div class="boot"><span class="spinner"></span></div>';
  try {
    setGroup(await api('GET', `/api/groups/${id}`));
  } catch (ex) {
    if (ex.status === 404) { forgetGroup(id); return renderNotFound('This group was deleted, or the link is mistyped.'); }
    renderNotFound('Could not reach the server. Check your connection and refresh.');
  }
}

function setGroup(g) {
  const first = state.group?.id !== g.id;
  if (first) { state.filter = 'all'; state.query = ''; }
  state.group = g;
  rememberGroup(g);
  document.title = `${g.name} - Evenly`;
  const y = scrollY;
  renderGroup(first);
  if (!first) scrollTo({ top: y });
  scheduleSync();
}

function renderGroup(animate) {
  const g = state.group;
  const created = new Date(g.createdAt).toLocaleDateString(LOCALE, { month: 'short', day: 'numeric', year: 'numeric' });
  const cats = Object.entries(g.stats.byCategory).sort((a, b) => b[1] - a[1]);
  const top = cats[0];
  const a = animate ? 'rise' : '';
  view.innerHTML = `
  <div class="wrap">
    <section class="ghead ${a}">
      <div class="ghead-title">
        <div class="crumbs"><span>${g.members.length} ${g.members.length === 1 ? 'person' : 'people'}</span><span class="sep"></span><span>${esc(g.currency)}</span><span class="sep"></span><span>Since ${esc(created)}</span></div>
        <h1 class="gname" id="gname" contenteditable="plaintext-only" spellcheck="false" aria-label="Group name, click to rename">${esc(g.name)}</h1>
      </div>
      <div class="ghead-actions">
        <button class="btn btn-ghost btn-sm" id="shareBtn" type="button">${icon('link')}<span class="lbl">Copy invite link</span></button>
        <a class="btn btn-ghost btn-sm" href="/api/groups/${esc(g.id)}/export.csv" download>${icon('download')}<span class="lbl">Export CSV</span></a>
        <button class="icon-btn" id="settingsBtn" type="button" aria-label="Group settings">${icon('gear')}</button>
      </div>
    </section>

    ${meBar(g, a)}

    <section class="stats ${a} ${a && 'rise-2'}">
      <div class="stat feature">
        <div class="k">Total group spend</div>
        <div class="v">${money(g.stats.totalSpent)}</div>
        ${cats.length ? `<div class="catbar" aria-hidden="true">${cats.map(([c, v]) => `<span style="flex:${v};background:${CATEGORY_META[c]?.color}"></span>`).join('')}</div>` : ''}
      </div>
      <div class="stat"><div class="k">Expenses logged</div><div class="v">${g.stats.expenseCount}</div></div>
      <div class="stat"><div class="k">Biggest category</div><div class="v" style="font-size:${top ? 30 : 40}px">${top ? esc(CATEGORY_META[top[0]]?.label) : '-'}${top ? `<small>${Math.round((top[1] / g.stats.totalSpent) * 100)}%</small>` : ''}</div></div>
    </section>

    <section class="layout">
      <div class="card ${a} ${a && 'rise-3'}" style="overflow:clip">
        <div class="toolbar">
          <label class="search"><span class="sr-only">Search expenses</span>${icon('search')}<input class="input" id="search" placeholder="Search expenses" value="${esc(state.query)}" autocomplete="off"></label>
          <div class="seg" role="group" aria-label="Filter activity">
            ${[['all', 'All'], ['expense', 'Expenses'], ['transfer', 'Payments']].map(([k, l]) => `<button type="button" data-filter="${k}" aria-pressed="${state.filter === k}">${l}</button>`).join('')}
          </div>
        </div>
        <div id="activity"></div>
      </div>
      <aside class="side ${a} ${a && 'rise-4'}">
        ${balancesCard(g)}
        ${settleCard(g)}
        ${peopleCard(g)}
      </aside>
    </section>
  </div>
  <button class="btn btn-primary fab" id="fab" type="button">${icon('plus')}Add expense <kbd class="kbd-hint">N</kbd></button>`;

  renderActivity();
  bindGroup();
}

function meBar(g, a) {
  if (g.members.length < 2) return '';
  const me = myId(g);
  if (!me) {
    return `<section class="me-bar ask ${a}">
      <div class="me-text"><b>Which one are you?</b><span class="muted">Evenly will show your own balance and pick you as the payer by default. Saved on this device only.</span></div>
      <div class="me-pick">${g.members.map((m) => `<button type="button" class="payer" data-me="${esc(m.id)}">${avatar(m)}${esc(m.name)}</button>`).join('')}</div>
    </section>`;
  }
  const bal = g.balances.find((b) => b.memberId === me)?.net ?? 0;
  const mine = g.transfers.filter((t) => t.from === me);
  const owedToMe = g.transfers.filter((t) => t.to === me);
  let line;
  let action = '';
  if (bal > 0) {
    line = `You get back <b class="pos">${money(bal, g)}</b>`;
    if (owedToMe.length) line += `<span class="muted"> from ${owedToMe.map((t) => esc(memberById(t.from).name)).join(', ')}</span>`;
  } else if (bal < 0) {
    line = `You owe <b class="neg">${money(-bal, g)}</b>`;
    if (mine.length) {
      line += `<span class="muted"> to ${mine.map((t) => esc(memberById(t.to).name)).join(', ')}</span>`;
      action = `<button class="btn btn-accent btn-sm" type="button" data-settle-mine>${icon('check')}Settle my part</button>`;
    }
  } else {
    line = g.entries.length ? 'You are all square. Nothing to pay.' : 'Nothing logged yet.';
  }
  return `<section class="me-bar ${a}">
    ${avatar(memberById(me), 'lg')}
    <div class="me-text"><span class="muted me-who">Viewing as ${esc(memberById(me).name)} · <button type="button" class="linklike" data-me-switch>switch</button></span><span class="me-line">${line}</span></div>
    ${action}
  </section>`;
}

function balancesCard(g) {
  const max = Math.max(1, ...g.balances.map((b) => Math.abs(b.net)));
  return `<div class="card"><div class="card-head"><h3 class="card-title">Balances</h3></div><div class="card-body bal">
    ${g.balances.map((b) => {
      const m = memberById(b.memberId);
      const w = (Math.abs(b.net) / max) * 50;
      const cls = b.net > 0 ? 'pos' : b.net < 0 ? 'neg' : 'zero';
      const caption = b.net > 0 ? 'gets back' : b.net < 0 ? 'owes' : 'all square';
      return `<div class="bal-row">${avatar(m)}
        <div style="min-width:0"><div class="n">${esc(m.name)}${youTag(m.id)}</div><div class="track">${b.net ? `<span class="${cls}" style="width:${w}%"></span>` : ''}</div></div>
        <div><div class="v ${cls}">${b.net ? money(b.net, g, { sign: true }) : money(0, g)}</div><div class="bal-caption" style="text-align:right">${caption}</div></div>
      </div>`;
    }).join('')}
  </div></div>`;
}

function settleCard(g) {
  let body;
  if (!g.entries.length) body = `<p class="muted" style="margin:0;font-size:14px">Suggested payments appear here once you log something.</p>`;
  else if (!g.transfers.length) body = `<div class="settled">${icon('party')}Everyone is settled up. Nice.</div>`;
  else body = `<div class="transfer-list">${g.transfers.map((t, i) => {
    const from = memberById(t.from); const to = memberById(t.to);
    return `<div class="tx">${avatar(from)}
      <div class="tx-main"><div class="who"><span><b>${esc(from.name)}</b></span>${icon('arrow', 'arrow')}<span>${esc(to.name)}</span></div><div class="amt">${money(t.amount, g)}</div></div>
      <button class="btn btn-ghost btn-xs" type="button" data-settle="${i}">Mark paid</button></div>`;
  }).join('')}</div>`;
  return `<div class="card"><div class="card-head"><h3 class="card-title">Settle up</h3>${g.transfers.length ? `<span class="muted" style="font-size:12.5px">${g.transfers.length} payment${g.transfers.length > 1 ? 's' : ''}</span>` : ''}</div><div class="card-body">${body}</div></div>`;
}

function peopleCard(g) {
  return `<div class="card people-card"><div class="card-head"><h3 class="card-title">People</h3></div><div class="card-body">
    <div class="people">${g.members.map((m) => `<div class="person" data-member="${esc(m.id)}">${avatar(m, 'sm')}<span class="n">${esc(m.name)}</span>
      <button class="icon-btn" type="button" data-rename="${esc(m.id)}" aria-label="Rename ${esc(m.name)}">${icon('pencil')}</button>
      <button class="icon-btn" type="button" data-remove="${esc(m.id)}" aria-label="Remove ${esc(m.name)}">${icon('trash')}</button></div>`).join('')}</div>
    <form class="add-person" id="addPerson"><input class="input" name="name" maxlength="32" placeholder="Add someone" autocomplete="off" aria-label="New person's name"><button class="btn btn-ghost btn-sm" type="submit">Add</button></form>
  </div></div>`;
}

function splitSummary(e) {
  const n = e.shares.length;
  if (n === state.group.members.length && e.splitMode === 'equal') return 'split equally';
  if (e.splitMode === 'equal') return `split ${n} way${n > 1 ? 's' : ''}`;
  return { exact: 'exact amounts', shares: 'by shares', percent: 'by percent' }[e.splitMode];
}

function renderActivity() {
  const g = state.group;
  const box = $('#activity');
  const q = state.query.trim().toLowerCase();
  const list = g.entries.filter((e) => (state.filter === 'all' || e.kind === state.filter) && (!q || `${e.title} ${e.note} ${memberById(e.paidBy).name} ${CATEGORY_META[e.category]?.label}`.toLowerCase().includes(q)));

  if (!g.entries.length) {
    box.innerHTML = `<div class="empty">
      <svg class="empty-art" viewBox="0 0 120 84" fill="none" aria-hidden="true">
        <rect x="18" y="10" width="56" height="70" rx="8" fill="var(--surface-2)" stroke="var(--line-strong)"/>
        <rect x="46" y="4" width="56" height="70" rx="8" fill="var(--surface)" stroke="var(--line-strong)"/>
        <path d="M58 22h32M58 32h22M58 42h28" stroke="var(--line-strong)" stroke-width="3" stroke-linecap="round"/>
        <circle cx="88" cy="58" r="10" fill="var(--accent-soft)" stroke="var(--accent)" stroke-width="2"/><path d="M84 58h8M88 54v8" stroke="var(--accent)" stroke-width="2" stroke-linecap="round"/>
      </svg>
      <h3>A clean slate</h3><p>Log the first expense and Evenly keeps a running tally of who owes whom.</p>
      <button class="btn btn-primary" type="button" data-new>${icon('plus')}Add the first expense</button></div>`;
    return;
  }
  if (!list.length) { box.innerHTML = `<div class="empty"><h3>No matches</h3><p>Try a different search or filter.</p></div>`; return; }

  const days = new Map();
  for (const e of list) { if (!days.has(e.date)) days.set(e.date, []); days.get(e.date).push(e); }
  box.innerHTML = [...days].map(([date, items]) => {
    const dayTotal = items.filter((e) => e.kind === 'expense').reduce((s, e) => s + e.amount, 0);
    return `<div class="day"><div class="day-head"><span>${esc(dayLabel(date))}</span><span>${dayTotal ? money(dayTotal) : ''}</span></div>
      ${items.map((e) => {
        const payer = memberById(e.paidBy);
        const meta = CATEGORY_META[e.category] ?? CATEGORY_META.general;
        if (e.kind === 'transfer') {
          const to = memberById(e.shares[0]?.memberId);
          return `<button class="entry transfer" type="button" data-entry="${esc(e.id)}"><span class="cat" style="--c:${meta.color}">${icon('transfer')}</span>
            <span style="min-width:0"><span class="t">${esc(payer.name)} paid ${esc(to.name)}</span><span class="s">${esc(e.title)}</span></span>
            <span class="amt"><span class="a">${money(e.amount)}</span><span class="m">payment</span></span></button>`;
        }
        return `<button class="entry" type="button" data-entry="${esc(e.id)}"><span class="cat" style="--c:${meta.color}">${icon(e.category)}</span>
          <span style="min-width:0"><span class="t">${esc(e.title)}</span><span class="s"><b>${esc(payer.id === myId() ? 'You' : payer.name)}</b> paid · ${esc(splitSummary(e))}${e.note ? ` · ${esc(e.note)}` : ''}</span></span>
          <span class="amt"><span class="a">${money(e.amount)}</span><span class="m">${esc(meta.label)}</span></span></button>`;
      }).join('')}</div>`;
  }).join('');
}

function bindGroup() {
  const g = state.group;
  $('#fab').addEventListener('click', () => openExpense());
  $('#settingsBtn').addEventListener('click', openSettings);
  $('#search').addEventListener('input', (e) => { state.query = e.target.value; renderActivity(); });

  const name = $('#gname');
  name.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); name.blur(); } if (e.key === 'Escape') { name.textContent = g.name; name.blur(); } });
  name.addEventListener('blur', async () => {
    const next = name.textContent.replace(/\s+/g, ' ').trim();
    if (!next || next === g.name) { name.textContent = g.name; return; }
    try { setGroup(await api('PATCH', `/api/groups/${g.id}`, { name: next })); toast('Group renamed'); }
    catch (ex) { name.textContent = g.name; toast(capitalise(ex.message), 'error'); }
  });

  $('#shareBtn').addEventListener('click', async () => {
    const url = `${location.origin}/g/${g.id}`;
    try {
      if (navigator.share && matchMedia('(pointer: coarse)').matches) await navigator.share({ title: g.name, url });
      else { await navigator.clipboard.writeText(url); toast('Invite link copied'); }
    } catch (ex) { if (ex.name !== 'AbortError') prompt('Copy this link', url); }
  });

  $('#addPerson').addEventListener('submit', async (e) => {
    e.preventDefault();
    const input = e.currentTarget.name;
    const n = input.value.trim();
    if (!n) return input.focus();
    try { const r = await api('POST', `/api/groups/${g.id}/members`, { name: n }); setGroup(r.group); toast(`${n} joined the group`); $('#addPerson input')?.focus(); }
    catch (ex) { toast(capitalise(ex.message), 'error'); }
  });
}

async function onGroupClick(e) {
  const g = state.group;
  if (!g) return;
  const t = e.target.closest('[data-entry],[data-new],[data-filter],[data-settle],[data-rename],[data-remove],[data-me],[data-me-switch],[data-settle-mine]');
  if (!t || !view.contains(t)) return;
  if (t.dataset.me) return setMe(t.dataset.me);
  if (t.dataset.meSwitch !== undefined) return setMe(null);
  if (t.dataset.settleMine !== undefined) {
    const mine = g.transfers.find((x) => x.from === myId());
    return mine && openTransfer(null, mine);
  }
  if (t.dataset.new !== undefined) return openExpense();
  if (t.dataset.entry) {
    const entry = g.entries.find((x) => x.id === t.dataset.entry);
    return entry.kind === 'transfer' ? openTransfer(entry) : openExpense(entry);
  }
  if (t.dataset.filter) {
    state.filter = t.dataset.filter;
    $$('[data-filter]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.filter === state.filter)));
    return renderActivity();
  }
  if (t.dataset.settle) return openTransfer(null, g.transfers[Number(t.dataset.settle)]);
  if (t.dataset.rename) {
    const row = t.closest('.person');
    const m = memberById(t.dataset.rename);
    const nameEl = row.querySelector('.n');
    const input = document.createElement('input');
    input.className = 'input'; input.value = m.name; input.maxLength = 32; input.style.height = '34px'; input.setAttribute('aria-label', 'New name');
    nameEl.replaceWith(input); input.focus(); input.select();
    let done = false;
    const finish = async (save) => {
      if (done) return; done = true;
      const v = input.value.trim();
      if (!save || !v || v === m.name) return renderGroup(false);
      try { setGroup(await api('PATCH', `/api/groups/${g.id}/members/${m.id}`, { name: v })); toast('Name updated'); }
      catch (ex) { toast(capitalise(ex.message), 'error'); renderGroup(false); }
    };
    input.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') finish(true); if (ev.key === 'Escape') finish(false); });
    input.addEventListener('blur', () => finish(true));
    return;
  }
  if (t.dataset.remove) {
    if (!t.classList.contains('armed')) {
      t.classList.add('armed'); t.style.color = 'var(--neg)'; t.style.opacity = 1; t.setAttribute('aria-label', 'Click again to remove');
      setTimeout(() => t.isConnected && (t.classList.remove('armed'), t.removeAttribute('style')), 2500);
      return toast('Click again to remove');
    }
    try { setGroup(await api('DELETE', `/api/groups/${g.id}/members/${t.dataset.remove}`)); toast('Removed'); }
    catch (ex) { toast(capitalise(ex.message), 'error'); }
  }
}

view.addEventListener('click', onGroupClick);

addEventListener('keydown', (e) => {
  if (!state.group || sheet.open || e.metaKey || e.ctrlKey || e.altKey) return;
  const tag = document.activeElement?.tagName;
  if (tag === 'INPUT' || tag === 'TEXTAREA' || document.activeElement?.isContentEditable) return;
  if (e.key === 'n' || e.key === 'N') { e.preventDefault(); openExpense(); }
  if (e.key === '/') { e.preventDefault(); $('#search')?.focus(); }
});

/* ---------------------------------------------------------- expense sheet */
let form = null;

function openExpense(entry = null) {
  const g = state.group;
  const values = {};
  if (entry && entry.splitMode !== 'equal') {
    for (const s of entry.shares) values[s.memberId] = entry.splitMode === 'exact' ? fromMinor(s.share, g.digits) : String(s.weight ?? '');
  }
  form = {
    id: entry?.id ?? null,
    amount: entry ? fromMinor(entry.amount, g.digits) : '',
    title: entry?.title ?? '',
    category: entry?.category ?? 'general',
    paidBy: entry?.paidBy ?? myId() ?? storageGet(`evenly.lastPayer.${g.id}`, g.members[0].id),
    date: entry?.date ?? todayISO(),
    note: entry?.note ?? '',
    mode: entry?.splitMode ?? 'equal',
    included: new Set(entry ? entry.shares.map((s) => s.memberId) : g.members.map((m) => m.id)),
    values,
    error: '',
  };
  if (!g.members.some((m) => m.id === form.paidBy)) form.paidBy = g.members[0].id;
  drawExpense();
  showSheet(() => (entry ? $('#fTitle') : $('#fAmount'))?.focus());
}

function showSheet(focus) {
  if (!sheet.open) sheet.showModal();
  requestAnimationFrame(focus);
}
sheet.addEventListener('click', (e) => { if (e.target === sheet) sheet.close(); });
sheet.addEventListener('close', () => { form = null; });

function computeSplit() {
  const g = state.group;
  const amount = toMinor(form.amount, g.digits) ?? 0;
  const ids = g.members.map((m) => m.id).filter((id) => form.included.has(id));
  const shares = Object.fromEntries(g.members.map((m) => [m.id, 0]));
  let status = { ok: ids.length > 0 && amount > 0, text: '' };
  if (!ids.length) return { shares, status: { ok: false, text: 'Pick at least one person', bad: true } };
  if (form.mode === 'equal') {
    allocate(amount, ids.map(() => 1)).forEach((v, i) => { shares[ids[i]] = v; });
    status.text = amount ? `${money(Math.floor(amount / ids.length))}${amount % ids.length ? '+' : ''} each` : '';
  } else if (form.mode === 'exact') {
    let sum = 0; let valid = true;
    for (const id of ids) { const raw = form.values[id] ?? ''; const v = raw === '' ? 0 : toMinor(raw, g.digits); if (v === null) valid = false; shares[id] = v ?? 0; sum += v ?? 0; }
    const left = amount - sum;
    status = valid && left === 0 && amount > 0 ? { ok: true, text: 'Adds up exactly', good: true }
      : !valid ? { ok: false, text: 'Check the amounts', bad: true }
      : { ok: false, text: left > 0 ? `${money(left)} left to assign` : `${money(-left)} over the total`, bad: true };
  } else {
    const weights = ids.map((id) => Math.max(0, Number(form.values[id] ?? (form.mode === 'shares' ? 1 : 0)) || 0));
    const total = weights.reduce((a, b) => a + b, 0);
    if (total > 0) allocate(amount, weights).forEach((v, i) => { shares[ids[i]] = v; });
    if (form.mode === 'percent') {
      const diff = Math.round((100 - total) * 100) / 100;
      status = diff === 0 ? { ok: amount > 0, text: '100% assigned', good: true } : { ok: false, text: diff > 0 ? `${diff}% left to assign` : `${-diff}% too much`, bad: true };
    } else {
      status = total > 0 ? { ok: amount > 0, text: `${total} share${total === 1 ? '' : 's'} in total` } : { ok: false, text: 'Give someone a share', bad: true };
    }
  }
  return { shares, status };
}

function seedValues(mode) {
  const g = state.group;
  const ids = g.members.map((m) => m.id).filter((id) => form.included.has(id));
  form.values = {};
  if (mode === 'shares') ids.forEach((id) => { form.values[id] = '1'; });
  if (mode === 'percent' && ids.length) {
    const base = Math.floor((100 / ids.length) * 100) / 100;
    ids.forEach((id, i) => { form.values[id] = String(i === ids.length - 1 ? Math.round((100 - base * (ids.length - 1)) * 100) / 100 : base); });
  }
  if (mode === 'exact') {
    const amount = toMinor(form.amount, g.digits);
    if (amount) allocate(amount, ids.map(() => 1)).forEach((v, i) => { form.values[ids[i]] = fromMinor(v, g.digits); });
  }
}

function drawExpense() {
  const g = state.group;
  const { shares, status } = computeSplit();
  const editing = Boolean(form.id);
  const sym = currencySymbol(g.currency);
  const placeholder = g.digits ? '0.00' : '0';
  sheet.innerHTML = `
    <form id="expenseForm" novalidate style="display:contents">
      <div class="sheet-head"><h2 id="sheetTitle">${editing ? 'Edit expense' : 'New expense'}</h2>
        <button class="icon-btn" type="button" data-close aria-label="Close">${icon('x')}</button></div>
      <div class="sheet-body">
        <div class="amount-hero">
          <label class="amount-line"><span class="cur">${esc(sym)}</span><span class="sr-only">Amount</span>
            <input class="amount-input" id="fAmount" inputmode="decimal" autocomplete="off" placeholder="${placeholder}" value="${esc(form.amount)}" data-key="amount"></label>
          <input class="input title-input" id="fTitle" maxlength="80" placeholder="What was it for?" value="${esc(form.title)}" data-key="title" aria-label="Description">
        </div>

        <div class="field"><span class="label">Category</span>
          <div class="cats" role="group" aria-label="Category">${state.meta.categories.map((c) => `<button type="button" class="cat-pill" style="--c:${CATEGORY_META[c].color}" data-cat="${c}" aria-pressed="${form.category === c}">${icon(c)}${esc(CATEGORY_META[c].label)}</button>`).join('')}</div>
        </div>

        <div class="field"><span class="label">Paid by</span>
          <div class="payers" role="group" aria-label="Paid by">${g.members.map((m) => `<button type="button" class="payer" data-payer="${esc(m.id)}" aria-pressed="${form.paidBy === m.id}">${avatar(m)}${esc(m.name)}</button>`).join('')}</div>
        </div>

        <div class="field">
          <div class="split-head"><span class="label">Split</span>
            <div class="seg" role="group" aria-label="Split method">${[['equal', 'Equally'], ['exact', 'Exact'], ['shares', 'Shares'], ['percent', 'Percent']].map(([k, l]) => `<button type="button" data-mode="${k}" aria-pressed="${form.mode === k}">${l}</button>`).join('')}</div>
          </div>
          <div class="split-list">${g.members.map((m) => {
            const on = form.included.has(m.id);
            const hasVal = form.mode !== 'equal' && on;
            const suffix = form.mode === 'percent' ? '%' : form.mode === 'shares' ? '×' : '';
            return `<div class="split-row ${on ? '' : 'off'} ${hasVal ? 'has-val' : ''}">
              <input type="checkbox" class="check" data-include="${esc(m.id)}" ${on ? 'checked' : ''} aria-label="Include ${esc(m.name)}">
              ${avatar(m, '')}
              <span class="n">${esc(m.name)}</span>
              ${hasVal ? `<input class="input val" data-val="${esc(m.id)}" data-key="val-${esc(m.id)}" inputmode="decimal" value="${esc(form.values[m.id] ?? '')}" placeholder="${form.mode === 'exact' ? placeholder : '0'}" aria-label="${esc(m.name)} ${form.mode}${suffix ? ` (${suffix})` : ''}">` : ''}
              <span class="share" data-share="${esc(m.id)}">${on ? money(shares[m.id]) : 'not included'}</span>
            </div>`;
          }).join('')}</div>
          <div class="remainder ${status.bad ? 'bad' : status.good ? 'good' : ''}" id="splitStatus"><span>${esc(status.text)}</span><span>${form.included.size}/${g.members.length} people</span></div>
        </div>

        <div class="meta-row">
          <label class="field"><span class="label">Date</span><input class="input" type="date" id="fDate" value="${esc(form.date)}" data-key="date" max="2100-12-31"></label>
          <label class="field"><span class="label">Note <span class="muted">(optional)</span></span><input class="input" id="fNote" maxlength="280" value="${esc(form.note)}" placeholder="Receipt number, details" data-key="note"></label>
        </div>
        ${form.error ? `<div class="form-error" role="alert">${esc(form.error)}</div>` : ''}
      </div>
      <div class="sheet-foot">
        ${editing ? `<button class="btn btn-danger btn-sm" type="button" id="deleteEntry">${icon('trash')}Delete</button>` : '<span></span>'}
        <div style="display:flex;gap:8px"><button class="btn btn-ghost" type="button" data-close>Cancel</button>
        <button class="btn btn-primary" type="submit" id="saveEntry">${editing ? 'Save changes' : 'Add expense'}</button></div>
      </div>
    </form>`;
  sizeAmount();
  bindExpense();
}

function sizeAmount() {
  const el = $('#fAmount');
  if (!el) return;
  const len = Math.max(2, (el.value || el.placeholder).length);
  // Shrink the type for long amounts so they never overflow a phone screen.
  const available = (el.closest('.amount-hero')?.clientWidth || 320) - 60;
  const size = Math.max(32, Math.min(68, available / (len * 0.62 + 0.4)));
  el.style.fontSize = `${size}px`;
  el.style.width = `${len * 0.62 + 0.4}em`;
}

function refreshSplit() {
  const { shares, status } = computeSplit();
  for (const el of $$('[data-share]', sheet)) {
    const id = el.dataset.share;
    el.textContent = form.included.has(id) ? money(shares[id]) : 'not included';
  }
  const st = $('#splitStatus');
  st.className = `remainder ${status.bad ? 'bad' : status.good ? 'good' : ''}`;
  st.firstElementChild.textContent = status.text;
}

function bindExpense() {
  const g = state.group;
  $$('[data-close]', sheet).forEach((b) => b.addEventListener('click', () => sheet.close()));
  $('#fAmount').addEventListener('input', (e) => {
    e.target.value = e.target.value.replace(g.digits ? /[^\d.,]/g : /[^\d,]/g, '');
    form.amount = e.target.value; sizeAmount(); refreshSplit();
  });
  $('#fTitle').addEventListener('input', (e) => { form.title = e.target.value; });
  $('#fNote').addEventListener('input', (e) => { form.note = e.target.value; });
  $('#fDate').addEventListener('input', (e) => { form.date = e.target.value; });
  $$('[data-cat]', sheet).forEach((b) => b.addEventListener('click', () => {
    form.category = b.dataset.cat;
    $$('[data-cat]', sheet).forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
  }));
  $$('[data-payer]', sheet).forEach((b) => b.addEventListener('click', () => {
    form.paidBy = b.dataset.payer;
    $$('[data-payer]', sheet).forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
  }));
  $$('[data-mode]', sheet).forEach((b) => b.addEventListener('click', () => {
    if (form.mode === b.dataset.mode) return;
    form.mode = b.dataset.mode; seedValues(form.mode); redraw(`[data-mode="${form.mode}"]`);
  }));
  $$('[data-include]', sheet).forEach((c) => c.addEventListener('change', () => {
    const id = c.dataset.include;
    if (c.checked) form.included.add(id); else form.included.delete(id);
    if (form.mode !== 'equal') seedValues(form.mode);
    redraw(`[data-include="${id}"]`);
  }));
  $$('[data-val]', sheet).forEach((inp) => inp.addEventListener('input', () => { form.values[inp.dataset.val] = inp.value; refreshSplit(); }));
  $('#expenseForm').addEventListener('submit', saveExpense);
  const del = $('#deleteEntry');
  if (del) armDelete(del, async () => {
    const r = await api('DELETE', `/api/groups/${g.id}/entries/${form.id}`);
    sheet.close(); setGroup(r); toast('Expense deleted');
  });
}

function redraw(focusSelector) {
  const scroll = $('.sheet-body', sheet)?.scrollTop ?? 0;
  drawExpense();
  $('.sheet-body', sheet).scrollTop = scroll;
  $(focusSelector, sheet)?.focus();
}

function armDelete(btn, action) {
  btn.addEventListener('click', async () => {
    if (!btn.classList.contains('armed')) {
      btn.classList.add('armed'); btn.lastChild.textContent = 'Confirm delete';
      setTimeout(() => { if (btn.isConnected) { btn.classList.remove('armed'); btn.lastChild.textContent = 'Delete'; } }, 3000);
      return;
    }
    btn.disabled = true;
    try { await action(); } catch (ex) { btn.disabled = false; toast(capitalise(ex.message), 'error'); }
  });
}

async function saveExpense(e) {
  e.preventDefault();
  const g = state.group;
  const amount = toMinor(form.amount, g.digits);
  const fail = (msg, sel) => { form.error = msg; redraw(sel); };
  if (!amount) return fail(g.digits ? 'Enter an amount, like 24.50.' : 'Enter a whole amount, like 2400.', '#fAmount');
  if (!form.title.trim()) return fail('Add a short description.', '#fTitle');
  const { status } = computeSplit();
  if (!status.ok) return fail(status.text || 'Check how the cost is split.');
  const ids = g.members.map((m) => m.id).filter((id) => form.included.has(id));
  const body = {
    kind: 'expense',
    title: form.title,
    amount: form.amount.replace(/,/g, ''),
    category: form.category,
    paidBy: form.paidBy,
    date: form.date || todayISO(),
    note: form.note,
    split: { mode: form.mode, participants: ids.map((memberId) => ({ memberId, ...(form.mode === 'equal' ? {} : { value: form.values[memberId] || '0' }) })) },
  };
  const btn = $('#saveEntry'); btn.disabled = true;
  try {
    storageSet(`evenly.lastPayer.${g.id}`, form.paidBy);
    const editing = Boolean(form.id);
    const r = editing ? await api('PUT', `/api/groups/${g.id}/entries/${form.id}`, body) : await api('POST', `/api/groups/${g.id}/entries`, body);
    sheet.close();
    setGroup(editing ? r : r.group);
    toast(editing ? 'Changes saved' : `${body.title.trim()} added`);
  } catch (ex) {
    btn.disabled = false;
    fail(capitalise(ex.message));
  }
}

/* --------------------------------------------------------- transfer sheet */
function openTransfer(entry = null, suggestion = null) {
  const g = state.group;
  const from = entry?.paidBy ?? suggestion?.from ?? g.members[0].id;
  const to = entry?.shares[0]?.memberId ?? suggestion?.to ?? g.members.find((m) => m.id !== from)?.id;
  const amount = entry ? fromMinor(entry.amount, g.digits) : suggestion ? fromMinor(suggestion.amount, g.digits) : '';
  let error = '';
  const draw = () => {
    const opts = (sel) => g.members.map((m) => `<option value="${esc(m.id)}" ${m.id === sel ? 'selected' : ''}>${esc(m.name)}</option>`).join('');
    sheet.innerHTML = `
    <form id="txForm" novalidate style="display:contents">
      <div class="sheet-head"><h2 id="sheetTitle">${entry ? 'Edit payment' : 'Record a payment'}</h2><button class="icon-btn" type="button" data-close aria-label="Close">${icon('x')}</button></div>
      <div class="sheet-body">
        <div class="amount-hero"><label class="amount-line"><span class="cur">${esc(currencySymbol(g.currency))}</span><span class="sr-only">Amount</span>
          <input class="amount-input" id="fAmount" inputmode="decimal" name="amount" value="${esc(amount)}" placeholder="${g.digits ? '0.00' : '0'}" autocomplete="off"></label>
          <span class="muted" style="font-size:13.5px">Money handed over outside the app, by cash or bank transfer.</span></div>
        <div class="meta-row">
          <label class="field"><span class="label">From</span><select class="select" name="from">${opts(from)}</select></label>
          <label class="field"><span class="label">To</span><select class="select" name="to">${opts(to)}</select></label>
        </div>
        <label class="field"><span class="label">Date</span><input class="input" type="date" name="date" value="${esc(entry?.date ?? todayISO())}"></label>
        ${error ? `<div class="form-error" role="alert">${esc(error)}</div>` : ''}
      </div>
      <div class="sheet-foot">
        ${entry ? `<button class="btn btn-danger btn-sm" type="button" id="deleteEntry">${icon('trash')}Delete</button>` : '<span></span>'}
        <div style="display:flex;gap:8px"><button class="btn btn-ghost" type="button" data-close>Cancel</button><button class="btn btn-accent" type="submit" id="saveTx">${entry ? 'Save' : 'Record payment'}</button></div>
      </div>
    </form>`;
    sizeAmount();
    $$('[data-close]', sheet).forEach((b) => b.addEventListener('click', () => sheet.close()));
    $('#fAmount').addEventListener('input', sizeAmount);
    const f = $('#txForm');
    f.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      const body = { kind: 'transfer', amount: f.amount.value.replace(/,/g, ''), paidBy: f.from.value, to: f.to.value, date: f.date.value || todayISO(), title: entry?.title ?? 'Settlement' };
      $('#saveTx').disabled = true;
      try {
        const r = entry ? await api('PUT', `/api/groups/${g.id}/entries/${entry.id}`, body) : await api('POST', `/api/groups/${g.id}/entries`, body);
        sheet.close();
        setGroup(entry ? r : r.group);
        toast(entry ? 'Payment updated' : `${memberById(body.paidBy).name} paid ${memberById(body.to).name}`);
      } catch (ex) { error = capitalise(ex.message); draw(); }
    });
    const del = $('#deleteEntry');
    if (del) armDelete(del, async () => { const r = await api('DELETE', `/api/groups/${g.id}/entries/${entry.id}`); sheet.close(); setGroup(r); toast('Payment deleted'); });
  };
  draw();
  showSheet(() => $('#saveTx')?.focus());
}

/* --------------------------------------------------------- settings sheet */
function forgetDeviceState(gid) {
  forgetGroup(gid);
  for (const key of [meKey(gid), `evenly.lastPayer.${gid}`]) {
    try { localStorage.removeItem(key); } catch { /* storage unavailable */ }
  }
}

function openSettings() {
  const g = state.group;
  const currencies = Object.keys(state.meta.currencies);
  let error = '';
  const draw = () => {
    sheet.innerHTML = `
    <form id="settingsForm" novalidate style="display:contents">
      <div class="sheet-head"><h2 id="sheetTitle">Group settings</h2><button class="icon-btn" type="button" data-close aria-label="Close">${icon('x')}</button></div>
      <div class="sheet-body">
        <label class="field"><span class="label">Group name</span><input class="input" name="name" maxlength="60" value="${esc(g.name)}" autocomplete="off"></label>
        <label class="field"><span class="label">Currency</span>
          <select class="select" name="currency">${currencies.map((c) => `<option ${c === g.currency ? 'selected' : ''}>${c}</option>`).join('')}</select>
          <span class="hint">Amounts are not converted. Switching between currencies with different decimals (like EUR and JPY) only works before the first expense.</span>
        </label>
        <div class="danger-zone">
          <div><b>Delete this group</b><span class="hint">Removes every expense and payment for everyone with the link. This cannot be undone.</span></div>
          <button class="btn btn-danger btn-sm" type="button" id="deleteGroup">${icon('trash')}Delete</button>
        </div>
        ${error ? `<div class="form-error" role="alert">${esc(error)}</div>` : ''}
      </div>
      <div class="sheet-foot"><span></span>
        <div style="display:flex;gap:8px"><button class="btn btn-ghost" type="button" data-close>Cancel</button><button class="btn btn-primary" type="submit" id="saveSettings">Save</button></div>
      </div>
    </form>`;
    $$('[data-close]', sheet).forEach((b) => b.addEventListener('click', () => sheet.close()));
    const f = $('#settingsForm');
    f.addEventListener('submit', async (ev) => {
      ev.preventDefault();
      $('#saveSettings').disabled = true;
      try {
        const r = await api('PATCH', `/api/groups/${g.id}`, { name: f.name.value, currency: f.currency.value });
        sheet.close(); setGroup(r); toast('Settings saved');
      } catch (ex) { error = capitalise(ex.message); draw(); }
    });
    armDelete($('#deleteGroup'), async () => {
      await api('DELETE', `/api/groups/${g.id}`);
      forgetDeviceState(g.id);
      sheet.close();
      state.group = null;
      navigate('/');
      toast('Group deleted');
    });
  };
  draw();
  showSheet(() => $('#settingsForm input')?.focus());
}

/* ----------------------------------------------------------------- boot */
(async function boot() {
  try { state.meta = await api('GET', '/api/meta'); }
  catch { state.meta = { currencies: { USD: {} }, categories: Object.keys(CATEGORY_META).filter((c) => c !== 'transfer') }; }
  route();
})();
