/**
 * One-off local script: migrate `community_evidence` Storage files from the
 * legacy FLAT path to the new NESTED path required by the VULN-009 fix.
 *
 * Security audit 2026-05-15, VULN-009 (see SECURITY_AUDIT_REPORT.md).
 *
 *   OLD (flat)   : community_evidence/{docId}_{timestamp}.{ext}
 *   NEW (nested) : community_evidence/{docId}/{timestamp}.{ext}
 *
 * The new storage.rules gate community_evidence reads/writes by doing a
 * firestore.get() against community_requests/{docId}. That only works when
 * {docId} is its OWN path segment — hence the nested layout. Files left on
 * the old flat path fall under storage default-deny once the new rules
 * deploy, so legacy evidence must be copied across FIRST.
 *
 * What this script does:
 *   • Lists every object under `community_evidence/`.
 *   • Skips files already in the nested layout (idempotent — safe to re-run).
 *   • For each legacy flat file, parses {docId} (everything before the LAST
 *     underscore) and {timestamp}.{ext} (after it). Firestore auto-IDs and
 *     millisecond timestamps contain no underscores, so the last underscore
 *     is an unambiguous separator.
 *   • COPIES it to the nested path (object metadata, incl. the Firebase
 *     download token + content-type, is preserved by GCS copy).
 *   • NEVER deletes originals unless you explicitly pass --delete-originals.
 *   • Writes a mapping file (community-evidence-migration-map.json) recording
 *     every old→new path plus old/new download URLs.
 *
 * SAFE BY DEFAULT: runs as a DRY RUN unless you pass --apply. A dry run
 * lists exactly what would happen and writes nothing.
 *
 * Run (from the functions/ directory):
 *   node scripts/migrate-community-evidence.js              # dry run (default)
 *   node scripts/migrate-community-evidence.js --apply      # actually copy
 *   node scripts/migrate-community-evidence.js --apply --delete-originals
 *
 * Optional:
 *   --bucket <name>   override the storage bucket
 *                     (default: anyskill-6fdf3.firebasestorage.app)
 *
 * Requires: either functions/service-account.json (gitignored) OR
 * Application Default Credentials (`firebase login`). Same credential
 * resolution as backfill-admin-claims.js.
 */

const admin = require("firebase-admin");
const path = require("path");
const fs = require("fs");

// ── Flags ────────────────────────────────────────────────────────────────
const APPLY = process.argv.includes("--apply");
const DELETE_ORIGINALS = process.argv.includes("--delete-originals");
const bucketFlagIdx = process.argv.indexOf("--bucket");
const BUCKET_NAME =
  (bucketFlagIdx !== -1 && process.argv[bucketFlagIdx + 1]) ||
  process.env.FIREBASE_STORAGE_BUCKET ||
  "anyskill-6fdf3.firebasestorage.app";

const PREFIX = "community_evidence/";
const PROJECT_ID = "anyskill-6fdf3";

// Legacy tail must look like `{digits}.{ext}` — a millisecond timestamp and
// a file extension, neither of which ever contains an underscore.
const TAIL_RE = /^\d+\.[A-Za-z0-9]+$/;

// ── Credentials (ordered): explicit SA file → Application Default ─────────
const SA_PATH = path.join(__dirname, "..", "service-account.json");
if (fs.existsSync(SA_PATH)) {
  console.log("[Migrate] Using explicit service-account.json credential");
  admin.initializeApp({
    credential: admin.credential.cert(require(SA_PATH)),
    storageBucket: BUCKET_NAME,
  });
} else {
  console.log("[Migrate] Using Application Default Credentials");
  admin.initializeApp({
    projectId: PROJECT_ID,
    storageBucket: BUCKET_NAME,
  });
}

/** Build the Firebase-style download URL for a stored object. */
function downloadUrl(objectPath, token) {
  if (!token) return null;
  return (
    `https://firebasestorage.googleapis.com/v0/b/${BUCKET_NAME}/o/` +
    `${encodeURIComponent(objectPath)}?alt=media&token=${token}`
  );
}

/** First Firebase download token from an object's custom metadata. */
function tokenOf(file) {
  const raw =
    file.metadata &&
    file.metadata.metadata &&
    file.metadata.metadata.firebaseStorageDownloadTokens;
  return raw ? String(raw).split(",")[0] : null;
}

