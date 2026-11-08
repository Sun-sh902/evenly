import { createApp } from './app.js';
import { fileURLToPath } from 'node:url';

const port = Number(process.env.PORT ?? 4173);
const host = process.env.HOST ?? '127.0.0.1';
const dbFile = process.env.EVENLY_DB ?? fileURLToPath(new URL('../data/evenly.db', import.meta.url));

const { server } = createApp({
  dbFile,
  trustProxy: process.env.TRUST_PROXY === '1',
  limits:
    process.env.EVENLY_RATE_LIMIT === 'off'
      ? null
      : {
          writesPerMinute: Number(process.env.EVENLY_WRITES_PER_MINUTE ?? 120),
          groupsPerHour: Number(process.env.EVENLY_GROUPS_PER_HOUR ?? 30),
        },
  logger: { info: (m) => process.env.QUIET || console.log(m), error: (e) => console.error(e) },
});

server.listen(port, host, () => {
  console.log(`Evenly is running at http://${host}:${port}`);
});

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => server.close(() => process.exit(0)));
}
