# Security Audit Report — AnySkill

**Audit date:** 2026-05-15
**Audit type:** Authorized internal penetration test (Red Team)
**Scope:** `firestore.rules`, `storage.rules`, `functions/index.js` (146 Cloud Functions), client-side Flutter app, PWA service workers.
**Method:** Static source-code analysis + Firebase Rules-Unit-Testing against the local emulator. No production data was touched.
**Auditor:** Claude Code (Red Team simulation), under owner authorization.

> This audit is a follow-up to the v15.x security pass documented in CLAUDE.md
> §50 (9 vulnerabilities closed, 2026-04-25). It re-verified those fixes still
> hold and audited the surface added since (Flash Auction §57, Babysitter
> Emergency §76, Delivery Express §78, Banners Studio §49/§51, Sound Studio
> §54, 8 Category-Specific Modules, AnyTasks, Vault, Categories v3).

---

## Executive Summary

| Severity | Found | Fixed | Accepted / Deferred |
|----------|-------|-------|---------------------|
| 🔴 Critical | 0 | 0 | 0 |
| 🟠 High | 2 | 2 | 0 |
| 🟡 Medium | 7 | 7 | 0 |
| 🔵 Low | 3 | 0 | 3 (documented) |
| ℹ️ Info / Operator | 3 | — | 3 |
| **Total** | **15** | **9** | **6** |

**Overall risk posture:**

| | Before audit | After audit |
|--|--------------|-------------|
| Score | 7.0 / 10 | **8.0 / 10** |
| Tier | Production-startup | Production-startup (hardened) |

No immediately exploitable money-creation or account-takeover path was found —
the v15.x §50 audit had already closed those. This audit closed a second tier
of **data-integrity, defacement, privacy, and in-app-phishing** vulnerabilities.
The remaining gap to a higher score is **operator-side** (App Check still in
Monitor mode, Maps API key domain restriction) — not code.

**What was verified SECURE (no action needed):**

- Money-mutating Cloud Functions read all amounts/recipients from server-side
  docs inside the transaction; idempotency caches are CF-only (`if false`).
- `isAdminCaller` prefers the signed JWT custom claim; falls back to the
  locked-down Firestore field. Returns `false` on error (safe default).
- `users/{uid}` update rule blocks every privileged field (`isAdmin`, `role`,
  `roles`, `balance`, `customCommission`, `verifiedAt`, …) via a `doesNotTouch`
  allow-list. Create-time blocks the same.
- `transactions`, `platform_earnings`, `support_audit_log`, `admin_audit_log`,
  `email_verification_codes`, all `*_idempotency` caches — correctly immutable
  / CF-only.
- CSP is strict; AI API keys live in Secret Manager; service worker only opens
  the app's own domain; passwords are never stored in web `localStorage`.
- `sendGlobalBroadcast` is properly admin-gated (the §50 Vuln-7 fix holds).
- Self-booking is blocked three ways (UI + service + rule).

---

## Findings

### 🟠 VULN-001 — `community_requests` open-task field free-for-all

| | |
|--|--|
| **Severity** | High (CVSS 3.1: `AV:N/AC:L/PR:L/UI:N/S:U/C:N/I:H/A:L` ≈ 7.1) |
| **Status** | ✅ Fixed |
| **File** | `firestore.rules` — `community_requests/{reqId}` update rule |

**Description.** The update rule allowed *any* authenticated user to update a
`community_requests` doc whose `status == 'open'` — with **no field-level
restriction**:

```
allow update: if isAdmin()
              || (isVerifiedAuth()
                  && (resource.data.requesterId  == request.auth.uid
                      || resource.data.volunteerId == request.auth.uid
                      || resource.data.status == 'open'));   // ← free-for-all
```

**Proof of Concept.**
```js
// Attacker is any signed-in user. req1 is anyone's open help request.
db.collection('community_requests').doc('req1').update({
  requesterId: 'attacker',                 // hijack ownership
  title:       'Phishing — click here',    // inject malicious content
  description: 'https://evil.example',
  volunteerId: 'innocent_provider',        // frame a stranger
});
```

