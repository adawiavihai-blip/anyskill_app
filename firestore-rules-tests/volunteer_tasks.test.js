// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — collection: volunteer_tasks/{taskId}
//
// Maps to firestore.rules lines 1323-1339.
// CLAUDE.md §7 (volunteer task lifecycle + anti-fraud) + §50.
//
// Critical invariants protected:
//   - Provider authorship — providerId MUST match auth.uid
//   - Self-assignment block — clientId MUST != providerId (prevents XP farming)
//   - Read isolation — only the two parties (or admin) can read
//   - No client-side deletes
// ─────────────────────────────────────────────────────────────────────────────

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { setLogLevel } = require('firebase/firestore');

const PROJECT_ID = 'anyskill-rules-tests';
const RULES_PATH = path.resolve(__dirname, '..', 'firestore.rules');

setLogLevel('error');

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

// ═══════════════════════════════════════════════════════════════════════════
// CONTROL: legitimate volunteer task creation succeeds
// ═══════════════════════════════════════════════════════════════════════════
test('Provider CAN create a volunteer task for someone else (control)', async () => {
  const db = testEnv.authenticatedContext('bob_provider', { admin: false, support_agent: false }).firestore();
  await assertSucceeds(
    db.collection('volunteer_tasks').add({
      providerId: 'bob_provider',     // matches auth.uid
      clientId:   'alice_needy',       // someone else
      category: 'repair',
      description: 'Fix the AC',
      status: 'accepted',
      createdAt: new Date(),
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// SELF-ASSIGNMENT BLOCK — providerId == clientId (XP farming attempt)
// CLAUDE.md §7.3 anti-fraud rule #1
// ═══════════════════════════════════════════════════════════════════════════
test('User CANNOT assign themselves as both provider AND client (XP farm)', async () => {
  const db = testEnv.authenticatedContext('attacker', { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('volunteer_tasks').add({
      providerId: 'attacker',
      clientId:   'attacker',          // SAME user — XP farming
      category: 'repair',
      description: 'Self-task to farm XP',
      status: 'accepted',
      createdAt: new Date(),
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER FORGERY — providerId != auth.uid
// ═══════════════════════════════════════════════════════════════════════════
test('User CANNOT create a task claiming a different providerId', async () => {
  // eve is signed in but writes "bob_provider" as the providerId
  const db = testEnv.authenticatedContext('eve', { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('volunteer_tasks').add({
      providerId: 'bob_provider',     // forged
      clientId:   'alice_needy',
      category: 'repair',
      description: 'Forged task',
      status: 'accepted',
      createdAt: new Date(),
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// READ ISOLATION — only the two parties (or admin) can read
// ═══════════════════════════════════════════════════════════════════════════
test('Random third party CANNOT read someone else\'s volunteer task', async () => {
  // Seed a task between alice (client) and bob (provider)
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('volunteer_tasks').doc('task1').set({
      providerId: 'bob_provider',
      clientId:   'alice_needy',
      category: 'repair',
      status: 'accepted',
    });
  });

  // eve tries to peek
  const db = testEnv.authenticatedContext('eve', { admin: false, support_agent: false }).firestore();
  await assertFails(db.collection('volunteer_tasks').doc('task1').get());
});

// ═══════════════════════════════════════════════════════════════════════════
// DELETE BLOCKED — historical XP/badge audit trail
// ═══════════════════════════════════════════════════════════════════════════
test('Even the participant CANNOT delete a volunteer task', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('volunteer_tasks').doc('task1').set({
      providerId: 'bob_provider',
      clientId:   'alice_needy',
      category: 'repair',
      status: 'accepted',
    });
  });

  const db = testEnv.authenticatedContext('bob_provider', { admin: false, support_agent: false }).firestore();
  await assertFails(db.collection('volunteer_tasks').doc('task1').delete());
});
