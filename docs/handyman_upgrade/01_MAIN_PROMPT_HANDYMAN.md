# 🛠️ AnySkill - Handyman Sub-Category (הנדימן)

> **קובץ ראשי - קרא אותו קודם!** | **Main file - Read this first**
>
> פרויקט: הוספת תת-קטגוריית הנדימן ב-AnySkill ברמה עולמית.
> Project: World-class Handyman sub-category for AnySkill.
>
> **ארכיטקטורה:** Category-Specific Modules (CSM) - חמישי בסדר (אחרי עיסוי/הדברה/שליחויות/נקיון).

---

## ⛔⛔⛔ עקרונות חובה - קריטי! אל תפר! ⛔⛔⛔

### 🚫 אסור לך למחוק שום דבר!

- **אסור** למחוק חלקים קיימים מדף פרופיל הלקוח (תמונה, ✓ כחול, אודות, השירות, יומן, ביקורות, כפתור תחתון)
- **אסור** למחוק חלקים קיימים מדף עריכת נותן השירות (פרטים אישיים, אודות, גלריה, יומן וכו׳)
- **אסור** לגעת במבנה הקיים של הפרופיל
- **אסור** לשנות את routing של קטגוריות אחרות
- **אסור** לבנות יומן חדש - **חובה** להשתמש ביומן הקיים!
- **אסור** לבנות מערכת צ'אט חדשה - **חובה** להשתמש במערכת הצ'אט הקיימת!

### ⚠️ אין "ביטוח" בקטגוריה זו!
האפליקציה **לא** מציעה ביטוח לנותני שירות. **אל תוסיף** שום אלמנט של ביטוח:
- לא ב-Trust Center
- לא ב-Sticky Summary
- לא ב-Aחריות section
- לא כ-badge בשום מקום

### ⚠️ אין כפילות של "אימות ת"ז"!
**כל נותן שירות באפליקציה כבר עבר אימות ת"ז בתהליך ההרשמה** - זה חלק מהמערכת הכללית.
**אסור** להציג "ת"ז מאומתת" כ-badge או badge בדף עריכת נותן השירות (כי זה כבר מאומת מראש גלובלית).

**אבל** - בדף הלקוח אפשר להציג badge "✓ Verified" או "✓ מאומת" כחלק מ-Trust Center, כי זו מידע שהלקוח רוצה לדעת שהנותן שירות מאומת באפליקציה.

### ✅ אתה רק מוסיף 2 בלוקים חדשים:

#### בלוק 1: בדף הלקוח (פרופיל נותן השירות)
```
1. Header (קיים)
2. Profile card + סטטיסטיקות (קיים)
3. גלריה + וידאו (קיים)
4. אודות (קיים)
↓ ↓ ↓
5. ✨ הבלוק החדש - "בוא נתקן את זה ביחד" ← כאן!
↑ ↑ ↑
6. השירות (קיים)
7. זמינות / יומן (קיים)
8. ביקורות (קיים)
9. כפתור תחתון (קיים)
```

#### בלוק 2: בדף עריכת נותן השירות
```
1. פרטים אישיים (קיים)
2. תמונת פרופיל (קיים)
3. אודות (קיים)
4. תת-קטגוריה: "הנדימן" (קיים)
↓ ↓ ↓
5. ✨ הבלוק החדש - "ההגדרות שלך" ← כאן!
   (מופיע **רק** אם נבחר "הנדימן")
↑ ↑ ↑
6. גלריית עבודות (קיים)
7. יומן זמינות (קיים) ⚠️ זה מקום השעות!
8. כפתורי שמירה (קיים)
```

---

## 🔄🔄🔄 חובת סנכרון מלא עם המערכת הקיימת

### 1️⃣ סנכרון צ'אט - חובה!
הצ'אט בתוך בלוק הלקוח חייב לעבוד עם מערכת הצ'אט הקיימת:

```dart
void onChatButtonPressed() {
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ExistingChatScreen(
      otherUserId: widget.providerId,
      otherUserName: provider.name,
      otherUserAvatar: provider.avatarUrl,
      bookingContext: BookingContext(
        category: 'handyman',
        bookingDraftId: currentBookingDraft?.id,
      ),
    ),
  ));
}

// Quick Reply chips
void onQuickReplyTap(String text) {
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ExistingChatScreen(
      otherUserId: widget.providerId,
      preFilledMessage: text,
    ),
  ));
}
```

### 2️⃣ סנכרון יומן - חובה!
הכפתור "קבע מועד · ₪500" חייב להוביל ליומן הקיים של נותן השירות:

```dart
void onBookNowPressed() {
  final preferences = HandymanPreferences(
    services: selectedServices,
    punchList: punchListItems,
    aiPhotoDiagnosis: aiDiagnosisResult,
    propertyInfo: propertyInfo,
    materialsOption: materialsOption,
    urgency: selectedUrgency,
    totalPrice: calculatedTotal,
  );

  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ExistingCalendarScreen(
      providerId: widget.providerId,
      bookingPreferences: preferences,
      totalPrice: calculatedTotal,
      duration: estimatedDuration,
    ),
  ));
}
```

**🔴 חשוב במיוחד**: אם נותן השירות סימן ביומן הקיים שהוא לא זמין ביום מסוים → היומן יציג את היום הזה כחסום, בלי שצריך לכתוב קוד מיוחד.

### 3️⃣ סנכרון שעות פעילות - חובה!
**אל תיצור חלון "שעות פעילות" בבלוק החדש של עריכת נותן השירות!**

שעות הפעילות נקבעות **אך ורק** ביומן הקיים. הוסף רק banner הסבר בבלוק החדש:

```dart
// בסקציית "אזורי שירות" בבלוק עריכת נותן השירות
Container(
  decoration: BoxDecoration(
    gradient: LinearGradient(colors: [
      Color(0xFF3B82F6).withOpacity(0.15),
      Color(0xFF2563EB).withOpacity(0.05),
    ]),
    border: Border.all(color: Color(0xFF3B82F6).withOpacity(0.3)),
    borderRadius: BorderRadius.circular(11),
  ),
  padding: EdgeInsets.all(10),
  child: Row(children: [
    Text('🗓️'),
    Expanded(child: Column([
      Text('שעות פעילות נקבעות ביומן', weight: 700),
      Text('סמן ביומן הקיים למטה את הימים והשעות שלך'),
    ])),
    Text('↓', color: blueArrow),
  ]),
)
```

### 4️⃣ סנכרון Express Reorder
קארד "הזמנה חוזרת" (אם יש) יקרא מ-`bookings` + `reviews`:

```dart
Future<LastBooking?> getLastHandymanBookingWithProvider(String providerId, String userId) async {
  final query = await firestore
    .collection('bookings')
    .where('clientId', isEqualTo: userId)
    .where('providerId', isEqualTo: providerId)
    .where('serviceCategory', isEqualTo: 'handyman')
    .where('status', isEqualTo: 'completed')
    .orderBy('completedAt', descending: true)
    .limit(1)
    .get();
  // ...
}
```

### 5️⃣ סנכרון Trust Center
ה-badges ב-Trust Center **לא** יציגו "אימות ת"ז" (כי זה כבר מאומת באפליקציה כולה).
במקום זאת:
- ✓ **Verified** - מאמת שהפרופיל עבר את כל הבדיקות
- 📋 **בדיקת רקע** - ספציפי להנדימן, מאמת רקע פלילי
- 📜 **אחריות 12 חודש** - ייחודי להנדימן

---

## 🎯 Goal | מטרה

לבנות את תת-קטגוריית ההנדימן הכי חכמה בעולם ב-AnySkill - רמה של **TaskRabbit + Thumbtack + Handy + Angi + BuildFolio משולבים**.

### היתרונות התחרותיים שלנו (10!):
1. **📸 AI Photo-to-Quote** - הלקוח מצלם, AI מאבחן ומתמחר (Gemini Vision)
2. **📋 Punch List חכם** - חיסכון בדמי-נסיעה על ריבוי עבודות באותו ביקור
3. **🛒 שקיפות חומרים** - AI מראה פירוט מחירים + "אני קונה" / "הלקוח קונה"
4. **🚨 חירום 24/7** - מחיר נפרד לזמני חירום
5. **🏠 Property-aware** - האפליקציה זוכרת פרטי הבית
6. **📜 אחריות 12 חודש** - תיקון חוזר חינם
7. **🔁 חוזי תחזוקה** - בייסיק/פרימיום/VIP
8. **💬 In-app Chat** - מסונכרן
9. **📊 23 תחומי התמחות** - multi-expert עם Market Intelligence
10. **⚡ Pro Verified** - Trust Center + בדיקת רקע

---

## 📦 קבצים נוספים בפרויקט הזה

- **`02_PROVIDER_EDIT_HANDYMAN.md`** - מפרט מלא של דף עריכת נותן השירות
- **`03_CLIENT_BOOKING_HANDYMAN.md`** - מפרט מלא של דף הלקוח

**קרא את שני הקבצים הנוספים לפני שמתחיל לקודד!**

---

## 🗄️ Firestore Schema

### Collection: `users` (תוספת לשדה הקיים)

הוסף `handymanProfile` **רק אם** נבחר `subcategory == 'handyman'`:

