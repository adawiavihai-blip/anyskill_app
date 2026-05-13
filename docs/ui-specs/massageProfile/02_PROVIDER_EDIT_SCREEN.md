# 📝 Provider Edit Screen | מסך עריכת פרופיל המעסה

> **קובץ זה הוא חלק מ-`01_MAIN_PROMPT.md`** - קרא אותו קודם!

---

## 🎯 מה הקובץ הזה מתאר

מפרט מלא של **התוספת החדשה** למסך עריכת הפרופיל של נותן השירות (המעסה).
**אסור לשנות** את החלקים הקיימים - רק להוסיף את הבלוק החדש.

---

## 📍 מיקום הבלוק החדש

הבלוק "הגדרות עיסוי" מופיע **רק** במצב הבא:
- המעסה נכנס/ה לעריכת פרופיל
- בחר/ה תת-קטגוריה "עיסוי" (`subcategory == 'massage'`)

**מיקום:** מתחת לבחירת התת-קטגוריה, ומעל שאר הסקציות הקיימות (גלריה, אודות, יומן וכו').

**אם המעסה מבטל/ת את בחירת "עיסוי":**
- הבלוק נעלם מה-UI
- אבל הנתונים נשמרים ב-Firestore (במקרה שהמעסה יחזור לבחור)

---

## 🎨 עיצוב הבלוק

### Banner צהוב למעלה (תמיד מופיע ראשון בבלוק)
```dart
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFFFF8E7), Color(0xFFFEF3C7)],
    ),
    border: Border.all(color: Color(0xFFFBBF24), width: 1),
    borderRadius: BorderRadius.circular(16),
  ),
  child: Row(
    children: [
      Text('💡', style: TextStyle(fontSize: 22)),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('הגדרות ייעודיות לעיסוי',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF78350F))),
          Text('הלקוחות יראו רק את מה שתסמני כאן',
            style: TextStyle(fontSize: 11, color: Color(0xFF92400E))),
        ],
      ),
    ],
  ),
)
```

---

## 📋 סקציה 1: סוגי טיפולים שאני מציעה

### Header
- כותרת: "סוגי טיפולים שאני מציעה" (15px, weight 500)
- תיאור: "סמני את כל הסוגים שאת יודעת לעשות. רק אלו יוצגו ללקוחות." (11px, color #999)
- בפינה: badge ירוק "X / 14" (כמה סומנו מתוך הסה"כ)

### 14 סוגי הטיפולים (Grid 2x7)

| ID | Hebrew | English | Icon | Tagline (HE) |
|----|--------|---------|------|--------------|
| `swedish` | שוודי | Swedish | 🌿 | קלאסי, רגיעה |
| `deep_tissue` | רקמות עמוק | Deep Tissue | 💪 | שחרור, עוצמתי |
| `pregnancy` | הריון | Pregnancy | 🤰 | בטוח, עדין |
| `hot_stones` | אבנים חמות | Hot Stones | 🪨 | חמימות, עומק |
| `sports` | ספורט | Sports | ⚡ | התאוששות |
| `couples` | זוגי | Couples | 👫 | חוויה משותפת |
| `aromatherapy` | ארומטרפי | Aromatherapy | 🌸 | שמנים אתריים |
| `thai` | תאילנדי | Thai | 🇹🇭 | מתיחות |
| `reflexology` | רפלקסולוגיה | Reflexology | 👣 | כפות רגליים |
| `shiatsu` | שיאצו | Shiatsu | 🥢 | לחיצה יפנית |
| `lymphatic` | לימפטי | Lymphatic | 🩹 | ניקוז |
| `ayurveda` | איורוודה | Ayurveda | 🧘 | הודי מסורתי |
| `reiki` | רייקי | Reiki | 🤲 | אנרגטי |
| `infant` | תינוקות | Infant | 👶 | עדין |

### State Design
- **Selected:** רקע gradient שחור `linear-gradient(135deg, #1A1A1A 0%, #2D3142 100%)` + check mark לבן
- **Unselected:** רקע לבן + border אפור #EAE7DF + אייקון על רקע פסטל

### כפתור "+ הוסף סוג טיפול אישי"
מתחת לרשת - מאפשר למעסה להוסיף סוג טיפול שלא ברשימה. פותח דיאלוג עם שם + אייקון + תיאור קצר.

---

## 📋 סקציה 2: איפה את נותנת טיפולים

### Header
- כותרת: "איפה את נותנת טיפולים"
- תיאור: "בחרי באילו אופציות הלקוחות יוכלו לבחור"

### 2 כרטיסים גדולים (Grid 1x2)

**כרטיס 1: בבית הלקוח**
- אייקון: 🏠
- כותרת: "בבית הלקוח"
- תיאור: "אני מגיעה אליו"

**כרטיס 2: בקליניקה שלי**
- אייקון: 🏢
- כותרת: "בקליניקה שלי"
- תיאור: "הלקוח מגיע אליי"

### Conditional Fields - מופיעים רק אם הכרטיס סומן

#### אם בית סומן ✓ - פותח קופסה אפורה בהירה:
```
🏠 פרטים על שירות בבית

רדיוס שירות (ק״מ ממיקומך)
[Slider: 1-50]  15 ק״מ

מחיר נסיעה (אופציונלי)
₪ [20]  לכיוון אחד
```

#### אם קליניקה סומנה ✓ - פותח קופסה אפורה בהירה:
```
🏢 פרטים על הקליניקה

כתובת מלאה (תוצג ללקוחות)
📍 [רחוב הרצל 15, תל אביב]

קומה / דירה (אופציונלי)
[קומה 3, דירה 12]

💡 הכתובת תוצג ללקוחות שיבחרו "בקליניקה" (notification ירוק)
```

### חשוב!
- ניתן לסמן את **שניהם** (האפליקציה תציג ללקוח שתי האופציות)
- ניתן לסמן רק **אחד** (האפליקציה תציג ללקוח רק את האופציה שנבחרה)
- חייב לסמן **לפחות אחד** (validation)

---

## 📋 סקציה 3: תוספות שאני מציעה ⭐ (הסקציה הכי ארוכה)

### Header
- כותרת: "תוספות שאני מציעה"
- תיאור: "סמני, שני מחיר אם רוצה, או הוסיפי משלך"
- Badge ירוק: "X / 18"

### 18 התוספות מאורגנות ב-4 קטגוריות

#### ⭐ מומלצים (3 תוספות)
| ID | Hebrew | English | Icon | Recommended Price | Description |
|----|--------|---------|------|-------------------|-------------|
| `aromatherapy_oil` | שמן ארומתרפיה | Aromatherapy oil | 🌸 | 25 | לבנדר, ניאולי, תפוז, מנטה |
| `hot_stones` | אבנים חמות | Hot stones | 🪨 | 40 | להרפיה עמוקה |
| `head_massage` | עיסוי ראש בסיום | Head massage finish | 💆 | 15 | 10 דקות נוספות |

#### 🌿 ארומתרפיה ושמנים (2 תוספות)
| ID | Hebrew | English | Icon | Recommended Price | Description |
|----|--------|---------|------|-------------------|-------------|
| `cbd_oil` | שמן CBD | CBD oil | 🌱 | 50 | להקלת כאבים ודלקות |
| `hot_towels` | מגבות חמות | Hot towels | 🔥 | 20 | חוויית ספא מלאה |

#### ⚕️ טכניקות טיפוליות (4 תוספות)
| ID | Hebrew | English | Icon | Recommended Price | Description |
|----|--------|---------|------|-------------------|-------------|
| `cupping` | כוסות רוח (Cupping) | Cupping | ⚫ | 35 | שחרור עמוק של רקמות |
| `theragun` | Theragun (אקדח עיסוי) | Theragun | 🔫 | 30 | טיפול פרקוסיבי |
| `cold_compress` | קומפרסים קרים | Cold compress | ❄️ | 20 | הקלה על דלקות |
| `assisted_stretching` | מתיחות מסייעות | Assisted stretching | 🌿 | 25 | שיפור גמישות |

#### ✨ טיפולים מעשירים (5 תוספות)
| ID | Hebrew | English | Icon | Recommended Price | Description |
|----|--------|---------|------|-------------------|-------------|
| `scalp_oil_treatment` | טיפול קרקפת בשמן חם | Hot oil scalp treatment | 💧 | 35 | 15 דקות הזנה לשיער |
| `foot_scrub` | פילינג רגליים | Foot scrub | 🦶 | 25 | מנטה ולימון |
| `post_nap` | 20 דק׳ מנוחה אחרי | 20 min nap | 😴 | 20 | להישאר על המיטה ולנמנם |
| `face_mask` | מסכת פנים | Face mask | 🌹 | 40 | בעת העיסוי |
| `body_scrub` | פילינג גוף | Body scrub | 💎 | 45 | סוכר + שמני אגוז |

### עיצוב כל תוספת

**Unselected:**
```
[Icon 38x38]  שם התוספת              מחיר מומלץ ₪25  [□]
              תיאור קצר
```

**Selected:**
```
[Icon 38x38]  שם התוספת          [₪ 25]              [✓]
              תיאור קצר          ↑ ניתן לעריכה
```
- רקע gradient בהיר `linear-gradient(135deg, #FAFAF6 0%, #F5F2EC 100%)`
- Border 1.5px solid #1A1A1A

### כפתור "+ הוסף תוספת אישית שלך"
בתחתית הסקציה - גדול, gradient שחור.
פותח דיאלוג:
- שם התוספת
- אייקון (בחירה מתוך 12 emoji או העלאה)
- תיאור קצר
- מחיר

### Subcategories Display
הצג כותרות קטנות לכל קטגוריה (10px, weight 500, color #1A1A1A) מעל הקבוצה.

---

## 📋 סקציה 4: משכי טיפול ומחירים

### Header
- כותרת: "משכי טיפול ומחירים"
- תיאור: "מחירי בסיס לטיפול שוודי · ניתן לעדכן לכל סוג בנפרד"

### 4 משכים (Stack vertical)

```
[30 דק׳]    ₪ [100]    [✓]
[60 דק׳]    ₪ [150]    [✓]
[90 דק׳]    ₪ [210]    [✓]
[120 דק׳]   ₪ [270]    [✓]
```

- כל שורה: רקע #FAF8F2 + border-radius 12px
- שדה מחיר עם רקע לבן + border #EAE7DF
- צ'קבוקס שחור בצד

### Validation
- חייב לאפשר **לפחות משך אחד**
- מחיר חייב להיות > 0

---

## 📋 סקציה 5: 🎁 חבילות הנחה (חדש!)

### Header
- כותרת: "חבילות הנחה"
- Badge חדש בצבע ענבר: "💰 משפר נאמנות"
- תיאור: "צרי חבילות שמקנות הנחה ללקוחות חוזרים"

### עיצוב חבילה קיימת

```dart
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
    ),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Color(0xFFFBBF24), width: 1.5),
  ),
  // ...
)
```

תוכן:
```
🎁 חבילת 5 טיפולים                    [פעיל ✓]

5 טיפולים  ·  הנחה 15%  ·  תוקף 6 חודשים

מחיר רגיל: ₪750         מחיר חבילה: ₪637
                        חיסכון: ₪113

[ערוך]  [מחק]
```

### כפתור "+ הוסף חבילה חדשה"
פותח דיאלוג:
- שם החבילה (לדוגמה: "חבילת 10 טיפולים")
- מספר טיפולים [10]
- אחוז הנחה [25%]
- תוקף בימים [365]
- צ'קבוקס "פעיל"

### חבילות מובנות (suggestions)
הצג למעלה 3 חבילות מומלצות שהמעסה יכולה להוסיף בלחיצה אחת:
- "חבילת 3 טיפולים · 10% הנחה · תוקף 90 ימים"
- "חבילת 5 טיפולים · 15% הנחה · תוקף 180 ימים"
- "חבילת 10 טיפולים · 25% הנחה · תוקף 365 ימים"

---

## 📋 סקציה 6: העדפות ושירות

### א. עוצמות לחץ שאני יכולה לתת
- כותרת: "עוצמות לחץ שאני יכולה לתת"
- 3 כפתורים (Multi-select):
  - 🪶 עדין (light)
  - ✋ בינוני (medium)
  - 💪 חזק (strong)
- Default: כל השלוש מסומנות

### ב. סגנון שיחה
- כותרת: "סגנון שיחה"
- 2 כפתורים (Multi-select):
  - 💬 בכיף לדבר (chatty)
  - 🤫 מינימלי (minimal)
- Default: שניהם מסומנים (המעסה גמישה)

---

## 🔘 Bottom Bar (כפתורים בתחתית)

```
[תצוגה מקדימה 👁]    [שמור שינויים]
   (1 חלק)              (1.5 חלק)
```

- "תצוגה מקדימה" - פותח preview של איך הלקוח יראה את הפרופיל
- "שמור שינויים" - שומר ל-Firestore + מסנכרן לדף הפרופיל הציבורי

---

## 💾 Save Logic

```javascript
async function saveMassageProfile(userId, formData) {
  const massageProfile = {
    specialties: formData.selectedSpecialties,  // array of IDs
    serviceLocations: {
      home: {
        enabled: formData.homeEnabled,
        radiusKm: formData.homeRadiusKm || 10,
        travelFee: formData.homeTravelFee || 0,
      },
      clinic: {
        enabled: formData.clinicEnabled,
        address: formData.clinicAddress || '',
        floor: formData.clinicFloor || '',
      }
    },
    addOns: formData.addOns.filter(a => a.enabled).map(a => ({
      id: a.id,
      enabled: true,
      customPrice: a.customPrice,
      isCustom: a.isCustom || false,
      // אם isCustom - שמור גם את: nameHe, nameEn, icon, description
    })),
    durations: formData.durations.filter(d => d.enabled),
    pressureLevels: formData.pressureLevels,
    conversationStyles: formData.conversationStyles,
    discountPackages: formData.packages.filter(p => p.enabled),
  };

  // Validation
  if (massageProfile.specialties.length === 0) throw 'בחרי לפחות סוג טיפול אחד';
  if (!massageProfile.serviceLocations.home.enabled && !massageProfile.serviceLocations.clinic.enabled) {
    throw 'בחרי לפחות מיקום אחד (בית או קליניקה)';
  }
  if (massageProfile.serviceLocations.clinic.enabled && !massageProfile.serviceLocations.clinic.address) {
    throw 'הזיני כתובת לקליניקה';
  }
  if (massageProfile.durations.length === 0) throw 'בחרי לפחות משך טיפול אחד';

  // Save
  await firestore.collection('users').doc(userId).update({
    massageProfile: massageProfile,
  });

  // Trigger sync to public profile
  await syncMassageProfileToProviderProfile(userId);
}
```

---

## 🌐 Localization Keys

```json
{
  "edit_massage_settings_banner_title": "הגדרות ייעודיות לעיסוי",
  "edit_massage_settings_banner_desc": "הלקוחות יראו רק את מה שתסמני כאן",

  "edit_specialties_title": "סוגי טיפולים שאני מציעה",
  "edit_specialties_desc": "סמני את כל הסוגים שאת יודעת לעשות. רק אלו יוצגו ללקוחות.",
  "edit_specialties_add_custom": "+ הוסף סוג טיפול אישי",

  "edit_locations_title": "איפה את נותנת טיפולים",
  "edit_locations_desc": "בחרי באילו אופציות הלקוחות יוכלו לבחור",
  "edit_locations_home": "בבית הלקוח",
  "edit_locations_home_desc": "אני מגיעה אליו",
  "edit_locations_clinic": "בקליניקה שלי",
  "edit_locations_clinic_desc": "הלקוח מגיע אליי",
  "edit_locations_home_details": "פרטים על שירות בבית",
  "edit_locations_radius_label": "רדיוס שירות (ק״מ ממיקומך)",
  "edit_locations_travel_fee_label": "מחיר נסיעה (אופציונלי)",
  "edit_locations_clinic_details": "פרטים על הקליניקה",
  "edit_locations_address_label": "כתובת מלאה (תוצג ללקוחות)",
  "edit_locations_floor_label": "קומה / דירה (אופציונלי)",
  "edit_locations_address_hint": "הכתובת תוצג ללקוחות שיבחרו 'בקליניקה'",

  "edit_addons_title": "תוספות שאני מציעה",
  "edit_addons_desc": "סמני, שני מחיר אם רוצה, או הוסיפי משלך",
  "edit_addons_recommended": "מומלצים",
  "edit_addons_aromatherapy": "ארומתרפיה ושמנים",
  "edit_addons_therapeutic": "טכניקות טיפוליות",
  "edit_addons_enriching": "טיפולים מעשירים",
  "edit_addons_recommended_price": "מחיר מומלץ ₪{price}",
  "edit_addons_add_custom": "הוסף תוספת אישית שלך",

  "edit_durations_title": "משכי טיפול ומחירים",
  "edit_durations_desc": "מחירי בסיס לטיפול שוודי · ניתן לעדכן לכל סוג בנפרד",

  "edit_packages_title": "חבילות הנחה",
  "edit_packages_badge": "משפר נאמנות",
  "edit_packages_desc": "צרי חבילות שמקנות הנחה ללקוחות חוזרים",
  "edit_packages_add": "+ הוסף חבילה חדשה",
  "edit_packages_sessions": "{count} טיפולים",
  "edit_packages_discount": "הנחה {percent}%",
  "edit_packages_validity": "תוקף {days} ימים",
  "edit_packages_active": "פעיל",
  "edit_packages_savings": "חיסכון: ₪{amount}",
  "edit_packages_suggested": "חבילות מומלצות",

  "edit_preferences_title": "העדפות ושירות",
  "edit_preferences_pressure": "עוצמות לחץ שאני יכולה לתת",
  "edit_preferences_pressure_light": "עדין",
  "edit_preferences_pressure_medium": "בינוני",
  "edit_preferences_pressure_strong": "חזק",
  "edit_preferences_conversation": "סגנון שיחה",
  "edit_preferences_chatty": "בכיף לדבר",
  "edit_preferences_minimal": "מינימלי",

  "edit_btn_preview": "תצוגה מקדימה",
  "edit_btn_save": "שמור שינויים"
}
```

---

## ⚠️ Edge Cases & Validation

1. **המעסה לא בחר/ה תת-קטגוריה "עיסוי"** → הבלוק לא מופיע
2. **המעסה ביטל/ה את "עיסוי"** → הבלוק נעלם, אבל הנתונים נשמרים (לא נמחקים) ב-Firestore
3. **המעסה החזיר/ה את בחירת "עיסוי"** → הבלוק חוזר עם כל הנתונים שהיו
4. **שום סוג טיפול לא סומן** → אי אפשר לשמור (validation error)
5. **שום מיקום לא סומן** → אי אפשר לשמור
6. **קליניקה סומנה אבל אין כתובת** → אי אפשר לשמור
7. **שום משך טיפול לא סומן** → אי אפשר לשמור
8. **מחיר 0 או שלילי** → לא אפשרי, מינימום ₪1
9. **תוספת ללא מחיר** → השתמש במחיר המומלץ אוטומטית

---

זהו המפרט המלא לדף עריכת המעסה. עבור הצד של הלקוח - ראה `03_CLIENT_BOOKING_SCREEN.md`.
