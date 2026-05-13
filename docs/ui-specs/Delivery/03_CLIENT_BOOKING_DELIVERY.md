# 🎨 Client Profile Screen - Delivery | דף הלקוח (שלח עם דני)

> **קובץ זה הוא חלק מ-`01_MAIN_PROMPT_DELIVERY.md`** - קרא אותו קודם!

---

## ⛔ תזכורת קריטית: לא למחוק כלום!

המסך הזה כבר קיים. אתה **רק מוסיף בלוק חדש** בין "אודות" ל"השירות".

**הסדר במסך:**
```
1. Header עם "→" "♡" "↗" (קיים - לא נוגעים)
2. Profile card - תמונה, ✓ כחול, "נותן שירות", "שליחויות", סטטיסטיקות (קיים - לא נוגעים)
3. גלריית עבודות + וידאו היכרות (קיים - לא נוגעים)
4. אודות (קיים - לא נוגעים)
   ↓ ↓ ↓
5. ✨ הבלוק החדש - "שלח עם דני" ← מתווסף כאן!
   ↑ ↑ ↑
6. השירות (קיים - לא נוגעים)
7. זמינות / יומן (קיים - לא נוגעים)
8. ביקורות (קיים - לא נוגעים)
9. כפתור תחתון "בחר תאריך ושעה" (קיים - לא נוגעים)
```

---

## 📍 מתי הבלוק החדש מופיע?

הבלוק מופיע **רק** במצב הבא:
- הלקוח נכנס לדף פרופיל של נותן שירות
- הקטגוריה של נותן השירות היא "משלוחים" (`category == 'delivery'` או `subcategory == 'delivery'`)
- לנותן השירות יש `deliveryProfile` ב-Firestore

---

## 🎨 הבלוק החדש - מבנה כללי (Dark Premium)

### Container ראשי - Dark Base
רקע `linear-gradient(135deg, #0A0E1A 0%, #151B2E 50%, #0F1420 100%)` עם 3 ambient orbs בצבעים כתום, סגול, ירוק.

הבלוק מתחיל עם separator צהוב + טקסט "↓ בלוק 'שלח עם דני' ↓"

### סקציות לפי הסדר:

1. 🌟 **Hero Story Mode** - "שלח עם דני"
2. 🔁 **Express Reorder** (אופציונלי - אם יש הזמנה קודמת)
3. 🗺️ **המסלול שלך** (מפה + כתובות + voice button)
4. 📦 **מה שולחים?** (4 סוגי חבילות + AI רכב + תיאור)
5. ⏰ **מתי?** (4 אופציות תזמון)
6. 🎯 **איך למסור?** (מסירה ליד / בדלת + הוראות)
7. ➕ **שדרוגים חכמים** (2 אופציות - ללא ביטוח)
8. 📋 **איש קשר במסירה** (+ phone masking)
9. ⚡ **הפעילות של דני** (3 משלוחים אחרונים)
10. 💼 **חבילות לעסקים** (3 tiers)
11. 💰 **Sticky bottom**: סיכום + כפתור ירוק

ובסוף: separator צהוב + "↑ סוף הבלוק ↑"

---

## 🌟 Section 0: Hero Story Mode

**עיצוב:** padding 20px סביב, text-align center.

### תמונת פרופיל יוקרתית:
- **Size**: 90x90
- **Outer glow**: radial gradient כתום מטושטש
- **Conic gradient ring**: `conic-gradient(from 0deg, #F59E0B, #FBBF24, #F59E0B)` 
- **Profile**: gradient זהוב עם אות "ד" בלבן
- **Badge sign**: circle ירוק עם check לבן (או הילה זהובה עם 🏆 למקצוענים)

### Badges:
```
[● זמין · 8 דק׳ אליך]  [🎯 94% דיוק]
```
- Badge 1: ירוק עם dot מהבהב glow
- Badge 2: כחול עם "🎯 94% דיוק מסירות"

### Title (gradient text!):
```dart
Text(
  'שלח עם דני',
  style: TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
    foreground: Paint()..shader = LinearGradient(
      colors: [Colors.white, Color(0xFFFCD34D)],
    ).createShader(Rect.fromLTWH(0, 0, 200, 40)),
  ),
)
```

### Subtitle:
"הדרך החכמה לשלוח משהו חשוב" - בצבע `rgba(255,255,255,0.55)`

