# 🚀 Performance Observatory V5 SCALE-READY - Main Implementation Prompt

## 📋 Project Context

**Project**: AnySkill - Hebrew/RTL two-sided service marketplace  
**Module**: Admin Panel → מערכת → ביצועים 🖥️  
**File Location**: `lib/screens/admin/tabs/system/performance_tab.dart` (rewrite completely)  
**Language**: Flutter + Dart (frontend) + TypeScript (Cloud Functions) + Hebrew RTL  
**AI Architecture**: HYBRID — Claude for strategic AI CEO, **Gemini 2.5 Pro for Performance Observatory** (per CLAUDE.md §12c, §31)

---

## 🎯 Mission Statement

Replace the existing basic performance tab (4 gauges + error feed + 3 maintenance buttons) with a **world-class observability dashboard** matching Datadog/New Relic/Dynatrace quality, featuring:

1. **AI Copilot "Nova"** — conversational AI that explains terms and solves issues
2. **5 Autonomous AI Agents** — Detective, Healer, Oracle, Guardian, Chronicler
3. **Business Observability** — links tech issues to revenue loss in real-time
4. **10M Users Scale-Ready Architecture** — BigQuery + Redis + Sharded Firestore + Multi-region
5. **30+ sections** covering every aspect of system health

---

## 🏗️ Critical Architecture Requirements

### ⚠️ CRITICAL: Scale-Ready Patterns (Non-Negotiable)

The existing dashboard reads directly from Firestore for metrics. **This WILL NOT scale beyond 100K users.** Replace with:

```
Users → CloudFlare CDN (91% hit rate)
      → Cloud Run (2-100 auto-scale instances)
      → Redis Cache (95% hit rate for hot data)
      → Firestore (sharded ×10, only 5% of reads)
      
Metrics Flow (separate pipeline):
      Cloud Run emits events → Pub/Sub → Dataflow aggregation
      → BigQuery (partitioned, 6mo hot + 2y cold)
      → Dashboard reads from BigQuery (NOT Firestore!)
```

**Expected cost at 10M DAU with this architecture**: $195K/month ($0.02/user/month)  
**Expected cost WITHOUT this architecture**: $180K/month but with frequent outages and degraded performance

### 🔑 Design System (Dark Premium Glassmorphism)

```dart
// Background gradient
colors: [
  Color(0xFF050816),  // ultra dark
  Color(0xFF0A0E1A),
  Color(0xFF0F1420),
  Color(0xFF1A0A2E),  // deep purple
]

// Ambient orbs (5 total, decorative)
// indigo, green, purple, orange, pink — radial gradients blur 70%

// Glassmorphism cards
background: Color.fromRGBO(255, 255, 255, 0.04)
border: Color.fromRGBO(255, 255, 255, 0.08)
backdropFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20)

// Business palette (KEY for financial impact UI)
pink: Color(0xFFEC4899)      // revenue
rose: Color(0xFFDB2777)      // loss
indigo: Color(0xFF6366F1)    // primary
purple: Color(0xFFA855F7)    // AI
orange: Color(0xFFFB923C)    // warnings

// Status colors
green: Color(0xFF4ADE80)     // healthy
yellow: Color(0xFFFDBA74)    // warning
red: Color(0xFFFCA5A5)       // critical
```

All text must use `Directionality.of(context) == TextDirection.rtl`.

---

## 📂 Files to Create/Modify

### New Flutter files:
1. `lib/screens/admin/tabs/system/performance_tab.dart` (main tab, rewrite)
2. `lib/screens/admin/widgets/performance/ai_copilot_nova_widget.dart` (Nova chat)
3. `lib/screens/admin/widgets/performance/business_impact_widget.dart` (revenue/min)
4. `lib/screens/admin/widgets/performance/ai_agents_swarm_widget.dart` (5 agents)
5. `lib/screens/admin/widgets/performance/incident_war_room_widget.dart`
6. `lib/screens/admin/widgets/performance/scale_readiness_widget.dart` (Score 68/100)
7. `lib/screens/admin/widgets/performance/architecture_live_view_widget.dart` (data flow)
8. `lib/screens/admin/widgets/performance/golden_signals_widget.dart` (Latency/Traffic/Errors/Saturation)
9. `lib/screens/admin/widgets/performance/cost_projection_widget.dart` (calculator)
10. `lib/screens/admin/widgets/performance/conversion_funnel_widget.dart`
11. `lib/screens/admin/widgets/performance/cohort_analysis_widget.dart`
12. `lib/screens/admin/widgets/performance/impact_simulator_widget.dart` (what-if)
13. `lib/screens/admin/widgets/performance/feature_flags_widget.dart`
14. `lib/screens/admin/widgets/performance/chaos_engineering_widget.dart`
15. `lib/screens/admin/widgets/performance/blameless_postmortem_widget.dart`
16. `lib/services/performance_observatory_service.dart` (reads from BigQuery!)
17. `lib/services/nova_ai_copilot_service.dart`

