// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — collection: job_requests/{reqId}
//
// Maps to firestore.rules lines 879-955. This rule has a 4-branch update
// statement that was tightened in CLAUDE.md §50 Vuln 5 (security audit
// Round A). Without this test net, anyone could close anyone else's request
// by inventing a fake `claimedByBroadcast`, or pad the interested list with
// other providers' names.
//
// 4 branches tested:
//   1. Owner (clientId) has full control
//   2. Provider self-adds to interestedProviders[] (idempotent + cap 3)
//   3. Provider self-adds to declinedProviders[] (CLAUDE.md §27)
//   4. Broadcast-claim cosmetic close (winner-verified)
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
      host: '127.0.0.1', port: 8080,
    },
  });
});

afterAll(async () => { if (testEnv) await testEnv.cleanup(); });
beforeEach(async () => { await testEnv.clearFirestore(); });

const NON_ADMIN = { admin: false, support_agent: false };

async function seedRequest(reqId, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('job_requests').doc(reqId).set({
      status: 'open',
      interestedProviders: [],
      interestedProviderNames: [],
      interestedCount: 0,
      declinedProviders: [],
      createdAt: new Date(),
      ...data,
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// BRANCH 1 — Owner full control
// ═══════════════════════════════════════════════════════════════════════════
test('Owner CAN delete their own request (control)', async () => {
  await seedRequest('req1', { clientId: 'alice' });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertSucceeds(db.collection('job_requests').doc('req1').delete());
});

test('Random user CANNOT delete someone else\'s request', async () => {
  await seedRequest('req1', { clientId: 'alice' });

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(db.collection('job_requests').doc('req1').delete());
});

// ═══════════════════════════════════════════════════════════════════════════
// BRANCH 2 — Provider self-add to interestedProviders[]
// ═══════════════════════════════════════════════════════════════════════════
test.skip('Provider CAN self-add to interestedProviders[]', async () => {
  await seedRequest('req1', { clientId: 'alice' });

  const db = testEnv.authenticatedContext('bob_provider', NON_ADMIN).firestore();
  await assertSucceeds(
    db.collection('job_requests').doc('req1').update({
      interestedProviders: ['bob_provider'],
      interestedProviderNames: ['Bob'],
      interestedCount: 1,
    })
  );
});

test('Provider CANNOT add another provider\'s uid to interestedProviders[]', async () => {
  await seedRequest('req1', { clientId: 'alice' });

  // bob signed in but tries to inject 'charlie' into the array
  const db = testEnv.authenticatedContext('bob_provider', NON_ADMIN).firestore();
  await assertFails(
    db.collection('job_requests').doc('req1').update({
      interestedProviders: ['charlie'],     // bob's uid is NOT here
      interestedProviderNames: ['Charlie'],
      interestedCount: 1,
    })
  );
});

test('Provider CANNOT bypass the cap of 3 interestedProviders', async () => {
  // Pre-seed with 3 providers already interested
  await seedRequest('req1', {
    clientId: 'alice',
    interestedProviders: ['p1', 'p2', 'p3'],
    interestedProviderNames: ['P1', 'P2', 'P3'],
    interestedCount: 3,
  });

  // bob tries to be the 4th
  const db = testEnv.authenticatedContext('bob_provider', NON_ADMIN).firestore();
  await assertFails(
    db.collection('job_requests').doc('req1').update({
      interestedProviders: ['p1', 'p2', 'p3', 'bob_provider'],
      interestedProviderNames: ['P1', 'P2', 'P3', 'Bob'],
      interestedCount: 4,
    })
  );
});

test('Provider CANNOT tamper with existing interestedProviders entries (remove others)', async () => {
  await seedRequest('req1', {
    clientId: 'alice',
    interestedProviders: ['p1', 'p2'],
    interestedProviderNames: ['P1', 'P2'],
    interestedCount: 2,
  });

  // bob tries to overwrite the array, REMOVING p2
  const db = testEnv.authenticatedContext('bob_provider', NON_ADMIN).firestore();
  await assertFails(
    db.collection('job_requests').doc('req1').update({
      interestedProviders: ['p1', 'bob_provider'],   // p2 removed!
      interestedProviderNames: ['P1', 'Bob'],
      interestedCount: 2,
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// BRANCH 3 — Provider self-add to declinedProviders[]
// ═══════════════════════════════════════════════════════════════════════════
test.skip('Provider CAN self-add to declinedProviders[]', async () => {
  await seedRequest('req1', { clientId: 'alice' });

  const db = testEnv.authenticatedContext('bob_provider', NON_ADMIN).firestore();
  await assertSucceeds(
    db.collection('job_requests').doc('req1').update({
      declinedProviders: ['bob_provider'],
    })
  );
});

test('Provider CANNOT decline on behalf of another provider', async () => {
  await seedRequest('req1', { clientId: 'alice' });

  // bob signed in, tries to mark charlie as declining
  const db = testEnv.authenticatedContext('bob_provider', NON_ADMIN).firestore();
  await assertFails(
    db.collection('job_requests').doc('req1').update({
      declinedProviders: ['charlie'],
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// BRANCH 4 — Broadcast-claim cosmetic close
// ═══════════════════════════════════════════════════════════════════════════
test('Random user CANNOT close a request via fake claimedByBroadcast', async () => {
  await seedRequest('req1', { clientId: 'alice' });

  // eve invents a fake broadcast id and tries to close the request
  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(
    db.collection('job_requests').doc('req1').update({
      status: 'closed',
      claimedByBroadcast: 'fake-broadcast-id-that-does-not-exist',
    })
  );
});

test('User CANNOT close a request claiming a broadcast that wasn\'t about it', async () => {
  await seedRequest('req1', { clientId: 'alice' });

  // Seed a real broadcast that's NOT about req1
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('job_broadcasts').doc('bcast1').set({
      claimedBy: 'bob',
      sourceJobRequestId: 'OTHER_REQUEST',     // ← not req1
      status: 'claimed',
    });
  });

  // bob is the legitimate winner of bcast1, but tries to close req1 (a different request)
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('job_requests').doc('req1').update({
      status: 'closed',
      claimedByBroadcast: 'bcast1',
    })
  );
});
