# 📝 Provider Edit Screen - Handyman | מסך עריכת נותן השירות

> **קובץ זה הוא חלק מ-`01_MAIN_PROMPT_HANDYMAN.md`** - קרא אותו קודם!

---

## ⛔ תזכורת קריטית

המסך הזה כבר קיים. אתה **רק מוסיף בלוק חדש** מתחת לבחירת תת-קטגוריה "הנדימן".

**הסדר במסך:**
```
1. Header (קיים)
2. פרטים אישיים (קיים)
3. תמונת פרופיל (קיים)
4. אודות (קיים)
5. תת-קטגוריה "הנדימן" (קיים)
   ↓ ↓ ↓
6. ✨ הבלוק החדש "ההגדרות שלך" ← מתווסף כאן רק אם נבחר "הנדימן"!
   ↑ ↑ ↑
7. גלריית עבודות (קיים)
8. יומן זמינות (קיים) ⚠️ שם קובעים שעות!
9. כפתורי שמירה (קיים)
```

---

## 🔴 מה אסור להיות בבלוק החדש (חשוב!)

1. ❌ **אין "תעודת זהות" בסקציית האימותים** - כל נותן שירות כבר עבר אימות ת"ז בהרשמה לאפליקציה (גלובלי)
2. ❌ **אין שום אלמנט של "ביטוח"** - האפליקציה לא מציעה ביטוח
3. ❌ **אין סקציית "שעות פעילות"** - השעות נקבעות ביומן הקיים למטה
4. ❌ **אין סקציית "Reviews Insights / איך לקוחות רואים אותך"** - הדירוג והביקורות כבר בפרופיל עצמו

---

## 📍 מתי הבלוק החדש מופיע?

- נותן השירות נכנס לעריכת פרופיל
- בחר תת-קטגוריה "הנדימן" (`subcategory == 'handyman'`)

אם מבטל את "הנדימן" → הבלוק נעלם, אבל הנתונים נשמרים ב-Firestore.

---

## 🎨 הבלוק החדש - Dark Premium Orange/Amber

### Container ראשי
```dart
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF0A0E1A),
        Color(0xFF1A1612),  // חם יותר לכתום
        Color(0xFF0F1420),
      ],
    ),
  ),
  // + 4 ambient orbs: orange, green, purple, indigo
)
```

הבלוק מתחיל עם separator + טקסט "↓ ההגדרות המקצועיות שלך ↓"

---

## 🌟 Section 0: Hero (בלי כפילויות!)

### מה יש:
1. **Badge ירוק עם pulse dot**: "● פרופיל פעיל · 12 פניות השבוע"
2. **3 Status Badges**:
   - 🏆 Top 1% · ת"א (סגול)
   - ⚡ Pro Verified (כחול)
   - ✓ מאומת מלא (ירוק)
3. **Gradient Title**: "ההגדרות שלך" (לבן → FDBA74)
4. **Subtitle**: "ככל שתגדיר יותר טוב - יותר לקוחות ימצאו אותך"
5. **Revenue Banner** (סגול):
   - 📈 "הכנסה החודש: ₪18,450"
   - "↗ +23% מהחודש שעבר · 87% לקוחות חוזרים"

### ❌ מה הוסר:
- תמונת פרופיל (כבר קיימת למעלה)
- KPIs כפולים (3,247/4.94/87% כבר בפרופיל)
- "פרופיל מלא 87%" progress bar

---

## 🔴 Section 1: אימותים (רק 2 - בלי ת"ז!)

### ⚠️ חשוב: רק 2 אימותים, לא 3!
**כל נותן שירות בAnySkill כבר אומת ת"ז בהרשמה → אל תציג את זה כאן!**

### Container:
- Border אדום בולט (rgba(220,38,38,0.4)) עם glow
- Header: "!" באדום + "אימותים (חובה)"
- Badge ירוק "2/2 מאושרים" בצד שמאל
- Subtitle: "חובה לאישור פרופיל - מוכיח ללקוחות שאפשר לסמוך עליך"

### 2 אימותים (בירוק):

#### 1. 📋 בדיקת רקע
- אייקון ירוק gradient
- "בדיקת רקע"
- "ללא רישום פלילי · עדכון 03/2026"
- Badge "מאושר" ירוק

#### 2. 📜 אחריות 12 חודש (Toggle!)
- אייקון ירוק gradient
- "אחריות 12 חודש"
- "תאושר אוטומטית על כל עבודה"
- **Toggle** (בברירת מחדל ON)

### ❌ לא להוסיף:
- תעודת זהות
- ביטוח

---

## 🤖 Section 2: AI Photo-to-Quote Settings

### Container:
- Border כתום בולט rgba(249,115,22,0.5)
- Box shadow: 0 8px 24px rgba(249,115,22,0.15)

### Header:
```
[🤖 gradient icon]  AI Photo-to-Quote          [Main Toggle ON]
                     ⭐ 78% מהלקוחות מעלים תמונה
```

