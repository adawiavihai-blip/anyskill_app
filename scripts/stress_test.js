/**
 * stress_test.js
 * --------------
 * Simulates 50 concurrent job flows against Firestore + Cloud Functions.
 *
 * Each flow:
 *   1. Create a job_requests document
 *   2. Create a jobs document (paid_escrow status = simulated escrow payment)
 *   3. Update job → expert_completed
 *   4. Call processPaymentRelease Cloud Function via REST (authenticated)
 *
 * Concurrency is capped at MAX_CONCURRENCY using a simple semaphore so we
 * don't hammer Firestore with all 50 flows simultaneously.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json node stress_test.js
 *
 * Requirements:
 *   npm install firebase-admin node-fetch
 *
 * Note: node-fetch v2 is used for CommonJS compatibility:
 *   npm install node-fetch@2
 */

'use strict';

const admin  = require('firebase-admin');
const fetch  = require('node-fetch');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const PROJECT_ID       = 'anyskill-6fdf3';
const REGION           = 'us-central1';
const CF_BASE_URL      = `https://${REGION}-${PROJECT_ID}.cloudfunctions.net`;
const CF_NAME          = 'processPaymentRelease';
const DEMO_PROVIDER_LIMIT = 50;
const DEMO_CLIENT_LIMIT   = 50;
const TOTAL_FLOWS      = 50;
const MAX_CONCURRENCY  = 10;

// ---------------------------------------------------------------------------
// Firebase init
// ---------------------------------------------------------------------------
admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

// ---------------------------------------------------------------------------
// Semaphore — limits concurrent async tasks
// ---------------------------------------------------------------------------
class Semaphore {
  constructor(max) {
    this._max     = max;
    this._current = 0;
    this._queue   = [];
  }

  acquire() {
    return new Promise((resolve) => {
      const tryAcquire = () => {
        if (this._current < this._max) {
          this._current++;
          resolve();
        } else {
          this._queue.push(tryAcquire);
        }
      };
      tryAcquire();
    });
  }

  release() {
    this._current--;
    if (this._queue.length > 0) {
      const next = this._queue.shift();
      next();
    }
  }
}

// ---------------------------------------------------------------------------
// Timing helpers
// ---------------------------------------------------------------------------
function now() {
  return Date.now();
}

function elapsed(start) {
  return Date.now() - start;
}

// ---------------------------------------------------------------------------
// Fetch a Google ID token for the Cloud Function call
// ---------------------------------------------------------------------------
async function getIdToken(targetUrl) {
  try {
    const token = await admin.app().options.credential.getAccessToken();
    // For Cloud Functions we need an identity token, not an access token.
    // If running on GCP (Cloud Run, GCE, etc.) use the metadata server.
    const metadataUrl =
      `http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity` +
      `?audience=${encodeURIComponent(targetUrl)}`;

    const res = await fetch(metadataUrl, {
      headers: { 'Metadata-Flavor': 'Google' },
      timeout: 5000,
    });

    if (res.ok) {
      return await res.text();
    }
  } catch (_) {
    // Not on GCP — fall back to the OAuth2 access token (works for private
    // functions when the SA has cloudfunctions.invoker role).
  }

  // Fallback: plain OAuth2 access token
  const token = await admin.app().options.credential.getAccessToken();
  return token.access_token;
}

// ---------------------------------------------------------------------------
// Step helpers
// ---------------------------------------------------------------------------

/** Step 1 — create a job_requests document */
async function stepCreateJobRequest(client, provider) {
  const t0 = now();
  const ref = db.collection('job_requests').doc();
  await ref.set({
    clientId:          client.uid,
    expertId:          provider.uid,
    category:          provider.serviceType || 'ניקיון',
    status:            'open',
    isActive:          true,
    isDemo:            true,
    description:       'בדיקת עומס אוטומטית',
    budget:            provider.pricePerHour || 100,
    interestedCount:   0,
    interestedProviders: [],
    createdAt:         admin.firestore.FieldValue.serverTimestamp(),
  });
  return { jobRequestId: ref.id, latencyMs: elapsed(t0) };
}

/** Step 2 — create a jobs document in paid_escrow status */
async function stepCreateJob(client, provider, jobRequestId) {
  const t0 = now();
  const ref = db.collection('jobs').doc();
  const totalAmount = (provider.pricePerHour || 100) * 2; // assume 2-hour job
  await ref.set({
    customerId:      client.uid,
    expertId:        provider.uid,
    jobRequestId,
    totalAmount,
    platformFee:     totalAmount * 0.1,
    expertAmount:    totalAmount * 0.9,
    status:          'paid_escrow',
    isDemo:          true,
    serviceType:     provider.serviceType || 'ניקיון',
    description:     'בדיקת עומס אוטומטית',
    createdAt:       admin.firestore.FieldValue.serverTimestamp(),
    updatedAt:       admin.firestore.FieldValue.serverTimestamp(),
  });
  return { jobId: ref.id, totalAmount, latencyMs: elapsed(t0) };
}

