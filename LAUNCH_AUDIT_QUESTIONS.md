# Launch Decisions Needed

Before Phase 2 auto-fixes run, 8 decisions require your input. Each item below has context, options, my recommendation, and the impact of deferring.

---

## Q1: Israeli payment provider integration
**Context:** Stripe Connect was removed in v11.9.x. Current app runs on an internal-credits ledger where money only enters via `grantAdminCredit` (admin tool). Cannot accept real customer payments. This is the **single biggest launch blocker**.
**Options:**
- A) **Tranzila** — cheapest fees, broad merchant support, mature API, but UI is dated.
- B) **PayPlus** — modern REST API + iframe checkout, stronger UX, slightly higher fees.
- C) **Cardcom** — Israeli incumbent, full-stack (invoices + payments), heavier integration.
- D) **Meshulam** — fintech-first, wallet + card, lighter integration but less proven at scale.
- E) **Defer** — launch as invite-only / free-tier MVP (no real money), delay monetization.

**My recommendation:** **B (PayPlus)** if we want a polished customer-facing checkout within 30 days, **A (Tranzila)** if minimizing fees is priority and we can absorb UI effort. Either way, plan 2 weeks dev + 1 week PSP certification.

**Impact if deferred:** Cannot onboard paying customers. Forces a "soft launch" / waitlist model.

---

## Q2: AI backend alignment — Gemini-only vs current hybrid
**Context:** The audit prompt states "Gemini only, NEVER Claude". The codebase intentionally uses **Claude Opus/Sonnet** for AI CEO tab (CLAUDE.md §12c, `functions/index.js:6698, 7404`) and **Gemini 2.5 Flash Lite** for Monetization tab (§31) + as cost fallback for CEO.
**Options:**
- A) **Keep hybrid** (current): Claude for CEO strategic analysis (strongest reasoning), Gemini for Monetization + fallback. Cost: ~$50-100/month Claude, ~$5/month Gemini.
- B) **Migrate CEO tab to Gemini 2.5 Pro**: single vendor, lower cost (~$10/month total), lower reasoning quality on complex strategy prompts.
- C) **Migrate everything to Gemini 2.5 Flash Lite**: cheapest (~$2/month), meaningful quality drop on CEO analysis.

**My recommendation:** **A (keep hybrid)**. Claude's reasoning is measurably stronger on open-ended strategy prompts, which is what CEO is for. The monthly cost is trivial vs the admin time it saves. The audit prompt's "Gemini only" rule seems to mis-model our architecture — confirm before I change anything.

**Impact if deferred:** None. Current hybrid works. Don't touch unless you want to consolidate.

---

## Q3: Re-enable App Check
**Context:** App Check is currently **disabled** (`lib/main.dart:312` — "DISABLED (social auth compatibility)"). Firestore rules are comprehensive so we're not defenseless, but App Check adds a client-attestation layer that blocks spoofed requests.
**Options:**
- A) **Enable at Firebase Console only** (no code change) — relies on Console-side enforcement. Works for web (reCAPTCHA Enterprise) + mobile (Play Integrity / App Attest).
- B) **Enable both Console + SDK call** — stronger but may break Google/Apple sign-in under edge conditions.
- C) **Defer to post-launch** — enable after 2-4 weeks of production traffic confirms auth stability.

**My recommendation:** **C (defer)**. Rules are solid. Enable Console-only toggle 2 weeks post-launch when we have traffic data.

**Impact if deferred:** Slightly higher risk of Firestore abuse (bot signups, scraping) for the first weeks. Mitigated by rate-limiting on sensitive endpoints.

---

## Q4: "Founding provider" badge
**Context:** No `foundingProvider` / `isFounder` / `earlyAdopter` field exists. You mentioned wanting this for launch to reward the first cohort (CLAUDE.md §3 doesn't mention it).
**Options:**
- A) **Implement now** — add `foundingProvider: true` field + badge widget on provider profile + search card. ~4 hours dev.
- B) **Implement in week 2 post-launch** — tag the first N providers retroactively once you have the cohort defined.
- C) **Skip entirely** — lean launch, no vanity badge.

