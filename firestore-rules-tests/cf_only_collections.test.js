// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — CF-only / append-only collections
//
// These collections are written EXCLUSIVELY by Cloud Functions via the
// Admin SDK (which bypasses rules). Any direct client write is a security
// regression. Maps to firestore.rules:
//   - platform_earnings/{id}      lines 637-642   (no update, no delete)
//   - admin_credit_idempotency    lines 1757-1760 (read+write blocked)
//   - email_verification_codes    lines 1764-1767 (read+write blocked)
//   - vip_payments/{id}           lines 1496-1501 (CF-only writes)
//   - support_audit_log           lines 1043-1052 (admin/agent read; CF-only writes)
//
// CLAUDE.md §4 (escrow), §4.6 (admin credits), §4.8 (RBAC), §51 (Banners Studio).
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

afterAll(async () => { if (testEnv) await testEnv.cleanup(); });
beforeEach(async () => { await testEnv.clearFirestore(); });

const NON_ADMIN = { admin: false, support_agent: false };

// ═══════════════════════════════════════════════════════════════════════════
// admin_credit_idempotency — full lockdown (read+write blocked)
// ═══════════════════════════════════════════════════════════════════════════
test('admin_credit_idempotency: client CANNOT read', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('admin_credit_idempotency').doc('cache1').set({
      adminUid: 'admin1', amount: 100, createdAt: new Date(),
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(db.collection('admin_credit_idempotency').doc('cache1').get());
});

test('admin_credit_idempotency: client CANNOT write', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('admin_credit_idempotency').doc('forgery').set({
      adminUid: 'alice', amount: 99999,
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// email_verification_codes — full lockdown (CF-only via callable)
// ═══════════════════════════════════════════════════════════════════════════
test('email_verification_codes: even the targeted user CANNOT read their own code', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('email_verification_codes').doc('alice').set({
      codeHash: 'sha256...', salt: 'abc', expiresAt: new Date(),
    });
  });

  // Alice cannot read her own code — only the verifyEmailCode CF can.
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(db.collection('email_verification_codes').doc('alice').get());
});

test('email_verification_codes: client CANNOT write', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('email_verification_codes').doc('alice').set({
      codeHash: 'forged', salt: 'fake',
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// platform_earnings — append-only audit trail (no update, no delete)
// ═══════════════════════════════════════════════════════════════════════════
test('platform_earnings: client CANNOT update existing earnings record', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('platform_earnings').doc('e1').set({
      jobId: 'job1', amount: 50, sourceExpertId: 'bob', status: 'pending_escrow',
    });
  });

  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('platform_earnings').doc('e1').update({ amount: 0 })
  );
});

test('platform_earnings: client CANNOT delete earnings record', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('platform_earnings').doc('e1').set({
      jobId: 'job1', amount: 50, sourceExpertId: 'bob',
    });
  });

  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('platform_earnings').doc('e1').delete()
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// vip_payments — CF-only writes (clients can read their own, never write)
// ═══════════════════════════════════════════════════════════════════════════
test('vip_payments: client CANNOT create a payment record', async () => {
  // Alice tries to fake a payment record for herself
  const db = testEnv.authenticatedContext('alice_provider', NON_ADMIN).firestore();
  await assertFails(
    db.collection('vip_payments').doc('forgery').set({
      providerId: 'alice_provider',
      amount: 99,
      status: 'completed',
      paymentDate: new Date(),
    })
  );
});

test('vip_payments: provider CANNOT update their own payment record', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('vip_payments').doc('p1').set({
      providerId: 'bob_provider', amount: 99, status: 'completed',
    });
  });

  const db = testEnv.authenticatedContext('bob_provider', NON_ADMIN).firestore();
  await assertFails(
    db.collection('vip_payments').doc('p1').update({ amount: 0, status: 'refunded' })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// support_audit_log — append-only via supportAgentAction CF
// ═══════════════════════════════════════════════════════════════════════════
test('support_audit_log: agent CANNOT delete their own audit entry', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('support_audit_log').doc('log1').set({
      agentUid: 'agent1',
      action: 'verify_identity',
      targetUserId: 'alice',
      reason: 'manual review',
      createdAt: new Date(),
    });
  });

  const db = testEnv.authenticatedContext('agent1', NON_ADMIN).firestore();
  await assertFails(
    db.collection('support_audit_log').doc('log1').delete()
  );
});

test('support_audit_log: agent CANNOT update their own audit entry', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('support_audit_log').doc('log1').set({
      agentUid: 'agent1',
      action: 'flag_account',
      targetUserId: 'alice',
      reason: 'suspicious',
      createdAt: new Date(),
    });
  });

  const db = testEnv.authenticatedContext('agent1', NON_ADMIN).firestore();
  await assertFails(
    db.collection('support_audit_log').doc('log1').update({
      reason: 'mistake — please ignore',
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// transactions — clients can create their own but cannot delete
// ═══════════════════════════════════════════════════════════════════════════
test('transactions: client CANNOT delete a transaction record', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('transactions').doc('tx1').set({
      userId: 'alice', amount: -100, type: 'quote_payment',
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('transactions').doc('tx1').delete()
  );
});

test.skip('transactions: client CANNOT create a forged transaction in another user\'s name', async () => {
  // bob signed in but tries to create a transaction with userId='alice'
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('transactions').doc('forged').set({
      userId: 'alice',           // forged
      senderId: 'alice',
      amount: -100,
      type: 'quote_payment',
    })
  );
});
