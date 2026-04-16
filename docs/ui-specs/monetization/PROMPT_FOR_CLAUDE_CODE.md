# 🎯 שדרוג מלא של טאב מוניטיזציה — AnySkill Admin Panel

> **קובץ זה מיועד ל-Claude Code.**
> קרא את כל הקובץ מתחילתו ועד סופו לפני שאתה מתחיל לכתוב קוד.
> ב-repo יש קובץ נוסף בשם `monetization_mockup.html` — פתח אותו בדפדפן כדי לראות בדיוק את התוצאה הסופית הרצויה.

---

## 📋 רקע ותפקיד

אתה הולך לבצע שדרוג מלא של הקובץ `lib/screens/admin_monetization_tab.dart` באפליקציית AnySkill.

הטאב הנוכחי הוא פונקציונלי אבל שטוח — 6 סקציות ללא היררכיה, ללא שליטה פר-ספק, ללא תובנות AI, וללא יכולות מתקדמות שדורשות שוק דו-צדדי ברמה של Uber/Airbnb/Stripe.

המטרה: להפוך את הטאב הזה ל**מרכז הבקרה הפיננסי-אסטרטגי** של הפלטפורמה — עם שכבות שליטה בעמלות (גלובלי → קטגוריה → ספק), תובנות AI חיות, סימולטור השפעה, זיהוי anomalies, וכל הכלים שמנהל מרקטפלייס מודרני צריך.

---

## 🏗️ ארכיטקטורה — 3 שכבות עמלה (היררכיה)

החוק: **הספציפי דורס את הכללי**.

```
┌─────────────────────────────────────────────────┐
│  שכבה 1: עמלה גלובלית (ברירת מחדל)           │
│  → admin/admin/settings/settings.feePercentage │
└─────────────────────────────────────────────────┘
              ↓ דורסת ↓
┌─────────────────────────────────────────────────┐
│  שכבה 2: עמלה לפי קטגוריה                       │
│  → category_commissions/{categoryId}            │
│    { percentage, updatedAt, updatedBy }         │
└─────────────────────────────────────────────────┘
              ↓ דורסת ↓
┌─────────────────────────────────────────────────┐
│  שכבה 3: עמלה פרטנית לספק                       │
│  → users/{uid}.customCommission                 │
│    { percentage, setAt, setBy, reason, notes }  │
└─────────────────────────────────────────────────┘
```

### פונקציית חישוב עמלה אפקטיבית

צור **Cloud Function חדשה** ב-`functions/index.js` בשם `getEffectiveCommission`:

```javascript
/**
 * מחזירה את העמלה האפקטיבית לספק מסוים.
 * סדר עדיפות: custom → category → global
 */
async function getEffectiveCommission(userId, categoryId) {
  const db = admin.firestore();

  // שכבה 3: עמלה פרטנית
  const userDoc = await db.collection('users').doc(userId).get();
  const custom = userDoc.data()?.customCommission;
  if (custom?.percentage !== undefined && custom?.percentage !== null) {
    return {
      percentage: custom.percentage,
      source: 'custom',
      setAt: custom.setAt,
    };
  }

  // שכבה 2: עמלה לפי קטגוריה
  if (categoryId) {
    const catDoc = await db.collection('category_commissions').doc(categoryId).get();
    if (catDoc.exists) {
      return {
        percentage: catDoc.data().percentage,
        source: 'category',
        categoryId,
      };
    }
  }

  // שכבה 1: גלובלית
  const settingsDoc = await db.collection('admin').doc('admin').collection('settings').doc('settings').get();
  return {
    percentage: (settingsDoc.data()?.feePercentage ?? 0.10) * 100,
    source: 'global',
  };
}

exports.getEffectiveCommission = getEffectiveCommission;
```

**חשוב**: שנה את `escrow_service.dart:41-54` כך שיקרא לפונקציה הזו במקום ל-`settings.feePercentage` ישירות.

---

## 🎨 מבנה הדף — 9 סקציות

הטאב החדש מורכב מ-9 סקציות, בסדר הזה מלמעלה למטה. כל סקציה מפורטת למטה עם שדות ספציפיים.

### סקציה 1: Top Bar + Command Palette + Save

```
[🟡 אייקון] מוניטיזציה · LIVE        [🔍 חפש כל שאלה... ⌘K]  [שמור שינויים]
            עודכן לפני 3 שניות
```

