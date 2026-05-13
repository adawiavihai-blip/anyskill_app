# 🎨 Client Profile Screen - Handyman | דף הלקוח (בוא נתקן את זה ביחד)

> **קובץ זה הוא חלק מ-`01_MAIN_PROMPT_HANDYMAN.md`** - קרא אותו קודם!

---

## ⛔ תזכורת קריטית: לא למחוק כלום!

המסך הזה כבר קיים. אתה **רק מוסיף בלוק חדש** בין "אודות" ל"השירות".

**הסדר במסך:**
```
1. Header (קיים)
2. Profile card - תמונה, ✓ כחול, סטטיסטיקות (קיים)
3. גלריית עבודות + וידאו היכרות (קיים)
4. אודות (קיים)
   ↓ ↓ ↓
5. ✨ הבלוק החדש - "בוא נתקן את זה ביחד" ← מתווסף כאן!
   ↑ ↑ ↑
6. השירות (קיים)
7. זמינות / יומן (קיים) ⚠️ הכפתור יוביל לכאן!
8. ביקורות (קיים)
9. כפתור תחתון "קבע מועד" (קיים)
```

---

## 🔴 מה אסור להיות בבלוק החדש

1. ❌ **אין "ביטוח" בשום מקום** - לא בTrust Center, לא ב-Summary, לא כbadge
2. ❌ **אין KPIs כפולים** - הסטטיסטיקות כבר ב-profile card למעלה
3. ❌ **אין תמונת פרופיל** - כבר למעלה

---

## 🔄🔄🔄 הסנכרון - חובה ביותר!

### 1️⃣ סנכרון יומן (CRITICAL!)

**הכפתור הסופי "קבע מועד · ₪500" בתחתית הבלוק חייב לפתוח את היומן הקיים של נותן השירות.**

```dart
class HandymanBookingSummary extends StatelessWidget {
  final HandymanPreferences preferences;
  final double totalPrice;

  void onBookNowPressed(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExistingCalendarScreen(
          providerId: providerId,
          serviceCategory: 'handyman',
          bookingPreferences: preferences,
          estimatedDurationMinutes: preferences.estimatedDurationMinutes,
          totalPrice: totalPrice,
          onBookingConfirmed: (selectedDateTime) async {
            await BookingService.createBooking(
              providerId: providerId,
              clientId: currentUser.uid,
              category: 'handyman',
              dateTime: selectedDateTime,
              handymanPreferences: preferences,
              priceBreakdown: preferences.priceBreakdown,
            );
          },
        ),
      ),
    );
  }
}
```

**🔴 חשוב**: היומן הקיים כבר יודע לקרוא מ-`users.{providerId}.availability` ולהציג ימים חסומים. אין צורך בקוד מיוחד.

### 2️⃣ סנכרון צ'אט (CRITICAL!)

```dart
class HandymanChatPreview extends StatelessWidget {
  void onMainChatButtonPressed(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExistingChatScreen(
          otherUserId: providerId,
          otherUserName: providerName,
          otherUserAvatar: providerAvatarUrl,
          context: ChatContext(
            type: ChatContextType.preBooking,
            category: 'handyman',
          ),
        ),
      ),
    );
  }

  void onQuickReplyPressed(BuildContext context, String quickReplyText) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExistingChatScreen(
          otherUserId: providerId,
          preFilledMessage: quickReplyText,
          context: ChatContext(
            type: ChatContextType.preBooking,
            category: 'handyman',
          ),
        ),
      ),
    );
  }
}
```

**Quick Replies (3):**
- "זמין מחר בבוקר?"
- "כמה זמן זה ייקח?"
- "אפשר לראות תמונה?"

### 3️⃣ סנכרון Trust Center
**בלי "ת"ז מאומתת" (כי זה ברירת מחדל גלובלית) ובלי "ביטוח".**

