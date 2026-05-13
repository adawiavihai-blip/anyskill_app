# 🤖 CLAUDE.md - Auto-Instructions for Claude Code

> **This file is automatically read by Claude Code at the start of every session.**  
> **It tells Claude Code how to behave with the scaling system.**

---

## ⚡ CRITICAL: READ ON EVERY SESSION

When starting any session in this project, Claude Code MUST:

### 1. Check the Scaling System

```bash
# Check if scaling system exists
if [ -d "anyskill_scaling_system" ]; then
  # Read current status
  cat anyskill_scaling_system/CURRENT_STATUS.md
fi
```

### 2. Verify Current Milestone

Read `CURRENT_STATUS.md` and check:
- `active_milestone: X`
- `status: completed | in_progress | not_started`
- Any triggered warnings

### 3. Check for Triggered Upgrades

If the user's request relates to the Performance tab OR mentions scaling/performance/slow/cost:

1. Check `CURRENT_STATUS.md` for trigger flags
2. If any trigger is `true`, alert user:
   ```
   🚨 I noticed your metrics suggest upgrading to Milestone X.
   Would you like me to execute [file_name].md?
   ```

---

## 🎯 MILESTONE-BASED BEHAVIOR

### If user asks to build/improve Performance Tab:

**Before writing ANY code, Claude Code MUST:**

1. Check which milestone is active:
   ```
   active_milestone: 1 → Use 01_OPTION_A_PROMPT.md ONLY
   active_milestone: 2 → Use 02_REDIS_SETUP.md ONLY
   active_milestone: 3 → Use 03_BIGQUERY_PIPELINE.md ONLY
   active_milestone: 4 → Use 04_SHARDING_MULTIREGION.md ONLY
   active_milestone: 5 → Use 05_ENTERPRISE_V5.md ONLY
   ```

2. NEVER mix features from different milestones.

3. NEVER add features from higher milestones even if requested:
   ```
   User: "Add AI agents to the performance tab"
   
   Claude Code check:
     active_milestone: 1
     AI agents are in milestone 5
   
   Response: "AI Agents are part of Milestone 5, which activates at 5M DAU.
   You're currently in Milestone 1 (4K DAU). 
   
   Instead, I can add the Scale Alert System from Milestone 1,
   which will notify you automatically when you reach Milestone 5 triggers.
   
   Want to proceed with that?"
   ```

---

## 🚨 TRIGGER DETECTION ALGORITHM

On every session, run this mental check:

```python
def check_and_alert(status):
    if status.active_milestone == 1:
        if status.daily_active_users > 10000:
            alert("Milestone 2 (Redis) triggered by DAU!")
        if status.firestore_monthly_cost_usd > 200:
            alert("Milestone 2 (Redis) triggered by cost!")
    
    if status.active_milestone == 2:
        if status.daily_active_users > 50000:
            alert("Milestone 3 (BigQuery) triggered by DAU!")
        if status.dashboard_load_time_ms > 2000:
            alert("Milestone 3 (BigQuery) triggered by performance!")
    
    if status.active_milestone == 3:
        if status.daily_active_users > 500000:
            alert("Milestone 4 (Sharding) triggered!")
        if status.firestore_peak_writes_per_sec > 8000:
            alert("Milestone 4 (Sharding) urgent - approaching limits!")
    
    if status.active_milestone == 4:
        if status.daily_active_users > 5000000:
            alert("Milestone 5 (Enterprise) available!")
```

---

## 📋 STANDARD RESPONSE PATTERNS

### Pattern 1: User asks vague question about performance

```
User: "The app is slow"

Claude Code:
1. Check CURRENT_STATUS.md
2. Check triggers
3. Respond:

"Let me check your scaling status...

📊 Current state:
- Milestone: 1 (Option A)
- DAU: 4,000
- Dashboard load: 800ms
- Firestore cost: $25/mo

🔍 Analysis:
No Milestone triggers are active. The slowness might be:
1. Specific queries in your code
2. UI rendering issues
3. Network latency

Can you share more details about which screen is slow?"
```

### Pattern 2: User asks for new feature

```
User: "I want AI agents that handle problems automatically"

Claude Code:
1. Check if feature exists in current milestone
2. If not, identify which milestone has it
3. Respond:

"That feature (AI Agents Swarm) is part of Milestone 5 (Enterprise V5).

Current milestone: 1
Required milestone: 5 (triggers at 5M DAU)
Your current DAU: 4K

Options:
a) Wait until 5M DAU (estimated: 5+ years at current growth)
b) Add a simpler version: Nova AI Chat (Milestone 1) - responds to queries
c) Override and build minimal version now (not recommended)

What would you like to do?"
```

### Pattern 3: User reports metrics exceeded trigger

