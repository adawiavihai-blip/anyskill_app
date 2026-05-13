# 📝 Provider Edit Screen - Cleaning | מסך עריכת המנקה

> **קובץ זה הוא חלק מ-`01_MAIN_PROMPT_CLEANING.md`** - קרא אותו קודם!

---

## ⛔ תזכורת קריטית: לא למחוק כלום!

המסך הזה כבר קיים. אתה **רק מוסיף בלוק חדש** מתחת לבחירת תת-קטגוריה "נקיון".

**הסדר במסך:**
```
1. Header עם "←" ו"שמור" (קיים - לא נוגעים)
2. פרטים אישיים - שם, ניסיון, ✎ (קיים - לא נוגעים)
3. תמונת פרופיל (קיים - לא נוגעים)
4. אודות (קיים - לא נוגעים)
5. בלוק תת-קטגוריה - "נקיון" (קיים - לא נוגעים)
   ↓ ↓ ↓
6. ✨ הבלוק החדש "המקצועיות שלך" ← מתווסף כאן רק אם נבחר "נקיון"!
   ↑ ↑ ↑
7. גלריית עבודות (קיים - לא נוגעים)
8. יומן זמינות (קיים - לא נוגעים) ⚠️ זה אותו יומן שהלקוחות יראו!
9. כפתורי "תצוגה מקדימה" + "שמור שינויים" (קיים - לא נוגעים)
```

---

## 🔄 הסנכרון - חובה!

### יומן זמינות - מסונכרן אוטומטית
**אסור לבנות יומן חדש בבלוק החדש!** היומן הקיים בסעיף 8 הוא **המקור היחיד** של הזמינות. כשהלקוח רואה את הבלוק "בואי נתאים את הניקיון שלך" ולוחץ "קבעי מועד", הוא נשלח לאותו יומן בדיוק.

### Recurring Customers Counter
**הספירה ב-Hero ("15 לקוחות פעילים, ₪3,470/חודש") חייבת לקרוא מ-bookings collection בזמן אמת:**

```dart
StreamBuilder<int>(
  stream: cleaningAnalyticsService.streamRecurringCustomersCount(providerId),
  builder: (context, snapshot) {
    final count = snapshot.data ?? 0;
    final monthlyRevenue = count * averageMonthlyValue;
    return RecurringCustomersBanner(
      count: count,
      monthlyRevenue: monthlyRevenue,
    );
  },
)
```

---

## 📍 מתי הבלוק החדש מופיע?

הבלוק "המקצועיות שלך" מופיע **רק** במצב הבא:
- המנקה נכנסת לעריכת פרופיל
- בחרה תת-קטגוריה "נקיון" (`subcategory == 'cleaning'`)

**אם המנקה מבטלת את בחירת "נקיון":**
- הבלוק נעלם מה-UI
- הנתונים נשמרים ב-Firestore (במקרה שתחזור)

---

## 🎨 הבלוק החדש - מבנה כללי

### Container ראשי - Dark Premium
רקע `linear-gradient(135deg, #0A0E1A 0%, #0F1A2E 50%, #0F1420 100%)` עם 3 ambient orbs:
- Orb cyan ברקע ימני עליון
- Orb green ברקע שמאלי אמצעי
- Orb purple ברקע ימני תחתון

הבלוק מתחיל עם separator cyan + טקסט "↓ הבלוק החדש - מתווסף רק אחרי 'נקיון' ↓"

### סקציות לפי הסדר:

### 🌟 Hero Section (Section 0)
1. **תמונת פרופיל** עם conic-gradient glow cyan
2. **Badge "🏆"** בפינה ימנית עליונה של התמונה
3. **כותרת** "המקצועיות שלך" ב-gradient text (לבן → cyan)
4. **Subtitle** "הגדרות שיביאו לך לקוחות בכל החודש"
5. **2 Status badges**: "פעילה · 12 בקשות השבוע" + "Top 3 · ת"א"
6. **3 KPIs**: 2,148 נקיונות · ★ 4.96 דירוג · 87% חוזרים
7. **Recurring Customers Banner** (גרדיאנט סגול): "15 לקוחות חוזרים פעילים · הכנסה קבועה: ₪3,470/חודש"