```javascript
{
  // ...כל השדות הקיימים נשארים...

  // === שדה חדש - רק להנדימן ===
  "handymanProfile": {
    // אימותים (רק 2, ת"ז כבר באפליקציה)
    "verifications": {
      "backgroundCheck": {
        "verified": true,
        "verifiedAt": "2026-03-20T10:00:00Z",
        "documentUrl": "https://..."
      },
      "warrantyEnabled": true  // אחריות 12 חודש
    },

    // 23 תחומי התמחות
    "specialties": [
      {
        "id": "tv_mounting",
        "nameHe": "תליית טלוויזיה",
        "icon": "📺",
        "active": true,
        "yearCount": 287,  // כמה פעמים השנה
        "popularity": "hot",  // hot | urgent | null
        "basePrice": 180,
        "estimatedMinutes": 60
      },
      {
        "id": "furniture_assembly",
        "nameHe": "הרכבת רהיטים",
        "icon": "🪑",
        "active": true,
        "yearCount": 412,
        "popularity": "hot",
        "basePrice": 220,
        "estimatedMinutes": 120
      },
      // ... 21 עוד תחומים
    ],

    // AI Photo-to-Quote Settings
    "aiPhotoToQuote": {
      "enabled": true,
      "categories": {
        "plumbing": true,   // 🚿 אינסטלציה
        "electrical": true, // 💡 חשמל
        "drywall": true,    // 🔨 גבס/צבע
        "furniture": true   // 🪑 רהיטים
      }
    },

    // מחירון לפי עבודה
    "pricing": {
      "custom": [
        { "serviceId": "tv_mounting", "price": 180 },
        { "serviceId": "furniture_assembly", "price": 220 },
        { "serviceId": "plumbing_fix", "price": 140 }
      ],
      "emergencySurcharge": 50  // ₪ תוספת לחירום
    },

    // Punch List Discount
    "punchListDiscount": {
      "2_jobs": 10,   // 2 עבודות - 10%
      "3_jobs": 20,   // 3 עבודות - 20%
      "4_plus_jobs": 30  // 4+ עבודות - 30%
    },

    // אזורי שירות
    "serviceArea": {
      "cities": ["תל אביב", "רמת גן", "גבעתיים", "הרצליה"],
      "emergency24_7": true,
      "bufferMinutes": 30  // זמן חייץ בין עבודות
    },

    // ניהול חומרים
    "materials": {
      "toolsIncluded": true,  // 50+ כלים כלולים
      "policy": "i_buy"  // i_buy | client_buys | flexible
    },

    // חוזי תחזוקה שנתיים
    "maintenancePackages": [
      {
        "id": "basic",
        "nameHe": "בייסיק",
        "visitsPerYear": 2,
        "yearlyPrice": 890,
        "enabled": true,
        "activeCustomers": 8
      },
      {
        "id": "premium",
        "nameHe": "פרימיום",
        "visitsPerYear": 4,
        "yearlyPrice": 1690,
        "enabled": true,
        "activeCustomers": 12,
        "popular": true
      },
      {
        "id": "vip",
        "nameHe": "VIP",
        "visitsPerYear": -1,  // ללא הגבלה
        "yearlyPrice": 2990,
        "enabled": true,
        "activeCustomers": 3
      }
    ]
  }
}
```

### Collection: `bookings` (תוספת)

```javascript
{
  // ...שדות קיימים...

  "handymanPreferences": {
    // עבודות שנבחרו (Punch List)
    "punchList": [
      {
        "serviceId": "tv_mounting",
        "nameHe": "תליית טלוויזיה 55\"",
        "estimatedMinutes": 60,
        "price": 180,
        "priority": 1
      },
      {
        "serviceId": "plumbing_fix",
        "nameHe": "החלפת ברז במטבח",
        "estimatedMinutes": 45,
        "price": 140,
        "priority": 2
      }
    ],

    // AI Photo Diagnosis (אם היה)
    "aiPhotoDiagnosis": {
      "photoUrls": ["https://..."],
      "identifiedProblem": "ברז דולף במטבח",
      "confidence": 0.94,
      "aiAnalysis": "זיהיתי דליפה באטם הברז (O-ring שחוק). תיקון פשוט - החלפת אטם.",
      "estimatedDurationMinutes": 30,
      "estimatedPrice": 95,
      "estimatedMaterialsCost": 15,
      "clientApproved": true
    },

    // פירוט הבעיה (אם הלקוח הזין)
    "problemDescription": "קיר גבס לבן, גובה 2.6מ', יש כבל חשמל בקיר...",
    "voiceNoteUrl": null,

    // מידע נכס
    "propertyInfo": {
      "ceilingHeight": "2.6m",
      "wallType": "drywall",
      "floor": 3,
      "hasElevator": true,
      "parkingAvailable": true
    },

    // חומרים
    "materialsOption": "provider_buys",  // provider_buys | client_brings
    "estimatedMaterialsCost": 85,
    "materialsBreakdown": [
      {"name": "מתלה VESA Universal", "price": 65, "details": "נושא עד 35 ק\"ג"},
      {"name": "דוויל וברגי גבס (×4)", "price": 12},
      {"name": "כבל HDMI 4K 1.5מ'", "price": 8}
    ],

    // דחיפות
    "urgency": "today",  // emergency | today | scheduled | maintenance_contract
    "arrivalWindow": {
      "from": "2026-04-18T14:00:00Z",
      "to": "2026-04-18T16:00:00Z"
    },

    // תמחור
    "priceBreakdown": {
      "servicesTotal": 415,  // 180 + 140 + 95
      "materialsEstimate": 85,
      "punchListDiscount": -150,  // חיסכון בדמי-נסיעה
      "emergencySurcharge": 0,
      "total": 500
    },

    // אחריות
    "warranty12MonthsIncluded": true
  }
}
```

