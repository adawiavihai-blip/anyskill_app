# 🧼 AnySkill - Cleaning Category (Cleaners) | נקיון

> **קובץ ראשי - קרא אותו קודם!** | **Main file - Read this first**
>
> פרויקט: הוספת קטגוריית נקיון ב-AnySkill ברמה עולמית (Handy + Cleanster + Turno + AllBetter משולבים).
> Project: World-class Cleaning category addition to AnySkill.
>
> **ארכיטקטורה:** Category-Specific Modules (CSM) - אותו עיקרון כמו עיסוי, הדברה ושליחויות.

---

## ⛔⛔⛔ עקרונות חובה - קריטי! אל תפר! ⛔⛔⛔

### 🚫 אסור לך למחוק שום דבר!

זה הכלל הכי חשוב בכל הפרויקט:
- **אסור** למחוק חלקים קיימים מדף פרופיל הלקוח (תמונה, ✓ כחול, אודות, השירות, יומן, ביקורות, כפתור תחתון)
- **אסור** למחוק חלקים קיימים מדף עריכת המנקה (פרטים אישיים, אודות, גלריה, יומן וכו׳)
- **אסור** לגעת במבנה הקיים של הפרופיל
- **אסור** לשנות את routing של קטגוריות אחרות
- **אסור** לבנות יומן חדש - **חובה** להשתמש ביומן הקיים!
- **אסור** לבנות מערכת צ'אט חדשה - **חובה** להשתמש במערכת הצ'אט הקיימת באפליקציה!
- **אסור** להשתמש ב-Claude API - השתמש ב-Gemini בלבד עבור AI

### ✅ אתה רק מוסיף 2 בלוקים חדשים:

#### בלוק 1: בדף הלקוח (פרופיל המנקה)
מתווסף **בדיוק** במיקום הזה:
```
1. Header (קיים - לא נוגעים)
2. Profile card עם תמונה, ✓ כחול, סטטיסטיקות (קיים - לא נוגעים)
3. גלריה + וידאו (קיים - לא נוגעים)
4. אודות (קיים - לא נוגעים)
↓ ↓ ↓
5. ✨ הבלוק החדש - "בואי נתאים את הניקיון שלך" ← כאן!
↑ ↑ ↑
6. השירות (קיים, לא נוגעים)
7. זמינות / יומן (קיים - לא נוגעים)
8. ביקורות (קיים - לא נוגעים)
9. כפתור תחתון "קבעי מועד" (קיים - לא נוגעים)
```

#### בלוק 2: בדף עריכת המנקה
מתווסף **בדיוק** במיקום הזה:
```
1. פרטים אישיים (קיים - לא נוגעים)
2. תמונת פרופיל (קיים - לא נוגעים)
3. אודות (קיים - לא נוגעים)
4. תת-קטגוריה: "נקיון" (כבר קיים)
↓ ↓ ↓
5. ✨ הבלוק החדש - "המקצועיות שלך" ← כאן!
   (מופיע **רק** אם נבחר "נקיון" כתת-קטגוריה)
↑ ↑ ↑
6. גלריית עבודות (קיים - לא נוגעים)
7. יומן זמינות (קיים - לא נוגעים)
8. כפתורי שמירה (קיים - לא נוגעים)
```

---

## 🔄🔄🔄 חובת סנכרון מלא עם המערכת הקיימת

זה **קריטי במיוחד** ללקוח אבי - חייב להיות מסונכרן 100% עם האפליקציה!

### 1️⃣ סנכרון צ'אט - חובה!
**הצ'אט בתוך בלוק הלקוח חייב לעבוד עם מערכת הצ'אט הקיימת באפליקציה!**

```dart
// ❌ לא לבנות מערכת צ'אט חדשה!
// ✅ להשתמש במערכת הקיימת:

void onChatButtonPressed() {
  // נווט למסך הצ'אט הקיים באפליקציה
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ExistingChatScreen(  // המסך הקיים באפליקציה
      otherUserId: widget.providerId,
      otherUserName: provider.name,
      otherUserAvatar: provider.avatarUrl,
      bookingContext: BookingContext(
        category: 'cleaning',
        bookingDraftId: currentBookingDraft?.id,
      ),
    ),
  ));
}
```

**Quick Reply chips** ("זמינה לשבת?" / "מביאה ציוד?") - גם הם פותחים את הצ'אט הקיים עם הטקסט מוכן:

```dart
void onQuickReplyTap(String text) {
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ExistingChatScreen(
      otherUserId: widget.providerId,
      preFilledMessage: text,  // הטקסט מוכן בשדה ההקלדה
    ),
  ));
}
```

### 2️⃣ סנכרון יומן - חובה!
**הכפתור "קבעי מועד · ₪234" חייב להוביל ליומן הקיים של נותן השירות!**

