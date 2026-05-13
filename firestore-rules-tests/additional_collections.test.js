// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — additional collections (Round 2)
//
// Maps to firestore.rules:
//   - volunteer_requests/{reqId}              line 961   — clientId ownership + admin update
//   - category_requests/{reqId}               line 974   — userId ownership + admin update
//   - community_requests/{reqId}              line 1247  — claim/visibility flow
//   - flash_auctions/{auctionId}              line 1575  — customer creates + status='searching'
//   - flash_auctions/{aId}/offers/{oId}       line 1600  — provider creates own offer
//
// All assertFails (attack scenarios) — assertSucceeds tests would hit the
// rules-engine flake we documented in the README.
// ─────────────────────────────────────────────────────────────────────────────

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
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

// ═══════════════════════════════════════════════════════════════════════════
// volunteer_requests — clientId ownership; only admin can update
// ═══════════════════════════════════════════════════════════════════════════
test('volunteer_requests: client CANNOT forge another user\'s clientId', async () => {
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('volunteer_requests').add({
      clientId: 'alice',  // forged
      title: 'Help me move',
      category: 'delivery',
    })
  );
});

test('volunteer_requests: random user CANNOT read someone else\'s request', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('volunteer_requests').doc('r1').set({
      clientId: 'alice', title: 'Private', category: 'delivery',
    });
  });

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(db.collection('volunteer_requests').doc('r1').get());
});

test('volunteer_requests: even owner CANNOT update own request (admin-only)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('volunteer_requests').doc('r1').set({
      clientId: 'alice', title: 'My request', status: 'open',
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('volunteer_requests').doc('r1').update({ status: 'closed' })
  );
});

test('volunteer_requests: nobody CAN delete (audit trail)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('volunteer_requests').doc('r1').set({
      clientId: 'alice', title: 'Old', status: 'completed',
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(db.collection('volunteer_requests').doc('r1').delete());
});

// ═══════════════════════════════════════════════════════════════════════════
// category_requests — userId ownership; admin approves
// ═══════════════════════════════════════════════════════════════════════════
test('category_requests: user CANNOT forge another\'s userId', async () => {
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('category_requests').add({
      userId: 'alice',  // forged
      description: 'New category for X',
      status: 'pending',
    })
  );
});

test('category_requests: random user CANNOT read someone else\'s request', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('category_requests').doc('r1').set({
      userId: 'alice', description: 'Private idea', status: 'pending',
    });
  });

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(db.collection('category_requests').doc('r1').get());
});

test('category_requests: owner CANNOT approve their own request (admin-only)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('category_requests').doc('r1').set({
      userId: 'alice', description: 'Make me a category', status: 'pending',
    });
  });

  // Alice tries to self-approve her own custom-category request
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('category_requests').doc('r1').update({
      status: 'approved',  // attempted self-approval
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// community_requests — open-tasks visibility flow
// ═══════════════════════════════════════════════════════════════════════════
test('community_requests: requester CANNOT forge another user\'s requesterId', async () => {
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('community_requests').add({
      requesterId: 'alice',  // forged
      title: 'Help with groceries',
      category: 'delivery',
      status: 'open',
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// flash_auctions — customer-only create with status='searching'
// ═══════════════════════════════════════════════════════════════════════════
test('flash_auctions: customer CANNOT forge customerId on create', async () => {
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('flash_auctions').add({
      customerId: 'alice',  // forged
      status: 'searching',
      notifiedProviderIds: [],
      pickupLocation: { lat: 32.0, lng: 34.7 },
    })
  );
});

test('flash_auctions: customer CANNOT create with non-empty notifiedProviderIds (CF-only)', async () => {
  // Attacker tries to bootstrap their own auction with a stacked notify list
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('flash_auctions').add({
      customerId: 'alice',
      status: 'searching',
      notifiedProviderIds: ['my_provider_friend'],  // not empty → blocked
      pickupLocation: { lat: 32.0, lng: 34.7 },
    })
  );
});

test('flash_auctions: customer CANNOT create with status other than searching', async () => {
  // Attacker tries to bypass the dispatch flow by creating an already-matched auction
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('flash_auctions').add({
      customerId: 'alice',
      status: 'matched',  // bypass attempt
      notifiedProviderIds: [],
    })
  );
});

test('flash_auctions: random user CANNOT read someone else\'s auction', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('flash_auctions').doc('a1').set({
      customerId: 'alice',
      status: 'searching',
      notifiedProviderIds: ['bob_provider', 'charlie_provider'],
    });
  });

  // eve is neither customer nor notified provider
  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(db.collection('flash_auctions').doc('a1').get());
});

// ═══════════════════════════════════════════════════════════════════════════
// flash_auctions/{aId}/offers/{oId} — provider creates own offer
// ═══════════════════════════════════════════════════════════════════════════
test('flash_auctions/offers: provider CANNOT forge providerId on offer', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('flash_auctions').doc('a1').set({
      customerId: 'alice', status: 'searching', notifiedProviderIds: ['bob', 'charlie'],
    });
  });

  // bob signed in but writes providerId='charlie' on the offer (impersonation)
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('flash_auctions').doc('a1')
      .collection('offers').doc('forged_offer')
      .set({
        providerId: 'charlie',  // impersonating
        status: 'pending',
        etaMinutes: 5,
        totalPrice: 100,
      })
  );
});

test('flash_auctions/offers: provider CANNOT create offer with status != pending', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('flash_auctions').doc('a1').set({
      customerId: 'alice', status: 'searching', notifiedProviderIds: ['bob'],
    });
  });

  // Provider tries to short-circuit by creating a pre-selected offer
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('flash_auctions').doc('a1')
      .collection('offers').doc('rigged')
      .set({
        providerId: 'bob',
        status: 'selected',  // bypass attempt
        etaMinutes: 5,
        totalPrice: 100,
      })
  );
});