### 🔴 Section 1: אימותים (חובה!)
- **Border אדום בולט** (1.5px solid rgba(220,38,38,0.4))
- 3 אימותי חובה:
  - 🆔 תעודת זהות (מאומת ב-OCR)
  - 📋 בדיקת רקע (ללא רישום פלילי, עדכון 03/2026)
  - 📞 3 ממליצים מאומתים (לקוחות שאישרו את העבודה)
- כל אימות עם אייקון gradient ירוק + badge "מאושר"

### 🧼 Section 2: סוגי נקיון שאני מבצעת
**Grid 2x3** עם 6 אפשרויות:
- 3 פעילים (gradient ירוק + checkmark + ספירת השנה: 847/312/624):
  - 🏠 בית רגיל
  - ✨ Deep / שיפוץ
  - 🏨 Airbnb
- 3 פוטנציאל (dashed border cyan + badge "+45/+22/+18"):
  - 🏢 משרדים
  - 🏬 חנויות
  - 🧽 לפני אירוע

### 🌱 Section 3: Eco Mode (border ירוק בולט)
- Header עם אייקון ירוק + "Eco-Friendly Mode"
- Subtitle: "⭐ 78% מהלקוחות בוחרים בעדיפות"
- Toggle לאפשור "אני מציעה חומרים אקולוגיים"
- Subtext: "מאושר EcoCert · בטוח לילדים ובעלי-חיים"
- שדה תוספת מחיר: ₪25 /לביקור

### 📋 Section 4: Checklist Builder (border סגול בולט)
- Header עם אייקון סגול + "Checklist בסיסי שלך"
- Subtitle: "⭐ הלקוחות יוכלו להוסיף/להוריד לעצמם"
- Info banner: "איך זה עובד: את מגדירה רשימה בסיסית. הלקוח רואה אותה ויכול לסמן/לבטל לפי הצורך."
- 3 קטגוריות מוכנות:
  - 🛏️ חדר שינה (3 משימות)
  - 🚿 חדר אמבטיה (4 משימות)
  - 🍽️ מטבח (5 משימות) - אחת היא Add-on +₪40
- כל משימה עם:
  - Checkbox סגול לסימון פעילות
  - Input לעריכת הטקסט
  - Drag handle ≡ לשינוי סדר
- כפתור "+הוסף משימה" בכל קטגוריה
- כפתור "+הוסף קטגוריה (חדר עבודה, מרפסת...)" בסוף

### 💰 Section 5: מחירון לפי גודל הבית
**Header**: "המערכת תחשב אוטומטית ללקוח"

#### 5a. בית רגיל - מחיר בסיס:
4 רמות:
- 🏠 עד 60 מ"ר (דירת 2) → ₪180
- 🏡 60-100 מ"ר (דירת 3-4 · הכי נפוץ) → ₪240 (highlight cyan)
- 🏘️ 100-150 מ"ר (5/קוטג') → ₪320
- 🏰 מעל 150 מ"ר (פנטהאוז) → ₪420

#### 5b. תוספות מחיר לפי סוג נקיון:
- ✨ Deep / לאחר שיפוץ: +100%
- 🏨 Airbnb (מהיר): -20%

#### 5c. תוספות אופציונליות (Add-Ons):
- 🍽️ תנור פנימי: ₪40
- 🧊 מקרר פנימי: ₪30
- 🪟 חלונות חיצוניים: ₪60
- 🛋️ ניקוי ספות בקיטור: ₪120

### 🔄 Section 6: מנוי קבוע - הנחות (border סגול בולט)
- Header עם אייקון סגול + "מנוי קבוע - הנחות"
- Subtitle: "⭐ הכנסה צפויה לאורך זמן"
- Info: "💎 מנקות עם 5+ לקוחות חוזרים = הכנסה כפולה"
- 3 רמות:
  - 📅 שבועי (לקוח קבוע מובהק) → -15%
  - ⭐ דו-שבועי (הכי משתלם · 70% מהלקוחות) → -10% (highlight)
  - 🗓️ חודשי (דיירי בית פרטי) → -5%

