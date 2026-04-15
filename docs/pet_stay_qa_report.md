# Pet Stay Tracker v13.0.0 — Full QA Report

**Date:** 2026-04-14
**Scope:** 10-phase systematic audit of the Pet Stay Tracker feature + project-wide regression check
**Result:** **6 bugs found, 6 fixed**, 0 regressions introduced

---

## Executive Summary

| Metric | Value |
|--------|-------|
| Phases executed | 10/10 |
| Bugs found | 6 |
| Bugs fixed | 6 |
| Bugs deferred | 0 |
| Pre-existing issues (documented, out-of-scope) | 11 |
| `flutter analyze` — pet_stay/ | **0 issues** |
| `flutter analyze` — full project | 11 issues (all pre-existing) |

---

## Bug Summary Table

| # | Phase | Severity | File | Bug | Root Cause | Fix Applied |
|---|-------|----------|------|-----|-----------|-------------|
| 1 | 2 | High | `firestore.rules` | PetStay `update` rule allowed either party to modify ANY field — malicious provider could forge rating, customer could wipe `dogSnapshot.allergies` | MVP shortcut: single-check permission without field allow-lists | Tightened with `diff().affectedKeys().hasOnly(...)` — customer: `rating, reviewText, ratedAt, status`; provider: counters + `status` |
| 2 | 3 | Medium | `dog_profile_builder_screen.dart` | Photo upload before typing name creates orphan doc with `name: ''` in Firestore + Storage | `_pickPhoto()` force-creates the profile doc (needs stable dogId for Storage path) without validating form | Added guard: abort + snackbar if name empty before pick |
| 3 | 4 | **HIGH** | `expert_profile_screen.dart` + `pet_stay_service.dart` | Schedule writes inside booking transaction could exceed Firestore's 500-op limit for long pension stays (180 days × 5 items = 900 items). Transaction throws → entire booking (payment!) rolls back | All writes inside `runTransaction` when only the snapshot needs atomicity with the job | Moved schedule writes OUT of the transaction. New `writeScheduleItemsBatched` commits in 400-item `WriteBatch` chunks. Graceful degradation: if batch fails, booking still lands with empty schedule |
| 4 | 5 | Medium | `dog_profile_card.dart` | Medications strict cast `List<Map<String,dynamic>>.from()` could throw `TypeError` if Firestore SDK returns `Map<Object?,Object?>` — fallback logic unreachable | Try/fallback via `.isEmpty` only catches success-empty case, not mid-iteration throw | Replaced with permissive `whereType<Map>() + Map.from()` pattern |
| 5 | 6 | Low | `owner_hero_card.dart` | ~250 lines of dead code: legacy `OwnerHeroCard` class with broken `_jobIdGuess()` stub returning empty string, shadowing the actual working `OwnerHeroCardWithJobId` | Incremental refactor left orphan class | Deleted the dead class entirely; file now contains only the working variant + helpers |
| 6 | 6 | **HIGH** | `firestore.indexes.json` + `live_walk_map.dart` | Missing composite index for `dog_walks.(jobId, startedAt DESC)`. LiveWalkMap query `where(jobId)+orderBy(startedAt DESC)+limit(1)` fails silently → owner never sees live walk | Index not registered when feature shipped | Added composite index to `firestore.indexes.json`. Same index also serves `DailyReportForm` autofill query |

---

## Phase Results

### Phase 1 — Compilation & Static Analysis
**Found:** 16 issues project-wide → **Fixed:** 5 (4 dangling doc comments + 1 `prefer_final_fields`). **Remaining:** 11 (all pre-existing, info-level).

