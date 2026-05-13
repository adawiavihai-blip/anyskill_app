# 🪲 AnySkill - Pest Control Category Upgrade | שדרוג קטגוריית הדברה

> **קובץ ראשי - קרא אותו קודם** | **Main file - Read this first**
>
> פרויקט: שדרוג של קטגוריית הדברה באפליקציית AnySkill ברמה עולמית.
> Project: World-class upgrade of the pest control category in AnySkill app.
>
> **ארכיטקטורה:** Category-Specific Modules (CSM) - אותו עיקרון כמו שעשינו בעיסוי.

---

## ⛔⛔⛔ עקרונות חובה - אל תפר! קריטי! ⛔⛔⛔

### 🚫 אסור לך למחוק שום דבר!

זה הכלל הכי חשוב בכל הפרויקט:
- **אסור** למחוק חלקים קיימים מדף פרופיל הלקוח (אורן אברהמי - תמונה, אודות, השירות, יומן, ביקורות, כפתור תחתון)
- **אסור** למחוק חלקים קיימים מדף עריכת המדביר (פרטים אישיים, אודות, גלריה, יומן וכו׳)
- **אסור** לגעת במבנה הקיים של הפרופיל
- **אסור** לשנות את routing של קטגוריות אחרות
- **אסור** לבנות יומן חדש - להשתמש ביומן הקיים!
- **אסור** להשתמש ב-Claude API - השתמש ב-Gemini בלבד עבור AI

### ✅ אתה רק מוסיף 2 בלוקים חדשים:

#### בלוק 1: בדף הלקוח (פרופיל המדביר)
מתווסף **בדיוק** במיקום הזה:
```
1. Header (קיים - לא נוגעים)
2. Profile card עם תמונה, ✓ כחול, סטטיסטיקות (קיים - לא נוגעים)
3. גלריה + וידאו (קיים - לא נוגעים)
4. אודות (קיים - לא נוגעים)
↓ ↓ ↓
5. ✨ הבלוק החדש - "בנה את הטיפול שלך" + "מה צריך לדעת לפני" ← כאן!
↑ ↑ ↑
6. השירות (פגישה קצרה / מורחב / מלאה - קיים, לא נוגעים)
7. זמינות / יומן (קיים - לא נוגעים)
8. ביקורות (קיים - לא נוגעים)
9. כפתור תחתון "בחר תאריך ושעה" (קיים - לא נוגעים)
```

#### בלוק 2: בדף עריכת המדביר
מתווסף **בדיוק** במיקום הזה:
```
1. פרטים אישיים (קיים - לא נוגעים)
2. תמונת פרופיל (קיים - לא נוגעים)
3. אודות (קיים - לא נוגעים)
4. תת-קטגוריה: "הדברה" (כבר קיים)
↓ ↓ ↓
5. ✨ הבלוק החדש - "הגדרות הדברה" ← כאן!
   (מופיע **רק** אם נבחר "הדברה" כתת-קטגוריה)
↑ ↑ ↑
6. גלריית עבודות (קיים - לא נוגעים)
7. יומן זמינות (קיים - לא נוגעים)
8. כפתורי שמירה (קיים - לא נוגעים)
```

### 🔄 הסנכרון הוא הכי חשוב!
- כל מה שהמדביר מסמן/כותב בעריכה → מופיע ללקוח **בזמן אמת**
- אם המדביר מבטל סוג מזיק - הלקוח כבר לא יראה אותו
- אם המדביר משנה מחיר - מתעדכן מיידית
- אם המדביר מסמן "לא לשטוף שבוע" - הלקוח רואה את זה לפני ההזמנה

---

## 🎯 Goal | מטרה

להפוך את AnySkill לאפליקציית ההדברה הכי טובה בעולם - מתחרה ל-Orkin, Terminix, Rentokil + תכונות שאף אחד לא עושה (AI לזיהוי מזיק מתמונה, לכידת בעלי חיים, הדברה ירוקה, שקיפות מחיר מלאה).