### New Cloud Functions (TypeScript):
1. `functions/src/performance/askPerformanceCopilot.ts` (Nova AI)
2. `functions/src/performance/analyzePerformanceMetrics.ts`
3. `functions/src/performance/predictSystemIssues.ts`
4. `functions/src/performance/generateRootCauseAnalysis.ts`
5. `functions/src/performance/groupSimilarErrors.ts`
6. `functions/src/performance/detectAnomalies.ts`
7. `functions/src/performance/calculateHealthScore.ts`
8. `functions/src/performance/calculateBusinessImpact.ts`
9. `functions/src/performance/orchestrateAgentSwarm.ts`
10. `functions/src/performance/simulateImpactScenario.ts`
11. `functions/src/performance/generateBlamelessPostMortem.ts`
12. `functions/src/performance/runSyntheticTests.ts`
13. `functions/src/performance/rollbackDeployment.ts`
14. `functions/src/performance/autoScaleTrigger.ts`
15. `functions/src/performance/aggregateMetricsToBigQuery.ts` (CRITICAL for scale!)
16. `functions/src/performance/triggerChaosTest.ts`

### Infrastructure files:
1. `infrastructure/bigquery/create_tables.sql`
2. `infrastructure/firestore/indexes_sharded.json`
3. `infrastructure/redis/cache_config.ts`
4. `infrastructure/pubsub/topics_setup.sh`
5. `infrastructure/cloudrun/scale_config.yaml`

---

## 🎨 UI Layout Order (top to bottom)

1. **Sticky Header** — Logo + On-Call badge + ⌘K + 🎤 Voice + 🤖 Nova AI button
2. **Scale Readiness Score** (big widget, score 0-100 + 5 sub-items)
3. **Architecture Live View** (animated data flow diagram)
4. **Cost Projection Calculator** (today/100K/1M/10M DAU)
5. **Top KPI Strip** (Health/APDEX/MTTR/Deploy Freq/CFR/DAU + MRR)
6. **Business Impact Banner** (revenue/min, conversion drop, churn risk)
7. **AI Agents Swarm** (5 agent status cards)
8. **Active Incident → Incident War Room** (collapsible)
9. **4 Golden Signals** (Latency/Traffic/Errors/Saturation)
10. **Global Performance Map** (12 regions)
11. **High Availability** (Multi-region status)
12. **Circuit Breakers + Rate Limits** (per-service)
13. **Auto-Scaling Live** (Cloud Run instances graph)
14. **Load Shedding Tiers** (4 tiers: Critical/Important/Nice/Background)
15. **Data Architecture** (4 tiers: Hot/Warm/Cool/Cold)
16. **Deploy Health Tracker** (last 5 deploys with health)
17. **Anomaly Detection** (ML spikes)
18. **Response Time Heatmap** (24h × 8 latency buckets)
19. **Service Map** (node graph with tolerances)
20. **SLO + Error Budget** (3 SLOs with budgets)
21. **Smart Error Groups** (clustered errors, not flat list)
22. **AI Copilot Nova Chat** (full section, not just button)
23. **Conversion Funnel** (6-step funnel)
24. **Cohort Analysis** (retention heatmap table)
25. **Feature Adoption** (per-category bars)
26. **Impact Simulator** (3 what-if scenarios)
27. **Chaos Engineering Lab** (4 chaos tests)
28. **Feature Flags + Dark Launches**
29. **Session Replay** (user journey + heatmap)
30. **Logs Explorer** (live tail)
31. **On-Call Rotation** (current + backup)
32. **Synthetic Monitoring** (4 user flows)
33. **Blameless Post-Mortem** (AI-generated drafts)
34. **Predictive Alerts** (AI Crystal Ball - 3 predictions)
35. **Disaster Recovery** (RTO/RPO metrics)
36. **Timeline** (24h events)
37. **Quick Actions** (10 action buttons)
38. **Firebase Costs** (today + breakdown + AI savings)
39. **RUM + Core Web Vitals** (LCP/FID/CLS + device split)
40. **Footer** (integrations badges)

---

## 🔗 Integration Points

