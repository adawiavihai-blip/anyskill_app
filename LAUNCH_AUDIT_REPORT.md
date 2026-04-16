# AnySkill Launch Audit Report

**Generated:** 2026-04-17 | **App version:** 11.9.0 | **Phase:** 1 (Discovery — read-only)

---

## Summary

| Metric | Value |
|--------|-------|
| Cloud Functions audited | 91 exported |
| Firestore rule blocks | 70 (zero wildcards) |
| Composite indexes | 67 |
| i18n keys × locales | 1,504 × 4 (100% sync) |
| Critical blockers (🚨) | **3** |
| High priority | 8 |
| Medium priority | 7 |
| Founder decisions required | 8 (see `LAUNCH_AUDIT_QUESTIONS.md`) |
| Auto-fixes applied | 0 (Phase 2 not yet started) |

---

## 🚨 Critical Issues (Block Launch)

### C1 — No Israeli payment provider integrated
**Status:** ❌ MISSING | **Impact:** Cannot accept real money from customers at launch.
- Stripe removed in v11.9.x. Current flow = internal-credit ledger only. `grantAdminCredit` CF is the only way money enters the system.
- Requires founder decision on provider (Tranzila / PayPlus / Cardcom / Meshulam). See Q1.
- **Files:** `functions/index.js:20-62` (removed exports listed), `lib/services/escrow_service.dart`, CLAUDE.md §4.

### C2 — `lookupLegacyUidByPhone` has no rate limit (enumeration attack)
**Status:** 🚨 EXPOSED | **Impact:** Attacker can enumerate every phone → uid mapping on the platform.
- CF is open (no auth required by design, used during OTP flow for legacy user migration).
- **File:** `functions/index.js:9159`
- **Fix:** Add caller-IP rate limit (e.g., 10/min) + log suspicious sweeps.

### C3 — `pendingBalance` cross-user write (documented but unfixed)
**Status:** ⚠️ ACCEPTED RISK | **Impact:** ANY verified user can increment ANY user's `pendingBalance` via client SDK.
- Mitigation: real payouts read from `jobs` docs, not this field. Noted as "accepted risk" in Firestore rules but abusable for UX confusion/fake balance display.
- **Files:** `firestore.rules:177-179`, `firestore.rules:1369-1382` (doc of risk), CLAUDE.md §11.
- **Fix:** Move `pendingBalance` mutation server-only via CF.

---

## High Priority (Fix Before Launch)

### H1 — Missing `.timeout()` on auth Cloud Function calls
User can hang indefinitely if the CF service degrades. Affected calls:
- `sendEmailVerificationCode` — `main.dart:1777`
- `verifyEmailCode` — `main.dart:1799`
- `lookupLegacyUidByPhone` — `otp_screen.dart:122`
- `deleteUserAccount` — `account_deletion_service.dart:164`
- `deleteUser` — `admin_users_tab.dart:488`

**Fix:** Wrap each with `.timeout(const Duration(seconds: 30))`.

### H2 — No max booking amount cap in `payQuote`
Client balance check is the only guard. Should match admin grant cap (₪5,000 per transaction).
- **File:** `lib/services/escrow_service.dart:93-96`
- **Fix:** Reject amounts > ₪5,000 (or configurable via admin settings).

### H3 — No idempotency on `payQuote` / `processPaymentRelease`
Double-tap on "Pay & Secure" or "Release Payment" could attempt double-debit.
- `payQuote` relies on `quote.status == 'paid'` guard (okay for quote flow but risky if invoked via new paths).
- `processPaymentRelease` relies on job status machine being in `expert_completed` exactly once.
- **Fix:** Add `clientReqId` parameter + 1-hour cache (same pattern as `grantAdminCredit` uses).

### H4 — No FCM push on critical `vault_alerts`
Admin must manually refresh dashboard to see risk/warning alerts. Hourly CF writes to `vault_alerts` but never notifies.
- **File:** `functions/vault_functions.js:179-265`
- **Fix:** In `generateVaultAlerts`, add FCM send to all `isAdmin: true` users when severity == "risk" or "warning".

### H5 — `vault_alerts` collection missing Firestore rule
Currently relies on default deny (works via Admin SDK) but admin Dart client reads this collection in the UI — may silently fail.
- **File:** `firestore.rules` (no `match /vault_alerts/{id}` block found)
- **Fix:** Add `match /vault_alerts/{id} { allow read: if isAdmin(); allow update: if isAdmin(); allow create, delete: if false; }`.

### H6 — No velocity check on job creation/broadcast
Single user could spam unlimited `job_requests` / `job_broadcasts`.
- **Fix:** Add 10-jobs-per-hour cap in `createJobRequest` / broadcast CFs.

### H7 — 11 `DateFormat(...)` calls missing `'he'` locale
Falls back to system locale, may display English month names in Hebrew UI.
- **Files:** `admin_agent_management_tab.dart:367`, `admin_ai_ceo_tab.dart:371`, + 9 more in `admin_*` / `bookings/`.
- **Fix:** Add `'he'` as second arg. Simple find-replace.