```dart
void onBookNowPressed() {
  // ❌ לא לבנות יומן חדש!
  // ✅ להשתמש ביומן הקיים של נותן השירות

  // אסוף את כל הבחירות של הלקוח
  final preferences = CleaningPreferences(
    cleaningType: selectedType,
    propertyDetails: propertyDetails,
    selectedTasks: selectedChecklistTasks,
    recurrence: selectedRecurrence,
    ecoMode: ecoEnabled,
    accessMethod: accessMethod,
    specialInstructions: instructionsText,
    addOns: selectedAddOns,
    totalPrice: calculatedTotal,
  );

  // נווט ליומן הקיים עם הפרטים
  Navigator.push(context, MaterialPageRoute(
    builder: (_) => ExistingCalendarScreen(  // היומן הקיים!
      providerId: widget.providerId,
      bookingPreferences: preferences,
      totalPrice: calculatedTotal,
      duration: estimatedDuration,
    ),
  ));
}
```

**🔴 חשוב במיוחד**: אם המנקה סימנה ביומן הקיים שהיא לא זמינה ב-21/04 → היומן יציג את היום הזה כחסום, **בלי שצריך לכתוב קוד מיוחד**. הסנכרון הוא דרך אותו `availability` collection ב-Firestore.

### 3️⃣ סנכרון Express Reorder - חובה!
**הביקורת והנתונים בExpress Reorder חייבים להגיע מהיסטוריית ההזמנות הקיימת:**

```dart
Future<LastBooking?> getLastBookingWithProvider(String providerId, String userId) async {
  // קח מההיסטוריה הקיימת ב-bookings collection
  final query = await firestore
    .collection('bookings')
    .where('clientId', isEqualTo: userId)
    .where('providerId', isEqualTo: providerId)
    .where('status', isEqualTo: 'completed')
    .orderBy('completedAt', descending: true)
    .limit(1)
    .get();

  if (query.docs.isEmpty) return null;

  final lastBooking = query.docs.first.data();

  // קח את הביקורת הקיימת
  final reviewQuery = await firestore
    .collection('reviews')
    .where('bookingId', isEqualTo: query.docs.first.id)
    .limit(1)
    .get();

  return LastBooking(
    cleaningType: lastBooking['cleaningPreferences']['cleaningType'],
    propertySize: lastBooking['cleaningPreferences']['propertyDetails']['squareMeters'],
    durationHours: lastBooking['estimatedDuration'],
    daysAgo: DateTime.now().difference(lastBooking['completedAt'].toDate()).inDays,
    rating: reviewQuery.docs.isNotEmpty ? reviewQuery.docs.first['rating'] : null,
    reviewText: reviewQuery.docs.isNotEmpty ? reviewQuery.docs.first['text'] : null,
  );
}
```

### 4️⃣ סנכרון Trust Center - חובה!
**ה-badges ב-Trust Center חייבים לקרוא מנתונים הקיימים של נותן השירות:**

```dart
class TrustCenterData {
  bool idVerified;        // קיים ב-users.verifications.idCard
  bool backgroundChecked; // קיים ב-users.verifications.backgroundCheck
  int insuranceAmount;    // חדש - יתוסף ל-cleaningProfile.insurance
  bool escrowEnabled;     // ברירת מחדל true (תכונת המערכת)
}
```

### 5️⃣ סנכרון "Recurring customers" באנליטיקה למנקה
המנקה רואה כמה לקוחות קבועים יש לה - חייב להגיע מ-bookings collection:

```dart
Future<int> countRecurringCustomers(String providerId) async {
  final query = await firestore
    .collection('bookings')
    .where('providerId', isEqualTo: providerId)
    .where('cleaningPreferences.recurrence.enabled', isEqualTo: true)
    .where('cleaningPreferences.recurrence.active', isEqualTo: true)
    .get();

  // unique clients only
  final uniqueClientIds = query.docs.map((d) => d['clientId']).toSet();
  return uniqueClientIds.length;
}
```

---

## 🎯 Goal | מטרה

לבנות את קטגוריית הנקיון הכי טובה בעולם ב-AnySkill - רמה של **Handy + Cleanster + Turno + AllBetter משולבים** עם פיצ'רים שאף אחד לא עושה יחד.

### היתרונות התחרותיים שלנו (10!):
1. **🤝 הלקוח בוחר את המנקה** - לא dispatch (הסיפור הגדול!)
2. **📋 Custom Checklist** - הלקוח מסמן מה חשוב במיוחד
3. **🔄 הזמנה חוזרת אוטומטית** - שבועי/דו-שבועי/חודשי
4. **📸 לפני/אחרי** - תמונות אוטומטיות בWhatsApp
5. **🌱 Eco Mode** - חומרים ירוקים אופציונלי
6. **⏱️ זמנים גמישים** - מחר 8:00, סוף שבוע
7. **💎 חבילות עסקיות** - 4×/8×/יומי
8. **🛡️ Trust Center** - 4 אימותים בולטים
9. **💯 Quality Guarantee** - אחריות 100%, נקיון חוזר חינם
10. **💬 Live Chat** - מסונכרן עם צ'אט האפליקציה

---

## 📦 קבצים נוספים בפרויקט הזה | Additional files

- **`02_PROVIDER_EDIT_CLEANING.md`** - מפרט מלא של דף עריכת המנקה
- **`03_CLIENT_BOOKING_CLEANING.md`** - מפרט מלא של דף הלקוח

**קרא את שני הקבצים הנוספים לפני שמתחיל לקודד!**

---

## 🗄️ Firestore Schema - שדות חדשים

