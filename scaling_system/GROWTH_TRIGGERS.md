# 🚦 GROWTH TRIGGERS - When to Activate Each Milestone

**This file defines EXACTLY when each scaling milestone should activate.**  
**Claude Code uses this to automatically detect upgrade needs.**

---

## 🎯 TRIGGER DEFINITIONS

### 🟢 Milestone 1: Option A (Pre-launch)
**Status:** ACTIVE NOW  
**Duration:** 1-2 Claude Code sessions  
**Cost:** $5/month total  

**Triggers to activate:** NONE - this is the starting point.

**What this includes:**
- Premium dashboard UI
- Nova AI Chat (Gemini Flash Lite)
- Business metrics from existing collections
- Scale Readiness Score (static)
- 4 Golden Signals
- Cost Projection Calculator
- **⚠️ Scale Alert System** (auto-detects next triggers)

---

### 🟡 Milestone 2: Redis Cache Layer
**Activate when ANY of:**

1. **DAU trigger:** `daily_active_users > 10,000`
   - *Why:* At this scale, repeat Firestore reads become expensive
   - *Signal:* Dashboard shows "🟡 Redis recommended"

2. **Cost trigger:** `firestore_monthly_cost_usd > 200`
   - *Why:* Redis saves 60-80% on repeat reads
   - *Signal:* Dashboard shows "💸 Firebase cost rising"

3. **Performance trigger:** `api_p95_latency_ms > 800`
   - *Why:* Redis returns data in <5ms vs Firestore ~200ms
   - *Signal:* Dashboard shows "⚡ Slow API responses"

**Claude Code Action:**
```markdown
If any trigger = true:
  → Read 02_REDIS_SETUP.md
  → Ask user: "Your metrics indicate it's time for Redis. Activate?"
  → If approved → Execute
  → Update CURRENT_STATUS.md
```

**Cost impact:** +$25-50/month  
**Time to implement:** 1 Claude Code session  
**Benefit:** 60-80% reduction in Firestore reads  

---

### 🟠 Milestone 3: BigQuery Analytics Pipeline
**Activate when ANY of:**

1. **DAU trigger:** `daily_active_users > 50,000`
   - *Why:* Dashboard reads from Firestore become bottleneck
   - *Signal:* Dashboard shows "🟠 BigQuery recommended"

2. **Performance trigger:** `dashboard_load_time_ms > 2,000`
   - *Why:* Aggregation queries on Firestore are slow
   - *Signal:* Dashboard shows "🐌 Dashboard is slow"

3. **Read volume trigger:** `firestore_reads_per_day > 10,000,000`
   - *Why:* Firestore pricing becomes prohibitive
   - *Signal:* Dashboard shows "📊 High read volume detected"

**Claude Code Action:**
```markdown
If any trigger = true AND Milestone 2 is complete:
  → Read 03_BIGQUERY_PIPELINE.md
  → Ask user: "Time for BigQuery Pipeline. Estimated $30-100/mo."
  → If approved → Execute (takes 3-4 sessions)
  → Update CURRENT_STATUS.md
```

**Cost impact:** +$30-100/month  
**Time to implement:** 3-4 Claude Code sessions  
**Benefit:** Dashboard loads in <100ms regardless of scale  

---

### 🔴 Milestone 4: Sharding + Multi-Region
**Activate when ANY of:**

1. **DAU trigger:** `daily_active_users > 500,000`
   - *Why:* Single collection approaches write limits
   - *Signal:* Dashboard shows "🔴 Sharding critical"

2. **Write throttling trigger:** `firestore_peak_writes_per_sec > 8,000`
   - *Why:* Firestore limit is 10K/sec per collection
   - *Signal:* Dashboard shows "⚠️ Approaching write limit"

3. **Geographic trigger:** `users_outside_israel_percent > 20`
   - *Why:* Latency for international users is poor
   - *Signal:* Dashboard shows "🌍 International users experiencing lag"

**Claude Code Action:**
```markdown
If any trigger = true AND Milestones 2-3 complete:
  → Read 04_SHARDING_MULTIREGION.md
  → ⚠️ Major migration - requires planning
  → Ask user: "Major infrastructure upgrade needed. Plan migration?"
  → If approved → Execute (takes 5-6 sessions)
  → Update CURRENT_STATUS.md
```

**Cost impact:** +$300-1,000/month  
**Time to implement:** 5-6 Claude Code sessions  
**Benefit:** Handle millions of concurrent users globally  

---

### 🟣 Milestone 5: Enterprise V5 (AI Agents + Chaos Engineering)
**Activate when ALL of:**