### היתרונות התחרותיים שלנו:
1. **🤖 AI לזיהוי מזיק** מתמונה (Gemini Vision)
2. **🚨 הזמנה מיידית "חירום"** עם תוספת מחיר אוטומטית
3. **💰 שקיפות מחיר מלאה** - "מחיר סופי, ללא הפתעות"
4. **🐍 לכידת בעלי חיים** (נחשים, יונים, עטלפים)
5. **🌿 הדברה ירוקה** מודגשת לבני בית מיוחדים
6. **📸 תמונות לפני/אחרי + דוח דיגיטלי** (הגנה משפטית)
7. **📋 הוראות התנהלות לאחר טיפול** - חדש! אף אחד בעולם לא עושה כמו שצריך

---

## 📦 קבצים נוספים בפרויקט הזה | Additional files

- **`02_PROVIDER_EDIT_PESTCONTROL.md`** - מפרט מלא של דף עריכת המדביר
- **`03_CLIENT_BOOKING_PESTCONTROL.md`** - מפרט מלא של דף הלקוח

**קרא את שני הקבצים הנוספים לפני שמתחיל לקודד!**

---

## 🗄️ Firestore Schema - שדות חדשים

### Collection: `users` (היכן ששמורים נותני שירות)

הוסף את השדה `pestControlProfile` **רק אם** המסמך מכיל `category == 'pest_control'` או שתת-הקטגוריה היא 'pest_control':

```javascript
{
  // ...כל השדות הקיימים נשארים בדיוק כמו שהם...

  // === שדה חדש - מופיע רק למדבירים ===
  "pestControlProfile": {
    // רישיונות (חובה לפי חוק בישראל!)
    "licenses": [
      {
        "id": "moep_4127",
        "type": "ministry_environmental_protection",
        "nameHe": "רישיון משרד הגנת הסביבה",
        "licenseNumber": "4127",
        "validUntil": "2027-12-31",
        "verified": true,
        "verifiedAt": "2026-04-15T10:00:00Z"
      },
      {
        "id": "snake_catcher",
        "type": "snake_catcher",
        "nameHe": "לוכד נחשים מוסמך",
        "issuedBy": "רשות הטבע והגנים",
        "verified": true
      }
    ],

    // סוגי מזיקים שהמדביר מטפל בהם (מתוך 14 אופציות)
    "pestTypes": [
      "cockroaches", "ants", "bedbugs", "fleas", "mosquitoes",
      "rats", "mice", "snakes"
    ],

    // שיטות טיפול שמציע (מתוך 5 אופציות)
    "treatmentMethods": [
      "green",        // הדברה ירוקה (מומלץ!)
      "regular_spray", // ריסוס רגיל
      "heat_treatment" // טיפול בחום
      // אופציות נוספות: "injection_baits", "fumigation_anoxia"
    ],

    // סוגי לקוחות (מתוך 6)
    "customerTypes": [
      "private",      // פרטיים
      "restaurants",  // מסעדות
      "kindergartens" // גני ילדים
      // אופציות נוספות: "offices", "hotels", "industrial"
    ],

    // זמינות ותגובה
    "availability": {
      "emergencyService": {
        "enabled": true,
        "additionalFee": 150,  // ₪ תוספת לחירום (תוך שעה)
      },
      "available247": true,
      "averageArrivalTime": 45  // דקות
    },

    // אזורי שירות
    "serviceArea": {
      "radiusKm": 30,
      "travelFee": 40,           // ₪ לכיוון
      "freeRadiusKm": 15         // עד X ק"מ - חינם
    },

    // תעריפים בסיסיים (שקיפות מלאה)
    "basePricing": {
      "apartment_3_4_rooms": 290,
      "private_house": 450,
      "restaurant_small_business": 350,
      "animal_capture": 220
    },

    // אחריות ושירות
    "warrantyAndService": {
      "warrantyMonths": 3,        // 1, 3, או 6
      "digitalReport": true,
      "beforeAfterPhotos": true
    },

    // 🆕 חבילות תחזוקה
    "maintenancePackages": [
      {
        "id": "pkg_quarterly_home",
        "nameHe": "רבעוני · ביתי",
        "type": "quarterly",
        "treatmentsCount": 4,
        "discountPercent": 30,
        "pricePerTreatment": 199,
        "enabled": true,
        "activeCustomers": 12  // לתצוגה למדביר בלבד
      },
      {
        "id": "pkg_monthly_business",
        "nameHe": "חודשי · עסקי",
        "type": "monthly",
        "treatmentsCount": 12,
        "pricePerTreatment": 149,
        "enabled": true,
        "activeCustomers": 3
      }
    ],

    // 🆕 הוראות והתנהלות לאחר טיפול - חדש!
    "treatmentInstructions": {
      // הוראות מובנות עם משך זמן (סמן + בחר)
      "structuredInstructions": [
        {
          "id": "evacuate_home",
          "type": "evacuate_home",
          "icon": "🚪",
          "titleHe": "פינוי הבית",
          "enabled": true,
          "duration": "4_hours",  // אופציות: 2_hours, 4_hours, 8_hours
          "color": "red"
        },
        {
          "id": "remove_pets",
          "type": "remove_pets",
          "icon": "🐕",
          "titleHe": "הרחקת חיות מחמד",
          "enabled": true,
          "duration": "8_hours",  // אופציות: 4_hours, 8_hours, 24_hours
          "color": "orange"
        },
        {
          "id": "no_washing",
          "type": "no_washing",
          "icon": "💧",
          "titleHe": "לא לשטוף את הבית",
          "enabled": true,
          "duration": "1_week",   // אופציות: 3_days, 1_week, 2_weeks
          "color": "blue"
        },
        {
          "id": "ventilation",
          "type": "ventilation",
          "icon": "🪟",
          "titleHe": "לאוורר אחרי החזרה",
          "enabled": true,
          "duration": "30_min",   // אופציות: 30_min, 1_hour
          "color": "green"
        },
        {
          "id": "cover_food",
          "type": "cover_food",
          "icon": "🍽️",
          "titleHe": "לכסות מזון ומים",
          "enabled": false
        },
        {
          "id": "cover_aquarium",
          "type": "cover_aquarium",
          "icon": "🐠",
          "titleHe": "לכסות אקווריומים",
          "enabled": false
        },
        {
          "id": "remove_ceramics",
          "type": "remove_ceramics",
          "icon": "🧴",
          "titleHe": "להוציא חפצי קרמיקה",
          "enabled": false
        }
      ],
      // הוראות אישיות חופשיות (עד 500 תווים)
      "customInstructions": "לאחר חזרה הביתה, מומלץ לנקות משטחי עבודה במטבח עם מים בלבד. במקרה של ריח חזק, ניתן ליצור איתי קשר ב-24 שעות הראשונות ללא עלות."
    }
  }
}
```