### 3 KPIs (עם separators):
```
1,247 | ★ 4.92 | 22׳
משלוחים | דירוג | ממוצע
```
- Separators: 1px height 20, `rgba(255,255,255,0.1)`
- Numbers: font 14px, weight 700, color white
- הדירוג ★ בזהב (#FCD34D)

---

## 🔁 Section 1: Express Reorder (Conditional)

**מופיע רק** אם ללקוח יש הזמנה קודמת עם אותו שליח.

**עיצוב:** glassmorphism עם border-radius 20px.

```
⚡ אקספרס - משלוח כמו אתמול

[🔁 דבר דני] [📝 מסמך לעו"ד רפי]
             הרצל 88 · ₪50 →
```

- Circle indicator סגול עם 🔁 בפינה שמאל-עליונה
- Icon 📝 בכרטיס
- כותרת + subtitle + price
- Arrow ← בלחיצה הולך ישר להזמנה

---

## 🗺️ Section 2: המסלול שלך (עם Live Map!)

### Header:
```
[1]  המסלול שלך              [🎤 קולי]
     דני מכיר את האזור מצוין
```

### Live Map Container:
**גודל:** רוחב מלא, height 150px
**רקע:** `linear-gradient(135deg, #1E3A5F 0%, #1E2C4F 100%)`
**תוכן**:

1. **Streets pattern** - SVG grid מעומעם
2. **LIVE badge** (top-right): ירוק עם pulse dot
3. **🛵 Courier tracker** (top-left): gradient כתום עם "דני · 600 מטר ממך"
4. **Animated courier marker** (middle): circle כתום עם 🛵 + pulse halo
5. **Pickup marker** (A, top-right area): ירוק
6. **Delivery marker** (B, bottom-left area): אדום
7. **Dashed route line** זהובה מונפשת בין A ל-B
8. **Bottom badges**: "8.4 ק"מ · 22׳" + "מתקרב אליך →"

### Addresses (מתחת למפה):
```
[A]  איסוף · 14:00 [אוטומטי]
     דיזנגוף 50, תל אביב
     דירה 4, קומה 2 · קוד: 1234
     ─ ─ ─ (dotted line)
     🛵 8.4 ק"מ · ~22 דק'
     ─ ─ ─
[B]  מסירה · ~14:30
     הרצל 88, רמת גן
     משרד 12, קומה 5
```

### Smart Hint (bottom):
```
💡 דני ביצע 87% מהמשלוחים שלו לרמת גן השבוע
```
רקע סגול עם `rgba(99,102,241,0.1)`

---

## 📦 Section 3: מה שולמים?

### Header:
```
[2]  מה שולחים?
     AI בחר את הרכב הכי מתאים
```

### Package Types Grid (4 options):
**Grid 4x1**:
- 📝 **מסמכים** (נבחר) - gradient זהוב מלא
- 📦 **קטנה** - רקע שקוף
- 📮 **בינונית** - רקע שקוף
- 🎁 **גדולה** - רקע שקוף

כל אחד עם: icon, name, weight spec.
**הנבחר**: יש checkmark בפינה + background gradient כתום + shadow זהוב.

### AI Vehicle Recommendation Card:
**רקע:** `linear-gradient(135deg, rgba(245,158,11,0.12), rgba(217,119,6,0.05))` עם border כתום.

```
[🤖]  AI ממליץ: קטנוע  [חוסך ₪15 + 7 דק']
      מהיר יותר בפקקים · בטוח למסמכים

[🛵 קטנוע ✓]    [🚗 רכב]
   ● 8 דק'          15 דק'
```

- Header עם אייקון gradient כתום + כותרת + badge יוקרתי
- Grid 2x1 של אופציות רכב (קטנוע נבחר עם border כתום + shadow)

### Description Field:
```
✏️ תיאור החבילה                 [🎤 דבר]

[Placeholder] "חוזה חתום לסקירה דחופה..."

[⚠️ שביר] [🤐 רגיש] [📸 לתעד] [🆔 חתימה]
```

- Textarea מאוחר
- Voice button בפינה
- 4 chips tags (ניתן לבחור כמה)

---

## ⏰ Section 4: מתי?

### Grid 2x2:

```
[⚡ עכשיו]      [⏰ תוך שעה ✓]
   30 דק'+₪25      14:00-15:00

[📅 היום]       [🗓️ מתוזמן]
   בחלון           ⭐ייחודי
```

- **עכשיו**: gradient אדום + badge "חירום" עם pulse dot
- **תוך שעה**: gradient זהוב + checkmark (default)
- **היום**: רקע שקוף
- **מתוזמן**: border סגול + badge "⭐ ייחודי" + hint "מחר 7:00"

### Confirmation banner:
```
[⚡] דני יאשר תוך 30 שניות
```
רקע ירוק עם circle badge ירוק מאיר.

---

## 🎯 Section 5: איך למסור?

### Header:
```
🎯  איך למסור?
    בחר את הסוג המועדף
```

### Grid 2x1:
```
[🤝 מסירה ליד ✓]     [🚪 השאר בדלת]
   דני ימתין 5 דק'     +תמונה אוטו'
```

- **מסירה ליד** (default): gradient ירוק + border ירוק + checkmark
- **השאר בדלת**: רקע שקוף

### Special Instructions:
```
💬 הוראות מיוחדות לדני

[Placeholder] "קומה 5, משרד 12 - לחדר הקבלה"
```

---

## ➕ Section 6: שדרוגים חכמים (ללא ביטוח!)

### Header:
```
+  שדרוגים חכמים
   לחבילות שחשובות לך
```

### 2 אופציות בלבד (הסרנו את הביטוח):

**1. תיעוד + GPS (Popular - Default)**
```
[✨ פופולרי]
[📸] תיעוד + GPS              +₪5
     תמונה אוטומטית במסירה     [✓]
```
- Background: gradient זהוב
- Icon: gradient כתום
- Badge "✨ פופולרי" בפינה
- Default checked

**2. SMS למקבל (Free)**
```
[📞] SMS למקבל עם tracking   חינם
     לינק לא דורש אפליקציה    [✓]
```
- Background: רקע שקוף
- Icon: gradient ירוק
- Label "חינם" בירוק
- Default checked

---

## 📋 Section 7: איש קשר במסירה

### Header:
```
[📋]  איש קשר במסירה          [👥]
      יקבל לינק לא דורש אפליקציה
```

### Input Fields:
```
[👤] מיכל כהן
[📱] 054-1234567          [✓ אומת]
```

- כל שדה עם אייקון + input + (לטלפון) badge אימות ירוק

### Privacy Banner:
```
🔒 המספר שלך מוסתר מדני אוטומטית
```
רקע כחול בהיר.

---

## ⚡ Section 8: הפעילות של דני

### Header:
```
⚡ הפעילות של דני              [● LIVE]
```

### Activity List (2-3 items):
```
[📦] משלוח לרמת גן · 23 דק'              שעה
     ★ 5.0 "שירות מעולה, מהיר מאוד"

[📝] מסמכים לעו"ד · 15 דק'               היום
     ★ 5.0 "מקצועי ויעיל"
```

- כל item עם אייקון gradient צבעוני + subtitle עם ציטוט + timestamp

---

## 💼 Section 9: חבילות לעסקים

### Container:
**רקע:** `linear-gradient(135deg, #1E3A8A 0%, #1E40AF 100%)` עם orb זהוב ברקע.

### Header:
```
[💼]  לעסקים: חיסכון עד 60%
      תשלום חודשי קבוע
```

### 3 Packages:
```
[  5  ]        [  15  ]         [  ∞  ]
משלוחים/חודש   הכי משתלם        ללא הגבלה
  ₪249          ₪599            ₪999
```

- Package 2 (middle): גדול יותר, border זהוב, shadow, label "הכי משתלם"

---

## 💰 Sticky Bottom Bar

### Container:
רקע `linear-gradient(135deg, #0A0E1A 0%, #151B2E 100%)` עם 2 orbs צבעוניים (כתום + ירוק).

### Price Summary Card (glassmorphism):
```
סך לתשלום                    ETA
₪50  ✓ סופי                 14:30
                          ● 30 דק'

───────────────────────────────
📝 מסמכים · 8.4 ק"מ · קטנוע   ₪45
📸 תיעוד + GPS                 ₪5
───────────────────────────────

[📝 מסמכים] [⏰ תוך שעה] [🛵 קטנוע]
[🤝 מסירה ליד] [📸 +תיעוד]
```

- ₪50 ב-**gradient text** (לבן → זהב)
- ETA בגודל 14px bold
- Breakdown מלא
- Tags chips יוקרתיים

### Main CTA Button (ירוק זוהר!):
```dart
Container(
  padding: EdgeInsets.all(17),
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF16A34A), Color(0xFF15803D)],
    ),
    borderRadius: BorderRadius.circular(18),
    boxShadow: [
      BoxShadow(
        color: Color(0xFF16A34A).withOpacity(0.5),
        blurRadius: 32,
        offset: Offset(0, 10),
      ),
    ],
  ),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text('שלח עכשיו · ₪50', style: TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      )),
      SizedBox(width: 10),
      Container(
        width: 24, height: 24,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.arrow_forward, size: 12, color: Colors.white),
      ),
    ],
  ),
)
```

### Trust Signals (3 items):
```
🔒 תשלום מאובטח  ·  📍 מעקב חי  ·  ↩️ ביטול חינם
```

---

## 🔘 חיבור לכפתור "בחר תאריך ושעה" הקיים

**חשוב:** השתמש ביומן הקיים, לא בנה חדש!

```dart
void onSendNowPressed() {
  // Build preferences object
  final preferences = DeliveryPreferences(
    packageType: selectedPackageType,
    packageDescription: descriptionController.text,
    packageTags: selectedTags,
    selectedVehicle: selectedVehicle,
    aiRecommendedVehicle: aiResult?.vehicle,
    pickupAddress: pickupAddress,
    deliveryAddress: deliveryAddress,
    distanceKm: calculatedDistance,
    timing: selectedTiming,
    scheduledFor: selectedTiming == 'scheduled' ? scheduledDate : null,
    deliveryMethod: selectedMethod,
    specialInstructions: instructionsController.text,
    addOns: selectedAddOns,
    recipient: Recipient(
      name: recipientName,
      phone: recipientPhone,
      phoneVerified: true,
    ),
    priceBreakdown: calculateFinalPrice(),
  );

  // Navigate to existing calendar (לא בונים חדש!)
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ExistingCalendarScreen(
      providerId: widget.providerId,
      deliveryPreferences: preferences,
      totalPrice: calculatedTotal,
    ),
  ));
}
```

---

## 🤖 AI Integration - Client Side

```dart
class AiVehicleRecommendationService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<VehicleRecommendation> recommendVehicle({
    required String packageType,
    required double distanceKm,
    required String urgency,
    String? weatherConditions,
  }) async {
    final callable = _functions.httpsCallable('recommendVehicleForDelivery');
    final result = await callable.call({
      'packageType': packageType,
      'distanceKm': distanceKm,
      'urgency': urgency,
      'weatherConditions': weatherConditions,
    });

    return VehicleRecommendation.fromJson(result.data);
  }
}

class VehicleRecommendation {
  final String recommendedVehicle; // scooter | car
  final int savingsAmount;         // ₪
  final int savingsMinutes;
  final String reason;
  final double confidence;

  VehicleRecommendation.fromJson(Map<String, dynamic> json)
    : recommendedVehicle = json['recommendedVehicle'],
      savingsAmount = json['savingsAmount'],
      savingsMinutes = json['savingsMinutes'],
      reason = json['reason'],
      confidence = json['confidence'].toDouble();
}
```

---

## 💾 State Management

```dart
class DeliveryBookingState extends ChangeNotifier {
  // AI recommendation
  VehicleRecommendation? aiResult;
  bool isLoadingAi = false;

  // User selections
  String selectedPackageType = 'documents';
  String selectedVehicle = 'scooter';
  List<String> selectedPackageTags = [];
  String descriptionText = '';

  DeliveryAddress? pickupAddress;
  DeliveryAddress? deliveryAddress;
  double distanceKm = 0;
  int etaMinutes = 0;

  String selectedTiming = 'regular';  // immediate, regular, today, scheduled
  DateTime? scheduledFor;

  String selectedMethod = 'hand_to_recipient';
  String specialInstructions = '';

  List<String> selectedAddOns = ['photo_gps', 'sms_tracking']; // defaults
  // REMOVED: 'insurance' - הוסר לפי בקשה

  String recipientName = '';
  String recipientPhone = '';
  bool recipientPhoneVerified = false;

  // Computed
  double get totalPrice {
    double base = provider.pricing[selectedPackageType] ?? 45;
    double addOnsTotal = selectedAddOns.fold(0, (sum, id) {
      final addOn = addOnCatalog.firstWhere((a) => a.id == id);
      return sum + addOn.price;
    });
    double immediateSurcharge = selectedTiming == 'immediate'
      ? provider.availability.immediate.surcharge
      : 0;
    double kmExtra = distanceKm > 5
      ? (distanceKm - 5) * provider.pricing.perKmAfter5
      : 0;
    return base + addOnsTotal + immediateSurcharge + kmExtra;
  }

  // Methods
  void selectPackageType(String type) { ... }
  void fetchAiRecommendation() async {
    isLoadingAi = true;
    notifyListeners();
    aiResult = await AiVehicleRecommendationService().recommendVehicle(
      packageType: selectedPackageType,
      distanceKm: distanceKm,
      urgency: selectedTiming,
    );
    // Update selected vehicle if AI recommended something different
    if (aiResult != null && aiResult!.confidence > 0.7) {
      selectedVehicle = aiResult!.recommendedVehicle;
    }
    isLoadingAi = false;
    notifyListeners();
  }

  DeliveryPreferences toBookingData() { ... }
}
```

---

## ⚠️ Edge Cases

1. **לשליח אין `deliveryProfile`** → הצג את הפרופיל הקיים בלי הבלוק
2. **שליח לא זמין עכשיו** → Badge "זמין · מחר 7:00" במקום "זמין · X דק'"
3. **AI לא הצליח** → לא להציג את card ההמלצה, רק את אופציות הרכב
4. **השליח לא מספק "מתוזמן"** → הסתר את האופציה בגריד
5. **אין הזמנה קודמת** → הסתר את Express Reorder
6. **המחיר מעל ₪200** → הצע אוטומטית את חבילות העסקים
7. **הלקוח פרטי ולא עסקי** → מסתיר את סקציית החבילות

---

## ✅ Acceptance Criteria - בלוק הלקוח

- [ ] הבלוק מופיע **רק** לשליחים בקטגוריית משלוחים
- [ ] הבלוק מופיע במיקום הנכון (בין "אודות" ל"השירות")
- [ ] **🆕 Hero Story Mode** עם תמונה מעוצבת + gradient text
- [ ] **🆕 Express Reorder** מופיע אם יש הזמנה קודמת
- [ ] **🆕 Live Location** - סמן השליח זז במפה
- [ ] **🆕 LIVE badge** ירוק בפינה עליונה של המפה
- [ ] **🆕 "דני · 600 מטר ממך"** badge בזמן אמת
- [ ] AI Vehicle Recommendation עובד עם Gemini
- [ ] **🚫 ללא ביטוח** - הוסר לפי בקשה
- [ ] **🆕 Phone masking** - "המספר שלך מוסתר"
- [ ] **🆕 Voice input** - כפתור 🎤 זמין
- [ ] **🆕 SMS למקבל** כברירת מחדל (חינם)
- [ ] רק סוגי משלוחים שהשליח אישר - מוצגים
- [ ] בחירות מסונכרנות לסיכום בתחתית
- [ ] לחיצה על "שלח עכשיו" - **לא** בונה יומן חדש
- [ ] כל הבחירות נשמרות ב-`bookings` collection
- [ ] תמיכה מלאה ב-RTL ובdark mode
- [ ] Haptic feedback בלחיצות

---

## 💾 בסיום העבודה - חובה לשמור!

**אחרי שסיימת את כל הפיתוח:**

1. שמור את 3 הקבצים ב-`/docs/delivery_upgrade/`:
   - `01_MAIN_PROMPT_DELIVERY.md`
   - `02_PROVIDER_EDIT_DELIVERY.md`
   - `03_CLIENT_BOOKING_DELIVERY.md`

2. עדכן את `CLAUDE.md` עם section חדש:
   ```markdown
   ## Section 32: Delivery CSM (Category-Specific Module)
   - Provider edit block: delivery_settings_block.dart
   - Client booking block: delivery_block.dart
   - AI integration: Gemini (vehicle recommendation)
   - 🆕 Express Reorder
   - 🆕 Live Location Tracking
   - 🆕 Phone Masking (privacy)
   - 🆕 Scheduled delivery (unique!)
   - 🆕 Voice input
   - 🆕 SMS tracking for recipients
   - 🚫 NO insurance feature (per user decision)
   - All files in /docs/delivery_upgrade/
   ```

3. רץ `flutter analyze` ווודא 0 issues

4. תכין סיכום מלא (כמו בהדברה):
   - כמה files נוצרו
   - אילו קבצים שונו
   - אילו features הוטמעו
   - Validation passed

---

🎉 זהו! עם 3 הקבצים האלה Claude Code יכול לבנות את הקטגוריה ברמה אולטימטיבית.

**זכור הכי חשוב: לא למחוק שום דבר! רק להוסיף 2 בלוקים חדשים במיקומים המדויקים.**
