# 📊 CURRENT STATUS - AnySkill Scaling State

**This file is updated automatically by Claude Code after each milestone completion.**
**It tells Claude Code the current state of the app.**

---

## 🎯 ACTIVE STATE

```yaml
active_milestone: 1
milestone_name: "Option A - Premium UI + Nova AI (Pre-launch)"
last_updated: "2026-04-18"
status: "completed"
completed_date: "2026-04-18"
```

---

## 📈 CURRENT METRICS (Real state · pre-launch)

```yaml
# === USER METRICS (live from CF snapshot — verified 2026-04-18) ===
daily_active_users: 2          # reported from updateMetricsSnapshot logs
monthly_active_users: 5        # best estimate
total_registered: 5            # real count
new_signups_per_day: 0         # pre-launch soft distribution

# === TECHNICAL METRICS (no real telemetry yet — lands in Milestone 3) ===
firestore_reads_per_day: 0     # unknown until BigQuery pipeline
firestore_writes_per_day: 0
firestore_peak_writes_per_sec: 0
firestore_monthly_cost_usd: 0  # negligible at 5 users (well under $1/mo)

# === PERFORMANCE ===
dashboard_load_time_ms: 0      # no telemetry — Milestone 3 dependency
api_p95_latency_ms: 0
error_rate_percent: 0          # CF computes from error_logs
uptime_percent: 99.9

# === INFRASTRUCTURE ===
has_premium_ui: true          # ← Milestone 1 ✅
has_nova_ai: true             # ← Milestone 1 ✅
has_scale_alerts: true        # ← Milestone 1 ✅
has_business_metrics: true    # ← Milestone 1 ✅
has_redis: false
has_bigquery_pipeline: false
has_sharding: false
has_multi_region: false
has_ai_agents: false
has_chaos_engineering: false
```

---

## 🚦 MILESTONE PROGRESS TRACKER

| # | Milestone | Status | Trigger | Done Date |
|---|-----------|--------|---------|-----------|
| 1 | Option A - Premium UI + Nova AI | ✅ COMPLETED | Start NOW | 2026-04-18 |
| 2 | Redis Cache Layer | ⏳ Waiting | DAU > 10K OR Firestore cost > $200/mo | - |
| 3 | BigQuery Pipeline | ⏳ Waiting | DAU > 50K OR Dashboard load > 2s | - |
| 4 | Sharding + Multi-region | ⏳ Waiting | DAU > 500K OR Writes > 8K/sec | - |
| 5 | Enterprise V5 (AI Agents + Chaos) | ⏳ Waiting | DAU > 5M | - |

**Next milestone:** Milestone 2 (Redis Cache Layer)
**Next milestone file:** `02_REDIS_SETUP.md`
**Next trigger:** `DAU > 10,000` OR `Firestore cost > $200/month`

---

## 🚨 ACTIVE TRIGGERS (Warnings)

*Claude Code: Check these against metrics above. If ANY trigger, recommend upgrade.*

```yaml
# Redis triggers (milestone 2)
trigger_redis_dau: false    # true if daily_active_users > 10000
trigger_redis_cost: false   # true if firestore_monthly_cost_usd > 200

# BigQuery triggers (milestone 3)
trigger_bigquery_dau: false         # true if daily_active_users > 50000
trigger_bigquery_dashboard: false   # true if dashboard_load_time_ms > 2000

# Sharding triggers (milestone 4)
trigger_sharding_dau: false     # true if daily_active_users > 500000
trigger_sharding_writes: false  # true if firestore_peak_writes_per_sec > 8000

# Enterprise triggers (milestone 5)
trigger_enterprise_dau: false   # true if daily_active_users > 5000000
```

---

## 📝 AUTOMATIC UPDATE INSTRUCTIONS (For Claude Code)

When Claude Code completes a milestone, update this file:

### After Milestone 2 completion:
```yaml
active_milestone: 2
milestone_name: "Redis Cache Layer"
status: "completed"
completed_date: "YYYY-MM-DD"

has_redis: true
redis_hit_rate: 85

trigger_redis_dau: false
trigger_redis_cost: false
```

