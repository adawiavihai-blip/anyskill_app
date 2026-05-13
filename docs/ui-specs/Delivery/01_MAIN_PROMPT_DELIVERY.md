# 🛵 AnySkill - Delivery Category (Couriers) | שליחויות

> **קובץ ראשי - קרא אותו קודם!** | **Main file - Read this first**
>
> פרויקט: הוספת קטגוריית שליחויות ב-AnySkill ברמה עולמית (Uber/Lalamove-level).
> Project: World-class Delivery category addition to AnySkill.
>
> **ארכיטקטורה:** Category-Specific Modules (CSM) - אותו עיקרון כמו שעשינו בעיסוי ובהדברה.

---

## ⛔⛔⛔ עקרונות חובה - קריטי! אל תפר! ⛔⛔⛔

### 🚫 אסור לך למחוק שום דבר!

זה הכלל הכי חשוב בכל הפרויקט:
- **אסור** למחוק חלקים קיימים מדף פרופיל הלקוח (תמונה, אודות, השירות, יומן, ביקורות, כפתור תחתון)
- **אסור** למחוק חלקים קיימים מדף עריכת השליח (פרטים אישיים, אודות, גלריה, יומן וכו׳)
- **אסור** לגעת במבנה הקיים של הפרופיל
- **אסור** לשנות את routing של קטגוריות אחרות
- **אסור** לבנות יומן חדש - להשתמש ביומן הקיים!
- **אסור** להשתמש ב-Claude API - השתמש ב-Gemini בלבד עבור AI

### ✅ אתה רק מוסיף 2 בלוקים חדשים:

#### בלוק 1: בדף הלקוח (פרופיל השליח)
מתווסף **בדיוק** במיקום הזה:
```
1. Header (קיים - לא נוגעים)
2. Profile card עם תמונה, ✓ כחול, סטטיסטיקות (קיים - לא נוגעים)
3. גלריה + וידאו (קיים - לא נוגעים)
4. אודות (קיים - לא נוגעים)
↓ ↓ ↓
5. ✨ הבלוק החדש - "שלח עם דני" ← כאן!
↑ ↑ ↑
6. השירות (קיים, לא נוגעים)
7. זמינות / יומן (קיים - לא נוגעים)
8. ביקורות (קיים - לא נוגעים)
9. כפתור תחתון "בחר תאריך ושעה" (קיים - לא נוגעים)
```

#### בלוק 2: בדף עריכת השליח
מתווסף **בדיוק** במיקום הזה:
```
1. פרטים אישיים (קיים - לא נוגעים)
2. תמונת פרופיל (קיים - לא נוגעים)
3. אודות (קיים - לא נוגעים)
4. תת-קטגוריה: "משלוחים" (כבר קיים)
↓ ↓ ↓
5. ✨ הבלוק החדש - "הקריירה שלך" ← כאן!
   (מופיע **רק** אם נבחר "משלוחים" כתת-קטגוריה)
↑ ↑ ↑
6. גלריית עבודות (קיים - לא נוגעים)
7. יומן זמינות (קיים - לא נוגעים)
8. כפתורי שמירה (קיים - לא נוגעים)
```

### 🔄 הסנכרון הוא הכי חשוב!
- כל מה שהשליח מסמן/כותב בעריכה → מופיע ללקוח **בזמן אמת**
- אם השליח מבטל סוג משלוח - הלקוח כבר לא יראה אותו
- אם השליח משנה מחיר - מתעדכן מיידית
- אם השליח כותב כללים - הלקוח רואה אותם לפני ההזמנה

---

## 🎯 Goal | מטרה

לבנות את קטגוריית השליחויות הכי טובה בעולם ב-AnySkill - רמה של **Uber + Lalamove + DoorDash משולבים** עם פיצ'רים שאף אחד לא עושה יחד.

### היתרונות התחרותיים שלנו:
1. **🤝 הלקוח בוחר שליח** - לא dispatch אוטומטי (הסיפור הגדול!)
2. **🗓️ הזמנה מראש** - "מחר ב-7:00" - ייחודי בישראל!
3. **📍 Live location** - רואים את השליח זז במפה בזמן אמת
4. **🤖 AI vehicle recommendation** - חוסך כסף ללקוח
5. **🔁 Express reorder** - משלוח חוזר בקליק אחד
6. **🎤 Voice input** - לא צריך להקליד
7. **🔒 Phone number masking** - privacy מלא
8. **📋 Rules system** - כללים מותאמים של השליח

