# 🎨 Client Profile Screen | מסך הלקוח עם בלוק ההזמנה החכם

> **קובץ זה הוא חלק מ-`01_MAIN_PROMPT_PESTCONTROL.md`** - קרא אותו קודם!

---

## ⛔ תזכורת קריטית: לא למחוק כלום!

המסך הזה כבר קיים. אתה **רק מוסיף בלוק חדש** בין "אודות" ל"השירות".

**הסדר במסך:**
```
1. Header עם "→" "♡" (קיים - לא נוגעים)
2. Profile card - תמונה, ✓ כחול, "נותן שירות", "הדברה", סטטיסטיקות (קיים - לא נוגעים)
3. גלריית עבודות + וידאו היכרות (קיים - לא נוגעים)
4. אודות (קיים - לא נוגעים)
   ↓ ↓ ↓
5. ✨ הבלוק החדש - "בנה את הטיפול שלך" + "מה צריך לדעת לפני" ← מתווסף כאן!
   ↑ ↑ ↑
6. השירות - פגישה קצרה ₪280, מורחב ₪392, מלאה ₪504 (קיים - לא נוגעים)
7. זמינות / יומן (קיים - לא נוגעים)
8. ביקורות 4.80 ★ (קיים - לא נוגעים)
9. כפתור תחתון "בחר תאריך ושעה" (קיים - לא נוגעים)
```

---

## 📍 מתי הבלוק החדש מופיע?

הבלוק מופיע **רק** במצב הבא:
- הלקוח נכנס לדף פרופיל של נותן שירות
- הקטגוריה של נותן השירות היא "הדברה" (`category == 'pest_control'` או `subcategory == 'pest_control'`)
- לנותן השירות יש `pestControlProfile` ב-Firestore

---

## 🎨 הבלוק החדש - מבנה כללי

הבלוק מתחיל עם separator צהוב + טקסט "↓ הבלוק החדש - מתווסף בין אודות להשירות ↓"

ואז הסקציות לפי הסדר:

1. 🌿 **Hero card** - "בנה את הטיפול שלך"
2. 🤖 **AI Identification card** - לזיהוי מזיק מתמונה
3. ✨ **AI Result card** - אחרי זיהוי, מציג מה זוהה + Match Score
4. 📋 **Treatment Instructions** - "מה צריך לדעת לפני" (חדש!)
5. **Section 1: איפה ומתי?**
6. **Section 2: סוג הטיפול**
7. **Section 3: פרטים נוספים**
8. **🎁 חבילות תחזוקה**
9. **📍 מה קורה בשכונה שלך** (Smart insights)
10. **💰 Sticky bottom: סיכום + כפתור הזמנה ירוק**

ובסוף: separator צהוב + "↑ סוף הבלוק החדש ↑"

---

## 🌿 סקציה 0: Hero Card

**עיצוב:** רקע לבן, border-radius 22px, padding 16px, box-shadow עדין.

```
[● זמין · 45 דק׳]  [⬢ רישיון משרד הגנ"ס]

       בנה את הטיפול שלך
   3 שלבים פשוטים · אורן יקבל הכל מוכן
```

**Tags:**
- "● זמין · 45 דק׳" - gradient ירוק `#14532D → #16A34A` (מבוסס על `availability` ו-`averageArrivalTime`)
- "⬢ רישיון משרד הגנ"ס" - רקע `#EFF6FF`, טקסט `#1E40AF`

---

## 🤖 סקציה 1: AI Identification Card

**עיצוב:** רקע gradient כחול `linear-gradient(135deg, #1E3A8A 0%, #1E40AF 100%)`, border-radius 16px, padding 14px.

```
[🤖] לא יודע מה זה?              [AI חכם]
     צלם והAI יזהה תוך 2 שניות

┌──────────────────┬──────────────────┐
│  📷  צלם עכשיו  │  🖼️  העלה תמונה  │
└──────────────────┴──────────────────┘
```