### H8 — 5 `.get()` calls in repositories without error handling
Callers must wrap or crashes propagate as unhandled exceptions.
- `lib/repositories/search_repository.dart:64, 114, 161` (searchByCategory/Name/Nearby)
- `lib/repositories/provider_repository.dart:28, 49, 62, 72`
- **Fix:** Wrap each in try/catch returning empty list + debugPrint.

---

## Medium Priority (Fix First Week Post-Launch)

### M1 — App Check disabled (intentional per social auth compatibility)
- **File:** `lib/main.dart:312`
- **Plan:** Enable at Firebase Console level after Google/Apple sign-in is stable under load. Low-risk given Firestore rules are comprehensive.

### M2 — `~32 print()` calls instead of `debugPrint`
- Stripped in release builds so not a runtime issue, but indicates code hygiene lapses. Top files: `main.dart` (7), `phone_login_screen.dart` (multiple), various services.
- **Fix:** Auto-replaceable in Phase 2.

### M3 — Dead code: `lib/screens/auth_screen.dart`
Orphaned email/password login screen from pre-v12.5. Never routed to.
- **Fix:** Rename to `.old` (per Rule 3) or delete entirely.

### M4 — No customer-facing "Request Refund" UI
Refunds only via admin dispute resolution. Customers must escalate to dispute to get any refund before expert_completed.
- **Fix:** See Q5.

### M5 — No device fingerprinting / IP logging
Expected per CLAUDE.md. Acceptable for Israeli MVP launch.
- **Plan:** Add in Phase 2 if fraud becomes a problem. Low-priority.

### M6 — "Founding provider" badge system not implemented
- No `foundingProvider`, `isFounder`, `earlyAdopter` references found.
- **Plan:** See Q4.

### M7 — 17 `Directionality(TextDirection.rtl)` legacy widgets
Unnecessary given MaterialApp locale config handles RTL automatically. Not harmful but code cluster.
- **Fix:** Gradual cleanup. Non-urgent.

---

## Dependency Updates Needed

### Flutter / Dart (top 6 with major gaps — test before upgrade)
| Package | Current | Latest | Gap | Risk |
|---------|---------|--------|-----|------|
| flutter_riverpod | 2.6.1 | 3.3.1 | +1 major | Breaking changes likely |
| flutter_secure_storage | 9.2.4 | 10.0.0 | +1 major | Security-critical |
| google_sign_in | 6.3.0 | 7.2.0 | +1 major | Auth integration |
| sentry_flutter | 8.14.2 | 9.18.0 | +1 major | Crash reporting |
| sign_in_with_apple | 6.1.4 | 7.0.1 | +1 major | Auth provider |
| google_fonts | 6.3.2 | 8.0.2 | +2 major | UI font loading |

### Node (functions/)
| Package | Current | Latest | Risk |
|---------|---------|--------|------|
| @anthropic-ai/sdk | 0.54.0 | 0.90.0 | Significant API drift — **test AI CEO tab after upgrade** |
| jest | 29.7.0 | 30.3.0 | Dev only, safe |

---

## Security Scan Results

✅ **No hardcoded secrets outside safe zones** — all API keys via Firebase Secrets Manager (`ANTHROPIC_API_KEY`, `GEMINI_API_KEY`).
✅ **`.gitignore` comprehensive** — `.env`, service account keys, google-services.json, keystores all excluded.
✅ **Firestore rules have zero `allow read, write: if true` wildcards.**
✅ **Account deletion truly deletes** (compliant with Israeli privacy law) — Firestore + Firebase Auth both removed via `admin.auth().deleteUser(uid)` in `deleteUserAccount` CF (`functions/index.js:4925-4943`).
✅ **Live selfie identity verification** — mandatory on provider onboarding, front-camera only (prevents gallery fakes).
✅ **5 existing anti-fraud checks in CFs** — relationship verification (XP), daily admin grant cap, idempotency dedup, self-grant prevention, deposit sufficiency.

---

## What Was Auto-Fixed

(Phase 2 not yet started — pending founder review of this report.)

---

## Strong Areas — Launch-Ready

- Provider onboarding: 11 mandatory fields, live selfie, admin approval required.
- Escrow state machine: paid_escrow → expert_completed → completed, with Firestore transactions.
- Amount validation in all payment CFs (grantAdminCredit, payQuote, processPaymentRelease, processCancellation).
- Currency locked to ILS (₪) across codebase.
- Terms of Service embedded + enforced-read checkbox before signup completion.
- i18n 100% synchronized across 4 locales (he/en/es/ar), 1,504 keys each.
- Crashlytics + Sentry dual-channel error reporting.
- Vault dashboard: 12 sections, hourly analytics + alerts CFs running.
- 67 composite indexes covering all queries (no silent empty-result bugs).
- MaterialApp locale + RTL auto-resolution configured correctly.

---

## Next Steps

1. **Founder reviews** `LAUNCH_AUDIT_QUESTIONS.md` (8 decisions).
2. After decisions, **Phase 2 auto-fixes** run on the H1/H4/H5/H7/H8 + M2/M3 items that don't require judgment.
3. **C1** (payment provider) is the gating blocker for real-money launch.
