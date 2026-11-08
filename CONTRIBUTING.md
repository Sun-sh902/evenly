# Contributing

Thanks for helping out. Evenly stays deliberately small, so a few ground rules keep it that way.

## Setup

```bash
git clone https://github.com/Sun-sh902/evenly.git
cd evenly
npm run dev        # restarts on file changes, http://127.0.0.1:4173
npm test
```

Node.js 22.13 or newer is all you need. There is no `npm install` step.

## Guidelines

- **No runtime dependencies.** The server uses only Node built-ins and the frontend is plain JavaScript without a build step. If a change seems to need a package, open an issue first.
- **Money is integer minor units.** Never store or add floats. Use `allocate()` in `src/money.js` for any split so parts always sum to the total.
- **Every API change needs a test** in `test/api.test.js`. Pure logic goes in `test/ledger.test.js`.
- **Keep the UI accessible.** Real buttons for actions, labels on inputs, visible focus, and it should work in both light and dark themes and at 375px wide.
- Match the existing code style: two-space indentation, single quotes, semicolons.

## Pull requests

1. Fork and branch from `main`.
2. Keep each PR to one focused change, and describe what changed and why.
3. Make sure `npm test` passes; CI runs it on Node 22 and 24 and also builds the Docker image.

## Reporting security issues

Please don't open a public issue for security problems. Use GitHub's private vulnerability reporting on this repository instead.
