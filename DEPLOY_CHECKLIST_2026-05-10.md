# Deploy Checklist — 2026-05-10 Session (§58 → §75 + audit fixes)

> **Authoritative reference for the operator** (you) to roll out the
> 18 sections shipped today, plus the post-audit fixes. Each step
> is checkable. **Do them in order** — earlier steps unblock later ones.

---

## 0. Pre-flight (5 min) — verify current state is shippable

- [ ] `git status` — confirm only the expected files changed (nothing accidental)
- [ ] `flutter analyze` → must report **0 issues**
- [ ] `flutter test test/unit/` → must pass (~534 tests)
- [ ] `flutter test test/widget/` → must pass (~149 tests)
- [ ] `node -c functions/index.js` → must print nothing (= clean syntax)
- [ ] `cd functions && npm test` → CF unit tests pass
- [ ] (Optional but recommended) Run the rules tests:
      ```bash
      cd firestore-rules-tests && npm ci && npm test
      ```
      Requires the Firestore Emulator (Java + firebase-tools).

If any of these fail, **STOP** and fix before continuing.

---

## 1. Firestore rules (2 min)

Adds 6 new rule blocks (§58 system_alerts, §60 ×3 idempotency caches,
§70 dispute_resolution_idempotency, plus pre-existing).

```bash
firebase deploy --only firestore:rules
```

- [ ] Deploy succeeded (no rule-syntax errors)
- [ ] Verify in Firebase Console → Firestore → Rules tab that the new
      `match /system_alerts/...`, `match /payment_release_idempotency/...`,
      `match /cancellation_idempotency/...`,
      `match /vip_purchase_idempotency/...`,
      `match /dispute_resolution_idempotency/...` blocks are live

---

## 2. Cloud Functions (5 min)

Deploy 6 new/modified CFs.

```bash
firebase deploy --only \
  functions:exportUserData,\
  functions:checkBackupHealth,\
  functions:processPaymentRelease,\
  functions:processCancellation,\
  functions:purchaseVipWithCredits,\
  functions:resolveDisputeAdmin
```

- [ ] All 6 deploy successfully (Firebase CLI prints "Deploy complete!")
- [ ] Cloud Scheduler job auto-created for `checkBackupHealth`
      (verify: GCP Console → Cloud Scheduler → search "checkBackupHealth")
      Schedule should be `0 * * * *` IST.

---

## 3. App Check Enforce mode (5 min) — **LAUNCH BLOCKER #1**

Currently in **Monitor** mode. Has been Monitor since v15.x audit (§50).
Without this, anyone with the public `apiKey` from `firebase_options.dart`
can hit your APIs from a curl client.

- [ ] Firebase Console → App Check → **Apps** tab → confirm web app is
      registered with reCAPTCHA Enterprise (or v3).
- [ ] Firebase Console → App Check → **APIs** tab:
  - [ ] Cloud Firestore → flip to **Enforce**
  - [ ] Cloud Storage → flip to **Enforce**
  - [ ] Cloud Functions → flip to **Enforce**
- [ ] **WAIT 24-48 hours of clean Monitor logs first** if you haven't
      reviewed Monitor metrics. The Monitor dashboard shows token
      verification %; if <99% in the last week, find the gap before
      flipping. Bots/old client builds won't have valid tokens.

---

## 4. Backup bucket exists (3 min) — **LAUNCH BLOCKER #2**

The `scheduledFirestoreBackup` CF (§4 of CLAUDE.md, deployed in earlier
session) writes to `gs://anyskill-6fdf3-backups`. Check if the bucket
actually exists:

```bash
gsutil ls gs://anyskill-6fdf3-backups/ 2>&1
```

If output starts with `BucketNotFoundException`:

```bash
gsutil mb -l me-west1 gs://anyskill-6fdf3-backups

gcloud projects add-iam-policy-binding anyskill-6fdf3 \
  --member="serviceAccount:anyskill-6fdf3@appspot.gserviceaccount.com" \
  --role="roles/datastore.importExportAdmin"

gsutil iam ch serviceAccount:anyskill-6fdf3@appspot.gserviceaccount.com:objectAdmin \
  gs://anyskill-6fdf3-backups
```

