/**
 * One-off local script: backfill `users/{uid}.goldHeartExpiresAt` for
 * Community v2 (Phase B migration, see CLAUDE.md community v2 section).
 *
 * Mirrors the deployed CF `backfillCommunityGoldHearts` logic via direct
 * Admin SDK access — no Firebase ID token, no curl, no callable
 * gymnastics. Same guards (sentinel doc + audit log) as the CF, so this
 * script and the CF SHARE state — running one prevents the other from
 * re-running.
 *
 * What it does:
 *   • Scans `users` where `lastVolunteerTaskAt > now - 30 days`.
 *   • For each user without an existing `goldHeartExpiresAt`, writes
 *     `goldHeartExpiresAt = lastVolunteerTaskAt + 30 days`. (Users with
 *     a stamp older than 30 days are NOT touched — they get a fresh
 *     heart on their next completion, per the chosen migration strategy.)
 *   • Writes sentinel `system_config/migrations/community_gold_heart_backfill_v1/status`
 *     with `completed: true` so the CF + this script both refuse to re-run.
 *   • Writes an `admin_audit_log` entry.
 *
 * Run (after `firebase login` OR with functions/service-account.json):
 *   cd functions
 *   node scripts/backfill-community-gold-hearts.js --dry-run   # preview
 *   node scripts/backfill-community-gold-hearts.js             # apply
 *
 * Re-run safety:
 *   • Idempotent — won't re-run while sentinel `completed: true` exists.
 *   • To force a re-run: delete the sentinel doc manually in the
 *     Firestore console at the path above, then run again.
 *   • `--dry-run` ignores the sentinel and always shows what WOULD happen.
 *
 * Cloud Shell:
 *   • Admin SDK auto-detects credentials from the Cloud Shell env — no
 *     extra setup needed. Just `cd functions && node scripts/...`.
 */

const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

// ── Args ─────────────────────────────────────────────────────────────────
const DRY_RUN = process.argv.includes("--dry-run");

// ── Constants (match the CF) ─────────────────────────────────────────────
const GOLD_HEART_DAYS = 30;
const MS_PER_DAY = 24 * 60 * 60 * 1000;
const BATCH_CHUNK = 400; // Firestore batch limit is 500 — leave headroom.
const SENTINEL_PATH = {
  collection: "system_config",
  doc: "migrations",
  subcollection: "community_gold_heart_backfill_v1",
  subdoc: "status",
};

// ── Credential resolution (same pattern as backfill-admin-claims.js) ─────
const SA_PATH = path.join(__dirname, "..", "service-account.json");
if (fs.existsSync(SA_PATH)) {
  console.log("[Backfill] Using explicit service-account.json credential");
  admin.initializeApp({
    credential: admin.credential.cert(require(SA_PATH)),
  });
} else {
  console.log("[Backfill] Using Application Default Credentials (gcloud / firebase login / Cloud Shell)");
  admin.initializeApp({
    projectId: "anyskill-6fdf3",
  });
}

const db = admin.firestore();

function sentinelRef() {
  return db
    .collection(SENTINEL_PATH.collection)
    .doc(SENTINEL_PATH.doc)
    .collection(SENTINEL_PATH.subcollection)
    .doc(SENTINEL_PATH.subdoc);
}

async function checkSentinel() {
  const snap = await sentinelRef().get();
  if (!snap.exists) return null;
  const d = snap.data() || {};
  return d.completed === true ? d : null;
}

function fmtTs(ts) {
  if (!ts) return "—";
  if (typeof ts.toDate === "function") return ts.toDate().toISOString();
  if (ts instanceof Date) return ts.toISOString();
  return String(ts);
}