async function main() {
  console.log("\n=== community_evidence path migration (VULN-009) ===");
  console.log(`  bucket          : ${BUCKET_NAME}`);
  console.log(`  mode            : ${APPLY ? "APPLY (writing)" : "DRY RUN (no writes)"}`);
  console.log(`  delete originals: ${DELETE_ORIGINALS ? "YES" : "no (copy only)"}`);
  console.log("");

  const bucket = admin.storage().bucket();

  // Fail fast with a clear message if the bucket name is wrong.
  const [bucketExists] = await bucket.exists();
  if (!bucketExists) {
    console.error(
      `[Migrate] FATAL: bucket "${BUCKET_NAME}" not found or not accessible.\n` +
      `          Pass the correct name with --bucket <name>. Common values:\n` +
      `            anyskill-6fdf3.firebasestorage.app   (current default)\n` +
      `            anyskill-6fdf3.appspot.com           (legacy default)`
    );
    process.exit(1);
  }

  console.log(`[Migrate] Listing objects under "${PREFIX}" …`);
  const [files] = await bucket.getFiles({ prefix: PREFIX });
  console.log(`[Migrate] ${files.length} object(s) found under the prefix.\n`);

  let alreadyNested = 0;
  let migrated = 0;
  let skippedExists = 0;
  let skippedUnparseable = 0;
  let deleted = 0;
  let errors = 0;
  const errorSamples = [];
  const mapping = [];

  for (const file of files) {
    const fullName = file.name; // e.g. community_evidence/abc123_1699999999999.jpg
    const remainder = fullName.slice(PREFIX.length); // abc123_1699999999999.jpg

    // Folder placeholder object (zero-byte "community_evidence/") — ignore.
    if (remainder === "" || remainder.endsWith("/")) continue;

    // Already nested (contains a "/" after the prefix) — nothing to do.
    if (remainder.includes("/")) {
      alreadyNested++;
      continue;
    }

    // Parse legacy flat name: {docId}_{timestamp}.{ext}.
    const lastUnderscore = remainder.lastIndexOf("_");
    const docId = lastUnderscore > 0 ? remainder.slice(0, lastUnderscore) : "";
    const tail = lastUnderscore > 0 ? remainder.slice(lastUnderscore + 1) : "";

    if (!docId || !TAIL_RE.test(tail)) {
      skippedUnparseable++;
      console.warn(
        `  ⚠ SKIP (does not match {docId}_{ts}.{ext}): ${fullName}`
      );
      continue;
    }

    const newPath = `${PREFIX}${docId}/${tail}`;
    const destFile = bucket.file(newPath);

    // Idempotency: if the nested copy already exists, leave it alone.
    const [destExists] = await destFile.exists();
    const oldToken = tokenOf(file);
    const contentType =
      (file.metadata && file.metadata.contentType) || "unknown";

    const record = {
      docId,
      contentType,
      oldPath: fullName,
      newPath,
      oldUrl: downloadUrl(fullName, oldToken),
      newUrl: downloadUrl(newPath, oldToken), // GCS copy preserves the token
      status: destExists ? "already-migrated" : APPLY ? "copied" : "would-copy",
    };

    if (destExists) {
      skippedExists++;
      console.log(`  • already migrated: ${docId}/${tail}`);
      mapping.push(record);
      continue;
    }

    if (!APPLY) {
      console.log(`  [dry run] would copy: ${fullName}  →  ${newPath}`);
      mapping.push(record);
      continue;
    }

    try {
      await file.copy(destFile);
      migrated++;
      console.log(`  ✓ copied: ${fullName}  →  ${newPath}`);

      if (DELETE_ORIGINALS) {
        await file.delete();
        deleted++;
        console.log(`    ↳ deleted original: ${fullName}`);
      }
      mapping.push(record);
    } catch (e) {
      errors++;
      record.status = "error";
      record.error = String(e.message || e);
      if (errorSamples.length < 10) {
        errorSamples.push({ path: fullName, error: record.error });
      }
      console.error(`  ✗ FAILED: ${fullName} — ${record.error}`);
      mapping.push(record);
    }
  }

  // Write the mapping artifact next to this script.
  const mapPath = path.join(__dirname, "community-evidence-migration-map.json");
  fs.writeFileSync(
    mapPath,
    JSON.stringify(
      {
        generatedAt: new Date().toISOString(),
        bucket: BUCKET_NAME,
        mode: APPLY ? "apply" : "dry-run",
        deleteOriginals: DELETE_ORIGINALS,
        entries: mapping,
      },
      null,
      2
    )
  );

  console.log("\n[Migrate] Summary:");
  console.log(`  legacy flat files copied  : ${migrated}`);
  console.log(`  already nested (untouched): ${alreadyNested}`);
  console.log(`  already migrated (skipped): ${skippedExists}`);
  console.log(`  unparseable (skipped)     : ${skippedUnparseable}`);
  console.log(`  originals deleted         : ${deleted}`);
  console.log(`  errors                    : ${errors}`);
  if (errorSamples.length) {
    errorSamples.forEach((s) => console.log(`    - ${s.path}: ${s.error}`));
  }
  console.log(`\n[Migrate] Mapping written to:\n  ${mapPath}`);

  if (!APPLY) {
    console.log(
      "\n[Migrate] DRY RUN — nothing was written. " +
      "Re-run with --apply to perform the copy."
    );
  } else if (errors === 0) {
    console.log("\n[Migrate] Done. Verify the nested files, THEN deploy storage.rules.");
  } else {
    console.log(
      "\n[Migrate] Completed WITH ERRORS — do NOT deploy storage.rules until " +
      "the failed files are resolved (re-run; the script is idempotent)."
    );
  }

  process.exit(errors === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("[Migrate] FATAL:", e);
  process.exit(1);
});