- [ ] Bucket exists (`gsutil ls` does NOT 404)
- [ ] IAM grants visible (`gcloud projects get-iam-policy anyskill-6fdf3 | grep -A1 datastore.import`)
- [ ] Force-trigger one backup from Firebase Console → Functions →
      `scheduledFirestoreBackup` → "Force run" — verify it succeeds
- [ ] Within 1 hour, `checkBackupHealth` runs and DOES NOT write
      `system_alerts/backup_stale`. Spot-check Firestore Console.

---

## 5. TTL policies — **LAUNCH BLOCKER #3** (10 min)

Every TTL-enabled collection writes an `expireAt: Timestamp` field but
the policy MUST be configured manually in GCP Console for Firestore
to actually delete expired docs. Per §19 / §60 / §70 / §58.

- [ ] https://console.cloud.google.com/firestore/databases/-default-/ttl
- [ ] Click **"Create Policy"** for each, field: `expireAt`:
  - [ ] `error_logs` (§19)
  - [ ] `activity_log` (§19)
  - [ ] `payment_release_idempotency` (§60)
  - [ ] `cancellation_idempotency` (§60)
  - [ ] `vip_purchase_idempotency` (§60)
  - [ ] `dispute_resolution_idempotency` (§70)
  - [ ] `admin_credit_idempotency` (legacy §4.6)

Without these, the collections grow unbounded. TTL deletes are FREE
(no quota cost) — only the policy creation is manual.

---

## 6. Web client (5 min)

```bash
flutter build web --release
firebase deploy --only hosting
```

- [ ] Build completes without errors
- [ ] Firebase Hosting URL serves the new bundle (open in incognito)
- [ ] Smoke test: open privacy policy from Profile → loads new screen
      with all 13 sections
- [ ] Smoke test: tap "ייצא נתונים אישיים" → button works → JSON
      preview shown
- [ ] Smoke test: tap a Pay & Secure button → renders new PrimaryCTA
      with indigo gradient + lock icon

---

## 7. Operator monitoring for 48h post-deploy

- [ ] Watch `system_alerts` collection in Firebase Console for
      backup_stale alerts (should auto-clear within 26h of first
      successful daily backup)
- [ ] Watch `admin_audit_log` for `data_export` rows (none expected
      until a user actually triggers an export)
- [ ] Watch CF logs for `[exportUserData]`, `[checkBackupHealth]`,
      idempotency cache hit rates
- [ ] Sentry → look for any `data_export_screen.dart` exceptions in
      the first week post-launch (real user exercise)

---

## 8. Post-launch — first 30 days follow-ups (lower priority)

- [ ] Add daily metric aggregation for backup health to a Vault tab
      KPI card (currently the canary just writes alerts)
- [ ] FCM-to-admin gateway when a critical system_alert fires for the
      first time (see §73 deferred)
- [ ] Audit Sentry releases for the new client bundle — confirm tags
      include `compliance-pack` and `cache-layer` for the new sections

---

## What this checklist does NOT cover

| Item | Status | Why |
|------|--------|-----|
| Israeli payment provider integration | Multi-day project | Phase 2 — separate scope |
| Top-3 customer screen widget tests | Multi-day | Each needs N more singleton-replacement hooks (§71-style work) |
| AnyTasks money path idempotency | Phase 2 | Already has `autoReleased` flag — model-level guard suffices |
| Privacy Policy translations to EN/AR/ES | Optional | Hebrew is the production primary |
| Legal review of Privacy Policy | Recommended | Have a lawyer review before public launch in EU |

---

## Rollback plan (if something breaks)

For each step above:

| Step | Rollback |
|------|----------|
| Firestore rules | `git revert` the rules commit + redeploy `firebase deploy --only firestore:rules` |
| Cloud Functions | `git revert` the CF commits + redeploy targeted CFs |
| App Check Enforce | Firebase Console → flip back to Monitor |
| Backup bucket | Cannot un-create; safe to leave |
| TTL policies | Console → delete the policy |
| Web client | `firebase hosting:rollback` |

---

**Estimated total time: 30-45 minutes** (excluding the 24-48h App Check
Monitor observation window).

After all checkboxes are ✅, you're at **launch-ready 9.0/10** for a
soft public launch in Israel. Add 24-48h Sentry monitoring on real
users before scaling marketing.

---

*Generated 2026-05-10 by Claude Code. Source of truth: CLAUDE.md §58–§75
+ post-audit fixes session.*