### Collection: `handyman_jobs_progress` (חדש)

מעקב בזמן אמת:
```javascript
{
  "bookingId": "abc123",
  "providerId": "handyman_xyz",
  "clientId": "user_456",
  "status": "in_progress",  // not_started | on_the_way | arrived | in_progress | completed
  "etaMinutes": 12,  // עדכוני ETA חיים כמו Uber
  "startedAt": "2026-04-18T14:15:00Z",
  "completedAt": null,
  "beforePhotos": ["https://..."],
  "afterPhotos": [],
  "tasksProgress": [
    {
      "serviceId": "tv_mounting",
      "status": "completed",
      "completedAt": "2026-04-18T15:15:00Z"
    },
    {
      "serviceId": "plumbing_fix",
      "status": "in_progress"
    }
  ],
  "materialsReceipts": [  // קבלות חומרים
    { "url": "https://...", "amount": 87, "uploadedAt": "..." }
  ]
}
```

---

## 🛠️ קבצים שצריך ליצור

### Models
- `lib/models/handyman_profile.dart`
- `lib/models/handyman_preferences.dart`
- `lib/models/handyman_specialty.dart`
- `lib/models/handyman_punch_list_item.dart`
- `lib/models/handyman_property_info.dart`
- `lib/models/handyman_ai_diagnosis.dart`
- `lib/models/handyman_maintenance_package.dart`
- `lib/models/handyman_job_progress.dart`
- `lib/models/handyman_trust_data.dart`

### Constants
- `lib/constants/handyman_specialties_catalog.dart` - 23 תחומים
- `lib/constants/handyman_market_prices.dart` - מחירי שוק לפי עיר
- `lib/constants/handyman_urgency_options.dart` - 4 דחיפויות
- `lib/constants/handyman_quick_replies.dart` - 3 quick replies