async function main() {
  console.log(`[Backfill] DRY_RUN=${DRY_RUN}`);
  console.log(`[Backfill] Project: anyskill-6fdf3`);
  console.log(`[Backfill] Sentinel: /${SENTINEL_PATH.collection}/${SENTINEL_PATH.doc}/${SENTINEL_PATH.subcollection}/${SENTINEL_PATH.subdoc}`);
  console.log("");

  // ── Sentinel guard (mirror CF behavior) ───────────────────────────────
  const sentinel = await checkSentinel();
  if (sentinel && !DRY_RUN) {
    console.log("[Backfill] ⛔ Sentinel says backfill ALREADY RAN. Refusing to re-run.");
    console.log(`           previouslyCompletedAt: ${fmtTs(sentinel.completedAt)}`);
    console.log(`           previouslyCompletedBy: ${sentinel.completedBy || "—"}`);
    console.log(`           previousScanned:       ${sentinel.scanned ?? "—"}`);
    console.log(`           previousGranted:       ${sentinel.granted ?? "—"}`);
    console.log(`           previousSkipped:       ${sentinel.skipped ?? "—"}`);
    console.log("");
    console.log("[Backfill] To force a re-run: delete the sentinel doc in the Firestore console");
    console.log("           and run this script again. (The CF will also stop refusing.)");
    process.exit(0);
  }
  if (sentinel && DRY_RUN) {
    console.log("[Backfill] ⚠️  Sentinel says already-ran — but --dry-run ignores it.");
    console.log(`           previouslyCompletedAt: ${fmtTs(sentinel.completedAt)}`);
    console.log(`           (Continuing in read-only mode to show what a re-run WOULD do.)`);
    console.log("");
  } else {
    console.log("[Backfill] ✓ Sentinel clear — first run.");
    console.log("");
  }

  // ── Scan users ────────────────────────────────────────────────────────
  const cutoff = admin.firestore.Timestamp.fromDate(
    new Date(Date.now() - GOLD_HEART_DAYS * MS_PER_DAY),
  );
  console.log(`[Backfill] Querying users where lastVolunteerTaskAt > ${fmtTs(cutoff)}…`);
  const snap = await db
    .collection("users")
    .where("lastVolunteerTaskAt", ">", cutoff)
    .get();
  console.log(`[Backfill] Got ${snap.size} candidate user(s).`);
  console.log("");

  if (snap.empty) {
    console.log("[Backfill] No users to backfill. (Nobody volunteered in the last 30 days.)");
    if (!DRY_RUN) await markSentinel(0, 0, 0, []);
    process.exit(0);
  }

  // ── Plan / execute per user ───────────────────────────────────────────
  let granted = 0;
  let skipped = 0;
  const errors = [];
  const docs = snap.docs;

  for (let i = 0; i < docs.length; i += BATCH_CHUNK) {
    const chunk = docs.slice(i, i + BATCH_CHUNK);
    const batch = DRY_RUN ? null : db.batch();

    console.log(`[Backfill] Processing chunk ${Math.floor(i / BATCH_CHUNK) + 1} (rows ${i + 1}-${Math.min(i + BATCH_CHUNK, docs.length)} of ${docs.length})…`);

    for (const doc of chunk) {
      const uid = doc.id;
      const data = doc.data() || {};
      const email = data.email || "—";
      const name = (data.name || "").trim() || "—";

      // Skip if user already has the new field — don't overwrite an
      // authoritative value (could be from the CF + a real completion).
      if (data.goldHeartExpiresAt) {
        skipped++;
        const existing = fmtTs(data.goldHeartExpiresAt);
        console.log(`  − SKIP    ${uid}  (${name} / ${email})  — already has goldHeartExpiresAt=${existing}`);
        continue;
      }

      const lastTs = data.lastVolunteerTaskAt;
      if (!lastTs || typeof lastTs.toMillis !== "function") {
        skipped++;
        console.log(`  − SKIP    ${uid}  (${name} / ${email})  — lastVolunteerTaskAt missing or malformed`);
        continue;
      }

      const expiresAtMs = lastTs.toMillis() + GOLD_HEART_DAYS * MS_PER_DAY;
      const expiresAt = admin.firestore.Timestamp.fromMillis(expiresAtMs);
      const expiresIsoStr = new Date(expiresAtMs).toISOString();

      if (DRY_RUN) {
        console.log(`  ◌ WOULD   ${uid}  (${name} / ${email})  — lastVT=${fmtTs(lastTs)}  → goldHeartExpiresAt=${expiresIsoStr}`);
      } else {
        batch.update(doc.ref, { goldHeartExpiresAt: expiresAt });
        console.log(`  ✓ GRANT   ${uid}  (${name} / ${email})  → goldHeartExpiresAt=${expiresIsoStr}`);
      }
      granted++;
    }

    if (!DRY_RUN && batch) {
      try {
        await batch.commit();
        console.log(`[Backfill] ✓ Chunk committed.`);
      } catch (e) {
        const msg = String(e.message || e);
        errors.push({ chunkStart: i, error: msg });
        console.log(`[Backfill] ✗ Chunk commit FAILED: ${msg}`);
      }
    }
  }

  // ── Summary ──────────────────────────────────────────────────────────
  console.log("");
  console.log("══════════════════════════════════════════════════════════");
  console.log("  Summary");
  console.log("══════════════════════════════════════════════════════════");
  console.log(`  scanned:   ${snap.size}    (users with lastVolunteerTaskAt within ${GOLD_HEART_DAYS}d)`);
  console.log(`  granted:   ${granted}    (${DRY_RUN ? "would receive" : "received"} goldHeartExpiresAt)`);
  console.log(`  skipped:   ${skipped}    (already had goldHeartExpiresAt OR malformed lastVolunteerTaskAt)`);
  console.log(`  errors:    ${errors.length}`);
  if (errors.length) {
    console.log(`  errorSamples:`);
    errors.slice(0, 5).forEach((e) => {
      console.log(`    - chunk@${e.chunkStart}: ${e.error}`);
    });
  }
  console.log("");

  if (DRY_RUN) {
    console.log("[Backfill] DRY RUN — no writes performed.");
    console.log("[Backfill] Re-run WITHOUT --dry-run to apply the changes above.");
    process.exit(0);
  }

  // ── Mark sentinel + audit log (mirror CF) ─────────────────────────────
  await markSentinel(snap.size, granted, skipped, errors);

  console.log("[Backfill] Sentinel + audit log written. Done. ✨");
  console.log("");
  console.log("[Backfill] What this means:");
  console.log("  • The CF will now refuse to run too — single source of truth.");
  console.log("  • Future completions get a FRESH gold heart via the");
  console.log("    onCommunityRequestCompleted CF + client dual-write.");
  console.log("  • Verify: Firestore → /system_config/migrations/community_gold_heart_backfill_v1/status");
  console.log("    should show completed=true.");
  process.exit(0);
}

async function markSentinel(scanned, granted, skipped, errors) {
  const completedAt = admin.firestore.FieldValue.serverTimestamp();
  await sentinelRef().set({
    completed: true,
    completedAt,
    completedBy: "local_cli",
    runner: "backfill-community-gold-hearts.js",
    scanned,
    granted,
    skipped,
    errorCount: errors.length,
    errorSamples: errors.slice(0, 5),
  });

  // Audit trail (matches §50 admin_audit_log convention)
  try {
    await db.collection("admin_audit_log").add({
      action: "backfill_community_gold_hearts_local_script",
      adminUid: "local_cli",
      result: { scanned, granted, skipped, errorCount: errors.length },
      createdAt: completedAt,
    });
  } catch (e) {
    console.log(`[Backfill] (audit log write failed but main work succeeded: ${e.message || e})`);
  }
}

main().catch((e) => {
  console.error("[Backfill] FATAL:", e);
  process.exit(1);
});
