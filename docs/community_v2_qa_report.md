# Community v2 — QA Report

**Date:** 2026-04-29
**Scope:** Full audit of the Community v2 module (Phases A-G) plus a
project-wide cross-cutting scan.
**Methodology:** Manual interaction trace per screen + service-layer
data-flow verification + Firestore rules / indexes audit + build/analyze
sanity at the end.

---

## TL;DR

| Severity | Count | Status |
|----------|-------|--------|
| BLOCKER  | **1** | ✅ Fixed (missing composite index — caused query rejection) |
| MEDIUM   | **2** | ✅ Fixed (map FAB UX + empty-state flash) |
| LOW      | **2** | ✅ Fixed (defensive guard + documentation) |
| Deferred | 6     | 📋 Documented as known limitations |

**Final state:** `flutter analyze` → 20 pre-existing, **0 new**.
`flutter build web` → success in 38.3s.

---

## Part 1 — Community v2 module trace

Every interactive surface in the v2 module was traced from user input
to Firestore (or Storage) write. ✓ = passes; ⚠️ = bug found and fixed.

### 1. Home banner V2 (mockup 10)

| Element | Action | Result |
|---------|--------|--------|
| Tap card | `push CommunityHubScreenV2` | ✓ |
| 3-stat strip "החודש" | `_countMonthlyCompletions()` future | ⚠️ **[BLOCKER]** missing index — fixed |
| 3-stat strip "מתנדבים" | reads `_volunteerCount` from parent state | ✓ |
| 3-stat strip "פתוחות" | `_countOpenRequests()` future | ✓ |
| Facepile + "+N פעילים" | reads `_recentVolunteerAvatars` from parent | ✓ |

### 2. Onboarding (mockup 11)

| Element | Action | Result |
|---------|--------|--------|
| Mounting | initState → `addPostFrameCallback` checks `shouldShow` → push if first time | ✓ |
| "דלג" (slides 1-2) | `markSeen + maybePop` | ✓ |
| "המשך" (slides 1-2) | `_pageCtrl.nextPage` | ✓ |
| "בוא נתחיל" (slide 3) | `markSeen + maybePop` | ✓ |
| Re-entry after seen | `shouldShow == false` → no push | ✓ |
| `SharedPreferences` failure | helper falls back gracefully → no block | ✓ |

### 3. Hub V2 main screen (mockup 01)

| Element | Action | Result |
|---------|--------|--------|
| Header back arrow | `Navigator.maybePop` | ✓ |
| Header map icon | `push CommunityMapViewScreen` | ✓ |
| Header search icon | snackbar "מגיע בעדכון עתידי" (deferred V2) | ✓ |
| Hero stats | `where('status'=='completed').where('completedAt'>=startOfMonth)` | ⚠️ **[BLOCKER]** missing index — fixed |
| Social proof bar | `_loadActiveVolunteers(limit:5)` | ✓ |
| Recommended carousel card tap | `push PublicProfileScreen(userId)` | ✓ |
| Tab "בקשות פתוחות" | TabBarView | ✓ |
| Tab "ההתנדבויות שלי" | embeds `MyVolunteeringContent` | ✓ |
| Filter pill tap | `setState` + client-side filter | ✓ |
| Open request card tap | `push RequestDetailScreen(requestId)` | ✓ |
| Bottom CTA "פרסם בקשה להתנדבות" | `push RequestFormScreen` (fullscreenDialog) | ✓ |

### 4. RequestDetailScreen (mockup 02)

| Element | Action | Result |
|---------|--------|--------|
| Header back | `Navigator.maybePop` | ✓ |
| Primary CTA "אני יכול/ה להתנדב" | confirm dialog → `claimRequest()` → push ChatScreen | ⚠️ **[LOW]** added requesterId-empty guard |
| Status != open | label "הבקשה כבר נתפסה" + onPressed null | ✓ |
| Confirm dialog cancel | dismisses dialog | ✓ |
| Loading state | `CircularProgressIndicator` while `_busy` | ✓ |
| Error path | snackbar with service's Hebrew error string | ✓ |