```dart
StreamBuilder<TrustCenterData>(
  stream: trustService.streamHandymanTrustData(providerId),
  builder: (context, snapshot) {
    final data = snapshot.data;
    return TrustCenter(
      verified: true,  // כבר אומת גלובלית
      backgroundChecked: data?.backgroundChecked ?? false,
      warranty12Months: data?.warrantyEnabled ?? true,
      escrowEnabled: true,  // תכונת המערכת
    );
  },
)
```

---

## 📍 מתי הבלוק מופיע?

- הלקוח נכנס לדף פרופיל של נותן שירות
- הקטגוריה היא "הנדימן" (`subcategory == 'handyman'`)
- לנותן השירות יש `handymanProfile` ב-Firestore

---

## 🎨 15 סקציות בבלוק הלקוח

### Container ראשי - Dark Premium Orange/Amber
```dart
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF0A0E1A), Color(0xFF1A1612), Color(0xFF0F1420)],
    ),
  ),
  // + 4 ambient orbs: orange, green, purple, indigo
)
```

---

## 🔴 Section 1: LIVE Urgency Banner (הדגשה!)

```
┌─────────────────────────────────────┐
│ 🔴 LIVE · 4 לקוחות בוחרים עכשיו   │
└─────────────────────────────────────┘
```

- Pulsing orange dot עם glow
- צבע: `linear-gradient(135deg, rgba(249,115,22,0.2), rgba(234,88,12,0.05))`
- Border כתום 1px

**Logic**: זה LIVE counter שמעודכן מ-Firestore - כמה active sessions פתוחים עכשיו של הפרופיל.

---

## 🌟 Section 2: Hero Section

### 4 Status Badges (במקום 3):
```
[● זמין · 25 דק']  [🚨 חירום 24/7]  [🏆 Top 1%]  [⚡ Pro]
```

### Gradient Title (3 שכבות צבע):
```dart
Text(
  'בוא נתקן\nאת זה ביחד',
  style: TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    foreground: Paint()..shader = LinearGradient(
      colors: [Color(0xFFFFFFFF), Color(0xFFFDBA74), Color(0xFFFB923C)],
    ).createShader(...),
  ),
)
```

### Subtitle (flow ויזואלי):
```
📸 צלם → 🤖 AI → 💰 אומדן → ✅ תיקון
```

### Stats Strip (3 KPIs):
```
⏱️ 3 דק' לתגובה  |  ✅ 98% הצלחה  |  🔁 87% חוזרים
```

---

## 🛡️ Section 3: Trust Center (בלי ת"ז, בלי ביטוח!)

### Container:
- Border ירוק rgba(34,197,94,0.4)

### Header:
```
[🛡️]  Trust Center · האפליקציה הכי בטוחה   [פרטים →]
       הגנה מלאה - הכל מאומת
```

### 4 Badges (Grid 4x1):
```
[✓]           [📋]          [📜]           [💎]
Verified      בדיקת רקע     אחריות         Escrow
              2026          12 חודש        תשלום בנאמנות
```

### ⚠️ שינויים חשובים:
- ❌ **אין "ת"ז"** (גלובלי באפליקציה)
- ❌ **אין "ביטוח ₪50K"** (לא קיים באפליקציה)
- ✅ במקום: "✓ Verified" (מאמת שהפרופיל עבר הכל)
- ✅ "Escrow" במקום "ביטוח"

### Escrow Info (ירוק):
```
💎 תשלום בנאמנות (Escrow) - אתה משלם רק אחרי שאישרת
```

---

## 🤖 Section 4: AI Photo-to-Quote (THE STAR! ⭐)

### Container:
- **Double border** כתום: 2px solid rgba(249,115,22,0.5)
- **Floating badge** למעלה: "⚡ AI · 5 שניות"
- Shadow חזק: `0 12px 40px rgba(249,115,22,0.25)`

### Header:
```
[📸 large gradient icon]  תאר/צלם את הבעיה
                           3 דרכי קלט · בחר מה הכי נוח
```

### 3 Input Methods:
```
[📷 צלם עכשיו]  [🖼️ גלריה]  [🎤 דבר]
```

### Inline AI Analysis Result (Conditional):
מופיע אם הלקוח העלה תמונה:

```dart
AnimatedContainer(
  decoration: BoxDecoration(
    color: Colors.black.withOpacity(0.5),
    border: Border.all(
      color: Color(0xFF16A34A).withOpacity(0.4),
    ),
  ),
  child: Column([
    // Badge "✓ AI ניתח" - ירוק
    // Photo thumbnail + identified problem
    Row([
      Container(photoThumb),
      Column([
        Text('ברז דולף במטבח'),
        Text('🎯 רמת ביטחון: 94%'),
      ]),
    ]),
    // AI Analysis text
    Container(
      color: greenTint,
      child: Text('🤖 אבחון AI: זיהיתי דליפה באטם...'),
    ),
    // 3 Metrics
    Row([
      Card('משך: ~30 דק'),
      Card('מחיר: ₪95'),
      Card('חומרים: ~₪15'),
    ]),
  ]),
)
```

### How It Works Info:
```
💡 איך זה עובד: צלם → AI מזהה תוך 5 שניות → אומדן זמן + מחיר + רשימת חומרים → אישור
```

### Gemini Cloud Function Call:
```dart
final result = await FirebaseFunctions.instance
  .httpsCallable('diagnoseHandymanProblemFromPhoto')
  .call({
    'photoUrls': uploadedPhotoUrls,
    'additionalDescription': descriptionText,
  });

final diagnosis = HandymanAiDiagnosis.fromJson(result.data);
```

---

## 🔍 Section 5: 23 Specialties with Smart Search

### Header:
```
[1]  או בחר מ-23 התחומים
     חיפוש חכם · סינון לפי דחיפות
```

### Search Bar עם ⌘K:
```
[🔍 חפש: 'דלת חורקת', 'שקע חשמל'...]            [⌘K]
```

### Filter Pills:
```
[הכל (23) ✓]  [⚡ פופולרי]  [⏱️ עד שעה]  [💰 עד ₪200]
```

### Specialties Grid (3x3):
```
[📺 ✓]          [🪑 🔥 חם]         [🚿 דחוף]
תליית TV         הרכבת רהיטים        אינסטלציה
₪180 · 1ש'      ₪220 · 2ש'          ₪140 · 1.5ש'

[💡 דחוף]        [🎨]                [🔨]
חשמל קל          צביעה               גבס
₪150 · 1ש'      לפי שטח             ₪95 · 30ד'

[⊕ 17 תחומים נוספים]
```

### Badges על הכרטיסים:
- ★ 5.0 (על התחום הנבחר - תליית TV)
- 🔥 חם (popular)
- דחוף (urgent - אינסטלציה/חשמל)

### Selected State:
- Background: gradient `#F97316 → #EA580C`
- Checkmark לבן בפינה שמאלית עליונה
- Shadow: `0 6px 20px rgba(249,115,22,0.4)`

---

## 📋 Section 6: Punch List חכם (ייחודי!)

### Container:
- Border **1.5px** סגול: rgba(168,85,247,0.5)

### Header:
```
[📋 purple icon]  Punch List חכם                [3 פעיל]
                   הוסף עוד עבודות באותו ביקור = חיסכון
```

### 💰 Savings Banner (ירוק בולט):
```
[💰]  חוסך ₪150 בדמי-נסיעה        [−30%]
      ביקור אחד במקום 3             הנחה
```

### 3 Job Cards:
כל card עם:
- אייקון התחום (orange gradient)
- שם העבודה + Badge #1/#2/#3 (סגול)
- תיאור קצר
- מחיר (amber)
- כפתור "הסר" (אדום)

```
[📺 #1]  תליית טלוויזיה 55"             ₪180  [הסר]
         ~1 שעה · קיר גבס

[🚿 #2]  החלפת ברז במטבח                ₪140  [הסר]
         ~45 דק' · ברז כלול

[🔨 #3]  תיקון חור בקיר                 ₪95   [הסר]
         ~30 דק' · גבס + צבע
```