### Phase 2 — Firestore Rules & Security
**Found:** 1 bug (#1) — too-permissive update rule. **Fixed:** tightened with per-party `diff().affectedKeys()` allow-lists.

### Phase 3 — Dog Profile (Owner)
**Found:** 1 bug (#2) — orphan profile from photo-before-name. **Fixed:** name-required guard.

### Phase 4 — Booking Flow
**Found:** 1 HIGH severity bug (#3) — transaction op-limit. **Fixed:** moved schedule to post-tx batch. **Also verified:** pension end-date picker, dog walker flag correctness, non-pet regression safety, chat-quote pet-gate.

### Phase 5 — Provider Pet Mode
**Found:** 1 bug (#4) — fragile medications cast. **Fixed:** permissive parse pattern.

### Phase 6 — Owner Pet Mode
**Found:** 2 bugs (#5 + #6) — dead code + missing index. **Both fixed.**

### Phase 7 — Daily Report
**Found:** 0 bugs. Index from Bug #6 fix also serves the autofill query.

### Phase 8 — Cross-Cutting & Edge Cases
**Found:** 0 bugs. All `.first` / `.last` / `!` usages guarded. RTL clean (no `EdgeInsets.only(left/right)`). Concurrent walks blocked in `DogWalkService.startWalk`. Walk resume scoped to current job. Deleted-dog race handled in `DogPickerSection`.

### Phase 9 — Regression (Non-Pet)
**Found:** 0 regressions. Non-pet bookings never set pet flags → all pet UI gated off. Chat-quote pet-gate fires only when schema has pet flags.

### Phase 10 — Final Report + MD Save
This document + CLAUDE.md update + MEMORY.md update.

---

## Files Changed During QA

### Security & Infrastructure
- `firestore.rules` — tightened `petStay/data` update rule with per-party field allow-lists
- `firestore.indexes.json` — added `dog_walks.(jobId, startedAt DESC)` composite index

### Pet Stay Feature
- `lib/features/pet_stay/services/pet_stay_service.dart` — new `writeScheduleItemsBatched(jobId, items)` method
- `lib/features/pet_stay/screens/dog_profile_builder_screen.dart` — name-required guard in `_pickPhoto`
- `lib/features/pet_stay/widgets/dog_profile_card.dart` — permissive medications parse
- `lib/features/pet_stay/widgets/owner_hero_card.dart` — deleted dead `OwnerHeroCard` class (~250 lines)

### Booking Flow
- `lib/screens/expert_profile_screen.dart` — hoisted `petStayJobId` + `petStayScheduleItems` out of transaction; added post-tx batch write with graceful degradation

### Codebase Hygiene (pre-existing cleanup)
- `lib/widgets/bookings/booking_shared_widgets.dart` — added `library;` directive
- `lib/widgets/bookings/calendar_widgets.dart` — added `library;` directive
- `lib/widgets/bookings/history_order_card.dart` — added `library;` directive
- `lib/widgets/bookings/transaction_history_card.dart` — added `library;` directive
- `lib/screens/alex_profile_screen.dart` — `_bioExpanded` → `final`

---

## Remaining Pre-existing Issues (NOT Pet Stay)

These 11 warnings exist in the project from before the Pet Stay work and require separate workflows to resolve:

| Count | Type | Location | Why not fixed |
|-------|------|----------|---------------|
| 9 | Riverpod `*Ref` deprecations (info) | `lib/providers/admin_*.dart` | Requires `build_runner` regeneration + explicit `Ref` import refactor. Scope = Riverpod 3.0 migration, NOT Pet Stay. |
| 2 | Dead methods `_classifyWithAI`, `_buildCategoryPicker` (warning) | `lib/screens/sign_up_screen.dart` | Removing cascades into ~80 lines of related dead fields (`_isClassifying`, `_aiResult`) + `CategoryAiService` integration. Pre-existing since AI classifier was removed from UI. |

All 11 are **info/warning level**, not errors. Zero runtime impact.

---

## Deployment Checklist

After this QA, deploy BOTH infrastructure changes:

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

**Critical:** The index deploy is required before owners will see the LiveWalkMap — otherwise the query silently returns empty.

Then rebuild + deploy web:

```bash
flutter build web --release
firebase deploy --only hosting
```

Ctrl+Shift+R in browser (service worker CSP cache).

---

## Manual QA Path (Post-Deploy)

1. **Customer:** Profile → הכלבים שלי → Add a dog (enter name first, then photo) → Save.
2. **Customer:** Book a pension provider for 14 days → dog picker appears, end-date picker defaults to +1 day → extend to 14 days → pay.
3. **Verify Firestore:** `jobs/{id}/petStay/data` exists with `isPension: true`, `totalNights: 14`, full `dogSnapshot`. `jobs/{id}/petStay/data/schedule/` has ~70 items (5/day × 14 days).
4. **Provider:** Opens active job → "מצב מטפל" → dog card + checklist visible, "התחל הליכון" button present.
5. **Provider:** Start walk → add 💧 pee marker → end walk → verify feed in Pet Mode shows walk_completed + pee updates.
6. **Customer:** Opens "מצב הכלב" → LiveWalkMap renders during active walk, then disappears when finished; feed populates.
7. **Provider:** Send "📊 דו"ח יומי" → verify mood + auto-fill stats appear in feed on both sides.
8. **Owner:** React ❤️ + reply on any feed item → provider sees reactions/replies in real time.
9. **Provider:** Mark job "expert_completed" → customer sees "⭐ איך היה?" prompt.
10. **Customer:** Submit 5-star rating + text review → verify `petStay/data.rating/reviewText/status=completed`.

**Non-pet regression check:** Open any non-pet provider → booking summary has no dog picker, no end-date picker. Pay normally. No `petStay/data` sub-doc created.

---

## Architectural Decisions Recorded

1. **Schedule writes are NOT atomic with booking.** Moved to post-tx `WriteBatch` to avoid 500-op transaction limit. Failure = empty schedule, booking still succeeds. Graceful degradation by design.

2. **`petStay/data` update rule uses per-party field allow-lists.** Customer writes only rating/review/status; provider writes only counters/status. Neither touches `dogSnapshot` — it's frozen at booking time.

3. **`OwnerHeroCard` stats derive from live feed, not stored counters.** Single source of truth. Stored `totalWalks/totalDistanceKm/etc.` fields exist for potential future use but are not the rendering source.

4. **The chat-quote pet-gate pre-check is fail-open.** If the provider's category lookup errors, the booking proceeds. Rationale: don't block real bookings on infra blips; the check is defense-in-depth.

5. **`dog_profiles/{ownerId}/**` Storage is readable by any signed-in user.** Provider needs to render the photo via the snapshot URL on their Pet Mode screen. URL obscurity + auth gate is sufficient; dog photos aren't sensitive.

---

*End of QA Report — 2026-04-14*
