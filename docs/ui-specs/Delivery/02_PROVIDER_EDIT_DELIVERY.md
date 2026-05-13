# 📝 Provider Edit Screen - Delivery | מסך עריכת השליח

> **קובץ זה הוא חלק מ-`01_MAIN_PROMPT_DELIVERY.md`** - קרא אותו קודם!

---

## ⛔ תזכורת קריטית: לא למחוק כלום!

המסך הזה כבר קיים. אתה **רק מוסיף בלוק חדש** מתחת לבחירת תת-קטגוריה "משלוחים".

**הסדר במסך:**
```
1. Header עם "←" ו"שמור" (קיים - לא נוגעים)
2. פרטים אישיים - שם, ניסיון, ✎ (קיים - לא נוגעים)
3. תמונת פרופיל (קיים - לא נוגעים)
4. אודות (קיים - לא נוגעים)
5. בלוק תת-קטגוריה - "משלוחים" (קיים - לא נוגעים)
   ↓ ↓ ↓
6. ✨ הבלוק החדש "הקריירה שלך" ← מתווסף כאן רק אם נבחר "משלוחים"!
   ↑ ↑ ↑
7. גלריית עבודות (קיים - לא נוגעים)
8. יומן זמינות (קיים - לא נוגעים)
9. כפתורי "תצוגה מקדימה" + "שמור שינויים" (קיים - לא נוגעים)
```

---

## 📍 מתי הבלוק החדש מופיע?

הבלוק "הקריירה שלך" מופיע **רק** במצב הבא:
- השליח נכנס לעריכת פרופיל
- בחר תת-קטגוריה "משלוחים" (`subcategory == 'delivery'`)

**אם השליח מבטל את בחירת "משלוחים":**
- הבלוק נעלם מה-UI
- הנתונים נשמרים ב-Firestore (במקרה שיחזור)

---

## 🎨 הבלוק החדש - מבנה כללי

### Container ראשי - Dark Premium
רקע `linear-gradient(135deg, #0A0E1A 0%, #151B2E 50%, #0F1420 100%)` עם 3 ambient orbs:
- Orb כתום ברקע ימני עליון
- Orb ירוק ברקע שמאלי אמצעי
- Orb סגול ברקע ימני תחתון

הבלוק מתחיל עם separator צהוב + טקסט "↓ הבלוק החדש - מתווסף רק אחרי 'משלוחים' ↓"

ואז 7 סקציות לפי הסדר:

### 🌟 Hero Story Mode (Section 0)
1. **תמונת פרופיל** עם conic-gradient glow זהוב
2. **Badge "🏆"** בפינה ימנית עליונה של התמונה
3. **כותרת** "הקריירה שלך" ב-gradient text (לבן → זהב)
4. **Subtitle** "כל מה שצריך כדי להרוויח יותר"
5. **2 Status badges**: "פעיל · מקבל הזמנות" + "Top 5 · ת"א"
6. **3 KPIs**: 1,247 משלוחים · ★ 4.92 דירוג · 22׳ ממוצע
7. **Upsell card**: "🚀 12 משלוחים לקפיצה למקום 1"

### 🔴 Section 1: מסמכים ורישיונות (חובה!)
- **Border אדום בולט** (1.5px solid rgba(220,38,38,0.4))
- 3 מסמכי חובה: תעודת זהות, רישיון נהיגה, ביטוח רכב
- כל מסמך עם אייקון gradient ירוק (מאושר) + badge "מאושר"
- אופציה להוסיף תעודה נוספת (dashed border)

### 🛵 Section 2: הצי שלי (Vehicles)
- 2 כרטיסים: קטנוע + רכב
- כל כרטיס עם: אייקון gradient זהוב, שם, שנה, דגם, משקל מקסימלי
- צ'קבוקס מאושר (מופעל)
- מטא-מידע: "📷 תמונות (N) · 📋 ביטוח אומת"
- אפשרות להוסיף רכב נוסף (dashed)

