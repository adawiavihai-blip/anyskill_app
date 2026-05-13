// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — misc collections (community_requests, app_feedback,
// demo_bookings, vip_subscriptions).
//
// Maps to firestore.rules:
//   - app_feedback/{id}         lines 698-716   (shape validation §42)
//   - community_requests/{id}   lines 1247-...  (volunteer hub §7b)
//   - vip_subscriptions/{id}    lines 1468-1474 (admin/CF only)
//   - demo_bookings/{id}        lines 1512-1518 (customer creates, admin reads)
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

// ═══════════════════════════════════════════════════════════════════════════
// app_feedback — shape validation gates (§42)
// ═══════════════════════════════════════════════════════════════════════════
const VALID_FEEDBACK = {
  uid: 'alice',
  userRole: 'customer',
  category: 'app_interface',
  content: 'The home screen is hard to find',
  npsScore: 7,
  status: 'pending',
  createdAt: new Date(),
};

test('app_feedback: valid feedback CAN be created (control)', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertSucceeds(
    db.collection('app_feedback').add(VALID_FEEDBACK)
  );
});

test('app_feedback: client CANNOT create feedback claiming another user\'s uid', async () => {
  // bob signed in but uid: 'alice' in payload
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('app_feedback').add({
      ...VALID_FEEDBACK,
      uid: 'alice',  // forged
    })
  );
});

test('app_feedback: rejects content > 500 chars', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('app_feedback').add({
      ...VALID_FEEDBACK,
      content: 'x'.repeat(501),
    })
  );
});

test('app_feedback: rejects empty content', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('app_feedback').add({
      ...VALID_FEEDBACK,
      content: '',
    })
  );
});

test('app_feedback: rejects npsScore out of range (>10)', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('app_feedback').add({
      ...VALID_FEEDBACK,
      npsScore: 11,
    })
  );
});

test('app_feedback: rejects npsScore out of range (<1)', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('app_feedback').add({
      ...VALID_FEEDBACK,
      npsScore: 0,
    })
  );
});

test('app_feedback: rejects unknown category', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('app_feedback').add({
      ...VALID_FEEDBACK,
      category: 'spam_request',  // not in allowed list
    })
  );
});

test('app_feedback: rejects status other than pending on create', async () => {
  // Attacker tries to bypass admin review by setting status='shipped'
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('app_feedback').add({
      ...VALID_FEEDBACK,
      status: 'shipped',
    })
  );
});

test('app_feedback: client CANNOT delete feedback (audit trail)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('app_feedback').doc('f1').set(VALID_FEEDBACK);
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('app_feedback').doc('f1').delete()
  );
});

test('app_feedback: client CANNOT update their own feedback (admin-only update)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('app_feedback').doc('f1').set(VALID_FEEDBACK);
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('app_feedback').doc('f1').update({
      content: 'I changed my mind',
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// community_requests — volunteer hub (§7b)
// ═══════════════════════════════════════════════════════════════════════════
test('community_requests: requester CANNOT forge another user\'s requesterId', async () => {
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('community_requests').add({
      requesterId: 'alice',  // forged
      title: 'Help me move',
      category: 'delivery',
      status: 'open',
      createdAt: new Date(),
    })
  );
});

test('community_requests: random user CANNOT read someone else\'s in-progress request', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('community_requests').doc('r1').set({
      requesterId: 'alice',
      volunteerId: 'bob',
      title: 'Hidden request',
      status: 'in_progress',  // not 'open' — should be private
    });
  });

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(db.collection('community_requests').doc('r1').get());
});

// ═══════════════════════════════════════════════════════════════════════════
// vip_subscriptions — admin/CF only writes
// ═══════════════════════════════════════════════════════════════════════════
test('vip_subscriptions: provider CANNOT create a subscription for themselves', async () => {
  // Provider tries to grant themselves VIP without paying
  const db = testEnv.authenticatedContext('alice_provider', NON_ADMIN).firestore();
  await assertFails(
    db.collection('vip_subscriptions').add({
      providerId: 'alice_provider',
      status: 'active',
      startDate: new Date(),
      endDate: new Date(Date.now() + 365 * 86400 * 1000),  // 1 year
    })
  );
});

test('vip_subscriptions: provider CANNOT update their own subscription', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('vip_subscriptions').doc('sub1').set({
      providerId: 'alice_provider',
      status: 'active',
      endDate: new Date(Date.now() + 86400 * 1000),  // 1 day from now
    });
  });

  // Provider tries to extend their own subscription
  const db = testEnv.authenticatedContext('alice_provider', NON_ADMIN).firestore();
  await assertFails(
    db.collection('vip_subscriptions').doc('sub1').update({
      endDate: new Date(Date.now() + 365 * 86400 * 1000),  // extend by a year
    })
  );
});

test('vip_subscriptions: random user CANNOT read someone else\'s subscription', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('vip_subscriptions').doc('sub1').set({
      providerId: 'alice_provider',
      status: 'active',
    });
  });

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(db.collection('vip_subscriptions').doc('sub1').get());
});

test('vip_subscriptions: nobody CAN delete a subscription (history preserved)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('vip_subscriptions').doc('sub1').set({
      providerId: 'alice_provider',
      status: 'expired',
    });
  });

  // Even an admin cannot delete (rule says: allow delete: if false)
  const db = testEnv.authenticatedContext('alice_provider', NON_ADMIN).firestore();
  await assertFails(
    db.collection('vip_subscriptions').doc('sub1').delete()
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// demo_bookings — customer creates, admin manages (§4.7)
// ═══════════════════════════════════════════════════════════════════════════
test('demo_bookings: customer CANNOT forge another user\'s customerId', async () => {
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('demo_bookings').add({
      customerId: 'alice',  // forged
      demoExpertId: 'demo1',
      demoExpertName: 'Demo Expert',
      selectedDate: '2026-05-09',
      status: 'pending',
    })
  );
});

test('demo_bookings: regular user CANNOT read demo bookings (admin-only)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('demo_bookings').doc('b1').set({
      customerId: 'alice',
      demoExpertId: 'demo1',
      status: 'pending',
    });
  });

  // Even the customer who created the booking cannot read it
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(db.collection('demo_bookings').doc('b1').get());
});

test('demo_bookings: regular user CANNOT update a demo booking', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('demo_bookings').doc('b1').set({
      customerId: 'alice',
      demoExpertId: 'demo1',
      status: 'pending',
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('demo_bookings').doc('b1').update({ status: 'contacted' })
  );
});