### 📍 Section 7: אזורי שירות וזמינות

#### 7a. אזורי כיסוי:
Chips נבחרים: תל אביב ✓ · רמת גן ✓ · גבעתיים ✓
Chips dashed: + הרצליה

#### 7b. שעות פעילות:
- בוקר 7-12 (ירוק)
- צהרי 12-17 (ירוק)
- ערב 17-22 (אפור)
- סופ"ש (אפור)

### 💼 Section 8: מנוי חודשי לעסקים
- Container gradient כחול כהה עם orb cyan ברקע
- Header: "מנוי חודשי לעסקים · משרדים, חנויות · הכנסה קבועה"
- 2 חבילות פעילות:
  - 📅 4 ביקורים/חודש (פעם בשבוע) → ₪890/חודש
  - 🚀 8 ביקורים/חודש (פעמיים בשבוע) → ₪1,690/חודש
- כפתור "+ הוסף חבילה"

ובסוף: separator cyan + "↑ סוף הבלוק החדש ↑"

---

## 💾 Save Logic

```javascript
async function saveCleaningProfile(userId, formData) {
  const cleaningProfile = {
    verifications: {
      idVerified: formData.idVerified,
      backgroundChecked: formData.backgroundChecked,
      referencesCount: formData.referencesCount,
      referencesVerified: formData.referencesVerified,
      insuranceAmount: formData.insuranceAmount || 10000,
      insuranceProvider: formData.insuranceProvider,
      insuranceValidUntil: formData.insuranceValidUntil,
    },
    cleaningTypes: formData.selectedTypes,
    customerTypes: formData.selectedCustomers,
    ecoMode: {
      enabled: formData.ecoEnabled,
      surcharge: formData.ecoSurcharge || 25,
      certified: 'EcoCert',
    },
    baseChecklist: formData.checklist,
    pricing: formData.pricing,
    recurringDiscounts: formData.recurringDiscounts,
    qualityGuarantee: {
      enabled: true,
      reportWindowHours: 24,
      reCleanFree: true,
      fullRefund: true,
    },
    serviceArea: formData.serviceArea,
    businessPackages: formData.packages.filter(p => p.enabled),
  };

  // Validation
  if (!cleaningProfile.verifications.idVerified) throw 'נדרשת ת"ז מאושרת';
  if (!cleaningProfile.verifications.backgroundChecked) throw 'נדרשת בדיקת רקע';
  if (cleaningProfile.verifications.referencesCount < 3) throw 'נדרשים לפחות 3 ממליצים';
  if (cleaningProfile.cleaningTypes.length === 0) throw 'בחרי לפחות סוג נקיון אחד';
  if (cleaningProfile.baseChecklist.length === 0) throw 'בנייה לפחות checklist אחד';

  // Save
  await firestore.collection('users').doc(userId).update({
    cleaningProfile: cleaningProfile,
  });

  // Trigger sync to public profile
  await syncCleaningProfileToListings(userId);
}
```

---

## ⚠️ Edge Cases & Validation

1. **המנקה לא בחרה תת-קטגוריה "נקיון"** → הבלוק לא מופיע
2. **המנקה ביטלה את "נקיון"** → הבלוק נעלם, אבל הנתונים נשמרים
3. **אין ת"ז מאושרת** → אי אפשר לאשר את הפרופיל
4. **אין בדיקת רקע** → אי אפשר לאשר את הפרופיל
5. **פחות מ-3 ממליצים** → אי אפשר לאשר את הפרופיל
6. **אין סוגי נקיון** → אי אפשר לשמור
7. **Checklist ריק** → אי אפשר לשמור
8. **Eco Mode מופעל ללא תוספת** → ברירת מחדל ₪25
9. **קטגוריה במחירון לא מולאה** → דרוש כל 4 הרמות

---

זה המפרט המלא לדף עריכת המנקה. עבור הצד של הלקוח - ראה `03_CLIENT_BOOKING_CLEANING.md`.
