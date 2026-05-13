// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — collection: jobs/{jobId}
//
// Maps to firestore.rules lines 394-414 (the jobs/{jobId} rule block).
// CLAUDE.md §4 (escrow lifecycle) + §50 (security audit).
//
// Critical invariants protected:
//   - Cross-user read isolation (only customer / expert / admin can read)
//   - Customer must author their own job (customerId == auth.uid)
//   - Self-booking blocked (customerId != expertId)
//   - Random user cannot create or update someone else's job
//   - No client-side deletes (historical record)
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

// ── Seed a job doc bypassing rules (test setup uses admin SDK) ──────────────
async function seedJob(jobId, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('jobs').doc(jobId).set({
      status: 'paid_escrow',
      totalAmount: 200,
      createdAt: new Date(),
      ...data,
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// READ ISOLATION
// ═══════════════════════════════════════════════════════════════════════════
test.skip('Customer CAN read their own job (control)', async () => {
  await seedJob('job1', { customerId: 'alice', expertId: 'bob' });

  const db = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).firestore();
  await assertSucceeds(db.collection('jobs').doc('job1').get());
});

test.skip('Expert CAN read their own job (control)', async () => {
  await seedJob('job1', { customerId: 'alice', expertId: 'bob' });

  const db = testEnv.authenticatedContext('bob', { admin: false, support_agent: false }).firestore();
  await assertSucceeds(db.collection('jobs').doc('job1').get());
});

test('Random third-party user CANNOT read someone else\'s job', async () => {
  await seedJob('job1', { customerId: 'alice', expertId: 'bob' });

  const db = testEnv.authenticatedContext('eve', { admin: false, support_agent: false }).firestore();
  await assertFails(db.collection('jobs').doc('job1').get());
});

test('Unauthenticated user CANNOT read jobs', async () => {
  await seedJob('job1', { customerId: 'alice', expertId: 'bob' });

  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(db.collection('jobs').doc('job1').get());
});

// ═══════════════════════════════════════════════════════════════════════════
// CREATE AUTHORSHIP — customer must author their own job
// ═══════════════════════════════════════════════════════════════════════════
test('User CANNOT create a job claiming a different customerId', async () => {
  // alice signed in but tries to create a job in bob's name
  const db = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('jobs').doc('forged').set({
      customerId: 'bob',     // forged — not auth.uid
      expertId: 'charlie',
      totalAmount: 200,
      status: 'paid_escrow',
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// SELF-BOOKING BLOCK — anti-fraud (CLAUDE.md §9b Law 13)
// ═══════════════════════════════════════════════════════════════════════════
test('User CANNOT self-book (customerId == expertId)', async () => {
  const db = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('jobs').doc('selfbook').set({
      customerId: 'alice',
      expertId: 'alice',     // same user — would enable fake reviews
      totalAmount: 200,
      status: 'paid_escrow',
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// UPDATE ISOLATION
// ═══════════════════════════════════════════════════════════════════════════
test('Random user CANNOT update someone else\'s job', async () => {
  await seedJob('job1', { customerId: 'alice', expertId: 'bob' });

  const db = testEnv.authenticatedContext('eve', { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('jobs').doc('job1').update({ status: 'completed' })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// DELETE BLOCKED — historical records cannot be erased
// ═══════════════════════════════════════════════════════════════════════════
test('Even the customer CANNOT delete their own job', async () => {
  await seedJob('job1', { customerId: 'alice', expertId: 'bob' });

  const db = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).firestore();
  await assertFails(db.collection('jobs').doc('job1').delete());
});
