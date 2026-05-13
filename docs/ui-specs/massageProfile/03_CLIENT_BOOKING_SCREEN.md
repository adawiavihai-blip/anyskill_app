# 🎨 Client Profile Booking Screen | מסך פרופיל הלקוח עם בלוק ההזמנה

> **קובץ זה הוא חלק מ-`01_MAIN_PROMPT.md`** - קרא אותו קודם!

---

## 🎯 מה הקובץ הזה מתאר

מפרט מלא של **בלוק "בנה את הטיפול שלך"** שמתווסף לדף פרופיל המעסה (צד הלקוח).
**אסור לשנות** את החלקים הקיימים - רק להוסיף את הבלוק החדש.

---

## 📍 מיקום הבלוק החדש

הבלוק "בנה את הטיפול שלך" מופיע **רק** במצב הבא:
- הלקוח נכנס לדף פרופיל של מעסה
- הקטגוריה של המעסה היא "עיסוי" (`category == 'massage'` או `subcategory == 'massage'`)
- למעסה יש `massageProfile` ב-Firestore

**מיקום במסך:**
```
1. Header (קיים - לא משנים)
2. Profile card (קיים - לא משנים)
3. גלריה + וידאו (קיים - לא משנים)
4. אודות (קיים - לא משנים)
↓ ↓ ↓
5. ✨ בנה את הטיפול שלך (חדש!) ← כאן מתווסף הבלוק
↑ ↑ ↑
6. השירות (קיים - לא משנים)
7. זמינות / יומן (קיים - לא משנים)
8. ביקורות (קיים - לא משנים)
9. Bottom CTA "בחר תאריך ושעה" (קיים, לא משנים אותו)
```

---

## 🎨 עיצוב הבלוק

### עטיפה ראשית
```dart
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFFFF8E7), Color(0xFFFEF3C7)],
    ),
    border: Border.all(color: Color(0xFFFBBF24), width: 1),
    borderRadius: BorderRadius.circular(20),
  ),
  padding: EdgeInsets.all(14),
)
```

### Header של הבלוק
```dart
Center(
  child: Text(
    '✨ בנה את הטיפול שלך',
    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Color(0xFF1A1A1A)),
  ),
)
SizedBox(height: 4)
Center(
  child: Text(
    'אילנה תכין הכל לפי הבחירות שלך',
    style: TextStyle(fontSize: 12, color: Color(0xFF8B8B85)),
  ),
)
```

### Smart Restore Banner (חדש - מופיע רק אם יש הזמנה קודמת)
```
┌─────────────────────────────────────┐
│ [⚡] ההעדפות מהפעם הקודמת    [השתמש] │
│     שוודי · 60 דק׳ · בית · ראש       │
└─────────────────────────────────────┘
```
- רקע: gradient שחור
- כפתור "השתמש" - לחיצה ממלאת את כל הסקציות אוטומטית

---

## 📋 סקציות הבלוק (8 סקציות)

### עקרונות עיצוב לכל סקציה
- כל סקציה בכרטיס לבן נפרד (rounded 20px)
- מספר ממוספר בצד ימין (1, 2, 3...) ברקע שחור
- כותרת בולטת + תיאור משני אפור
- בחירה אקטיבית = gradient שחור-כחול עמוק

---

### 1️⃣ סוג העיסוי

**מה מציג:** רק את `specialties` שהמעסה סימנה (1-14 סוגים).

**Layout:** Grid 3 עמודות, כל קלף 110x90 פיקסלים בערך.

**עיצוב כל קלף:**
```
┌──────────┐
│   [✓]    │  ← אם נבחר, badge לבן עם ✓
│  [Icon]  │  ← אייקון 36x36 ברקע פסטל מתאים
│  שוודי   │  ← שם
│  קלאסי   │  ← tagline קטן
└──────────┘
```

**Smart Tags:**
- אם זה הסוג שהלקוח בחר בהזמנה האחרונה → badge קטן "🔄 בחירה קודמת"
- אם זה הסוג הכי פופולרי אצל המעסה → badge "⭐ פופולרי"