### Firebase services:
- Firebase Performance Monitoring (existing)
- Firebase Crashlytics (existing)
- Sentry (existing)
- Firestore (read/write, BUT metrics should go to BigQuery)
- Cloud Functions (all new ones listed above)

### External services:
- Gemini 2.5 Pro (for Nova + 5 agents + predictions)
- BigQuery (new - for metrics pipeline)
- Redis (Memorystore for Redis on GCP)
- Pub/Sub (metrics event streaming)
- CloudFlare CDN (edge caching)
- PagerDuty (incident escalation)
- Mixpanel (user analytics)
- Stripe (MRR data)

---

## 🌐 Localization (Hebrew RTL)

All UI strings must be in Hebrew. Keep English technical terms when they are industry-standard (APDEX, MTTR, SLO, p95, latency, etc.) but add Hebrew hover tooltips with explanations.

Localization file: `lib/l10n/performance_observatory_he.dart`

Example:
```dart
const Map<String, String> performanceObservatoryHe = {
  'title': 'Performance Observatory',
  'subtitle': 'v5.0 SCALE-READY · מוכן ל-10M משתמשים',
  'health_score': 'ציון בריאות',
  'apdex_tooltip': 'ציון בין 0 ל-1 שמודד כמה המשתמשים מרוצים מזמני התגובה',
  'mttr_tooltip': 'זמן ממוצע לתיקון תקלה מרגע זיהוי (Mean Time To Recovery)',
  // ... ~80 more keys
};
```

---

## 🎯 Implementation Order (Do in this order!)

### Phase 1: Infrastructure (DO THIS FIRST - critical for scale!)
1. Create BigQuery dataset `anyskill_observability`
2. Create BigQuery tables (see `02_CLOUD_FUNCTIONS.md`)
3. Setup Pub/Sub topics for metrics streaming
4. Deploy Cloud Function `aggregateMetricsToBigQuery`
5. Setup Redis Memorystore instance (Basic tier 1GB)
6. Add Firestore composite indexes for sharded collections
7. Create Firestore shards: experts_shard_0 through experts_shard_9

### Phase 2: Cloud Functions (16 functions)
Deploy all Cloud Functions in `/functions/src/performance/` directory. Test each one with curl before moving on. See `02_CLOUD_FUNCTIONS.md` for full code.

### Phase 3: Frontend Widgets (17 widgets)
Build in this order (dependencies first):
1. `performance_observatory_service.dart` (service layer)
2. `nova_ai_copilot_service.dart`
3. Small widgets: `scale_readiness_widget.dart`, `golden_signals_widget.dart`, `cost_projection_widget.dart`
4. Complex widgets: `ai_copilot_nova_widget.dart`, `business_impact_widget.dart`, `ai_agents_swarm_widget.dart`
5. Super complex: `incident_war_room_widget.dart`, `impact_simulator_widget.dart`
6. Everything else
7. Final assembly in `performance_tab.dart`

### Phase 4: Testing & Polish
1. Hebrew RTL check across all widgets
2. `flutter analyze` must return 0 issues
3. Test with low-data scenarios (no errors, empty states)
4. Test with high-data scenarios (500+ errors, 10+ active incidents)
5. Responsive design check (mobile + tablet + desktop)
6. Accessibility check (semantic labels, screen reader)

---

## 🧠 AI Agents Behavior Spec

### 5 AI Agents (all powered by Gemini 2.5 Pro):

**🔍 Detective Agent**
- Role: Investigates root causes of issues
- Triggers: Any P1/P2 incident
- Outputs: Confidence score 0-100%, hypothesis list, evidence trails
- Max 147 actions/day

**🔧 Healer Agent**
- Role: Auto-fixes common issues
- Requires user approval in "Supervised" mode, acts alone in "Autonomous"
- Capable actions: Add Firestore index, restart CF, clear cache, rollback deploy, rate limit
- Max 23 fixes/day (safety limit)

**🔮 Oracle Agent**
- Role: Predicts future issues 2-24h ahead
- Methods: ML anomaly detection on time series, pattern matching
- Outputs: Risk %, estimated time to issue, recommended actions
- Monitors 5+ predictions simultaneously

**🛡️ Guardian Agent**
- Role: Security anomaly detection
- Monitors: Login attempts, API abuse, unusual traffic patterns
- Capable of: IP blocking (after approval), rate limit adjustment, session revocation

**📝 Chronicler Agent**
- Role: Writes blameless post-mortems automatically
- Triggers: After every resolved P1/P2 incident
- Structure: TL;DR → Timeline → Root Cause → Business Impact → Lessons → Action Items
- Uses: Gemini 2.5 Pro with custom system prompt

