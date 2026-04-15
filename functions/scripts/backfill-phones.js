/**
 * One-off local script: attach every users/{uid}.phone to the matching
 * Firebase Auth account via admin.auth().updateUser(uid, { phoneNumber }).
 *
 * Why: before v12.5 removed email/password login, some users had NO phone
 * attached to their Firebase Auth account. When they switch to phone login,
 * Firebase creates a new uid — their legacy data is orphaned. This script
 * links each legacy user's phone to their existing Auth uid so future phone
 * logins route to the original uid.
 *
 * Idempotent — skips users already carrying the correct phoneNumber in Auth.
 *
 * Run:
 *   cd functions
 *   node scripts/backfill-phones.js
 *
 * Requires: `firebase login` completed (uses application default credentials).
 */

const admin = require("firebase-admin");

// Use the project that firebase-tools is logged into.
admin.initializeApp({
  projectId: "anyskill-6fdf3",
});

function normalizeE164(raw) {
  if (!raw) return null;
  const digits = String(raw).replace(/\D/g, "");
  if (!digits) return null;
  if (digits.length === 10 && digits.startsWith("0")) {
    return "+972" + digits.substring(1);
  }
  if (String(raw).startsWith("+")) return String(raw);
  return "+" + digits;
}

async function main() {
  const db = admin.firestore();
  console.log("[Backfill] Reading users with a phone field…");

  const snap = await db.collection("users").where("phone", ">", "").get();
  console.log(`[Backfill] Found ${snap.size} user docs with a phone.`);

  let scanned = 0;
  let updated = 0;
  let skipped = 0;
  let errors = 0;
  const errorSamples = [];

  for (const doc of snap.docs) {
    scanned++;
    const data = doc.data();
    const e164 = normalizeE164(data.phone);
    if (!e164 || e164.length < 10) {
      skipped++;
      continue;
    }

    try {
      let authUser;
      try {
        authUser = await admin.auth().getUser(doc.id);
      } catch (_) {
        // Auth record missing — maybe orphan Firestore doc. Skip.
        skipped++;
        continue;
      }

      if (authUser.phoneNumber === e164) {
        skipped++;
        continue;
      }

      await admin.auth().updateUser(doc.id, { phoneNumber: e164 });
      updated++;
      console.log(`  ✓ linked ${doc.id} → ${e164} (${data.name || "no-name"})`);
    } catch (e) {
      errors++;
      if (errorSamples.length < 10) {
        errorSamples.push({ uid: doc.id, error: String(e.message || e) });
      }
      console.log(`  ✗ ${doc.id}: ${e.message || e}`);
    }
  }

  console.log("\n[Backfill] Summary:");
  console.log(`  scanned: ${scanned}`);
  console.log(`  updated: ${updated}`);
  console.log(`  skipped: ${skipped}`);
  console.log(`  errors:  ${errors}`);
  if (errorSamples.length) {
    console.log(`  errorSamples:`);
    errorSamples.forEach((s) => console.log(`    - ${s.uid}: ${s.error}`));
  }

  // Audit trail
  await db.collection("admin_audit_log").add({
    action: "backfill_phones_to_auth_local_script",
    adminUid: "local_cli",
    scanned, updated, skipped, errors, errorSamples,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log("\n[Backfill] Audit log written. Done.");
  process.exit(0);
}

main().catch((e) => {
  console.error("[Backfill] FATAL:", e);
  process.exit(1);
});