### 📦 Section 3: סוגי משלוחים
- Grid 2x3
- 4 סוגים פעילים: מסמכים, חבילה קטנה, בינונית, גדולה
- כל אחד עם gradient ירוק (green selected style) + מספר משלוחים השנה
- 2 אופציות "פוטנציאל": פרחים (+15), עוגות (+8) עם dashed border זהוב

### 👤 Section 4: סוגי לקוחות
- Grid 2x2
- 2 נבחרים (gradient לבן-שחור): פרטיים + עסקים
- 2 לא נבחרים: חנויות + מסעדות

### ⏰ Section 5: זמינות (3 אופציות)
- **⚡ משלוח מיידי** - רקע אדום + toggle ON + שדה תוספת ₪25
- **⏰ משלוח רגיל** - רקע אפור + toggle ON (ברירת מחדל)
- **🗓️ הזמנה מראש** - רקע סגול + toggle ON + **Badge "ייחודי!"** + hint "פי 2.4 הזמנות מעסקים"

### 📍 Section 6: אזורי שירות
- **בסיס פעילות**: input + אייקון mapping
- **אזורי כיסוי**: chips נבחרים (4 פעילים) + chips אפשריים (dashed)
- Info card ירוק: "בכיסוי שלך: 4 ערים · ~83% מהביקוש"

### 💰 Section 7: מחירון לפי משקל
- **Badge "שקיפות"** ירוק
- 4 שורות מחיר: מסמכים ₪35, קטנה ₪45, בינונית ₪65, גדולה ₪90
- תוספת ק"מ: ₪3.5 לכל ק"מ אחרי 5

### 📋 Section 8: הכללים שלך (Purple border!)
- **Border סגול בולט** (1.5px solid rgba(99,102,241,0.4))
- Header עם אייקון gradient סגול
- Info banner: "למה זה חשוב? פחות אי הבנות = יותר ★★★★★"
- **5 כללים מהירים** (3 מופעלים, 2 לא):
  - 🚫 לא אקח חבילות מסוכנות (אדום, ✓)
  - 📷 תיעוד תמונה (כתום, ✓)
  - 📱 התקשרות לפני הגעה (כחול, ✓)
  - ⚖️ שקילה לאישור משקל (ניטרלי, ✗)
  - 🌧️ משלוח גם בגשם (ניטרלי, ✗)
- **הוראות אישיות** - textarea עם border סגול + counter 500 תווים
- **Chips suggestions**: +חבילות שביר, +חשבון לעסק, +אזור הגבלה
- **Preview button**: "👀 תצוגה מקדימה ללקוחות"

### 💼 Section 9: חבילות לעסקים
- רקע gradient כחול כהה
- Hint: "💰 שליחים עם חבילות = פי 2.5 הכנסה"
- 2 חבילות פעילות: בייסיק ₪249 (5/חודש), פרו ₪599 (15/חודש)
- כפתור "+ הוסף חבילה"

ובסוף: separator צהוב + "↑ סוף הבלוק החדש ↑"

---

## 💾 Save Logic

