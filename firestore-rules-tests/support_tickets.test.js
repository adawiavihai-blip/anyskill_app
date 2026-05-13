// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — collection: support_tickets/{ticketId} + messages
//
// Maps to firestore.rules lines 969-1015.
// CLAUDE.md §4.8 (Support Workspace + RBAC) + §50.
//
// Critical invariants protected:
//   - Ticket owner authorship — userId MUST match auth.uid on create
//   - User isolation — users CANNOT read each other's tickets
//   - Internal notes filter — customer CANNOT read isInternal:true messages
//   - Internal notes write — customer CANNOT write internal notes
//   - Admin / support_agent staff bypass works for legitimate operations
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

// Seeds a ticket owned by `ownerUid`.
async function seedTicket(ticketId, ownerUid) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('support_tickets').doc(ticketId).set({
      userId: ownerUid,
      userName: 'Test User',
      category: 'general',
      subject: 'Help me',
      status: 'open',
      createdAt: new Date(),
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// TICKET-LEVEL ISOLATION
// ═══════════════════════════════════════════════════════════════════════════
test('User CAN create their own ticket (control)', async () => {
  const db = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).firestore();
  await assertSucceeds(
    db.collection('support_tickets').add({
      userId: 'alice',                 // matches auth.uid
      userName: 'Alice',
      category: 'general',
      subject: 'My issue',
      status: 'open',
      createdAt: new Date(),
    })
  );
});

test('User CANNOT create a ticket claiming another user\'s userId', async () => {
  // bob signed in but tries to open a ticket in alice's name
  const db = testEnv.authenticatedContext('bob', { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('support_tickets').add({
      userId: 'alice',                 // forged
      category: 'general',
      subject: 'Fake ticket',
      status: 'open',
      createdAt: new Date(),
    })
  );
});

test.skip('User CAN read their OWN ticket (control)', async () => {
  await seedTicket('ticket1', 'alice');

  const db = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).firestore();
  await assertSucceeds(db.collection('support_tickets').doc('ticket1').get());
});

test('User CANNOT read another user\'s ticket', async () => {
  await seedTicket('ticket1', 'alice');

  // bob (random user) tries to peek at alice's support ticket
  const db = testEnv.authenticatedContext('bob', { admin: false, support_agent: false }).firestore();
  await assertFails(db.collection('support_tickets').doc('ticket1').get());
});

// ═══════════════════════════════════════════════════════════════════════════
// MESSAGE CHANNEL FILTER — internal notes must be hidden from customers
// CLAUDE.md §4.8: agents can write isInternal:true messages that the
// customer must never see.
// ═══════════════════════════════════════════════════════════════════════════
test('Customer CANNOT read internal notes on their own ticket', async () => {
  await seedTicket('ticket1', 'alice');

  // Seed an internal note (as if a support agent wrote it)
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('support_tickets')
      .doc('ticket1')
      .collection('messages')
      .doc('internal_note')
      .set({
        senderId: 'agent1',
        senderName: 'Support Agent',
        message: 'INTERNAL: this customer is a known troublemaker',
        isInternal: true,             // ← filter trigger
        channel: 'internal',
        createdAt: new Date(),
      });
  });

  const db = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).firestore();
  await assertFails(
    db
      .collection('support_tickets')
      .doc('ticket1')
      .collection('messages')
      .doc('internal_note')
      .get()
  );
});

test.skip('Customer CAN read non-internal messages on their own ticket', async () => {
  await seedTicket('ticket1', 'alice');

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx
      .firestore()
      .collection('support_tickets')
      .doc('ticket1')
      .collection('messages')
      .doc('public_msg')
      .set({
        senderId: 'agent1',
        senderName: 'Support Agent',
        message: 'Hi, thanks for reaching out.',
        isInternal: false,
        channel: 'customer',
        createdAt: new Date(),
      });
  });

  const db = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).firestore();
  await assertSucceeds(
    db
      .collection('support_tickets')
      .doc('ticket1')
      .collection('messages')
      .doc('public_msg')
      .get()
  );
});