### AI Recommendations Row:
```
🤖 AI ממליץ להוסיף (משתלם!)

[🚪 דלת חורקת +₪65]  [🔌 שקע +₪80]  [🪟 תריס +₪110]
```

---

## 📝 Section 7: תיאור מפורט

### Header:
```
[2]  תיאור מפורט
     פרט כדי שיוסי יגיע מוכן
```

### Description Card:
```
📝 תיאור הבעיה                   [🎤 דבר] [🤖 AI שפר]

[Textarea:]
"קיר גבס לבן, גובה 2.6מ', יש כבל חשמל בקיר.
הטלוויזיה Samsung 55" - 18 ק"ג."

87 / 500 תווים              ✓ מספיק מידע
```

### Property Info Grid (2x2):
```
📐 מידע על הנכס             💾 נשמר אוטומטית

[גובה תקרה: 2.6 מ' ✓]   [סוג קיר: גבס ✓]
[קומה: 3 · מעלית]         [חניה: פנויה ✓]
```

### Voice-to-Text Integration:
```dart
// Using speech_to_text package
final speech = stt.SpeechToText();
await speech.initialize();
speech.listen(
  onResult: (result) {
    descriptionController.text = result.recognizedWords;
  },
  localeId: 'he_IL',
);
```

### AI Enhance:
```dart
final enhanced = await FirebaseFunctions.instance
  .httpsCallable('enhanceHandymanDescription')
  .call({'originalText': description});
descriptionController.text = enhanced.data['enhancedText'];
```

---

## 🛒 Section 8: חומרים וציוד · שקיפות מלאה

### Container:
- Border amber rgba(245,158,11,0.5)

### Header:
```
[🛒 amber icon]  חומרים וציוד · שקיפות מלאה
                  ✨ AI חישב את כל החומרים
```

### Card 1: Tools Included (ירוק)
```
[🔧 green icon]  כל הציוד המקצועי כלול    [חינם]
                  50+ כלים מקצועיים
```

### Card 2: Materials Required (amber)
```
[📦 amber icon]  חומרים נדרשים                ₪85
                  יוסי יקנה ויחזיר קבלה        משוער

─────────────────────────────────
פירוט חומרים (AI):

• מתלה VESA Universal                ₪65
  דגם: נושא עד 35 ק"ג · המבורג
• דוויל וברגי גבס (×4)                ₪12
  נושא עד 35 ק"ג
• כבל HDMI 1.5מ' (איכות 4K)          ₪8
  שחור · מסוכך

─────────────────────────────────

[✓ יוסי יקנה]    [אני אביא]
```

---

## 🚨 Section 9: מתי שיגיע? (4 דחיפויות)

### Header:
```
[3]  מתי שיגיע?
     בחר דחיפות שמתאימה לך
```

### Grid 2x2:

#### 🚨 עכשיו (אדום)
```
[🚨 badge: חירום]
עכשיו
25 דק' · +₪50
```
Background: `linear-gradient(135deg, #DC2626, #991B1B)`

#### ⚡ היום (כתום - נבחר)
```
[✓ checkmark]
⚡
היום
14:00-16:00
```
Background: `linear-gradient(135deg, #F97316, #EA580C)`
Shadow: `0 6px 20px rgba(249,115,22,0.4)`

#### 📅 תאריך אחר
```
📅
תאריך אחר
בחר מתי
```

#### 🔁 תחזוקה (indigo)
```
[⭐ חכם badge]
🔁
תחזוקה
חוזה שנתי
```
Background: `linear-gradient(135deg, rgba(99,102,241,0.2), rgba(79,70,229,0.08))`

### Arrival Window Visualization (Uber-style):
```
📍 חלון הגעה

[14:00]  [=====================]  [16:00]
🎯 עדכוני ETA חיים (כמו Uber)
```

---

## 📜 Section 10: אחריות 12 חודשים

### Container:
- Border ירוק 1.5px rgba(34,197,94,0.5)

### Header:
```
[📜 green large icon]  אחריות 12 חודשים מלאה
                        משהו התקלקל? יוסי חוזר חינם!
```