1. **DAU trigger:** `daily_active_users > 5,000,000`
2. **Maturity trigger:** All previous milestones stable for 3+ months
3. **Team trigger:** You have a dedicated DevOps/SRE team

**Why wait?**
- 5 AI Agents require advanced infrastructure
- Chaos Engineering on production needs careful planning
- Cost/benefit only makes sense at massive scale

**Claude Code Action:**
```markdown
If DAU > 5M AND all previous milestones done:
  → Read 05_ENTERPRISE_V5.md
  → Ask user: "Ready for enterprise features? Estimated +$1000/mo."
  → Major undertaking - review carefully
  → Execute over 10+ sessions
```

**Cost impact:** +$1,000-5,000/month  
**Time to implement:** 10+ Claude Code sessions  
**Benefit:** Autonomous operations, predictive scaling, chaos resilience  

---

## 📊 TRIGGER DETECTION ALGORITHM

Claude Code should run this check on every session:

```typescript
function checkTriggers(status: CurrentStatus): TriggeredMilestones {
  const triggered = [];
  
  // Milestone 2 - Redis
  if (status.active_milestone === 1) {
    if (status.daily_active_users > 10000) {
      triggered.push({ milestone: 2, reason: "DAU exceeded 10K" });
    }
    if (status.firestore_monthly_cost_usd > 200) {
      triggered.push({ milestone: 2, reason: "Firestore cost > $200" });
    }
    if (status.api_p95_latency_ms > 800) {
      triggered.push({ milestone: 2, reason: "API latency > 800ms" });
    }
  }
  
  // Milestone 3 - BigQuery
  if (status.active_milestone === 2) {
    if (status.daily_active_users > 50000) {
      triggered.push({ milestone: 3, reason: "DAU exceeded 50K" });
    }
    if (status.dashboard_load_time_ms > 2000) {
      triggered.push({ milestone: 3, reason: "Dashboard slow" });
    }
    if (status.firestore_reads_per_day > 10000000) {
      triggered.push({ milestone: 3, reason: "High read volume" });
    }
  }
  
  // Milestone 4 - Sharding
  if (status.active_milestone === 3) {
    if (status.daily_active_users > 500000) {
      triggered.push({ milestone: 4, reason: "DAU exceeded 500K" });
    }
    if (status.firestore_peak_writes_per_sec > 8000) {
      triggered.push({ milestone: 4, reason: "Write throttling risk" });
    }
  }
  
  // Milestone 5 - Enterprise
  if (status.active_milestone === 4) {
    if (status.daily_active_users > 5000000) {
      triggered.push({ milestone: 5, reason: "Enterprise scale reached" });
    }
  }
  
  return triggered;
}
```

---

## 🎁 BONUS: PREDICTIVE TRIGGERS

Use growth rate to PREDICT when triggers will fire:

```typescript
function predictTriggerDate(
  currentDAU: number, 
  growthRate: number, // users/day
  targetDAU: number
): Date {
  const daysUntil = (targetDAU - currentDAU) / growthRate;
  const predictedDate = new Date();
  predictedDate.setDate(predictedDate.getDate() + daysUntil);
  return predictedDate;
}

// Example:
// Current: 4,000 DAU
// Growth: 50 users/day
// Target: 10,000 (Milestone 2 trigger)
// Predicted: (10000 - 4000) / 50 = 120 days ≈ 4 months
```

This allows Claude Code to say:
> "Based on your growth rate, you'll hit Milestone 2 in approximately 4 months. Want to prepare now?"

---

## 🚨 EMERGENCY TRIGGERS (Skip milestone order)

In rare cases, skip ahead if:

1. **Viral spike:** DAU jumped from 5K → 500K in a week
   - Action: Skip to Milestone 4 immediately
   - Risk: High, but better than crashes

2. **Outage:** Firestore write limit hit constantly
   - Action: Emergency sharding (Milestone 4)
   - Deploy hot-fix first, then proper migration

3. **Investor demo in 1 week, need to show enterprise features:**
   - Action: Skip to Milestone 5 cosmetic features only
   - Don't activate real autonomous agents

**Rule:** Emergency only. Normal flow = sequential.

---

## 📝 TRIGGER HISTORY LOG

*Claude Code appends here when triggers fire:*

```markdown
## 2026-XX-XX - Trigger Fired
Milestone: X
Reason: <which trigger>
Action taken: <what Claude Code did>
User approval: yes/no
```

---

**Version:** 1.0  
**Last updated:** 2026-04-18