**Business impact.** Platform-wide sabotage of the Community Hub: hijack help
requests, impersonate volunteers, inject phishing links into community-visible
text, pre-claim categories.

**Fix.** Non-participants now get a single narrow primitive — a self-claim
that sets `volunteerId`/`volunteerName` to *themselves* and flips `status` to
`'accepted'`, via an `onlyFields(['volunteerId','volunteerName','claimedAt','status'])`
allow-list. All other fields are immutable for non-participants.

**Regression test.** `firestore-rules-tests/pentest_2026_05_15.test.js`
→ `describe('VULN-001 …')` — 5 tests.

---

### 🟠 VULN-002 — Legacy `anytasks` open-task field free-for-all

| | |
|--|--|
| **Severity** | High (CVSS ≈ 7.3 — touches a money-bearing collection) |
| **Status** | ✅ Fixed |
| **File** | `firestore.rules` — `anytasks/{taskId}` update rule |

**Description.** Identical pattern to VULN-001, on the **legacy** `anytasks`
collection (no underscore — the v14.x marketplace lives at `any_tasks` with
proper rules). Any non-creator could rewrite **every** field of an open task,
including `creatorId`, `budgetNis`, and `status`.

**Proof of Concept.**
```js
db.collection('anytasks').doc('task1').update({
  creatorId: 'attacker',     // steal the task
  budgetNis: 999999,         // inflate budget
  status:    'completed',    // jump status, potentially trip a payout path
});
```

**Business impact.** Task hijacking + budget manipulation on a collection that
historically fed the escrow/jobs pipeline. The legacy collection still has a
scheduled CF (`anytaskExpireOpen`) operating on it.

**Fix.** Four tightly-scoped update branches, each with an `onlyFields(...)`
allow-list: admin / creator-lifecycle / open-claim-by-provider / assigned-
provider-work. `creatorId` and `budgetNis` are now immutable post-create.

**Regression test.** `describe('VULN-002 …')` — 5 tests.

> **Recommendation:** confirm the legacy `anytasks` collection has no live
> documents and, if so, lock the entire block to admin-only in a future PR
> (CLAUDE.md §38 already flags it as removal-candidate).

---

### 🟡 VULN-003 — `/admin/` collection broad read (revenue leakage)

| | |
|--|--|
| **Severity** | Medium |
| **Status** | ✅ Fixed |
| **File** | `firestore.rules` — `match /admin/{docId}` + recursive subtree |

**Description.** `allow read: if isVerifiedAuth()` on `/admin/` *and* its entire
recursive `{nestedDoc=**}` subtree. Any signed-in customer could read every
admin document — including `totalPlatformBalance` (cumulative platform
revenue), broadcast configuration, internal KPIs.

**Proof of Concept.**
```js
db.collection('admin').doc('broadcast_logs').get();   // internal config
// → leaks platform revenue, campaign costs, internal metrics
```

**Business impact.** Information disclosure / competitive intelligence — a
competitor signs up as a customer and reads the platform's financial position.

**Fix.** Read collapses to admin/CMS-admin only, with **one explicit carve-out**:
the booking flow legitimately needs `admin/admin/settings/settings` for fee
preview, so a dedicated `match /settings/{settingId}` keeps that single path
readable by authenticated users. (Note: a `path`-typed recursive wildcard has
no `.matches()` method — the first fix attempt failed the emulator test and
was corrected to an explicit single-segment match.)

**Regression test.** `describe('VULN-003 …')` — 3 tests (incl. the negative
control that fee-preview still works).

---

### 🟡 VULN-004 — `pendingBalance` writable by anyone / unrestricted by owner

| | |
|--|--|
| **Severity** | Medium |
| **Status** | ✅ Fixed |
| **File** | `firestore.rules` — `users/{uid}` update rule |

**Description.** Two issues, the second discovered *during* fix verification:

