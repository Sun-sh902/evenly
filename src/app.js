// HTTP layer: a tiny router on top of node:http, JSON API + static frontend.

import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openStore, CATEGORIES } from './store.js';
import { CURRENCIES } from './money.js';

const PUBLIC_DIR = fileURLToPath(new URL('../public/', import.meta.url));
const MAX_BODY = 64 * 1024;
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
};

const SECURITY_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'X-Frame-Options': 'DENY',
  'Content-Security-Policy':
    "default-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
};

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function send(res, status, body, headers = {}) {
  const isJson = typeof body !== 'string' && !Buffer.isBuffer(body);
  const payload = body === undefined ? '' : isJson ? JSON.stringify(body) : body;
  res.writeHead(status, {
    ...SECURITY_HEADERS,
    ...(isJson && body !== undefined ? { 'Content-Type': 'application/json; charset=utf-8' } : {}),
    'Cache-Control': 'no-store',
    ...headers,
  });
  res.end(payload);
}

async function readJson(req) {
  const type = req.headers['content-type'] ?? '';
  if (!type.toLowerCase().startsWith('application/json')) throw new HttpError(415, 'send JSON with Content-Type: application/json');
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY) throw new HttpError(413, 'request body is too large');
    chunks.push(chunk);
  }
  const text = Buffer.concat(chunks).toString('utf8');
  if (!text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch {
    throw new HttpError(400, 'request body is not valid JSON');
  }
}

/**
 * Fixed-window rate limiter keyed by client and bucket. In-memory on purpose:
 * Evenly is a single-process app, and limits reset harmlessly on restart.
 */
export function createLimiter({ now = () => Date.now() } = {}) {
  const hits = new Map();
  const sweep = setInterval(() => {
    const t = now();
    for (const [k, v] of hits) if (v.reset <= t) hits.delete(k);
  }, 60_000);
  sweep.unref();
  return {
    take(key, limit, windowMs) {
      const t = now();
      let rec = hits.get(key);
      if (!rec || rec.reset <= t) {
        rec = { count: 0, reset: t + windowMs };
        hits.set(key, rec);
      }
      rec.count += 1;
      return rec.count <= limit ? 0 : Math.ceil((rec.reset - t) / 1000);
    },
    stop: () => clearInterval(sweep),
  };
}

function clientIp(req, trustProxy) {
  if (trustProxy) {
    const fwd = req.headers['x-forwarded-for'];
    if (typeof fwd === 'string' && fwd.trim()) return fwd.split(',')[0].trim();
  }
  return req.socket.remoteAddress ?? 'unknown';
}

function buildRoutes(store) {
  // [method, pattern, handler(params, req) => [status, body, headers?]]
  return [
    ['GET', /^\/api\/health$/, () => [200, { ok: true }]],
    ['GET', /^\/api\/meta$/, () => [200, { currencies: CURRENCIES, categories: CATEGORIES }]],
    ['POST', /^\/api\/groups$/, async (_p, req) => [201, store.createGroup(await readJson(req))]],
    ['GET', /^\/api\/groups\/([\w-]+)$/, ([id], req) => {
      // Weak ETag from the group's revision lets clients poll cheaply for changes.
      const etag = `W/"${id}-${store.groupRevision(id)}"`;
      if (req.headers['if-none-match'] === etag) return [304, undefined, { ETag: etag }];
      return [200, store.getGroup(id), { ETag: etag }];
    }],
    ['PATCH', /^\/api\/groups\/([\w-]+)$/, async ([id], req) => [200, store.updateGroup(id, await readJson(req))]],
    ['DELETE', /^\/api\/groups\/([\w-]+)$/, ([id]) => (store.deleteGroup(id), [204])],
    ['POST', /^\/api\/groups\/([\w-]+)\/members$/, async ([id], req) => [201, store.addMember(id, await readJson(req))]],
    ['PATCH', /^\/api\/groups\/([\w-]+)\/members\/([\w-]+)$/, async ([id, mid], req) => [200, store.renameMember(id, mid, await readJson(req))]],
    ['DELETE', /^\/api\/groups\/([\w-]+)\/members\/([\w-]+)$/, ([id, mid]) => [200, store.removeMember(id, mid)]],
    ['POST', /^\/api\/groups\/([\w-]+)\/entries$/, async ([id], req) => [201, store.addEntry(id, await readJson(req))]],
    ['PUT', /^\/api\/groups\/([\w-]+)\/entries\/([\w-]+)$/, async ([id, eid], req) => [200, store.updateEntry(id, eid, await readJson(req))]],
    ['DELETE', /^\/api\/groups\/([\w-]+)\/entries\/([\w-]+)$/, ([id, eid]) => [200, store.deleteEntry(id, eid)]],
    ['GET', /^\/api\/groups\/([\w-]+)\/export\.csv$/, ([id]) => {
      const csv = store.exportCsv(id);
      return [200, csv, { 'Content-Type': 'text/csv; charset=utf-8', 'Content-Disposition': `attachment; filename="evenly-${id}.csv"` }];
    }],
  ];
}