### Collection: `users` (היכן ששמורים נותני שירות)

הוסף את השדה `cleaningProfile` **רק אם** המסמך מכיל `category == 'cleaning'` או שתת-הקטגוריה היא 'cleaning':

```javascript
{
  // ...כל השדות הקיימים נשארים בדיוק כמו שהם...

  // === שדה חדש - מופיע רק למנקות ===
  "cleaningProfile": {
    // אימותים (חובה!)
    "verifications": {
      "idVerified": true,
      "idVerifiedAt": "2026-03-15T10:00:00Z",
      "backgroundChecked": true,
      "backgroundCheckedAt": "2026-03-20T10:00:00Z",
      "backgroundCheckDocument": "url-to-pdf",
      "referencesCount": 3,
      "referencesVerified": true,
      "insuranceAmount": 10000,  // ₪
      "insuranceProvider": "מגדל",
      "insuranceValidUntil": "2027-01-01"
    },

    // סוגי נקיון שמבצעת (מתוך 6)
    "cleaningTypes": [
      "regular_home",      // 🏠 בית רגיל
      "deep_renovation",   // ✨ Deep / לאחר שיפוץ
      "airbnb"             // 🏨 Airbnb
      // אופציות נוספות: "office", "store", "event"
    ],

    // סוגי לקוחות (מתוך 4)
    "customerTypes": [
      "private",           // 👤 פרטיים
      "business"           // 🏢 עסקים
      // אופציות נוספות: "stores", "restaurants"
    ],

    // Eco Mode
    "ecoMode": {
      "enabled": true,
      "surcharge": 25,     // ₪ תוספת לביקור
      "certified": "EcoCert"
    },

    // Checklist בסיסי שהמנקה מגדירה
    "baseChecklist": [
      {
        "categoryId": "bedroom",
        "categoryNameHe": "חדר שינה",
        "categoryIcon": "🛏️",
        "tasks": [
          {
            "id": "bedroom_1",
            "nameHe": "החלפת מצעים + סידור מיטה",
            "withPhoto": true,    // 📷 - האם תמונה אוטומטית
            "addOn": null
          },
          {
            "id": "bedroom_2",
            "nameHe": "שאיבת אבק + ניגוב משטחים",
            "withPhoto": false,
            "addOn": null
          },
          {
            "id": "bedroom_3",
            "nameHe": "חלונות פנימיים",
            "withPhoto": false,
            "addOn": null
          }
        ]
      },
      {
        "categoryId": "bathroom",
        "categoryNameHe": "חדר אמבטיה",
        "categoryIcon": "🚿",
        "tasks": [
          {
            "id": "bathroom_1",
            "nameHe": "ניקוי מקלחת + אסלה לעומק",
            "withPhoto": true,
            "addOn": null
          },
          {
            "id": "bathroom_2",
            "nameHe": "הסרת אבנית מברזים",
            "withPhoto": false,
            "addOn": null
          }
        ]
      },
      {
        "categoryId": "kitchen",
        "categoryNameHe": "מטבח",
        "categoryIcon": "🍽️",
        "tasks": [
          {
            "id": "kitchen_1",
            "nameHe": "משטחי עבודה + כיורים",
            "withPhoto": false,
            "addOn": null
          },
          {
            "id": "kitchen_2",
            "nameHe": "ניקוי תנור פנימי",
            "withPhoto": false,
            "addOn": { "amount": 40, "currency": "ILS" }  // +₪40
          }
        ]
      }
    ],

    // מחירון לפי גודל הבית
    "pricing": {
      "regular_home": {
        "upTo60sqm": 180,      // עד 60 מ"ר (דירת 2)
        "60to100sqm": 240,     // 60-100 מ"ר (דירת 3-4)
        "100to150sqm": 320,    // 100-150 מ"ר (5/קוטג')
        "over150sqm": 420      // מעל 150 (פנטהאוז)
      },
      "typeMultipliers": {
        "deep_renovation": 2.0,  // +100%
        "airbnb": 0.8,          // -20% (מהיר)
        "office": 1.5,
        "store": 1.3,
        "event": 1.7
      },
      "addOns": {
        "oven_inside": 40,      // 🍽️ תנור פנימי
        "fridge_inside": 30,    // 🧊 מקרר פנימי
        "windows_outside": 60,  // 🪟 חלונות חיצוניים
        "sofa_steam": 120       // 🛋️ ניקוי ספות בקיטור
      }
    },

    // הנחות מנוי קבוע
    "recurringDiscounts": {
      "weekly": 15,        // שבועי -15%
      "biweekly": 10,      // דו-שבועי -10% (default)
      "monthly": 5         // חודשי -5%
    },

    // Quality Guarantee
    "qualityGuarantee": {
      "enabled": true,
      "reportWindowHours": 24,
      "reCleanFree": true,
      "fullRefund": true
    },

    // אזורי שירות
    "serviceArea": {
      "cities": ["תל אביב", "רמת גן", "גבעתיים", "הרצליה"],
      "workHours": {
        "morning_7_12": true,
        "afternoon_12_17": true,
        "evening_17_22": false,
        "weekend": false
      }
    },

    // חבילות עסקיות
    "businessPackages": [
      {
        "id": "package_4x",
        "nameHe": "📅 4 ביקורים/חודש",
        "visitsPerMonth": 4,
        "monthlyPrice": 890,
        "enabled": true,
        "activeCustomers": 2  // לתצוגה למנקה
      },
      {
        "id": "package_8x",
        "nameHe": "🚀 8 ביקורים/חודש",
        "visitsPerMonth": 8,
        "monthlyPrice": 1690,
        "enabled": true,
        "activeCustomers": 1
      }
    ]
  }
}
```