### ... (same pattern for milestones 3, 4, 5)

---

## 📋 HISTORY LOG

*Claude Code appends entries here after each milestone:*

```markdown
## 2026-04-18 - Initial Setup
- Created scaling system
- Ready to start Milestone 1 (Option A)
- Current DAU: 4,000
- Estimated trigger for Milestone 2: 2026-07 (based on 50 signups/day growth)

## 2026-04-18 - Milestone 1 Completed ✅
Built premium Performance Observatory replacing the legacy admin tab.

### What was built
- **Premium Glassmorphism UI** — dark gradient background, 5 ambient orbs,
  glass cards with backdrop blur, indigo/purple/pink business palette.
  All content wrapped in `Directionality(textDirection: TextDirection.rtl)`.
- **Scale Alert Widget** ⭐ (THE innovation) — reads the live metrics and
  surfaces the top applicable Milestone trigger as a hero banner. Tap the
  action button → sheet with milestone file, trigger detail, and the
  exact Claude Code prompt to run. Supports stacked alerts (multiple
  triggers active).
- **Business Impact Widget** — live: revenue today/week/month, bookings,
  DAU+MAU, Happiness Score (completed/total jobs), churn risk (stale users),
  open disputes.
- **Scale Readiness Score** — static `completed/60 + flags × weights`
  calculation showing the 8-item infra checklist. At Milestone 1 scores ~66.
- **Cost Projection Widget** — 5-row table from current to 10M DAU with
  the current row highlighted.
- **Golden Signals** — 4 cards: Latency / Traffic / Errors / Saturation.
  Color-coded by threshold, with "Milestone 3 required" hints for the
  values that need BigQuery telemetry.
- **Nova AI Chat** — full-height chat with 3 suggestion chips, typing
  animation, gradient bubbles, "Gemini 2.5 Flash Lite" badge. Never
  touches Claude.

### Cloud Functions added
1. `updateMetricsSnapshot` — scheduled every 5 min. Runs 13 parallel
   Firestore counts/sums, writes `performance_metrics/current` with:
   DAU, MAU, bookings today/week/month, revenue today/week/month,
   completed/total/cancelled jobs, errors last hour/24h, open disputes,
   happiness score, churn risk, error rate, uptime, cost hints.
   Memory: 256MiB · Timeout: 120s · Region: us-central1.
2. `askNovaChat` — callable (admin + support_agent). Takes `{question,
   context}` → Gemini 2.5 Flash Lite via REST → returns `{text, model}`.
   Logs each conversation to `nova_conversations/{id}` with `expireAt`
   (30d TTL). 1000-char cap on question. No Claude.

### Files created
- `lib/screens/performance/models/performance_metric.dart`
- `lib/screens/performance/models/scale_alert.dart`
- `lib/screens/performance/services/performance_service.dart`
- `lib/screens/performance/services/metrics_calculator.dart` (ScaleAlertEngine)
- `lib/screens/performance/services/nova_chat_service.dart`
- `lib/screens/performance/widgets/_design.dart` (PerfDesign palette)
- `lib/screens/performance/widgets/scale_alert_widget.dart` ⭐
- `lib/screens/performance/widgets/business_impact_widget.dart`
- `lib/screens/performance/widgets/scale_readiness_widget.dart`
- `lib/screens/performance/widgets/cost_projection_widget.dart`
- `lib/screens/performance/widgets/golden_signals_widget.dart`
- `lib/screens/performance/widgets/nova_ai_chat_widget.dart`
- `lib/screens/performance/performance_tab.dart` (main)

### Files modified
- `lib/screens/admin_screen.dart` — swapped import +
  `const SystemPerformanceTab()` → `const PerformanceTab()`.
- `functions/index.js` — appended `updateMetricsSnapshot` +
  `askNovaChat` CFs (~300 lines).

### Legacy kept (per user directive "לא למחוק כלום")
- `lib/screens/system_performance_tab.dart` remains on disk, now
  orphaned (no imports). Safe to delete in a future cleanup PR.

### Scaling contract in place
- Widgets DO NOT fetch from Firestore directly. They consume the
  single `PerformanceMetric` snapshot produced by the scheduled CF.
- At 4K DAU, the whole tab is **1 Firestore read per render** +
  the CF snapshot every 5 minutes.
- When DAU or Firestore cost trips the next threshold, the Scale
  Alert Widget will banner the next Milestone automatically.

### Validation
- `flutter analyze` on new tab: **0 issues**
- `flutter analyze` full project: 13 pre-existing info warnings,
  **zero regressions introduced**.
- `node -c functions/index.js`: **OK**.

### Cost impact
- CF executions: `updateMetricsSnapshot` = 288 runs/day, each ~15
  reads = ~4,300 reads/day (~$0.01/month)
- `askNovaChat`: ~$1/month expected (Gemini Flash Lite is cheap)
- **Total: ~$1-2/month added to existing footprint**

### Next steps
- Watch for: DAU > 10,000 OR Firestore monthly cost > $200
- When triggered: Scale Alert Widget will banner Milestone 2
  automatically. Admin requests Claude Code to "execute 02_REDIS_SETUP.md".
- Estimated trigger date: tbd (depends on actual launch date).

## 2026-04-18 - Milestone 1 Hotfix 🔧
Dashboard was reading correctly at the CF layer (logs showed
`DAU=2 bookings=0 rev=₪0 happy=80`) but showing zeros in the UI.

### Root cause
No Firestore security rules for `performance_metrics/` collection.
The `updateMetricsSnapshot` CF writes via Admin SDK (bypasses rules
— works fine) but the Flutter client's `StreamBuilder` got a silent
`permission-denied` on `.snapshots()`, so `snap.data` was always
null and `PerformanceMetric.empty()` (all zeros) rendered.

### Fix
1. **firestore.rules** — added explicit match blocks:
   - `performance_metrics/{docId}`: `allow read: if isAdmin() || isSupportAgent()`
   - `nova_conversations/{docId}`: `allow read: if isAdmin()`, no client writes
2. **Removed hardcoded placeholder values** from the CF write
   (`firestore_monthly_cost_usd: 25`, `dashboard_load_time_ms: 800`,
   etc.). These were lies at 5-user pre-launch scale. They now
   render as 0/— with the "Milestone 3 required" hint in the
   Golden Signals widget.
3. **Freshness indicator** — new `freshness_dot.dart` shows 🟢
   (<1h), 🟡 (1-5h), 🔴 (>5h), ⏳ (no snapshot yet). Dot appears
   in the header next to the timestamp. When `lastUpdated == null`
   the whole tab gets an orange `WaitingForSnapshotBanner` at the
   top telling the admin the CF hasn't fired yet.
4. **Pre-launch reality check** — updated the current metrics
   block above from aspirational "4000 DAU" to real "2 DAU, 5
   registered, negligible cost".

### Deploy
```bash
firebase deploy --only firestore:rules
firebase deploy --only functions:updateMetricsSnapshot
flutter build web --release && firebase deploy --only hosting
```

### Validation
- `flutter analyze`: clean on new files (pre-existing project-wide baseline unchanged)
- Firestore rules compile: OK
- CF syntax: OK
- Post-deploy: admin opens tab → sees real DAU=2, happiness=80, etc.
  If the first snapshot hasn't landed yet (1st 5-min tick), shows
  the "ממתין לעדכון ראשון" banner instead of zeros.
```

---

## 🎯 HOW TO READ THIS FILE

### If you're Claude Code:
1. Check `active_milestone` - what's in progress?
2. Check `status` - is it done?
3. Check triggers - should we upgrade?
4. Execute accordingly

### If you're Avihai:
1. See current state at top
2. See progress table
3. Any trigger = red flag → time to upgrade!
4. Tell Claude Code: "Execute next milestone"

---

## 🔄 MANUAL OVERRIDE

If Claude Code misses a trigger or you want to force an upgrade:

```markdown
## MANUAL OVERRIDE REQUESTED
Date: YYYY-MM-DD
Reason: <why>
Force upgrade to milestone: X
Approved by: Avihai
```

---

**Last automatic check:** 2026-04-18
**Next automatic check:** When dashboard metrics update