### Behavior:
- **לחיצה על "צלם עכשיו"**: פותח מצלמה (image_picker)
- **לחיצה על "העלה תמונה"**: פותח גלריה
- אחרי בחירת תמונה: שולח ל-Cloud Function `identifyPestFromImage` עם base64 של התמונה
- מחכה לתשובה מ-Gemini Vision (~2-3 שניות)
- מציג loading state (skeleton)
- אחרי קבלת תשובה: מציג את "AI Result Card" למטה

---

## ✨ סקציה 2: AI Result Card (מופיע אחרי זיהוי)

**עיצוב:** רקע gradient ירוק `linear-gradient(135deg, #F0FDF4, #DCFCE7)`, border `#BBF7D0`.

```
┌────────────────────────────────────┐
│ ┌────┐                              │
│ │ 🪲 │  תיקן גרמני                  │
│ │ AI │  זוהה ע"י AI · 96% התאמה   │
│ └────┘                              │
│                                     │
│ ┌─────────────────────────────────┐│
│ │ ✓ אורן טיפל ב-87 מקרים השנה   ││
│ │ ✓ הדברה ירוקה - בטוח לחתול שלך││
│ │ ✓ זמין היום · 45 דק׳ אליך      ││
│ └─────────────────────────────────┘│
└────────────────────────────────────┘
```

### Match Score Calculation:
```javascript
function calculateMatchScore(pestType, providerProfile) {
  let score = 0;

  // האם המדביר מטפל בסוג המזיק הזה?
  if (providerProfile.pestTypes.includes(pestType)) score += 40;

  // כמה מקרים דומים טיפל השנה?
  const similarCases = await getCasesCount(providerId, pestType);
  if (similarCases > 50) score += 30;
  else if (similarCases > 20) score += 20;
  else if (similarCases > 5) score += 10;

  // האם זמין כעת?
  if (providerProfile.availability.available247) score += 15;

  // דירוג ממוצע
  if (providerProfile.avgRating >= 4.7) score += 15;

  return Math.min(score, 99);
}
```

### "למה אורן הכי מתאים לך:" - 3 סיבות דינמיות:
לוגיקה לבחירת הסיבות:
1. **טיפל ב-X מקרים השנה** - מ-Firestore aggregate
2. **הדברה ירוקה - בטוח ל[ילדים/חיות]** - אם המדביר מציע ירוק + הלקוח סימן בני בית
3. **זמין היום · X דק׳ אליך** - אם זמין

---

## 📋🌟 סקציה 3: Treatment Instructions (חדש - הכי חשוב!)

זו **הסקציה הכי חשובה החדשה** - מציגה ללקוח מה ההוראות לפני שהוא מזמין.