### 5. RequestFormScreen (mockup 08, 3 steps)

| Element | Action | Result |
|---------|--------|--------|
| Header X (step 0) | `maybePop` | ✓ |
| Header X (step 1+2) | `setState` back a step (NOT pop) | ✓ |
| Step 1 title field | live counter via maxLength | ✓ |
| Step 1 description | inline error if length < 15 | ✓ |
| Step 1 category pills | `setState(_category)` | ✓ |
| Step 2 type pills | `setState(_requesterType)` | ✓ |
| Step 2 urgency 3-button | `setState(_urgency)` with animated bg | ✓ |
| Step 2 anonymous switch | `setState(_isAnonymous)` | ✓ |
| Step 3 preview | rendered from state | ✓ |
| Bottom "המשך" | gates on `_canProceed`, advances step | ✓ |
| Bottom "פרסם בקשה" (step 2 final) | `createRequest()` → snackbar + `pop(newId)` | ✓ |
| Bottom "הקודם" (steps 1+2) | `setState(_step--)` | ✓ |
| Submit failure | snackbar "פרסום נכשל" | ✓ |

### 6. CompleteVolunteeringScreen (mockup 04)

| Element | Action | Result |
|---------|--------|--------|
| Header back | `maybePop` | ✓ |
| Photo area tap | `showModalBottomSheet` (camera / gallery) | ✓ |
| Camera pick | `ImagePicker.pickImage(camera)` → upload → setState URL | ✓ |
| Gallery pick | `ImagePicker.pickImage(gallery)` → same flow | ✓ |
| Storage upload | `community_evidence/{requestId}_{ts}.jpg` (matches storage rule) | ✓ |
| Replace photo | re-tap area → new pick | ✓ |
| Note field | captures locally (NOT sent to service per documented decision) | ✓ |
| 15-min elapsed indicator | green when ≥ 15min, ענבר when < | ✓ |
| "ביטול" | `maybePop` | ✓ |
| "סיימתי לעזור" | gated on uploaded URL → `markTaskDone()` → snackbar + pop | ✓ |
| Service rejects (not 15min, etc.) | snackbar with service's Hebrew error | ✓ |

### 7. ConfirmCompletionScreen (mockup 05)

| Element | Action | Result |
|---------|--------|--------|
| Header back | `maybePop` | ✓ |
| Star tap (1-5) | `setState(_rating)` | ✓ |
| Review TextField onChanged | `setState` for live counter "X/10 מינ׳" | ✓ |
| Counter color | green ≥10, ענבר otherwise | ✓ |
| Thank-you note (optional) | gold-tinted card | ✓ |
| Proof photo display | `Image.network` with errorBuilder for broken URLs | ✓ |
| "עוד לא" | `rejectCompletion()` → maybePop | ✓ |
| "אשר ותודה" | gated on rating>0 + review.length≥10 → `completeRequest()` with rating → maybePop | ✓ |
| Rating writes to Firestore | only when 1-5 (no fake placeholders) | ✓ |
| Service errors | snackbar | ✓ |

### 8. CompletionCelebrationScreen (mockup 06)

| Element | Action | Result |
|---------|--------|--------|
| Data load | `Future.wait([users/{uid}, community_requests/{requestId}])` | ✓ |
| Hero medallion | static gold heart icon in tinted circle | ✓ |
| Stat row "XP שהורווח" | hardcoded "+450" (matches communityXpReward) | ✓ |
| Stat row "סה״כ התנדבויות" | reads `userData['volunteerTaskCount']` | ✓ |
| Stat row "לב זהב פעיל עד" | `GoldHeartHelper.expiryDateHebrew()` | ✓ |
| Stat row "דירוג שקיבלת" | reads real `req['rating']` (or "—" if absent) | ✓ |
| Thank-you note card | only renders when `req['thankYouNote']` non-empty | ✓ |
| Primary CTA tap | if `volunteerTaskCount <= 1` → push FirstGoldHeart, else maybePop | ✓ |
| Ghost "חזרה לבית" | `popUntil((r) => r.isFirst)` | ✓ |
| Data load failure | `_ErrorView` with back button (no fake celebration) | ✓ |