1. The dedicated rule allowed **any** authenticated user to *decrement* **any**
   other user's `pendingBalance` (defacement primitive).
2. **Worse:** `pendingBalance` was **not in the `doesNotTouch` blocklist** of the
   general owner-update branch — so the owner could set their *own*
   `pendingBalance` to **any value**, including negative or wildly inflated.
   (A regression test for "owner cannot go negative" surfaced this — it
   *succeeded* when it should have failed.)

**Proof of Concept.**
```js
// (1) Grief a stranger:
db.collection('users').doc('victim_provider').update({ pendingBalance: 0 });
// (2) Owner self-inflate (general branch — pendingBalance not blocked):
db.collection('users').doc(myUid).update({ pendingBalance: 9999999 });
```

**Business impact.** Defacement of any provider's visible "pending earnings",
corrupted admin dashboards / Vault analytics. Monetary payout math uses job-doc
amounts (not this field), so no direct money loss — but trust + reporting
integrity are real.

**Fix.**
- Added `pendingBalance` to the general owner-update `doesNotTouch` blocklist.
- The *only* remaining client write is a dedicated **owner-only decrement**
  branch that also enforces `>= 0`.
- Corrected the misleading "RESOLVED" comment at the bottom of `firestore.rules`
  (it claimed pendingBalance writes were already fully blocked — they were not).

**Regression test.** `describe('VULN-004 …')` — 4 tests.

---

### 🟡 VULN-005 — `provider_live_location` real-time stalking

| | |
|--|--|
| **Severity** | Medium |
| **Status** | ✅ Fixed |
| **Files** | `firestore.rules`; `lib/services/live_location_service.dart`; `lib/widgets/bookings/expert_job_card.dart` |

**Description.** `allow read: if isAdmin() || isVerifiedAuth()` — *any* signed-in
user could read *any* provider's live GPS coordinates by document ID
(`provider_live_location/{providerUid}`), enabling real-time tracking of any
provider during an active job.

**Proof of Concept.**
```js
db.collection('provider_live_location').doc(targetProviderUid).snapshots();
// → streams the provider's live lat/lng as they drive
```

**Business impact.** Physical-safety / stalking risk for providers.

**Fix (rules + client code).**
- Rule now allows read only by the provider themselves, the **customer of the
  current job**, or admin.
- `LiveLocationService.startBroadcasting` gained a **required `customerId`**
  argument and stamps `customerId` onto every position write, so the rule has
  a value to authorize against. Legacy docs without `customerId` degrade
  safely (provider + admin only — no stalking, customer map re-binds on the
  next broadcast).
- The one call site (`expert_job_card.dart`) was updated to pass
  `job['customerId']`.

**Regression test.** `describe('VULN-005 …')` — 4 tests.

---

### 🟡 VULN-006 — `notifications` create-by-anyone (in-app phishing)

| | |
|--|--|
| **Severity** | Medium |
| **Status** | ✅ Fixed |
| **File** | `firestore.rules` — `notifications/{notifId}` create rule |

**Description.** The create rule allowed any authenticated user to write a
notification document targeting **any** `userId`, as long as it had ≤10 fields
and a ≤1000-char body — an in-app phishing primitive.

**Proof of Concept.**
```js
db.collection('notifications').add({
  userId: 'victim',
  title:  'Account suspended',
  body:   'Tap here to verify your account: https://evil.example',
  type:   'system_warning',
});
// → renders inside the victim's notification bell as a "system" alert
```

**Business impact.** Mass in-app phishing, system-message impersonation,
notification spam.

**Fix.** Cross-user notification creates now require **both**: (a) a `type` on
an explicit allow-list of genuine client-side flows (`help_request`,
`volunteer_*`, `community_*`, `broadcast_claimed`, `request_declined`,
`csat_survey_response`, `demo_contact`, `review_published`); **and** (b) a
`senderId` field stamped with the caller's own uid (audit trail + anti-spoof).
Self-notifications (recipient == caller) still pass freely. All other types
must flow through Cloud Functions (Admin SDK bypasses rules).

