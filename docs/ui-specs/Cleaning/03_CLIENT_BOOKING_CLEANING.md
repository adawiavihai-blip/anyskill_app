# 🎨 Client Profile Screen - Cleaning | דף הלקוח (בואי נתאים את הניקיון שלך)

> **קובץ זה הוא חלק מ-`01_MAIN_PROMPT_CLEANING.md`** - קרא אותו קודם!

---

## ⛔ תזכורת קריטית: לא למחוק כלום!

המסך הזה כבר קיים. אתה **רק מוסיף בלוק חדש** בין "אודות" ל"השירות".

**הסדר במסך:**
```
1. Header עם "→" "♡" "↗" (קיים - לא נוגעים)
2. Profile card - תמונה, ✓ כחול, "נותנת שירות", "נקיון", סטטיסטיקות (קיים - לא נוגעים)
3. גלריית עבודות + וידאו היכרות (קיים - לא נוגעים)
4. אודות (קיים - לא נוגעים)
   ↓ ↓ ↓
5. ✨ הבלוק החדש - "בואי נתאים את הניקיון שלך" ← מתווסף כאן!
   ↑ ↑ ↑
6. השירות (קיים - לא נוגעים)
7. זמינות / יומן (קיים - לא נוגעים) ⚠️ הכפתור בבלוק יוביל לכאן!
8. ביקורות (קיים - לא נוגעים)
9. כפתור תחתון "קבעי מועד" (קיים - לא נוגעים)
```

---

## 🔄🔄🔄 הסנכרון - חובה ביותר!

### 1️⃣ סנכרון יומן (CRITICAL!)

**הכפתור הסופי "קבעי מועד · ₪234" בתחתית הבלוק חייב לפתוח את היומן הקיים** של נותן השירות.

```dart
class CleaningBookingSummary extends StatelessWidget {
  final CleaningPreferences preferences;
  final double totalPrice;

  void onBookNowPressed(BuildContext context) {
    // ❌❌❌ אסור לבנות יומן חדש!
    // ✅ נווט ליומן הקיים עם כל הפרטים

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExistingCalendarScreen(  // ← היומן הקיים באפליקציה!
          providerId: providerId,
          serviceCategory: 'cleaning',
          bookingPreferences: preferences,
          estimatedDurationMinutes: preferences.estimatedDurationMinutes,
          totalPrice: totalPrice,
          onBookingConfirmed: (selectedDateTime) async {
            // יצור הזמנה ב-bookings collection
            await BookingService.createBooking(
              providerId: providerId,
              clientId: currentUser.uid,
              category: 'cleaning',
              dateTime: selectedDateTime,
              cleaningPreferences: preferences,
              priceBreakdown: preferences.priceBreakdown,
            );
          },
        ),
      ),
    );
  }
}
```

**🔴 חשוב במיוחד**: היומן הקיים כבר יודע לקרוא מ-`users.{providerId}.availability` ולהציג ימים חסומים. המנקה סימנה ב-section 8 שלה (היומן הקיים) שאינה זמינה ב-21/04 → היומן יציג את היום הזה כחסום ללקוח **בלי קוד מיוחד**.

### 2️⃣ סנכרון צ'אט (CRITICAL!)

**הכפתור "פתחי צ'אט עם שרה" + Quick Reply chips חייבים לפתוח את הצ'אט הקיים באפליקציה.**

```dart
class CleaningChatPreview extends StatelessWidget {
  final String providerId;
  final String providerName;
  final String? providerAvatarUrl;

  // כפתור ראשי - פותח צ'אט ריק
  void onMainChatButtonPressed(BuildContext context) {
    // ❌❌❌ אסור לבנות מערכת צ'אט חדשה!
    // ✅ נווט לצ'אט הקיים באפליקציה

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExistingChatScreen(  // ← הצ'אט הקיים!
          otherUserId: providerId,
          otherUserName: providerName,
          otherUserAvatar: providerAvatarUrl,
          // קונטקסט שיעזור לצ'אט להבין שזו שיחה לפני הזמנה
          context: ChatContext(
            type: ChatContextType.preBooking,
            category: 'cleaning',
          ),
        ),
      ),
    );
  }

  // Quick Reply - פותח את הצ'אט עם הטקסט מוכן בשדה ההקלדה
  void onQuickReplyPressed(BuildContext context, String quickReplyText) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExistingChatScreen(
          otherUserId: providerId,
          otherUserName: providerName,
          otherUserAvatar: providerAvatarUrl,
          preFilledMessage: quickReplyText,  // ← הטקסט מוכן בשדה!
          context: ChatContext(
            type: ChatContextType.preBooking,
            category: 'cleaning',
          ),
        ),
      ),
    );
  }
}
```

