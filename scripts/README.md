# `scripts/` — One-off operational scripts

Stand-alone Node.js scripts for seeding test data, cleanup, and
load-testing against Firebase. **These are NOT part of the app build** —
they're CLI utilities for the developer/admin to run manually.

All scripts use **firebase-admin** (Admin SDK) which bypasses Firestore
rules. They REQUIRE valid credentials. Never run them with production
credentials unless you intend to mutate production data.

## Setup (one-time, per machine)

Each script needs `firebase-admin` installed at the project root:

```bash
npm install firebase-admin
```

And a service-account JSON file. Two ways:

```bash
# Option A: env var (recommended)
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json

# Option B: place the file at functions/service-account.json
# (already in .gitignore)
```

Get the service-account JSON from:
**Firebase Console → Project Settings → Service accounts →
Generate new private key**.

⚠️ Treat that JSON like a database password. Never commit it.

## Scripts

### `seed_test_data.js`

Seeds **2,000 fake users** (1,000 customers + 1,000 providers) into Firestore
for load testing. Each doc is tagged `isDemo: true` so it can be cleanly
removed afterwards by `cleanup_test_data.js`.

**When to use**: stress-testing a CF, search-ranking algorithm, or admin
panel pagination at realistic scale.

**Run**:
```bash
GOOGLE_APPLICATION_CREDENTIALS=./functions/service-account.json node scripts/seed_test_data.js
```

⚠️ **Never run against production**. Only against the staging project
(`anyskill-staging`) or a local emulator.

---

### `cleanup_test_data.js`

Deletes every doc in `users` where `isDemo: true`. Processes in batches
of 500 (Firestore's batched-write limit).

**When to use**: after a load-testing run.

**Run**:
```bash
GOOGLE_APPLICATION_CREDENTIALS=./functions/service-account.json node scripts/cleanup_test_data.js
```

⚠️ This script ONLY targets `isDemo: true` records. It will not affect
real users. Still — never run with prod credentials unless you've
double-checked.

---

### `stress_test.js`

Simulates **50 concurrent escrow flows** end-to-end:
1. Create a `job_requests` doc
2. Create a `jobs` doc (`status: paid_escrow`)
3. Update job → `expert_completed`
4. Call `processPaymentRelease` Cloud Function via REST

Concurrency is capped via a semaphore. Used to validate that the
escrow + payment-release pipeline holds up under realistic load.

**When to use**: before a major release, or after refactoring the
escrow flow / `processPaymentRelease` CF.

**Run**:
```bash
GOOGLE_APPLICATION_CREDENTIALS=./functions/service-account.json node scripts/stress_test.js
```

Reports per-flow latency + success/failure rate at the end.

⚠️ Generates real auth tokens via Admin SDK and hits the actual deployed
CFs. Run against staging, not prod.

## What's NOT in this folder

- **CI tests** — those live in `firestore-rules-tests/` (rules) and
  `functions/__tests__/` (CFs).
- **App seeding via admin UI** — categories/banners/etc. are seeded via
  the admin panel UI; not via these scripts.
- **Migration scripts** — those live in `functions/scripts/` so they
  can be invoked from `firebase functions:shell`.

## Adding a new script

1. Use the same shebang `'use strict';` style as the existing scripts.
2. Document inputs (env vars + flags) at the top of the file.
3. Always tag synthetic data with `isDemo: true` so cleanup can find it.
4. Include a `--dry-run` flag for any destructive operation.
5. Add a section to this README with WHEN to use + the run command.

## Why not in `package.json` scripts?

These scripts use `firebase-admin` which is a heavy dependency
(50+ MB). The main project's `package.json` doesn't depend on it
to keep the dev setup lean. Scripts are run ad-hoc with explicit
environment setup.

If a script becomes part of CI or recurring ops → move it to
`functions/scripts/` where `firebase-admin` is already a dependency.