**Regression test.** `describe('VULN-006 …')` — 5 tests.

> **Follow-up:** audit each client call site that creates a notification and
> ensure it stamps `senderId` + uses an allow-listed `type`. Sites that can't
> should migrate to a Cloud Function.

---

### 🟡 VULN-007 — `motorcycle_bike_types` Storage writable by any user

| | |
|--|--|
| **Severity** | Medium |
| **Status** | ✅ Fixed |
| **File** | `storage.rules` — `motorcycle_bike_types/{file=**}` |

**Description.** `allow write: if isSignedIn() && isImageContentType() && underSize(5)`.
A long in-file comment justified this as "low-blast-radius" — incorrectly. Any
signed-in user could overwrite catalog images served (and CDN-cached) to every
provider and customer.

**Business impact.** CDN-hosted XSS (SVG with embedded script), brand
defacement, hosting of offensive/illegal content on the platform CDN (legal
liability).

**Fix.** `allow write: if isAdmin() && isImageContentType() && underSize(5)` —
uses the same `firestore.get()`-based admin gate as every other admin-write
Storage path.

**Regression test.** Covered by `storage.test.js` pattern; verified the full
storage suite still passes (14/14 suites).

---

### 🟡 VULN-008 — `business_docs` Storage missing content-type guard

| | |
|--|--|
| **Severity** | Medium |
| **Status** | ✅ Fixed |
| **File** | `storage.rules` — `business_docs/{userId}/{allPaths=**}` |

**Description.** Unlike `id_docs/` (which enforces `isImageContentType()`),
`business_docs/` had `allow write: if isOwner(userId) && underSize(10)` — **no
content-type guard**. A provider could upload `.exe` / `.html` / `.svg`
(embedded JS). An admin opening the file from the verification console would
execute the payload.

**Fix.** Write now requires `image/*` **or** `application/pdf` (legitimate
business licenses are commonly PDF scans).

---

### 🟡 VULN-009 — `community_evidence` Storage no participant gate

| | |
|--|--|
| **Severity** | Medium |
| **Status** | ✅ Fixed |
| **Files** | `storage.rules`; `lib/screens/community_hub_screen.dart`; `lib/screens/community/complete_volunteering_screen.dart` |

**Description.** Flat path `community_evidence/{docId}_{ts}.{ext}` with
`allow read, write: if isSignedIn()` — any signed-in user could read or
overwrite **any** volunteer-task evidence photo by brute-forcing the docId.

**Business impact.** Privacy leak of volunteer photos (locations, faces,
timestamps); proof tampering.

**Fix.** Path restructured to nested `community_evidence/{docId}/{file}` so the
rule can do a `firestore.get()` against the parent `community_requests/{docId}`
doc and gate read by participant (requester / volunteer / admin) and write by
the assigned volunteer only. Both Dart upload sites were updated to the nested
path.

> **Operator note:** files already uploaded under the *old* flat path are no
> longer served (they fall under storage default-deny). If legacy evidence must
> remain visible, run a one-shot admin migration to move them into the nested
> structure before deploying `storage.rules`.

---

### 🔵 VULN-010 — `booking_requirements` / `job_photos` Storage broad read

| | |
|--|--|
| **Severity** | Low |
| **Status** | ⚠️ Documented (not fixed — needs path refactor) |
| **File** | `storage.rules` lines ~111, ~121 |

`booking_requirements/{userId}/**` and `job_photos/{userId}/**` both have
`allow read: if isSignedIn()`. Any auth user who knows/guesses a customer UID
can read that customer's pre-booking photos (home interiors, "visual
diagnosis" photos of infestations/leaks, package contents).

**Why deferred:** the paths are keyed by `customerUid` with no `jobId`
segment, so a participant gate requires a path refactor (→
`booking_requirements/{jobId}/{file}`) plus migration of existing files —
larger blast radius than appropriate for a Low finding. **Recommended fix:**
adopt the same nested-path + `firestore.get()` pattern used for the VULN-009
fix, in a dedicated PR.