---

## 📦 קבצים נוספים בפרויקט הזה | Additional files

- **`02_PROVIDER_EDIT_DELIVERY.md`** - מפרט מלא של דף עריכת השליח
- **`03_CLIENT_BOOKING_DELIVERY.md`** - מפרט מלא של דף הלקוח

**קרא את שני הקבצים הנוספים לפני שמתחיל לקודד!**

---

## 🗄️ Firestore Schema - שדות חדשים

### Collection: `users` (היכן ששמורים נותני שירות)

הוסף את השדה `deliveryProfile` **רק אם** המסמך מכיל `category == 'delivery'` או שתת-הקטגוריה היא 'delivery':

```javascript
{
  // ...כל השדות הקיימים נשארים בדיוק כמו שהם...

  // === שדה חדש - מופיע רק לשליחים ===
  "deliveryProfile": {
    // מסמכים ורישיונות (חובה!)
    "documents": [
      {
        "id": "id_card",
        "type": "id_card",
        "nameHe": "תעודת זהות",
        "verifiedAt": "2026-03-15T10:00:00Z",
        "verified": true,
        "verificationMethod": "OCR"
      },
      {
        "id": "driver_license",
        "type": "driver_license",
        "nameHe": "רישיון נהיגה",
        "classes": ["B", "A2"],
        "validUntil": "2028-03-15",
        "verified": true
      },
      {
        "id": "insurance",
        "type": "vehicle_insurance",
        "nameHe": "ביטוח רכב + צד ג'",
        "validUntil": "2027-01-01",
        "verified": true
      }
    ],

    // הצי - רכבים של השליח
    "vehicles": [
      {
        "id": "scooter_2022",
        "type": "scooter",
        "nameHe": "קטנוע 125cc",
        "manufacturer": "SYM Cruisym",
        "year": 2022,
        "maxWeightKg": 30,
        "photos": ["url1.jpg", "url2.jpg", "url3.jpg"],
        "insuranceVerified": true,
        "enabled": true
      },
      {
        "id": "car_2020",
        "type": "car",
        "nameHe": "רכב פרטי",
        "manufacturer": "Hyundai i20",
        "year": 2020,
        "maxWeightKg": 60,
        "photos": [],
        "insuranceVerified": true,
        "enabled": true
      }
    ],

    // סוגי משלוחים שמבצע (מתוך 6)
    "deliveryTypes": [
      "documents",        // מסמכים עד 1 ק"ג
      "small_package",    // עד 5 ק"ג
      "medium_package",   // 5-15 ק"ג
      "large_package"     // 15-30 ק"ג
      // אופציות נוספות: "flowers", "cakes"
    ],

    // סוגי לקוחות (מתוך 4)
    "customerTypes": [
      "private",      // פרטיים
      "business"      // עסקים
      // אופציות נוספות: "stores", "restaurants"
    ],

    // זמינות - 3 סוגי הזמנות
    "availability": {
      "immediate": {
        "enabled": true,
        "surcharge": 25,  // ₪ תוספת לעכשיו (תוך 30 דק')
      },
      "regular": {
        "enabled": true,
        // תוך שעה - סטנדרטי, ללא תוספת
      },
      "scheduled": {
        "enabled": true,
        // 🌟 ייחודי! הזמנות מראש - מחר, השבוע
      }
    },

    // אזור שירות
    "serviceArea": {
      "baseLocation": "תל אביב מרכז",
      "baseLocationGeo": {
        "lat": 32.0853,
        "lng": 34.7818
      },
      "coverageCities": [
        "תל אביב",
        "רמת גן",
        "גבעתיים",
        "הרצליה"
      ]
    },

    // מחירון לפי משקל (עד 5 ק"מ)
    "pricing": {
      "documents": 35,        // מסמכים עד 1ק"ג
      "small_package": 45,    // חבילה קטנה עד 5ק"ג
      "medium_package": 65,   // בינונית 5-15ק"ג
      "large_package": 90,    // גדולה 15-30ק"ג
      "perKmAfter5": 3.5      // תוספת לכל ק"מ אחרי 5
    },

    // 🆕 כללים של השליח - הלקוחות יראו לפני ההזמנה!
    "rules": {
      // כללים מובנים (5 אופציות)
      "structuredRules": [
        {
          "id": "no_dangerous",
          "type": "no_dangerous",
          "icon": "🚫",
          "titleHe": "לא אקח חבילות מסוכנות",
          "descHe": "חומרים דליקים או מסוכנים",
          "enabled": true,
          "color": "red"
        },
        {
          "id": "photo_documentation",
          "type": "photo_documentation",
          "icon": "📷",
          "titleHe": "תיעוד תמונה בכל משלוח",
          "descHe": "תמונה באיסוף + מסירה (אוטומטי)",
          "enabled": true,
          "color": "amber"
        },
        {
          "id": "call_before_arrival",
          "type": "call_before_arrival",
          "icon": "📱",
          "titleHe": "התקשרות לפני הגעה",
          "descHe": "תמיד אצלצל 5 דק' לפני",
          "enabled": true,
          "color": "blue"
        },
        {
          "id": "weight_verification",
          "type": "weight_verification",
          "icon": "⚖️",
          "titleHe": "שקילה לאישור משקל",
          "descHe": "אם משקל לא תואם הצהרה",
          "enabled": false
        },
        {
          "id": "rain_delivery",
          "type": "rain_delivery",
          "icon": "🌧️",
          "titleHe": "משלוח גם בגשם",
          "descHe": "בעטיפת ניילון בלבד",
          "enabled": false
        }
      ],
      // הוראות אישיות חופשיות (עד 500 תווים)
      "customRules": "חבילות שביר - חובה לסמן! אגיע עם בועות וניילון מגן. לעסקים: ניתן לפתוח חשבון חודשי."
    },

    // 🆕 חבילות לעסקים (B2B subscriptions)
    "businessPackages": [
      {
        "id": "basic",
        "nameHe": "📦 בייסיק",
        "deliveriesPerMonth": 5,
        "monthlyPrice": 249,
        "enabled": true,
        "activeCustomers": 3  // לתצוגה לשליח בלבד
      },
      {
        "id": "pro",
        "nameHe": "🚀 פרו",
        "deliveriesPerMonth": 15,
        "monthlyPrice": 599,
        "enabled": true,
        "activeCustomers": 1
      }
      // אפשרי: חבילת ∞ ב-₪999
    ]
  }
}
```