### 3 Pillars Grid:
```
[📅]           [🔧]           [🛡️]
12 חודש        תיקון חוזר     ביטוח נזק
מסיום העבודה   חינם           עד ₪50K
```

**⚠️ שים לב**: "ביטוח נזק" כאן מתייחס ל-Escrow protection, לא ביטוח אמיתי. אפשר לשנות ל-"הגנת Escrow" אם רוצים.

### Support Banner:
```
📞 תמיכה זמינה 24/7 · גיבוי מקצועי במקרה הצורך
```

---

## 📊 Section 11: Reviews Insights (חדש - רק לבלוק הלקוח!)

### Container:
- Standard glassmorphism

### Header:
```
📊  תובנות מ-892 ביקורות
     מה אנשים אומרים על יוסי
```

### 4 Metric Bars:
```
⏰ דייקנות   [========= ]  96%
🎯 איכות     [=========]   98%
💰 הוגנות    [======== ]   94%
🤝 שירות     [=========]   99%
```

כל bar עם:
- אייקון + שם + min-width 60px
- Progress bar (linear-gradient ירוק)
- אחוז בצבע ירוק

### Word Cloud Tags:
```
[✨ "מקצוען" (87)]  [⚡ "מהיר" (62)]
[💯 "אמין" (54)]   [🧹 "נקי" (43)]
```

### Latest Review Card:
```
[ר avatar]  "יוסי הגיע בזמן, פתר 4 בעיות בביקור
             אחד וחיסך לי המון כסף. מקצוען!"
             ★★★★★ - רונית ב. · גבעתיים · לפני יומיים
```

---

## 💬 Section 12: Chat Preview (מסונכרן!)

### Header:
```
[💬 blue icon]  שאלות ליוסי?             [● מקוון]
                 תגובה ב-3 דק' · עברית/EN/RU
```

### Main Chat Button:
```dart
GestureDetector(
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ExistingChatScreen(
        otherUserId: providerId,
        otherUserName: 'יוסי אברהם',
        context: ChatContext.preBooking('handyman'),
      ),
    ),
  ),
  child: Container(
    gradient: blueGradient,
    child: Text('💬 פתח צ\'אט עם יוסי  →'),
  ),
)
```

### 3 Quick Replies (עם 💭 icon):
```
[💭 "זמין מחר בבוקר?"]
[💭 "כמה זמן זה ייקח?"]
[💭 "אפשר לראות תמונה?"]
```

כל אחד פותח את הצ'אט הקיים עם הטקסט מוכן בשדה ההקלדה.

---

## 💼 Section 13: חוזי תחזוקה שנתיים

### Container:
- Dark blue gradient: `linear-gradient(135deg, #1E3A8A, #1E40AF)`
- 2 orbs (amber + purple) ברקע

### Header:
```
[🔁 amber icon]  תחזוקה שנתית · חיסכון 30%
                  חוזה שנתי · בדיקה חודשית · עדיפות
```

### 3 Package Cards:
```
[בייסיק]          [פרימיום ⭐]        [VIP]
2/שנה            הכי משתלם           ∞
₪890             4/שנה               ₪2,990
                 ₪1,690
```

חבילת "פרימיום" מודגשת:
- Border amber 1.5px
- Badge "⭐ הכי משתלם" למעלה
- Shadow חזק יותר

### Benefits Footer:
```
✓ עדיפות בחירום   ✓ ללא תוספות   ✓ חומרים בעלות
```

---

## 💰 Section 14: Sticky Bottom Summary

### Container:
- Gradient: `linear-gradient(135deg, #0A0E1A 0%, #1A1612 100%)`
- 2 orbs ברקע

### Price Card:
```
┌────────────────────────────────────┐
│ סך לתשלום (משוער)        משך       │
│ ₪500  +חומרים            ~2.5 שע' │
│ 3 עבודות · חיסכון ₪150   ● היום 14:00│
│                                    │
│ ─────────────────────────────────  │
│ 📺 תליית TV 55"              ₪180  │
│ 🚿 החלפת ברז                ₪140  │
│ 🔨 תיקון קיר                ₪95   │
│ 📦 חומרים (משוער)          ₪85   │
│ ─────────────────────────────────  │
│ 💚 חיסכון Punch List       −₪150  │
│                                    │
│ [🛡️ Escrow] [📜 12 חודש] [📦]      │
│ [⚡ היום]                          │
└────────────────────────────────────┘
```