### Collection: `bookings` (חדש בכל הזמנת נקיון)

```javascript
{
  // ...שדות הזמנה קיימים...

  "cleaningPreferences": {
    // סוג הנקיון
    "cleaningType": "regular_home",  // regular_home, deep_renovation, airbnb, office, store, event

    // פרטי הנכס
    "propertyDetails": {
      "bedrooms": 2,
      "bathrooms": 1,
      "squareMeters": 80,
      "hasPets": true,
      "petType": "dog",
      "floor": "elevator",  // ground, elevator, stairs
      "specialNotes": ""
    },

    // משך משוער (מחושב אוטומטית)
    "estimatedDurationMinutes": 180,

    // משימות שהלקוח בחר (subset מהbase checklist + add-ons)
    "selectedTasks": [
      "bedroom_1", "bedroom_2", "bedroom_3",
      "bathroom_1", "bathroom_2",
      "kitchen_1"
    ],

    // משימות שהלקוח הוסיף בעצמו
    "customTasks": [
      { "nameHe": "ניקוי שטיחים", "estimatedMinutes": 30 }
    ],

    // Add-ons שנבחרו
    "selectedAddOns": ["oven_inside"],  // +₪40

    // תזמון
    "schedulingType": "recurring",  // one_time, recurring
    "recurrence": {
      "enabled": true,
      "frequency": "biweekly",    // weekly, biweekly, monthly
      "discount": 10,              // %
      "startDate": "2026-04-21T08:00:00Z",
      "nextVisitDate": "2026-05-04T08:00:00Z",
      "active": true,              // לבדיקה אם המנוי פעיל
      "cancellableAnytime": true
    },

    // Eco Mode
    "ecoMode": {
      "enabled": true,
      "surcharge": 25
    },

    // שיטת גישה
    "accessMethod": "client_present",  // client_present, key_code
    "specialInstructions": "יש לי כלב קטן וידידותי. אנא אל תשתמשי במכשיר אדים בסלון.",

    // Quality Guarantee
    "qualityGuaranteeOptedIn": true,

    // Photo documentation
    "beforeAfterPhotos": {
      "enabled": true,
      "deliveryChannel": "whatsapp",  // whatsapp, in_app
      "rooms": ["bedroom", "bathroom", "kitchen"]
    },

    // מחיר
    "priceBreakdown": {
      "basePriceForType": 240,
      "addOnsTotal": 0,
      "ecoSurcharge": 25,
      "subtotal": 265,
      "recurringDiscount": -31,
      "total": 234
    }
  }
}
```

### Collection: `cleaning_jobs_progress` (חדש - מעקב בזמן אמת)

לשליחת תמונות לפני/אחרי + מעקב משימות:

```javascript
{
  "bookingId": "abc123",
  "providerId": "cleaner_xyz",
  "clientId": "user_456",
  "status": "in_progress",  // not_started, in_progress, completed
  "startedAt": "2026-04-21T08:05:00Z",
  "completedAt": null,
  "tasksProgress": [
    {
      "taskId": "bedroom_1",
      "status": "completed",
      "completedAt": "2026-04-21T08:30:00Z",
      "photoBeforeUrl": "https://...",
      "photoAfterUrl": "https://..."
    },
    {
      "taskId": "bedroom_2",
      "status": "in_progress"
    }
  ],
  "issuesReported": [],  // אם המנקה דיווחה על בעיה
  "qualityFeedback": null  // יוקטן בסיום על-ידי הלקוח
}
```

---

## 🛠️ קבצים שצריך ליצור | Files to create

### Models
- `lib/models/cleaning_profile.dart` - המודל הראשי
- `lib/models/cleaning_preferences.dart` - העדפות בהזמנה
- `lib/models/cleaning_property_details.dart`
- `lib/models/cleaning_checklist.dart`
- `lib/models/cleaning_task.dart`
- `lib/models/cleaning_recurrence.dart`
- `lib/models/cleaning_business_package.dart`
- `lib/models/cleaning_job_progress.dart` - 🆕 לזמן אמת
- `lib/models/cleaning_trust_data.dart`

### Constants
- `lib/constants/cleaning_types_catalog.dart` - 6 סוגי נקיון
- `lib/constants/cleaning_customer_types.dart` - 4 סוגי לקוחות
- `lib/constants/cleaning_addons_catalog.dart` - 4 add-ons
- `lib/constants/cleaning_default_checklists.dart` - תבניות checklist