```javascript
async function saveDeliveryProfile(userId, formData) {
  const deliveryProfile = {
    documents: formData.documents,
    vehicles: formData.vehicles.filter(v => v.enabled),
    deliveryTypes: formData.selectedTypes,
    customerTypes: formData.selectedCustomers,

    availability: {
      immediate: {
        enabled: formData.immediateEnabled,
        surcharge: formData.immediateSurcharge || 25,
      },
      regular: {
        enabled: formData.regularEnabled ?? true,
      },
      scheduled: {
        enabled: formData.scheduledEnabled,
      },
    },

    serviceArea: {
      baseLocation: formData.baseLocation,
      baseLocationGeo: formData.baseLocationGeo,
      coverageCities: formData.coverageCities,
    },

    pricing: formData.pricing,

    rules: {
      structuredRules: formData.rules
        .filter(r => r.enabled)
        .map(r => ({
          id: r.id,
          type: r.type,
          icon: r.icon,
          titleHe: r.titleHe,
          descHe: r.descHe,
          enabled: true,
          color: r.color,
        })),
      customRules: formData.customRules || '',
    },

    businessPackages: formData.packages.filter(p => p.enabled),
  };

  // Validation
  const requiredDocs = ['id_card', 'driver_license', 'vehicle_insurance'];
  for (const docType of requiredDocs) {
    const doc = deliveryProfile.documents.find(d => d.type === docType);
    if (!doc || !doc.verified) {
      throw `נדרש ${docType} מאושר`;
    }
  }

  if (deliveryProfile.vehicles.length === 0) {
    throw 'נדרש לפחות רכב אחד פעיל';
  }

  if (deliveryProfile.deliveryTypes.length === 0) {
    throw 'בחר לפחות סוג משלוח אחד';
  }

  // Save
  await firestore.collection('users').doc(userId).update({
    deliveryProfile: deliveryProfile,
  });

  // Trigger sync to public profile
  await syncDeliveryProfileToListings(userId);
}
```

---

## ⚠️ Edge Cases & Validation

1. **השליח לא בחר תת-קטגוריה "משלוחים"** → הבלוק לא מופיע
2. **השליח ביטל את "משלוחים"** → הבלוק נעלם, אבל הנתונים נשמרים
3. **אין ת"ז מאושרת** → אי אפשר לאשר את הפרופיל
4. **אין רישיון נהיגה** → אי אפשר לאשר את הפרופיל
5. **אין ביטוח** → אי אפשר לאשר את הפרופיל
6. **אין רכבים פעילים** → אי אפשר לשמור
7. **אין סוגי משלוחים** → אי אפשר לשמור
8. **חירום מופעל ללא תוספת** → ברירת מחדל ₪25
9. **טקסט כללים מעל 500 תווים** → לא מאפשר להמשיך לכתוב

---

## 🎨 Design Tokens (עבור Flutter)

### Container עם glassmorphism:
```dart
Container(
  decoration: BoxDecoration(
    color: Colors.white.withOpacity(0.04),
    border: Border.all(
      color: Colors.white.withOpacity(0.1),
      width: 1,
    ),
    borderRadius: BorderRadius.circular(22),
  ),
  // עטוף ב-BackdropFilter
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
    child: // ...
  ),
)
```

### Badges (Status pills):
```dart
// Green - Available
Container(
  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: Color(0xFF22C55E).withOpacity(0.2),
    border: Border.all(
      color: Color(0xFF4ADE80).withOpacity(0.3),
      width: 1,
    ),
    borderRadius: BorderRadius.circular(999),
  ),
  child: Row(
    children: [
      Container(
        width: 5, height: 5,
        decoration: BoxDecoration(
          color: Color(0xFF4ADE80),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(
            color: Color(0xFF4ADE80),
            blurRadius: 10,
          )],
        ),
      ),
      Text('פעיל · מקבל הזמנות', style: TextStyle(
        color: Color(0xFF4ADE80),
        fontSize: 9,
        fontWeight: FontWeight.w600,
      )),
    ],
  ),
)
```

### Number input (price field):
```dart
Container(
  decoration: BoxDecoration(
    color: Colors.black.withOpacity(0.3),
    border: Border.all(
      color: Colors.white.withOpacity(0.05),
      width: 1,
    ),
    borderRadius: BorderRadius.circular(7),
  ),
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  child: Row(
    children: [
      Text('₪', style: TextStyle(
        color: Colors.white.withOpacity(0.5),
        fontSize: 9,
      )),
      TextField(
        controller: priceController,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(border: InputBorder.none),
      ),
    ],
  ),
)
```

---

זה המפרט המלא לדף עריכת השליח. עבור הצד של הלקוח - ראה `03_CLIENT_BOOKING_DELIVERY.md`.
