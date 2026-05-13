// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers for Firestore rules tests.
// ─────────────────────────────────────────────────────────────────────────────
//
// Why this file exists:
//   firestore.rules has an isAdmin() helper that does:
//     get(/users/$(request.auth.uid)).data.isAdmin == true
//   When the user's doc doesn't exist (which is the default in a fresh test
//   environment), get() returns null, and accessing .data on null throws
//   "Null value error" — even when called in an OR branch that should
//   short-circuit. This causes legitimate operations to be denied.
//
// The fix: pre-seed minimal user docs for every uid used in tests, so that
// isAdmin() can resolve safely (and return false, since isAdmin == false
// is set explicitly).
// ─────────────────────────────────────────────────────────────────────────────

const COMMON_UIDS = [
  // Generic test personas
  'alice', 'bob', 'eve', 'charlie', 'me', 'attacker',
  // Role-suffixed
  'bob_provider', 'bob_walker', 'bob_winner', 'bob_tower',
  'alice_needy', 'alice_stranded', 'charlie_loser',
  // Support
  'agent1',
];

/**
 * Seeds minimal non-admin user docs for every uid in [uids].
 * If [uids] is omitted, seeds the default set used across this test suite.
 * Call this in beforeEach AFTER clearFirestore.
 */
async function seedAuthUsers(testEnv, uids = COMMON_UIDS) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of uids) {
      await db.collection('users').doc(uid).set({
        isAdmin: false,
        roles: [],
        name: `Test ${uid}`,
      });
    }
  });
}

/**
 * Standard token claims for non-admin authenticated contexts.
 * Pass to authenticatedContext(uid, NON_ADMIN_TOKEN) to ensure
 * request.auth.token.admin == false (not undefined → "Null value error").
 */
const NON_ADMIN_TOKEN = { admin: false, support_agent: false };

module.exports = { seedAuthUsers, NON_ADMIN_TOKEN, COMMON_UIDS };