### 9. FirstGoldHeartScreen (mockup 15)

| Element | Action | Result |
|---------|--------|--------|
| Data load | `users/{uid}.name` → first name (fallback "מתנדב/ת") | ✓ |
| Top X close | `popUntil((r) => r.isFirst)` | ✓ |
| Hero medallion (88×88 + concentric rings) | static | ✓ |
| RichText "30 יום" emphasis | gold span via `TextSpan` | ✓ |
| 3 benefit rows | static layout | ✓ |
| "הצג את הפרופיל החדש שלי" | `popUntil((r) => r.isFirst)` | ✓ |
| Ghost "המשך לחפש בקשות" | `popUntil((r) => r.isFirst)` | ✓ |

### 10. MyVolunteeringContent (mockup 07)

| Element | Action | Result |
|---------|--------|--------|
| Header (only on standalone Scaffold variant) | back + title + 3-dot | ✓ |
| Hero "X התנדבויות" | reads `userData['volunteerTaskCount']` | ✓ |
| Monthly delta | placeholder "—" (Phase H deferred) | ✓ |
| Stats row "XP קהילתי" | reads `userData['communityXP']` + thousands format | ✓ |
| Stats row "דירוג ממוצע" | placeholder "—" (deferred until rating dataset is meaningful) | ✓ |
| Gold heart progress card | `GoldHeartHelper.progressFraction` + days left + expiry date | ✓ |
| No-active-heart state | renders `_NoHeartCard` empty-state | ✓ |
| Tab "פעילות" | streams `streamMyVolunteerTasks` | ✓ |
| Tab "פעילות" badge count | live count from same stream | ✓ |
| Tab "היסטוריה" | indexed query (volunteerId + status + completedAt DESC) | ✓ |
| Active card "סיימתי" | `push CompleteVolunteeringScreen(requestId: taskId)` | ✓ |
| Active card "צ'אט" | `push ChatScreen` (gated on requesterId not empty) | ✓ |
| Pending confirmation card | amber info pill (passive) | ✓ |
| Accepted card | gray info pill (passive) | ✓ |
| Empty state | "אין כרגע התנדבויות פעילות" | ✓ |
| History row | green checkmark + title + meta + "+450 XP" | ✓ |

### 11. MapViewScreen (mockup 13)

| Element | Action | Result |
|---------|--------|--------|
| Header back | `maybePop` | ✓ |
| "רשימה" toggle | `maybePop` (returns to hub) | ✓ |
| Map pan/zoom | `flutter_map` defaults | ✓ |
| Marker tap | `setState(_selectedRequestId, _selectedRequestData)` | ✓ |
| Selected marker visual | black bg + white text | ✓ |
| Bottom card visibility | renders only when selection exists | ✓ |
| Bottom card close × | clears selection | ✓ |
| Bottom card "הצג פרטים" | `push RequestDetailScreen(requestId)` | ✓ |
| Top filter chips | non-functional placeholder (Phase F deferred) | ✓ |
| My-location FAB | ⚠️ **[MEDIUM]** was just resetting to Tel Aviv — fixed to use LocationService |
| Empty state | ⚠️ **[MEDIUM]** flashed during load — fixed with `snap.hasData` guard |

### 12. NotificationRouter handlers