### Collection: `bookings` (חדש בכל הזמנת הדברה)

```javascript
{
  // ...שדות הזמנה קיימים...

  "pestControlPreferences": {
    "pestTypeIdentified": "cockroach_german", // אם זוהה ע"י AI
    "aiIdentificationData": {
      "confidence": 0.94,
      "alternatives": ["cockroach_american", "cockroach_oriental"],
      "imageUrl": "gs://anyskill/pest-photos/{userId}/{timestamp}.jpg"
    },
    "selectedPestType": "cockroaches",
    "urgency": "today",  // emergency, today, this_week, whenever
    "location": "apartment",  // apartment, private_house, yard, restaurant, office, kindergarten
    "size": "full_apartment",  // single_room, full_apartment, whole_house
    "treatmentMethod": "green",
    "specialHouseholdMembers": ["children", "pets"],
    "addOns": [
      { "id": "extended_warranty_6m", "price": 80 },
      { "id": "follow_up_check", "price": 50 }
    ],
    "additionalNotes": "ג׳וקים במטבח ליד הכיור...",
    "instructionsAcknowledged": true,  // 🆕 האם הלקוח אישר שקרא את ההוראות
    "instructionsAcknowledgedAt": "2026-04-17T14:30:00Z"
  },

  "priceBreakdown": {
    "basePrice": 290,
    "addOnsTotal": 80,
    "emergencyFee": 0,
    "travelFee": 0,
    "discount": 0,
    "total": 370
  }
}
```

