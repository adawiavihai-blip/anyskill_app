# 🎛️ AnySkill Scaling System - Master Control

**קובץ זה הוא "המוח" של מערכת הסקיילינג. Claude Code קורא אותו קודם.**

---

## 🤖 FOR CLAUDE CODE: READ THIS FIRST!

**You are operating in AnySkill's scaling system. Your job:**

1. ✅ Read the `CURRENT_STATUS.md` file to know where the app stands NOW
2. ✅ Check which milestone is active
3. ✅ Execute ONLY the prompt file matching current milestone
4. ❌ DO NOT skip ahead or mix milestones
5. ✅ After completion, update `CURRENT_STATUS.md`

---

## 📂 FOLDER STRUCTURE

```
anyskill_scaling_system/
├── 00_MASTER_CONTROL.md           ← YOU ARE HERE
├── CURRENT_STATUS.md              ← State of the app (read this!)
├── GROWTH_TRIGGERS.md             ← When to activate each milestone
├── 01_OPTION_A_PROMPT.md          ← Milestone 1 (BUILD NOW)
├── 02_REDIS_SETUP.md              ← Milestone 2 (activate at 10K DAU)
├── 03_BIGQUERY_PIPELINE.md        ← Milestone 3 (activate at 50K DAU)
├── 04_SHARDING_MULTIREGION.md     ← Milestone 4 (activate at 500K DAU)
└── 05_ENTERPRISE_V5.md            ← Milestone 5 (activate at 5M DAU)
```

---

## 🎯 DECISION TREE FOR CLAUDE CODE

```
START
  │
  ├─ Read CURRENT_STATUS.md
  │
  ├─ Check "active_milestone" field:
  │     │
  │     ├─ If "1" → Execute 01_OPTION_A_PROMPT.md
  │     ├─ If "2" → Execute 02_REDIS_SETUP.md
  │     ├─ If "3" → Execute 03_BIGQUERY_PIPELINE.md
  │     ├─ If "4" → Execute 04_SHARDING_MULTIREGION.md
  │     └─ If "5" → Execute 05_ENTERPRISE_V5.md
  │
  ├─ Check "triggers" in CURRENT_STATUS.md:
  │     │
  │     ├─ If any trigger matches → Suggest user to upgrade milestone
  │     └─ If not → Continue with current milestone
  │
  └─ After work complete:
        └─ Update CURRENT_STATUS.md with new state
```

---

## 🚨 AUTOMATIC MILESTONE DETECTION

When Claude Code opens this folder, it should:

### 1. Read latest metrics from the Performance Dashboard:
```typescript
// Read from admin dashboard's performance_metrics collection
const metrics = await firestore.collection('performance_metrics').doc('current').get();
const dau = metrics.data().activeUsersDaily;
const firestoreCost = metrics.data().firestoreMonthlyCost;
const writesPerSec = metrics.data().peakWritesPerSec;
```

### 2. Compare against triggers in `GROWTH_TRIGGERS.md`

### 3. Report to user:
```
🎯 Current milestone: 1 (Option A - Pre-launch)
📊 Current DAU: 4,500
⚠️  Next milestone triggers at: 10,000 DAU

Would you like me to:
a) Continue with current milestone work
b) Preview next milestone setup
c) Show status summary
```

---

## 🔄 HOW TO PROGRESS BETWEEN MILESTONES

### When user says "the dashboard says I need to scale":

1. **Verify the trigger is real:**
```bash
# Check actual Firebase usage
firebase firestore:indexes
firebase firestore:databases:list
```

2. **Run the appropriate milestone prompt:**
```
User: "I reached 10K DAU - upgrade me to Redis"
Claude Code: 
  → Reads 02_REDIS_SETUP.md
  → Executes all steps in order
  → Updates CURRENT_STATUS.md to milestone 2
  → Reports completion
```

3. **NEVER skip milestones.** If user has 50K DAU but hasn't done Redis:
```
❌ Don't jump to BigQuery
✅ First do Redis (02), then BigQuery (03)
```

---

## 🎨 CONSISTENT RULES (APPLY TO ALL MILESTONES)

These rules apply regardless of which milestone is active:

### Code Quality:
- ✅ `flutter analyze`: 0 issues
- ✅ All Hebrew RTL
- ✅ No breaking changes to existing features
- ✅ Backward compatible

### AI Architecture (NEVER CHANGE):
- 🧠 Claude Opus/Sonnet → CEO tab only
- ⚡ Gemini 2.5 Flash Lite → Performance, Monetization, CSMs

### Design System (PRESERVE):
- Dark glassmorphism theme
- Business palette: #EC4899, #6366F1, #A855F7
- Heebo font
- Directionality.rtl wrapping

### Database Rules:
- ✅ Use Firebase Firestore as source of truth
- ✅ Add caching layers (Redis/BigQuery) when milestones require
- ❌ Never replace Firestore - only supplement it

---

## 📢 COMMUNICATION PROTOCOL

When Claude Code completes work for any milestone:

### 1. Update `CURRENT_STATUS.md`:
```yaml
active_milestone: 1 (or 2, 3, 4, 5)
completed_date: YYYY-MM-DD
next_milestone_preview: <name of next>
estimated_next_trigger_date: <based on growth rate>
```

### 2. Show user a summary:
```
✅ Completed: Milestone X - <name>
📊 What changed:
   - <feature 1>
   - <feature 2>
📈 Next milestone: Y
🚨 Watch for: <trigger conditions>
📍 Read: <next file name> when triggered
```

### 3. Create a PR summary:
```bash
git commit -m "feat: complete milestone X - <name>

- <change 1>
- <change 2>

Next milestone: Y (activate when <trigger>)
See: anyskill_scaling_system/<file>"
```

---

## 🛡️ SAFETY RULES

### Before executing ANY milestone:

1. **Backup first:**
```bash
# Before major changes:
git checkout -b "milestone-X-backup"
git push origin "milestone-X-backup"
```

2. **Test in staging:**
```bash
# Deploy to staging environment first
firebase use staging
firebase deploy
# Test thoroughly
firebase use production
```

3. **Monitor after deployment:**
- Watch error logs for 24 hours
- Check performance metrics
- Rollback if issues

### If something breaks:
```bash
# Immediate rollback
git revert HEAD
firebase deploy
```

---

## 🎁 FOR USER (AVIHAI)

### When you want to check status:
```
Claude, read anyskill_scaling_system/CURRENT_STATUS.md 
and tell me what milestone I'm in
```

### When you want to upgrade:
```
Claude, the dashboard is showing I should upgrade.
Read anyskill_scaling_system/00_MASTER_CONTROL.md 
and execute the next milestone.
```

### When you want preview:
```
Claude, show me what milestone 3 would do 
without executing it yet.
```

---

## 📝 VERSION

**Version:** 1.0  
**Created:** 2026-04-18  
**Author:** Avihai + Claude  
**Purpose:** Staged scaling for AnySkill from 4K to 10M DAU  

**This is the master file. Update only when adding new milestones.**