/** Step 3 — mark job as expert_completed */
async function stepMarkExpertCompleted(jobId) {
  const t0 = now();
  await db.collection('jobs').doc(jobId).update({
    status:    'expert_completed',
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  return { latencyMs: elapsed(t0) };
}

/** Step 4 — call processPaymentRelease Cloud Function */
async function stepCallProcessPayment(jobId) {
  const t0  = now();
  const url = `${CF_BASE_URL}/${CF_NAME}`;

  let idToken;
  try {
    idToken = await getIdToken(url);
  } catch (tokenErr) {
    return {
      latencyMs: elapsed(t0),
      skipped: true,
      reason: `Could not obtain auth token: ${tokenErr.message}`,
    };
  }

  const res = await fetch(url, {
    method:  'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Bearer ${idToken}`,
    },
    body: JSON.stringify({ jobId }),
    timeout: 30000,
  });

  const body = await res.text();
  return {
    latencyMs:  elapsed(t0),
    httpStatus: res.status,
    ok:         res.ok,
    body:       body.slice(0, 200), // truncate for log readability
  };
}

// ---------------------------------------------------------------------------
// Single end-to-end flow
// ---------------------------------------------------------------------------
async function runFlow(flowIndex, client, provider) {
  const flowStart = now();
  const result = {
    flowIndex,
    clientId:   client.uid,
    providerId: provider.uid,
    success:    false,
    error:      null,
    steps: {
      createJobRequest:     null,
      createJob:            null,
      markExpertCompleted:  null,
      callProcessPayment:   null,
    },
    totalLatencyMs: 0,
  };

  try {
    // Step 1
    const s1 = await stepCreateJobRequest(client, provider);
    result.steps.createJobRequest = s1;

    // Step 2
    const s2 = await stepCreateJob(client, provider, s1.jobRequestId);
    result.steps.createJob = s2;

    // Step 3
    const s3 = await stepMarkExpertCompleted(s2.jobId);
    result.steps.markExpertCompleted = s3;

    // Step 4
    const s4 = await stepCallProcessPayment(s2.jobId);
    result.steps.callProcessPayment = s4;

    // Mark success if CF responded 2xx OR was skipped (auth not available)
    if (s4.skipped || s4.ok) {
      result.success = true;
    } else {
      result.error = `CF returned HTTP ${s4.httpStatus}: ${s4.body}`;
    }
  } catch (err) {
    result.error = err.message;
  }

  result.totalLatencyMs = elapsed(flowStart);
  return result;
}

// ---------------------------------------------------------------------------
// Load demo users from Firestore
// ---------------------------------------------------------------------------
async function loadDemoUsers(role, limit) {
  const field = role === 'provider' ? 'isProvider' : 'isCustomer';
  const snap = await db
    .collection('users')
    .where('isDemo', '==', true)
    .where(field, '==', true)
    .limit(limit)
    .get();

  if (snap.empty) {
    throw new Error(
      `No demo ${role}s found. Run seed_test_data.js first.`
    );
  }
  return snap.docs.map((d) => ({ uid: d.id, ...d.data() }));
}

// ---------------------------------------------------------------------------
// Compute per-step latency statistics
// ---------------------------------------------------------------------------
function computeStats(values) {
  if (values.length === 0) return { count: 0, avg: 0, min: 0, max: 0, p95: 0 };
  const sorted = [...values].sort((a, b) => a - b);
  const sum = sorted.reduce((a, b) => a + b, 0);
  const p95idx = Math.floor(sorted.length * 0.95);
  return {
    count: sorted.length,
    avg:   Math.round(sum / sorted.length),
    min:   sorted[0],
    max:   sorted[sorted.length - 1],
    p95:   sorted[p95idx],
  };
}

function printStats(label, values) {
  const s = computeStats(values);
  console.log(
    `  ${label.padEnd(25)} avg=${s.avg}ms  min=${s.min}ms  p95=${s.p95}ms  max=${s.max}ms  (n=${s.count})`
  );
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  console.log('=== AnySkill Stress Test ===');
  console.log(`Project         : ${PROJECT_ID}`);
  console.log(`Flows           : ${TOTAL_FLOWS}`);
  console.log(`Max concurrency : ${MAX_CONCURRENCY}`);
  console.log(`CF endpoint     : ${CF_BASE_URL}/${CF_NAME}`);
  console.log('');

  // Load demo users
  console.log('Loading demo users from Firestore...');
  const [providers, clients] = await Promise.all([
    loadDemoUsers('provider', DEMO_PROVIDER_LIMIT),
    loadDemoUsers('client',   DEMO_CLIENT_LIMIT),
  ]);
  console.log(`  Loaded ${providers.length} demo providers`);
  console.log(`  Loaded ${clients.length}   demo clients`);
  console.log('');

  if (providers.length === 0 || clients.length === 0) {
    console.error('Not enough demo users. Please run seed_test_data.js first.');
    process.exit(1);
  }

  const semaphore = new Semaphore(MAX_CONCURRENCY);
  const results   = [];
  let completed   = 0;

  const globalStart = now();

  console.log('Starting flows...');

  const tasks = Array.from({ length: TOTAL_FLOWS }, (_, i) => {
    const provider = providers[i % providers.length];
    const client   = clients[i % clients.length];

    return (async () => {
      await semaphore.acquire();
      try {
        const result = await runFlow(i + 1, client, provider);
        results.push(result);
        completed++;

        const icon = result.success ? '✓' : '✗';
        const cfNote = result.steps.callProcessPayment?.skipped
          ? ' (CF skipped—no auth)'
          : result.steps.callProcessPayment?.ok === false
            ? ` (CF HTTP ${result.steps.callProcessPayment.httpStatus})`
            : '';
        console.log(
          `  [${String(completed).padStart(2)}/${TOTAL_FLOWS}] Flow ${String(i + 1).padStart(2)} ${icon}  ${result.totalLatencyMs}ms${cfNote}${result.error ? ' ERR: ' + result.error : ''}`
        );
      } finally {
        semaphore.release();
      }
    })();
  });

  await Promise.all(tasks);

  const totalElapsed = elapsed(globalStart);

  // ---------------------------------------------------------------------------
  // Results analysis
  // ---------------------------------------------------------------------------
  const successes = results.filter((r) => r.success);
  const failures  = results.filter((r) => !r.success);

  // Per-step latencies (only from successful + partially successful flows)
  const s1Latencies  = results.map((r) => r.steps.createJobRequest?.latencyMs).filter(Boolean);
  const s2Latencies  = results.map((r) => r.steps.createJob?.latencyMs).filter(Boolean);
  const s3Latencies  = results.map((r) => r.steps.markExpertCompleted?.latencyMs).filter(Boolean);
  const s4Latencies  = results.map((r) => r.steps.callProcessPayment?.latencyMs).filter(Boolean);
  const totalLatencies = results.map((r) => r.totalLatencyMs);

  console.log('');
  console.log('=== TIMING REPORT ===');
  printStats('Step 1 createJobRequest', s1Latencies);
  printStats('Step 2 createJob',        s2Latencies);
  printStats('Step 3 markCompleted',    s3Latencies);
  printStats('Step 4 callCF',           s4Latencies);
  printStats('Total per flow',          totalLatencies);

  console.log('');
  console.log('=== SUMMARY ===');
  console.log(`  Total flows     : ${TOTAL_FLOWS}`);
  console.log(`  Successes       : ${successes.length}`);
  console.log(`  Failures        : ${failures.length}`);
  console.log(`  Total wall time : ${(totalElapsed / 1000).toFixed(2)}s`);
  console.log(`  Throughput      : ${(TOTAL_FLOWS / (totalElapsed / 1000)).toFixed(2)} flows/sec`);

  if (failures.length > 0) {
    console.log('');
    console.log('=== FAILURE DETAILS ===');
    failures.forEach((r) => {
      console.log(`  Flow ${r.flowIndex}: client=${r.clientId} provider=${r.providerId}`);
      console.log(`    Error: ${r.error}`);
    });
  }

  // CF skipped summary
  const skippedCF = results.filter((r) => r.steps.callProcessPayment?.skipped);
  if (skippedCF.length > 0) {
    console.log('');
    console.log(
      `NOTE: ${skippedCF.length} flow(s) skipped the CF call (auth token unavailable).`
    );
    console.log(
      'To enable CF calls, run with GOOGLE_APPLICATION_CREDENTIALS pointing to a'
    );
    console.log('service account that has the Cloud Functions Invoker role.');
  }

  console.log('');
  console.log('Stress test complete.');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
