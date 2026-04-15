#!/usr/bin/env node
/**
 * One-time migration script: Creates provider_listings docs for all existing providers.
 *
 * Usage:
 *   cd functions
 *   node run_migration.js
 *
 * This runs LOCALLY using the Admin SDK service account from your Firebase project.
 * It bypasses Cloud Functions auth checks — same logic as migrateProvidersToListings.
 *
 * Safe to run multiple times (idempotent — skips already-migrated providers).
 */

const admin = require("firebase-admin");
const path = require("path");

// Initialize with local service account JSON file.
const serviceAccount = require(path.join(__dirname, "service-account.json"));

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: "anyskill-6fdf3",
  });
}

const db = admin.firestore();

async function migrate() {
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("  AnySkill v10.1.0 — Provider Listings Migration");
  console.log("═══════════════════════════════════════════════════════════════\n");

  let migrated = 0;
  let skipped = 0;
  let errors = 0;
  let lastDoc = null;

  // Process in batches of 100
  while (true) {
    let query = db.collection("users")
      .where("isProvider", "==", true)
      .orderBy("__name__")
      .limit(100);

    if (lastDoc) query = query.startAfter(lastDoc);

    const snap = await query.get();
    if (snap.empty) break;
    lastDoc = snap.docs[snap.docs.length - 1];

    const batch = db.batch();
    let batchCount = 0;

    for (const doc of snap.docs) {
      const u = doc.data();
      const uid = doc.id;

      // Skip if already migrated
      if (u.listingIds && u.listingIds.length > 0) {
        skipped++;
        continue;
      }

      // Skip if no serviceType
      const serviceType = u.serviceType || "";
      if (!serviceType || serviceType === "לקוח") {
        skipped++;
        continue;
      }

      try {
        const listingRef = db.collection("provider_listings").doc();
        batch.set(listingRef, {
          uid,
          identityIndex: 0,
          // Denormalized shared fields
          name: u.name || u.fullName || "",
          profileImage: u.profileImage || "",
          isVerified: u.isVerified || false,
          isHidden: u.isHidden || false,
          isDemo: u.isDemo || false,
          isVolunteer: u.isVolunteer || false,
          isOnline: u.isOnline || false,
          isAnySkillPro: u.isAnySkillPro || false,
          isPromoted: u.isPromoted || false,
          profileBoostUntil: u.profileBoostUntil || null,
          latitude: u.latitude || null,
          longitude: u.longitude || null,
          geohash: u.geohash || null,
          // Identity-specific
          serviceType,
          parentCategory: u.parentCategory || "",
          subCategory: u.subCategory || "",
          aboutMe: u.aboutMe || "",
          pricePerHour: u.pricePerHour || 0,
          gallery: u.gallery || [],
          categoryDetails: u.categoryDetails || {},
          priceList: u.priceList || {},
          quickTags: u.quickTags || [],
          workingHours: u.workingHours || {},
          cancellationPolicy: u.cancellationPolicy || "flexible",
          // Ratings (carry over)
          rating: u.rating || 5.0,
          reviewsCount: u.reviewsCount || 0,
          // Metadata
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Update user doc with listing reference
        batch.update(doc.ref, {
          listingIds: [listingRef.id],
          activeIdentityCount: 1,
        });

        batchCount++;
        migrated++;

        // Log each provider for transparency
        process.stdout.write(`  ✓ ${u.name || uid} (${serviceType})\n`);
      } catch (e) {
        errors++;
        console.error(`  ✗ ${uid}: ${e.message}`);
      }
    }

    if (batchCount > 0) {
      await batch.commit();
      console.log(`\n  [Batch committed: ${batchCount} providers]\n`);
    }
  }

  // ── Phase 2: Backfill reviews with listingId ──────────────────────────────
  console.log("\n── Backfilling reviews with listingId ──────────────────────\n");
  let reviewsBackfilled = 0;

  // Find reviews that don't have a listingId yet
  const reviewSnap = await db.collection("reviews")
    .limit(500)
    .get();

  if (!reviewSnap.empty) {
    // Cache: uid → primary listingId
    const listingCache = {};
    const reviewBatch = db.batch();
    let reviewBatchCount = 0;

    for (const revDoc of reviewSnap.docs) {
      const rev = revDoc.data();

      // Skip if already has listingId
      if (rev.listingId) continue;

      const revieweeId = rev.revieweeId || rev.expertId;
      if (!revieweeId) continue;

      // Look up or cache the primary listing for this reviewee
      if (!listingCache[revieweeId]) {
        const listingSnap = await db.collection("provider_listings")
          .where("uid", "==", revieweeId)
          .where("identityIndex", "==", 0)
          .limit(1)
          .get();
        listingCache[revieweeId] = listingSnap.empty ? null : listingSnap.docs[0].id;
      }

      const listingId = listingCache[revieweeId];
      if (listingId) {
        reviewBatch.update(revDoc.ref, { listingId });
        reviewBatchCount++;
        reviewsBackfilled++;
      }
    }

    if (reviewBatchCount > 0) {
      await reviewBatch.commit();
    }
  }

  // ── Summary ─────────────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════════════════════");
  console.log("  MIGRATION COMPLETE");
  console.log("═══════════════════════════════════════════════════════════════");
  console.log(`  ✓ Providers migrated:    ${migrated}`);
  console.log(`  ○ Providers skipped:     ${skipped} (already migrated or no serviceType)`);
  console.log(`  ✗ Errors:                ${errors}`);
  console.log(`  📝 Reviews backfilled:   ${reviewsBackfilled}`);
  console.log("═══════════════════════════════════════════════════════════════\n");

  if (errors > 0) {
    console.log("⚠️  Some providers failed — re-run the script to retry them.\n");
  }
}

migrate()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("\n❌ Migration failed:", e);
    process.exit(1);
  });
