/**
 * cleanup_test_data.js
 * --------------------
 * Deletes all Firestore documents in the `users` collection where
 * `isDemo: true`.  Processes in batches of 500.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json node cleanup_test_data.js
 *
 * Requirements:
 *   npm install firebase-admin
 */

'use strict';

const admin = require('firebase-admin');

// ---------------------------------------------------------------------------
// Firebase init — Application Default Credentials (no hardcoded keys)
// ---------------------------------------------------------------------------
admin.initializeApp({
  projectId: 'anyskill-6fdf3',
});

const db = admin.firestore();

const BATCH_SIZE = 500;
const PROGRESS_INTERVAL = 100;

// ---------------------------------------------------------------------------
// Delete a single page of demo users, returns count deleted
// ---------------------------------------------------------------------------
async function deletePage(query) {
  const snapshot = await query.get();
  if (snapshot.empty) return 0;

  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  return snapshot.size;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  console.log('=== AnySkill Cleanup Script ===');
  console.log('Project  : anyskill-6fdf3');
  console.log('Target   : users collection, isDemo == true');
  console.log('');

  const startTime = Date.now();

  // First, count how many documents we're about to delete so we can give an
  // accurate estimate. (count() is a lightweight aggregation — no doc reads.)
  console.log('Counting demo documents...');
  const countSnap = await db
    .collection('users')
    .where('isDemo', '==', true)
    .count()
    .get();
  const totalToDelete = countSnap.data().count;
  console.log(`  Found ${totalToDelete} demo user(s) to delete.`);
  console.log('');

  if (totalToDelete === 0) {
    console.log('Nothing to clean up. Exiting.');
    return;
  }

  // Paginate using a cursor so we never load more than BATCH_SIZE docs at once.
  // We order by __name__ (document ID) to get a stable cursor.
  let totalDeleted = 0;
  let lastDoc = null;

  while (true) {
    let query = db
      .collection('users')
      .where('isDemo', '==', true)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(BATCH_SIZE);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    totalDeleted += snapshot.size;
    lastDoc = snapshot.docs[snapshot.docs.length - 1];

    if (totalDeleted % PROGRESS_INTERVAL === 0 || snapshot.size < BATCH_SIZE) {
      const pct = totalToDelete > 0
        ? ((totalDeleted / totalToDelete) * 100).toFixed(1)
        : '100.0';
      console.log(
        `  Deleted ${totalDeleted} / ${totalToDelete} (${pct}%)`
      );
    }

    // If the page was smaller than BATCH_SIZE we've reached the end
    if (snapshot.size < BATCH_SIZE) break;
  }

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);

  console.log('');
  console.log('=== SUMMARY ===');
  console.log(`  Documents deleted : ${totalDeleted}`);
  console.log(`  Elapsed time      : ${elapsed}s`);
  console.log('');
  console.log('Cleanup complete.');
}

main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