### Provider Edit Screen
- `lib/screens/handyman/handyman_settings_block.dart` - הבלוק הראשי (9 סקציות)
- `lib/screens/handyman/widgets/handyman_hero_stats.dart`
- `lib/screens/handyman/widgets/handyman_verifications_section.dart` - 2 badges (בלי ת"ז!)
- `lib/screens/handyman/widgets/handyman_ai_photo_settings.dart`
- `lib/screens/handyman/widgets/handyman_specialties_grid.dart`
- `lib/screens/handyman/widgets/handyman_pricing_editor.dart`
- `lib/screens/handyman/widgets/handyman_punch_list_discount.dart`
- `lib/screens/handyman/widgets/handyman_service_area.dart` - עם banner "שעות ביומן"
- `lib/screens/handyman/widgets/handyman_materials_management.dart`
- `lib/screens/handyman/widgets/handyman_maintenance_packages.dart`

### Client Profile Screen
- `lib/screens/handyman/handyman_booking_block.dart` - הבלוק הראשי (15 סקציות)
- `lib/screens/handyman/widgets/handyman_hero_section.dart`
- `lib/screens/handyman/widgets/handyman_trust_center.dart` - בלי ביטוח!
- `lib/screens/handyman/widgets/handyman_ai_photo_to_quote.dart` - **הכי חשוב!**
- `lib/screens/handyman/widgets/handyman_specialties_selector.dart` - 23 תחומים + search
- `lib/screens/handyman/widgets/handyman_punch_list.dart`
- `lib/screens/handyman/widgets/handyman_problem_description.dart`
- `lib/screens/handyman/widgets/handyman_property_info.dart`
- `lib/screens/handyman/widgets/handyman_materials_section.dart`
- `lib/screens/handyman/widgets/handyman_urgency_selector.dart`
- `lib/screens/handyman/widgets/handyman_warranty_section.dart`
- `lib/screens/handyman/widgets/handyman_reviews_insights.dart`
- `lib/screens/handyman/widgets/handyman_chat_preview.dart`
- `lib/screens/handyman/widgets/handyman_maintenance_contracts.dart`
- `lib/screens/handyman/widgets/handyman_booking_summary.dart`

### Services
- `lib/services/handyman_booking_service.dart` - חישוב מחירים + Punch List
- `lib/services/handyman_ai_diagnosis_service.dart` - Gemini Vision integration
- `lib/services/handyman_market_intelligence_service.dart` - Gemini market prices
- `lib/services/handyman_maintenance_scheduler.dart` - חוזים שנתיים

### 🔴 חובה - שימוש בשירותים קיימים (לא לבנות חדש!):
- **Chat**: `lib/services/chat_service.dart` (קיים)
- **Calendar**: `lib/screens/calendar/calendar_screen.dart` (קיים)
- **Bookings**: `lib/services/booking_service.dart` (קיים)

### Cloud Functions (functions/index.js)
- `diagnoseHandymanProblemFromPhoto` - Gemini 2.5 Flash Lite עם Vision
- `analyzeHandymanMarketPrices` - Gemini Flash Lite, מחירי שוק
- `calculatePunchListDiscount` - חישוב הנחות מדורגות
- `triggerMaintenanceContractVisit` - יצירת ביקורים עתידיים

---

## 🤖 Gemini AI Integration (הכי חשוב - AI Photo-to-Quote!)

**חובה: Gemini 2.5 Flash Lite עם Vision, לא Claude API!**

```javascript
// functions/diagnoseHandymanProblemFromPhoto.js
const { GoogleGenerativeAI } = require('@google/generative-ai');

exports.diagnoseHandymanProblemFromPhoto = functions.https.onCall(async (data, context) => {
  const { photoUrls, additionalDescription } = data;

  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash-lite" });

  // Convert photos to base64
  const imageParts = await Promise.all(photoUrls.map(async (url) => {
    const response = await fetch(url);
    const buffer = await response.arrayBuffer();
    return {
      inlineData: {
        data: Buffer.from(buffer).toString('base64'),
        mimeType: 'image/jpeg'
      }
    };
  }));

  const prompt = `אתה מומחה הנדימן רב-תחומי. נתח את התמונה/ות וזהה את הבעיה.

תיאור נוסף מהלקוח: ${additionalDescription || 'אין'}

השב בפורמט JSON בלבד (ללא markdown):
{
  "identifiedProblem": "string - תיאור קצר בעברית",
  "confidence": number - 0 עד 1,
  "aiAnalysis": "string - הסבר מפורט של הבעיה והפתרון בעברית",
  "category": "plumbing" | "electrical" | "drywall" | "furniture" | "painting" | "other",
  "estimatedDurationMinutes": number,
  "estimatedPrice": number (בש\"ח),
  "estimatedMaterialsCost": number (בש\"ח),
  "recommendedMaterials": [
    { "name": "string", "estimatedPrice": number, "details": "string" }
  ],
  "urgencyLevel": "low" | "medium" | "high"
}`;

  const result = await model.generateContent([prompt, ...imageParts]);
  const text = result.response.text();

  // Parse JSON (remove markdown if present)
  const cleanJson = text.replace(/```json|```/g, '').trim();
  return JSON.parse(cleanJson);
});
```

---

## ✅ Acceptance Criteria | קריטריונים לקבלה

### חובה לעבוד:
- [ ] בעריכת פרופיל - בחירת תת-קטגוריה "הנדימן" פותחת **אוטומטית** את בלוק "ההגדרות שלך"
- [ ] ביטול בחירת "הנדימן" - מסתיר את הבלוק (אבל שומר הגדרות)
- [ ] **אימותים**: **בלי** "תעודת זהות" - רק "בדיקת רקע" + "אחריות 12 חודש"
- [ ] **אין** שום אלמנט של "ביטוח" בשום מקום!
- [ ] **🔄 סנכרון יומן**: כפתור "קבע מועד" פותח את **היומן הקיים** עם פרטי ההזמנה
- [ ] **🔄 סנכרון יומן זמינות**: ימים שנותן השירות חסם ביומן הקיים מופיעים כחסומים ללקוח
- [ ] **🔄 אין סקציית "שעות פעילות"** בבלוק העריכה - רק banner שמפנה ליומן
- [ ] **🔄 סנכרון צ'אט**: כפתור "פתח צ'אט עם יוסי" פותח את **הצ'אט הקיים**
- [ ] **🔄 Quick Reply**: פותח את הצ'אט עם הטקסט מוכן
- [ ] **🔄 Reviews**: אין סקציית "איך לקוחות רואים אותך" בדף העריכה (הדירוג בפרופיל עצמו)
- [ ] **🤖 AI Photo-to-Quote** עובד עם Gemini Vision - מחזיר אבחון תוך 5 שניות
- [ ] **📋 Punch List** עם חיסכון מדורג (2 עבודות -10%, 3 -20%, 4+ -30%)
- [ ] **🛒 חומרים**: שקיפות עם פירוט AI + בחירה "יוסי קונה" / "אני אביא"
- [ ] **🚨 4 דחיפויות**: עכשיו / היום / תאריך / חוזה תחזוקה
- [ ] **📜 אחריות 12 חודש** - תצוגה בלבד (לא toggle בדף לקוח)
- [ ] **🔁 חוזי תחזוקה** - 3 חבילות + ספירת לקוחות פעילים
- [ ] תמיכה מלאה ב-RTL (עברית)
- [ ] flutter analyze: 0 issues

### אסור:
- [ ] **לא להציג** "אימות ת"ז" (כבר באפליקציה כולה)
- [ ] **לא להוסיף** שום אלמנט של "ביטוח"
- [ ] **לא לבנות** יומן חדש
- [ ] **לא לבנות** צ'אט חדש
- [ ] **לא לשים** סקציית "שעות פעילות" בבלוק עריכה
- [ ] **לא לשים** "Reviews Insights" בדף עריכת נותן השירות
- [ ] **לא להשתמש** ב-Claude API (Gemini בלבד)
- [ ] **לא להציג** הגדרות הנדימן אם לא נבחר "הנדימן"

---

## 🎨 Design System - Dark Premium Orange/Amber

### Base Colors
```dart
// Dark base
const darkBase = Color(0xFF0A0E1A);
const darkBaseMid = Color(0xFF1A1612);  // ייחודי להנדימן - יותר חם
const darkBaseDeep = Color(0xFF0F1420);

// Primary - Orange/Amber (ייחודי להנדימן)
const handymanOrange = Color(0xFFF97316);
const handymanOrangeDark = Color(0xFFEA580C);
const handymanOrangeLight = Color(0xFFFB923C);
const handymanAmberPale = Color(0xFFFDBA74);
const handymanBgPale = Color(0xFFFFF7ED);

// Status
const statusGreen = Color(0xFF16A34A);
const statusRed = Color(0xFFDC2626);
const statusAmber = Color(0xFFF59E0B);
const purplePro = Color(0xFFA855F7);
const blueChat = Color(0xFF3B82F6);
```

### Ambient Orbs (רקע)
1. **Orb orange** (top-right) - `radial-gradient(rgba(249,115,22,0.28) 0%, transparent 70%)`
2. **Orb green** (middle-left) - `radial-gradient(rgba(34,197,94,0.18) 0%, transparent 70%)`
3. **Orb purple** (bottom) - `radial-gradient(rgba(168,85,247,0.15) 0%, transparent 70%)`
4. **Orb indigo** (middle-right) - `radial-gradient(rgba(99,102,241,0.15) 0%, transparent 70%)`

---

## 🌐 Localization Keys (מרכזיים)

הוסף ל-`l10n/app_he.arb`, `app_en.arb`, `app_es.arb`, `app_ar.arb`:

```json
{
  "handyman_settings_banner": "הגדרות ייעודיות להנדימן",
  "handyman_hero_title_client": "בוא נתקן\nאת זה ביחד",
  "handyman_hero_subtitle_client": "📸 צלם → 🤖 AI → 💰 אומדן → ✅ תיקון",
  "handyman_hero_title_provider": "ההגדרות שלך",
  "handyman_hero_subtitle_provider": "ככל שתגדיר יותר טוב - יותר לקוחות ימצאו אותך",

  "handyman_status_available": "זמין · {minutes} דק'",
  "handyman_status_emergency": "🚨 חירום 24/7",
  "handyman_status_top_provider": "🏆 Top 1%",
  "handyman_status_pro": "⚡ Pro Verified",

  "handyman_trust_center_title": "Trust Center",
  "handyman_trust_background_check": "בדיקת רקע",
  "handyman_trust_warranty": "אחריות 12 חודש",
  "handyman_trust_escrow": "תשלום בנאמנות",
  "handyman_trust_verified": "✓ Verified",

  "handyman_ai_photo_title": "תאר/צלם את הבעיה",
  "handyman_ai_photo_subtitle": "3 דרכי קלט · בחר מה הכי נוח לך",
  "handyman_ai_photo_camera": "צלם עכשיו",
  "handyman_ai_photo_gallery": "גלריה",
  "handyman_ai_photo_voice": "דבר",
  "handyman_ai_photo_badge": "⚡ AI · 5 שניות",
  "handyman_ai_analyzed": "✓ AI ניתח",
  "handyman_ai_confidence": "🎯 רמת ביטחון: {percent}%",
  "handyman_ai_diagnosis": "🤖 אבחון AI:",

  "handyman_specialties_title": "או בחר מ-23 התחומים",
  "handyman_specialties_subtitle": "חיפוש חכם · סינון לפי דחיפות",
  "handyman_specialties_search_placeholder": "חפש: 'דלת חורקת', 'שקע חשמל'...",
  "handyman_specialty_tv": "תליית טלוויזיה",
  "handyman_specialty_furniture": "הרכבת רהיטים",
  "handyman_specialty_plumbing": "אינסטלציה",
  "handyman_specialty_electrical": "חשמל קל",
  "handyman_specialty_painting": "צביעה",
  "handyman_specialty_drywall": "גבס",
  "handyman_specialty_doors": "דלתות",
  "handyman_specialty_repair": "תיקון רהיטים",

  "handyman_punch_list_title": "Punch List חכם",
  "handyman_punch_list_subtitle": "הוסף עוד עבודות באותו ביקור = חיסכון משמעותי",
  "handyman_punch_list_savings": "חוסך ₪{amount} בדמי-נסיעה",
  "handyman_punch_list_ai_suggests": "🤖 AI ממליץ להוסיף (משתלם!)",

  "handyman_description_title": "תיאור מפורט",
  "handyman_description_subtitle": "פרט ככל שתוכל - יוסי יבוא מוכן",
  "handyman_description_voice": "🎤 דבר",
  "handyman_description_ai_enhance": "🤖 AI שפר",
  "handyman_description_placeholder": "תיאור הבעיה...",

  "handyman_property_title": "📐 מידע על הנכס",
  "handyman_property_ceiling_height": "גובה תקרה",
  "handyman_property_wall_type": "סוג קיר",
  "handyman_property_floor": "קומה",
  "handyman_property_parking": "חניה",

  "handyman_materials_title": "חומרים וציוד · שקיפות מלאה",
  "handyman_materials_subtitle": "AI חישב את כל החומרים",
  "handyman_tools_included": "כל הציוד המקצועי כלול",
  "handyman_tools_count": "50+ כלים מקצועיים",
  "handyman_materials_required": "חומרים נדרשים",
  "handyman_materials_provider_buys": "✓ יוסי יקנה",
  "handyman_materials_client_brings": "אני אביא לבד",

  "handyman_urgency_title": "מתי שיגיע?",
  "handyman_urgency_subtitle": "בחר דחיפות שמתאימה לך",
  "handyman_urgency_emergency": "עכשיו",
  "handyman_urgency_today": "היום",
  "handyman_urgency_scheduled": "תאריך אחר",
  "handyman_urgency_maintenance": "תחזוקה",
  "handyman_urgency_arrival_window": "חלון הגעה",
  "handyman_urgency_live_eta": "🎯 עדכוני ETA חיים (כמו Uber)",

  "handyman_warranty_title": "אחריות 12 חודשים",
  "handyman_warranty_subtitle": "התקלקל? יוסי חוזר חינם!",
  "handyman_warranty_period": "12 חודש",
  "handyman_warranty_repair": "תיקון חוזר",
  "handyman_warranty_free": "חינם",
  "handyman_warranty_support": "📞 תמיכה 24/7 · גיבוי מקצועי במקרה הצורך",

  "handyman_reviews_insights_title": "תובנות מ-{count} ביקורות",
  "handyman_reviews_punctuality": "⏰ דייקנות",
  "handyman_reviews_quality": "🎯 איכות",
  "handyman_reviews_fairness": "💰 הוגנות",
  "handyman_reviews_service": "🤝 שירות",

  "handyman_chat_title": "שאלות ליוסי?",
  "handyman_chat_subtitle": "תגובה ב-3 דק' · עברית/EN/RU",
  "handyman_chat_button": "פתח צ'אט עם יוסי",
  "handyman_chat_online": "מקוון",
  "handyman_chat_quick_1": "\"זמין מחר בבוקר?\"",
  "handyman_chat_quick_2": "\"כמה זמן זה ייקח?\"",
  "handyman_chat_quick_3": "\"אפשר לראות תמונה?\"",

  "handyman_maintenance_title": "תחזוקה שנתית · חיסכון 30%",
  "handyman_maintenance_subtitle": "חוזה שנתי · בדיקה חודשית · עדיפות",
  "handyman_maintenance_basic": "בייסיק",
  "handyman_maintenance_premium": "פרימיום",
  "handyman_maintenance_vip": "VIP",
  "handyman_maintenance_popular": "⭐ הכי משתלם",

  "handyman_summary_total": "סך לתשלום (משוער)",
  "handyman_summary_materials": "+חומרים",
  "handyman_summary_savings": "💚 חיסכון Punch List",
  "handyman_summary_cta": "קבע מועד · ₪{amount}",
  "handyman_summary_secure": "תשלום בנאמנות",
  "handyman_summary_warranty": "12 חודש אחריות",
  "handyman_summary_cancel": "ביטול חופשי",

  "handyman_provider_income_month": "הכנסה החודש: ₪{amount}",
  "handyman_provider_income_trend": "↗ +{percent}% מהחודש שעבר · {returning}% לקוחות חוזרים",
  "handyman_provider_specialties_title": "תחומי ההתמחות שלך",
  "handyman_provider_active_count": "{active} פעיל · {potential} פוטנציאל להוסיף",
  "handyman_provider_multi_expert_tip": "טיפ: נותני שירות עם 12+ תחומים מרוויחים פי 2.3",
  "handyman_provider_pricing_title": "מחירון חכם לפי עבודה",
  "handyman_provider_pricing_subtitle": "AI משווה למחירי שוק תל אביב",
  "handyman_provider_market_title": "מחירי שוק ת\"א (ממוצע)",
  "handyman_provider_emergency_surcharge": "תוספת חירום",
  "handyman_provider_punch_list_discount_title": "Punch List Discount",
  "handyman_provider_punch_list_discount_subtitle": "ככל שיש יותר עבודות בביקור - יותר הנחה",
  "handyman_provider_service_area_title": "אזורי שירות",
  "handyman_provider_service_area_subtitle": "איפה אתה עובד",
  "handyman_provider_hours_in_calendar_banner": "שעות פעילות נקבעות ביומן",
  "handyman_provider_hours_in_calendar_hint": "סמן ביומן הקיים למטה את הימים והשעות שלך",
  "handyman_provider_buffer_minutes": "זמן חייץ בין עבודות",
  "handyman_provider_materials_title": "ניהול חומרים וציוד",
  "handyman_provider_materials_policy_title": "מדיניות חומרים",
  "handyman_provider_materials_i_buy": "אני קונה",
  "handyman_provider_materials_client": "הלקוח",
  "handyman_provider_materials_flexible": "גמיש",
  "handyman_provider_maintenance_title": "חוזי תחזוקה שנתיים",
  "handyman_provider_maintenance_subtitle": "הכנסה קבועה · {count} לקוחות פעילים",
  "handyman_provider_maintenance_yearly_income": "הכנסה שנתית מחוזים: ₪{amount}"
}
```

---

## 📊 KPIs להצלחה

לאחר ההשקה - מדידה דרך AI CEO Agent:
- **Conversion rate** (יעד: +55%)
- **AI Photo-to-Quote usage** - אחוז שמעלים תמונה (יעד: >60%)
- **Punch List adoption** - אחוז הזמנות עם 2+ עבודות (יעד: >40%)
- **Emergency bookings** - כמה מההזמנות הן חירום (יעד: 15-25%)
- **Maintenance contract sales** - כמה חוזים שנתיים נמכרים (יעד: 50/חודש)
- **Time to booking** - מכניסה להזמנה (יעד: <60 שניות)
- **Materials "I buy" adoption** - אחוז שבוחרים שהנותן קונה (יעד: >70%)
- **Specialties per provider** - ממוצע תחומים לנותן שירות (יעד: >10)

---

## 💾 בסיום העבודה - חובה לשמור!

1. **שמור את כל קבצי MD** ב-`/docs/handyman_upgrade/`
2. **עדכן CLAUDE.md** עם section חדש:
   ```markdown
   ## Section 35: Handyman CSM (Category-Specific Module)
   - Provider edit block: handyman_settings_block.dart (9 sections)
   - Client booking block: handyman_booking_block.dart (15 sections)
   - AI integration: Gemini 2.5 Flash Lite with Vision
   - 🆕 AI Photo-to-Quote (זיהוי בעיות מתמונה!)
   - 🆕 Punch List with graduated discount
   - 🆕 Materials transparency (AI-calculated)
   - 🆕 23 specialties with market intelligence
   - 🆕 4 urgency levels including Emergency 24/7
   - 🆕 12-month warranty
   - 🆕 Maintenance contracts (3 tiers)
   - 🆕 Reviews insights for client (not provider)
   - 🔄 Synced Chat (existing ChatScreen)
   - 🔄 Synced Calendar (existing CalendarScreen - hours there!)
   - ❌ NO insurance anywhere
   - ❌ NO ID verification (already global in app)
   - All files in /docs/handyman_upgrade/
   ```
3. **תעדכן userMemories** שעבר Handyman CSM הוטמע
4. **רץ flutter analyze** ווודא 0 issues
5. **תכין סיכום מלא**

---

## 🤖 Built for AnySkill - Claude Code Implementation

**זכור: לא למחוק כלום! הכל מסונכרן עם המערכת הקיימת! רק להוסיף 2 בלוקים חדשים במיקומים המדויקים שצוינו למעלה.**

**אין ביטוח. אין כפילות אימות ת"ז. שעות ביומן בלבד. Reviews Insights רק ללקוח, לא לנותן שירות.**