---

## 🛠️ קבצים שצריך ליצור | Files to create

### Models
- `lib/models/pest_control_profile.dart` - המודל הראשי
- `lib/models/pest_control_booking_preferences.dart`
- `lib/models/pest_license.dart`
- `lib/models/maintenance_package.dart`
- `lib/models/treatment_instruction.dart` - 🆕 חדש!

### Constants
- `lib/constants/pest_types_catalog.dart` - 14 סוגי מזיקים עם אייקונים, צבעים
- `lib/constants/treatment_methods.dart` - 5 שיטות טיפול
- `lib/constants/customer_types.dart` - 6 סוגי לקוחות
- `lib/constants/special_household_members.dart` - 6 סוגים
- `lib/constants/structured_instructions_catalog.dart` - 🆕 7 הוראות מוכנות

### Provider Edit Screen
- `lib/screens/provider_edit/widgets/pest_control_settings_block.dart` - הבלוק הראשי
- `lib/screens/provider_edit/widgets/pest_licenses_section.dart`
- `lib/screens/provider_edit/widgets/pest_types_picker.dart`
- `lib/screens/provider_edit/widgets/treatment_methods_picker.dart`
- `lib/screens/provider_edit/widgets/customer_types_picker.dart`
- `lib/screens/provider_edit/widgets/availability_editor.dart`
- `lib/screens/provider_edit/widgets/service_area_editor.dart`
- `lib/screens/provider_edit/widgets/base_pricing_editor.dart`
- `lib/screens/provider_edit/widgets/warranty_editor.dart`
- `lib/screens/provider_edit/widgets/maintenance_packages_editor.dart`
- `lib/screens/provider_edit/widgets/treatment_instructions_editor.dart` - 🆕 חשוב!

### Client Profile Screen
- `lib/screens/provider_profile/widgets/pest_booking_block.dart` - הבלוק הראשי
- `lib/screens/provider_profile/widgets/ai_pest_identifier.dart` - 🤖 AI integration
- `lib/screens/provider_profile/widgets/ai_result_card.dart`
- `lib/screens/provider_profile/widgets/pest_type_selector.dart`
- `lib/screens/provider_profile/widgets/urgency_selector.dart`
- `lib/screens/provider_profile/widgets/location_size_selector.dart`
- `lib/screens/provider_profile/widgets/treatment_method_selector.dart`
- `lib/screens/provider_profile/widgets/special_members_selector.dart`
- `lib/screens/provider_profile/widgets/addons_selector.dart`
- `lib/screens/provider_profile/widgets/maintenance_packages_display.dart`
- `lib/screens/provider_profile/widgets/treatment_instructions_display.dart` - 🆕 חשוב!
- `lib/screens/provider_profile/widgets/booking_summary_bar.dart`

### Services
- `lib/services/pest_control_booking_service.dart` - חישוב מחירים, שמירה
- `lib/services/gemini_pest_identification_service.dart` - 🤖 אינטגרציה עם Gemini Vision API
- `lib/services/license_verification_service.dart`

### Cloud Functions (functions/index.js)
- `syncPestControlProfileToProviderListings` - מסנכרן את ההגדרות
- `verifyPestControlLicense` - אימות רישיון אוטומטי (יכול להיות ידני בהתחלה)
- `identifyPestFromImage` - 🤖 קורא ל-Gemini Vision API
- `calculateEmergencySurcharge` - חישוב תוספת חירום

---

## 🤖 Gemini Vision API Integration

**חובה: השתמש ב-Gemini, לא ב-Claude API!**