### Collection: `bookings` (חדש בכל הזמנת שליחות)

```javascript
{
  // ...שדות הזמנה קיימים...

  "deliveryPreferences": {
    // סוג החבילה
    "packageType": "documents",  // documents, small_package, medium_package, large_package
    "packageDescription": "חוזה חתום לסקירה דחופה",
    "packageTags": ["sensitive", "photo_documentation"],  // ⚠️ שביר, 🤐 רגיש, 📸 לתעד, 🆔 חתימה

    // רכב שנבחר
    "selectedVehicle": "scooter",  // scooter, car
    "aiRecommendedVehicle": "scooter",
    "aiRecommendationSavings": {
      "amount": 15,
      "timeMinutes": 7
    },

    // כתובות
    "pickupAddress": {
      "address": "דיזנגוף 50, תל אביב",
      "details": "דירה 4, קומה 2",
      "accessCode": "1234",
      "geo": { "lat": 32.0853, "lng": 34.7818 }
    },
    "deliveryAddress": {
      "address": "הרצל 88, רמת גן",
      "details": "משרד 12, קומה 5",
      "geo": { "lat": 32.0823, "lng": 34.8144 }
    },
    "distanceKm": 8.4,
    "estimatedTravelMinutes": 22,

    // תזמון
    "timing": "regular",  // immediate (+₪25), regular, today, scheduled
    "scheduledFor": null,  // אם scheduled - התאריך המבוקש
    "pickupTime": "14:00",
    "estimatedDeliveryTime": "14:30",

    // סוג מסירה
    "deliveryMethod": "hand_to_recipient",  // hand_to_recipient, leave_at_door
    "specialInstructions": "קומה 5, משרד 12 - לחדר הקבלה",

    // תוספות
    "addOns": [
      { "id": "photo_gps", "nameHe": "תיעוד + GPS", "price": 5 }
      // אפשרי: { "id": "sms_tracking", "nameHe": "SMS למקבל", "price": 0 }
    ],

    // איש קשר במסירה
    "recipient": {
      "name": "מיכל כהן",
      "phone": "054-1234567",
      "phoneVerified": true
    },

    // מחיר
    "priceBreakdown": {
      "base": 45,
      "addOnsTotal": 5,
      "emergencySurcharge": 0,
      "kmAfter5": 0,
      "total": 50
    }
  }
}
```