```
User: "I now have 15,000 daily users, dashboard is slow"

Claude Code:
1. Detect trigger (DAU > 10K)
2. Respond:

"🚨 Milestone 2 (Redis Cache) is now required!

Your metrics:
- DAU: 15,000 (trigger: >10K ✓)
- Dashboard: slow (consistent with Redis benefit)

Let me execute Milestone 2:
1. Read /anyskill_scaling_system/02_REDIS_SETUP.md
2. Tell you what user actions are needed
3. Implement the code
4. Update CURRENT_STATUS.md

Approximate time: 4-6 hours
Approximate cost: +$25-50/month

Shall I proceed?"
```

---

## ❌ FORBIDDEN ACTIONS

Claude Code MUST NOT:

### 1. Skip Milestones
```
❌ User has Milestone 1, wants Milestone 3
✅ Execute Milestone 2 first
```

### 2. Mix Infrastructure Layers
```
❌ Milestone 1 with BigQuery queries
✅ Milestone 1 uses Firestore only
```

### 3. Change AI Architecture
```
❌ Use Claude for Performance tab
✅ Use Gemini 2.5 Flash Lite for Performance
✅ Use Claude for CEO tab only
```

### 4. Skip Hebrew RTL
```
❌ English-only UI or LTR layout
✅ All Directionality.rtl, all Hebrew strings
```

### 5. Create Infrastructure Before Milestone
```
❌ Milestone 1 + set up Redis
✅ Milestone 1 + Scale Alert warns about Redis for later
```

---

## ✅ REQUIRED ACTIONS

Claude Code MUST:

### 1. Update CURRENT_STATUS.md after each milestone
```markdown
After completing any milestone, append to CURRENT_STATUS.md:

## YYYY-MM-DD - Milestone X Completed
- What was built
- What changed
- Next milestone name and trigger
```

### 2. Create git branch before major changes
```bash
git checkout -b "milestone-X-implementation"
```

### 3. Run flutter analyze after every change
```bash
flutter analyze
# Must show: 0 issues
```

### 4. Test in Hebrew RTL
```dart
// Always wrap in:
Directionality(
  textDirection: TextDirection.rtl,
  child: YourWidget(),
)
```

### 5. Respect the AI architecture
```
Performance/Monetization/CSMs → Gemini 2.5 Flash Lite
CEO strategic reasoning → Claude Opus/Sonnet
```

---

## 📞 COMMUNICATION TEMPLATES

### Template: Milestone ready to execute
```
🎯 Ready to execute Milestone X: <n>

What I'll do:
1. <step 1>
2. <step 2>
3. <step 3>

What you'll need to do:
1. <user action 1>
2. <user action 2>

Estimated time: X hours
Estimated cost impact: +$X/month
Risk: Low/Medium/High

Shall I proceed?
```

### Template: Milestone completed
```
✅ Milestone X completed!

What was built:
- <feature 1>
- <feature 2>
- <feature 3>

What changed:
- CURRENT_STATUS.md updated
- <file changes>

Your new capabilities:
- <capability 1>
- <capability 2>

Next steps:
- Watch for: <trigger conditions>
- When triggered: Execute Milestone X+1
- Estimated trigger date: YYYY-MM
```

### Template: Trigger detected
```
🚨 Scaling trigger detected!

Current state:
- <metric 1>: <value> (trigger was <threshold>)
- <metric 2>: <value>

Recommended action:
- Execute Milestone X
- File: <file_name>.md
- Estimated time: X hours
- Cost impact: +$X/month

Options:
a) Execute now
b) Schedule for this weekend
c) Override and wait (not recommended)
d) Show me what it would do first
```

---

## 🔄 SESSION START CHECKLIST

At the start of EVERY Claude Code session, run this mental checklist:

```
[ ] Read CLAUDE.md (this file)
[ ] Read CURRENT_STATUS.md
[ ] Note active_milestone
[ ] Check all triggers
[ ] If triggers active → alert user
[ ] If user asks for feature → verify milestone compatibility
[ ] Never mix milestones
[ ] Always update CURRENT_STATUS.md after work
```

---

## 📝 EXAMPLE SESSION

```
User: "Claude, let's work on the app"

Claude Code: *reads CLAUDE.md and CURRENT_STATUS.md*

"Good morning! 👋

📊 Your status:
- Milestone: 1 (Option A) - In Progress
- DAU: 4,100 (+100 since yesterday)
- All systems: Green 🟢
- No triggers active

🎯 Available actions:
1. Complete Milestone 1 (Performance Dashboard)
2. Work on AnyTasks feature
3. Continue Handyman CSM optimizations
4. Something else

What would you like to do today?"
```

---

## 🎯 GOLDEN RULES

1. **The scaling system is authoritative.** Don't deviate.
2. **User growth dictates features.** Not ambition.
3. **Alerts are real.** Don't ignore them.
4. **Milestones are sequential.** No skipping.
5. **Update CURRENT_STATUS.md religiously.**

---

**Version:** 1.0  
**Last updated:** 2026-04-18  
**Maintainer:** Avihai + Claude

**This file is the brain of the system. Keep it updated.**