| Type | v2 path | v1 fallback | Result |
|------|---------|-------------|--------|
| `community_request` | push `RequestDetailScreen(requestId)` | popToFirst (legacy hub catches) | ✓ |
| `community_pending_confirmation` | push `ConfirmCompletionScreen(requestId)` | push `ChatScreen` with relatedUserId | ✓ |
| `community_completed` | push `CompletionCelebrationScreen(requestId)` | push `ChatScreen` with relatedUserId | ✓ |

All 3 are gated on `isCommunityV2EnabledFor(viewerUid)`.

### 13. Profile screen (mockup 09 elements)

| Element | Action | Result |
|---------|--------|--------|
| Avatar overlay (v2 + active heart) | gold heart with white halo + boxShadow | ✓ |
| Avatar overlay (v1 OR not active) | existing AnySkillBrandIcon | ✓ |
| "לב זהב פעיל" days bar | renders only for v2 + active heart | ✓ |
| Days remaining text | `GoldHeartHelper.daysUntilExpiryFromUserData` | ✓ |
| Existing community badge gradient | preserved (renders below new bar) | ✓ |
| All other profile elements | UNCHANGED | ✓ |

---

## Part 2 — Cross-cutting checks

### Services + signatures

| Check | Result |
|-------|--------|
| `completeRequest` callers pass new optional `int? rating` correctly | ✓ ConfirmCompletionScreen passes it; legacy callers don't (default null) |
| `markTaskDone` notification includes `requestId` | ✓ |
| `_notifyVolunteers` signature change → all callers updated | ✓ (only `createRequest`) |
| `_updateVolunteerProfile` 7-field atomic write | ✓ single `update()` call |
| `hasVolunteerHeart` no longer has callers | ✓ verified via grep — kept for API stability |
| `VolunteerService.hasActiveVolunteerBadge` delegates to GoldHeartHelper | ✓ search ranking gets the migration transparently |

### Firestore rules audit

| Rule | Allows v2 writes? |
|------|-------------------|
| `users/{uid}` update — `goldHeartExpiresAt` in onlyFields whitelist | ✓ Phase B |
| `community_requests/{id}` create — anyone authenticated, requesterId == auth.uid | ✓ |
| `community_requests/{id}` update — requester or volunteer or status==open | ✓ rating writes through this path |
| `notifications/{id}` create — max 10 fields, body ≤ 1000 chars | ⚠️ **[LOW]** `_notifyVolunteers` is at exactly 10 fields — added in-code comment |

### Firestore indexes audit

| Query | Index | Status |
|-------|-------|--------|
| `community_requests where status==open orderBy createdAt DESC limit 30` | status + createdAt DESC | ✓ existing |
| `community_requests where status==open + requesterType==X orderBy createdAt DESC` | status + requesterType + createdAt DESC | ✓ existing |
| `community_requests where requesterId + createdAt DESC` | exists | ✓ |
| `community_requests where volunteerId + status` (whereIn) | exists | ✓ |
| `community_requests where volunteerId + status + completedAt DESC` | exists | ✓ |
| `community_requests where status==open limit 80` (map) | single field — auto-indexed | ✓ |
| `community_requests where status==completed + completedAt >= startOfMonth` (hero stats) | status + completedAt | ⚠️ **[BLOCKER]** missing — added |

### Storage rules audit

| Path | Rule | Status |
|------|------|--------|
| `community_evidence/{file}` (mockup 04 photo upload) | signed-in + isImageContentType + ≤10MB | ✓ existing |

### Cloud Functions audit

| CF | Idempotency | Result |
|----|-------------|--------|
| `onCommunityRequestCompleted` | `if (before.status === 'completed') return null` | ✓ rule (א) |
| `backfillCommunityGoldHearts` | sentinel doc + admin_audit_log | ✓ rule (ב) |

Both CF + client-side `_updateVolunteerProfile` write `goldHeartExpiresAt` and the legacy fields. Both write `now + 30d` so the order of arrival doesn't matter — last-writer-wins on identical values. **No race issue.**

### l10n sweep