### Provider Edit Screen
- `lib/screens/provider_edit/widgets/cleaning_settings_block.dart` - הבלוק הראשי
- `lib/screens/provider_edit/widgets/cleaning_hero_stats.dart`
- `lib/screens/provider_edit/widgets/cleaning_verifications_section.dart`
- `lib/screens/provider_edit/widgets/cleaning_types_picker.dart`
- `lib/screens/provider_edit/widgets/cleaning_eco_editor.dart`
- `lib/screens/provider_edit/widgets/cleaning_checklist_builder.dart` - 🆕 חשוב!
- `lib/screens/provider_edit/widgets/cleaning_pricing_editor.dart`
- `lib/screens/provider_edit/widgets/cleaning_recurring_discounts_editor.dart`
- `lib/screens/provider_edit/widgets/cleaning_service_area_editor.dart`
- `lib/screens/provider_edit/widgets/cleaning_business_packages_editor.dart`

### Client Profile Screen
- `lib/screens/provider_profile/widgets/cleaning_block.dart` - הבלוק הראשי
- `lib/screens/provider_profile/widgets/cleaning_hero_section.dart`
- `lib/screens/provider_profile/widgets/cleaning_trust_center.dart` - 🆕 חשוב!
- `lib/screens/provider_profile/widgets/cleaning_express_reorder.dart`
- `lib/screens/provider_profile/widgets/cleaning_type_selector.dart`
- `lib/screens/provider_profile/widgets/cleaning_property_setup.dart`
- `lib/screens/provider_profile/widgets/cleaning_smart_checklist.dart`
- `lib/screens/provider_profile/widgets/cleaning_recurrence_selector.dart`
- `lib/screens/provider_profile/widgets/cleaning_eco_toggle.dart`
- `lib/screens/provider_profile/widgets/cleaning_access_method.dart`
- `lib/screens/provider_profile/widgets/cleaning_before_after_card.dart`
- `lib/screens/provider_profile/widgets/cleaning_quality_guarantee.dart` - 🆕 חשוב!
- `lib/screens/provider_profile/widgets/cleaning_social_proof.dart`
- `lib/screens/provider_profile/widgets/cleaning_chat_preview.dart` - 🆕 מסונכרן!
- `lib/screens/provider_profile/widgets/cleaning_business_packages.dart`
- `lib/screens/provider_profile/widgets/cleaning_booking_summary.dart`

### Services
- `lib/services/cleaning_booking_service.dart` - חישוב מחירים
- `lib/services/cleaning_duration_calculator.dart` - חישוב משך לפי AI/heuristic
- `lib/services/cleaning_recurring_scheduler.dart` - יצירת ביקורים עתידיים
- `lib/services/cleaning_photo_documentation_service.dart` - WhatsApp integration
- `lib/services/cleaning_quality_guarantee_service.dart` - דיווח על בעיות

### 🔴 חובה - שימוש בשירותים קיימים (לא לבנות חדש!):
- **Chat**: `lib/services/chat_service.dart` (קיים) - השתמש בו לפתיחת צ'אט
- **Calendar**: `lib/screens/calendar/calendar_screen.dart` (קיים) - השתמש בו ליומן
- **Bookings**: `lib/services/booking_service.dart` (קיים) - השתמש בו ליצירת הזמנה

### Cloud Functions (functions/index.js)
- `syncCleaningProfileToListings` - מסנכרן הגדרות
- `calculateCleaningDuration` - Gemini AI לחישוב משך
- `scheduleRecurringCleanings` - יצירת ביקורים עתידיים אוטומטית
- `triggerBeforeAfterPhotosWhatsApp` - שליחת תמונות בWhatsApp
- `processQualityComplaint` - טיפול בתלונות איכות

---

## 🤖 Gemini AI Integration

**חובה: השתמש ב-Gemini, לא ב-Claude API!**

### Cloud Function לחישוב משך הנקיון:
```javascript
// functions/calculateCleaningDuration.js
const { GoogleGenerativeAI } = require('@google/generative-ai');

exports.calculateCleaningDuration = functions.https.onCall(async (data, context) => {
  const {
    cleaningType,
    bedrooms,
    bathrooms,
    squareMeters,
    hasPets,
    selectedTasksCount,
    addOnsCount
  } = data;

  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash-lite" });

  const prompt = `אתה מומחה לתעשיית הנקיון. חשב משך נקיון מומלץ:
  - סוג נקיון: ${cleaningType}
  - חדרי שינה: ${bedrooms}
  - חדרי אמבט: ${bathrooms}
  - מ"ר: ${squareMeters}
  - בעלי-חיים: ${hasPets}
  - משימות נבחרות: ${selectedTasksCount}
  - תוספות: ${addOnsCount}

  השב בפורמט JSON:
  {
    "estimatedMinutes": number,
    "rangeMin": number,
    "rangeMax": number,
    "reasoning": "string בעברית קצר"
  }`;

  const result = await model.generateContent(prompt);
  return JSON.parse(result.response.text());
});
```

---

## ✅ Acceptance Criteria | קריטריונים לקבלה