### ❌ חשוב: בבלוק הזה **אין** "🛡️ מבוטח ₪50K"! המלה המקורית הוחלפה ב-"Escrow".

### CTA Button (Orange Glowing):
```dart
ElevatedButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExistingCalendarScreen(
          providerId: providerId,
          bookingPreferences: gatheredPreferences,
          totalPrice: 500,
          duration: Duration(hours: 2, minutes: 30),
        ),
      ),
    );
  },
  style: ElevatedButton.styleFrom(
    padding: EdgeInsets.all(17),
    backgroundColor: Color(0xFFF97316),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    ),
  ),
  child: Row([
    Text('קבע מועד · ₪500'),
    CircleAvatar(backgroundColor: white20, child: Icon(Icons.arrow_forward)),
  ]),
)
```

Shadow: `0 10px 32px rgba(249,115,22,0.5)`

### Trust Signals (תחתית):
```
🔒 תשלום בנאמנות  ·  📜 12 חודש אחריות  ·  ↩️ ביטול חופשי
```

---

## 💾 State Management

```dart
class HandymanBookingState extends ChangeNotifier {
  // AI Diagnosis
  HandymanAiDiagnosis? aiDiagnosis;
  List<String> uploadedPhotos = [];
  bool isAnalyzing = false;

  // Selected services (Punch List)
  List<HandymanSpecialty> selectedServices = [];

  // Problem description
  String problemDescription = '';
  String? voiceNoteUrl;

  // Property info
  HandymanPropertyInfo propertyInfo = HandymanPropertyInfo();

  // Materials
  String materialsOption = 'provider_buys';

  // Urgency
  String urgency = 'today';
  DateTimeRange? arrivalWindow;

  // Computed
  double get servicesTotal => selectedServices
    .map((s) => s.basePrice)
    .fold(0.0, (a, b) => a + b);

  double get punchListDiscount {
    final count = selectedServices.length;
    if (count >= 4) return servicesTotal * 0.30;
    if (count == 3) return servicesTotal * 0.20;
    if (count == 2) return servicesTotal * 0.10;
    return 0;
  }

  double get materialsEstimate {
    if (materialsOption == 'client_brings') return 0;
    return aiDiagnosis?.estimatedMaterialsCost ?? 85;
  }

  double get emergencySurcharge {
    return urgency == 'emergency' ? 50 : 0;
  }

  double get total => servicesTotal - punchListDiscount + materialsEstimate + emergencySurcharge;

  // Methods
  Future<void> analyzePhoto(List<String> photoUrls) async {
    isAnalyzing = true;
    notifyListeners();

    final result = await FirebaseFunctions.instance
      .httpsCallable('diagnoseHandymanProblemFromPhoto')
      .call({
        'photoUrls': photoUrls,
        'additionalDescription': problemDescription,
      });

    aiDiagnosis = HandymanAiDiagnosis.fromJson(result.data);
    isAnalyzing = false;
    notifyListeners();
  }

  HandymanPreferences toBookingData() {
    return HandymanPreferences(
      punchList: selectedServices.map((s) => PunchListItem(
        serviceId: s.id,
        nameHe: s.nameHe,
        estimatedMinutes: s.estimatedMinutes,
        price: s.basePrice,
        priority: selectedServices.indexOf(s) + 1,
      )).toList(),
      aiPhotoDiagnosis: aiDiagnosis,
      problemDescription: problemDescription,
      voiceNoteUrl: voiceNoteUrl,
      propertyInfo: propertyInfo,
      materialsOption: materialsOption,
      estimatedMaterialsCost: materialsEstimate,
      materialsBreakdown: aiDiagnosis?.recommendedMaterials,
      urgency: urgency,
      arrivalWindow: arrivalWindow,
      priceBreakdown: PriceBreakdown(
        servicesTotal: servicesTotal,
        materialsEstimate: materialsEstimate,
        punchListDiscount: -punchListDiscount,
        emergencySurcharge: emergencySurcharge,
        total: total,
      ),
      warranty12MonthsIncluded: true,
    );
  }
}
```

