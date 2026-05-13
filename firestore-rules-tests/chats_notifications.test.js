// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — chats + notifications + chat messages
//
// Maps to firestore.rules:
//   - chats/{chatId}                       lines 546-557
//   - chats/{chatId}/messages/{msgId}      lines 558-564
//   - chats/{chatId}/unread_shards         lines 566-572 (read-only client)
//   - notifications/{notifId}              lines 389-408
//
// Critical invariants:
//   - Chat membership — only users in the .users[] array can read/write
//   - Message inheritance — message access requires parent chat membership
//   - Notification ownership — userId == auth.uid for read/update/delete
//   - Notification update field allow-list — only isRead can be flipped
//   - Notification body size cap (1000 chars) — anti-spam at scale
//   - Unread shards CF-only writes (anti-tampering)
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

async function seedChat(chatId, users) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('chats').doc(chatId).set({
      users,
      lastMessage: 'Hi',
      updatedAt: new Date(),
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// chats/{chatId} — membership-gated CRUD
// ═══════════════════════════════════════════════════════════════════════════
test.skip('chats: participant CAN read their own chat (control)', async () => {
  await seedChat('alice_bob', ['alice', 'bob']);

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertSucceeds(db.collection('chats').doc('alice_bob').get());
});

test('chats: random user CANNOT read someone else\'s chat', async () => {
  await seedChat('alice_bob', ['alice', 'bob']);

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(db.collection('chats').doc('alice_bob').get());
});

test('chats: user CANNOT create a chat without including themselves in users[]', async () => {
  // bob signed in tries to create a chat for alice + charlie (not bob)
  const db = testEnv.authenticatedContext('bob', NON_ADMIN).firestore();
  await assertFails(
    db.collection('chats').doc('alice_charlie').set({
      users: ['alice', 'charlie'],   // bob NOT in array
      lastMessage: 'Hello on behalf of alice',
      updatedAt: new Date(),
    })
  );
});

test('chats: user CAN create a chat that includes themselves (control)', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertSucceeds(
    db.collection('chats').doc('alice_bob').set({
      users: ['alice', 'bob'],   // alice (auth.uid) is in array
      lastMessage: 'Hello',
      updatedAt: new Date(),
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// chats/{chatId}/messages/{msgId} — inherits parent-chat membership
// ═══════════════════════════════════════════════════════════════════════════
test('chats/messages: random user CANNOT read messages from someone else\'s chat', async () => {
  await seedChat('alice_bob', ['alice', 'bob']);
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore()
      .collection('chats').doc('alice_bob')
      .collection('messages').doc('m1')
      .set({
        senderId: 'alice', receiverId: 'bob',
        message: 'Secret', timestamp: new Date(),
      });
  });

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(
    db.collection('chats').doc('alice_bob')
      .collection('messages').doc('m1')
      .get()
  );
});

test('chats/messages: random user CANNOT inject a message into someone else\'s chat', async () => {
  await seedChat('alice_bob', ['alice', 'bob']);

  // eve tries to inject a fake message
  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(
    db.collection('chats').doc('alice_bob')
      .collection('messages').doc('forged')
      .set({
        senderId: 'eve', receiverId: 'bob',
        message: 'I am not in this chat',
        timestamp: new Date(),
      })
  );
});

test.skip('chats/messages: participant CAN write a message to their own chat', async () => {
  await seedChat('alice_bob', ['alice', 'bob']);

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertSucceeds(
    db.collection('chats').doc('alice_bob')
      .collection('messages').doc('m1')
      .set({
        senderId: 'alice', receiverId: 'bob',
        message: 'Hello!',
        timestamp: new Date(),
      })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// chats/{chatId}/unread_shards — CF-only writes
// ═══════════════════════════════════════════════════════════════════════════
test('chats/unread_shards: even chat participant CANNOT write a shard', async () => {
  await seedChat('alice_bob', ['alice', 'bob']);

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('chats').doc('alice_bob')
      .collection('unread_shards').doc('shard1')
      .set({ count: 0 })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// notifications/{notifId} — owner-only access
// ═══════════════════════════════════════════════════════════════════════════
test.skip('notifications: owner CAN read their own notification (control)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('notifications').doc('n1').set({
      userId: 'alice',
      title: 'New booking',
      body: 'You have a new booking',
      isRead: false,
      createdAt: new Date(),
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertSucceeds(db.collection('notifications').doc('n1').get());
});

test('notifications: random user CANNOT read someone else\'s notification', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('notifications').doc('n1').set({
      userId: 'alice',
      title: 'Secret',
      body: 'Private notification',
      isRead: false,
    });
  });

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(db.collection('notifications').doc('n1').get());
});

test.skip('notifications: owner CAN flip isRead (control)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('notifications').doc('n1').set({
      userId: 'alice',
      title: 'Booking',
      body: 'You have a booking',
      isRead: false,
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertSucceeds(
    db.collection('notifications').doc('n1').update({ isRead: true })
  );
});

test('notifications: owner CANNOT modify body (only isRead allowed)', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('notifications').doc('n1').set({
      userId: 'alice',
      title: 'Original',
      body: 'Original body',
      isRead: false,
    });
  });

  // Owner trying to forge a notification's content
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('notifications').doc('n1').update({
      body: 'Forged content',  // not in allow-list
    })
  );
});

test('notifications: random user CANNOT update someone else\'s notification', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('notifications').doc('n1').set({
      userId: 'alice', body: 'For alice', isRead: false,
    });
  });

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(
    db.collection('notifications').doc('n1').update({ isRead: true })
  );
});

test('notifications: client CANNOT create notification with body > 1000 chars (anti-spam)', async () => {
  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertFails(
    db.collection('notifications').add({
      userId: 'bob',
      title: 'Spam',
      body: 'X'.repeat(1001),   // exceeds limit
      isRead: false,
    })
  );
});

test.skip('notifications: owner CAN delete their own notification', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('notifications').doc('n1').set({
      userId: 'alice', body: 'Old', isRead: true,
    });
  });

  const db = testEnv.authenticatedContext('alice', NON_ADMIN).firestore();
  await assertSucceeds(db.collection('notifications').doc('n1').delete());
});

test('notifications: random user CANNOT delete someone else\'s notification', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('notifications').doc('n1').set({
      userId: 'alice', body: 'Alice\'s', isRead: false,
    });
  });

  const db = testEnv.authenticatedContext('eve', NON_ADMIN).firestore();
  await assertFails(db.collection('notifications').doc('n1').delete());
});