### חובה לעבוד | Must work
- [ ] בעריכת פרופיל - בחירת תת-קטגוריה "נקיון" פותחת **אוטומטית** את בלוק "המקצועיות שלך" מתחת
- [ ] ביטול בחירת "נקיון" - מסתיר את הבלוק (אבל שומר את ההגדרות)
- [ ] **אימותים חובה**: לא ניתן לאשר פרופיל ללא ת"ז + בדיקת רקע + ממליצים
- [ ] **🔄 סנכרון יומן**: כפתור "קבעי מועד" פותח את **היומן הקיים** עם פרטי ההזמנה
- [ ] **🔄 סנכרון יומן זמינות**: ימים שהמנקה חסמה ביומן הקיים מופיעים כחסומים ללקוח
- [ ] **🔄 סנכרון צ'אט**: כפתור "פתחי צ'אט עם שרה" פותח את **הצ'אט הקיים** באפליקציה
- [ ] **🔄 סנכרון Quick Reply**: לחיצה על "זמינה לשבת?" פותחת את הצ'אט עם הטקסט מוכן בשדה ההקלדה
- [ ] **🔄 סנכרון Express Reorder**: הנתונים מגיעים מהזמנות קודמות + ביקורות מהמערכת
- [ ] **🔄 סנכרון Recurring Customers**: הספירה מגיעה מbookings collection בזמן אמת
- [ ] **🛡️ Trust Center** מציג נתונים אמיתיים מ-`users.verifications`
- [ ] **📋 Smart Checklist** עם progress bars ו-toggle לכל משימה
- [ ] **💯 Quality Guarantee** - דיווח על בעיות תוך 24 שעות מפעיל cloud function
- [ ] **📸 Before/After photos** נשלחות אוטומטית בWhatsApp בסיום הנקיון
- [ ] **🌱 Eco Mode** מחושב במחיר במקרה של בחירה
- [ ] רק סוגי נקיון שהמנקה סימנה - מוצגים ללקוח
- [ ] חבילות עסקיות מוצגות אם המנקה הגדירה
- [ ] תמיכה מלאה ב-RTL (עברית)
- [ ] flutter analyze: 0 issues

### אסור | Must NOT happen
- [ ] **לא לגעת** בחלקים הקיימים של דף הפרופיל
- [ ] **לא לגעת** ביומן הקיים - רק נווט אליו
- [ ] **לא לבנות** מערכת צ'אט חדשה - השתמש בקיימת!
- [ ] **לא לשנות** routing של קטגוריות אחרות
- [ ] **לא להוסיף** monthly subscriptions ללקוחות פרטיים (רק לעסקים!)
- [ ] **לא להשתמש** ב-Claude API (Gemini בלבד)
- [ ] **לא להציג** הגדרות נקיון אם לא נבחר "נקיון" כתת-קטגוריה
- [ ] **לא לבנות** היסטוריית עבודות חדשה - תקרא מ-bookings + reviews

---

## 🎨 Design System - Dark Premium with Cyan/Teal

### Base Colors
```dart
// Dark base gradient (לקטגוריית נקיון)
const darkBase = Color(0xFF0A0E1A);
const darkBaseMid = Color(0xFF0F1A2E);
const darkBaseDeep = Color(0xFF0F1420);

// Primary - Cyan/Teal (ייחודי לנקיון)
const cleaningCyanDark = Color(0xFF0891B2);
const cleaningCyanMid = Color(0xFF06B6D4);
const cleaningCyanLight = Color(0xFF67E8F9);
const cleaningCyanPale = Color(0xFFECFEFF);

// Status colors
const statusGreen = Color(0xFF16A34A);
const statusGreenLight = Color(0xFF4ADE80);
const statusGreenBg = Color(0xFF86EFAC);

const statusRed = Color(0xFFDC2626);
const statusRedLight = Color(0xFFFCA5A5);

// Unique features
const purpleMedium = Color(0xFFA855F7);  // Express Reorder + Checklist Builder
const purpleDark = Color(0xFF7E22CE);
const amberMedium = Color(0xFFF59E0B);   // Before/After photos
const blueMedium = Color(0xFF3B82F6);    // Chat
```

### Glassmorphism Pattern
```dart
decoration: BoxDecoration(
  color: Colors.white.withOpacity(0.04),
  border: Border.all(
    color: Colors.white.withOpacity(0.1),
    width: 1,
  ),
  borderRadius: BorderRadius.circular(22),
)
```

### Ambient Gradients (רקע)
3 orbs צבעוניים כ-background:
1. **Orb cyan** (top-right) - `radial-gradient(circle, rgba(6,182,212,0.22) 0%, transparent 70%)`
2. **Orb green** (middle-left) - `radial-gradient(circle, rgba(34,197,94,0.15) 0%, transparent 70%)`
3. **Orb purple** (bottom-right) - `radial-gradient(circle, rgba(168,85,247,0.12) 0%, transparent 70%)`

### Hero Section
- **כותרת ב-2 שורות**: "בואי נתאים את הניקיון שלך" עם gradient text (לבן → cyan)
- **Subtitle עם value props**: "3 דקות ההזמנה · ביטוח עד ₪10,000 · אחריות מלאה"
- **3 status badges**: "זמינה היום" / "🌱 Eco-Certified" / "🏆 Top 3"
- **❌ אין תמונת פרופיל** (כבר קיים למעלה)
- **❌ אין KPIs כפולים** (2,148/4.96 כבר קיים בפרופיל)

---

## 🌐 Localization Keys (מרכזיים)

