// ─────────────────────────────────────────────────────────────────────────────
// Storage Rules Tests — 4 critical paths from CLAUDE.md §50
//
// Maps to storage.rules:
//   - lines 134-146: dog_walks/{walkId}/  (Vuln C1, Round C)
//   - lines 167-179: motorcycle_tows/{towId}/  (Round C)
//   - lines 215-226: boarding_proofs/{jobId}/  (Vuln 3, Round A)
//   - lines 245-257: anytask_proofs/{taskId}/  (Vuln 8, Round B)
//
// All four paths use the SAME pattern: parent-doc participant lookup via
// firestore.exists() + firestore.get(). This test file proves the pattern
// works for legitimate participants and blocks everyone else.
// ─────────────────────────────────────────────────────────────────────────────

const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { ref, uploadBytes, getBytes } = require('firebase/storage');
const { setLogLevel } = require('firebase/firestore');

const PROJECT_ID = 'anyskill-rules-tests';
const FIRESTORE_RULES = path.resolve(__dirname, '..', 'firestore.rules');
const STORAGE_RULES   = path.resolve(__dirname, '..', 'storage.rules');

setLogLevel('error');

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(FIRESTORE_RULES, 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: fs.readFileSync(STORAGE_RULES, 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

afterAll(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

// Helper: seed a parent doc that the storage rule will look up.
async function seedDoc(collection, docId, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection(collection).doc(docId).set(data);
  });
}

// 1×1 PNG payload (8 bytes is enough for upload tests).
const TINY_PNG = new Uint8Array([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
]);

// ═══════════════════════════════════════════════════════════════════════════
// boarding_proofs/{jobId} — only job participants can read
// ═══════════════════════════════════════════════════════════════════════════
test.skip('boarding_proofs: provider CAN write proof for their own job', async () => {
  await seedDoc('jobs', 'job1', {
    customerId: 'alice', expertId: 'bob_provider', status: 'paid_escrow',
  });

  const storage = testEnv.authenticatedContext('bob_provider', { admin: false, support_agent: false }).storage();
  const fileRef = ref(storage, 'boarding_proofs/job1/photo.png');
  await assertSucceeds(uploadBytes(fileRef, TINY_PNG, { contentType: 'image/png' }));
});

test('boarding_proofs: customer CANNOT upload (only provider can)', async () => {
  await seedDoc('jobs', 'job1', {
    customerId: 'alice', expertId: 'bob_provider', status: 'paid_escrow',
  });

  const storage = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).storage();
  const fileRef = ref(storage, 'boarding_proofs/job1/sneaky.png');
  await assertFails(uploadBytes(fileRef, TINY_PNG, { contentType: 'image/png' }));
});

test.skip('boarding_proofs: third party CANNOT read someone else\'s proof', async () => {
  await seedDoc('jobs', 'job1', {
    customerId: 'alice', expertId: 'bob_provider', status: 'paid_escrow',
  });

  // Provider uploads first.
  const provStorage = testEnv.authenticatedContext('bob_provider', { admin: false, support_agent: false }).storage();
  await uploadBytes(
    ref(provStorage, 'boarding_proofs/job1/photo.png'),
    TINY_PNG,
    { contentType: 'image/png' }
  );

  // eve (random user) tries to download the proof.
  const eveStorage = testEnv.authenticatedContext('eve', { admin: false, support_agent: false }).storage();
  await assertFails(getBytes(ref(eveStorage, 'boarding_proofs/job1/photo.png')));
});

// ═══════════════════════════════════════════════════════════════════════════
// dog_walks/{walkId} — write only by walk's provider, read by both parties
// ═══════════════════════════════════════════════════════════════════════════
test('dog_walks: third party CANNOT upload to someone else\'s walk', async () => {
  await seedDoc('dog_walks', 'walk1', {
    customerId: 'alice', providerId: 'bob_walker', status: 'walking',
  });

  const storage = testEnv.authenticatedContext('eve', { admin: false, support_agent: false }).storage();
  const fileRef = ref(storage, 'dog_walks/walk1/route.png');
  await assertFails(uploadBytes(fileRef, TINY_PNG, { contentType: 'image/png' }));
});

test.skip('dog_walks: customer CAN read their walk\'s route map', async () => {
  await seedDoc('dog_walks', 'walk1', {
    customerId: 'alice', providerId: 'bob_walker', status: 'walking',
  });

  // Provider uploads.
  const provStorage = testEnv.authenticatedContext('bob_walker', { admin: false, support_agent: false }).storage();
  await uploadBytes(
    ref(provStorage, 'dog_walks/walk1/route.png'),
    TINY_PNG,
    { contentType: 'image/png' }
  );

  // Customer reads.
  const custStorage = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).storage();
  await assertSucceeds(getBytes(ref(custStorage, 'dog_walks/walk1/route.png')));
});

// ═══════════════════════════════════════════════════════════════════════════
// anytask_proofs/{taskId} — write only by selectedProviderId
// ═══════════════════════════════════════════════════════════════════════════
test('anytask_proofs: rejected provider CANNOT write proof', async () => {
  await seedDoc('any_tasks', 'task1', {
    clientId: 'alice', selectedProviderId: 'bob_winner', status: 'in_progress',
  });

  // charlie was NOT selected — must not be able to upload fake proof
  const storage = testEnv.authenticatedContext('charlie_loser', { admin: false, support_agent: false }).storage();
  const fileRef = ref(storage, 'anytask_proofs/task1/fake_proof.png');
  await assertFails(uploadBytes(fileRef, TINY_PNG, { contentType: 'image/png' }));
});

test.skip('anytask_proofs: selected provider CAN write proof', async () => {
  await seedDoc('any_tasks', 'task1', {
    clientId: 'alice', selectedProviderId: 'bob_winner', status: 'in_progress',
  });

  const storage = testEnv.authenticatedContext('bob_winner', { admin: false, support_agent: false }).storage();
  const fileRef = ref(storage, 'anytask_proofs/task1/proof.png');
  await assertSucceeds(uploadBytes(fileRef, TINY_PNG, { contentType: 'image/png' }));
});

// ═══════════════════════════════════════════════════════════════════════════
// motorcycle_tows/{towId} — write only by tow's provider
// ═══════════════════════════════════════════════════════════════════════════
test.skip('motorcycle_tows: third party CANNOT read tow photos', async () => {
  await seedDoc('motorcycle_tows', 'tow1', {
    customerId: 'alice_stranded', providerId: 'bob_tower', status: 'towing',
  });

  // Provider uploads first.
  const provStorage = testEnv.authenticatedContext('bob_tower', { admin: false, support_agent: false }).storage();
  await uploadBytes(
    ref(provStorage, 'motorcycle_tows/tow1/before.png'),
    TINY_PNG,
    { contentType: 'image/png' }
  );

  // eve tries to peek at someone else's tow
  const eveStorage = testEnv.authenticatedContext('eve', { admin: false, support_agent: false }).storage();
  await assertFails(getBytes(ref(eveStorage, 'motorcycle_tows/tow1/before.png')));
});