**My recommendation:** **B (implement week 2)**. Cleaner — you'll know the exact cutoff once you see signup velocity. The badge has no urgent dependency.

**Impact if deferred:** None for launch. Providers won't miss it if it ships week 2.

---

## Q5: Customer-facing refund dialog
**Context:** Currently refunds only happen via admin dispute resolution. Customer must escalate to `disputed` status to request any refund. No direct "Request Refund" button in booking/chat screens.
**Options:**
- A) **Add customer "Request Refund" button** — before `expert_completed`, customer can one-tap full refund. After `expert_completed`, dispute-only.
- B) **Keep dispute-only** (current) — simpler but frustrating for legitimate cancellation requests.
- C) **Add refund button + auto-approve within cancellation deadline** — uses existing `processCancellation` CF (already handles flexible/moderate/strict policies per §4.4).

**My recommendation:** **C (use existing processCancellation CF)**. Wire a "Cancel & Refund" button in `my_bookings_screen.dart` that calls `processCancellation`. Zero new backend code. ~2 hours dev.

**Impact if deferred:** More support tickets. Not a blocker but a UX paper cut on day 1.

---

## Q6: Dependency upgrade strategy
**Context:** 15+ Flutter packages and `@anthropic-ai/sdk` have major/minor version gaps (see report H8). Riverpod 2→3, Sentry 8→9, google_sign_in 6→7, sign_in_with_apple 6→7, Anthropic SDK 0.54→0.90.
**Options:**
- A) **Upgrade everything pre-launch** — safest long-term, riskiest for schedule (each major upgrade needs regression testing).
- B) **Upgrade critical security libs only** — flutter_secure_storage 9→10, sentry 8→9. Defer Riverpod + auth.
- C) **Freeze everything** — ship as-is, upgrade post-launch with incident response plan.

**My recommendation:** **B (critical security only)** + upgrade Anthropic SDK in an isolated PR with AI CEO regression testing. The Riverpod 2→3 migration alone is 1-2 days of work; not worth risking pre-launch.

**Impact if deferred:** No immediate risk. Plan a "dependency week" in month 2.

---

## Q7: `pendingBalance` cross-user write hardening (C3)
**Context:** Any verified user can increment any other user's `pendingBalance` via client SDK (documented "accepted risk" per `firestore.rules:1369-1382`). Real payouts read from jobs, not this field, but an attacker could inflate another user's displayed pending balance for confusion/social engineering.
**Options:**
- A) **Move to CF-only** — block client writes, add CF that handles all pendingBalance mutations inside the escrow transaction. ~3 hours + migration.
- B) **Keep as-is** (accept risk) — documented, no known real-world exploit. Launch, revisit if abused.

**My recommendation:** **A (fix before launch)**. It's 3 hours of work and removes a category of attack. The fact that we noted it as "accepted risk" means we already know it's wrong.

**Impact if deferred:** Launch-day PR risk if a bad actor publicizes the exploit. Even a benign social media post showing "I inflated X's balance" would be bad optics.

---

## Q8: `lookupLegacyUidByPhone` rate limit (C2)
**Context:** Open callable CF (no auth) that returns the uid for a given phone number. Used during OTP flow to migrate legacy phone-login users. No rate limit → anyone can sweep every phone number in Israel and enumerate which belong to AnySkill users.
**Options:**
- A) **Add IP-based rate limit (10/min)** — standard approach, blocks sweeps, minimal effect on legit OTP flow.
- B) **Add caller-UID rate limit post-OTP** — weaker since pre-OTP callers have no UID.
- C) **Require App Check token on this endpoint** — strongest, but depends on Q3.

**My recommendation:** **A (IP rate limit)** — 30 minutes of work. Log suspicious sweeps to `activity_log` for admin visibility.

**Impact if deferred:** Privacy leak: attacker could publish "here are X thousand AnySkill user phone numbers" — a GDPR/privacy law incident.

---

## Next Step
Answer each question with the letter (A/B/C/etc) or write in your own answer. Once I have your decisions, I run Phase 2 auto-fixes on H1/H4/H5/H7/H8 + M2/M3 (the items that don't require judgment), commit each as a separate git commit, and report back.