| File | Change |
|------|--------|
| `app_he.arb` line 1218 | "נתינה מהלב" → "קהילה" |
| `app_en.arb` line 1217 | "Giving from the heart" → "Community" |
| `app_es.arb` line 1139 | "Dar desde el corazón" → "Comunidad" |
| `app_ar.arb` line 1139 | "العطاء من القلب" → "المجتمع" |
| `app_localizations_he.dart` line 2474 | hardcoded "נתינה מהלב" → "קהילה" |
| `app_localizations_en.dart` line 2474 | "Giving from the heart" → "Community" |
| `app_localizations_es.dart` line 2474 | "Dar desde el corazón" → "Comunidad" |
| `app_localizations_ar.dart` line 2474 | "العطاء من القلب" → "المجتمع" |
| `app_localizations.dart` line 4701 | doc comment matches new HE text | ✓ |

`homeCommunitySlogan` deliberately UNCHANGED — only the title.

### Project-wide regressions

`flutter analyze` (full project): **20 issues, 0 new from this work.** All
20 are pre-existing deprecations in unrelated files
(`admin_user_detail_provider.dart`, `admin_users_provider.dart`,
`credentials_service.dart` — all baseline §44/§45/§54 warnings).

---

## Part 3 — Bugs found and fixed

### Fix #1 — BLOCKER: Missing composite index (status + completedAt)

**Symptom:** The Hub V2 hero "X התנדבויות החודש" + the home banner V2
"החודש" stat would silently show "—" forever in production. The Firestore
query would throw `FAILED_PRECONDITION: The query requires an index`.

**Root cause:** Two queries added in Phase D-1 use
`where('status'=='completed').where('completedAt'>=startOfMonth)` — needs
a composite index `status ASC + completedAt ASC`. None of the existing
9 community_requests indexes covered this shape.

**Fix:** Added the index at the TOP of `firestore.indexes.json` (with a
`_comment` pointing to the affected widgets).

**Deploy:** `firebase deploy --only firestore:indexes` will trigger
Firestore to build the index (1-5 min). After that, both stat surfaces
populate correctly.

### Fix #2 — MEDIUM: Map "my location" FAB was misleading

**Symptom:** The FAB in `MapViewScreen` had a `Icons.my_location_rounded`
icon implying it goes to the user's actual location. In reality it just
moved the camera back to a hardcoded Tel Aviv center.

**Root cause:** Phase E shipped the FAB with a placeholder onTap.

**Fix:** Wired `_goToMyLocation()` to call
`LocationService.requestAndGet(context)`. On success → `_mapCtrl.move`
to the actual coordinates with zoom 14. On null (permission denied or
geolocation failure) → falls back to Tel Aviv.

### Fix #3 — MEDIUM: Map empty state flashed during initial load

**Symptom:** "אין כרגע בקשות עם מיקום באזור זה" appeared for a frame
during the initial connecting state of the Firestore stream, before any
data arrived. Cosmetic but jarring.

**Root cause:** The condition was
`withLoc.isEmpty && snap.connectionState == ConnectionState.active`. For
a snapshots stream, `connectionState` is `.active` even before the first
snapshot lands, so an empty-list result was returned during loading.

**Fix:** Tightened condition to `snap.hasData && withLoc.isEmpty` —
guarantees the empty state only renders after at least one snapshot has
arrived.

### Fix #4 — LOW: requesterId empty guard in claim flow

**Symptom:** Theoretical — if a `community_requests` doc is malformed
and has an empty `requesterId`, the post-claim `pushReplacement` to
`ChatScreen(receiverId: '')` would push a broken chat.

