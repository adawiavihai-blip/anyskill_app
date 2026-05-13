# AnySkill Pro — Auto-Eval System v1 (Phase 1 + Phase 2)

> Server-side badge grant/revoke activated 2026-04-24.
> Phase 2 notifications + email + dashboard polish activated same day.

## Decision logic

Single source of truth: [functions/pro_service.js](../functions/pro_service.js)
`evaluateProStatus({ db, uid, source, triggerReason?, adminUid? })`.

A provider is **granted** the Pro badge iff all 4 criteria pass:

| # | Criterion | Field (user doc) | Threshold (overridable via `system_settings/pro`) |
|---|-----------|------------------|----------------------------------------------------|
| 1 | Rating    | `rating`         | `>= minRating` (default 4.8) |
| 2 | Experience | count of `jobs` where `status == 'completed'` & `expertId == uid` | `>= minOrders` (default 20) |
| 3 | Response time | `avgResponseMinutes` | `<= maxResponseMinutes` (default 15). **Exception:** 0 = "no data yet", not penalised. |
| 4 | Reliability | count of `jobs` where `status == 'cancelled'`, `cancelledBy == 'expert'`, `cancelledAt > now - 30d` | must be `0` |

`proManualOverride == true` **freezes** the badge — auto-eval returns
early without writing.

## Triggers

All triggers live in [functions/index.js](../functions/index.js) (end of file).

| Name | Type | Fires when | source value |
|------|------|------------|--------------|
| `onJobCompletedEvalPro` | `onDocumentUpdated` on `jobs/{jobId}` | `status` transitions → `completed` | `auto` |
| `onJobCancelledEvalPro` | `onDocumentUpdated` on `jobs/{jobId}` | `status` transitions → `cancelled` AND `cancelledBy == 'expert'` | `auto` |
| `onReviewPublishedEvalPro` | `onDocumentUpdated` on `reviews/{reviewId}` | `isPublished` transitions false → true AND `isClientReview == true` | `auto` |
| `scheduledProRefresh` | `onSchedule` every 6h | always | `cron` |

Triggers are the primary path. The 6h cron exists purely to catch the
one case they cannot: a 30-day-old expert cancellation that rolls out of
the window without any new job activity on the provider.

## Callables

| Name | Auth | Input | Purpose |
|------|------|-------|---------|
| `evaluateMyProStatus` | authenticated (any user) | none | Used by [lib/screens/provider_ai_insights_screen.dart](../lib/screens/provider_ai_insights_screen.dart) — provider-initiated refresh. Hard-gated to `request.auth.uid` — the client CANNOT pass a target uid. Rate-limited to 1 call per 60s per uid. |
| `evaluateProStatusAsAdmin` | admin only (`isAdminCaller`) | `{ targetUid: string }` | Used by [lib/screens/admin_pro_tab.dart](../lib/screens/admin_pro_tab.dart) — admin-initiated recompute for any provider. |

The client-side [lib/services/pro_service.dart](../lib/services/pro_service.dart)
`checkAndRefreshProStatus(uid)` dispatches between the two: same signature
as before, but delegates to the server instead of writing directly.

## Fields written

All on `users/{uid}`:

| Field | Written by | Value |
|-------|-----------|-------|
| `isAnySkillPro` | `evaluateProStatus` on transition | `bool` |
| `anySkillProGrantedAt` | `evaluateProStatus` on **grant** (not revoke) | `Timestamp` — refreshed on every new grant. Historical grants live in `admin_audit_log.previousGrantedAt`. |
| `proManualOverride` | admin manual actions only | `bool` |

## Audit log

Every transition writes one `admin_audit_log/{auto-id}` document:

```jsonc
{
  "action":           "pro_granted" | "pro_revoked",
  "targetUserId":     "<uid>",
  "targetUserName":   "...",
  "source":           "auto" | "cron" | "callable_self" | "callable_admin",
  "triggerReason":    "job_completed:JOB_ID" | "job_cancelled_by_expert:..." | "review_published:..." | "scheduled_6h" | null,
  "adminUid":         "<uid>" | null,      // set when an admin triggered
  "revocationReason": "expert_cancellation_30d (count=N)" | "rating_below_threshold (...)" | null,
  "metricsSnapshot":  { rating, completedOrders, avgResponseMinutes, recentCancellations, thresholds: { ... } },
  "previousGrantedAt": Timestamp | null,   // old value BEFORE this grant
  "createdAt":        serverTimestamp()
}
```

Revocation-reason priority (first match wins): cancellation → rating →
orders → response. Matches the spec; surfaces the most actionable reason
in the notification email (Phase 2).