### Info Banner (כתום):
> 💡 **איך זה עובד:** הלקוח מצלם → AI מנתח → אתה מאשר את האומדן או משנה. פרופילים עם AI מקבלים **+40% הזמנות**

### Sub-toggles (4 קטגוריות):
```
⚙️ מה AI יזהה עבורך

🚿 בעיות אינסטלציה    [Toggle ON]
💡 בעיות חשמל         [Toggle ON]
🔨 בעיות גבס/צבע     [Toggle ON]
🪑 הרכבת רהיטים      [Toggle ON]
```

### Save Logic:
```dart
Map<String, dynamic> aiSettings = {
  'enabled': mainToggle,
  'categories': {
    'plumbing': plumbingToggle,
    'electrical': electricalToggle,
    'drywall': drywallToggle,
    'furniture': furnitureToggle,
  }
};
await firestore.collection('users').doc(userId).update({
  'handymanProfile.aiPhotoToQuote': aiSettings,
});
```

---

## 🧰 Section 3: 23 תחומי ההתמחות

### Header:
```
[1]  תחומי ההתמחות שלך
     8 פעיל · 15 פוטנציאל להוסיף
```

### Search Bar:
```
[🔍 חפש תחום...]
```

### Grid 3x4 (23 תחומים):

#### 🟢 8 תחומים פעילים (ירוק + checkmark):
1. 📺 תליית TV · 287 השנה
2. 🪑 רהיטים · 412 השנה
3. 🚿 אינסטלציה · 198 השנה
4. 💡 חשמל קל · 156 השנה
5. 🎨 צביעה · 87 השנה
6. 🔨 גבס · 234 השנה
7. 🚪 דלתות · 143 השנה
8. 🔧 תיקון רהיטים · 189 השנה

#### 🟠 3 פוטנציאל (dashed + badge):
- 🪟 תריסים · +67 לקוחות צפויים
- 🧱 אריחים · +45
- 🪴 גינון · +38

#### "עוד 12" - כפתור להרחבה

### Tip חכם (סגול):
> 💎 **טיפ**: נותני שירות עם 12+ תחומים מרוויחים פי 2.3
> הוסף עוד 4 תחומים ותקבל badge "Multi-Expert"

---

## 💰 Section 4: מחירון חכם עם Market Intelligence

### Container:
- Border amber rgba(245,158,11,0.5)

### Header:
```
[💰 amber icon]  מחירון חכם לפי עבודה
                  AI משווה למחירי שוק תל אביב
```

### Market Intelligence Card (כחול):
```
📊 מחירי שוק ת"א (ממוצע)

[זול: ₪150]  [ממוצע: ₪180 ✓]  [יקר: ₪220]
```
הערך הנבחר מודגש בכחול.

### My Prices Section:
```
המחירים שלך

📺 תליית טלוויזיה      [₪180]   ✓ מחיר תחרותי
🪑 הרכבת רהיטים       [₪220]   ⚠ מעל הממוצע
🚿 אינסטלציה          [₪140]   ✓ מחיר תחרותי
```

כל שורה עם:
- אייקון התחום
- שם + Feedback (ירוק: ✓ / צהוב: ⚠)
- Input box למחיר (עריך)

### כפתור:
```
+ הוסף עבודה מותאמת
```

### תוספת חירום (אדום):
```
🚨 תוספת חירום                 [+₪50]
   מחירך על הגעה תוך 25 דק'
```

---

## 📋 Section 5: Punch List Discount

### Container:
- Border סגול rgba(168,85,247,0.5)

### Header:
```
[📋 purple icon]  Punch List Discount
                   ככל שיש יותר עבודות בביקור - יותר הנחה
```

### 3 רמות עם Progress Bars:
```
2 עבודות   [===   ]   [−10%]
3 עבודות   [=====  ]   [−20%]
4+ עבודות  [=======]   [−30%]
```

כל רמה עם:
- טקסט "2 עבודות" וכו'
- Progress bar מילוי (50%/75%/100%)
- Input עריך לאחוז ההנחה

### Save:
```dart
await firestore.collection('users').doc(userId).update({
  'handymanProfile.punchListDiscount': {
    '2_jobs': 10,
    '3_jobs': 20,
    '4_plus_jobs': 30,
  }
});
```

---

## 🗺️ Section 6: אזורי שירות (בלי שעות!)

### Header:
```
[2]  אזורי שירות
     איפה אתה עובד
```

### Sub-section A: חירום 24/7 (אדום)
```
🚨 חירום 24/7                        [Toggle ON]
   הגעה תוך 25 דק' · הכנסה גבוהה
```

### Sub-section B: אזורי כיסוי
```
🗺️ אזורי כיסוי

[תל אביב ✓] [רמת גן ✓] [גבעתיים ✓] [הרצליה ✓]
[+ בני ברק] (dashed)
```

### Sub-section C: זמן חייץ
```
🕐 זמן חייץ בין עבודות     [30 דק']
   לנסיעה + התכוננות
```