---

### 🔵 VULN-011 — `lookupLegacyUidByPhone` phone enumeration

| | |
|--|--|
| **Severity** | Low / Informational |
| **Status** | ⚠️ Accepted risk (documented) |
| **File** | `functions/index.js:9797` |

The CF is intentionally unauthenticated (legacy phone→account self-heal before
login — CLAUDE.md §23). It returns whether a phone number maps to a registered
account. It is **already** mitigated: 10-requests/min/IP rate limit + a
honeypot that returns fake `{found:false}` after the limit (so the attacker
can't tell they were blocked).

Residual risk: a distributed attacker (proxy pool) could still enumerate which
phone numbers are registered, then chain phone → uid → profile (the `users`
doc is readable by any auth user). **Accepted** per the §23 design trade-off;
recommendation is to keep an eye on the `activity_log` rate-limit events.

---

### 🔵 VULN-012 — Dispatch-auction parent docs loosely updatable by notified providers

| | |
|--|--|
| **Severity** | Low |
| **Status** | ⚠️ Documented (already flagged as v2 follow-up in-rule) |
| **File** | `firestore.rules` — `flash_auctions` / `babysitter_emergencies` / `delivery_express` update rules |

The parent-doc `update` rule for all three emergency-dispatch collections
allows any *notified provider* to update the parent doc (not just create an
offer in the `offers` subcollection). The rule comments already acknowledge
this is "loose … field-level tightening ships in v2." No money path is exposed
(payouts go through the `bookFrom*Offer` CFs, which re-read everything inside a
transaction), so impact is limited to cosmetic auction-doc tampering.
**Recommendation:** add an `onlyFields(...)` allow-list in the planned v2 pass.

---

### ℹ️ Operator / Informational items

| ID | Item | Action owner |
|----|------|--------------|
| OP-1 | **App Check is in Monitor mode**, not Enforce. Until flipped to Enforce in the Firebase Console, a determined attacker with the public `apiKey` can hit Firebase APIs from a non-app client. | Operator (Firebase Console) |
| OP-2 | **Google Maps JS API key** (`web/Maps.js`) — verify it is domain-restricted in Cloud Console to `*.web.app` / `*.firebaseapp.com`. Firebase keys are public-by-design and rules-protected; the Maps key needs an HTTP-referrer restriction to prevent quota theft. | Operator (Cloud Console) |
| OP-3 | **`requestWithdrawal` has no max-amount cap and no idempotency key.** The atomic transaction prevents true double-spend, but a balance-inflation bug elsewhere could be drained in one request, and a double-tap creates two pending withdrawals. Recommend a per-request cap + a `clientReqId` idempotency check (mirror the §60 pattern). | Dev (future PR) |

---

## Fixes Applied — File Manifest

| File | Change |
|------|--------|
| `firestore.rules` | VULN-001, 002, 003, 004, 006 fixes + corrected stale comment |
| `storage.rules` | VULN-007, 008, 009 fixes |
| `lib/services/live_location_service.dart` | VULN-005 — `customerId` field added to broadcast doc; `startBroadcasting` requires `customerId` |
| `lib/widgets/bookings/expert_job_card.dart` | VULN-005 — call site passes `customerId` |
| `lib/screens/community_hub_screen.dart` | VULN-009 — nested Storage path |
| `lib/screens/community/complete_volunteering_screen.dart` | VULN-009 — nested Storage path + doc comment |
| `firestore-rules-tests/pentest_2026_05_15.test.js` | **NEW** — 26 regression tests |
| `firestore-rules-tests/package.json` | `--runInBand` added (deterministic CI — see below) |

---

## Verification

All fixes were verified against the Firebase Emulator with
`@firebase/rules-unit-testing`:

```
firebase emulators:exec --only firestore,storage --project=anyskill-rules-tests \
  "cd firestore-rules-tests && npm test"
```

| Suite | Result |
|-------|--------|
| `pentest_2026_05_15.test.js` (new) | **26 / 26 passed** |
| Full regression suite (14 files) | **163 passed, 20 skipped, 0 failed** |
| `flutter analyze` on 4 modified Dart files | **0 issues** |

**CI hardening:** the rules-test suite was running non-deterministically — all
14 test files share one emulator + project ID, and each file's `clearFirestore()`
in `beforeEach` wipes data mid-test for any file running concurrently. It only
"passed" in CI because GitHub's 2-vCPU runners make Jest default to a single
worker. Running locally on a multi-core machine produced 58 spurious failures.
Fixed by adding `--runInBand` to the `npm test` script — the suite is now
deterministic regardless of core count.

---

## Deployment Checklist

Apply in this order. **`storage.rules` requires a migration decision first**
(VULN-009 — see note below).

```bash
# 1. Firestore rules (VULN-001..004, 006)
firebase deploy --only firestore:rules

# 2. Storage rules (VULN-007..009)
#    ⚠️ BEFORE deploying: existing files under the OLD flat
#    `community_evidence/{docId}_{ts}.ext` path stop being served.
#    If legacy volunteer evidence must stay visible, first run a one-shot
#    admin migration to move them to `community_evidence/{docId}/{file}`.
firebase deploy --only storage

# 3. Web client (VULN-005 LiveLocationService + VULN-009 upload paths)
flutter build web --release && firebase deploy --only hosting
```

**Operator follow-ups (not code):**
- [ ] Flip App Check Firestore + Storage to **Enforce** after a 24-48h clean
      Monitor window (OP-1).
- [ ] Verify the Google Maps JS API key is HTTP-referrer-restricted (OP-2).

---

## Long-Term Recommendations

1. **Add `--runInBand` awareness to the rules-test docs** — done in `package.json`;
   also worth a line in `firestore-rules-tests/README.md`.
2. **Field-level allow-lists everywhere** — the recurring root cause of
   VULN-001/002 (and VULN-012) is `allow update: if <ownership>` without an
   `onlyFields()` / `diff().affectedKeys().hasOnly()` clause. Adopt a review
   checklist: *every* `allow update` on a non-trivial collection must either
   be admin-only or carry a field allow-list.
2. **Migrate `pendingBalance` decrements to a Cloud Function** so the last
   client-write branch can be deleted (VULN-004 follow-up).
3. **`requestWithdrawal` hardening** — per-request cap + idempotency (OP-3).
4. **Storage path convention** — any user-uploaded media tied to a parent
   entity should use a nested `{collection}/{parentId}/{file}` path so the
   rule can `firestore.get()` the parent for a participant gate. Retro-fit
   `booking_requirements/` and `job_photos/` (VULN-010).
5. **CI security checks** — add `npm audit` (functions + rules-tests) and a
   dependency scanner (e.g. Dependabot / Snyk) to the GitHub Actions pipeline.
6. **Re-run this pen-test every 3-6 months** and after any new collection /
   Cloud Function is added — especially new CSMs and dispatch modules, which
   were the source of several findings here.

---

## Appendix — Methodology

- **Stage 1 (Reconnaissance):** inventoried all 146 Cloud Functions (trigger
  type, auth pattern, money-touching flag), all ~80 Firestore match blocks,
  all 28 Storage match blocks, and all client-side sensitive-storage call
  sites.
- **Stages 2-6:** static analysis of `firestore.rules`, `storage.rules`,
  critical money Cloud Functions (`processPaymentRelease`, `requestWithdrawal`,
  `bookFromFlashAuctionOffer`, `adminReleaseEscrow`, …), the `isAdminCaller`
  helper, client-side storage, CSP, service workers, and the password-reset /
  account-self-heal flows.
- **Stage 7:** wrote fixes for all 9 confirmed High/Medium vulnerabilities.
- **Stage 8:** authored 26 emulator-backed regression tests; verified the full
  163-test suite passes with no regressions.
- **Stage 9:** this report.

No destructive operations were performed. No production data was read or
written. All testing ran against the local Firebase Emulator.