**Default selection:** ההזמנה הקודמת של הלקוח, או הסוג הראשון ברשימה.

---

### 2️⃣ איפה?

**מה מציג:** רק את האופציות שהמעסה הפעילה ב-`serviceLocations`.

**Layout:** Grid 1x2 (אם שני המיקומים פעילים), אחרת 1x1.

**כרטיס "בבית הלקוח":**
```
┌──────────────────────┐
│ [✓]                  │
│ 🏠                   │
│ אצלי בבית            │
│ המעסה מגיע אליך      │
│ עד 30 דק׳ הגעה       │
└──────────────────────┘
```

**כרטיס "בקליניקה":**
```
┌──────────────────────┐
│                      │
│ 🏢                   │
│ בקליניקה             │
│ רחוב הרצל 15         │
│ 4.2 ק״מ ממך          │
└──────────────────────┘
```

**Distance Calculation:** השתמש ב-Geolocator package כדי לחשב מרחק מהמשתמש לקליניקה.

**Bonus Insight (smart):**
מתחת לכרטיסים, אם בית פעיל - הצג insight:
```
💡 לקוחות בוחרים בית פי 3 יותר אצל אילנה
```
(מבוסס על ניתוח הזמנות אמיתיות)

**אם רק אופציה אחת מסומנת אצל המעסה:**
- הצג רק אותה
- אל תאפשר ללקוח לבחור אחרת
- המראה: כרטיס יחיד שתופס רוחב מלא, מסומן כבר ✓

---

### 3️⃣ משך

**מה מציג:** רק את ה-`durations` שהמעסה הפעילה.

**Layout:** Pill segmented control (כמו iOS).

```
┌─────────────────────────────────┐
│  30   [60]   90   120          │
│ דק׳   ₪150  ₪210 ₪270          │
└─────────────────────────────────┘
```

- האופציה הנבחרת: רקע לבן עם shadow קטן
- האחרות: שקופות עם טקסט אפור
- מתחת לכל מספר - המחיר (לפי `durations[i].price`)

**Default:** 60 דקות (הכי פופולרי).

**Side label:**
```
3. משך                    הכי פופולרי: 60 דק׳
```

---

### 4️⃣ עוצמת לחץ

**מה מציג:** רק את `pressureLevels` שהמעסה תומכת בהן (1-3).

**Layout:** Slider עם 3 נקודות (אם 3 פעילות).

```
[🪶 ━━━━━━●━━━━━━ ✋ ━━━━━━━ 💪]
  עדין    בינוני (נבחר)    חזק
```

- פס gradient מירוק-כתום-אדום (light to strong)
- מסגרת שחורה עם רקע לבן + shadow
- אנימציה חלקה כשגוררים

**מתחת:**
```
┌──────────────────────────────────┐
│ לחץ נעים, מתאים לרוב האנשים     │  (טקסט מסביר לפי הבחירה)
└──────────────────────────────────┘
```

**אם רק עוצמה אחת זמינה:** הצג כתג בלבד, ללא slider.

---

### 5️⃣ איפה כואב?

**Header:**
```
5. איפה כואב?              [2 נבחרו]
   סמן ואילנה תתמקד שם
```

**Layout:** SVG של גוף אדם בצד + רשימת אזורים מסומנים בצד.

**8 אזורי הגוף:**
| ID | Hebrew | English |
|----|--------|---------|
| `neck` | צוואר | Neck |
| `shoulders` | כתפיים | Shoulders |
| `upper_back` | גב עליון | Upper back |
| `lower_back` | גב תחתון | Lower back |
| `legs` | רגליים | Legs |
| `arms` | ידיים | Arms |
| `head` | ראש | Head |
| `feet` | כפות רגליים | Feet |

**Body SVG:**
- גוף סטיילי, איור פשוט בצבע אפור-בז'
- כל אזור הוא `<path>` שניתן ללחוץ עליו
- אזורים נבחרים מודגשים בכתום `#F59E0B` עם אנימציית opacity (pulse)

**רשימה ימנית (chips):**
- כל אזור נבחר מופיע כ-chip עם נקודה כתומה
- מתחת: "+ הוסף אזור" (פותח את הרשימה המלאה)

