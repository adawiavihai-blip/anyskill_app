/**
 * One-off local script: sync Firebase Auth Custom Claims with the
 * admin/support_agent role data in Firestore.
 *
 * v15.x security audit Round C (2026-04-25). Rationale + behavior:
 *   • Custom Claims are signed by Firebase and CANNOT be forged from the
 *     client (unlike Firestore fields, which depend on a perfect rule
 *     blocklist). Migrating role-based access to claims is defense in
 *     depth at the protocol layer.
 *   • The setUserRole CF already dual-writes claims for every NEW role
 *     change. This script syncs all EXISTING admins/agents that pre-date
 *     the dual-write change.
 *   • Idempotent — re-running rewrites the same claims; safe to call
 *     multiple times.
 *   • On role REMOVAL, also revokes refresh tokens so the demotion
 *     takes effect within ~1h instead of waiting for natural expiry.
 *
 * Why a local script and not the CF: callable v2 functions are awkward
 * to invoke from `firebase functions:shell` (the shell doesn't auto-
 * wrap `{data: ...}` correctly). This local script does the same work
 * via direct Admin SDK access — using the same Application Default
 * Credentials that `firebase login` already provisioned.
 *
 * Run:
 *   cd functions
 *   node scripts/backfill-admin-claims.js
 *
 * Optional dry-run (preview without writing claims):
 *   node scripts/backfill-admin-claims.js --dry-run
 *
 * Requires: `firebase login` completed (uses Application Default
 * Credentials).
 */

const admin = require("firebase-admin");

const DRY_RUN = process.argv.includes("--dry-run");

// Use the project that firebase-tools is logged into.
admin.initializeApp({
  projectId: "anyskill-6fdf3",
});

async function main() {
  const db = admin.firestore();

  console.log(`[Backfill] DRY_RUN=${DRY_RUN}`);
  console.log("[Backfill] Listing all Firebase Auth users…");

  let scanned = 0;
  let updated = 0;
  let cleared = 0;
  let skipped = 0;
  let errors = 0;
  const errorSamples = [];
  let pageToken;

  do {
    const list = await admin.auth().listUsers(1000, pageToken);

    for (const authUser of list.users) {
      scanned++;
      const uid = authUser.uid;
      try {
        const snap = await db.collection("users").doc(uid).get();
        const d = snap.exists ? (snap.data() || {}) : {};
        const roles = Array.isArray(d.roles) ? d.roles : [];
        const desiredAdmin =
          d.isAdmin === true
          || d.role === "admin"
          || roles.includes("admin");
        const desiredSupport =
          d.role === "support_agent"
          || roles.includes("support_agent");

        const cur = authUser.customClaims || {};
        const curAdmin = cur.admin === true;
        const curSupport = cur.support_agent === true;

        // Skip if claims already match.
        if (curAdmin === desiredAdmin && curSupport === desiredSupport) {
          skipped++;
          continue;
        }

        const isPrivilegeRemoval =
          (curAdmin && !desiredAdmin)
          || (curSupport && !desiredSupport);

        if (DRY_RUN) {
          console.log(
            `  [would update] ${authUser.email || uid}: ` +
            `admin ${curAdmin}→${desiredAdmin}, support ${curSupport}→${desiredSupport}`
          );
        } else {
          await admin.auth().setCustomUserClaims(uid, {
            admin: desiredAdmin,
            support_agent: desiredSupport,
          });
          if (isPrivilegeRemoval) {
            await admin.auth().revokeRefreshTokens(uid);
          }
          console.log(
            `  ✓ ${authUser.email || uid}: ` +
            `admin=${desiredAdmin} support=${desiredSupport}` +
            (isPrivilegeRemoval ? " (refresh tokens revoked)" : "")
          );
        }

        if (!desiredAdmin && !desiredSupport && (curAdmin || curSupport)) {
          cleared++;
        } else {
          updated++;
        }
      } catch (e) {
        errors++;
        if (errorSamples.length < 10) {
          errorSamples.push({ uid, error: String(e.message || e) });
        }
        console.log(`  ✗ ${uid}: ${e.message || e}`);
      }
    }

    pageToken = list.pageToken;
  } while (pageToken);

  console.log("\n[Backfill] Summary:");
  console.log(`  scanned: ${scanned}`);
  console.log(`  updated: ${updated}  (claim added or changed)`);
  console.log(`  cleared: ${cleared}  (stale claim removed)`);
  console.log(`  skipped: ${skipped}  (already in sync)`);
  console.log(`  errors:  ${errors}`);
  if (errorSamples.length) {
    console.log(`  errorSamples:`);
    errorSamples.forEach((s) => console.log(`    - ${s.uid}: ${s.error}`));
  }

  if (!DRY_RUN) {
    // Audit trail
    await db.collection("admin_audit_log").add({
      action: "backfill_admin_claims_local_script",
      adminUid: "local_cli",
      scanned, updated, cleared, skipped, errors, errorSamples,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log("\n[Backfill] Audit log written. Done.");
    console.log(
      "\n[Backfill] NEXT: every user whose claim changed must sign out + " +
      "back in (or wait ≤1h) for their new JWT to include the claim."
    );
  } else {
    console.log("\n[Backfill] Dry run — no changes written. " +
      "Re-run without --dry-run to apply.");
  }

  process.exit(0);
}

main().catch((e) => {
  console.error("[Backfill] FATAL:", e);
  process.exit(1);
});