**רכיבים:**
- כותרת "מוניטיזציה" + badge "LIVE" ירוק
- טקסט עדכון חי: `"עודכן לפני X שניות"` (משתמש ב-`StreamBuilder` על `platform_earnings` כדי לעדכן בכל write)
- שדה חיפוש/שאל-AI — ב-Phase 1 רק UI, ב-Phase 2 מחובר ל-Gemini (ראה סקציה 11)
- כפתור "שמור שינויים" שחור בלבד — מופיע רק אם יש שינויים לא שמורים (state: `_hasUnsavedChanges`)

### סקציה 2: AI Insight Banner (Gemini)

באנר סגול רחב שמציג תובנה מה-AI CEO:

```dart
Container(
  decoration: BoxDecoration(
    color: Color(0xFFEEEDFE),
    border: Border.all(color: Color(0xFFAFA9EC), width: 0.5),
    borderRadius: BorderRadius.circular(12),
  ),
  padding: EdgeInsets.all(14),
  child: Row(
    children: [
      // אייקון עגול סגול כהה
      // כותרת "תובנת AI CEO" + badge "Gemini 2.5"
      // טקסט תובנה דינמי (למשל: "קטגוריית אימון אישי מציגה churn של 23%...")
      // כפתורים: "הפעל" (סגול כהה) + "דחה" (outline)
    ],
  ),
);
```

