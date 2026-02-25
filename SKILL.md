---
name: browser-playwright-bridge
description: Run Playwright scripts that share OpenClaw browser's login state via CDP, with automatic conflict avoidance. Use when: (1) recording browser tool operations as reusable Playwright scripts, (2) running headless automation that needs existing cookies/sessions, (3) scheduling browser tasks in cron without CDP conflicts, (4) converting exploratory browser tool workflows into zero-token repeatable scripts.
---

# Browser ↔ Playwright Bridge

OpenClaw's browser tool and external Playwright scripts cannot share the same CDP connection simultaneously. This skill provides a lock-based bridge: stop OpenClaw browser → run Playwright with the same Chrome profile (cookies/login intact) → release for OpenClaw to reconnect.

## Architecture

```
Chrome (CDP :18800)  ←  shared user-data-dir (~/.openclaw/browser/openclaw/user-data)
       ↕ mutually exclusive
┌──────────────┐    ┌──────────────────┐
│ OpenClaw     │ OR │ Playwright script │
│ browser tool │    │ (zero token cost) │
└──────────────┘    └──────────────────┘
       ↕ managed by browser-lock.sh
```

## Setup

Install Playwright in the workspace (once):

```bash
cd <workspace> && npm install playwright
```

Copy `scripts/browser-lock.sh` to your workspace `scripts/` directory and make it executable:

```bash
chmod +x scripts/browser-lock.sh
```

## Usage

### Run a Playwright script (recommended)

```bash
./scripts/browser-lock.sh run scripts/my-task.js [args...]
```

This automatically: checks lock → stops OpenClaw browser → starts Chrome with CDP → runs script → cleans up → releases lock.

### Manual acquire/release

```bash
./scripts/browser-lock.sh acquire    # stop OpenClaw browser, start Chrome
node scripts/my-task.js              # run script(s)
./scripts/browser-lock.sh release    # kill Chrome, release lock
```

### Check status

```bash
./scripts/browser-lock.sh status
```

## Writing Playwright Scripts

Use `scripts/playwright-template.js` as starting point. Key rules:

```javascript
const { chromium } = require('playwright');

async function main() {
  // Connect to the standalone Chrome started by browser-lock.sh
  const browser = await chromium.connectOverCDP('http://127.0.0.1:18800');
  const context = browser.contexts()[0]; // reuse existing context (cookies!)
  const page = await context.newPage();

  try {
    // ... your automation ...
  } finally {
    await page.close();     // close only your tab
    // NEVER call browser.close() — it kills the entire Chrome
  }
}

main().then(() => process.exit(0)).catch(e => {
  console.error('❌', e.message);
  process.exit(1);
});
```

**Critical:**
- `browser.contexts()[0]` — reuse the existing context to inherit cookies/login
- `page.close()` only — never `browser.close()`
- Always `process.exit(0)` on success — Playwright keeps event loops alive otherwise
- CDP port defaults to 18800; override with `CDP_PORT` env var

## Workflow: Explore → Record → Replay

1. **Explore** — Use OpenClaw browser tool (snapshot/act) to figure out a new workflow
2. **Record** — Ask the agent to convert the steps into a Playwright script
3. **Replay** — Run via `browser-lock.sh run` — zero token cost, deterministic

## Cron / Scheduled Tasks

In cron tasks, call browser-lock.sh directly:

```bash
cd /path/to/workspace && ./scripts/browser-lock.sh run scripts/publish-task.js
```

The lock file (`/tmp/openclaw-browser.lock`) prevents concurrent browser access. If a lock is stale (owner process dead), it auto-recovers.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Lock held by PID xxx` | Run `./scripts/browser-lock.sh release` to force-release |
| Playwright connectOverCDP timeout | Ensure OpenClaw browser is stopped first (that's what `acquire` does) |
| `openclaw browser stop` doesn't work | Known issue; browser-lock.sh kills the process directly |
| Script hangs after completion | Add `process.exit(0)` at the end of your main function |
| Login expired | Use OpenClaw browser tool to re-login, then run scripts again |

## Environment Variables

| Var | Default | Description |
|-----|---------|-------------|
| `CDP_PORT` | 18800 | Chrome DevTools Protocol port |
| `CHROME_BIN` | auto-detect | Path to Chrome/Chromium binary |