---

## 🛠️ קבצים שצריך ליצור | Files to create

### Models
- `lib/models/delivery_profile.dart` - המודל הראשי
- `lib/models/delivery_preferences.dart` - העדפות בהזמנה
- `lib/models/delivery_vehicle.dart`
- `lib/models/delivery_document.dart`
- `lib/models/courier_rule.dart` - 🆕 חשוב!
- `lib/models/business_package.dart`

### Constants
- `lib/constants/delivery_types_catalog.dart` - 6 סוגי משלוחים
- `lib/constants/vehicle_types_catalog.dart` - רכבים: קטנוע, רכב
- `lib/constants/courier_customer_types.dart` - 4 סוגי לקוחות
- `lib/constants/courier_rules_catalog.dart` - 5 כללים מוכנים
- `lib/constants/package_tags.dart` - תגיות: שביר, רגיש, תיעוד, חתימה

### Provider Edit Screen
- `lib/screens/provider_edit/widgets/delivery_settings_block.dart` - הבלוק הראשי
- `lib/screens/provider_edit/widgets/delivery_hero_stats.dart`
- `lib/screens/provider_edit/widgets/delivery_documents_section.dart`
- `lib/screens/provider_edit/widgets/delivery_fleet_editor.dart`
- `lib/screens/provider_edit/widgets/delivery_types_picker.dart`
- `lib/screens/provider_edit/widgets/delivery_customers_picker.dart`
- `lib/screens/provider_edit/widgets/delivery_availability_editor.dart`
- `lib/screens/provider_edit/widgets/delivery_service_area_editor.dart`
- `lib/screens/provider_edit/widgets/delivery_pricing_editor.dart`
- `lib/screens/provider_edit/widgets/courier_rules_editor.dart` - 🆕 חשוב!
- `lib/screens/provider_edit/widgets/business_packages_editor.dart`

### Client Profile Screen
- `lib/screens/provider_profile/widgets/delivery_block.dart` - הבלוק הראשי
- `lib/screens/provider_profile/widgets/delivery_hero_story.dart`
- `lib/screens/provider_profile/widgets/delivery_express_reorder.dart` - 🆕
- `lib/screens/provider_profile/widgets/delivery_route_map.dart` - 🆕 Live map!
- `lib/screens/provider_profile/widgets/delivery_package_selector.dart`
- `lib/screens/provider_profile/widgets/ai_vehicle_recommendation.dart`
- `lib/screens/provider_profile/widgets/delivery_timing_selector.dart`
- `lib/screens/provider_profile/widgets/delivery_method_selector.dart`
- `lib/screens/provider_profile/widgets/delivery_addons_selector.dart`
- `lib/screens/provider_profile/widgets/recipient_contact_form.dart`
- `lib/screens/provider_profile/widgets/courier_rules_display.dart`
- `lib/screens/provider_profile/widgets/courier_live_activity.dart`
- `lib/screens/provider_profile/widgets/business_packages_display.dart`
- `lib/screens/provider_profile/widgets/delivery_booking_summary.dart`

### Services
- `lib/services/delivery_booking_service.dart` - חישוב מחירים, שמירה
- `lib/services/ai_vehicle_recommendation_service.dart` - אינטגרציה עם Gemini
- `lib/services/delivery_route_service.dart` - חישוב מרחק, ETA
- `lib/services/recipient_sms_service.dart` - שליחת SMS עם tracking link

### Cloud Functions (functions/index.js)
- `syncDeliveryProfileToListings` - מסנכרן את ההגדרות
- `recommendVehicleForDelivery` - Gemini AI עבור המלצת רכב
- `calculateDeliveryRoute` - Google Maps API
- `sendRecipientTrackingSms` - SMS עם לינק מעקב
- `generateMaskedPhoneNumber` - מספר מוסתר לפרטיות

---

## 🤖 Gemini AI Integration

**חובה: השתמש ב-Gemini, לא ב-Claude API!**