### Cloud Function לזיהוי מזיק:
```javascript
// functions/identifyPestFromImage.js
const { GoogleGenerativeAI } = require('@google/generative-ai');

exports.identifyPestFromImage = functions.https.onCall(async (data, context) => {
  const { imageBase64 } = data;

  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash-lite" });

  const prompt = `אתה מומחה זיהוי מזיקים. נתח את התמונה ותן תשובה בפורמט JSON:
  {
    "pestType": "cockroach_german|ant|bedbug|mouse|rat|mosquito|fly|spider|termite|flea|snake|pigeon|bat|other",
    "pestTypeHe": "השם בעברית",
    "confidence": 0.0-1.0,
    "alternativeMatches": ["array of other possible matches"],
    "urgencyLevel": "low|medium|high|emergency",
    "isHebrewName": "השם המדויק של המזיק בעברית",
    "description": "תיאור קצר ב-1-2 משפטים",
    "treatmentRecommendation": "ירוק|רגיל|חום"
  }

  התמקד במזיקים שמצויים בישראל.`;

  const result = await model.generateContent([
    prompt,
    { inlineData: { mimeType: "image/jpeg", data: imageBase64 } }
  ]);

  const response = JSON.parse(result.response.text());
  return response;
});
```

---

## ✅ Acceptance Criteria | קריטריונים לקבלה

### חובה לעבוד | Must work
- [ ] בעריכת פרופיל - בחירת תת-קטגוריה "הדברה" פותחת **אוטומטית** את בלוק "הגדרות הדברה" מתחת
- [ ] ביטול בחירת "הדברה" - מסתיר את הבלוק (אבל שומר את ההגדרות)
- [ ] **רישיונות חובה**: לא ניתן לאשר פרופיל ללא רישיון משרד הגנ"ס
- [ ] **לכידת נחשים**: מופעלת רק אם יש רישיון לוכד נחשים
- [ ] בלוק AI לזיהוי מזיק עובד עם Gemini Vision API
- [ ] בדף הפרופיל - בלוק "בנה את הטיפול שלך" מופיע **בין** "אודות" ל"השירות"
- [ ] **🆕 בלוק "מה צריך לדעת לפני"** מופיע בולט ללקוח עם ההוראות שהמדביר כתב
- [ ] **Checkbox אישור** "קראתי והבנתי" נשמר ב-bookings
- [ ] רק סוגי מזיקים שהמדביר סימן - מוצגים ללקוח
- [ ] רק שיטות טיפול שהמדביר סימן - מוצגות ללקוח
- [ ] חבילות תחזוקה מוצגות אם המדביר הגדיר
- [ ] חירום מציג +₪150 (או הסכום שהמדביר קבע)
- [ ] לחיצה על "בחר תאריך ושעה" - פותחת את **היומן הקיים** (לא חדש!)
- [ ] תמיכה מלאה ב-RTL (עברית)
- [ ] flutter analyze: 0 issues

### אסור | Must NOT happen
- [ ] **לא לגעת** בחלקים הקיימים של דף הפרופיל
- [ ] **לא לגעת** ביומן הקיים
- [ ] **לא לשנות** routing של קטגוריות אחרות
- [ ] **לא להוסיף** monthly subscriptions בשום מקום
- [ ] **לא להשתמש** ב-Claude API (Gemini בלבד)
- [ ] **לא להציג** הגדרות הדברה אם לא נבחר "הדברה" כתת-קטגוריה

---

## 🎨 Design System

### Colors (חדש לקטגוריית הדברה)
```dart
// Primary brand colors
const primaryDark = Color(0xFF1A1A1A);
const primaryDarkSecondary = Color(0xFF2D3142);

// 🌿 Pest Control specific - Green theme
const pestGreenDark = Color(0xFF14532D);
const pestGreenMedium = Color(0xFF166534);
const pestGreenLight = Color(0xFF15803D);
const pestGreenBg = Color(0xFFDCFCE7);
const pestGreenBgLight = Color(0xFFF0FDF4);

// 🤖 AI features - Blue
const aiBlueDark = Color(0xFF1E3A8A);
const aiBlueMedium = Color(0xFF1E40AF);
const aiBlueLight = Color(0xFF3B82F6);
const aiBlueBg = Color(0xFFEFF6FF);

// 🚨 Emergency - Red
const emergencyRed = Color(0xFFDC2626);
const emergencyRedDark = Color(0xFFB91C1C);
const emergencyRedBg = Color(0xFFFEE2E2);

// 🎁 Maintenance packages - Amber
const amberDark = Color(0xFFD97706);
const amberMedium = Color(0xFFF59E0B);
const amberLight = Color(0xFFFBBF24);
const amberBg = Color(0xFFFEF3C7);

// 📋 Instructions block - Purple/Indigo (חדש!)
const indigoMedium = Color(0xFF6366F1);
const indigoDark = Color(0xFF4F46E5);
const indigoBg = Color(0xFFEEF2FF);

// Backgrounds
const cream = Color(0xFFFBFAF6);
const creamSecondary = Color(0xFFF5F2EC);
const creamBorder = Color(0xFFEAE7DF);
```