**AI Suggestion (מתחת):**
```
✨ לפי הבחירה שלך - מומלץ "עיסוי ראש בסיום" להקלת מתח בצוואר
```
- רקע ירוק בהיר #ECFDF5
- מבוסס על הקשר בין האזור הנבחר לתוספות הזמינות
- לחיצה על ה-suggestion - מסמנת את התוספת אוטומטית

---

### 6️⃣ תוספות

**מה מציג:** רק את ה-`addOns` שהמעסה אישרה (עם `enabled: true`).

**Layout:** רשימה אנכית, כל תוספת:

```
┌───────────────────────────────────────┐
│ [Icon] שמן ארומתרפיה        +₪25 [□] │
│        לבנדר · ניאולי · תפוז          │
└───────────────────────────────────────┘
```

**אם נבחר:**
```
┌──────────────────────────────────────────────┐
│ [מומלץ עבורך] ← badge קטן בפינה            │
│ [Icon] עיסוי ראש בסיום       +₪15  [✓]     │
│        10 דקות סיום מושלמות                │
└──────────────────────────────────────────────┘
```
- רקע: gradient cream `linear-gradient(135deg, #FAFAF6 0%, #F5F2EC 100%)`
- Border: 1.5px solid #1A1A1A
- אייקון על רקע gradient

**Smart Recommendations:**
- אם הלקוח סימן "צוואר" באזורי כאב → המלץ על "עיסוי ראש בסיום" (badge "מומלץ עבורך")
- אם בחר "ספורט" כסוג העיסוי → המלץ על "Theragun" ו"מתיחות מסייעות"
- אם בחר "הריון" → אל תציג CBD oil (לא מתאים)

---

### 7️⃣ 🎁 חבילות הנחה (חדש!)

**מה מציג:** רק אם המעסה הגדירה `discountPackages` עם `enabled: true`.

**Layout:** קלפים אופקיים עם scroll אם יש יותר מאחד.

**עיצוב כרטיס חבילה:**
```dart
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
    ),
    border: Border.all(color: Color(0xFFFBBF24), width: 1.5),
    borderRadius: BorderRadius.circular(16),
  ),
)
```

תוכן הכרטיס:
```
┌────────────────────────────────────┐
│ 🎁 [חדש]                          │
│ חבילת 5 טיפולים                    │
│                                    │
│ ✓ 5 טיפולים מלאים                  │
│ ✓ הנחה 15% על כל טיפול             │
│ ✓ תוקף 6 חודשים                    │
│                                    │
│ ₪750 → ₪637                       │
│ חיסכון של ₪113                     │
│                                    │
│ [קנה חבילה]                       │
└────────────────────────────────────┘
```

**Behavior:**
- לחיצה על "קנה חבילה" → פותחת flow תשלום נפרד (לא חלק מההזמנה הרגילה)
- אם הלקוח כבר קנה חבילה → הצג: "יש לך 3/5 טיפולים נותרים בחבילה"

**אם אין חבילות:** הסקציה לא מופיעה כלל.

---

### 8️⃣ אווירה

**א. מוזיקה (4 אופציות):**
```
[🧘 רגועה ✓]  [🌊 טבע]  [🎵 קלאסי]  [🤫 שקט]
```
- האופציה הנבחרת: gradient שחור עם 4 פסי waveform animated
- ברירת מחדל: רגועה

**ב. שיחה במהלך:**
```
[💬 בכיף לדבר]  [🤫 מינימלי ✓]
```
- מציג רק את האופציות ש-`conversationStyles` של המעסה כולל

---

### 9️⃣ הערות נוספות (אופציונלי)

```
+ משהו שכדאי שאילנה תדע?
  הודעה אישית · נשלחת מאובטחת

┌──────────────────────────────────────┐
│ לדוגמה: יש לי רגישות באזור הצוואר... │
└──────────────────────────────────────┘

[+ פציעה ישנה] [+ הריון] [+ אלרגיה לשמן]
```

- שדה טקסט פתוח
- 3 chips של נושאים נפוצים שמוסיפים לטקסט אוטומטית

---