### Autonomous Mode Levels:
1. **Supervised** (default) — All agents propose, user approves each action
2. **Recommend** — Agents show recommendations as priority list, user picks
3. **Autonomous** — Agents act automatically within safety limits (only for Tier 1-2 issues)

---

## ✅ Acceptance Criteria (must pass ALL before merging)

### Functionality
- [ ] All 40 sections render correctly
- [ ] Nova AI Copilot responds in Hebrew within 2 seconds for common questions
- [ ] Business Impact widget shows real-time revenue/min calculation (not just demo data)
- [ ] 5 AI Agents have independent status and update independently
- [ ] Incident War Room activates automatically on P1 events
- [ ] Cost Projection Calculator reflects real Firebase pricing as of today
- [ ] Impact Simulator runs Gemini predictions and returns results in under 10s
- [ ] Chaos Engineering tests can be executed and tracked
- [ ] Feature Flags can toggle percentage rollouts live

### Scale
- [ ] Dashboard reads primarily from BigQuery (NOT Firestore for metrics)
- [ ] Redis cache layer is active for hot data (user sessions, top searches, recent chats)
- [ ] Firestore is sharded for `experts` collection (experts_shard_0 through _9)
- [ ] Cloud Functions have `minInstances: 2` for hot functions
- [ ] Multi-region deployment active for IL + US + EU (AU optional)
- [ ] Dashboard page load time < 500ms at 1M DAU simulated load
- [ ] Cost per user per month < $0.05 at 1M DAU, < $0.02 at 10M DAU

### Design
- [ ] Dark premium glassmorphism theme throughout
- [ ] All text in Hebrew RTL with English technical terms allowed
- [ ] 5 ambient orbs present on main page
- [ ] Smooth animations on data flow diagrams
- [ ] Mobile responsive (breakpoints: 768px, 1024px)
- [ ] `flutter analyze`: 0 issues
- [ ] Matches visual mockup quality (see V5 mockup)

### AI Quality
- [ ] Nova explains APDEX/MTTR/SLO/p95 correctly in Hebrew
- [ ] Root Cause Analysis has confidence score
- [ ] Blameless Post-Mortem AI draft is 70%+ complete before user edits
- [ ] Anomaly detection catches >95% of traffic spikes
- [ ] Impact Simulator predictions match reality within 20% on retrospective tests

---

## 🚀 Getting Started Instructions for Claude Code

1. **Read this entire file first** (you're doing that now)
2. **Read `02_CLOUD_FUNCTIONS.md`** (all 16 Cloud Functions with full TypeScript code)
3. **Read `03_FRONTEND_WIDGETS.md`** (all 17 Flutter widgets with Dart code)
4. **Read `04_INFRASTRUCTURE.md`** (BigQuery schema, Pub/Sub, Redis, Firestore sharding)
5. **Read `05_LOCALIZATION.md`** (Hebrew strings)
6. **Follow Phase 1 → 2 → 3 → 4 in order**
7. **Commit after each phase with descriptive messages**
8. **Test extensively before moving to next phase**

---

## 📌 Critical Notes

- **HYBRID AI**: Use Gemini 2.5 Pro for all Performance Observatory AI (Nova + 5 agents). Do NOT use Claude here — per §12c and §31 of CLAUDE.md, the Monetization tab and Performance are Gemini, while the AI CEO is Claude.
- **HEBREW FIRST**: All UI strings in Hebrew. Document comments in English for code maintenance.
- **NO Firestore for metrics**: This is the #1 reason the current system doesn't scale. Metrics MUST go through Pub/Sub → BigQuery. The dashboard reads from BigQuery only.
- **Consent for autonomous actions**: Even in "Autonomous" mode, log every action and allow user to undo within 24h.
- **Cost tracking**: Every Cloud Function should log its execution cost to BigQuery `costs_per_function` table.

---

## 🎁 Bonus: Voice Commands

When user taps 🎤 button in header:
- Recording starts (use `speech_to_text` package)
- Transcribed query sent to Nova
- Response shown in chat AND spoken back via `flutter_tts`

Supported commands:
- "כמה הפסדתי היום?" → opens Business Impact widget
- "מה קורה עכשיו?" → shows active incidents + health score
- "תתקן את זה" → executes Healer agent's top recommendation
- "תחזית לשבוע הבא" → opens Oracle agent predictions

---

**Ready? Go build something amazing! 🚀**

Next: Read `02_CLOUD_FUNCTIONS.md` for Cloud Function code.