async function serveStatic(req, res, pathname) {
  // Client side routes all resolve to the single page app shell.
  let rel;
  try {
    rel = pathname === '/' || /^\/g\/[\w-]+\/?$/.test(pathname) ? 'index.html' : decodeURIComponent(pathname.slice(1));
  } catch {
    return send(res, 400, { error: 'bad url' });
  }
  const file = normalize(join(PUBLIC_DIR, rel));
  if (!file.startsWith(PUBLIC_DIR) || rel.split(/[\\/]/).includes('..')) return send(res, 404, { error: 'not found' });
  try {
    const info = await stat(file);
    if (!info.isFile()) throw new Error('not a file');
    const lastModified = new Date(Math.floor(info.mtimeMs / 1000) * 1000).toUTCString();
    const headers = {
      ...SECURITY_HEADERS,
      'Content-Type': MIME[extname(file)] ?? 'application/octet-stream',
      'Cache-Control': 'no-cache',
      'Last-Modified': lastModified,
    };
    const since = Date.parse(req.headers['if-modified-since'] ?? '');
    if (!Number.isNaN(since) && since >= Date.parse(lastModified)) {
      res.writeHead(304, headers);
      return res.end();
    }
    const body = await readFile(file);
    res.writeHead(200, headers);
    res.end(req.method === 'HEAD' ? undefined : body);
  } catch {
    send(res, 404, { error: 'not found' });
  }
}

export const DEFAULT_LIMITS = { writesPerMinute: 120, groupsPerHour: 30 };

export function createApp({ dbFile = ':memory:', logger = null, limits = DEFAULT_LIMITS, trustProxy = false } = {}) {
  const store = openStore(dbFile);
  const routes = buildRoutes(store);
  const limiter = createLimiter();

  function checkLimits(req, pathname) {
    if (req.method === 'GET' || req.method === 'HEAD' || !limits) return;
    const ip = clientIp(req, trustProxy);
    let wait = limiter.take(`w:${ip}`, limits.writesPerMinute, 60_000);
    if (!wait && req.method === 'POST' && pathname === '/api/groups') {
      wait = limiter.take(`g:${ip}`, limits.groupsPerHour, 3_600_000);
    }
    if (wait) {
      const err = new HttpError(429, 'too many requests, slow down a little');
      err.retryAfter = wait;
      throw err;
    }
  }

  const server = createServer(async (req, res) => {
    const started = Date.now();
    let pathname;
    try {
      pathname = new URL(req.url, 'http://localhost').pathname;
    } catch {
      return send(res, 400, { error: 'bad url' });
    }
    try {
      if (pathname.startsWith('/api/')) {
        const matching = routes.filter(([, re]) => re.test(pathname));
        if (!matching.length) throw new HttpError(404, 'no such endpoint');
        const route = matching.find(([m]) => m === req.method);
        if (!route) {
          return send(res, 405, { error: 'method not allowed' }, { Allow: [...new Set(matching.map(([m]) => m))].join(', ') });
        }
        checkLimits(req, pathname);
        const params = pathname.match(route[1]).slice(1);
        const [status, body, headers] = await route[2](params, req);
        send(res, status, status === 204 || status === 304 ? undefined : body, headers);
      } else if (req.method === 'GET' || req.method === 'HEAD') {
        await serveStatic(req, res, pathname);
      } else {
        send(res, 405, { error: 'method not allowed' }, { Allow: 'GET, HEAD' });
      }
    } catch (err) {
      const status = err.status ?? 500;
      if (status >= 500) logger?.error?.(err);
      send(
        res,
        status,
        { error: status >= 500 ? 'something went wrong' : err.message, ...(err.field ? { field: err.field } : {}) },
        err.retryAfter ? { 'Retry-After': String(err.retryAfter) } : {},
      );
    } finally {
      logger?.info?.(`${req.method} ${pathname} ${res.statusCode} ${Date.now() - started}ms`);
    }
  });

  server.on('close', () => {
    limiter.stop();
    store.close();
  });
  return { server, store };
}