## 💰 Bottom Booking Bar (עליון לכפתור הקיים)

מעל כפתור "בחר תאריך ושעה" הקיים, הוסף סיכום:

```
┌────────────────────────────────────────────┐
│ סך הכל                       משך כולל     │
│ ₪165   ₪̶1̶9̶0̶   חיסכון ₪25      70 דק׳     │
│                                            │
│ [שוודי] [בית] [60 דק׳] [בינוני]          │
│ [צוואר · גב עליון] [+ עיסוי ראש]         │
└────────────────────────────────────────────┘

[🔘 בחר תאריך ושעה →]   ← הכפתור הקיים, לא משנים!
```

**עיצוב הסיכום:**
- רקע gradient עדין `linear-gradient(135deg, #FBFAF6 0%, #F5F2EC 100%)`
- Border 1px solid #EAE7DF
- מחיר גדול ומוקצה
- אם יש חיסכון - הצג מחיר מקור מחוק + badge ירוק

**Trust Signals מתחת לכפתור:**
```
🔒 תשלום מאובטח · ביטול חינם עד 24 שעות לפני
```

---

## 🔘 חיבור לכפתור "בחר תאריך ושעה" הקיים

**חשוב מאוד:**
1. **לא לבנות יומן חדש**
2. **להשתמש ביומן הקיים באפליקציה**
3. בלחיצה על הכפתור הקיים:
   - קח את כל הבחירות מהבלוק (`massagePreferences`)
   - שלח אותן כפרמטר ליומן הקיים
   - היומן ימשיך כרגיל - מציג שעות פנויות לפי הזמינות של המעסה
   - בסוף ההזמנה - שמור הכל יחד ל-`bookings` collection

```dart
void onCalendarPressed() {
  final preferences = MassagePreferences(
    massageType: selectedType,
    location: selectedLocation,
    duration: selectedDuration,
    addOns: selectedAddOns,
    pressureLevel: selectedPressure,
    focusAreas: selectedFocusAreas,
    notes: notesController.text,
    musicPreference: selectedMusic,
    conversationStyle: selectedConversation,
  );

  // נווט ליומן הקיים עם הפרמטר החדש
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ExistingCalendarScreen(
      providerId: widget.providerId,
      massagePreferences: preferences,  // ← פרמטר חדש שמועבר
      totalPrice: calculatedTotal,
    ),
  ));
}
```

---

## 🎨 Design System Quick Reference

### Colors used in this screen
```dart
const sectionBg = Color(0xFFFFFFFF);
const screenBg = Color(0xFFFBFAF6);
const heroAmber1 = Color(0xFFFFF8E7);
const heroAmber2 = Color(0xFFFEF3C7);
const heroAmberBorder = Color(0xFFFBBF24);

// Selected state
const selectedGradient = LinearGradient(
  colors: [Color(0xFF1A1A1A), Color(0xFF2D3142)],
);

// Pastels for icon backgrounds (per specialty type)
const pastels = {
  'swedish': Color(0xFFE1F5EE),
  'deep_tissue': Color(0xFFFFF1ED),
  'pregnancy': Color(0xFFFFF0F5),
  'hot_stones': Color(0xFFFFF8E7),
  'sports': Color(0xFFEBF5FF),
  'couples': Color(0xFFF3E8FF),
  // ...
};
```

### Animation Guidelines
- **Selection feedback:** 200ms ease-out scale 1.0 → 0.95 → 1.0
- **Section transitions:** 300ms fade-in when section becomes relevant
- **Pressure slider:** 100ms snap to position
- **Body SVG focus areas:** continuous pulse (2s cycle, opacity 0.4 → 0.8)
- **Music waveform:** infinite bounce animation

### Microinteractions
- כל לחיצה על כרטיס/כפתור → haptic feedback קל (`HapticFeedback.lightImpact()`)
- הוספת תוספת → animated price update בסיכום התחתון
- בחירת אזור כאב על ה-SVG → אנימציית "ripple" קצרה

---

## 🌐 Localization Keys

