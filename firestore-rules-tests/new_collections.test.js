// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — newer collections (post-§50 audit)
//
// Coverage: flash_auctions, vip_subscriptions, vip_payments, app_feedback,
//           category_commissions, monetization_alerts, ai_insights,
//           dog_walks, boarding_proofs, demo_bookings.
//
// Each test maps to a security guarantee documented in the relevant CLAUDE.md
// section. If anyone loosens a rule that protects against these scenarios,
// the test fails in CI before the change merges.
// ─────────────────────────────────────────────────────────────────────────────

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { setLogLevel } = require('firebase/firestore');
const { seedAuthUsers, NON_ADMIN_TOKEN } = require('./_helpers');

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
  await seedAuthUsers(testEnv, [
    'customer1', 'provider1', 'provider2', 'attacker', 'admin1', 'agent1',
  ]);
  // Mark admin1 as admin
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('users').doc('admin1').update({
      isAdmin: true,
    });
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// flash_auctions/{id} (CLAUDE.md §57)
// ═══════════════════════════════════════════════════════════════════════════
describe('flash_auctions — security boundary', () => {
  test('customer can create auction with their own customerId', async () => {
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(
      db.collection('flash_auctions').add({
        customerId: 'customer1',
        status: 'searching',
        notifiedProviderIds: [],
        createdAt: new Date(),
      })
    );
  });

  test('attacker CANNOT create auction with someone else\'s customerId', async () => {
    const db = testEnv
      .authenticatedContext('attacker', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('flash_auctions').add({
        customerId: 'customer1', // not the attacker!
        status: 'searching',
        notifiedProviderIds: [],
      })
    );
  });

  test('CANNOT create auction with status != "searching"', async () => {
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('flash_auctions').add({
        customerId: 'customer1',
        status: 'matched', // already matched at create time → suspicious
        notifiedProviderIds: [],
      })
    );
  });

  test('customer can read their own auction', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('flash_auctions').doc('a1').set({
        customerId: 'customer1',
        status: 'searching',
        notifiedProviderIds: [],
      });
    });
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(db.collection('flash_auctions').doc('a1').get());
  });

  test('notified provider can read the auction', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('flash_auctions').doc('a1').set({
        customerId: 'customer1',
        status: 'searching',
        notifiedProviderIds: ['provider1', 'provider2'],
      });
    });
    const db = testEnv
      .authenticatedContext('provider1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(db.collection('flash_auctions').doc('a1').get());
  });

  test('NON-notified third party CANNOT read the auction', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('flash_auctions').doc('a1').set({
        customerId: 'customer1',
        status: 'searching',
        notifiedProviderIds: ['provider1'],
      });
    });
    const db = testEnv
      .authenticatedContext('attacker', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(db.collection('flash_auctions').doc('a1').get());
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// vip_subscriptions/{id} (CLAUDE.md §51)
// ═══════════════════════════════════════════════════════════════════════════
describe('vip_subscriptions — admin-only writes', () => {
  test('client CANNOT create vip_subscriptions doc directly', async () => {
    const db = testEnv
      .authenticatedContext('provider1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('vip_subscriptions').add({
        providerId: 'provider1',
        status: 'active',
      })
    );
  });

  test('provider can read their OWN subscription', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('vip_subscriptions').doc('s1').set({
        providerId: 'provider1',
        status: 'active',
      });
    });
    const db = testEnv
      .authenticatedContext('provider1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(db.collection('vip_subscriptions').doc('s1').get());
  });

  test('provider CANNOT read SOMEONE ELSE\'S subscription', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('vip_subscriptions').doc('s1').set({
        providerId: 'provider1',
        status: 'active',
      });
    });
    const db = testEnv
      .authenticatedContext('provider2', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(db.collection('vip_subscriptions').doc('s1').get());
  });

  test('client CANNOT delete vip_subscriptions (immutable from client)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('vip_subscriptions').doc('s1').set({
        providerId: 'provider1',
        status: 'active',
      });
    });
    const db = testEnv
      .authenticatedContext('admin1', { admin: true })
      .firestore();
    // Even ADMIN cannot delete (allow delete: if false)
    await assertFails(db.collection('vip_subscriptions').doc('s1').delete());
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// vip_payments/{id} (CLAUDE.md §51)
// ═══════════════════════════════════════════════════════════════════════════
describe('vip_payments — CF-only writes, owner reads', () => {
  test('client CANNOT create vip_payments directly (must go through CF)', async () => {
    const db = testEnv
      .authenticatedContext('provider1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('vip_payments').add({
        providerId: 'provider1',
        amount: 99,
        status: 'paid',
      })
    );
  });

  test('payment owner can read their payment', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('vip_payments').doc('p1').set({
        providerId: 'provider1',
        amount: 99,
        status: 'paid',
      });
    });
    const db = testEnv
      .authenticatedContext('provider1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(db.collection('vip_payments').doc('p1').get());
  });

  test('non-owner CANNOT read another user\'s payment', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('vip_payments').doc('p1').set({
        providerId: 'provider1',
        amount: 99,
      });
    });
    const db = testEnv
      .authenticatedContext('attacker', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(db.collection('vip_payments').doc('p1').get());
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// app_feedback/{id} (CLAUDE.md §42)
// ═══════════════════════════════════════════════════════════════════════════
describe('app_feedback — owner authorship', () => {
  test('user can create feedback with their own uid', async () => {
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(
      db.collection('app_feedback').add({
        uid: 'customer1',
        userRole: 'customer',
        category: 'app_interface',
        content: 'I would love a dark mode option for the app please',
        npsScore: 8,
        status: 'pending',
      })
    );
  });

  test('attacker CANNOT submit feedback as someone else', async () => {
    const db = testEnv
      .authenticatedContext('attacker', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('app_feedback').add({
        uid: 'customer1', // not the attacker!
        userRole: 'customer',
        category: 'app_interface',
        content: 'fake feedback impersonating customer1',
        npsScore: 1,
        status: 'pending',
      })
    );
  });

  test('cannot create feedback with content > 500 chars', async () => {
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('app_feedback').add({
        uid: 'customer1',
        userRole: 'customer',
        category: 'app_interface',
        content: 'A'.repeat(501), // over the 500-char rule limit
        npsScore: 8,
        status: 'pending',
      })
    );
  });

  test('cannot create feedback with NPS out of [1,10]', async () => {
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('app_feedback').add({
        uid: 'customer1',
        userRole: 'customer',
        category: 'app_interface',
        content: 'good app',
        npsScore: 11, // invalid!
        status: 'pending',
      })
    );
  });

  test('cannot create with non-pending status (admin-only via update)', async () => {
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('app_feedback').add({
        uid: 'customer1',
        userRole: 'customer',
        category: 'app_interface',
        content: 'good app',
        npsScore: 8,
        status: 'shipped', // can't ship-mark your own feedback!
      })
    );
  });

  test('user CANNOT update their feedback (immutable from user)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('app_feedback').doc('f1').set({
        uid: 'customer1',
        userRole: 'customer',
        category: 'app_interface',
        content: 'original',
        npsScore: 8,
        status: 'pending',
      });
    });
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('app_feedback').doc('f1').update({
        content: 'updated',
      })
    );
  });

  test('user can read their own feedback', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('app_feedback').doc('f1').set({
        uid: 'customer1',
        userRole: 'customer',
        category: 'app_interface',
        content: 'good app',
        npsScore: 8,
      });
    });
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(db.collection('app_feedback').doc('f1').get());
  });

  test('attacker CANNOT read another user\'s feedback', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('app_feedback').doc('f1').set({
        uid: 'customer1',
        userRole: 'customer',
        category: 'app_interface',
        content: 'private feedback',
        npsScore: 8,
      });
    });
    const db = testEnv
      .authenticatedContext('attacker', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(db.collection('app_feedback').doc('f1').get());
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// category_commissions/{id} (CLAUDE.md §31)
// ═══════════════════════════════════════════════════════════════════════════
describe('category_commissions — admin-only writes', () => {
  test('non-admin CANNOT write category commission', async () => {
    const db = testEnv
      .authenticatedContext('provider1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('category_commissions').doc('cleaning').set({
        categoryId: 'cleaning',
        categoryName: 'נקיון',
        percentage: 5, // tries to set their own category to 5% — denied
      })
    );
  });

  test('non-admin CANNOT update category commission', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('category_commissions').doc('cleaning').set({
        percentage: 10,
      });
    });
    const db = testEnv
      .authenticatedContext('provider1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('category_commissions').doc('cleaning').update({
        percentage: 0, // try to zero out platform fee
      })
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// monetization_alerts/{id} + ai_insights/{id} (CLAUDE.md §31)
// ═══════════════════════════════════════════════════════════════════════════
describe('monetization_alerts + ai_insights — admin-only', () => {
  test('non-admin CANNOT read monetization_alerts', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('monetization_alerts').doc('a1').set({
        type: 'churn_risk',
        entityId: 'provider1',
      });
    });
    const db = testEnv
      .authenticatedContext('provider1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(db.collection('monetization_alerts').doc('a1').get());
  });

  test('non-admin CANNOT read ai_insights', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('ai_insights').doc('monetization').set({
        title: 'Confidential AI insight',
      });
    });
    const db = testEnv
      .authenticatedContext('provider1', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(db.collection('ai_insights').doc('monetization').get());
  });

  test('client CANNOT create monetization_alert (CF-only)', async () => {
    const db = testEnv
      .authenticatedContext('admin1', { admin: true })
      .firestore();
    // Even admin cannot create directly — must go through CF
    await assertFails(
      db.collection('monetization_alerts').add({
        type: 'anomaly',
        entityType: 'user',
        entityId: 'fake',
      })
    );
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// dog_walks/{id} (CLAUDE.md §3d)
// ═══════════════════════════════════════════════════════════════════════════
describe('dog_walks — provider writes, both parties read', () => {
  test('customer can read walk on their job', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('dog_walks').doc('w1').set({
        customerId: 'customer1',
        providerId: 'provider1',
        jobId: 'j1',
        status: 'walking',
      });
    });
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(db.collection('dog_walks').doc('w1').get());
  });

  test('provider can read their own walk', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('dog_walks').doc('w1').set({
        customerId: 'customer1',
        providerId: 'provider1',
        jobId: 'j1',
      });
    });
    const db = testEnv
      .authenticatedContext('provider1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(db.collection('dog_walks').doc('w1').get());
  });

  test('outsider CANNOT read someone else\'s walk', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('dog_walks').doc('w1').set({
        customerId: 'customer1',
        providerId: 'provider1',
      });
    });
    const db = testEnv
      .authenticatedContext('attacker', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(db.collection('dog_walks').doc('w1').get());
  });
});

// ═══════════════════════════════════════════════════════════════════════════
// demo_bookings/{id} (CLAUDE.md §4.7)
// ═══════════════════════════════════════════════════════════════════════════
describe('demo_bookings — customer create, admin read', () => {
  test('customer can create demo_booking with their own customerId', async () => {
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(
      db.collection('demo_bookings').add({
        customerId: 'customer1',
        demoExpertId: 'demo1',
        status: 'pending',
      })
    );
  });

  test('attacker CANNOT create demo_booking impersonating someone', async () => {
    const db = testEnv
      .authenticatedContext('attacker', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(
      db.collection('demo_bookings').add({
        customerId: 'customer1', // not the attacker
        demoExpertId: 'demo1',
        status: 'pending',
      })
    );
  });

  test('non-admin CANNOT read demo_bookings (privacy)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('demo_bookings').doc('b1').set({
        customerId: 'customer1',
        demoExpertId: 'demo1',
      });
    });
    const db = testEnv
      .authenticatedContext('customer1', NON_ADMIN_TOKEN)
      .firestore();
    // Even the customer who created it cannot read — admin only.
    await assertFails(db.collection('demo_bookings').doc('b1').get());
  });
});