---

## ⚠️ Edge Cases

1. **לנותן השירות אין `handymanProfile`** → הצג הפרופיל הקיים בלי הבלוק
2. **נותן השירות לא זמין היום** → Badge "זמין מחר" במקום "זמין היום"
3. **AI Photo-to-Quote מכובה** → הסתר את הסקציה ה-AI, הצג רק 23 תחומים
4. **Punch List ריק** → הסתר "AI ממליץ" + הסתר "חיסכון ₪150"
5. **רק עבודה 1** → אין discount (0%)
6. **AI לא הצליח לזהות** → הצג fallback: "לא זיהיתי בוודאות, אנא בחר מהרשימה"
7. **תמונה לא חוקית** → הצג error + אפשרות לנסות שוב
8. **הנותן שירות לא הפעיל חוזי תחזוקה** → הסתר סקציה 13

---

## ✅ Acceptance Criteria

- [ ] הבלוק מופיע **רק** לנותני שירות הנדימן
- [ ] הבלוק במיקום הנכון (בין "אודות" ל"השירות")
- [ ] **🔴 LIVE banner** עם pulsing dot
- [ ] **🌟 Hero** - 4 status badges, gradient title, stats strip
- [ ] **🛡️ Trust Center** - 4 badges (Verified/בדיקת רקע/אחריות/Escrow)
- [ ] **❌ אין "ת"ז" ב-Trust Center**
- [ ] **❌ אין "ביטוח" בשום מקום**
- [ ] **🤖 AI Photo-to-Quote** עובד עם Gemini Vision
- [ ] **🔍 Smart Search** + 4 filter pills
- [ ] **📋 Punch List** עם #1/#2/#3 badges + AI suggestions
- [ ] **📝 Voice-to-text** + AI enhance buttons
- [ ] **🏠 Property info** (4 fields) נשמר אוטומטית
- [ ] **🛒 Materials** עם פירוט AI + 2 אופציות
- [ ] **🚨 4 דחיפויות** + arrival window visualization
- [ ] **📜 אחריות 12 חודש** עם 3 pillars
- [ ] **📊 Reviews Insights** עם 4 bars + word cloud
- [ ] **💬 Chat** - פותח ChatScreen הקיים
- [ ] **💬 Quick Replies** - פותחים עם הטקסט מוכן
- [ ] **💼 3 חבילות תחזוקה**
- [ ] **💰 Sticky Summary** - בלי "ביטוח"!
- [ ] **🗓️ "קבע מועד"** - פותח CalendarScreen הקיים
- [ ] תמיכה מלאה ב-RTL
- [ ] Haptic feedback

---

## 💾 בסיום - חובה לשמור!

1. שמור את 3 הקבצים ב-`/docs/handyman_upgrade/`
2. עדכן `CLAUDE.md` Section 35
3. עדכן userMemories
4. רץ `flutter analyze` - 0 issues
5. הכן סיכום מלא

---

🎉 זהו! עם 3 הקבצים האלה Claude Code יכול לבנות את הקטגוריה ברמה עולמית.

**זכור הכי חשוב:**
- ❌ **אין "ביטוח"** באף מקום
- ❌ **אין "ת"ז"** (כבר מאומת גלובלית)
- ❌ **אין "שעות פעילות"** בדף העריכה (ביומן!)
- ❌ **אין "Reviews Insights"** בדף העריכה (רק בדף הלקוח)
- ✅ **Chat** → ExistingChatScreen הקיים
- ✅ **Calendar** → ExistingCalendarScreen הקיים
- ✅ **AI** → Gemini 2.5 Flash Lite בלבד