**עיצוב:** רקע לבן, border-radius 20px, padding 14px, **border סגול בולט (1.5px solid #6366F1) + box-shadow סגול בהיר**.

### Header:
```
[📋]  מה צריך לדעת לפני                [חשוב!]
      הוראות מאורן · קרא לפני ההזמנה
```

### כרטיסי הוראות (מופיעים רק אם המדביר סימן אותן):

#### 🚪 פינוי הבית (אדום)
```
┌─────────────────────────────────────┐
│ [🚪]  פינוי הבית · 4 שעות           │
│       בני הבית לא יוכלו להיות בבית │
│       במשך 4 שעות אחרי הטיפול      │
└─────────────────────────────────────┘
```
- **רקע:** `linear-gradient(135deg, #FEE2E2, #FECACA)`, border `#FCA5A5`
- **טקסט הראשי:** `#991B1B`, weight 600
- **טקסט המשני:** `#B91C1C`

#### 🐕 הרחקת חיות מחמד (כתום)
```
┌─────────────────────────────────────┐
│ [🐕]  הרחקת חיות מחמד · 8 שעות     │
│       חתולים, כלבים וציפורים -      │
│       הרחק לפחות 8 שעות            │
└─────────────────────────────────────┘
```
- **רקע:** `linear-gradient(135deg, #FEF3C7, #FDE68A)`, border `#FBBF24`

#### 💧 לא לשטוף (כחול)
```
┌─────────────────────────────────────┐
│ [💧]  לא לשטוף · שבוע                │
│       לא לשטוף משטחים בהם בוצע      │
│       טיפול במשך שבוע               │
└─────────────────────────────────────┘
```
- **רקע:** `linear-gradient(135deg, #DBEAFE, #BFDBFE)`, border `#93C5FD`

#### 🪟 לאוורר (ירוק)
```
┌─────────────────────────────────────┐
│ [🪟]  לאוורר · 30 דקות              │
│       לפתוח חלונות לאוורור בעת     │
│       חזרה הביתה                    │
└─────────────────────────────────────┘
```
- **רקע:** `linear-gradient(135deg, #DCFCE7, #BBF7D0)`, border `#86EFAC`

### Mapping של duration → טקסט בעברית:
```dart
const durationMap = {
  'evacuate_home': {
    '2_hours': '2 שעות',
    '4_hours': '4 שעות',
    '8_hours': '8 שעות',
  },
  'remove_pets': {
    '4_hours': '4 שעות',
    '8_hours': '8 שעות',
    '24_hours': '24 שעות',
  },
  'no_washing': {
    '3_days': '3 ימים',
    '1_week': 'שבוע',
    '2_weeks': 'שבועיים',
  },
  'ventilation': {
    '30_min': '30 דקות',
    '1_hour': 'שעה',
  },
};
```

### הערה אישית מהמדביר (אם קיימת):
```
┌─────────────────────────────────────┐
│ 💬 הערה אישית מאורן                 │
│ ─────────────────────────────────── │
│ לאחר חזרה הביתה, מומלץ לנקות      │
│ משטחי עבודה במטבח עם מים בלבד.    │
│ במקרה של ריח חזק, ניתן ליצור      │
│ איתי קשר ב-24 שעות הראשונות       │
│ ללא עלות.                          │
└─────────────────────────────────────┘
```
- **רקע:** `linear-gradient(135deg, #FAFAFA, #F5F5F5)`
- **border-right:** 3px solid `#6366F1`

### ✅ Confirmation Checkbox (חובה!):
```
┌─────────────────────────────────────┐
│ ✓ קראתי והבנתי - אני מאשר את      │
│   ההוראות                       [✓]│
└─────────────────────────────────────┘
```

**Logic:**
- `instructionsAcknowledged` = false בהתחלה
- הלקוח חייב לסמן לפני שיכול להזמין
- אם לא סומן - כפתור "הזמן עכשיו" disabled (אפור)
- כשסומן - שדה `instructionsAcknowledged: true` נשמר עם timestamp

---

## 📍 סקציה 4: איפה ומתי? (מספר 1)

```
[1]  איפה ומתי?                  [✓ מוכן]
     מילאנו עבורך · לחץ לשנות
```

### Location summary card (smart - מילאו אוטומטית מהפרופיל הקיים של הלקוח):
```
┌─────────────────────────────────────┐
│ [📍]  דירה · 3-4 חדרים          [✎]│
│       בית הכרם, ירושלים · 2 ק"מ    │
└─────────────────────────────────────┘
```

### Urgency selector (Grid 2x2):
**עיצוב כל אופציה:**

#### 🚨 חירום (Selected: רקע אדום)
```
[● חירום]  ← tag למעלה
[🚨]
תוך שעה
+₪150
```
- gradient `#DC2626 → #B91C1C`

#### ⚡ היום (Default selected)
```
[✓]  ← בפינה
[⚡]
היום · אחה"צ
14:00-18:00
```
- gradient `#1a1a1a → #2D3142`
- ברירת מחדל מסומן

#### 📅 השבוע (לא נבחר)
- רקע לבן + border אפור

#### 🗓️ מתישהו (לא נבחר)
- רקע לבן + border אפור

### Smart Nudge (מתחת):
```
[⚡] 8 הזמנות בשעה האחרונה אצל אורן · רוץ!
```
- רקע gradient `#FEF3C7 → #FDE68A`
- מעודד הזמנה מהירה (FOMO)

---

## 🌿 סקציה 5: סוג הטיפול (מספר 2)

```
[2]  סוג הטיפול
     AI בחר את הכי מתאים לך
```

### Recommended treatment (גדול וירוק):
```
[✨ הכי מתאים לך]  ← tag למעלה

┌─────────────────────────────────────┐
│ [🌿]  הדברה ירוקה            [✓]   │
│       בטוח · ילדים, חיות, הריון    │
│       [חזרה אחרי 30 דק׳]            │
└─────────────────────────────────────┘
```
- **רקע:** `linear-gradient(135deg, #DCFCE7, #BBF7D0)`, border 1.5px `#16A34A`

### Show more (מתחתית):
```
+ ראה 2 שיטות נוספות (ריסוס רגיל, חום)
```
- לחיצה מציגה את שאר השיטות שהמדביר מציע

---

## 👨‍👩‍👧 סקציה 6: פרטים נוספים (מספר 3)

```
[3]  פרטים נוספים
     אופציונלי · משפר את השירות
```

### בני בית מיוחדים (Multi-select chips):

```
בני בית מיוחדים (אורן יתאים)
[👶 ילדים ✓] [🐕 חתול ✓] [🤰] [🧴] [🐠] [🌱] [+ עוד]
```

**Selected:** `bg: linear-gradient(#DCFCE7, #BBF7D0)`, border 1.5px `#16A34A`, color `#166534`
**Unselected:** רקע לבן, border אפור

### תוספת מומלצת (Recommended add-on):

```
[✨ מומלץ]  ← tag

┌──────────────────────────────────────┐
│ [🛡️]  אחריות מורחבת 6 חודשים +₪80 │
│       חזרה חינם אם המזיק חוזר   [✓]│
└──────────────────────────────────────┘
```
- **רקע:** `linear-gradient(135deg, #FAFAF6, #F5F2EC)`, border 1.5px `#1a1a1a`
- ברירת מחדל מסומן (להגדיל AOV)

---

## 💬 סקציה 7: שאלות לפני ההזמנה?

```
[💬]  שאלות לפני ההזמנה?
      קבל תשובה מיידית מאורן

[🐱 בטוח לחתול שלי?] [⏱️ כמה זמן?] [📋 איך מתכוננים?]

┌──────────────────────────────────────┐
│ ✏️ שאל את אורן משהו...           [→]│
└──────────────────────────────────────┘
```

**FAQ Buttons:** 3 שאלות מוכנות, לחיצה שולחת אותן ל-AI Chat (Gemini)

**שדה חופשי:** הלקוח יכול לשאול כל שאלה.

---

## 🎁 סקציה 8: חבילות תחזוקה (אופציונלי)

```
🎁 חבילות תחזוקה            [חוסך 30%]

┌──────────┬──────────┬──────────┐
│חד פעמי   │ פופולרי  │  חודשי   │
│ ₪290     │ ₪199    │  ₪149    │
│3 חו׳    │חיסכון₪364│ לעסקים   │
└──────────┴──────────┴──────────┘
```

- **חד פעמי:** רקע לבן
- **רבעוני (פופולרי):** רקע gradient שחור עם tag צהוב "פופולרי"
- **חודשי:** רקע לבן

---

## 📍 סקציה 9: מה קורה בשכונה שלך (Smart Insights)

```
📍 מה קורה בשכונה שלך

🏠 [3 דירות בבית הכרם] · אורן טיפל השבוע    היום
🪲 [67% עליה] בפניות על ג׳וקים החודש        טרנד
⭐ [דנה כהן] דרגה את אורן 5 כוכבים          לפני שעה
```

- **כרטיס ירוק** (חיובי) עם border-right `#16A34A`
- **כרטיס כתום** (טרנד) עם border-right `#F97316`
- **כרטיס כחול** (חברתי) עם border-right `#3B82F6`

---

## 💰 Sticky Bottom Bar (חשוב!)

**עיצוב:** רקע gradient כהה `linear-gradient(135deg, #1a1a1a, #2D3142)`, border-radius 18px.

```
┌──────────────────────────────────────┐
│ מחיר סופי                            │
│ ₪370   ✓ ללא הפתעות     משך ~90 דק׳│
│                                      │
│ [🪲 תיקן גרמני] [⚡ היום] [🌿 ירוק] │
│ [🛡️ +6 חו׳ אחריות]                  │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│      הזמן עכשיו · ₪370          →   │
└──────────────────────────────────────┘
🔒 תשלום אחרי · 📋 דוח דיגיטלי · ↩️ ביטול חינם
```

### כפתור הזמנה (חשוב!):
- **גודל:** רוחב מלא, padding 16px, border-radius 16px
- **רקע:** `linear-gradient(135deg, #16A34A, #15803D)` - **ירוק זוהר**
- **box-shadow:** `0 4px 16px rgba(22,163,74,0.25)` - הילה ירוקה
- **טקסט:** "הזמן עכשיו · ₪{price}" (כולל המחיר!)
- **font-weight:** 600
- **icon:** "→" בצד שמאל

### Disabled state (אם לא סומן ההוראות):
- אם `instructionsAcknowledged === false` → כפתור disabled עם opacity 0.5
- טקסט מתחת: "אנא אשר את ההוראות למעלה כדי להמשיך"

### Trust Signals (3 chips קטנים מתחת):
- 🔒 תשלום אחרי
- 📋 דוח דיגיטלי
- ↩️ ביטול חינם 4 שעות

---

## 🔘 חיבור לכפתור "בחר תאריך ושעה" הקיים

**חשוב:** השתמש ביומן הקיים, לא בנה חדש!

```dart
void onBookNowPressed() {
  // Validate
  if (!instructionsAcknowledged) {
    showSnackbar('אנא אשר את ההוראות לפני ההזמנה');
    return;
  }

  // Build preferences object
  final preferences = PestControlPreferences(
    pestTypeIdentified: aiResult?.pestType,
    aiIdentificationData: aiResult,
    selectedPestType: selectedPestType,
    urgency: selectedUrgency,
    location: selectedLocation,
    size: selectedSize,
    treatmentMethod: selectedMethod,
    specialHouseholdMembers: selectedMembers,
    addOns: selectedAddOns,
    additionalNotes: notesController.text,
    instructionsAcknowledged: true,
    instructionsAcknowledgedAt: DateTime.now(),
  );

  // Navigate to existing calendar (לא בונים חדש!)
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ExistingCalendarScreen(
      providerId: widget.providerId,
      pestControlPreferences: preferences,
      totalPrice: calculatedTotal,
    ),
  ));
}
```

---

## 🤖 Gemini AI Integration - Client Side

```dart
class GeminiPestIdentificationService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<PestIdentificationResult> identifyPest(File imageFile) async {
    // Convert to base64
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    // Call Cloud Function (which uses Gemini, NOT Claude!)
    final callable = _functions.httpsCallable('identifyPestFromImage');
    final result = await callable.call({
      'imageBase64': base64Image,
    });

    return PestIdentificationResult.fromJson(result.data);
  }
}

class PestIdentificationResult {
  final String pestType;
  final String pestTypeHe;
  final double confidence;
  final List<String> alternativeMatches;
  final String urgencyLevel;
  final String description;
  final String treatmentRecommendation;

  PestIdentificationResult.fromJson(Map<String, dynamic> json)
    : pestType = json['pestType'],
      pestTypeHe = json['pestTypeHe'],
      confidence = json['confidence'].toDouble(),
      alternativeMatches = List<String>.from(json['alternativeMatches']),
      urgencyLevel = json['urgencyLevel'],
      description = json['description'],
      treatmentRecommendation = json['treatmentRecommendation'];
}
```

---

## 💾 State Management

```dart
class PestBookingState extends ChangeNotifier {
  // AI identification
  PestIdentificationResult? aiResult;
  File? identifiedImage;
  bool isIdentifying = false;

  // User selections
  String? selectedPestType;
  String selectedUrgency = 'today';
  String selectedLocation = 'apartment';
  String selectedSize = 'full_apartment';
  String selectedTreatmentMethod = 'green';
  List<String> selectedSpecialMembers = [];
  List<String> selectedAddOns = ['extended_warranty_6m']; // default
  String additionalNotes = '';

  // 🆕 Instructions
  bool instructionsAcknowledged = false;

  // Computed
  double get totalPrice {
    double base = provider.basePricing[locationToKey(selectedLocation)] ?? 290;
    double addOnsTotal = selectedAddOns.fold(0, (sum, id) => sum + getAddOnPrice(id));
    double emergencyFee = selectedUrgency == 'emergency'
      ? provider.availability.emergencyService.additionalFee
      : 0;
    return base + addOnsTotal + emergencyFee;
  }

  bool get canBook => instructionsAcknowledged;

  // Methods
  void identifyPestFromImage(File image) async { ... }
  void selectPestType(String type) { ... }
  void toggleAddOn(String id) { ... }
  void acknowledgeInstructions() {
    instructionsAcknowledged = true;
    notifyListeners();
  }

  PestControlPreferences toBookingData() { ... }
}
```

---

## ⚠️ Edge Cases

1. **למדביר אין `pestControlProfile`** → הצג את הפרופיל הקיים בלי הבלוק
2. **AI לא הצליח לזהות מזיק** → הצג "לא הצלחנו לזהות, אנא בחר ידנית"
3. **המדביר לא מטפל בסוג שהAI זיהה** → הצג "אורן לא מטפל בזה, מומלץ לחפש מדביר אחר"
4. **המדביר אין הוראות מוגדרות** → הסתר את סקציית "מה צריך לדעת לפני"
5. **המדביר אין חבילות** → הסתר את הסקציה
6. **חירום סומן אבל המדביר לא תומך** → הסתר את אופציית החירום
7. **לכידת נחשים בלי רישיון** → אל תציג את האופציה ללקוח
8. **הלקוח לא אישר הוראות** → כפתור הזמנה disabled

---

## ✅ Acceptance Criteria - בלוק הלקוח

- [ ] הבלוק מופיע **רק** למדבירים בקטגוריית הדברה
- [ ] הבלוק מופיע במיקום הנכון (בין "אודות" ל"השירות")
- [ ] AI Identification עובד עם Gemini Vision API (לא Claude!)
- [ ] **🆕 בלוק "מה צריך לדעת לפני" מופיע בולט** עם סגול
- [ ] **🆕 Checkbox "אני מאשר את ההוראות"** מונע הזמנה אם לא סומן
- [ ] רק האופציות שהמדביר אישר - מוצגות
- [ ] בחירות מסונכרנות בזמן אמת לסיכום בתחתית
- [ ] לחיצה על "הזמן עכשיו" - **לא** בונה יומן חדש, אלא קורא ליומן הקיים
- [ ] כל הבחירות נשמרות יחד עם ההזמנה ב-`bookings` collection
- [ ] `instructionsAcknowledged` נשמר עם timestamp
- [ ] Match Score מחושב דינמית
- [ ] Smart insights מתעדכנים מ-Firestore
- [ ] תמיכה מלאה ב-RTL ובdark mode
- [ ] Haptic feedback בלחיצות

---

## 💾 בסיום העבודה - חובה לשמור!

**אחרי שסיימת את כל הפיתוח, חובה לשמור את כל הקבצי MD מהפרויקט הזה:**

1. שמור את 3 הקבצים ב-`/docs/pest_control_upgrade/`:
   - `01_MAIN_PROMPT_PESTCONTROL.md`
   - `02_PROVIDER_EDIT_PESTCONTROL.md`
   - `03_CLIENT_BOOKING_PESTCONTROL.md`

2. עדכן את `CLAUDE.md` עם section חדש:
   ```markdown
   ## Section 32: Pest Control CSM (Category-Specific Module)
   - Provider edit block: pest_control_settings_block.dart
   - Client booking block: pest_booking_block.dart
   - AI integration: Gemini Vision (NOT Claude API)
   - 🆕 Treatment Instructions feature
   - All files in /docs/pest_control_upgrade/
   ```

3. רץ `flutter analyze` ווודא 0 issues

4. תכין סיכום של מה נעשה (כמו שעשית עם עיסוי):
   - כמה files נוצרו
   - אילו קבצים שונו
   - אילו features הוטמעו
   - Validation passed

---

🎉 זהו! עם 3 הקבצים האלה Claude Code יכול לבנות את כל הפיצ'ר ברמה עולמית.

**זכור הכי חשוב: לא למחוק שום דבר! רק להוסיף 2 בלוקים חדשים במיקומים המדויקים.**