```json
{
  "build_treatment_title": "בנה את הטיפול שלך",
  "build_treatment_subtitle": "{providerName} תכין הכל לפי הבחירות שלך",

  "smart_restore_title": "ההעדפות מהפעם הקודמת",
  "smart_restore_btn": "השתמש",

  "section_massage_type": "סוג העיסוי",
  "section_massage_type_helper": "בחר אחד",

  "section_location": "איפה?",
  "location_home_main": "אצלי בבית",
  "location_home_desc": "המעסה מגיע אליך · עד 30 דק׳ הגעה",
  "location_clinic_main": "בקליניקה",
  "location_clinic_desc_template": "{address} · {distance} ק״מ ממך",
  "location_insight_template": "💡 לקוחות בוחרים בית פי 3 יותר אצל {providerName}",

  "section_duration": "משך",
  "duration_popular": "הכי פופולרי: 60 דק׳",

  "section_pressure": "עוצמת לחץ",
  "pressure_light": "עדין",
  "pressure_medium": "בינוני",
  "pressure_strong": "חזק",
  "pressure_helper_light": "מגע עדין ורגוע",
  "pressure_helper_medium": "לחץ נעים, מתאים לרוב האנשים",
  "pressure_helper_strong": "לחץ עוצמתי לשחרור עמוק",

  "section_focus_areas": "איפה כואב?",
  "section_focus_areas_helper": "סמן ואילנה תתמקד שם",
  "focus_areas_count": "{count} נבחרו",
  "focus_area_neck": "צוואר",
  "focus_area_shoulders": "כתפיים",
  "focus_area_upper_back": "גב עליון",
  "focus_area_lower_back": "גב תחתון",
  "focus_area_legs": "רגליים",
  "focus_area_arms": "ידיים",
  "focus_area_head": "ראש",
  "focus_area_feet": "כפות רגליים",
  "focus_area_add": "+ הוסף אזור",
  "focus_areas_ai_suggestion": "✨ לפי הבחירה שלך - מומלץ \"{addonName}\" להקלת מתח באזור",

  "section_addons": "תוספות",
  "section_addons_helper": "שדרג את החוויה",
  "section_addons_recommended_for_you": "מומלץ עבורך",

  "section_packages": "חבילות הנחה",
  "section_packages_savings": "חיסכון של ₪{amount}",
  "section_packages_buy": "קנה חבילה",
  "section_packages_remaining": "יש לך {used}/{total} טיפולים נותרים בחבילה",

  "section_ambiance": "אווירה",
  "ambiance_subtitle": "המקום שלך, החוקים שלך",
  "ambiance_music_label": "מוזיקת רקע",
  "music_calm": "רגועה",
  "music_nature": "טבע",
  "music_classical": "קלאסי",
  "music_silent": "שקט",
  "ambiance_conversation_label": "שיחה במהלך הטיפול",
  "conversation_chatty": "בכיף לדבר",
  "conversation_minimal": "מינימלי",

  "section_notes_title": "משהו שכדאי ש{providerName} תדע?",
  "section_notes_subtitle": "הודעה אישית · נשלחת מאובטחת",
  "section_notes_placeholder": "לדוגמה: יש לי רגישות באזור הצוואר, פציעת ספורט ישנה...",
  "notes_chip_old_injury": "+ פציעה ישנה",
  "notes_chip_pregnancy": "+ הריון",
  "notes_chip_oil_allergy": "+ אלרגיה לשמן",

  "summary_total": "סך הכל",
  "summary_duration": "משך כולל",
  "summary_savings": "חיסכון ₪{amount}",
  "summary_minutes": "{count} דק׳",
  "btn_choose_date_time": "בחר תאריך ושעה",
  "trust_signal": "🔒 תשלום מאובטח · ביטול חינם עד 24 שעות לפני"
}
```

---

## 💾 State Management