**Quick Replies:**
- "זמינה לשבת?" → פותח צ'אט עם "זמינה לשבת?" כבר מוכן
- "מביאה ציוד?" → פותח צ'אט עם "מביאה ציוד?" כבר מוכן

### 3️⃣ סטטוס "מקוונת" - מסונכרן בזמן אמת

```dart
StreamBuilder<UserPresence>(
  stream: presenceService.streamUserPresence(providerId),
  builder: (context, snapshot) {
    final isOnline = snapshot.data?.isOnline ?? false;
    final lastSeen = snapshot.data?.lastSeen;

    return Container(
      // אם isOnline → "● מקוונת" ירוק
      // אם לא → "פעילה לאחרונה לפני X" אפור
      child: Row(
        children: [
          if (isOnline) PulsingDot(color: Colors.green),
          Text(isOnline ? 'מקוונת' : 'נראתה לפני ${formatLastSeen(lastSeen)}'),
        ],
      ),
    );
  },
)
```

### 4️⃣ סנכרון Express Reorder

הקארד "Express Reorder · נקיון אחרון לפני 7 ימים" חייב להציג נתונים אמיתיים:

```dart
FutureBuilder<LastBooking?>(
  future: bookingHistoryService.getLastBookingWithProvider(
    providerId: providerId,
    clientId: currentUser.uid,
  ),
  builder: (context, snapshot) {
    final lastBooking = snapshot.data;
    if (lastBooking == null) return SizedBox.shrink();

    return ExpressReorderCard(
      cleaningType: lastBooking.cleaningType,
      propertySize: lastBooking.propertySize,
      durationHours: lastBooking.durationHours,
      daysAgo: lastBooking.daysAgo,
      rating: lastBooking.rating,
      reviewSnippet: lastBooking.reviewText?.substring(0, 60),
      onPressed: () => prefillFromLastBooking(lastBooking),
    );
  },
)
```

### 5️⃣ סנכרון Trust Center

**ה-badges קוראים מנתונים הקיימים של נותן השירות:**

```dart
StreamBuilder<TrustCenterData>(
  stream: trustService.streamTrustData(providerId),
  builder: (context, snapshot) {
    final data = snapshot.data;
    return TrustCenter(
      idVerified: data?.idVerified ?? false,           // users.verifications.idCard
      backgroundChecked: data?.backgroundChecked ?? false,  // users.verifications.backgroundCheck
      insuranceAmount: data?.insuranceAmount ?? 0,     // cleaningProfile.insurance
      escrowEnabled: true,  // ברירת מחדל - תכונת המערכת
    );
  },
)
```

---

## 📍 מתי הבלוק החדש מופיע?

הבלוק מופיע **רק** במצב הבא:
- הלקוח נכנס לדף פרופיל של נותנת שירות
- הקטגוריה היא "נקיון" (`category == 'cleaning'` או `subcategory == 'cleaning'`)
- לנותנת השירות יש `cleaningProfile` ב-Firestore

---

## 🎨 הבלוק החדש - מבנה כללי (Dark Premium)

### Container ראשי
רקע `linear-gradient(135deg, #0A0E1A 0%, #0F1A2E 50%, #0F1420 100%)` עם 3 ambient orbs cyan/green/purple.

הבלוק מתחיל עם separator cyan + טקסט "↓ הזמנת ניקיון אישית ↓"

### סקציות לפי הסדר:

1. 🌟 **Hero Section** (חדש - בלי תמונת פרופיל!)
2. 🛡️ **Trust Center** (חדש!)
3. 🔁 **Express Reorder** (אופציונלי - אם יש הזמנה קודמת)
4. 🧼 **בחירת סוג נקיון** (1 מ-6)
5. 🏠 **פרטי הנכס** (חדרים/אמבט/מ"ר/חיות/קומה)
6. 📋 **Smart Checklist** עם progress bars
7. ⏰ **תזמון** - חד פעמי / קבוע + תדירות
8. 🌱 **Eco Mode** toggle
9. 🚪 **שיטת גישה** - אני בבית / מפתח-קוד
10. 📸 **Before/After Photos**
11. 💯 **Quality Guarantee** (חדש!)
12. 📊 **Recent Works** - 3 thumbnails + ציטוט
13. 💬 **Chat Preview** (מסונכרן!)
14. 💼 **חבילות עסקים**
15. 💰 **Sticky Bottom Summary**

---

## 🌟 Section 0: Hero Section (בלי תמונה!)

**עיצוב:** padding 18-14px, text-align center.

### ❌ מה הוסר מ-V1:
- תמונת פרופיל (כבר קיימת למעלה)
- KPIs כפולים (2,148/4.96/3 שע')
- Title "נקה איתי שרה"

### ✅ מה יש בפנים:

**3 Status Badges** (top):
```
[● זמינה היום]  [🌱 Eco-Certified]  [🏆 Top 3]
```

**Title (gradient text, 2 lines!):**
```dart
Text(
  'בואי נתאים\nאת הניקיון שלך',
  textAlign: TextAlign.center,
  style: TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -1.2,
    foreground: Paint()..shader = LinearGradient(
      colors: [Colors.white, Color(0xFF67E8F9)],
    ).createShader(Rect.fromLTWH(0, 0, 300, 80)),
  ),
)
```

**Subtitle (value props):**
```
3 דקות ההזמנה · ביטוח עד ₪10,000 · אחריות מלאה
```

---

## 🛡️ Section 1: Trust Center (חדש!)

**Container**: `linear-gradient(135deg, rgba(34,197,94,0.15), rgba(22,163,74,0.05))` + border ירוק bold.

### Header:
```
[🛡️]  Trust Center                                              ›
       למה את יכולה לסמוך עליה
```

### 4 Trust Badges (Grid 4x1):
```
[🆔]            [📋]            [🛡️]            [💎]
ת"ז             בדיקת          ביטוח           תשלום
מאומתת          רקע            ₪10K            בנאמנות
```

כל badge ב-`background: rgba(0,0,0,0.25)` עם `border: 1px solid rgba(34,197,94,0.2)`.

---

## 🔁 Section 2: Express Reorder (Conditional!)

**מופיע רק** אם ללקוח יש הזמנה קודמת עם המנקה הזו.

**Container**: gradient סגול + border 1.5px.

### Header:
```
🔁 Express Reorder · נקיון אחרון לפני 7 ימים
```

### Content:
```
[🏠]  בית רגיל · 80 מ"ר · 3 שעות           [חזור]
      ★★★★★ "מצוין כרגיל, התמונות אחרי - וואו!"
```

הכפתור "חזור" בtouch מעתיק את כל הפרטים מההזמנה הקודמת לבחירות הנוכחיות.

---

## 🧼 Section 3: בחירת סוג ניקיון

### Header:
```
[1]  איזה ניקיון את רוצה?
     בחרי את הסוג שמתאים לך
```

### Grid 3x2 (6 אפשרויות):
- 🏠 בית רגיל (~3 שעות) - **נבחר** (gradient cyan + checkmark)
- ✨ Deep / שיפוץ (~5 שעות)
- 🏨 Airbnb (~2 שעות)
- 🏢 משרדים (לפי גודל)
- 🏬 חנויות (לפי גודל)
- 🧽 לפני אירוע (~4 שעות)

---

## 🏠 Section 4: פרטי הנכס (משופר)

### Header:
```
[2]  פרטי הנכס שלך                          [💾 נשמר אוטומטית]
     המחיר מתעדכן בזמן אמת
```

### Grid 3x1 (Stepper inputs):
```
🛏️ חדרי שינה        🚿 חדרי אמבט        📐 גודל (מ"ר)
   [-] 2 [+]            [-] 1 [+]              [80]
```

### Grid 2x1 (Toggle inputs):
```
🐕 בעלי-חיים          🪜 קומה
[כן ✓]  [לא]          [קרקע]  [מעלית ✓]
```

### AI Calculation Card:
```
[⏱️]  משך משוער: 3 שעות                    [AI חישב]
      מחיר בסיס: ₪240
```

### Logic:
```dart
final propertyDetails = PropertyDetails(
  bedrooms: bedrooms,
  bathrooms: bathrooms,
  squareMeters: squareMeters,
  hasPets: hasPets,
  floor: floor,
);

// קריאה ל-Cloud Function עם Gemini
final estimate = await cloudFunctions.calculateCleaningDuration({
  'cleaningType': selectedType,
  'bedrooms': bedrooms,
  'bathrooms': bathrooms,
  'squareMeters': squareMeters,
  'hasPets': hasPets,
  'selectedTasksCount': selectedTasks.length,
  'addOnsCount': selectedAddOns.length,
});

// תצוגה: "משך משוער: 3 שעות · מחיר בסיס: ₪240"
```

---

## 📋 Section 5: Smart Checklist עם Progress Bars

### Header:
```
[3]  המשימות שלך                              [12 פעיל]
     סמני מה חשוב במיוחד
```

### Info Banner:
```
💡 איך זה עובד: שרה מבצעת את המשימות לפי הסדר.
   את תקבלי תמונה לכל משימה שמסומנת 📷
```

### 3 Categories (כל אחת עם progress bar):

#### 🛏️ חדר שינה (3/3)
```
[≡] [✓] החלפת מצעים + סידור מיטה              📷
[≡] [✓] שאיבת אבק + ניגוב משטחים
[≡] [✓] חלונות פנימיים
```

#### 🚿 חדר אמבטיה (4/4)
```
[≡] [✓] ניקוי מקלחת + אסלה לעומק              📷
[≡] [✓] הסרת אבנית מברזים
```

#### 🍽️ מטבח (5/6)
```
[≡] [✓] משטחי עבודה + כיורים
[≡] [ ] ניקוי תנור פנימי                      [+₪40]
```

### Add Custom Task Button:
```
+ הוסף משימה אישית (כביסה, שטיחים...)
```

---

## ⏰ Section 6: תזמון

### Header:
```
[4]  מתי שרה תגיע?
     חד פעמי או חוזר אוטומטית
```

### Grid 2x1 (One-time vs Recurring):
```
[📅 חד פעמי]              [🔄 קבוע ✓]
   בחרי תאריך              חיסכון עד 15%
```

### Recurrence Sub-section (מופיע אם נבחר "קבוע"):
```
📆 איזו תדירות?

[שבועי]    [דו-שבועי ✓]    [חודשי]
−15%        −10%             −5%
```

### Schedule Confirmation:
```
🗓️ מתחיל: ראשון 21/04, 8:00-11:00         ✎
   הביקור הבא: 04/05 · ביטול חופשי בכל עת
```

---

## 🌱 Section 7: Eco Mode

**Container**: gradient ירוק + border ירוק bold.

```
[🌱]  חומרים אקולוגיים                      [Toggle ON]
      בטוח לילדים, חיות מחמד, אלרגיות

      💚 שרה תביא חומרים מאושרים EcoCert      +₪25
```

---

## 🚪 Section 8: שיטת גישה

### Header:
```
[5]  איך שרה תיכנס?
     בחרי את שיטת הגישה
```

### Grid 2x1:
```
[🏠 אני בבית ✓]            [🔑 מפתח/קוד]
   אפתח לה                    ללא נוכחות
```

### Special Instructions:
```
💬 הוראות נוספות לשרה
[Placeholder] "יש לי כלב קטן וידידותי..."
```

---

## 📸 Section 9: Before/After Photos

**Container**: gradient amber + border amber bold.

### Header:
```
[📸]  תיעוד "לפני ואחרי"                     [חינם]
      תקבלי תמונות אוטומטית בWhatsApp
```

### Visual:
```
[📷]              →              [✨]
לפני                              אחרי
3 חדרים                           בסיום
```

---

## 💯 Section 10: Quality Guarantee (חדש!)

**Container**: gradient ירוק + border ירוק bold.

### Header:
```
[💯]  אחריות 100% שביעות רצון
      לא מרוצה? נקיון חוזר חינם תוך 24 שעות
```

### Grid 3x1:
```
[⏰]            [🔄]            [💸]
24 שעות         נקיון חוזר      או החזר
לדווח           חינם            מלא
```

---

## 📊 Section 11: Recent Works

### Header:
```
📊 העבודות האחרונות של שרה                [ראי הכל →]
```

### Grid 3x1 (Before/After thumbnails):
```
[לפני → אחרי]   [לפני → אחרי]   [לפני → אחרי]
    🏠 ת"א           🏨 Airbnb        ✨ Deep
    ★ 5.0           ★ 5.0            ★ 4.9
```

### Latest Review (with avatar):
```
[מ]  "שרה הפכה את הדירה שלי. הצילומים אחרי הניקוי - וואו! 🤩"
     - מיכל ל. · רמת גן · לפני 3 ימים
```

---

## 💬 Section 12: Chat Preview (מסונכרן!)

**Container**: glassmorphism standard.

### Header:
```
[💬]  שאלות לשרה?                            [● מקוונת]
      היא מגיבה תוך ~5 דקות
```

### Main Chat Button:
```dart
// Container עם gradient כחול
GestureDetector(
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ExistingChatScreen(  // ← הצ'אט הקיים!
        otherUserId: providerId,
        otherUserName: 'שרה לוי',
        otherUserAvatar: providerAvatarUrl,
        context: ChatContext.preBooking('cleaning'),
      ),
    ),
  ),
  child: Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        Color(0xFF3B82F6).withOpacity(0.2),
        Color(0xFF2563EB).withOpacity(0.08),
      ]),
      border: Border.all(color: Color(0xFF3B82F6).withOpacity(0.3)),
      borderRadius: BorderRadius.circular(12),
    ),
    padding: EdgeInsets.all(10),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('פתחי צ\'אט עם שרה', style: TextStyle(
          color: Color(0xFF93C5FD),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        )),
        SizedBox(width: 8),
        Icon(Icons.arrow_forward, color: Color(0xFF93C5FD), size: 14),
      ],
    ),
  ),
)
```

### Quick Reply Chips:
```dart
Row(
  children: [
    Expanded(
      child: QuickReplyButton(
        text: '"זמינה לשבת?"',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExistingChatScreen(
              otherUserId: providerId,
              preFilledMessage: 'זמינה לשבת?',  // ← מוכן בשדה!
            ),
          ),
        ),
      ),
    ),
    SizedBox(width: 5),
    Expanded(
      child: QuickReplyButton(
        text: '"מביאה ציוד?"',
        onTap: () => /* same pattern */,
      ),
    ),
  ],
)
```

---

## 💼 Section 13: חבילות עסקים

**Container**: gradient כחול כהה עם orb ברקע.

### Header:
```
[💼]  חבילות לעסקים
      חיסכון של עד 30% למשרדים וחנויות
```

### 3 Packages (Grid 3x1):
```
[  4×  ]        [  8×  ]        [  ∞  ]
/חודש           הכי משתלם       יומי
₪890            ₪1,690          ₪3,490
```

---

## 💰 Sticky Bottom Summary

**Container**: רקע `linear-gradient(135deg, #0A0E1A 0%, #0F1A2E 100%)` עם 2 orbs.

### Price Card (glassmorphism):
```
סך לתשלום                        משך
₪234  −10%                       3 שעות
במקום ₪260 · מנוי דו-שבועי       ● 8:00-11:00

──────────────────────────────────────
🏠 נקיון בית · 80 מ"ר · 2-1 חדרים    ₪240
🌱 חומרים אקולוגיים                    ₪25
──────────────────────────────────────
🔄 הנחת מנוי דו-שבועי                 −₪31

[🛡️ מבוטח] [💯 אחריות] [🌱 Eco] [📸 +תיעוד]
```

### Main CTA Button (Cyan glowing):
```dart
GestureDetector(
  onTap: () {
    // ❌ אסור לבנות יומן!
    // ✅ נווט ליומן הקיים
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExistingCalendarScreen(
          providerId: providerId,
          serviceCategory: 'cleaning',
          bookingPreferences: gatheredPreferences,
          totalPrice: 234,
          duration: Duration(hours: 3),
        ),
      ),
    );
  },
  child: Container(
    padding: EdgeInsets.all(17),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Color(0xFF06B6D4).withOpacity(0.5),
          blurRadius: 32,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('קבעי מועד · ₪234', style: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        )),
        SizedBox(width: 10),
        Icon(Icons.arrow_forward, size: 12, color: Colors.white),
      ],
    ),
  ),
)
```

### Trust Signals:
```
🔒 תשלום בנאמנות  ·  ↩️ ביטול עד 24 שע'  ·  💯 אחריות מלאה
```

---

## 💾 State Management

```dart
class CleaningBookingState extends ChangeNotifier {
  // User selections
  String? selectedCleaningType;
  PropertyDetails propertyDetails = PropertyDetails();
  List<String> selectedTasks = [];
  List<CustomTask> customTasks = [];
  List<String> selectedAddOns = [];

  String schedulingType = 'recurring';  // one_time, recurring
  String recurrenceFrequency = 'biweekly';
  DateTime? selectedDate;

  bool ecoModeEnabled = true;
  String accessMethod = 'client_present';
  String specialInstructions = '';

  // AI calculations
  int estimatedDurationMinutes = 0;
  bool isCalculatingDuration = false;

  // Computed
  double get basePrice {
    if (selectedCleaningType == null) return 0;
    final pricing = provider.cleaningProfile.pricing;
    final basePriceForType = _calculateBasePrice(pricing, propertyDetails);
    final typeMultiplier = pricing.typeMultipliers[selectedCleaningType] ?? 1.0;
    return basePriceForType * typeMultiplier;
  }

  double get addOnsTotal => selectedAddOns
    .map((id) => provider.cleaningProfile.pricing.addOns[id] ?? 0)
    .reduce((a, b) => a + b);

  double get ecoSurcharge => ecoModeEnabled
    ? provider.cleaningProfile.ecoMode.surcharge
    : 0;

  double get subtotal => basePrice + addOnsTotal + ecoSurcharge;

  double get recurringDiscount {
    if (schedulingType != 'recurring') return 0;
    final discountPercent = provider.cleaningProfile.recurringDiscounts[recurrenceFrequency] ?? 0;
    return subtotal * (discountPercent / 100);
  }

  double get total => subtotal - recurringDiscount;

  // Methods
  Future<void> calculateDuration() async {
    isCalculatingDuration = true;
    notifyListeners();

    final result = await CloudFunctions.instance
      .httpsCallable('calculateCleaningDuration')
      .call({
        'cleaningType': selectedCleaningType,
        'bedrooms': propertyDetails.bedrooms,
        'bathrooms': propertyDetails.bathrooms,
        'squareMeters': propertyDetails.squareMeters,
        'hasPets': propertyDetails.hasPets,
        'selectedTasksCount': selectedTasks.length,
        'addOnsCount': selectedAddOns.length,
      });

    estimatedDurationMinutes = result.data['estimatedMinutes'];
    isCalculatingDuration = false;
    notifyListeners();
  }

  CleaningPreferences toBookingData() {
    return CleaningPreferences(
      cleaningType: selectedCleaningType!,
      propertyDetails: propertyDetails,
      estimatedDurationMinutes: estimatedDurationMinutes,
      selectedTasks: selectedTasks,
      customTasks: customTasks,
      selectedAddOns: selectedAddOns,
      schedulingType: schedulingType,
      recurrence: schedulingType == 'recurring'
        ? Recurrence(
            enabled: true,
            frequency: recurrenceFrequency,
            discount: provider.cleaningProfile.recurringDiscounts[recurrenceFrequency] ?? 0,
            startDate: selectedDate!,
          )
        : null,
      ecoMode: EcoMode(
        enabled: ecoModeEnabled,
        surcharge: ecoSurcharge,
      ),
      accessMethod: accessMethod,
      specialInstructions: specialInstructions,
      qualityGuaranteeOptedIn: true,
      beforeAfterPhotos: BeforeAfterPhotos(
        enabled: true,
        deliveryChannel: 'whatsapp',
        rooms: _getRoomsFromSelectedTasks(),
      ),
      priceBreakdown: PriceBreakdown(
        basePriceForType: basePrice,
        addOnsTotal: addOnsTotal,
        ecoSurcharge: ecoSurcharge,
        subtotal: subtotal,
        recurringDiscount: -recurringDiscount,
        total: total,
      ),
    );
  }
}
```

---

## ⚠️ Edge Cases

1. **לנותנת השירות אין `cleaningProfile`** → הצג את הפרופיל הקיים בלי הבלוק
2. **המנקה לא זמינה היום** → Badge "זמינה מחר" במקום "זמינה היום"
3. **אין הזמנה קודמת** → הסתר את Express Reorder
4. **הלקוח לא הזין כל הפרטים** → כפתור "קבעי מועד" disabled
5. **AI לא חישב משך** → הצג fallback ידני (משך ברירת מחדל לפי type)
6. **המחיר עבר ₪500** → הצע אוטומטית את חבילות העסקים
7. **המנקה לא הגדירה Eco Mode** → הסתר את הסקציה
8. **הצ'אט הקיים אינו זמין** → הצג hint "פתחי בהמשך באפליקציה"

---

## ✅ Acceptance Criteria - בלוק הלקוח

- [ ] הבלוק מופיע **רק** למנקות בקטגוריית נקיון
- [ ] הבלוק מופיע במיקום הנכון (בין "אודות" ל"השירות")
- [ ] **🌟 Hero חדש** - בלי תמונה כפולה, בלי KPIs כפולים
- [ ] **🛡️ Trust Center** עם 4 badges בולטים
- [ ] **🔁 Express Reorder** מופיע אם יש הזמנה קודמת + ביקורת אמיתית
- [ ] **🏠 Property Setup** עם בעלי-חיים + קומה
- [ ] **📋 Smart Checklist** עם progress bars לכל קטגוריה
- [ ] **🌱 Eco Mode** מחושב במחיר הסופי
- [ ] **📸 Before/After** - "תקבלי בWhatsApp"
- [ ] **💯 Quality Guarantee** עם 3 פיצ'רים
- [ ] **💬 Chat Preview** - **🔄 פותח את הצ'אט הקיים** באפליקציה
- [ ] **💬 Quick Reply** - **🔄 פותח צ'אט עם טקסט מוכן** בשדה
- [ ] **💬 סטטוס מקוונת** - מסונכרן בזמן אמת
- [ ] **🗓️ "קבעי מועד"** - **🔄 פותח את היומן הקיים** עם פרטי ההזמנה
- [ ] **🗓️ ימים שנחסמו ביומן הקיים** - מופיעים כחסומים בלי קוד נוסף
- [ ] רק סוגי נקיון שהמנקה אישרה - מוצגים
- [ ] בחירות מסונכרנות לסיכום בתחתית בזמן אמת
- [ ] תמיכה מלאה ב-RTL ובdark mode
- [ ] Haptic feedback בלחיצות

---

## 💾 בסיום העבודה - חובה לשמור!

**אחרי שסיימת את כל הפיתוח:**

1. שמור את 3 הקבצים ב-`/docs/cleaning_upgrade/`:
   - `01_MAIN_PROMPT_CLEANING.md`
   - `02_PROVIDER_EDIT_CLEANING.md`
   - `03_CLIENT_BOOKING_CLEANING.md`

2. עדכן את `CLAUDE.md` עם section חדש:
   ```markdown
   ## Section 34: Cleaning CSM (Category-Specific Module)
   - Provider edit block: cleaning_settings_block.dart
   - Client booking block: cleaning_block.dart
   - AI integration: Gemini (duration calculation)
   - 🆕 Trust Center (4 verification badges)
   - 🆕 Smart Checklist with progress bars
   - 🆕 Quality Guarantee 100%
   - 🔄 Synced In-app Chat (uses existing ChatScreen)
   - 🔄 Synced Calendar (uses existing CalendarScreen)
   - 🆕 Express Reorder from booking history + reviews
   - 🆕 Eco Mode toggle with EcoCert
   - 🆕 Before/After photos to WhatsApp
   - 🆕 Recurring discounts (15%/10%/5%)
   - 🆕 Business packages (4×/8×/daily)
   - All files in /docs/cleaning_upgrade/
   ```

3. רץ `flutter analyze` ווודא 0 issues

4. תכין סיכום מלא:
   - כמה files נוצרו
   - אילו קבצים שונו
   - אילו features הוטמעו
   - Validation passed

---

🎉 זהו! עם 3 הקבצים האלה Claude Code יכול לבנות את הקטגוריה ברמה אולטימטיבית.

**זכור הכי חשוב:**
- **לא למחוק שום דבר!** רק להוסיף 2 בלוקים חדשים
- **🔄 הכל מסונכרן** - צ'אט, יומן, היסטוריה - הכל עם המערכת הקיימת!
- **🎨 V2 ULTIMATE** - בלי כפילויות, עם Trust Center, Quality Guarantee, In-app Chat