**Root cause:** No data integrity safety net. (`createRequest` always
sets `requesterId`, so this shouldn't happen in practice.)

**Fix:** Added a defensive check in `RequestDetailScreen._claim` — if
`requesterId.isEmpty` after a successful claim, show a friendly snackbar
("תפסת את ההתנדבות. פתח/י את ההתנדבויות שלי לצ׳אט.") and pop back
instead of pushing a broken chat.

### Fix #5 — LOW: Notifications field-count documentation

**Symptom:** `_notifyVolunteers` writes notifications with EXACTLY 10
fields, the hard limit set by `firestore.rules`. If a future PR adds
another field, the rule will start rejecting the writes silently (since
they're `.add()` calls inside fire-and-forget loops).

**Root cause:** Easy to miss the limit when adding fields.

**Fix:** Added an in-code comment immediately above the
`notifications.add(...)` block warning future maintainers about the
limit and which two fields (`category`, `urgency`) are good drop
candidates.

---

## Part 4 — Known limitations (deferred — not bugs)

| # | Item | Why deferred |
|---|------|--------------|
| 1 | Mockup 12 — Yearly Recap | Requires CF aggregator + trigger on Jan 1; V2 scope per kickoff |
| 2 | Mockup 14 — Skills Search | Conceptual change (free-text search vs categories); V2 per kickoff |
| 3 | Mockup 17 — Streak | Requires weekly cron + new `volunteerStreakWeeks` field; V2 per kickoff |
| 4 | Mockup 16 — distance + demographic in push body | Requires geo data on volunteer + age schema we don't track yet (kept the simpler "התנדבות חדשה / דחופה" copy) |
| 5 | Auto-popup celebration when volunteer is in-app | Phase H polish — currently only fires via notification tap |
| 6 | Volunteer's optional note in `markTaskDone` | UI captures the text but service signature doesn't accept it; needs a small additive update |
| 7 | Mockup 03 — community-skinned chat | Per project rule (CLAUDE.md §47/§54) we never fork ChatScreen — using the existing one as-is |
| 8 | Real average rating + monthly delta % | Placeholder "—" until enough rated requests exist + a 2-query (current+prior month) helper |
| 9 | Map "קרוב אליי" filter | Currently shows all — Phase F may wire to `LocationService` for distance filtering |
| 10 | Storage path `community_evidence` open to any signed-in user | Pre-existing issue from CLAUDE.md §50 — flagged for security audit Phase 2 |

---

## Part 5 — Pre-deploy checklist (UPDATED with QA fix #1)

Run these in order. The new index deploy is REQUIRED before flipping
the v2 flag for users — without it, the home banner + hub hero will
silently show "—".

```bash
# 1) Firestore rules + INDEXES (rules unchanged from Phase B; index NEW)
firebase deploy --only firestore:rules,firestore:indexes

# 2) Two Cloud Functions
firebase deploy --only functions:onCommunityRequestCompleted,functions:backfillCommunityGoldHearts

# 3) Web hosting (with all Phase A-G + QA fixes)
flutter build web --release && firebase deploy --only hosting

# 4) Manual: run backfillCommunityGoldHearts ONCE from Firebase Console
#    → Functions → Force run → {}
#    Verify: Firestore Console → system_config/migrations/community_gold_heart_backfill_v1/status.completed === true
```

**The new composite index takes 1-5 minutes to build** after `firebase
deploy --only firestore:indexes`. Watch progress at
https://console.firebase.google.com/project/anyskill-6fdf3/firestore/indexes

---

## Part 6 — Final validation snapshot

```
flutter analyze         → 20 issues (all pre-existing, 0 new)
flutter build web       → Built build\web in 38.3s, 0 errors
node -c functions/index.js → OK
```

**21 community v2 files compile clean** (11 screens + 7 widgets + 1
helper + 1 theme + 1 feature flag). **5 modified files** still pass
their own analyze. **0 new analyze warnings** project-wide vs the
baseline established at start of Phase A.

---

*Reviewer: Claude Opus 4.7 (1M context) · Methodology: manual interaction
trace + service signature audit + Firestore rules + indexes verification +
build sanity. No automated test suite was run because the project does
not have one for these surfaces — the existing `test/unit/` suite is
unrelated to community.*