### Cloud Function לממליץ רכב:
```javascript
// functions/recommendVehicleForDelivery.js
const { GoogleGenerativeAI } = require('@google/generative-ai');

exports.recommendVehicleForDelivery = functions.https.onCall(async (data, context) => {
  const { packageType, distanceKm, urgency, weatherConditions } = data;

  const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY);
  const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash-lite" });

  const prompt = `אתה מומחה לוגיסטיקה. המלץ על רכב אופטימלי לשליחות:
  - סוג חבילה: ${packageType}
  - מרחק: ${distanceKm} ק"מ
  - דחיפות: ${urgency}
  - מזג אויר: ${weatherConditions}

  השב בפורמט JSON:
  {
    "recommendedVehicle": "scooter|car",
    "savingsAmount": number (₪),
    "savingsMinutes": number,
    "reason": "string בעברית",
    "confidence": 0.0-1.0
  }`;

  const result = await model.generateContent(prompt);
  return JSON.parse(result.response.text());
});
```

---

## ✅ Acceptance Criteria | קריטריונים לקבלה

### חובה לעבוד | Must work
- [ ] בעריכת פרופיל - בחירת תת-קטגוריה "משלוחים" פותחת **אוטומטית** את בלוק "הקריירה שלך" מתחת
- [ ] ביטול בחירת "משלוחים" - מסתיר את הבלוק (אבל שומר את ההגדרות)
- [ ] **מסמכים חובה**: לא ניתן לאשר פרופיל ללא ת"ז + רישיון נהיגה + ביטוח
- [ ] בלוק AI המלצת רכב עובד עם Gemini API
- [ ] בדף הפרופיל - בלוק "שלח עם דני" מופיע **בין** "אודות" ל"השירות"
- [ ] **🆕 Express Reorder** מופיע אם ללקוח יש משלוח קודם עם אותו שליח
- [ ] **🆕 Live Location** - סמן השליח זז במפה בזמן אמת (או סטטי אם לא בנסיעה)
- [ ] **🆕 Rules Display** - הכללים שהשליח כתב מופיעים ללקוח
- [ ] רק סוגי משלוחים שהשליח סימן - מוצגים ללקוח
- [ ] חבילות עסקיות מוצגות אם השליח הגדיר
- [ ] חירום מציג +₪25 (או הסכום שהשליח קבע)
- [ ] **🆕 Scheduled delivery** - הלקוח יכול לבחור תאריך עתידי
- [ ] **🆕 Phone masking** - מספר הלקוח מוסתר מהשליח
- [ ] **🆕 SMS למקבל** - לינק tracking נשלח ב-SMS
- [ ] לחיצה על "שלח עכשיו" - פותחת את **היומן הקיים**
- [ ] תמיכה מלאה ב-RTL (עברית)
- [ ] flutter analyze: 0 issues

### אסור | Must NOT happen
- [ ] **לא לגעת** בחלקים הקיימים של דף הפרופיל
- [ ] **לא לגעת** ביומן הקיים
- [ ] **לא לשנות** routing של קטגוריות אחרות
- [ ] **לא להוסיף** monthly subscriptions ללקוחות פרטיים (רק לעסקים!)
- [ ] **לא להשתמש** ב-Claude API (Gemini בלבד)
- [ ] **לא להציג** הגדרות משלוחים אם לא נבחר "משלוחים" כתת-קטגוריה
- [ ] **לא להציג** משאיות / מקררים - רק קטנוע + רכב
- [ ] **לא להציג** ביטוח חבילה - לא בגרסה הזו

---

## 🎨 Design System - Dark Premium

### Base Colors
```dart
// Dark base gradient (חדש לקטגוריית משלוחים)
const darkBase = Color(0xFF0A0E1A);
const darkBaseMid = Color(0xFF151B2E);
const darkBaseSecondary = Color(0xFF1A1F2E);
const darkBaseDeep = Color(0xFF0F1420);

// Primary - Amber/Gold (לשליחויות)
const deliveryGoldDark = Color(0xFFD97706);
const deliveryGoldMid = Color(0xFFF59E0B);
const deliveryGoldLight = Color(0xFFFBBF24);
const deliveryGoldPale = Color(0xFFFCD34D);

// Status colors
const statusGreen = Color(0xFF16A34A);
const statusGreenLight = Color(0xFF4ADE80);
const statusGreenBg = Color(0xFF86EFAC);

const statusRed = Color(0xFFDC2626);
const statusRedLight = Color(0xFFFCA5A5);

const statusBlue = Color(0xFF3B82F6);
const statusBlueDeep = Color(0xFF1E40AF);

// Unique feature - Indigo (Scheduled delivery)
const indigoMedium = Color(0xFF6366F1);
const indigoDark = Color(0xFF4F46E5);
```