### 🗓️ BANNER חשוב - רמז ליומן:
```
┌─────────────────────────────────────┐
│ 🗓️ שעות פעילות נקבעות ביומן      ↓ │
│    סמן ביומן הקיים למטה את הימים   │
│    והשעות שלך                       │
└─────────────────────────────────────┘
```

Container:
- Gradient כחול: `linear-gradient(135deg, rgba(59,130,246,0.15), rgba(37,99,235,0.05))`
- Border: 1px solid rgba(59,130,246,0.3)
- חץ ↓ שמרמז על היומן למטה במסך

### ❌ לא להוסיף:
- סקציית "שעות פעילות" עם 4 toggles
- בוקר/צהרי/ערב/סופ"ש
- אלה נקבעים ביומן!

---

## 🛒 Section 7: ניהול חומרים

### Header:
```
[🛒 amber icon]  ניהול חומרים וציוד
                  שקיפות = יותר לקוחות סומכים עליך
```

### Sub-section A: כלים כלולים
```
🔧 כל הציוד המקצועי כלול           [Toggle ON]
   50+ כלים - ברירת מחדל
```

### Sub-section B: מדיניות חומרים
```
📦 מדיניות חומרים
   מי קונה חומרים לעבודה?

[🛍️ אני קונה ✓]   [🏪 הלקוח]   [🔄 גמיש]
+ 15%               בעלות          לפי עבודה
```

### Tip (כתום):
```
💡 פרופיל עם "אני קונה חומרים" מקבל +32% המרות
```

---

## 💼 Section 8: חוזי תחזוקה שנתיים

### Container:
- Gradient כחול כהה: `linear-gradient(135deg, #1E3A8A 0%, #1E40AF 100%)`
- 1 orb זהוב ברקע

### Header:
```
[🔁 amber icon]  חוזי תחזוקה שנתיים
                  הכנסה קבועה · 23 לקוחות פעילים
```

### 3 חבילות:

#### בייסיק (פעיל)
```
בייסיק · 2 ביקורים/שנה           [פעיל]
8 לקוחות פעילים
[₪ 890 /שנה] (input editable)
```

#### פרימיום (highlighted ⭐)
```
[⭐ פופולרי]
פרימיום · 4 ביקורים/שנה           [פעיל]
12 לקוחות פעילים
[₪ 1690 /שנה]
```

#### VIP
```
VIP · ללא הגבלה                  [פעיל]
3 לקוחות פעילים
[₪ 2990 /שנה]
```

### Revenue Summary (תחתית):
```
💰 הכנסה שנתית מחוזים: ₪34,820
   23 לקוחות פעילים · הכנסה קבועה
```

---

## 💾 Save Logic

```dart
async function saveHandymanProfile(userId, formData) {
  final handymanProfile = {
    'verifications': {
      'backgroundCheck': {
        'verified': formData.backgroundVerified,
        'verifiedAt': formData.backgroundVerifiedAt,
        'documentUrl': formData.backgroundDocUrl,
      },
      // NO idVerification here - global in app
      // NO insurance - doesn't exist in app
      'warrantyEnabled': formData.warrantyToggle,
    },
    'specialties': formData.selectedSpecialties,
    'aiPhotoToQuote': formData.aiSettings,
    'pricing': {
      'custom': formData.customPrices,
      'emergencySurcharge': formData.emergencySurcharge,
    },
    'punchListDiscount': formData.discounts,
    'serviceArea': {
      'cities': formData.selectedCities,
      'emergency24_7': formData.emergency247,
      'bufferMinutes': formData.bufferMinutes,
      // NO workHours here - in calendar!
    },
    'materials': {
      'toolsIncluded': formData.toolsIncluded,
      'policy': formData.materialsPolicy,
    },
    'maintenancePackages': formData.maintenancePackages,
  };

  // Validation
  if (!handymanProfile.verifications.backgroundCheck.verified) {
    throw 'נדרשת בדיקת רקע מאושרת';
  }
  if (handymanProfile.specialties.filter(s => s.active).length === 0) {
    throw 'בחר לפחות תחום התמחות אחד';
  }

  await firestore.collection('users').doc(userId).update({
    handymanProfile: handymanProfile,
  });

  await syncHandymanProfileToListings(userId);
}
```

---

## ⚠️ Edge Cases & Validation

1. **לא נבחרה תת-קטגוריה "הנדימן"** → הבלוק לא מופיע
2. **ביטול "הנדימן"** → הבלוק נעלם, הנתונים נשמרים
3. **אין בדיקת רקע** → אי אפשר לאשר פרופיל
4. **0 תחומים פעילים** → אי אפשר לשמור
5. **מחיר 0 או שלילי** → validation error
6. **חירום 24/7 ללא תוספת מחיר** → warning
7. **חבילה פעילה בלי מחיר** → validation error

---

זה המפרט המלא לדף עריכת נותן השירות. עבור הצד של הלקוח - ראה `03_CLIENT_BOOKING_HANDYMAN.md`.