```dart
class BuildYourTreatmentState extends ChangeNotifier {
  String? massageType;
  String? location; // 'home' | 'clinic'
  int duration = 60;
  String pressure = 'medium';
  List<String> focusAreas = [];
  List<String> selectedAddOns = [];
  String? musicPreference = 'calm';
  String? conversationStyle = 'minimal';
  String additionalNotes = '';

  // Computed
  double get totalPrice {
    final basePrice = _calculateBasePrice();
    final addOnsPrice = _calculateAddOnsPrice();
    final travelFee = location == 'home' ? (provider.massageProfile.serviceLocations.home.travelFee ?? 0) : 0;
    return basePrice + addOnsPrice + travelFee;
  }

  int get totalDurationMinutes {
    int extra = 0;
    if (selectedAddOns.contains('head_massage')) extra += 10;
    if (selectedAddOns.contains('post_nap')) extra += 20;
    return duration + extra;
  }

  // Methods
  void selectMassageType(String type) { ... }
  void toggleAddOn(String id) { ... }
  void toggleFocusArea(String id) { ... }
  void restoreFromLastBooking(MassagePreferences last) { ... }

  MassagePreferences toBookingData() { ... }
}
```

---

## 🤖 Smart Suggestions Logic

```dart
class MassageSmartSuggestions {

  // Recommend addon based on focus areas
  static List<String> recommendedAddOns(List<String> focusAreas) {
    final recommendations = <String>{};
    if (focusAreas.contains('neck')) recommendations.add('head_massage');
    if (focusAreas.contains('lower_back')) recommendations.add('hot_stones');
    if (focusAreas.contains('feet')) recommendations.add('foot_scrub');
    return recommendations.toList();
  }

  // Recommend addon based on massage type
  static List<String> typeRecommendations(String massageType) {
    switch (massageType) {
      case 'sports': return ['theragun', 'assisted_stretching', 'cold_compress'];
      case 'deep_tissue': return ['hot_stones', 'theragun'];
      case 'pregnancy': return ['aromatherapy_oil', 'hot_towels']; // NOT cbd_oil
      case 'aromatherapy': return ['aromatherapy_oil', 'scalp_oil_treatment'];
      default: return [];
    }
  }

  // Filter out incompatible addons
  static List<String> filterIncompatible(String massageType, List<String> addons) {
    if (massageType == 'pregnancy') {
      addons.removeWhere((id) => ['cbd_oil', 'theragun', 'cupping'].contains(id));
    }
    return addons;
  }
}
```

---

## ⚠️ Edge Cases

1. **המעסה אין לה `massageProfile`** → הצג את הפרופיל הקיים בלי הבלוק
2. **רק סוג עיסוי אחד מוצע** → סמן אותו אוטומטית, אבל הצג אותו (כדי שהלקוח יידע)
3. **רק מיקום אחד מוצע** → סמן אותו אוטומטית, הצג כקלף יחיד ברוחב מלא
4. **אין תוספות מוצעות** → הסתר את הסקציה לחלוטין
5. **אין חבילות הנחה** → הסתר את הסקציה לחלוטין
6. **המעסה הסירה אופציה שהלקוח בחר בעבר** → אל תציג את "Smart Restore" עם הבחירה ההיא
7. **מחיר 0 (אם יש באג)** → הצג "מחיר ייקבע" במקום "₪0"

---

## ✅ Acceptance Criteria - בלוק הלקוח

- [ ] הבלוק מופיע **רק** למעסים בקטגוריית עיסוי
- [ ] הבלוק מופיע במיקום הנכון (בין "אודות" ל"השירות")
- [ ] רק האופציות שהמעסה אישרה - מוצגות
- [ ] בחירות מסונכרנות בזמן אמת לסיכום בתחתית
- [ ] לחיצה על "בחר תאריך ושעה" - **לא** בונה יומן חדש, אלא קורא ליומן הקיים
- [ ] כל הבחירות נשמרות יחד עם ההזמנה ב-`bookings` collection
- [ ] Smart Restore עובד אם יש הזמנה קודמת
- [ ] AI suggestions עובדות לפי הלוגיקה
- [ ] חבילות הנחה מוצגות אם הוגדרו ע"י המעסה
- [ ] אנימציות חלקות (200-300ms ease-out)
- [ ] Haptic feedback בלחיצות
- [ ] תמיכה מלאה ב-RTL ובdark mode

---

🎉 זהו! עם 3 הקבצים האלה Claude Code יכול לבנות את כל הפיצ'ר.