**לוגיקה:**
- צור Cloud Function חדשה בשם `generateMonetizationInsight` שרצה כל 6 שעות
- היא מנתחת: GMV לפי קטגוריה, churn rate, ספקים פעילים, ומחזירה המלצה אחת עם:
  - `title` (למשל: "הזדמנות: קטגוריית אימון אישי")
  - `recommendation` (פעולה מוצעת)
  - `expectedImpact` (משמעות מספרית: "+₪890/חודש, שימור 5 ספקים")
  - `actionType` (enum: `adjust_category_commission`, `promote_provider`, `reduce_provider_commission`, וכו')
  - `actionParams` (JSON לפעולה)
- שמור ב-Firestore: `ai_insights/monetization/latest`
- הבאנר מציג את התובנה האחרונה. לחיצה על "הפעל" מבצעת את הפעולה אוטומטית עם confirmation dialog.

### סקציה 3: 4 KPIs עליונים

ארבעה כרטיסים בשורה עם sparklines.

| KPI | חישוב | ויזואל נוסף |
|-----|-------|--------------|
| **עמלות החודש** | `SUM(platform_earnings.amount) WHERE timestamp >= monthStart` | Sparkline 30 ימים + שינוי % מול חודש קודם |
| **בנאמנות כרגע** | `SUM(jobs.price) WHERE status == 'paid_escrow'` | Progress bars (כל עסקה bar אחד, צבע לפי זמן המתנה) |
| **עמלה משוקללת** | `SUM(platformFee) / SUM(amount) * 100` | Progress bar מול יעד (יעד = ערך settings.feePercentage) |
| **עמלות מותאמות** | `COUNT(users) WHERE customCommission != null` | Bar chart קטן (כמה הם מניבים מסך ההכנסה) |

**שדות חשובים:**
- כל KPI מראה גם את ה-**delta**: "▲ 23%" או "▼ 8%"
- תחזית לסוף החודש: `currentMonthEarnings / daysPassed * 30` (פרויקציה ליניארית פשוטה)

### סקציה 4: Smart Alerts Strip (3 עמודות)

3 baners אופקיים:

1. **🔴 Anomaly זוהה** — ספק עם ירידה חריגה ב-GMV (>30% מול ממוצע 4 שבועות)
2. **🟣 Churn Risk** — ספקי VIP שלא התחברו 10+ ימים, או ספקים רגילים עם `lastActive > 14 days ago`
3. **🟢 הזדמנות צמיחה** — קטגוריה עם גידול של >20% ב-GMV

**Cloud Function חדשה**: `detectMonetizationAnomalies` שרצה כל שעה ושומרת ב-`monetization_alerts/{alertId}`:
```javascript
{
  type: 'anomaly' | 'churn_risk' | 'growth_opportunity',
  severity: 'low' | 'medium' | 'high',
  entityType: 'user' | 'category',
  entityId: '...',
  message: 'יוסי כהן — GMV ירד 40% ב-7 ימים',
  detectedAt: Timestamp,
  resolved: false,
  suggestedAction: '...',
}
```

הטאב מציג 3 alerts אחרונים לא-resolved. לחיצה על "בדוק" פותחת את פרופיל הספק/קטגוריה.

### סקציה 5: מרכז שליטה בעמלות (Grid 2/3 + 1/3)

**חלק שמאלי (2/3) — Commission Control Center:**

- הדמיית היררכיה ויזואלית: `גלובלי (10%) → 5 קטגוריות מותאמות → 8 ספקים פרטניים`
- **ארבעה טאבים פנימיים**: `גלובלי | קטגוריות | ספקים | A/B בדיקות`
  - `גלובלי`: הסליידרים הנוכחיים (עמלה + דחיפות) — אבל עם **input numeric נוסף** ליד הסליידר לדיוק
  - `קטגוריות`: grid של כל הקטגוריות עם סליידר לכל אחת + badge "מותאם" אם != global
  - `ספקים`: חיפוש + טבלה (סקציה 7)
  - `A/B בדיקות`: Phase 2 — רשימת טסטים חיים (placeholder בינתיים)

- **שלושה כללים חכמים** (toggles):
  1. **פטור 3 עסקאות ראשונות** — שדה חדש ב-`settings`: `waiveFeeFirstNJobs: 3`. בדוק ב-`escrow_service` אם `user.completedJobs < 3` והחזר 0%.
  2. **עמלה מדורגת לפי volume** — חדש: `tieredCommission: { enabled: true, tiers: [{ minGMV: 5000, discount: 0.02 }, { minGMV: 10000, discount: 0.04 }] }`
  3. **בוסט סוף שבוע** — חדש: `weekendBoost: { enabled: true, daysOfWeek: [5, 6], extraPercentage: 2 }`

**חלק ימני (1/3) — Live Simulator:**

קונטיינר שחור (`#1D1D1B`) עם טקסט לבן. כשמשנים סליידר בחלק השמאלי, הסימולטור מחשב בזמן אמת:

```dart
class SimulationResult {
  final double projectedRevenue;
  final double revenueDelta;
  final int providersAtChurnRisk;
  final double acceptanceRate;
  final double projectedGMV;
  final String aiOpinion;
}

Future<SimulationResult> simulate({
  required double newGlobalFee,
  required double newUrgencyFee,
  Map<String, double>? categoryOverrides,
}) async {
  // 1. Fetch last 30 days of transactions
  // 2. Apply new commission structure to each transaction
  // 3. For each provider, calculate churn probability based on:
  //    - feeIncrease * their price sensitivity (use historical cancel rate)
  // 4. Return aggregated result
}
```

**Phase 1**: סימולציה פשוטה (הכנסה חדשה = GMV חודשי * עמלה חדשה, churn = אחוז קבוע לפי הפרש).
**Phase 2**: Cloud Function שקוראת ל-Gemini עם היסטוריית העסקאות ומבקשת חיזוי מתוחכם יותר.

### סקציה 6: Revenue Chart + Heatmap (Grid 3/5 + 2/5)

**גרף הכנסות ומגמות (3/5):**

גרף קווים (לא עמודות!) שמציג:
- חודש נוכחי (סגול מלא)
- חודש קודם (אפור מקווקו לרקע השוואה)
- תחזית להמשך החודש (ירוק מקווקו + אזור רקע בהיר)
- נקודה מסומנת בשיא עם label

השתמש ב-`fl_chart` package. אם לא מותקן:
```yaml
dependencies:
  fl_chart: ^0.69.0
```

תחת הגרף: שורה עם 4 סטטיסטיקות (ממוצע יומי, שיא, תחזית סוף חודש, MoM%).

**Heatmap לפי יום-שעה (2/5):**

Grid של 4 שורות (08, 12, 16, 20) × 7 עמודות (א-ש), כל תא בצבע סגול עם רמת saturation לפי מספר עסקאות.

שאילתה: `transactions where createdAt >= 30daysAgo` → ספור לפי `dayOfWeek × hourBucket`.

תא צבוע עם הערך הגבוה ביותר יוצג עם gradient הכי כהה. תחתיו תובנה אוטומטית:
> "שיא הפעילות ה׳ 16:00-20:00. שקול תוספת דחיפות של +3% בחלון הזה."

### סקציה 7: טבלת ניהול ספקים (מתקדמת)

**Filter chips למעלה:**
- הכל · 127
- מותאמים · 8
- VIP · 2
- Top 10% הכנסה
- בסיכון churn · 3 (אדום)
- ללא פעילות 7י׳

**עמודות הטבלה:**

| עמודה | מה מציג | מקור |
|-------|----------|------|
| ספק | אווטאר + שם + badges (VIP, Churn, Top) + תת-טקסט "מס' עסקאות · מאז תאריך" | `users` collection |
| קטגוריה | שם קטגוריה | `users.categoryId` → `categories.name` |
| GMV (30י) | סכום + חץ ↓ אם ירד | aggregate מ-`jobs` |
| עמלה | % + תת-טקסט (מותאם/מקטגוריה/ברירת מחדל) | מהפונקציה `getEffectiveCommission` |
| בריאות | ציון 0-100 + progress bar צבעוני | חישוב מקומי (ראה למטה) |
| מגמה | Sparkline 7 ימים (SVG inline) | `jobs` אחרונים |
| פעולה | כפתור "ערוך" (או "פעל ↗" אדום לספקים בסיכון) | — |

**חישוב ציון בריאות (0-100):**

```dart
double calculateHealthScore(User user) {
  double score = 50; // בסיס

  // עסקאות אחרונות (0-20 נקודות)
  final recentJobs = user.completedJobsLast30Days;
  score += (recentJobs / 30 * 20).clamp(0, 20);

  // דירוג ממוצע (0-15 נקודות)
  score += (user.avgRating / 5 * 15).clamp(0, 15);

  // אחוז cancel (0 עד -15 נקודות)
  score -= (user.cancelRate * 15).clamp(0, 15);

  // פעילות אחרונה (0 עד -20 נקודות)
  final daysSinceActive = DateTime.now().difference(user.lastActive).inDays;
  if (daysSinceActive > 14) score -= 20;
  else if (daysSinceActive > 7) score -= 10;

  // תגובה למסרים (0-15 נקודות)
  score += (user.responseRate * 15).clamp(0, 15);

  return score.clamp(0, 100);
}
```

צבע ה-bar:
- 80+: `#1D9E75` (ירוק)
- 50-79: `#EF9F27` (כתום)
- <50: `#E24B4A` (אדום)

**דיאלוג עריכת עמלה לספק:**

לחיצה על "ערוך" פותחת `showDialog` עם:
- סליידר לעמלה + numeric input
- 3 presets: "ברירת מחדל", "קטגוריה", "מותאם"
- שדה `reason` (dropdown): "שימור ספק", "ספק חדש", "Top performer", "פיצוי על תקלה", "אחר"
- שדה `notes` (טקסט חופשי)
- כפתור שמירה: מבצע `users/{uid}.update({ customCommission: { percentage, setAt: now, setBy: adminUid, reason, notes } })` + רושם ל-`activity_log`

### סקציה 8: Bottom Row — Escrow + Activity (Grid 1/2 + 1/2)

**Escrow משודרג:**

כל עסקה מוצגת עם **progress bar ויזואלי של 3 שלבים**:
```
[■■■■■] שולם ✓   [■■■□□] בביצוע   [□□□□□] שחרור
```

שני כפתורים במקום אחד:
- 🟢 **שחרר לספק** — מבצע batch: `jobs.status = 'completed'`, זיכוי `providerUid.balance += amount - platformFee`, רושם ל-`platform_earnings`, transaction ב-`transactions`.
- 🔴 **החזר ללקוח** — הפעולה הקיימת (השאר כמו שהיא).

כפתור `⋯` נוסף עם: "צפה בפרטי העסקה", "שלח הודעה לשני הצדדים", "העבר למחלקת תמיכה".

**Activity Timeline חי:**

`StreamBuilder` על `activity_log` where `category == 'monetization'` limit 5. כל פריט:
- אייקון עגול בצבע לפי סוג הפעולה
- תיאור + קישורים לישויות
- זמן יחסי ("לפני 3 דקות")

סוגי אירועים:
- עסקה שוחררה
- עמלה עודכנה (פר-ספק / קטגוריה / גלובלי)
- עסקה בנאמנות חדשה
- VIP חדש / ביטול VIP
- תובנת AI חדשה

### סקציה 9: (הוסר — נכלל בטאבים של סקציה 5)

---

## 📦 Collections חדשות ב-Firestore

### 1. `category_commissions/{categoryId}`
```typescript
{
  categoryId: string,
  percentage: number,       // 0-30
  updatedAt: Timestamp,
  updatedBy: string,        // admin uid
  reason?: string,
}
```

### 2. `users/{uid}.customCommission` (שדה חדש)
```typescript
{
  percentage: number,
  setAt: Timestamp,
  setBy: string,
  reason: string,
  notes?: string,
  expiresAt?: Timestamp,    // אופציונלי — עמלה זמנית
}
```

### 3. `ai_insights/monetization/latest`
```typescript
{
  title: string,
  recommendation: string,
  expectedImpact: string,
  actionType: string,
  actionParams: Record<string, any>,
  generatedAt: Timestamp,
  model: 'gemini-2.5-flash-lite',
  applied: boolean,
  dismissedBy?: string,
}
```

### 4. `monetization_alerts/{alertId}`
```typescript
{
  type: 'anomaly' | 'churn_risk' | 'growth_opportunity',
  severity: 'low' | 'medium' | 'high',
  entityType: 'user' | 'category',
  entityId: string,
  message: string,
  detectedAt: Timestamp,
  resolved: boolean,
  suggestedAction: string,
}
```

### 5. `admin/admin/settings/settings` (שדות חדשים)
```typescript
{
  // ... שדות קיימים
  waiveFeeFirstNJobs: number,           // ברירת מחדל: 0 (מבוטל)
  tieredCommission: {
    enabled: boolean,
    tiers: Array<{ minGMV: number, discount: number }>,
  },
  weekendBoost: {
    enabled: boolean,
    daysOfWeek: number[],               // [5, 6] = ו', ש'
    extraPercentage: number,
  },
}
```

---

## ⚙️ Cloud Functions חדשות ב-`functions/index.js`

```javascript
// 1. מחזירה עמלה אפקטיבית
exports.getEffectiveCommission = functions.https.onCall(async (data, context) => { ... });

// 2. סורק anomalies כל שעה
exports.detectMonetizationAnomalies = functions.pubsub
  .schedule('every 1 hours')
  .onRun(async (context) => { ... });

// 3. מייצר תובנת AI כל 6 שעות (Gemini)
exports.generateMonetizationInsight = functions.pubsub
  .schedule('every 6 hours')
  .onRun(async (context) => {
    // קורא ל-Gemini 2.5 Flash Lite עם:
    // - סכום GMV לפי קטגוריה (30 ימים)
    // - ספקים פעילים/לא פעילים
    // - churn rate
    // - עמלות ממוצעות בפועל
    // ומבקש המלצה אחת קונקרטית
  });

// 4. סימולטור השפעה (async, על הדרישה)
exports.simulateCommissionChange = functions.https.onCall(async (data, context) => { ... });

// 5. מחשב ציון בריאות לכל הספקים (כל לילה)
exports.calculateProviderHealthScores = functions.pubsub
  .schedule('every day 03:00')
  .timeZone('Asia/Jerusalem')
  .onRun(async (context) => { ... });
```

---

## 🎨 עיצוב — Design Tokens

צור `lib/widgets/monetization/design_tokens.dart`:

```dart
class MonetizationTokens {
  // Colors — Airbnb-inspired warm palette
  static const primary = Color(0xFF7F77DD);      // Purple 400
  static const primaryDark = Color(0xFF3C3489);
  static const primaryLight = Color(0xFFEEEDFE);

  static const success = Color(0xFF1D9E75);      // Teal 600
  static const successLight = Color(0xFFE1F5EE);

  static const warning = Color(0xFFEF9F27);      // Amber 400
  static const warningLight = Color(0xFFFAEEDA);

  static const danger = Color(0xFFE24B4A);       // Red 400
  static const dangerLight = Color(0xFFFCEBEB);

  static const vip = Color(0xFF854F0B);          // Amber 800
  static const vipLight = Color(0xFFFAEEDA);

  static const textPrimary = Color(0xFF1D1D1B);
  static const textSecondary = Color(0xFF5F5E5A);
  static const textTertiary = Color(0xFF888780);

  static const borderSoft = Color(0x26000000);   // 0.15 alpha
  static const surface = Colors.white;
  static const surfaceAlt = Color(0xFFF7F5F0);

  // Typography
  static const fontFamily = 'Assistant'; // או מה שקיים בפרויקט
  static TextStyle h1 = TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: textPrimary);
  static TextStyle h2 = TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: textPrimary);
  static TextStyle h3 = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: textPrimary);
  static TextStyle body = TextStyle(fontSize: 13, color: textPrimary, height: 1.5);
  static TextStyle caption = TextStyle(fontSize: 11, color: textSecondary);
  static TextStyle micro = TextStyle(fontSize: 10, color: textTertiary);

  // Spacing
  static const spaceXs = 4.0;
  static const spaceSm = 8.0;
  static const spaceMd = 12.0;
  static const spaceLg = 16.0;
  static const spaceXl = 20.0;
  static const spaceXxl = 28.0;

  // Radius
  static const radiusSm = 6.0;
  static const radiusMd = 8.0;
  static const radiusLg = 12.0;
  static const radiusXl = 16.0;

  // Shadows (VERY subtle only)
  static const cardShadow = [
    BoxShadow(color: Color(0x08000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
}
```

---

## 📂 קבצים חדשים שצריך ליצור

```
lib/screens/
  admin_monetization_tab.dart              ← שכתוב מלא
lib/widgets/monetization/
  design_tokens.dart                       ← חדש
  kpi_card.dart                            ← חדש
  smart_alert_card.dart                    ← חדש
  ai_insight_banner.dart                   ← חדש
  commission_simulator.dart                ← חדש
  commission_hierarchy_visual.dart         ← חדש
  provider_commission_table.dart           ← חדש
  provider_edit_dialog.dart                ← חדש
  escrow_transaction_card.dart             ← חדש
  activity_timeline.dart                   ← חדש
  revenue_chart.dart                       ← חדש
  activity_heatmap.dart                    ← חדש
  command_palette.dart                     ← חדש (Phase 2)
lib/services/
  monetization_service.dart                ← חדש (wraps כל הקריאות ל-Firestore)
  commission_calculator.dart               ← חדש
functions/
  index.js                                 ← הוסף 5 פונקציות חדשות
```

---

## 🔒 הוראות קריטיות

### ✅ חובה

1. **Gemini ולא Claude** — ה-AI CEO חייב להישאר על Gemini (`gemini-2.5-flash-lite`). אל תחליף ל-Claude API. זה חובה.
2. **עברית RTL** — כל הטקסטים בעברית, כל הפריסה RTL (`Directionality(textDirection: TextDirection.rtl, ...)`).
3. **תמיכה במצב כהה** — השתמש ב-`Theme.of(context).brightness` כדי להתאים צבעים.
4. **ללא Stripe** — Phase 2 עובד רק עם יתרת קרדיטים פנימית. כל "החזר" מזכה את `users.balance`.
5. **Atomic operations** — כל פעולת כסף חייבת להיות בתוך `FirebaseFirestore.instance.runTransaction()` או `WriteBatch`.
6. **Activity log** — כל פעולת אדמין (שינוי עמלה, שחרור escrow, החזר) חייבת להירשם ב-`activity_log` עם:
   ```dart
   {
     'action': 'commission_updated_for_user',
     'category': 'monetization',
     'adminUid': currentUser.uid,
     'targetUid': providerUid,
     'oldValue': 10,
     'newValue': 8,
     'reason': '...',
     'timestamp': FieldValue.serverTimestamp(),
   }
   ```
7. **Firestore Rules** — עדכן את `firestore.rules` כדי ש:
   - `category_commissions` יהיה קריא לכולם, כתיב רק לאדמינים
   - `ai_insights` יהיה קריא לאדמינים בלבד
   - `monetization_alerts` יהיה קריא לאדמינים בלבד
   - `users.customCommission` יהיה כתיב רק על ידי אדמין (דרך Cloud Function, לא ישירות)

### ❌ אסור

1. אל תמחק את שדה `feePercentage` ב-settings — עדיין שימושי כברירת מחדל.
2. אל תשבור את ה-flow הקיים של escrow_service — רק הרחב אותו.
3. אל תשתמש ב-`print()` — רק `debugPrint()` או logger.
4. אל תכתוב ב-English בתוך UI (רק labels טכניים).

---

## 🧪 בדיקות

אחרי הסיום:

```bash
# 1. בדיקת לינט
flutter analyze

# 2. בדיקת בנייה
flutter build web

# 3. deploy של הפונקציות
firebase deploy --only functions:getEffectiveCommission,functions:detectMonetizationAnomalies,functions:generateMonetizationInsight,functions:simulateCommissionChange,functions:calculateProviderHealthScores

# 4. deploy של rules
firebase deploy --only firestore:rules
```

**יעד**: `flutter analyze` חייב להחזיר **0 issues**.

---

## 📋 Checklist לפני commit

- [ ] כל 9 הסקציות ממומשות ו-responsive
- [ ] 4 KPIs מציגים נתונים חיים מ-Firestore (לא mock data)
- [ ] שכבת עמלות עובדת: גלובלי → קטגוריה → ספק
- [ ] דיאלוג עריכת עמלה פרטנית שומר ל-`users.customCommission`
- [ ] סימולטור מחשב בזמן אמת (גם אם Phase 1 פשוט)
- [ ] Escrow תומך ב-"שחרר לספק" + "החזר ללקוח"
- [ ] Activity log נרשם בכל פעולת אדמין
- [ ] 5 Cloud Functions חדשות deploy-ed
- [ ] `flutter analyze`: 0 issues
- [ ] RTL נכון בכל מקום
- [ ] Dark mode עובד
- [ ] עדכון `CLAUDE.md` בפרויקט (סקציה 29 או חדשה) שמתעד את המבנה החדש

---

## 🎯 שלבי עבודה מומלצים

**שלב 1 — תשתית נתונים (יום 1):**
1. צור את 4 ה-collections החדשים
2. צור את `monetization_service.dart`
3. עדכן `firestore.rules`
4. צור את `getEffectiveCommission` Cloud Function
5. עדכן `escrow_service.dart` לקרוא לפונקציה החדשה

**שלב 2 — UI Skeleton (יום 2):**
6. צור `design_tokens.dart`
7. שכתב את `admin_monetization_tab.dart` עם Scaffold של כל 9 הסקציות (תוכן placeholder)
8. צור את רכיבי ה-widget החדשים (קבצים ריקים עם class מוצהר)

**שלב 3 — KPIs + Alerts (יום 3):**
9. מימוש 4 ה-KPIs עם sparklines
10. מימוש Smart Alerts Strip + Cloud Function `detectMonetizationAnomalies`

**שלב 4 — Commission Control Center (יום 4-5):**
11. טאבים פנימיים
12. Grid של קטגוריות
13. טבלת ספקים + דיאלוג עריכה
14. כללים חכמים (3 toggles)

**שלב 5 — Simulator + AI (יום 6):**
15. Live Simulator
16. AI Insight Banner + Cloud Function `generateMonetizationInsight`

**שלב 6 — Charts + Escrow + Activity (יום 7):**
17. Revenue chart (fl_chart)
18. Heatmap
19. Escrow משודרג
20. Activity Timeline

**שלב 7 — Polish + Tests (יום 8):**
21. Responsive design
22. Dark mode
23. `flutter analyze` → 0 issues
24. עדכון `CLAUDE.md`
25. Commit + push

---

## 📎 הפניות לקבצים קיימים

קבצים שתצטרך להתייחס אליהם (קרא אותם לפני העבודה):

- `lib/screens/admin_monetization_tab.dart` — הקובץ הנוכחי לשכתוב
- `lib/services/escrow_service.dart` — שורות 41-54 (פונקציית חישוב עמלה)
- `functions/index.js` — כאן יתווספו 5 הפונקציות החדשות
- `CLAUDE.md` — תיעוד פרויקטי (סקציה 29 — Vault, סקציה 6 — דירוג חיפוש)
- `lib/screens/admin_screen.dart` — הטאב משולב כאן במבנה tabs

---

## 🎨 ה-Mockup

**אל תמציא עיצוב — פתח את הקובץ `monetization_mockup.html` בדפדפן וראה בדיוק איך הדף אמור להיראות.**

הוא מכיל את כל 9 הסקציות בפריסה הסופית, עם צבעים מדויקים, מיקומים, ו-spacing. כל פרט שם הוא **כוונתי** — הפריסה, המרווחים, הצבעים, הטייפוגרפיה. אם יש סתירה בין הטקסט בקובץ הזה לבין ה-HTML — ה-HTML מנצח.

---

**בהצלחה! זה שדרוג משמעותי — אל תמהר, עבוד לפי שלבים, והקפד על איכות קוד. אם משהו לא ברור — שאל את אביחי לפני שאתה מחליט לבד.**