### Component Patterns

**רישיון מאושר:**
```dart
decoration: BoxDecoration(
  gradient: LinearGradient(colors: [pestGreenBg, Color(0xFFBBF7D0)]),
  border: Border.all(color: pestGreenLight, width: 1),
  borderRadius: BorderRadius.circular(11),
)
```

**מזיק שנבחר:**
```dart
decoration: BoxDecoration(
  gradient: LinearGradient(colors: [pestGreenDark, pestGreenMedium]),
  borderRadius: BorderRadius.circular(11),
)
```

**לכידת חיות (גוון כחול שונה):**
```dart
decoration: BoxDecoration(
  gradient: LinearGradient(colors: [aiBlueMedium, aiBlueDark]),
  borderRadius: BorderRadius.circular(11),
)
```

**בלוק הוראות (סגול בולט):**
```dart
decoration: BoxDecoration(
  color: Colors.white,
  border: Border.all(color: indigoMedium, width: 1.5),
  borderRadius: BorderRadius.circular(20),
  boxShadow: [BoxShadow(
    color: indigoMedium.withOpacity(0.12),
    blurRadius: 16,
    offset: Offset(0, 4),
  )],
)
```

---

## 🚀 סדר ביצוע מומלץ | Recommended Order

### Phase 1: Foundation (יום 1-2)
1. Models + constants (כולל catalog של 7 הוראות)
2. Firestore schema
3. Localization files (HE/EN/ES/AR)
4. Gemini Vision API integration setup

### Phase 2: Provider Edit Screen (יום 3-5)
1. בלוק `PestControlSettingsBlock` עם conditional rendering
2. כל ה-pickers (licenses, pest types, methods, customer types, etc.)
3. **🆕 Treatment Instructions Editor** (סקציה הכי חשובה החדשה!)
4. שמירה ל-Firestore

### Phase 3: Client Profile Screen (יום 6-8)
1. בלוק `PestBookingBlock` בין "אודות" ל"השירות"
2. **🤖 AI Pest Identifier** עם Gemini integration
3. **🆕 Treatment Instructions Display** (חובה - בולט!)
4. כל הסלקטורים והסיכום הדינמי
5. סנכרון real-time עם הגדרות המדביר

### Phase 4: Smart Features (יום 9)
1. AI suggestions לפי סוג המזיק שזוהה
2. Smart insights ("8 הזמנות בשעה האחרונה")
3. Live activity feed ("אורן טיפל ב-3 דירות בשכונה")
4. Animations & haptic feedback

### Phase 5: Testing (יום 10)
1. Test flow מלא: יצירת מדביר → הגדרות → לקוח → הזמנה
2. AI identification עם 5+ סוגי מזיקים שונים
3. בדיקת סנכרון בין מסכים
4. RTL & dark mode
5. flutter analyze - 0 issues

---

## 🌐 Localization Keys (מרכזיים)

הוסף ל-`l10n/app_he.arb`, `app_en.arb`, `app_es.arb`, `app_ar.arb`:

```json
{
  "pest_settings_banner_title": "הגדרות ייעודיות להדברה",
  "pest_settings_banner_desc": "הלקוחות יראו רק את מה שתסמן כאן · רישיון משרד הגנ\"ס נדרש",

  "pest_licenses_title": "רישיונות חובה",
  "pest_licenses_required_warning": "חובה לפי חוק - אימות נדרש לפני אישור הפרופיל",

  "pest_types_title": "סוגי מזיקים שאני מטפל",
  "pest_types_helper": "הלקוחות יראו את הסל שלך",

  "pest_treatment_methods_title": "שיטות הטיפול שלי",
  "pest_customer_types_title": "סוגי לקוחות",
  "pest_availability_title": "זמינות ותגובה",
  "pest_emergency_label": "🚨 שירות חירום",
  "pest_emergency_desc": "תוך שעה - תוספת מחיר",
  "pest_247_label": "🌙 זמין 24/7",

  "pest_service_area_title": "אזורי שירות",
  "pest_pricing_title": "מחירון שקוף",
  "pest_pricing_subtitle": "לקוחות סומכים על מחיר ברור",

  "pest_warranty_title": "אחריות ושירות",
  "pest_warranty_basic": "אחריות בסיסית",
  "pest_digital_report": "דוח דיגיטלי אוטומטי",
  "pest_before_after_photos": "תמונות לפני/אחרי",

  "pest_packages_title": "חבילות תחזוקה",
  "pest_packages_revenue_hint": "הכנסה קבועה · לקוחות חוזרים",

  "pest_instructions_title": "הוראות והתנהלות לאחר טיפול",
  "pest_instructions_subtitle": "מתורגם אוטומטית ללקוחות",
  "pest_instructions_quick": "הוראות מהירות (סמן את הרלוונטיות)",
  "pest_instructions_custom": "הוראות אישיות נוספות",
  "pest_instructions_preview": "איך הלקוחות יראו את זה",

  "client_block_title": "בנה את הטיפול שלך",
  "client_block_subtitle": "{providerName} יקבל הכל מוכן",
  "client_ai_identify_title": "לא יודע מה זה?",
  "client_ai_identify_subtitle": "צלם והAI יזהה תוך 2 שניות",
  "client_ai_identify_btn_capture": "צלם עכשיו",
  "client_ai_identify_btn_upload": "העלה תמונה",
  "client_ai_result_confidence": "{percent}% ביטחון",
  "client_ai_result_match": "{percent}% התאמה ל{providerName}",

  "client_instructions_title": "מה צריך לדעת לפני",
  "client_instructions_subtitle": "הוראות מ{providerName} · קרא לפני ההזמנה",
  "client_instructions_important_badge": "חשוב!",
  "client_instructions_personal_note": "הערה אישית מ{providerName}",
  "client_instructions_acknowledge": "קראתי והבנתי - אני מאשר את ההוראות",

  "client_btn_book_now": "הזמן עכשיו · ₪{price}",
  "client_trust_payment_after": "תשלום אחרי",
  "client_trust_digital_report": "דוח דיגיטלי",
  "client_trust_free_cancel": "ביטול חינם"
}
```

---

## 📊 KPIs להצלחה

לאחר ההשקה - מדידה דרך AI CEO Agent:
- **Conversion rate** מקטגוריית הדברה להזמנה (יעד: +50%)
- **AI Identification usage** - אחוז לקוחות שמשתמשים ב-AI (יעד: >40%)
- **Time to booking** - מכניסה לפרופיל ועד הזמנה (יעד: <90 שניות)
- **Cancellation rate** - אחוז ביטולים אחרי הזמנה (יעד: <5% - בזכות ההוראות!)
- **Emergency bookings** - אחוז הזמנות חירום (יעד: 15-20%)
- **Maintenance packages** - אחוז לקוחות שקונים חבילה (יעד: 25%)

---

## 💾 בסיום העבודה - חובה לשמור!

### בסוף הפיתוח:
1. **שמור את כל הקבצי MD מהתיקייה הזו** ב-`/docs/pest_control_upgrade/`
2. **עדכן CLAUDE.md** עם section חדש על Pest Control CSM
3. **תעדכן userMemories** שעבר Pest Control CSM הוטמע
4. **רץ flutter analyze** ווודא 0 issues
5. **תכין סיכום מלא** של מה נעשה (כמו שעשית עם עיסוי)

---

## 🤖 Built for AnySkill - Claude Code Implementation

המסמך הזה הוא הבסיס. עבור פרטים מלאים על כל מסך - ראה את שני הקבצים הנוספים. בהצלחה! 🚀

**זכור: לא למחוק כלום! רק להוסיף 2 בלוקים חדשים במיקומים המדויקים שצוינו למעלה.**
