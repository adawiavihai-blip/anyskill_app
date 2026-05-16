/**
 * Companion to migrate-community-evidence.js (security audit VULN-009).
 *
 * The file-copy script moves the evidence PHOTOS to the new nested Storage
 * path. But each photo's download URL is also persisted in Firestore at
 * `community_requests/{docId}.completionPhotoUrl` (see
 * community_hub_service.dart → markTaskDone). Those stored URLs still point
 * at the OLD flat path and will 404 once the new storage.rules deploy.
 *
 * This script rewrites `completionPhotoUrl` to reference the new nested
 * path, using the mapping JSON the file-copy script produced.
 *
 * How the rewrite works (surgical + safe):
 *   • For each mapping entry it computes the URL-encoded OLD and NEW object
 *     paths (`/` → `%2F`).
 *   • If the stored URL CONTAINS the encoded old path, it swaps ONLY that
 *     path segment — leaving the real `?alt=media&token=...` untouched. The
 *     GCS copy preserved the download token, so the token is still valid
 *     for the new path.
 *   • If the stored URL already references the new path → skipped.
 *   • If it references neither → left alone + logged (never blind-overwrite).
 *
 * SAFE BY DEFAULT: dry run unless you pass --apply. --apply additionally
 * REFUSES to run unless the mapping JSON was produced by a real (--apply)
 * file-copy run — so you cannot point Firestore at files that were never
 * actually copied.
 *
 * Run (from the functions/ directory) — AFTER migrate-community-evidence.js
 * has been run with --apply:
 *   node scripts/rewrite-community-evidence-urls.js            # dry run
 *   node scripts/rewrite-community-evidence-urls.js --apply    # write
 *
 * Idempotent — re-running skips docs already pointing at the new path.
 *
 * Requires: functions/service-account.json (gitignored) OR Application
 * Default Credentials (`firebase login`).
 */

const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

const APPLY = process.argv.includes("--apply");
const PROJECT_ID = "anyskill-6fdf3";
const MAP_PATH = path.join(__dirname, "community-evidence-migration-map.json");

// ── Credentials (ordered): explicit SA file → Application Default ─────────
const SA_PATH = path.join(__dirname, "..", "service-account.json");
if (fs.existsSync(SA_PATH)) {
  console.log("[Rewrite] Using explicit service-account.json credential");
  admin.initializeApp({
    credential: admin.credential.cert(require(SA_PATH)),
  });
} else {
  console.log("[Rewrite] Using Application Default Credentials");
  admin.initializeApp({ projectId: PROJECT_ID });
}