### Glassmorphism Pattern
```dart
// לכל הכרטיסים הראשיים
decoration: BoxDecoration(
  color: Colors.white.withOpacity(0.04),
  border: Border.all(
    color: Colors.white.withOpacity(0.1),
    width: 1,
  ),
  borderRadius: BorderRadius.circular(22),
  // backdrop filter נדרש ב-Flutter:
  // עטוף ב-BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20))
)
```

### Ambient Gradients (רקע)
כל המסך עם 3 orbs צבעוניים כ-background:
1. **Orb כתום** (top-right) - `radial-gradient(circle, rgba(245,158,11,0.2) 0%, transparent 70%)`
2. **Orb סגול** (middle-left) - `radial-gradient(circle, rgba(99,102,241,0.12) 0%, transparent 70%)`
3. **Orb ירוק** (bottom-right) - `radial-gradient(circle, rgba(34,197,94,0.1) 0%, transparent 70%)`

### Hero Story Mode
- תמונת פרופיל עם **conic-gradient glow** זהוב מסתובב
- **טבעת** חיצונית מסתובבת
- **Title gradient**: `linear-gradient(135deg, #FFFFFF 0%, #FCD34D 100%)` ב-text fill
- Subtitle בצבע `rgba(255,255,255,0.55)`
- 3 KPIs מתחת עם mini separators

### Critical Colors for Buttons
```dart
// Primary action button (Send now - green)
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
)
```

---

## 🌐 Localization Keys (מרכזיים)

הוסף ל-`l10n/app_he.arb`, `app_en.arb`, `app_es.arb`, `app_ar.arb`:

```json
{
  "delivery_settings_banner": "הגדרות ייעודיות לשליחויות",
  "delivery_hero_title": "הקריירה שלך",
  "delivery_hero_subtitle": "כל מה שצריך כדי להרוויח יותר",
  "delivery_top_badge": "Top 5 בעיר",

  "delivery_documents_title": "מסמכים ורישיונות",
  "delivery_documents_required": "חובה - אימות נדרש לאישור הפרופיל",
  "delivery_doc_id_card": "תעודת זהות",
  "delivery_doc_driver_license": "רישיון נהיגה",
  "delivery_doc_insurance": "ביטוח רכב + צד ג'",

  "delivery_fleet_title": "הצי שלי",
  "delivery_fleet_subtitle": "לקוחות יראו את האפשרויות",
  "delivery_add_vehicle": "הוסף רכב נוסף",

  "delivery_types_title": "סוגי משלוחים",
  "delivery_type_documents": "מסמכים",
  "delivery_type_small": "חבילה קטנה",
  "delivery_type_medium": "בינונית",
  "delivery_type_large": "גדולה",

  "delivery_customer_types_title": "סוגי לקוחות",
  "delivery_customer_private": "פרטיים",
  "delivery_customer_business": "עסקים",

  "delivery_availability_title": "זמינות",
  "delivery_immediate_title": "⚡ משלוח מיידי",
  "delivery_immediate_desc": "תוך 30 דקות · תוספת מחיר",
  "delivery_regular_title": "⏰ משלוח רגיל",
  "delivery_regular_desc": "תוך שעה · סטנדרטי",
  "delivery_scheduled_title": "🗓️ הזמנה מראש",
  "delivery_scheduled_badge": "ייחודי!",
  "delivery_scheduled_hint": "שליחים שמאפשרים = פי 2.4 הזמנות מעסקים",

  "delivery_area_title": "אזורי שירות",
  "delivery_base_location": "בסיס פעילות",
  "delivery_coverage_cities": "אזורי כיסוי",

  "delivery_pricing_title": "מחירון לפי משקל",
  "delivery_pricing_transparency": "שקיפות",
  "delivery_pricing_base": "מחיר בסיס (עד 5 ק\"מ)",
  "delivery_pricing_per_km": "תוספת לכל ק\"מ נוסף",

  "delivery_rules_title": "הכללים שלך",
  "delivery_rules_subtitle": "הלקוחות יראו לפני ההזמנה",
  "delivery_rules_why": "פחות אי הבנות = יותר ★★★★★",
  "delivery_rules_quick": "כללים מהירים",
  "delivery_rule_no_dangerous": "לא אקח חבילות מסוכנות",
  "delivery_rule_photo": "תיעוד תמונה בכל משלוח",
  "delivery_rule_call": "התקשרות לפני הגעה",
  "delivery_rule_weight": "שקילה לאישור משקל",
  "delivery_rule_rain": "משלוח גם בגשם",
  "delivery_rules_custom": "הוראות אישיות נוספות",

  "delivery_business_packages_title": "חבילות לעסקים",
  "delivery_business_revenue_hint": "שליחים עם חבילות = פי 2.5 הכנסה",

  "client_send_with_title": "שלח עם {courierName}",
  "client_send_subtitle": "הדרך החכמה לשלוח משהו חשוב",
  "client_express_reorder": "אקספרס - משלוח כמו אתמול",
  "client_step_route": "המסלול שלך",
  "client_step_package": "מה שולחים?",
  "client_step_timing": "מתי?",
  "client_step_method": "איך למסור?",
  "client_step_addons": "שדרוגים חכמים",
  "client_step_recipient": "איש קשר במסירה",

  "client_ai_recommend_vehicle": "AI ממליץ",
  "client_ai_savings": "חוסך ₪{amount} + {minutes} דק'",

  "client_method_hand": "מסירה ליד",
  "client_method_hand_desc": "השליח ימתין 5 דק'",
  "client_method_door": "השאר בדלת",
  "client_method_door_desc": "+תמונה אוטומטית",
  "client_special_instructions": "הוראות מיוחדות לשליח",

  "client_addon_photo": "תיעוד + GPS",
  "client_addon_photo_desc": "תמונה אוטומטית במסירה",
  "client_addon_sms": "SMS למקבל עם tracking",
  "client_addon_sms_desc": "לינק לא דורש אפליקציה",

  "client_recipient_phone_masked": "המספר שלך מוסתר מהשליח אוטומטית",
  "client_phone_verified": "אומת",

  "client_live_activity": "הפעילות של {courierName}",
  "client_courier_approx_distance": "{courierName} · {distance} ממך",

  "client_price_breakdown_title": "סך לתשלום",
  "client_price_final": "סופי",
  "client_eta": "ETA",
  "client_send_now_btn": "שלח עכשיו · ₪{price}",
  "client_trust_secure_payment": "תשלום מאובטח",
  "client_trust_live_tracking": "מעקב חי",
  "client_trust_free_cancel": "ביטול חינם"
}
```