## Security

[firestore.rules](../firestore.rules) blocks client writes on
`isAnySkillPro`, `proManualOverride`, `anySkillProGrantedAt` via the
existing `doesNotTouch([...])` list on `users/{uid}` update. Admins still
write these fields through the `|| isAdmin()` clause (manual override).
Cloud Functions use the Admin SDK and bypass rules entirely.

`evaluateMyProStatus` cannot target other uids — it reads
`request.auth.uid` directly, never from `request.data`. 60-second
in-memory rate limit per uid.

## Tests

- [test/unit/pro_service_test.dart](../test/unit/pro_service_test.dart) —
  6 decision-logic invariants (boundary grant 4.8/20, boundary deny 4.79,
  immediate revoke on 1 cancellation, idempotency, 60-day-old cancel
  safety, manual override freeze).
- [test/unit/pro_audit_test.dart](../test/unit/pro_audit_test.dart) —
  6 audit-shape invariants (first-grant shape, re-grant
  `previousGrantedAt`, revocation-reason priority, rating-only revoke,
  idempotent no-log, manual-override no-log, admin-caller fields).

Run all: `flutter test test/unit/pro_service_test.dart test/unit/pro_audit_test.dart`.

## Deploy

```bash
firebase deploy --only functions:onJobCompletedEvalPro,functions:onJobCancelledEvalPro,functions:onReviewPublishedEvalPro,functions:scheduledProRefresh,functions:evaluateMyProStatus,functions:evaluateProStatusAsAdmin
firebase deploy --only firestore:rules
```

The `scheduledProRefresh` CF auto-creates its Cloud Scheduler job on
first deploy (§38). No manual GCP Console step needed.

## Phase 2 — active

Activated 2026-04-24 in the same release as Phase 1.

### Notification fan-out (`_notifyProviderTransition` in pro_service.js)

Every grant/revoke transition writes three side-effects, each wrapped in
its own try/catch so one channel failing never aborts the others:

1. **In-app notification** — `notifications/{auto-id}` with
   `type='pro_granted'|'pro_revoked'`, `userId`, Hebrew `title`/`body`,
   `isRead: false`, `createdAt`. Drives the bell-icon inbox.
2. **FCM push** — `admin.messaging().send({...})` with the provider's
   `fcmToken || deviceToken`. iOS priority 10, Android high priority,
   web opens the app. Gracefully skipped (warn-log only) when the
   provider has no token on file.
3. **Email** — `mail/{auto-id}` doc picked up by the Firebase Trigger
   Email extension. Grant → celebratory Hebrew template. Revoke →
   diagnostic template with the specific failing criterion + recovery
   tip. Both fully RTL, matching the copy the product team wrote.

### Router

[lib/services/notification_router.dart](../lib/services/notification_router.dart)
already routed `pro_granted` → `ProviderAiInsightsScreen`. Phase 2 adds
`pro_revoked` to the same branch so the provider lands on the 4-criteria
dashboard and immediately sees which one failed.

### Dashboard polish

[lib/screens/provider_ai_insights_screen.dart](../lib/screens/provider_ai_insights_screen.dart)
— the overall card now shows "חבר Pro מאז DD/MM/YYYY" when actively Pro.
Backed by the new `anySkillProGrantedAt` field on `ProMetrics`.

### Admin — "תנועות Pro ב-7 ימים אחרונים"

[lib/screens/admin_pro_tab.dart](../lib/screens/admin_pro_tab.dart) —
new card between the manual-override section and the Pro-list. Streams
`admin_audit_log` with `createdAt >= now-7d` (single-field auto-indexed,
no new composite needed), filters `action in [pro_granted, pro_revoked]`
client-side, renders:
- KPI strip: granted / revoked counts over the last week
- Up to 10 most-recent transitions, each row showing provider name,
  action emoji + label, source (auto/cron/callable_admin/etc. in
  Hebrew), revocation reason (short Hebrew), and relative timestamp.

### Test coverage

Added [test/unit/pro_notifications_test.dart](../test/unit/pro_notifications_test.dart)
— 8 invariants over the fan-out behavior: grant writes all 3 channels,
revoke uses the correct subject line + copy, missing fcmToken skips
push cleanly, missing/invalid email skips mail cleanly, revocation-copy
priority matches pro_service.js.

## Phase 3 (future, NOT in this release)

- Real-time StreamBuilder on the provider dashboard (currently
  FutureBuilder — refresh is explicit via button).
- Per-admin "who granted/revoked" drilldown table.
- Optional SMS channel for transitions on high-tier providers.