async function main() {
  console.log("\n=== community_requests.completionPhotoUrl rewrite (VULN-009) ===");
  console.log(`  mode: ${APPLY ? "APPLY (writing)" : "DRY RUN (no writes)"}`);

  // ── Load + validate the mapping JSON ───────────────────────────────────
  if (!fs.existsSync(MAP_PATH)) {
    console.error(
      `[Rewrite] FATAL: mapping file not found:\n  ${MAP_PATH}\n` +
      `          Run migrate-community-evidence.js first.`
    );
    process.exit(1);
  }

  let map;
  try {
    map = JSON.parse(fs.readFileSync(MAP_PATH, "utf8"));
  } catch (e) {
    console.error(`[Rewrite] FATAL: mapping file is not valid JSON — ${e.message}`);
    process.exit(1);
  }

  const entries = Array.isArray(map.entries) ? map.entries : [];
  console.log(`  mapping: ${entries.length} entr(ies), generated ${map.generatedAt}`);
  console.log(`  mapping mode: ${map.mode}\n`);

  if (APPLY && map.mode !== "apply") {
    console.error(
      "[Rewrite] FATAL: --apply refused. The mapping JSON was produced by a " +
      "DRY RUN of the file-copy script, so the nested files do not exist " +
      "yet.\n          Run `migrate-community-evidence.js --apply` first, " +
      "then re-run this script."
    );
    process.exit(1);
  }

  if (entries.length === 0) {
    console.log("[Rewrite] Mapping has no entries — nothing to do.");
    process.exit(0);
  }

  // ── Group entries by docId (a docId can have several uploads; only the
  //    one referenced by completionPhotoUrl gets rewritten). Skip entries
  //    whose file was not actually copied. ────────────────────────────────
  const byDoc = new Map();
  let ignoredEntries = 0;
  for (const e of entries) {
    if (e.status !== "copied" && e.status !== "already-migrated") {
      ignoredEntries++;
      continue;
    }
    if (!byDoc.has(e.docId)) byDoc.set(e.docId, []);
    byDoc.get(e.docId).push(e);
  }
  console.log(
    `[Rewrite] ${byDoc.size} community_requests doc(s) to inspect ` +
    `(${ignoredEntries} mapping entr(ies) ignored — not copied).\n`
  );

  const db = admin.firestore();

  let rewritten = 0;
  let alreadyNew = 0;
  let noUrlField = 0;
  let docMissing = 0;
  let noMatch = 0;
  let errors = 0;
  const errorSamples = [];

  for (const [docId, docEntries] of byDoc) {
    try {
      const ref = db.collection("community_requests").doc(docId);
      const snap = await ref.get();

      if (!snap.exists) {
        docMissing++;
        console.warn(`  ⚠ doc not found: community_requests/${docId}`);
        continue;
      }

      const data = snap.data() || {};
      const stored = (data.completionPhotoUrl || "").trim();

      if (!stored) {
        noUrlField++;
        console.log(`  • no completionPhotoUrl: ${docId} (orphan upload — skip)`);
        continue;
      }

      // Find which of this doc's mapping entries the stored URL references.
      let matched = null;
      let alreadyDone = false;
      for (const e of docEntries) {
        const encOld = encodeURIComponent(e.oldPath); // community_evidence%2Fabc_123.jpg
        const encNew = encodeURIComponent(e.newPath); // community_evidence%2Fabc%2F123.jpg
        if (stored.includes(encNew)) {
          alreadyDone = true;
          break;
        }
        if (stored.includes(encOld)) {
          matched = { e, encOld, encNew };
          break;
        }
      }

      if (alreadyDone) {
        alreadyNew++;
        console.log(`  • already nested: ${docId}`);
        continue;
      }

      if (!matched) {
        noMatch++;
        console.warn(
          `  ⚠ completionPhotoUrl on ${docId} does not reference any migrated ` +
          `file — left unchanged.`
        );
        continue;
      }

      const newStored = stored.replace(matched.encOld, matched.encNew);
      if (newStored === stored) {
        // Should not happen (includes() matched) — guard anyway.
        noMatch++;
        console.warn(`  ⚠ rewrite produced no change for ${docId} — skipped.`);
        continue;
      }

      if (APPLY) {
        await ref.update({ completionPhotoUrl: newStored });
        console.log(`  ✓ rewritten: ${docId}`);
      } else {
        console.log(`  [dry run] would rewrite: ${docId}`);
        console.log(`      old: ${stored}`);
        console.log(`      new: ${newStored}`);
      }
      rewritten++;
    } catch (e) {
      errors++;
      if (errorSamples.length < 10) {
        errorSamples.push({ docId, error: String(e.message || e) });
      }
      console.error(`  ✗ FAILED: ${docId} — ${e.message || e}`);
    }
  }

  console.log("\n[Rewrite] Summary:");
  console.log(`  rewritten              : ${rewritten}`);
  console.log(`  already nested (skipped): ${alreadyNew}`);
  console.log(`  no completionPhotoUrl   : ${noUrlField}`);
  console.log(`  doc not found           : ${docMissing}`);
  console.log(`  url did not match       : ${noMatch}`);
  console.log(`  errors                  : ${errors}`);
  if (errorSamples.length) {
    errorSamples.forEach((s) => console.log(`    - ${s.docId}: ${s.error}`));
  }

  if (APPLY && errors === 0) {
    await db.collection("admin_audit_log").add({
      action: "rewrite_community_evidence_urls_local_script",
      adminUid: "local_cli",
      rewritten, alreadyNew, noUrlField, docMissing, noMatch, errors,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log("\n[Rewrite] Audit log written. Done.");
    console.log(
      "[Rewrite] Migration COMPLETE — files copied + Firestore URLs rewritten. " +
      "It is now safe to deploy storage.rules."
    );
  } else if (APPLY) {
    console.log(
      "\n[Rewrite] Completed WITH ERRORS — do NOT deploy storage.rules until " +
      "the failed docs are resolved (re-run; the script is idempotent)."
    );
  } else {
    console.log("\n[Rewrite] DRY RUN — nothing was written. Re-run with --apply to write.");
  }

  process.exit(errors === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("[Rewrite] FATAL:", e);
  process.exit(1);
});