הוסף ל-`l10n/app_he.arb`, `app_en.arb`, `app_es.arb`, `app_ar.arb`:

```json
{
  "cleaning_settings_banner": "הגדרות ייעודיות לנקיון",
  "cleaning_hero_title_line1": "בואי נתאים",
  "cleaning_hero_title_line2": "את הניקיון שלך",
  "cleaning_hero_subtitle": "3 דקות ההזמנה · ביטוח עד ₪10,000 · אחריות מלאה",
  "cleaning_status_available_today": "זמינה היום",
  "cleaning_status_eco_certified": "🌱 Eco-Certified",
  "cleaning_status_top_provider": "🏆 Top {rank}",

  "cleaning_trust_center_title": "Trust Center",
  "cleaning_trust_center_subtitle": "למה את יכולה לסמוך עליה",
  "cleaning_trust_id_verified": "ת\"ז מאומתת",
  "cleaning_trust_background_check": "בדיקת רקע",
  "cleaning_trust_insurance": "ביטוח ₪{amount}",
  "cleaning_trust_escrow": "תשלום בנאמנות",

  "cleaning_express_reorder_title": "Express Reorder · נקיון אחרון לפני {days} ימים",
  "cleaning_express_reorder_button": "חזור",

  "cleaning_step_1_title": "איזה ניקיון את רוצה?",
  "cleaning_step_1_subtitle": "בחרי את הסוג שמתאים לך",
  "cleaning_type_regular": "בית רגיל",
  "cleaning_type_deep": "Deep / שיפוץ",
  "cleaning_type_airbnb": "Airbnb",
  "cleaning_type_office": "משרדים",
  "cleaning_type_store": "חנויות",
  "cleaning_type_event": "לפני אירוע",

  "cleaning_step_2_title": "פרטי הנכס שלך",
  "cleaning_step_2_subtitle": "המחיר מתעדכן בזמן אמת",
  "cleaning_property_bedrooms": "🛏️ חדרי שינה",
  "cleaning_property_bathrooms": "🚿 חדרי אמבט",
  "cleaning_property_size": "📐 גודל (מ\"ר)",
  "cleaning_property_pets": "🐕 בעלי-חיים",
  "cleaning_property_floor": "🪜 קומה",
  "cleaning_property_floor_ground": "קרקע",
  "cleaning_property_floor_elevator": "מעלית",
  "cleaning_property_estimated_duration": "משך משוער: {hours} שעות",
  "cleaning_property_base_price": "מחיר בסיס: ₪{amount}",
  "cleaning_property_ai_calculated": "AI חישב",
  "cleaning_property_auto_saved": "💾 נשמר אוטומטית",

  "cleaning_step_3_title": "המשימות שלך",
  "cleaning_step_3_subtitle": "סמני מה חשוב במיוחד",
  "cleaning_step_3_active_count": "{count} פעיל",
  "cleaning_checklist_how_it_works": "איך זה עובד:",
  "cleaning_checklist_explanation": "שרה מבצעת את המשימות לפי הסדר. את תקבלי תמונה לכל משימה שמסומנת 📷",
  "cleaning_checklist_add_custom": "+ הוסף משימה אישית (כביסה, שטיחים...)",

  "cleaning_step_4_title": "מתי שרה תגיע?",
  "cleaning_step_4_subtitle": "חד פעמי או חוזר אוטומטית",
  "cleaning_schedule_one_time": "חד פעמי",
  "cleaning_schedule_one_time_hint": "בחרי תאריך",
  "cleaning_schedule_recurring": "קבוע",
  "cleaning_schedule_recurring_hint": "חיסכון עד 15%",
  "cleaning_frequency_question": "📆 איזו תדירות?",
  "cleaning_frequency_weekly": "שבועי",
  "cleaning_frequency_biweekly": "דו-שבועי",
  "cleaning_frequency_monthly": "חודשי",

  "cleaning_eco_title": "חומרים אקולוגיים",
  "cleaning_eco_subtitle": "בטוח לילדים, חיות מחמד, אלרגיות",
  "cleaning_eco_certification": "שרה תביא חומרים מאושרים EcoCert",

  "cleaning_step_5_title": "איך שרה תיכנס?",
  "cleaning_step_5_subtitle": "בחרי את שיטת הגישה",
  "cleaning_access_present": "אני בבית",
  "cleaning_access_present_hint": "אפתח לה",
  "cleaning_access_key": "מפתח/קוד",
  "cleaning_access_key_hint": "ללא נוכחות",
  "cleaning_special_instructions": "הוראות נוספות לשרה",

  "cleaning_photos_title": "תיעוד \"לפני ואחרי\"",
  "cleaning_photos_subtitle": "תקבלי תמונות אוטומטית בWhatsApp",
  "cleaning_photos_free_badge": "חינם",

  "cleaning_quality_title": "אחריות 100% שביעות רצון",
  "cleaning_quality_subtitle": "לא מרוצה? נקיון חוזר חינם תוך 24 שעות",
  "cleaning_quality_24h": "24 שעות",
  "cleaning_quality_24h_hint": "לדווח",
  "cleaning_quality_reclean": "נקיון חוזר",
  "cleaning_quality_reclean_hint": "חינם",
  "cleaning_quality_refund": "או החזר",
  "cleaning_quality_refund_hint": "מלא",

  "cleaning_recent_works_title": "העבודות האחרונות של שרה",
  "cleaning_recent_works_view_all": "ראי הכל →",

  "cleaning_chat_title": "שאלות לשרה?",
  "cleaning_chat_subtitle": "היא מגיבה תוך ~5 דקות",
  "cleaning_chat_status_online": "מקוונת",
  "cleaning_chat_button": "פתחי צ'אט עם שרה",
  "cleaning_chat_quick_1": "\"זמינה לשבת?\"",
  "cleaning_chat_quick_2": "\"מביאה ציוד?\"",

  "cleaning_business_packages_title": "חבילות לעסקים",
  "cleaning_business_packages_subtitle": "חיסכון של עד 30% למשרדים וחנויות",

  "cleaning_summary_total": "סך לתשלום",
  "cleaning_summary_discount": "−{percent}%",
  "cleaning_summary_was": "במקום ₪{original}",
  "cleaning_summary_due_to": "מנוי דו-שבועי",
  "cleaning_summary_duration": "משך",
  "cleaning_summary_cta": "קבעי מועד · ₪{amount}",
  "cleaning_summary_secure_payment": "תשלום בנאמנות",
  "cleaning_summary_cancel_24h": "ביטול עד 24 שע'",
  "cleaning_summary_full_warranty": "אחריות מלאה",

  "cleaning_provider_hero_title": "המקצועיות שלך",
  "cleaning_provider_hero_subtitle": "הגדרות שיביאו לך לקוחות בכל החודש",
  "cleaning_provider_recurring_customers": "{count} לקוחות חוזרים פעילים",
  "cleaning_provider_monthly_revenue": "הכנסה קבועה: ₪{amount}/חודש",
  "cleaning_provider_verifications_title": "אימותים",
  "cleaning_provider_verifications_required": "חובה - אימות נדרש לאישור הפרופיל",
  "cleaning_provider_checklist_builder_title": "Checklist בסיסי שלך",
  "cleaning_provider_checklist_builder_subtitle": "הלקוחות יוכלו להוסיף/להוריד לעצמם",
  "cleaning_provider_pricing_title": "מחירון לפי גודל הבית",
  "cleaning_provider_pricing_subtitle": "המערכת תחשב אוטומטית ללקוח",
  "cleaning_provider_recurring_discounts_title": "מנוי קבוע - הנחות",
  "cleaning_provider_recurring_discounts_subtitle": "הכנסה צפויה לאורך זמן"
}
```