---

## 📊 KPIs להצלחה

לאחר ההשקה - מדידה דרך AI CEO Agent:
- **Conversion rate** מקטגוריה להזמנה (יעד: +50%)
- **Express reorder usage** - אחוז משתמשים חוזרים (יעד: >40%)
- **Scheduled delivery usage** - אחוז הזמנות מראש (יעד: >25% של B2B)
- **Time to booking** - מכניסה לפרופיל ועד הזמנה (יעד: <60 שניות)
- **Cancellation rate** - אחוז ביטולים אחרי הזמנה (יעד: <5%)
- **Emergency bookings** - אחוז הזמנות חירום (יעד: 15-20%)
- **Business packages** - אחוז לקוחות שקונים חבילה (יעד: 20% מהעסקים)

---

## 💾 בסיום העבודה - חובה לשמור!

### בסוף הפיתוח:
1. **שמור את כל הקבצי MD** ב-`/docs/delivery_upgrade/`
2. **עדכן CLAUDE.md** עם section חדש:
   ```markdown
   ## Section 32: Delivery CSM (Category-Specific Module)
   - Provider edit block: delivery_settings_block.dart
   - Client booking block: delivery_block.dart
   - AI integration: Gemini (vehicle recommendation)
   - 🆕 Express Reorder feature
   - 🆕 Scheduled delivery (unique!)
   - 🆕 Phone masking
   - 🆕 Courier rules system
   - All files in /docs/delivery_upgrade/
   ```
3. **תעדכן userMemories** שעבר Delivery CSM הוטמע
4. **רץ flutter analyze** ווודא 0 issues
5. **תכין סיכום מלא** של מה נעשה (כמו עם הדברה)

---

## 🤖 Built for AnySkill - Claude Code Implementation

המסמך הזה הוא הבסיס. עבור פרטים מלאים על כל מסך - ראה את שני הקבצים הנוספים. בהצלחה! 🛵

**זכור: לא למחוק כלום! רק להוסיף 2 בלוקים חדשים במיקומים המדויקים שצוינו למעלה.**
