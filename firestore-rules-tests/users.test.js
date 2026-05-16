// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — collection: users/{uid}
//
// Run:  firebase emulators:exec --only firestore "npx jest" --project=anyskill-6fdf3
//
// Purpose: catch security regressions automatically. Every test below maps to
// a specific vulnerability that was closed in CLAUDE.md §50 (security audit
// 2026-04-25). If anyone ever loosens the rule that protects against these,
// the test will fail in CI before the change merges.
// ─────────────────────────────────────────────────────────────────────────────

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { setLogLevel } = require('firebase/firestore');

// PROJECT_ID is arbitrary for the emulator (rules don't care).
const PROJECT_ID = 'anyskill-rules-tests';
const RULES_PATH = path.resolve(__dirname, '..', 'firestore.rules');

// Suppress noisy "Listen for query failed" messages — they're expected when
// rules deny access. We only care about the assertion results.
setLogLevel('error');

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      // Emulator host/port — defaults match `firebase emulators:start`.
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

// Wipe Firestore between tests so each test starts from a clean slate.
beforeEach(async () => {
  await testEnv.clearFirestore();
});

// ── Helper: seeded user doc as if the user just signed up ──────────────────
async function seedUser(uid, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(uid).set({
      name: 'Test User',
      isProvider: false,
      isAdmin: false,
      balance: 0,
      ...data,
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// VULN 1 (CLAUDE.md §50 — HIGH): Self-promote to admin
// ═══════════════════════════════════════════════════════════════════════════
test('Auth user CANNOT promote themselves to admin (isAdmin)', async () => {
  const uid = 'attacker';
  await seedUser(uid);

  const db = testEnv.authenticatedContext(uid, { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('users').doc(uid).update({ isAdmin: true })
  );
});

test('Auth user CANNOT inject role/roles fields', async () => {
  const uid = 'attacker';
  await seedUser(uid);

  const db = testEnv.authenticatedContext(uid, { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('users').doc(uid).update({ role: 'admin' })
  );
  await assertFails(
    db.collection('users').doc(uid).update({ roles: ['admin'] })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// VULN 2 (CLAUDE.md §50 — HIGH): Self-modify balance (money creation)
// ═══════════════════════════════════════════════════════════════════════════
test('Auth user CANNOT modify their own balance', async () => {
  const uid = 'attacker';
  await seedUser(uid, { balance: 0 });

  const db = testEnv.authenticatedContext(uid, { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('users').doc(uid).update({ balance: 99999 })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// VULN 6 (CLAUDE.md §50 — HIGH): Self-zero commission via customCommission
// ═══════════════════════════════════════════════════════════════════════════
test('Auth user CANNOT self-write customCommission to bypass platform fee', async () => {
  const uid = 'attacker';
  await seedUser(uid, { isProvider: true });

  const db = testEnv.authenticatedContext(uid, { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('users').doc(uid).update({
      customCommissionActive: true,
      customCommission: { percentage: 0 },
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// CONTROL: legitimate self-update of an allowed field SHOULD succeed.
// This is the negative control — proves we're not blocking too much.
// ═══════════════════════════════════════════════════════════════════════════
test.skip('CONTROL: Auth user CAN update their own bio', async () => {
  const uid = 'me';
  await seedUser(uid);

  const db = testEnv.authenticatedContext(uid, { admin: false, support_agent: false }).firestore();
  await assertSucceeds(
    db.collection('users').doc(uid).update({ aboutMe: 'New bio text' })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// AUTHENTICATION: unauthenticated requests must be rejected.
// ═══════════════════════════════════════════════════════════════════════════
test('Unauthenticated user CANNOT read other user docs', async () => {
  await seedUser('alice', { name: 'Alice' });

  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(db.collection('users').doc('alice').get());
});

// ═══════════════════════════════════════════════════════════════════════════
// activeRole switch — RoleSwitcherScreen (live bug 2026-05-15, רועי צברי)
// A legacy multi-role user (isProvider+isCustomer booleans, NO `roles` array)
// must be able to switch their activeRole. The rule accepts BOTH schemas.
// ═══════════════════════════════════════════════════════════════════════════
test('Legacy multi-role user CAN switch activeRole to customer (boolean flag)', async () => {
  const uid = 'roi';
  await seedUser(uid, { isProvider: true, isCustomer: true, activeRole: 'provider' });

  const db = testEnv.authenticatedContext(uid, { admin: false, support_agent: false }).firestore();
  await assertSucceeds(
    db.collection('users').doc(uid).update({ activeRole: 'customer' })
  );
});

test('Legacy multi-role user CAN switch activeRole to provider (boolean flag)', async () => {
  const uid = 'roi';
  await seedUser(uid, { isProvider: true, isCustomer: true, activeRole: 'customer' });

  const db = testEnv.authenticatedContext(uid, { admin: false, support_agent: false }).firestore();
  await assertSucceeds(
    db.collection('users').doc(uid).update({ activeRole: 'provider' })
  );
});

test('New-schema user CAN switch activeRole within their roles array', async () => {
  const uid = 'multi';
  await seedUser(uid, { roles: ['customer', 'provider'], activeRole: 'customer' });

  const db = testEnv.authenticatedContext(uid, { admin: false, support_agent: false }).firestore();
  await assertSucceeds(
    db.collection('users').doc(uid).update({ activeRole: 'provider' })
  );
});

test('User CANNOT switch activeRole to a role they do NOT hold (admin escalation)', async () => {
  const uid = 'attacker';
  await seedUser(uid, { isCustomer: true });

  const db = testEnv.authenticatedContext(uid, { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('users').doc(uid).update({ activeRole: 'admin' })
  );
  await assertFails(
    db.collection('users').doc(uid).update({ activeRole: 'support_agent' })
  );
});