---

## 📊 KPIs להצלחה

לאחר ההשקה - מדידה דרך AI CEO Agent:
- **Conversion rate** מקטגוריה להזמנה (יעד: +50%)
- **Express Reorder usage** - אחוז משתמשים חוזרים (יעד: >45%)
- **Recurring subscription rate** - אחוז שלוקחים מנוי (יעד: >30%)
- **Time to booking** - מכניסה לפרופיל ועד הזמנה (יעד: <90 שניות)
- **Eco Mode adoption** - אחוז שבוחרים Eco (יעד: >25%)
- **Quality Guarantee usage** - אחוז שמדווחים בעיות (יעד: <3%)
- **Chat engagement** - אחוז שפותחים צ'אט לפני הזמנה (יעד: >40%)
- **Trust Center clicks** - אחוז שלוחצים על Trust Center (יעד: >50%)

---

## 💾 בסיום העבודה - חובה לשמור!

### בסוף הפיתוח:
1. **שמור את כל קבצי MD** ב-`/docs/cleaning_upgrade/`
2. **עדכן CLAUDE.md** עם section חדש:
   ```markdown
   ## Section 34: Cleaning CSM (Category-Specific Module)
   - Provider edit block: cleaning_settings_block.dart
   - Client booking block: cleaning_block.dart
   - AI integration: Gemini (duration calculation)
   - 🆕 Trust Center (4 verification badges)
   - 🆕 Smart Checklist with progress bars
   - 🆕 Quality Guarantee 100%
   - 🆕 In-app Chat sync (uses existing ChatScreen)
   - 🆕 Calendar sync (uses existing CalendarScreen)
   - 🆕 Express Reorder from booking history
   - 🆕 Eco Mode toggle with EcoCert
   - 🆕 Before/After photos to WhatsApp
   - 🆕 Recurring discounts (15%/10%/5%)
   - 🆕 Business packages (4×/8×/daily)
   - All files in /docs/cleaning_upgrade/
   ```
3. **תעדכן userMemories** שעבר Cleaning CSM הוטמע
4. **רץ flutter analyze** ווודא 0 issues
5. **תכין סיכום מלא** של מה נעשה (כמו עם השליחויות)

---

## 🤖 Built for AnySkill - Claude Code Implementation

המסמך הזה הוא הבסיס. עבור פרטים מלאים על כל מסך - ראה את שני הקבצים הנוספים. בהצלחה! 🧼

**זכור: לא למחוק כלום! הכל מסונכרן עם המערכת הקיימת! רק להוסיף 2 בלוקים חדשים במיקומים המדויקים שצוינו למעלה.**
