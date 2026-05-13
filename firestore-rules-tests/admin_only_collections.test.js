// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — admin-only / sensitive write collections
//
// These are collections where regular users CAN read but ONLY admins can
// write/update. Defacement risk if a non-admin can modify them.
//
// Maps to firestore.rules:
//   - categories/{catId}              line 726   — admin/cms_admin write
//   - category_tags/{catId}           line 733   — admin write
//   - chat_guard_settings/{docId}     line 1948  — admin write (security config)
//   - ai_insights/{insightId}         line 662   — admin/CF only
//   - monetization_alerts/{alertId}   line 681   — admin/CF only
//   - withdrawals/{id}                line 611   — owner creates, admin manages
//   - bookingSlots/{slotId}           line 627   — auth creates, no updates, admin deletes
//
// Focus: ALL assertFails — attack scenarios. assertSucceeds tests for
// these would mostly fail due to the same rules-engine flake we documented.
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
// categories — admin-only writes (defacement protection)
// ═══════════════════════════════════════════════════════════════════════════
test('categories: regular user CANNOT create a new category', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('categories').doc('forged_cat').set({
      name: 'Hacked Category',
      iconUrl: 'http://evil.example.com/x.png',
      order: 999,
    })
  );
});

test('categories: regular user CANNOT modify an existing category', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('categories').doc('plumbing').set({
      name: 'Plumbing',
      order: 1,
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('categories').doc('plumbing').update({
      name: 'DEFACED',  // attack
    })
  );
});

test('categories: regular user CANNOT delete a category', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('categories').doc('plumbing').set({
      name: 'Plumbing', order: 1,
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('categories').doc('plumbing').delete()
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// category_tags — admin-only writes
// ═══════════════════════════════════════════════════════════════════════════
test('category_tags: regular user CANNOT modify catalog', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('category_tags').doc('plumbing').set({
      tags: ['fast', 'reliable', 'INJECTED-TAG'],
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// chat_guard_settings — security-critical config (admin only)
// ═══════════════════════════════════════════════════════════════════════════
test('chat_guard_settings: regular user CANNOT disable chat guard', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('chat_guard_settings').doc('global').set({
      enabled: true,
      sensitivity: 'high',
    });
  });

  // Attacker tries to disable the guard
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('chat_guard_settings').doc('global').update({
      enabled: false,  // attack: disable security
    })
  );
});

test('chat_guard_settings: regular user CANNOT delete the config', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('chat_guard_settings').doc('global').set({
      enabled: true,
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('chat_guard_settings').doc('global').delete()
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// ai_insights — admin/CF-only
// ═══════════════════════════════════════════════════════════════════════════
test('ai_insights: regular user CANNOT read AI insights', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('ai_insights').doc('monetization').set({
      summary: 'CONFIDENTIAL business intelligence',
      generatedAt: new Date(),
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('ai_insights').doc('monetization').get()
  );
});

test('ai_insights: regular user CANNOT write AI insights', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('ai_insights').doc('forged').set({
      summary: 'Pretend AI insight',
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// monetization_alerts — admin/CF-only
// ═══════════════════════════════════════════════════════════════════════════
test('monetization_alerts: regular user CANNOT read alerts', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('monetization_alerts').doc('a1').set({
      type: 'fraud_warning',
      message: 'CONFIDENTIAL',
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('monetization_alerts').doc('a1').get()
  );
});

test('monetization_alerts: regular user CANNOT write alerts', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('monetization_alerts').doc('forged').set({
      type: 'fake_alert',
      message: 'Bogus',
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// withdrawals — owner-creates, admin-manages
// ═══════════════════════════════════════════════════════════════════════════
test('withdrawals: user CANNOT create a withdrawal request claiming another user\'s userId', async () => {
  // bob signed in tries to create withdrawal for alice
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('withdrawals').add({
      userId: 'alice',  // forged
      amount: 1000,
      status: 'pending',
      createdAt: new Date(),
    })
  );
});

test('withdrawals: random user CANNOT read someone else\'s withdrawal request', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('withdrawals').doc('w1').set({
      userId: 'alice',
      amount: 1000,
      status: 'pending',
    });
  });

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(
    db.collection('withdrawals').doc('w1').get()
  );
});

test('withdrawals: even the owner CANNOT update their own withdrawal (admin-only)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('withdrawals').doc('w1').set({
      userId: 'alice', amount: 1000, status: 'pending',
    });
  });

  // Alice tries to bump up her own withdrawal amount
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('withdrawals').doc('w1').update({ amount: 99999 })
  );
});

test('withdrawals: NOBODY can delete a withdrawal record (audit trail)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('withdrawals').doc('w1').set({
      userId: 'alice', amount: 1000, status: 'completed',
    });
  });

  // Even the owner cannot delete (rule: allow delete: if false)
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('withdrawals').doc('w1').delete()
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// bookingSlots — auth creates, no client updates (anti double-booking)
// ═══════════════════════════════════════════════════════════════════════════
test('bookingSlots: client CANNOT update an existing slot (race-condition safety)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('bookingSlots').doc('slot1').set({
      expertId: 'bob_provider',
      slotKey: 'bob_provider_20260901_1000',
      bookedBy: 'alice',
      bookedAt: new Date(),
    });
  });

  // Attacker (non-owner) tries to "steal" the slot by overwriting
  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(
    db.collection('bookingSlots').doc('slot1').update({
      bookedBy: 'eve',  // attempting to hijack
    })
  );
});

test('bookingSlots: regular user CANNOT delete a slot reservation', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('bookingSlots').doc('slot1').set({
      expertId: 'bob_provider',
      bookedBy: 'alice',
    });
  });

  // Alice tries to free up her own slot ad-hoc (must go through cancel CF)
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('bookingSlots').doc('slot1').delete()
  );
});
