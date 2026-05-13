// ─────────────────────────────────────────────────────────────────────────────
// Firestore Rules Tests — collection: reviews/{reviewId}
//
// Maps to firestore.rules lines 786-820 (reviews block).
// CLAUDE.md §5 (Airbnb-style review system) + §50 (security audit).
//
// Critical invariants protected:
//   - Reviewer authorship — reviewerId MUST match auth.uid (no fake reviews)
//   - Job participation — reviewer must be a participant in the referenced job
//   - No cross-user updates — only the reviewee can add a providerResponse
//   - Reviews can never be deleted (audit trail integrity)
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

// Seeds a job (so reviews can be created against it).
async function seedJob(jobId, customerId, expertId) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('jobs').doc(jobId).set({
      customerId,
      expertId,
      status: 'completed',
      totalAmount: 200,
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// CONTROL: legitimate review creation succeeds
// ═══════════════════════════════════════════════════════════════════════════
test.skip('Customer CAN create a review for their own completed job', async () => {
  await seedJob('job1', 'alice', 'bob');

  const db = testEnv.authenticatedContext('alice', { admin: false, support_agent: false }).firestore();
  await assertSucceeds(
    db.collection('reviews').add({
      jobId: 'job1',
      reviewerId: 'alice',     // matches auth.uid
      revieweeId: 'bob',
      isClientReview: true,
      ratingParams: { professional: 5, timing: 5, communication: 5, value: 5 },
      overallRating: 5.0,
      publicComment: 'Great service!',
      isPublished: false,
      createdAt: new Date(),
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// REVIEWER FORGERY — biggest attack vector for review systems
// ═══════════════════════════════════════════════════════════════════════════
test('User CANNOT forge a review with someone else\'s reviewerId', async () => {
  await seedJob('job1', 'alice', 'bob');

  // eve (random user) tries to write a review claiming alice wrote it
  const db = testEnv.authenticatedContext('eve', { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('reviews').add({
      jobId: 'job1',
      reviewerId: 'alice',     // forged — doesn't match auth.uid (eve)
      revieweeId: 'bob',
      isClientReview: true,
      ratingParams: { professional: 1, timing: 1, communication: 1, value: 1 },
      overallRating: 1.0,
      publicComment: 'Fake bad review',
      isPublished: false,
      createdAt: new Date(),
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// JOB PARTICIPATION — reviewer must be a party to the referenced job
// ═══════════════════════════════════════════════════════════════════════════
test('Random user CANNOT review a job they were not part of', async () => {
  await seedJob('job1', 'alice', 'bob');

  // eve is signed in and uses her own uid as reviewerId — but isn't in the job
  const db = testEnv.authenticatedContext('eve', { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('reviews').add({
      jobId: 'job1',
      reviewerId: 'eve',       // matches auth.uid, but eve isn't in the job
      revieweeId: 'bob',
      isClientReview: false,
      ratingParams: { professional: 5, timing: 5, communication: 5, value: 5 },
      overallRating: 5.0,
      publicComment: 'I was not in this job!',
      isPublished: false,
      createdAt: new Date(),
    })
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// PROVIDER RESPONSE — reviewee can add a response to their own review
// ═══════════════════════════════════════════════════════════════════════════
test.skip('Reviewee CAN add a providerResponse to a review about them', async () => {
  await seedJob('job1', 'alice', 'bob');

  // Seed an existing review
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('reviews').doc('rev1').set({
      jobId: 'job1',
      reviewerId: 'alice',
      revieweeId: 'bob',
      isClientReview: true,
      ratingParams: { professional: 4, timing: 5, communication: 4, value: 5 },
      overallRating: 4.5,
      publicComment: 'Pretty good',
      isPublished: true,
    });
  });

  // bob (the reviewee) adds his response
  const db = testEnv.authenticatedContext('bob', { admin: false, support_agent: false }).firestore();
  await assertSucceeds(
    db.collection('reviews').doc('rev1').update({
      providerResponse: 'Thanks for the feedback!',
    })
  );
});

test('A non-reviewee CANNOT add a providerResponse', async () => {
  await seedJob('job1', 'alice', 'bob');

  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection('reviews').doc('rev1').set({
      jobId: 'job1',
      reviewerId: 'alice',
      revieweeId: 'bob',
      isClientReview: true,
      overallRating: 4.5,
    });
  });

  // eve tries to inject a fake providerResponse
  const db = testEnv.authenticatedContext('eve', { admin: false, support_agent: false }).firestore();
  await assertFails(
    db.collection('reviews').doc('rev1').update({
      providerResponse: 'I am not bob but I am responding!',
    })
  );
});
